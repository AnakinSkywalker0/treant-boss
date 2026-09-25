class_name LongRangeAttack
extends RefCounted
## Backs away, then performs 3 consecutive horizontal limb sweeps, each
## reaching further across the arena, so the player can't just stand still.

static func execute(boss: TreantBoss) -> void:
	await boss.move_away_from_player(TreantBoss.LONG_RANGE_RETREAT_DISTANCE)
	for sweep in TreantBoss.LONG_RANGE_REACH_FRACTIONS.size():
		if boss.is_defeated:
			return
		await boss.perform_horizontal_attack(sweep)
	if not boss.is_defeated:
		boss.state_chart.send_event("ranged_finished")
