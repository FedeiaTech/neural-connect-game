class_name ReceptorView
extends Node2D
## Receptor extras (T7.3, SDD 5.4), drawn additively around one receptor neuron (its soma is a
## cyan NeuronView): a soft pulsing halo ring at the reach limit (radius + reach), a searching
## soft bud that sways towards the nearest free candidate while links are missing, and one
## dot per required link above the soma (filled when linked). Reduced motion: still ring, no
## sway. Listens to link_formed / link_broken for its own receptor id. T8.2: while a toxic neuron
## contaminates it, the halo ring turns toxic yellow and beats faster.

const DOT_RADIUS := 4.5
const DOT_GAP := 14.0
const DOT_DISTANCE := 13.0
const BUD_LENGTH := 20.0
const BUD_WIDTH := 6.0
const HALO_PULSE_SPEED := 1.6

var receptor_id := PuzzleModel.NO_NEURON

var _model: PuzzleModel
var _radius := 28.0
var _reach := 0.0
var _required := 1
var _linked := 0
var _contaminated := false
var _time := 0.0
var _stub_angle := -PI * 0.5


func setup(id: int, model: PuzzleModel) -> void:
	receptor_id = id
	_model = model
	_radius = model.get_neuron_radius()
	_reach = model.get_receptor_reach(id)
	_required = model.get_required_links(id)
	_linked = model.get_link_count(id)
	position = model.get_neuron_position(id)
	_phase_offset()
	model.link_formed.connect(_on_link_changed)
	model.link_broken.connect(_on_link_changed)
	_contaminated = _contamination_in(model)
	model.contamination_formed.connect(_on_contamination_changed.unbind(2))
	model.contamination_cleared.connect(_on_contamination_changed.unbind(2))
	queue_redraw()


## Radius of the halo ring: a neuron whose center is inside it gets linked.
func get_halo_radius() -> float:
	return _radius + _reach


## One entry per required link: true when that slot is linked.
func get_dot_states() -> Array[bool]:
	var states: Array[bool] = []
	for i in _required:
		states.append(i < _linked)
	return states


## True while a toxic neuron is inside this receptor's reach (T8.2).
func is_contaminated() -> bool:
	return _contaminated


## True while links are missing (the stub is out, looking for a partner).
func is_searching() -> bool:
	return _linked < _required


func _phase_offset() -> void:
	_time = VisualTuning.phase_for(receptor_id + 31)


func _process(delta: float) -> void:
	_time += delta
	if is_searching() and _model != null:
		var target := _nearest_candidate_angle()
		if VisualTuning.is_motion_enabled():
			_stub_angle = lerp_angle(_stub_angle, target, minf(1.0, delta * 3.0))
		else:
			_stub_angle = target
	if VisualTuning.is_motion_enabled() or is_searching():
		queue_redraw()


func _draw() -> void:
	var motion := VisualTuning.motion_scale()
	var speed := HALO_PULSE_SPEED * (2.6 if _contaminated else 1.0)
	var pulse := 0.5 + 0.5 * sin(_time * speed) * motion
	var calm := 0.55 if not is_searching() and not _contaminated else 1.0
	var halo := get_halo_radius()
	var glow := Palette.TOXIC_GLOW if _contaminated else Palette.RECEPTOR_GLOW
	var line := Palette.TOXIC if _contaminated else Palette.RECEPTOR
	draw_arc(Vector2.ZERO, halo, 0.0, TAU, 96, Color(glow, (0.04 + 0.04 * pulse) * calm), 14.0, true)
	draw_arc(Vector2.ZERO, halo, 0.0, TAU, 96, Color(line, (0.16 + 0.14 * pulse) * calm), 2.0, true)
	if is_searching():
		_draw_stub(motion)
	_draw_dots()


## Soft convex bud (an ellipse, never a spike) swelling out of the soma towards _stub_angle,
## swaying and breathing with motion.
func _draw_stub(motion: float) -> void:
	var length := BUD_LENGTH * (0.9 + 0.1 * sin(_time * 2.3) * motion)
	var angle := _stub_angle + 0.12 * sin(_time * 1.7) * motion
	var direction := Vector2.from_angle(angle)
	var center := direction * (_radius * 0.9 + length * 0.4)
	var halo := _ellipse(center, angle, length * 0.9, BUD_WIDTH * 1.7)
	var bud := _ellipse(center, angle, length * 0.6, BUD_WIDTH)
	draw_colored_polygon(halo, Color(Palette.RECEPTOR_GLOW, 0.16))
	draw_colored_polygon(bud, Color(Palette.LINK, 0.6))
	draw_circle(center + direction * length * 0.25, 2.2, Color(Palette.LINK, 0.9), true, -1.0, true)


static func _ellipse(center: Vector2, angle: float, semi_long: float, semi_short: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in 20:
		var a := TAU * float(k) / 20.0
		points.append(center + Vector2(cos(a) * semi_long, sin(a) * semi_short).rotated(angle))
	return points


func _draw_dots() -> void:
	var states := get_dot_states()
	var start := -DOT_GAP * (states.size() - 1) * 0.5
	for i in states.size():
		var center := Vector2(start + DOT_GAP * i, -_radius - DOT_DISTANCE)
		if states[i]:
			draw_circle(center, DOT_RADIUS + 3.0, Color(Palette.RECEPTOR_GLOW, 0.3), true, -1.0, true)
			draw_circle(center, DOT_RADIUS, Palette.LINK, true, -1.0, true)
		else:
			draw_arc(center, DOT_RADIUS, 0.0, TAU, 20, Color(Palette.LINK, 0.75), 1.5, true)


## Direction (radians) to the nearest movable neuron not linked to this receptor.
func _nearest_candidate_angle() -> float:
	var best := INF
	var angle := _stub_angle
	var links := _model.get_links(receptor_id)
	for id in _model.get_neuron_ids():
		if _model.is_fixed(id) or _model.is_toxic(id) or links.has(id):
			continue
		var offset := _model.get_neuron_position(id) - position
		if offset.length() < best:
			best = offset.length()
			angle = offset.angle()
	return angle


func _contamination_in(model: PuzzleModel) -> bool:
	for pair in model.get_contamination_links():
		if pair.x == receptor_id:
			return true
	return false


func _on_contamination_changed() -> void:
	_contaminated = _contamination_in(_model)
	queue_redraw()


func _on_link_changed(id: int, _neuron_id: int) -> void:
	if id != receptor_id:
		return
	_linked = _model.get_link_count(id)
	queue_redraw()
