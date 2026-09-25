class_name RootAttackExecutor
extends RefCounted
## Unlocked below 50% HP (see the ToRootAttack guard on the LongRange state).
## Moves to the nearer arena corner, channels, then three spikey roots emerge
## at shifting ground positions before the boss returns to normal combat.

static func execute(boss: TreantBoss) -> void:
	var corner := boss.pick_corner()
	var run_time := maxf(absf(corner.x - boss.global_position.x) / TreantBoss.CORNER_RUN_SPEED, 0.2)
	await boss.move_to_position(corner, run_time)
	if boss.is_defeated:
		return
	await boss.channel_roots()
	if not boss.is_defeated:
		boss.state_chart.send_event("root_finished")
