extends Camera2D
## Follows the player horizontally and leans toward the boss so both stay
## in frame. Camera2D's own limit_left/limit_right stop it from showing
## anything past the ends of the platform.

@export var target_path: NodePath
@export var focus_path: NodePath
## 0 = centred on the target, 1 = centred on the focus.
@export_range(0.0, 1.0) var focus_weight := 0.35

@onready var _target: Node2D = get_node_or_null(target_path)
@onready var _focus: Node2D = get_node_or_null(focus_path)

func _ready() -> void:
	_follow()
	reset_smoothing()

func _process(_delta: float) -> void:
	_follow()

func _follow() -> void:
	if not is_instance_valid(_target):
		return
	var x := _target.global_position.x
	if is_instance_valid(_focus):
		x = lerpf(x, _focus.global_position.x, focus_weight)
	global_position.x = x
