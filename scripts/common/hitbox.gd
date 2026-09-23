class_name Hitbox
extends Area2D
## Deals damage to whatever Hurtbox it overlaps while active.
## Attacks enable/disable this for their `active_time` window instead of
## each attack script rolling its own overlap-checking logic.

@export var damage: float = 10.0

func _ready() -> void:
	monitoring = false
	area_entered.connect(_on_area_entered)

## Deferred because these are often called from inside a hit callback
## (e.g. the killing blow), where Godot forbids changing `monitoring`.
func activate(with_damage: float = -1.0) -> void:
	if with_damage >= 0.0:
		damage = with_damage
	set_deferred("monitoring", true)

func deactivate() -> void:
	set_deferred("monitoring", false)

func _on_area_entered(area: Area2D) -> void:
	if area is Hurtbox:
		area.apply_damage(damage, self)
