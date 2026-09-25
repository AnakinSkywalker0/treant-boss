class_name RootAttack
extends Node
## How the Pattern/RootAttack state plays out (CDD Phase 2). The boss runs
## to the nearer arena corner and channels while the ground shows warnings,
## then three large spikey roots erupt. One always targets where the player
## is standing, so the answer is to move, not to jump in place.
##
## Chart: RunToCorner --arrived--> Channel --telegraph--> RootsUp
## --active--> Recover --recovery--> Melee. Timings come from
## root_spikes.tres. Whether a root attack may start at all is the Roots
## region's job (Locked / Ready / CoolingDown). Handlers are connected in
## treant_boss.tscn.

const ROOT_COUNT := 3
const ROOT_SIZE := Vector2(70, 170) # taller than the player can jump: must reposition
const ROOT_MIN_SPACING := 160.0
const ROOT_SPREAD := 450.0 # the extra roots land within this distance of the player

@onready var boss: TreantBoss = owner

var _positions: Array[Vector2] = []
var _warnings: Array[Node2D] = []
var _roots: Array[Hitbox] = []
var _pulse: Tween

func _on_root_attack_entered() -> void:
	boss.load_attack_timing(boss.root_attack)

func _on_run_to_corner_entered() -> void:
	boss.show_label("ROOT ATTACK: to the corner")
	boss.run_to_nearer_corner()

## A pulsing red crack on the ground plus a faint "ghost" of the spike, so
## the player sees exactly where each root will come up.
func _on_channel_entered() -> void:
	boss.show_label("ROOT ATTACK: channeling")
	_positions = _pick_positions()
	for pos in _positions:
		_warnings.append(_spawn_warning(pos))
	_pulse = boss.create_tween().set_loops()
	_pulse.tween_property(boss.body_sprite, "modulate", boss.root_attack.debug_color, 0.25)
	_pulse.tween_property(boss.body_sprite, "modulate", boss.base_body_color, 0.25)

func _on_channel_exited() -> void:
	if _pulse:
		_pulse.kill()
	for warning in _warnings:
		if is_instance_valid(warning):
			warning.queue_free()
	_warnings.clear()
	boss.restore_body_color()

func _on_roots_up_entered() -> void:
	boss.show_label("ROOT ATTACK: roots up")
	for pos in _positions:
		_roots.append(_spawn_spike(pos))

func _on_roots_up_exited() -> void:
	for root in _roots:
		_retract(root)
	_roots.clear()

func _on_recover_entered() -> void:
	boss.show_label("ROOT ATTACK: recovering")

func _pick_positions() -> Array[Vector2]:
	var lo := boss.arena_min_x + ROOT_SIZE.x / 2.0
	var hi := boss.arena_max_x - ROOT_SIZE.x / 2.0
	var ground_y := boss.global_position.y
	var center := boss.global_position.x
	var positions: Array[Vector2] = []
	if is_instance_valid(boss.player):
		center = clampf(boss.player.global_position.x, lo, hi)
		positions.append(Vector2(center, ground_y))
	var spread_lo := maxf(lo, center - ROOT_SPREAD)
	var spread_hi := minf(hi, center + ROOT_SPREAD)
	var attempts := 0
	while positions.size() < ROOT_COUNT and attempts < 100:
		attempts += 1
		var candidate := Vector2(boss.rng.randf_range(spread_lo, spread_hi), ground_y)
		var far_enough := true
		for existing in positions:
			if absf(existing.x - candidate.x) < ROOT_MIN_SPACING:
				far_enough = false
				break
		if far_enough:
			positions.append(candidate)
	return positions

func _spawn_warning(pos: Vector2) -> Node2D:
	var warning := Node2D.new()
	var crack := Polygon2D.new()
	crack.polygon = PackedVector2Array([Vector2(-45, -3), Vector2(45, -3), Vector2(45, 8), Vector2(-45, 8)])
	crack.color = Color(1.0, 0.25, 0.1, 0.95)
	warning.add_child(crack)
	var ghost := Polygon2D.new()
	ghost.polygon = _spike_points()
	ghost.color = Color(1.0, 0.3, 0.15, 0.25)
	warning.add_child(ghost)

	boss.get_parent().add_child(warning)
	warning.global_position = pos
	var pulse := warning.create_tween().set_loops()
	pulse.tween_property(warning, "modulate:a", 0.35, 0.18)
	pulse.tween_property(warning, "modulate:a", 1.0, 0.18)
	return warning

func _spawn_spike(pos: Vector2) -> Hitbox:
	var root := Hitbox.new()
	root.name = "RootSpike"
	root.collision_layer = 0
	root.collision_mask = TreantBoss.PLAYER_HURTBOX_MASK

	var poly := Polygon2D.new()
	poly.polygon = _spike_points()
	poly.color = Color(0.55, 0.22, 0.1)
	root.add_child(poly)

	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(ROOT_SIZE.x * 0.7, ROOT_SIZE.y)
	collision.shape = shape
	collision.position = Vector2(0, -ROOT_SIZE.y / 2.0)
	root.add_child(collision)

	boss.get_parent().add_child(root)
	root.global_position = pos
	root.scale = Vector2(1.0, 0.05)
	root.create_tween().tween_property(root, "scale:y", 1.0, 0.12).set_trans(Tween.TRANS_BACK)
	root.activate(boss.root_attack.damage * boss.attack_damage_mult)
	return root

func _retract(root: Hitbox) -> void:
	if not is_instance_valid(root):
		return
	root.deactivate()
	var tween := root.create_tween()
	tween.tween_property(root, "scale:y", 0.0, 0.15)
	tween.tween_callback(root.queue_free)

func _spike_points() -> PackedVector2Array:
	var w := ROOT_SIZE.x / 2.0
	var h := ROOT_SIZE.y
	return PackedVector2Array([
		Vector2(-w, 0), Vector2(-w * 0.35, -h * 0.45), Vector2(-w * 0.75, -h * 0.5),
		Vector2(0, -h),
		Vector2(w * 0.75, -h * 0.5), Vector2(w * 0.35, -h * 0.45), Vector2(w, 0),
	])
