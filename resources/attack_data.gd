class_name AttackData
extends Resource
## Data-driven description of a single boss attack. To add a melee attack,
## create a new .tres of this type and list it in TreantBoss.MELEE_ATTACK_PATHS.

@export var id: StringName = &""
@export var display_name: String = ""

## Seconds of telegraph/wind-up before the attack becomes dangerous.
@export var telegraph_time: float = 0.5
## Seconds the hitbox/hazard is actually active.
@export var active_time: float = 0.3
## Seconds of recovery after the attack before another can start.
@export var recovery_time: float = 0.4

@export var damage: float = 10.0

## Melee hitbox rectangle, relative to the boss's AttackOrigin (chest
## height): x points toward the player, +y is down, the ground is at y = 90.
## This is what makes each melee attack dodge differently. Unused by the
## projectile throw.
@export var hitbox_size := Vector2(200, 90)
@export var hitbox_offset := Vector2(80, 0)

## Placeholder colour used to represent this attack's telegraph/hitbox
## until real VFX/animations exist.
@export var debug_color: Color = Color.ORANGE
