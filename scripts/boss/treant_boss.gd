class_name TreantBoss
extends CharacterBody2D
## The Treant's body. The StateChart child decides WHAT the boss does and
## WHEN: every beat of every attack (approach, telegraph, active, recover),
## its timing, the phases, the root cooldown, stagger, victory and defeat
## are states, and the chart moves between them on events, delays and
## guards (see docs/HOW_IT_WORKS.md §4).
##
## This script and the behaviour nodes under Behaviours/ only say HOW each
## state looks and acts. Their handlers are connected to the states'
## state_entered / state_exited signals in treant_boss.tscn. They report
## facts back to the chart as events ("arrived", "parried", "player_died")
## and keep its expression properties (hp_percent, speed, attack timings)
## up to date.
##
## Because every beat is a state, leaving a state (the boss dies, gets
## staggered, or the player dies) cancels its pending timers, and the exit
## handlers switch off hitboxes and stop movement. Nothing has to keep
## checking an "is the boss dead?" flag.

const MELEE_ATTACK_PATHS := [
	"res://resources/attacks/arm_swipe.tres",
	"res://resources/attacks/overhead_strike.tres",
	"res://resources/attacks/ground_smash.tres",
	"res://resources/attacks/root_arm_attack.tres",
]
const PROJECTILE_ATTACK_PATH := "res://resources/attacks/projectile_throw.tres"
const LONG_RANGE_ATTACK_PATH := "res://resources/attacks/long_range_sweep.tres"
const ROOT_ATTACK_PATH := "res://resources/attacks/root_spikes.tres"

const PLAYER_HURTBOX_MASK := 1 << 1 # physics layer 2, "player_hurtbox"
const ARENA_FALLBACK_HALF_EXTENT := 420.0 # only used if the level has no corner markers

const MELEE_APPROACH_RANGE := 130.0 # CDD: boss "stays relatively close to the player"
const MELEE_APPROACH_SPEED := 340.0
const RETREAT_SPEED := 260.0
const CORNER_RUN_SPEED := 450.0

const ENRAGE_MULTIPLIER := 1.1 # CDD: +10% attack speed, +10% attack damage
const ENRAGE_VFX_SCALE := 1.3

const CORRUPTION_COLOR := Color(0.45, 0.15, 0.5, 0.8)
const CRIMSON := Color(0.95, 0.1, 0.15, 0.9)
const ENRAGED_BODY_COLOR := Color(0.85, 0.15, 0.15)
const STAGGER_COLOR := Color(0.75, 0.9, 1.0)
const CLEANSED_COLOR := Color(0.65, 0.95, 0.55)

const HEALTH_BAR_WIDTH := 156.0
const PHASE1_BAR_COLOR := Color(0.25, 0.8, 0.25)
const PHASE2_BAR_COLOR := Color(0.9, 0.75, 0.15)
const ENRAGED_BAR_COLOR := Color(0.85, 0.15, 0.15)

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

var melee_attacks: Array[AttackData] = []
var projectile_attack: AttackData
var long_range_attack: AttackData
var root_attack: AttackData
var player: Node2D = null
var attack_speed_mult := 1.0
var attack_damage_mult := 1.0
var vfx_scale := 1.0
var facing := -1.0
## The body's resting colour. Attacks tint the body and restore this.
var base_body_color: Color
## Horizontal limits of the fight, read from the level's corner markers.
var arena_min_x := -ARENA_FALLBACK_HALF_EXTENT
var arena_max_x := ARENA_FALLBACK_HALF_EXTENT
var rng := RandomNumberGenerator.new()

var _idle_tween: Tween
var _glow_tween: Tween
var _move_tween: Tween
var _stagger_tween: Tween

func _ready() -> void:
	rng.randomize()
	_read_arena_bounds()
	for path in MELEE_ATTACK_PATHS:
		melee_attacks.append(load(path) as AttackData)
	projectile_attack = load(PROJECTILE_ATTACK_PATH) as AttackData
	long_range_attack = load(LONG_RANGE_ATTACK_PATH) as AttackData
	root_attack = load(ROOT_ATTACK_PATH) as AttackData

	base_body_color = body_sprite.modulate
	limb_indicator.visible = false
	melee_indicator.visible = false
	enrage_glow.visible = false
	corruption_particles.color = CORRUPTION_COLOR
	_update_health_bar(1.0)

	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	detection.player_detected.connect(_on_player_detected)
	hurtbox.damaged.connect(_on_hurtbox_damaged)

## --- facts reported to the state chart --------------------------------------

func _on_player_detected(detected: Node2D) -> void:
	player = detected
	if detected is PlayerController and not detected.health.died.is_connected(_on_player_died):
		detected.health.died.connect(_on_player_died)
	state_chart.send_event("player_detected")

func _on_player_died() -> void:
	state_chart.send_event("player_died")

## Connected to each thrown SpikedBulb's `parried` signal.
func on_bulb_parried() -> void:
	state_chart.send_event("parried")

func _on_hurtbox_damaged(amount: float, source: Node) -> void:
	health.apply_damage(amount, source)
	FloatingText.spawn(get_parent(), str(roundi(amount)), global_position + Vector2(rng.randf_range(-30, 30), -215), Color(1.0, 0.9, 0.3))

## hp_percent drives the Phase and Roots regions' guarded transitions
## directly, so there's no "health changed" event to send.
func _on_health_changed(_current: float, _max_hp: float, percent: float) -> void:
	_update_health_bar(percent)
	state_chart.set_expression_property("hp_percent", percent)

func _on_died() -> void:
	state_chart.send_event("died")

## Publishes an attack's timings for the delayed transitions between its
## Telegraph -> Active -> Recover states ("telegraph_time / speed", ...).
func load_attack_timing(atk: AttackData) -> void:
	state_chart.set_expression_property("telegraph_time", atk.telegraph_time)
	state_chart.set_expression_property("active_time", atk.active_time)
	state_chart.set_expression_property("recovery_time", atk.recovery_time)

## --- Idle / Victory / Defeated -----------------------------------------------

## CDD Idle: "remains stationary, plays an idle animation". Placeholder
## animation is a slow breathing squash on the body.
func _on_idle_entered() -> void:
	show_label("Idle")
	_start_breathing()

func _on_idle_exited() -> void:
	_stop_breathing()
	create_tween().tween_property(detection, "modulate:a", 0.0, 0.4)

## The player died. Leaving Aggro exits all three of its regions, so
## whatever attack was running is cancelled by its exit handlers.
func _on_victory_entered() -> void:
	show_label("Victorious - press R to retry")
	face_player()
	_start_breathing()

func _on_defeated_entered() -> void:
	hurtbox.invulnerable = true
	detection.set_deferred("monitoring", false)
	_play_cleansing_sequence()

## CDD: "DEFEATED -> TREE ROOT CLEANSING SEQUENCE". Placeholder: the
## corruption drains out of the body and particles, and turns green.
func _play_cleansing_sequence() -> void:
	show_label("Defeated")
	if _glow_tween:
		_glow_tween.kill()
	enrage_glow.visible = false
	health_bar.visible = false
	corruption_particles.color = CLEANSED_COLOR
	corruption_particles.gravity = Vector2(0, -60)
	var tween := create_tween()
	tween.tween_property(body_sprite, "modulate", CLEANSED_COLOR, 2.0)
	await tween.finished
	show_label("Cleansed - press R to fight again")
	corruption_particles.emitting = false

func _start_breathing() -> void:
	_stop_breathing()
	_idle_tween = create_tween().set_loops()
	_idle_tween.tween_property(body_sprite, "scale", Vector2(1.0, 1.04), 0.9).set_trans(Tween.TRANS_SINE)
	_idle_tween.tween_property(body_sprite, "scale", Vector2.ONE, 0.9).set_trans(Tween.TRANS_SINE)

func _stop_breathing() -> void:
	if _idle_tween:
		_idle_tween.kill()
	body_sprite.scale = Vector2.ONE

## --- Phase region: Phase1 -> Phase2 -> Enraged --------------------------------

func _on_phase1_entered() -> void:
	health_bar_fill.color = PHASE1_BAR_COLOR

## CDD Phase 2 (< 50% HP): the root attack unlocks (the Roots region's
## Locked -> Ready transition uses the same guard) and old attacks continue.
func _on_phase2_entered() -> void:
	health_bar_fill.color = PHASE2_BAR_COLOR
	FloatingText.spawn(get_parent(), "PHASE 2", global_position + Vector2(0, -250), PHASE2_BAR_COLOR, 26)

## CDD Phase 3 (<= 10% HP): red glow, more crimson particles, stronger
## attack VFX, +10% attack speed and damage. Same attack patterns, just
## harder. `speed` divides every attack delay in the chart.
func _on_enraged_entered() -> void:
	attack_speed_mult = ENRAGE_MULTIPLIER
	attack_damage_mult = ENRAGE_MULTIPLIER
	vfx_scale = ENRAGE_VFX_SCALE
	state_chart.set_expression_property("speed", ENRAGE_MULTIPLIER)
	base_body_color = ENRAGED_BODY_COLOR
	body_sprite.modulate = base_body_color
	health_bar_fill.color = ENRAGED_BAR_COLOR
	FloatingText.spawn(get_parent(), "ENRAGED!", global_position + Vector2(0, -250), CRIMSON, 28)

	enrage_glow.visible = true
	_glow_tween = create_tween().set_loops()
	_glow_tween.tween_property(enrage_glow, "modulate:a", 0.6, 0.35)
	_glow_tween.tween_property(enrage_glow, "modulate:a", 0.2, 0.35)

	corruption_particles.color = CRIMSON
	corruption_particles.amount = 70
	corruption_particles.initial_velocity_max = 110.0

## --- Pattern region -------------------------------------------------------------

## Connected to state_exited of Melee, LongRange and RootAttack. However an
## attack ends (finished, staggered, player died, boss died), nothing is
## left live: no hitbox, no telegraph, no half-finished walk.
func _on_attack_state_exited() -> void:
	stop_moving()
	melee_hitbox.deactivate()
	limb_hitbox.deactivate()
	melee_indicator.visible = false
	limb_indicator.visible = false
	restore_body_color()

## CDD: the spiked bulb "can be parried". A parry staggers the boss: the
## chart's Pattern/Staggered state, which holds no attacks and returns to
## Melee after its delayed transition. Entering it cancels the attack that
## was running.
func _on_staggered_entered() -> void:
	show_label("STAGGERED")
	FloatingText.spawn(get_parent(), "STAGGERED!", global_position + Vector2(0, -250), STAGGER_COLOR, 26)
	body_sprite.modulate = STAGGER_COLOR
	_stagger_tween = create_tween().set_loops()
	_stagger_tween.tween_property(body_sprite, "rotation", 0.06, 0.08)
	_stagger_tween.tween_property(body_sprite, "rotation", -0.06, 0.08)

func _on_staggered_exited() -> void:
	if _stagger_tween:
		_stagger_tween.kill()
	body_sprite.rotation = 0.0
	restore_body_color()

## --- helpers for the behaviour nodes ----------------------------------------

func show_label(text: String) -> void:
	state_label.text = text

func restore_body_color() -> void:
	body_sprite.modulate = base_body_color

## Enraged attacks flash hotter (CDD: "stronger attack VFX"). Indicator
## sizes stay put because they always match the real hitbox.
func active_color(base: Color) -> Color:
	return base.lerp(Color.WHITE, 0.35) if vfx_scale > 1.0 else base

func face_player() -> void:
	if not is_instance_valid(player):
		return
	var dx := player.global_position.x - global_position.x
	if dx != 0.0:
		facing = signf(dx)
	attack_origin.scale.x = facing
	if flip_sprite_with_facing:
		body_sprite.flip_h = facing > 0.0

## Melee Swing/Approach: walk to MELEE_APPROACH_RANGE from the player.
func approach_player() -> void:
	if not is_instance_valid(player):
		_arrive()
		return
	var dx := player.global_position.x - global_position.x
	if absf(dx) <= MELEE_APPROACH_RANGE:
		_arrive()
		return
	move_to_x(player.global_position.x - signf(dx) * MELEE_APPROACH_RANGE, MELEE_APPROACH_SPEED)

## LongRange/Retreat: back away from the player.
func retreat_from_player(distance: float) -> void:
	var dir := -facing
	if is_instance_valid(player):
		var dx := global_position.x - player.global_position.x
		if dx != 0.0:
			dir = signf(dx)
	move_to_x(global_position.x + dir * distance, RETREAT_SPEED)

## RootAttack/RunToCorner. CDD Phase 2: "moves to a corner of the arena".
## The nearer edge, so the run stays short and on screen.
func run_to_nearer_corner() -> void:
	var to_left := absf(global_position.x - arena_min_x)
	var to_right := absf(global_position.x - arena_max_x)
	move_to_x(arena_min_x if to_left <= to_right else arena_max_x, CORNER_RUN_SPEED)

## Walks to `target_x` (clamped to the arena), then sends "arrived". The
## movement states wait for that event. Their parent attack state calls
## stop_moving() on exit, so an interrupted walk just stops.
func move_to_x(target_x: float, move_speed: float) -> void:
	stop_moving()
	target_x = clampf(target_x, arena_min_x, arena_max_x)
	var duration := absf(target_x - global_position.x) / (move_speed * attack_speed_mult)
	if duration < 0.02:
		_arrive()
		return
	_move_tween = create_tween()
	_move_tween.tween_property(self, "global_position:x", target_x, duration)
	_move_tween.tween_callback(_arrive)

func stop_moving() -> void:
	if _move_tween:
		_move_tween.kill()
		_move_tween = null

func _arrive() -> void:
	face_player()
	state_chart.send_event("arrived")

## The level defines the fight's extent with "boss_arena_corner" markers,
## so the arena can be resized without touching this script.
func _read_arena_bounds() -> void:
	var corners := get_tree().get_nodes_in_group("boss_arena_corner")
	if corners.size() < 2:
		return
	arena_min_x = INF
	arena_max_x = -INF
	for corner: Node2D in corners:
		arena_min_x = minf(arena_min_x, corner.global_position.x)
		arena_max_x = maxf(arena_max_x, corner.global_position.x)

func _update_health_bar(percent: float) -> void:
	health_bar_fill.size.x = HEALTH_BAR_WIDTH * clampf(percent, 0.0, 1.0)
