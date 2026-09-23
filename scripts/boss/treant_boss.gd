class_name TreantBoss
extends CharacterBody2D
## Owns the state chart and exposes small, reusable "how to perform a beat"
## helpers (perform_attack, perform_horizontal_attack, perform_projectile_throw,
## move_to_position, channel_roots) that the attack scripts under
## scripts/boss/attacks/ call. The state chart only decides WHEN something
## happens; these helpers and the attack scripts decide HOW.

const ATTACK_RESOURCE_PATHS := [
	"res://resources/attacks/arm_swipe.tres",
	"res://resources/attacks/overhead_strike.tres",
	"res://resources/attacks/ground_smash.tres",
	"res://resources/attacks/root_arm_attack.tres",
	"res://resources/attacks/projectile_throw.tres",
]

const PLAYER_HURTBOX_MASK := 1 << 1 # physics layer 2, "player_hurtbox"
const ARENA_HALF_EXTENT := 420.0

const MELEE_APPROACH_RANGE := 130.0 # CDD: boss "stays relatively close to the player"
const MELEE_APPROACH_SPEED := 340.0

const LONG_RANGE_RETREAT_DISTANCE := 260.0
const LONG_RANGE_BASE_RANGE := 160.0
const LONG_RANGE_RANGE_STEP := 110.0
const LONG_RANGE_LOCAL_Y := 65.0 # low sweep near the ground so a jump clears it
const LONG_RANGE_DAMAGE := 12.0
const LIMB_THICKNESS := 24.0
const LIMB_TELEGRAPH_TIME := 0.6
const LIMB_ACTIVE_TIME := 0.35
const LIMB_RECOVERY_TIME := 0.4

const PROJECTILE_SPEED := 300.0
const PROJECTILE_RANGE := 900.0
const PROJECTILE_RADIUS := 14.0

const ROOT_DAMAGE := 15.0
const ROOT_SIZE := Vector2(70, 170) # taller than the player can jump: must reposition
const ROOT_MIN_SPACING := 160.0
const ROOT_CHANNEL_TIME := 1.3
const ROOT_ACTIVE_TIME := 1.4
const ROOT_RECOVERY_TIME := 0.6
const ROOT_COOLDOWN_CYCLES := 1 # long-range sequences to sit out after a root attack

const ENRAGE_MULTIPLIER := 1.1 # CDD: +10% attack speed, +10% attack damage
const ENRAGE_VFX_SCALE := 1.3

const CORRUPTION_COLOR := Color(0.45, 0.15, 0.5, 0.8)
const CRIMSON := Color(0.95, 0.1, 0.15, 0.9)
const ENRAGED_BODY_COLOR := Color(0.85, 0.15, 0.15)
const CHANNEL_COLOR := Color(0.6, 0.3, 0.95)
const CLEANSED_COLOR := Color(0.65, 0.95, 0.55)

## Placeholder art has "TREANT" baked into the texture, so mirroring it
## shows the text backwards. Turn on once real directional art exists.
@export var flip_sprite_with_facing := false

@onready var state_chart: StateChart = $StateChart
@onready var health: Health = $Health
@onready var detection: DetectionArea = $DetectionArea
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var body_sprite: Sprite2D = $BodySprite
@onready var enrage_glow: Sprite2D = $EnrageGlow
@onready var corruption_particles: CPUParticles2D = $CorruptionParticles
@onready var attack_origin: Marker2D = $AttackOrigin
@onready var melee_hitbox: Hitbox = $AttackOrigin/MeleeHitbox
@onready var melee_indicator: Sprite2D = $AttackOrigin/MeleeIndicator
@onready var limb_indicator: Sprite2D = $AttackOrigin/LimbIndicator
@onready var limb_hitbox: Hitbox = $AttackOrigin/LimbHitbox
@onready var state_label: Label = $StateLabel
@onready var health_bar: Node2D = $HealthBar
@onready var health_bar_fill: ColorRect = $HealthBar/BarFill

var attack_pool: Array[AttackData] = []
var player: Node2D = null
var attack_speed_mult := 1.0
var attack_damage_mult := 1.0
var vfx_scale := 1.0
var facing := -1.0
## Set once the Defeated state is entered. Attack coroutines check it after
## every wait so a dead boss never swings again.
var is_defeated := false

var _base_body_color: Color
var _idle_tween: Tween
var _glow_tween: Tween
var _root_cooldown := 0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	for path in ATTACK_RESOURCE_PATHS:
		attack_pool.append(load(path) as AttackData)

	_base_body_color = body_sprite.modulate
	limb_indicator.visible = false
	melee_indicator.visible = false
	enrage_glow.visible = false
	corruption_particles.color = CORRUPTION_COLOR
	_update_health_bar(1.0)

	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	detection.player_detected.connect(_on_player_detected)
	hurtbox.damaged.connect(_on_hurtbox_damaged)

	var idle: StateChartState = $StateChart/Boss/Idle
	var melee: StateChartState = $StateChart/Boss/Aggro/AttackPattern/Melee
	var long_range: StateChartState = $StateChart/Boss/Aggro/AttackPattern/LongRange
	var root_attack: StateChartState = $StateChart/Boss/Aggro/AttackPattern/RootAttack
	var enraged: StateChartState = $StateChart/Boss/Aggro/EnrageTrack/Enraged
	var defeated: StateChartState = $StateChart/Boss/Defeated

	idle.state_entered.connect(_on_idle_entered)
	idle.state_exited.connect(_on_idle_exited)
	melee.state_entered.connect(func(): MeleeCombo.execute(self))
	long_range.state_entered.connect(func(): LongRangeAttack.execute(self))
	long_range.state_exited.connect(_on_long_range_exited)
	root_attack.state_entered.connect(_on_root_attack_entered)
	enraged.state_entered.connect(_on_enraged_entered)
	defeated.state_entered.connect(_on_defeated_entered)

	for s in [idle, melee, long_range, root_attack, defeated]:
		s.state_entered.connect(_update_state_label.bind(s.name))

	state_chart.set_expression_property("hp_percent", 1.0)
	state_chart.set_expression_property("root_ready", true)

## --- state chart glue -----------------------------------------------------

func _on_player_detected(detected: Node2D) -> void:
	player = detected
	state_chart.send_event("player_detected")

func _on_hurtbox_damaged(amount: float, source: Node) -> void:
	health.apply_damage(amount, source)
	FloatingText.spawn(get_parent(), str(roundi(amount)), global_position + Vector2(_rng.randf_range(-30, 30), -215), Color(1.0, 0.9, 0.3))

func _on_health_changed(_current: float, _max_hp: float, percent: float) -> void:
	state_chart.set_expression_property("hp_percent", percent)
	state_chart.send_event("health_changed")
	_update_health_bar(percent)

func _update_health_bar(percent: float) -> void:
	const FULL_WIDTH := 156.0
	health_bar_fill.size.x = FULL_WIDTH * clampf(percent, 0.0, 1.0)
	if percent > 0.5:
		health_bar_fill.color = Color(0.25, 0.8, 0.25)
	elif percent > 0.1:
		health_bar_fill.color = Color(0.9, 0.75, 0.15)
	else:
		health_bar_fill.color = Color(0.85, 0.15, 0.15)

func _on_died() -> void:
	state_chart.send_event("died")

## Root attack cooldown. `root_ready` feeds the ToRootAttack guard, which is
## evaluated when a long-range sequence finishes, before LongRange exits.
## So: root attack -> next long-range goes to Melee (and counts down on
## exit) -> the one after that may root attack again.
func _on_root_attack_entered() -> void:
	_root_cooldown = ROOT_COOLDOWN_CYCLES
	state_chart.set_expression_property("root_ready", false)
	RootAttackExecutor.execute(self)

func _on_long_range_exited() -> void:
	if _root_cooldown <= 0:
		return
	_root_cooldown -= 1
	if _root_cooldown == 0:
		state_chart.set_expression_property("root_ready", true)

## CDD Idle: "remains stationary, plays an idle animation". Placeholder
## animation is a slow breathing squash on the body.
func _on_idle_entered() -> void:
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(body_sprite, "scale", Vector2(1.0, 1.04), 0.9).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(body_sprite, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)

func _on_idle_exited() -> void:
	if _idle_tween:
		_idle_tween.kill()
	body_sprite.scale = Vector2.ONE

## CDD Phase 3: red glow, more crimson particles, stronger attack VFX,
## +10% attack speed and damage. Same attack patterns, just harder.
func _on_enraged_entered() -> void:
	attack_speed_mult = ENRAGE_MULTIPLIER
	attack_damage_mult = ENRAGE_MULTIPLIER
	vfx_scale = ENRAGE_VFX_SCALE
	_base_body_color = ENRAGED_BODY_COLOR
	body_sprite.modulate = _base_body_color

	enrage_glow.visible = true
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(enrage_glow, "modulate:a", 0.6, 0.35)
	_glow_tween.tween_property(enrage_glow, "modulate:a", 0.2, 0.35)

	corruption_particles.color = CRIMSON
	corruption_particles.amount = 70
	corruption_particles.initial_velocity_max = 110.0

func _on_defeated_entered() -> void:
	is_defeated = true
	hurtbox.invulnerable = true
	detection.set_deferred("monitoring", false)
	melee_hitbox.deactivate()
	limb_hitbox.deactivate()
	melee_indicator.visible = false
	limb_indicator.visible = false
	_play_cleansing_sequence()

## CDD: "DEFEATED -> TREE ROOT CLEANSING SEQUENCE". Placeholder: the
## corruption drains out of the body and particles, and turns green.
func _play_cleansing_sequence() -> void:
	if _glow_tween:
		_glow_tween.kill()
	enrage_glow.visible = false
	health_bar.visible = false
	corruption_particles.color = CLEANSED_COLOR
	corruption_particles.gravity = Vector2(0, -60)
	var tween := create_tween()
	tween.tween_property(body_sprite, "modulate", CLEANSED_COLOR, 2.0)
	await tween.finished
	state_label.text = "Cleansed - press R to fight again"
	corruption_particles.emitting = false

func _update_state_label(state_name: String) -> void:
	state_label.text = state_name

## --- reusable attack beats, called by scripts/boss/attacks/*.gd -----------

func face_player() -> void:
	if not is_instance_valid(player):
		return
	var dx := player.global_position.x - global_position.x
	if dx != 0.0:
		facing = signf(dx)
	attack_origin.scale.x = facing
	if flip_sprite_with_facing:
		body_sprite.flip_h = facing > 0.0

func approach_player_if_needed() -> void:
	if not is_instance_valid(player):
		return
	var dx := player.global_position.x - global_position.x
	if absf(dx) <= MELEE_APPROACH_RANGE:
		face_player()
		return
	var target_x := player.global_position.x - signf(dx) * MELEE_APPROACH_RANGE
	target_x = clampf(target_x, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)
	var duration := maxf(absf(target_x - global_position.x) / MELEE_APPROACH_SPEED, 0.1)
	await move_to_position(Vector2(target_x, global_position.y), duration)

func move_away_from_player(distance: float, duration: float = 1.0) -> void:
	var dir := -facing
	if is_instance_valid(player):
		var dx := global_position.x - player.global_position.x
		if dx != 0.0:
			dir = signf(dx)
	var target := global_position + Vector2(dir * distance, 0.0)
	target.x = clampf(target.x, -ARENA_HALF_EXTENT, ARENA_HALF_EXTENT)
	await move_to_position(target, duration)

func move_to_position(target: Vector2, duration: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(self, "global_position", target, duration / attack_speed_mult)
	await tween.finished
	face_player()

## One melee swing: telegraph (body + arrow tinted in the attack's colour),
## active hitbox, recovery. Timings come from the AttackData resource.
func perform_attack(atk: AttackData) -> void:
	await approach_player_if_needed()
	if is_defeated:
		return
	state_label.text = "MELEE: " + atk.display_name
	body_sprite.modulate = atk.debug_color
	melee_indicator.visible = true
	melee_indicator.modulate = atk.debug_color
	melee_indicator.scale = Vector2(0.4, 0.4) * vfx_scale
	melee_indicator.position = Vector2(60, 0)
	await get_tree().create_timer(atk.telegraph_time / attack_speed_mult).timeout
	if is_defeated:
		return

	melee_indicator.scale = Vector2.ONE * vfx_scale
	melee_indicator.position = Vector2(100, 0)
	melee_hitbox.activate(atk.damage * attack_damage_mult)
	await get_tree().create_timer(atk.active_time / attack_speed_mult).timeout
	melee_hitbox.deactivate()
	melee_indicator.visible = false
	if is_defeated:
		return
	body_sprite.modulate = _base_body_color
	await get_tree().create_timer(atk.recovery_time / attack_speed_mult).timeout

## The spiked bulb is ranged, so it's thrown from wherever the boss stands
## rather than after walking up to the player.
func perform_projectile_throw(atk: AttackData) -> void:
	face_player()
	state_label.text = "THROW: " + atk.display_name
	body_sprite.modulate = atk.debug_color
	await get_tree().create_timer(atk.telegraph_time / attack_speed_mult).timeout
	if is_defeated:
		return
	body_sprite.modulate = _base_body_color
	_spawn_projectile(atk)
	await get_tree().create_timer(atk.recovery_time / attack_speed_mult).timeout

## One sweep of the long-range limb. The telegraph draws the full reach as
## a thin line along the ground, so the player can see how far it will go.
## Positions are NOT multiplied by `facing`: the parent AttackOrigin is
## already mirrored via its scale.
func perform_horizontal_attack(range_length: float) -> void:
	face_player()
	state_label.text = "LONG-RANGE (reach %d)" % roundi(range_length)
	var tex_size := limb_indicator.texture.get_size()
	var center := Vector2(range_length / 2.0, LONG_RANGE_LOCAL_Y)

	limb_indicator.visible = true
	limb_indicator.position = center
	limb_indicator.scale = Vector2(range_length, 4.0) / tex_size
	limb_indicator.modulate = Color(0.95, 0.85, 0.2, 0.85)
	await get_tree().create_timer(LIMB_TELEGRAPH_TIME / attack_speed_mult).timeout
	if is_defeated:
		return

	limb_indicator.scale = Vector2(range_length, LIMB_THICKNESS * vfx_scale) / tex_size
	limb_indicator.modulate = Color(0.9, 0.2, 0.1)
	var shape := (limb_hitbox.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	shape.size = Vector2(range_length, LIMB_THICKNESS)
	limb_hitbox.position = center
	limb_hitbox.activate(LONG_RANGE_DAMAGE * attack_damage_mult)
	await get_tree().create_timer(LIMB_ACTIVE_TIME / attack_speed_mult).timeout

	limb_hitbox.deactivate()
	limb_indicator.visible = false
	if is_defeated:
		return
	await get_tree().create_timer(LIMB_RECOVERY_TIME / attack_speed_mult).timeout

func _spawn_projectile(atk: AttackData) -> void:
	var bulb := SpikedBulb.new()
	bulb.name = "SpikedBulb"
	bulb.damage = atk.damage * attack_damage_mult
	bulb.collision_layer = 0
	bulb.collision_mask = PLAYER_HURTBOX_MASK

	var poly := Polygon2D.new()
	poly.polygon = _star_points(PROJECTILE_RADIUS * 1.4 * vfx_scale, PROJECTILE_RADIUS * 0.7 * vfx_scale, 8)
	poly.color = atk.debug_color
	bulb.add_child(poly)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = PROJECTILE_RADIUS
	collision.shape = shape
	bulb.add_child(collision)

	get_parent().add_child(bulb)
	bulb.global_position = attack_origin.global_position

	var travel_time := PROJECTILE_RANGE / PROJECTILE_SPEED
	var tween := bulb.create_tween().set_parallel(true)
	tween.tween_property(bulb, "global_position", bulb.global_position + Vector2(facing * PROJECTILE_RANGE, 0.0), travel_time)
	tween.tween_property(bulb, "rotation", TAU * 3.0 * facing, travel_time)
	tween.chain().tween_callback(bulb.queue_free)

func pick_corner() -> Vector2:
	var corners := get_tree().get_nodes_in_group("boss_arena_corner")
	if corners.is_empty():
		return Vector2(ARENA_HALF_EXTENT * facing, global_position.y)
	var corner: Node2D = corners[_rng.randi_range(0, corners.size() - 1)]
	return corner.global_position

## CDD Phase 2: channel while the ground shows warnings, then three large
## spikey roots erupt. One always targets where the player is standing, so
## the answer is to move, not to jump in place.
func channel_roots() -> void:
	state_label.text = "ROOT ATTACK: channeling"
	var positions := _pick_root_positions(3)
	var warnings: Array[Node2D] = []
	for pos in positions:
		warnings.append(_spawn_root_warning(pos))

	var channel_tween := create_tween().set_loops()
	channel_tween.tween_property(body_sprite, "modulate", CHANNEL_COLOR, 0.25)
	channel_tween.tween_property(body_sprite, "modulate", _base_body_color, 0.25)
	await get_tree().create_timer(ROOT_CHANNEL_TIME / attack_speed_mult).timeout
	channel_tween.kill()
	for w in warnings:
		w.queue_free()
	if is_defeated:
		return
	body_sprite.modulate = _base_body_color

	var roots: Array[Hitbox] = []
	for pos in positions:
		roots.append(_spawn_root_spike(pos))
	state_label.text = "ROOT ATTACK: roots up"
	await get_tree().create_timer(ROOT_ACTIVE_TIME / attack_speed_mult).timeout
	for root in roots:
		_retract_root(root)
	if is_defeated:
		return
	state_label.text = "ROOT ATTACK: recovering"
	await get_tree().create_timer(ROOT_RECOVERY_TIME / attack_speed_mult).timeout

func _pick_root_positions(count: int) -> Array[Vector2]:
	var limit := ARENA_HALF_EXTENT - ROOT_SIZE.x
	var ground_y := global_position.y
	var positions: Array[Vector2] = []
	if is_instance_valid(player):
		positions.append(Vector2(clampf(player.global_position.x, -limit, limit), ground_y))
	var attempts := 0
	while positions.size() < count and attempts < 100:
		attempts += 1
		var candidate := Vector2(_rng.randf_range(-limit, limit), ground_y)
		var far_enough := true
		for existing in positions:
			if absf(existing.x - candidate.x) < ROOT_MIN_SPACING:
				far_enough = false
				break
		if far_enough:
			positions.append(candidate)
	return positions

## A pulsing red crack on the ground plus a faint "ghost" of the spike,
## so the player sees exactly where each root will come up.
func _spawn_root_warning(pos: Vector2) -> Node2D:
	var warning := Node2D.new()
	var crack := Polygon2D.new()
	crack.polygon = PackedVector2Array([Vector2(-45, -3), Vector2(45, -3), Vector2(45, 8), Vector2(-45, 8)])
	crack.color = Color(1.0, 0.25, 0.1, 0.95)
	warning.add_child(crack)
	var ghost := Polygon2D.new()
	ghost.polygon = _spike_points()
	ghost.color = Color(1.0, 0.3, 0.15, 0.25)
	warning.add_child(ghost)

	get_parent().add_child(warning)
	warning.global_position = pos
	var pulse := warning.create_tween().set_loops()
	pulse.tween_property(warning, "modulate:a", 0.35, 0.18)
	pulse.tween_property(warning, "modulate:a", 1.0, 0.18)
	return warning

func _spawn_root_spike(pos: Vector2) -> Hitbox:
	var root := Hitbox.new()
	root.name = "RootSpike"
	root.collision_layer = 0
	root.collision_mask = PLAYER_HURTBOX_MASK

	var poly := Polygon2D.new()
	poly.polygon = _spike_points()
	poly.color = Color(0.55, 0.22, 0.1)
	root.add_child(poly)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(ROOT_SIZE.x * 0.7, ROOT_SIZE.y)
	collision.shape = shape
	collision.position = Vector2(0, -ROOT_SIZE.y / 2.0)
	root.add_child(collision)

	get_parent().add_child(root)
	root.global_position = pos
	root.scale = Vector2(1.0, 0.05)
	root.create_tween().tween_property(root, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK)
	root.activate(ROOT_DAMAGE * attack_damage_mult)
	return root

func _retract_root(root: Hitbox) -> void:
	if not is_instance_valid(root):
		return
	root.deactivate()
	var tween := root.create_tween()
	tween.tween_property(root, "scale:y", 0.0, 0.15)
	tween.tween_callback(root.queue_free)

func _spike_points() -> PackedVector2Array:
	var w := ROOT_SIZE.x / 2.0
	var h := ROOT_SIZE.y
	return PackedVector2Array([
		Vector2(-w, 0), Vector2(-w * 0.35, -h * 0.45), Vector2(-w * 0.75, -h * 0.5),
		Vector2(0, -h),
		Vector2(w * 0.75, -h * 0.5), Vector2(w * 0.35, -h * 0.45), Vector2(w, 0),
	])

func _star_points(outer: float, inner: float, spikes: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in spikes * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := TAU * i / (spikes * 2)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
