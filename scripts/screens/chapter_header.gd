class_name ChapterHeader
extends Control
## Illustrated header of one chapter in MissionSelect (SDD 5.5): a procedural cell-field backdrop
## (assets/shaders/chapter_header.gdshader) with its own seed and accent per chapter, and the
## chapter title and subtitle over it. Built in code; decorative only (ignores the mouse).

const HeaderShader := preload("res://assets/shaders/chapter_header.gdshader")
const HEIGHT := 150.0
## Chapter accents cycle through the strict palette: cold white, white, red, light green.
const ACCENTS: Array[Color] = [Palette.NEURON_GLOW, Palette.NEURON, Palette.NEURON_FIXED_GLOW, Palette.TENSION]

var _backdrop := ColorRect.new()
var _title := Label.new()
var _subtitle := Label.new()
var _material := ShaderMaterial.new()


## Distinct, stable seed per chapter id.
static func seed_for(chapter_id: int) -> float:
	return 1.0 + fposmod(float(chapter_id) * 0.618034, 1.0) * 9.0


static func accent_for(chapter_id: int) -> Color:
	return ACCENTS[posmod(chapter_id - 1, ACCENTS.size())]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, HEIGHT)
	_material.shader = HeaderShader
	_backdrop.material = _material
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.offset_left = 40.0
	column.add_theme_constant_override(&"separation", 2)
	add_child(column)
	_title.add_theme_font_size_override(&"font_size", 40)
	_title.add_theme_constant_override(&"outline_size", 10)
	_title.add_theme_color_override(&"font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
	column.add_child(_title)
	_subtitle.add_theme_font_size_override(&"font_size", 24)
	_subtitle.add_theme_color_override(&"font_color", Color(0.85, 0.92, 1.0, 0.65))
	column.add_child(_subtitle)
	resized.connect(_on_resized)


func setup(chapter_id: int, title: String, subtitle: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_material.set_shader_parameter(&"seed", seed_for(chapter_id))
	_material.set_shader_parameter(&"accent", accent_for(chapter_id))
	_material.set_shader_parameter(&"motion", VisualTuning.motion_scale())


func get_title_text() -> String:
	return _title.text


func get_backdrop() -> ColorRect:
	return _backdrop


func _on_resized() -> void:
	_material.set_shader_parameter(&"rect_size", size)
