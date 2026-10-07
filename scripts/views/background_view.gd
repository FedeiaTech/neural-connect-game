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


func _ready() -> void:
	_spore_speed = _spores.speed_scale
	_fit_to_viewport()
	get_viewport().size_changed.connect(_fit_to_viewport)
	GameState.settings_changed.connect(_apply_motion)
	_apply_motion()


func get_spores() -> CPUParticles2D:
	return _spores


func get_vignette() -> ColorRect:
	return _vignette


func _fit_to_viewport() -> void:
	var size := get_viewport().get_visible_rect().size
	_spores.position = size * 0.5
	_spores.emission_rect_extents = size * 0.5


func _apply_motion() -> void:
	_spores.speed_scale = _spore_speed if VisualTuning.is_motion_enabled() else 0.0
