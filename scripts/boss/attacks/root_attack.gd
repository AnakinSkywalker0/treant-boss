class_name RootAttackExecutor
extends RefCounted
## Unlocked below 50% HP (see the ToRootAttack guard on the LongRange state).
## Moves to an arena corner, channels, then three spikey roots emerge at
## shifting ground positions before the boss returns to normal combat.

static func execute(boss: TreantBoss) -> void:
	await boss.move_to_position(boss.pick_corner(), 1.2)
	if boss.is_defeated:
		return
	await boss.channel_roots()
	if not boss.is_defeated:
		boss.state_chart.send_event("root_finished")
