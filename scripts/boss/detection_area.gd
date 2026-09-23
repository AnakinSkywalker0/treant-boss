class_name DetectionArea
extends Area2D
## Fires once when a member of the "player" group first enters range.
## Kept separate from TreantBoss so the detection radius/shape can be
## tuned in the editor without touching boss logic.

signal player_detected(player: Node2D)

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_detected.emit(body)
