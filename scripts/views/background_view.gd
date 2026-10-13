class_name BackgroundView
extends CanvasLayer
## Reusable background (SDD 5.4), drawn on a negative canvas layer behind the playfield and any
## menu: a pure black base with a barely visible radial depth lift, a few faint spores drifting
## slowly (CPUParticles2D with a procedural radial GradientTexture2D, no image files) and a soft
## vignette. It never competes with gameplay: low counts, low alpha, nothing on top of the
## playfield. Reduced motion freezes the spores in place.

@onready var _spores: CPUParticles2D = $Spores
@onready var _vignette: ColorRect = $Vignette

var _spore_speed := 1.0
var _boss_look := false


func _ready() -> void:
	_spore_speed = _spores.speed_scale
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	GameState.settings_changed.connect(_apply_motion)
	_apply_motion()


## Boss look (T8.6): a deeper, redder vignette. Visual only.
func set_boss_look(boss: bool) -> void:
	_boss_look = boss
	var material := _vignette.material as ShaderMaterial
	if material == null:
		return
	material.set_shader_parameter(&"tint", Color(0.28, 0.0, 0.02, 0.92) if boss else Color(0.0, 0.0, 0.0, 0.85))
	material.set_shader_parameter(&"inner", 0.22 if boss else 0.35)


func is_boss_look() -> bool:
	return _boss_look


func get_spores() -> CPUParticles2D:
	return _spores


func get_vignette() -> ColorRect:
	return _vignette


func _fit_to_viewport() -> void:
	var size := get_viewport().get_visible_rect().size
	_spores.position = size * 0.5
	_spores.emission_rect_extents = size * 0.5


func _apply_motion() -> void:
	# Low quality (Android, or the low memory setting) drops the spores entirely.
	var spores_on := not VisualTuning.is_low_quality()
	_spores.visible = spores_on
	_spores.emitting = spores_on
	_spores.speed_scale = _spore_speed if VisualTuning.is_motion_enabled() else 0.0
