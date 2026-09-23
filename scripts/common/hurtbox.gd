class_name Hurtbox
extends Area2D
## Receives damage. Attach to whatever should be able to get hit
## (player, boss). Emits `damaged` so health components stay decoupled
## from whoever dealt the hit.

signal damaged(amount: float, source: Node)

## While true, hits are ignored (dash i-frames, death). A flag rather than
## toggling `monitorable`, so it can be flipped safely mid-physics-callback.
var invulnerable := false

func apply_damage(amount: float, source: Node = null) -> void:
	if invulnerable:
		return
	damaged.emit(amount, source)
