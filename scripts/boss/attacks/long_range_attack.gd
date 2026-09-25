class_name LongRangeAttack
extends Node
## How the Pattern/LongRange state plays out (CDD Phase 1): back away, then
## 3 horizontal limb sweeps, each reaching further across the arena, so the
## player can't just stand still. The answer is to jump over them.
##
## The chart runs Retreat --arrived--> NextSweep, then loops
## NextSweep -> Sweep (Telegraph -> Active -> Recover) -> NextSweep. Once all
## sweeps are done, NextSweep's guarded transitions go to RootAttack if the
## Roots region is in Ready, otherwise back to Melee. Timings come from
## long_range_sweep.tres. Handlers are connected in treant_boss.tscn.

## CDD: the limb reaches "across the arena", each sweep further than the
## last. Fractions of the arena width, one per sweep.
const REACH_FRACTIONS := [0.25, 0.4, 0.55]
const RETREAT_DISTANCE := 260.0
const SWEEP_LOCAL_Y := 65.0 # low sweep near the ground so a jump clears it
const LIMB_THICKNESS := 24.0

@onready var boss: TreantBoss = owner

var _sweep := -1
var _reach := 0.0

func _on_long_range_entered() -> void:
	_sweep = -1
	boss.load_attack_timing(boss.long_range_attack)

func _on_retreat_entered() -> void:
	boss.show_label("LONG-RANGE: backing off")
	boss.retreat_from_player(RETREAT_DISTANCE)

## Same pattern as Melee/NextMove: set the property, then send "next".
func _on_next_sweep_entered() -> void:
	_sweep += 1
	boss.state_chart.set_expression_property("sweeps_done", _sweep >= REACH_FRACTIONS.size())
	boss.state_chart.send_event("next")

## A thin yellow line along the ground shows exactly how far the sweep will
## reach. Positions are NOT multiplied by `facing`: the parent AttackOrigin
## is already mirrored via its scale.
func _on_telegraph_entered() -> void:
	boss.face_player()
	_reach = _reach_for(_sweep)
	boss.show_label("LONG-RANGE %d/%d" % [_sweep + 1, REACH_FRACTIONS.size()])
	var indicator := boss.limb_indicator
	indicator.visible = true
	indicator.position = Vector2(_reach / 2.0, SWEEP_LOCAL_Y)
	indicator.scale = Vector2(_reach, 4.0) / indicator.texture.get_size()
	indicator.modulate = Color(0.95, 0.85, 0.2, 0.85)

func _on_active_entered() -> void:
	var atk := boss.long_range_attack
	var indicator := boss.limb_indicator
	indicator.scale = Vector2(_reach, LIMB_THICKNESS) / indicator.texture.get_size()
	indicator.modulate = boss.active_color(atk.debug_color)
	var shape := (boss.limb_hitbox.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	shape.size = Vector2(_reach, LIMB_THICKNESS)
	boss.limb_hitbox.position = Vector2(_reach / 2.0, SWEEP_LOCAL_Y)
	boss.limb_hitbox.activate(atk.damage * boss.attack_damage_mult)

func _on_active_exited() -> void:
	boss.limb_hitbox.deactivate()
	boss.limb_indicator.visible = false

## Cut off at the arena edge the boss is facing.
func _reach_for(sweep: int) -> float:
	var reach: float = (boss.arena_max_x - boss.arena_min_x) * REACH_FRACTIONS[sweep]
	var edge := boss.arena_max_x if boss.facing > 0.0 else boss.arena_min_x
	return minf(reach, absf(edge - boss.global_position.x))
