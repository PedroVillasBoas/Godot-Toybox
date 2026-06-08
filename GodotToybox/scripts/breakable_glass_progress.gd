extends Node

@export var slider: HSlider
@export var glass_rect: ColorRect

var _mat: ShaderMaterial


func _ready() -> void:
	_mat = glass_rect.material as ShaderMaterial
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.001
	slider.value_changed.connect(_on_slider_changed)


func _on_slider_changed(value: float) -> void:
	_mat.set_shader_parameter("break_progress", value)
