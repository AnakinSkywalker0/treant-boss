class_name SpikedBulb
extends Area2D
## The Treant's thrown projectile (CDD Phase 1: "throws a spiked bulb at
## the player that can be parried"). It travels in a straight line; the
## tween that moves it is owned by the bulb itself so it dies with it.
## Counters: parry (be mid-swing when it arrives) or dash through it.

var damage: float = 8.0

func _ready() -> void:
	area_entered.connect(_on_area_entered)

func _on_area_entered(area: Area2D) -> void:
	if not area is Hurtbox or area.invulnerable:
		return
	var target := area.get_parent()
	if target is PlayerController and target.is_parrying():
		FloatingText.spawn(get_parent(), "PARRY!", global_position + Vector2(0, -30), Color(0.4, 0.9, 1.0), 26)
		queue_free()
		return
	area.apply_damage(damage, self)
	queue_free()
