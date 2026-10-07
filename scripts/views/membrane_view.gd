class_name MembraneView
extends Node2D
## Base for outlines drawn as a living membrane (SDD 5.3, 5.4): a thick white core line with a
## soft additive glow (the scene sets a CanvasItemMaterial with BLEND_MODE_ADD), slowly
## undulating, rippling where a neuron touches it and "exhaling" on level completion.
## Subclasses choose amplitude, width, color and glow strength. Cosmetic only: the model keeps
## the fixed collision polygon. With reduced motion the outline stays still (no redraws unless
## the exhale glow changes).

var _outline := PackedVector2Array()
var _membrane := MembraneOutline.new()
var _amplitude := VisualTuning.BOUNDARY_AMPLITUDE
var _line_width := 6.0
var _color := Color.WHITE
var _glow_scale := 1.0
var _contact_distance := 0.0
var _time := 0.0
var _exhale := 0.0
var _exhale_tween: Tween
## Core color per drawn point (closed: last = first). Lethal edges (T7.2) are violet.
var _point_colors := PackedColorArray()
var _uniform_color := true


## polygon: open polygon from the model. model (optional): ripples on neuron_blocked.
## lethal_edges: polygon edge indices drawn in the lethal color.
func _setup_membrane(polygon: PackedVector2Array, model: PuzzleModel,
		lethal_edges: Dictionary[int, bool] = {}) -> void:
	_outline = OutlineUtils.closed(polygon)
	_membrane.build(polygon)
	_point_colors = PackedColorArray()
	var edges := _membrane.get_edge_indices()
	for i in edges.size():
		_point_colors.append(Palette.LETHAL if lethal_edges.has(edges[i]) else _color)
	if not _point_colors.is_empty():
		_point_colors.append(_point_colors[0])
	_uniform_color = lethal_edges.is_empty()
	_time = 0.0
	if model != null:
		# The model reports the neuron center at contact: one radius away from the outline.
		_contact_distance = model.get_neuron_radius() * 1.3
		model.neuron_blocked.connect(_on_neuron_blocked)
	queue_redraw()


## Closed outline (first point repeated at the end).
func get_outline() -> PackedVector2Array:
	return _outline.duplicate()


func get_line_width() -> float:
	return _line_width


func get_color() -> Color:
	return _color


## Core color of every drawn outline point (closed).
func get_point_colors() -> PackedColorArray:
	return _point_colors.duplicate()


## Core color of the outline point nearest to point.
func get_color_at(point: Vector2) -> Color:
	var base := _membrane.get_base_points()
	var best := 0
	for i in base.size():
		if base[i].distance_squared_to(point) < base[best].distance_squared_to(point):
			best = i
	return _point_colors[best] if best < _point_colors.size() else _color


func has_ripples() -> bool:
	return _membrane.has_ripples(_time)


func get_exhale() -> float:
	return _exhale


## Completion: the membrane swells outward and glows, then settles back (glow only with
## reduced motion).
func exhale(duration := 1.6) -> void:
	if _exhale_tween != null:
		_exhale_tween.kill()
	if not is_inside_tree():
		return
	_exhale_tween = create_tween()
	_exhale_tween.tween_property(self, ^"_exhale", 1.0, duration * 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_exhale_tween.tween_property(self, ^"_exhale", 0.0, duration * 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(delta: float) -> void:
	_time += delta
	if VisualTuning.is_motion_enabled() or _exhale > 0.0:
		queue_redraw()


func _draw() -> void:
	_draw_membrane()


## The only drawing entry point: wide faint glow, narrower glow, then the thick core line.
func _draw_membrane() -> void:
	if _outline.size() < 3:
		return
	var points := _membrane.displaced(_time, _amplitude, VisualTuning.motion_scale(), _exhale)
	var glow := 1.0 + _exhale * 1.5
	var wide := Palette.MEMBRANE_GLOW_WIDE
	var near := Palette.MEMBRANE_GLOW
	# Soft bands fade to zero at their edges (smooth, no hard glow edges); the profile peaks
	# higher than the old flat alpha so the overall glow stays about the same.
	var band := SoftLine.Band.new()
	band.add(points, Color(wide, wide.a * glow * _glow_scale * 2.6), _line_width * 3.4)
	band.add(points, Color(near, near.a * glow * _glow_scale * 2.6), _line_width * 1.5)
	band.draw(self)
	if _uniform_color or _point_colors.size() != points.size():
		draw_polyline(points, _color, _line_width, true)
	else:
		draw_polyline_colors(points, _point_colors, _line_width, true)


func _on_neuron_blocked(_id: int, contact: Vector2) -> void:
	if _membrane.add_ripple(contact, _time, _contact_distance):
		queue_redraw()
