class_name MeleeCombo
extends Node
## How the Pattern/Melee state plays out (CDD Phase 1): "a random sequence
## of 3-6 melee attacks", drawn from the boss's melee attacks. The spiked
## bulb is listed separately in the CDD, so it doesn't count toward the
## 3-6: some of the time, one throw is slotted into the sequence at a random
## point.
##
## The state chart runs the sequence. Melee/NextMove publishes the next
## attack and sends "next", and its guarded transitions branch to Swing
## (Approach -> Telegraph -> Active -> Recover), Throw (Windup -> Release)
## or, once the combo is done, LongRange. Both branches loop back to
## NextMove. This node only rolls the plan and makes each state look and hit
## right. Its handlers are connected to those states in treant_boss.tscn.

const PROJECTILE_CHANCE := 0.5
const BULB_SPEED := 300.0
const BULB_RANGE := 900.0
const BULB_RADIUS := 14.0

@onready var boss: TreantBoss = owner

var _plan: Array[AttackData] = []
var _attack: AttackData

func _on_melee_entered() -> void:
	_plan.clear()
	for i in boss.rng.randi_range(3, 6):
		_plan.append(boss.melee_attacks[boss.rng.randi_range(0, boss.melee_attacks.size() - 1)])
	if boss.rng.randf() < PROJECTILE_CHANCE:
		_plan.insert(boss.rng.randi_range(0, _plan.size()), boss.projectile_attack)

## Sets every property the guards read before sending "next". Transitions
## triggered by an event only check their guards when that event arrives,
## so they never see a half-updated set of properties.
func _on_next_move_entered() -> void:
	var chart := boss.state_chart
	chart.set_expression_property("combo_done", _plan.is_empty())
	if not _plan.is_empty():
		_attack = _plan.pop_front()
		chart.set_expression_property("next_is_throw", _attack == boss.projectile_attack)
		boss.load_attack_timing(_attack)
	chart.send_event("next")

## --- Swing: Approach -> Telegraph -> Active -> Recover ------------------------

func _on_approach_entered() -> void:
	boss.show_label("MELEE: " + _attack.display_name)
	boss.approach_player()

## The body tints to the attack's colour and a faint box shows exactly
## where the swing will land.
func _on_telegraph_entered() -> void:
	boss.face_player()
	boss.body_sprite.modulate = _attack.debug_color
	_set_melee_area(_attack)
	boss.melee_indicator.visible = true
	boss.melee_indicator.modulate = Color(_attack.debug_color, 0.3)

func _on_active_entered() -> void:
	boss.melee_indicator.modulate = boss.active_color(Color(_attack.debug_color, 0.8))
	boss.melee_hitbox.activate(_attack.damage * boss.attack_damage_mult)

func _on_active_exited() -> void:
	boss.melee_hitbox.deactivate()
	boss.melee_indicator.visible = false

func _on_recover_entered() -> void:
	boss.restore_body_color()

## Sizes the melee hitbox and its indicator to this attack's rectangle, so
## the telegraph shows exactly where the swing will land.
func _set_melee_area(atk: AttackData) -> void:
	var collision := boss.melee_hitbox.get_node("CollisionShape2D") as CollisionShape2D
	(collision.shape as RectangleShape2D).size = atk.hitbox_size
	collision.position = atk.hitbox_offset
	boss.melee_indicator.position = atk.hitbox_offset
	boss.melee_indicator.scale = atk.hitbox_size / boss.melee_indicator.texture.get_size()

## --- Throw: Windup -> Release ---------------------------------------------------

## The spiked bulb is ranged, so it's thrown from wherever the boss stands
## rather than after walking up to the player.
func _on_windup_entered() -> void:
	boss.face_player()
	boss.show_label("THROW: " + _attack.display_name)
	boss.body_sprite.modulate = _attack.debug_color

func _on_release_entered() -> void:
	boss.restore_body_color()
	_spawn_bulb(_attack)

## The bulb lives in the arena, not under the boss, so it keeps flying
## whatever state the boss moves on to. A parry reaches the chart as the
## "parried" event.
func _spawn_bulb(atk: AttackData) -> void:
	var bulb := SpikedBulb.new()
	bulb.name = "SpikedBulb"
	bulb.damage = atk.damage * boss.attack_damage_mult
	bulb.collision_layer = 0
	bulb.collision_mask = TreantBoss.PLAYER_HURTBOX_MASK
	bulb.parried.connect(boss.on_bulb_parried)

	var poly := Polygon2D.new()
	poly.polygon = _star_points(BULB_RADIUS * 1.4 * boss.vfx_scale, BULB_RADIUS * 0.7 * boss.vfx_scale, 8)
	poly.color = atk.debug_color
	bulb.add_child(poly)

	var collision := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = BULB_RADIUS
	collision.shape = shape
	bulb.add_child(collision)

	boss.get_parent().add_child(bulb)
	bulb.global_position = boss.attack_origin.global_position

	var travel_time := BULB_RANGE / BULB_SPEED
	var tween := bulb.create_tween().set_parallel(true)
	tween.tween_property(bulb, "global_position", bulb.global_position + Vector2(boss.facing * BULB_RANGE, 0.0), travel_time)
	tween.tween_property(bulb, "rotation", TAU * 3.0 * boss.facing, travel_time)
	tween.chain().tween_callback(bulb.queue_free)

func _star_points(outer: float, inner: float, spikes: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in spikes * 2:
		var radius := outer if i % 2 == 0 else inner
		var angle := TAU * i / (spikes * 2)
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	return points
