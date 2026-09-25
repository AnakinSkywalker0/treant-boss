extends Node2D
## Playtest harness for the boss fight. R reloads the scene to retry.
## Debug keys jump the boss's HP to the start of a phase, so every phase can
## be checked without playing the whole fight: 2 = just under 50% (Phase 2,
## root attacks unlock), 3 = just under 10% (Phase 3, enraged). The state
## chart reacts to hp_percent on its own, before or after the fight starts.

const PHASE_2_HP_PERCENT := 0.49
const PHASE_3_HP_PERCENT := 0.09

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		match key:
			KEY_2:
				_set_boss_hp_percent(PHASE_2_HP_PERCENT)
			KEY_3:
				_set_boss_hp_percent(PHASE_3_HP_PERCENT)

## Only ever lowers HP, through Health.apply_damage, so the health bar, the
## chart's hp_percent and the phase transitions all update the normal way.
func _set_boss_hp_percent(target: float) -> void:
	var boss := get_tree().get_first_node_in_group("boss")
	if boss == null:
		return
	var health: Health = boss.get_node("Health")
	var damage := health.current_health - health.max_health * target
	if damage > 0.0:
		health.apply_damage(damage)
