class_name LongRangeAttack
extends RefCounted
## Backs away, then performs 3 consecutive horizontal limb attacks with
## progressively longer range, forcing the player to keep repositioning.

static func execute(boss: TreantBoss) -> void:
	await boss.move_away_from_player(TreantBoss.LONG_RANGE_RETREAT_DISTANCE)
	for i in 3:
		if boss.is_defeated:
			return
		var range_length: float = TreantBoss.LONG_RANGE_BASE_RANGE + i * TreantBoss.LONG_RANGE_RANGE_STEP
		await boss.perform_horizontal_attack(range_length)
	if not boss.is_defeated:
		boss.state_chart.send_event("ranged_finished")
