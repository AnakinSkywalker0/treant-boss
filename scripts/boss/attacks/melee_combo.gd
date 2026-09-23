class_name MeleeCombo
extends RefCounted
## Phase 1 default behaviour: a random 3-6 attack sequence drawn from the
## boss's attack_pool. Adding a new melee attack = adding a new AttackData
## .tres to res://resources/attacks/ and listing it in TreantBoss's pool;
## nothing here needs to change.

static func execute(boss: TreantBoss) -> void:
	var count := boss._rng.randi_range(3, 6)
	for i in count:
		if boss.is_defeated or not is_instance_valid(boss.player):
			return
		var atk: AttackData = boss.attack_pool[boss._rng.randi_range(0, boss.attack_pool.size() - 1)]
		if atk.id == &"projectile_throw":
			await boss.perform_projectile_throw(atk)
		else:
			await boss.perform_attack(atk)
	if not boss.is_defeated:
		boss.state_chart.send_event("combo_finished")
