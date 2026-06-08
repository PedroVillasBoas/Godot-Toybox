extends Control

@onready var mat: ShaderMaterial = material as ShaderMaterial

func _ready() -> void:
	shatter(Vector2(0.5, 0.5))

func shatter(impact_uv: Vector2, duration: float = 1.0) -> void:
	mat.set_shader_parameter("impact_point", impact_uv)
	mat.set_shader_parameter("break_progress", 0.0)

	var t := create_tween()
	t.tween_method(
		func(v: float): mat.set_shader_parameter("break_progress", v),
		0.0,
		1.0,
		duration,
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
