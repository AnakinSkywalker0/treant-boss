class_name AttackData
extends Resource
## Data-driven description of a single boss attack.
## New attacks are added by creating a new .tres of this type — no code changes.

@export var id: StringName = &""
@export var display_name: String = ""

## Seconds of telegraph/wind-up before the attack becomes dangerous.
@export var telegraph_time: float = 0.5
## Seconds the hitbox/hazard is actually active.
@export var active_time: float = 0.3
## Seconds of recovery after the attack before another can start.
@export var recovery_time: float = 0.4

@export var damage: float = 10.0
@export var range: float = 2.0

## Placeholder colour used to represent this attack's telegraph/hitbox
## until real VFX/animations exist.
@export var debug_color: Color = Color.ORANGE
