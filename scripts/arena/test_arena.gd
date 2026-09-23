extends Node2D
## Playtest harness for the boss fight. R reloads the scene to retry.

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
