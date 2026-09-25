class_name PlayerController
extends CharacterBody2D
## Minimal placeholder player for a side-view platformer boss arena:
## move, jump, dash/evade, a basic attack that can parry, and health/death.
## Only exists to exercise the boss's behaviour during playtesting.

const SPEED := 260.0
const JUMP_VELOCITY := -480.0
const DASH_SPEED := 620.0
const DASH_TIME := 0.18
const GRAVITY := 1400.0
const HIT_IFRAMES_TIME := 0.5 # brief invulnerability after taking a hit, so attacks can't chain

const ATTACK_DAMAGE := 12.0
const ATTACK_TELEGRAPH_TIME := 0.08
const ATTACK_ACTIVE_TIME := 0.12
const ATTACK_COOLDOWN_TIME := 0.25
const ATTACK_OFFSET := 42.0
## attack_sword draws its slash about 0.25s in. Speed the animation up so the
## slash lands halfway through the hitbox's active window.
const ATTACK_ANIM_SLASH_TIME := 0.25
const ATTACK_ANIM_SPEED := ATTACK_ANIM_SLASH_TIME / (ATTACK_TELEGRAPH_TIME + ATTACK_ACTIVE_TIME * 0.5)

## Animations in assets/player/player_pk.skel (Spine). The rig faces right.
const ANIM_IDLE := "idle"
const ANIM_RUN := "run"
const ANIM_JUMP_START := "jump_start"
const ANIM_JUMP_LOOP := "jumping"
const ANIM_FALL := "fall"
const ANIM_LAND := "landing"
const ANIM_DASH := "dash"
const ANIM_ATTACK := "attack_sword"
const LOOPING_ANIMS := [ANIM_IDLE, ANIM_RUN, ANIM_JUMP_LOOP]

@onready var body_sprite: SpineSprite = $BodySprite
@onready var attack_hitbox: Hitbox = $AttackOrigin/AttackHitbox
@onready var attack_origin: Marker2D = $AttackOrigin
@onready var hurtbox: Hurtbox = $Hurtbox
@onready var health: Health = $Health
@onready var health_label: Label = $HealthLabel

var _dash_timer := 0.0
var _dash_direction := 0.0
var _hit_iframes := 0.0
var facing := 1.0
var _attacking := false
var _parry_window := false
var _dead := false
var _anim := ""
var _sprite_scale := 1.0

func _ready() -> void:
	_sprite_scale = absf(body_sprite.scale.x)
	health.health_changed.connect(_on_health_changed)
	health.died.connect(_on_died)
	_update_health_label(health.max_health, health.max_health)
	_apply_facing()

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if _dead:
		velocity.x = 0.0
		move_and_slide()
		_update_animation()
		return

	_hit_iframes = maxf(_hit_iframes - delta, 0.0)

	if _dash_timer > 0.0:
		_dash_timer -= delta
		velocity.x = _dash_direction * DASH_SPEED
	else:
		var input_dir := Input.get_action_strength("move_right") - Input.get_action_strength("move_left")
		velocity.x = input_dir * SPEED

		if input_dir != 0.0:
			facing = signf(input_dir)
			_apply_facing()

		if Input.is_action_just_pressed("jump") and is_on_floor():
			velocity.y = JUMP_VELOCITY

		if Input.is_action_just_pressed("dash") and input_dir != 0.0:
			_dash_direction = signf(input_dir)
			_dash_timer = DASH_TIME

		if Input.is_action_just_pressed("attack") and not _attacking:
			_do_attack()

	_update_invulnerability()
	move_and_slide()
	_update_animation()

## Runs after move_and_slide() so is_on_floor() reflects this frame.
## Only switches when the choice changes, so looping animations keep playing.
func _update_animation() -> void:
	var anim := _choose_animation()
	if anim != _anim:
		_play_animation(anim)

func _choose_animation() -> String:
	if _dash_timer > 0.0:
		return ANIM_DASH
	if _attacking:
		return ANIM_ATTACK
	if not is_on_floor():
		return ANIM_JUMP_START if velocity.y < 0.0 else ANIM_FALL
	if velocity.x != 0.0:
		return ANIM_RUN
	# Touching down while standing still plays the landing once, then idles.
	if _anim == ANIM_JUMP_START or _anim == ANIM_FALL:
		return ANIM_LAND
	if _anim == ANIM_LAND and not body_sprite.get_animation_state().get_track(0).is_complete():
		return ANIM_LAND
	return ANIM_IDLE

## Always restarts `anim`, even if it's already playing (back-to-back attacks).
func _play_animation(anim: String) -> SpineTrackEntry:
	_anim = anim
	var state := body_sprite.get_animation_state()
	var entry := state.set_animation(anim, anim in LOOPING_ANIMS, 0)
	if anim == ANIM_JUMP_START:
		state.add_animation(ANIM_JUMP_LOOP, 0.0, true, 0)
	return entry

## Single source of truth for "can I be hit right now?". Dashing (the CDD's
## "evade") and post-hit i-frames both make the hurtbox ignore damage.
## Dashing shows as see-through, post-hit i-frames as a flicker.
## Uses modulate, not self_modulate: SpineSprite draws each slot as a child
## mesh, and self_modulate doesn't reach children.
func _update_invulnerability() -> void:
	var dashing := _dash_timer > 0.0
	hurtbox.invulnerable = _dead or dashing or _hit_iframes > 0.0
	if dashing:
		body_sprite.modulate.a = 0.45
	elif _hit_iframes > 0.0:
		body_sprite.modulate.a = 0.3 if int(_hit_iframes * 20.0) % 2 == 0 else 1.0
	else:
		body_sprite.modulate.a = 1.0

## Keeps every facing-dependent node (sprite, attack pivot) in sync with
## `facing` in one place. SpineSprite has no flip_h, so the rig is mirrored
## with a negative scale.
func _apply_facing() -> void:
	body_sprite.scale.x = _sprite_scale * facing
	attack_origin.scale.x = facing

## Swings should hit what you're aiming at. Since the boss is the only
## thing worth attacking, face it at the moment you commit to a swing
## rather than relying on whichever direction you last walked.
func _face_nearest_boss() -> void:
	var bosses := get_tree().get_nodes_in_group("boss")
	if bosses.is_empty():
		return
	var boss: Node2D = bosses[0]
	var dx := boss.global_position.x - global_position.x
	if dx != 0.0:
		facing = signf(dx)
		_apply_facing()

## True during the swing's wind-up and active frames. SpikedBulb checks this.
func is_parrying() -> bool:
	return _parry_window

func _do_attack() -> void:
	_attacking = true
	_parry_window = true
	_face_nearest_boss()
	_play_animation(ANIM_ATTACK).set_time_scale(ATTACK_ANIM_SPEED)
	attack_origin.position.x = ATTACK_OFFSET * facing
	# Keep alpha: _update_invulnerability() owns it.
	body_sprite.modulate = Color(1.3, 1.3, 1.3, body_sprite.modulate.a)
	await get_tree().create_timer(ATTACK_TELEGRAPH_TIME).timeout

	attack_hitbox.activate(ATTACK_DAMAGE)
	await get_tree().create_timer(ATTACK_ACTIVE_TIME).timeout

	attack_hitbox.deactivate()
	_parry_window = false
	if not _dead:
		body_sprite.modulate = Color(1, 1, 1, body_sprite.modulate.a)
	await get_tree().create_timer(ATTACK_COOLDOWN_TIME).timeout
	_attacking = false

func _on_hurtbox_damaged(amount: float, source: Node) -> void:
	health.apply_damage(amount, source)
	FloatingText.spawn(get_parent(), "-%d" % roundi(amount), global_position + Vector2(0, -125), Color(1.0, 0.4, 0.35))
	_hit_iframes = HIT_IFRAMES_TIME
	_update_invulnerability()

func _on_health_changed(current: float, max_hp: float, _percent: float) -> void:
	_update_health_label(current, max_hp)

func _update_health_label(current: float, max_hp: float) -> void:
	health_label.text = "HP %d/%d" % [int(current), int(max_hp)]

func _on_died() -> void:
	_dead = true
	_dash_timer = 0.0
	_hit_iframes = 0.0
	_update_invulnerability()
	attack_hitbox.deactivate()
	body_sprite.modulate = Color(0.35, 0.35, 0.35)
	health_label.text = "DEFEATED - press R"
