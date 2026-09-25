class_name MeleeCombo
extends RefCounted
## Phase 1 default behaviour. CDD: "a random sequence of 3-6 melee attacks",
## drawn from the boss's melee attacks. The spiked bulb is listed separately
## in the CDD, so it doesn't count toward the 3-6: some of the time, one
## throw is slotted into the sequence at a random point.

const PROJECTILE_CHANCE := 0.5

static func execute(boss: TreantBoss) -> void:
	var plan: Array[AttackData] = []
	for i in boss._rng.randi_range(3, 6):
		plan.append(boss.melee_attacks[boss._rng.randi_range(0, boss.melee_attacks.size() - 1)])
	if boss._rng.randf() < PROJECTILE_CHANCE:
		plan.insert(boss._rng.randi_range(0, plan.size()), boss.projectile_attack)

	for atk in plan:
		if boss.is_defeated or not is_instance_valid(boss.player):
			return
		if atk == boss.projectile_attack:
			await boss.perform_projectile_throw(atk)
		else:
			await boss.perform_attack(atk)
	if not boss.is_defeated:
		boss.state_chart.send_event("combo_finished")
