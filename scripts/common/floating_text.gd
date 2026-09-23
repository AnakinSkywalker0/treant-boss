class_name FloatingText
extends RefCounted
## Short-lived text that drifts up and fades out: damage numbers, "PARRY!".

const WIDTH := 120.0

static func spawn(parent: Node, text: String, at: Vector2, color: Color = Color.WHITE, font_size: int = 20) -> void:
	var label := Label.new()
	label.text = text
	label.z_index = 10
	label.custom_minimum_size = Vector2(WIDTH, 0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	parent.add_child(label)
	label.global_position = at - Vector2(WIDTH / 2.0, 0)

	var tween := label.create_tween().set_parallel(true)
	tween.tween_property(label, "global_position:y", at.y - 45.0, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.2)
	tween.chain().tween_callback(label.queue_free)
