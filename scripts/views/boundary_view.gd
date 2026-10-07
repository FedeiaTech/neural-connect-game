class_name BoundaryView
extends MembraneView
## Play area outline (SDD 5.3): white, thicker than dendrites, drawn as a breathing membrane
## with a soft glow (see MembraneView). It listens to neuron_blocked: a contact near the outline
## starts a local ripple there and is remembered as the last contact point.

const LINE_WIDTH := 6.0

var _last_contact := Vector2.INF


func _init() -> void:
	_amplitude = VisualTuning.BOUNDARY_AMPLITUDE
	_line_width = LINE_WIDTH
	_color = Palette.BOUNDARY


func setup(model: PuzzleModel) -> void:
	_last_contact = Vector2.INF
	_setup_membrane(model.get_play_area(), model)


## Last neuron stop position reported by the model, or Vector2.INF if none.
func get_last_contact() -> Vector2:
	return _last_contact


func _on_neuron_blocked(id: int, contact: Vector2) -> void:
	_last_contact = contact
	super(id, contact)
