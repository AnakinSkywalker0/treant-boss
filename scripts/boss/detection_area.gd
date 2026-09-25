class_name DetectionArea
extends Area2D
## The boss's aggro range (CDD Idle: "remains dormant until the player
## enters its detection range"). Fires `player_detected` when a member of
## the "player" group enters it, and draws the range on the ground so the
## player can see where the fight starts. Resize it by editing the child
## CollisionShape2D's rectangle; the drawing follows the shape.

signal player_detected(player: Node2D)

@export var show_range := true
@export var range_color := Color(0.95, 0.25, 0.15, 0.7)

@onready var _shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _draw() -> void:
	var rect := _shape.shape as RectangleShape2D
	if not show_range or rect == null:
		return
	var left := _shape.position.x - rect.size.x / 2.0
	var right := _shape.position.x + rect.size.x / 2.0
	draw_rect(Rect2(left, -4.0, right - left, 8.0), range_color)
	for x in [left, right]:
		draw_line(Vector2(x, 0.0), Vector2(x, -120.0), range_color, 5.0)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		player_detected.emit(body)
