class_name Health
extends Node
## Single source of truth for an actor's HP. Everything else (state chart
## guards, VFX, UI) reacts to its signals instead of tracking HP itself.
## Shared by TreantBoss and PlayerController.

signal health_changed(current: float, max: float, percent: float)
signal died()

@export var max_health: float = 100.0

var current_health: float = 0.0

func _ready() -> void:
	current_health = max_health

func apply_damage(amount: float, _source: Node = null) -> void:
	if current_health <= 0.0:
		return
	current_health = maxf(current_health - amount, 0.0)
	health_changed.emit(current_health, max_health, percent())
	if current_health <= 0.0:
		died.emit()

func percent() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health
