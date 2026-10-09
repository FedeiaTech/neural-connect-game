class_name BoundaryView
extends MembraneView
## Play area outline (SDD 5.3): white, thicker than dendrites, drawn as a breathing membrane
## with a soft glow (see MembraneView). It listens to neuron_blocked: a contact near the outline
## starts a local ripple there and is remembered as the last contact point.

const LINE_WIDTH := 6.0

var _last_contact := Vector2.INF
var _boss_look := false


func _init() -> void:
	_amplitude = VisualTuning.BOUNDARY_AMPLITUDE
	_line_width = LINE_WIDTH
	_color = Palette.BOUNDARY


## Boss look (T8.6): warm white membrane, stronger glow and a livelier undulation. Takes effect at
## the next setup().
func set_boss_look(boss: bool) -> void:
	_color = Palette.BOSS_MEMBRANE if boss else Palette.BOUNDARY
	_glow_scale = 1.9 if boss else 1.0
	_amplitude = VisualTuning.BOUNDARY_AMPLITUDE * (1.8 if boss else 1.0)
	_boss_look = boss


func is_boss_look() -> bool:
	return _boss_look


func setup(model: PuzzleModel) -> void:
	_last_contact = Vector2.INF
	var lethal: Dictionary[int, bool] = {}
	for i in model.get_play_area().size():
		if model.is_lethal_edge(i):
			lethal[i] = true
	_setup_membrane(model.get_play_area(), model, lethal)


## Last neuron stop position reported by the model, or Vector2.INF if none.
func get_last_contact() -> Vector2:
	return _last_contact


func _on_neuron_blocked(id: int, contact: Vector2) -> void:
	_last_contact = contact
	super(id, contact)
