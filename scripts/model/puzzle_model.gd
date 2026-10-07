class_name PuzzleModel
extends RefCounted
## Pure puzzle rules (SDD 2, 8.1, 8.5): neuron positions, dendrite crossings, drag
## collisions, tension and win state. Holds no Node references; views listen to its signals.
##
## Crossing rule: two dendrites cross when their segments intersect (endpoints touching and
## collinear overlaps included) and they share no neuron. Edge id = index in LevelData.dendrites.

signal neuron_moved(id: int, pos: Vector2)
signal neuron_blocked(id: int, contact: Vector2)
signal crossings_changed(crossing_edges: Array[int], involved_neurons: Array[int])
signal tension_changed(edge_id: int, ratio: float)
signal edge_broke(edge_id: int)
signal solved()

const NO_NEURON := -1
## Drag sub-step as a fraction of the neuron radius. A circle can clip a sharp corner between
## two samples by at most radius * (1 - sqrt(1 - (STEP_FACTOR / 2)^2)), about 0.2 px at radius 28.
const STEP_FACTOR := 0.25
const MIN_STEP := 1.0
## Binary search iterations to locate the contact point inside the blocked sub-step.
const BISECT_ITERATIONS := 16

var _ids: Array[int] = []
var _positions: Dictionary[int, Vector2] = {}
var _fixed: Dictionary[int, bool] = {}
var _edges: Array[Vector2i] = []
var _radius := 28.0
var _play_area := PackedVector2Array()
var _obstacles: Array[PackedVector2Array] = []

var _crossing_edges: Array[int] = []
var _crossing_neurons: Array[int] = []
var _crossing_count := 0

## TENSION edges only: edge id -> Vector2(rest_length, max_length).
var _tension_limits: Dictionary[int, Vector2] = {}
var _tension_ratios: Dictionary[int, float] = {}
## Neuron id -> ids of the TENSION edges attached to it.
var _tension_edges_by_neuron: Dictionary[int, Array] = {}
var _broken := false

var _grabbed_id := NO_NEURON
var _moved_during_grab := false
var _move_count := 0
var _solved := false


## Builds a model from level data. The resource is copied, never mutated.
## With use_solution, neurons start at their reference solution positions (for validation).
## Expects a structurally valid level (see validate_level); returns null otherwise.
static func from_level(level: LevelData, use_solution := false) -> PuzzleModel:
	var model := PuzzleModel.new()
	model._radius = level.neuron_radius
	model._play_area = level.play_area.duplicate()
	for obstacle: PackedVector2Array in level.obstacles:
		model._obstacles.append(obstacle.duplicate())
	for neuron: NeuronData in level.neurons:
		model._ids.append(neuron.id)
		model._positions[neuron.id] = neuron.solution_position if use_solution else neuron.position
		model._fixed[neuron.id] = neuron.fixed
	for dendrite: DendriteData in level.dendrites:
		if not model._positions.has(dendrite.a) or not model._positions.has(dendrite.b):
			push_error("PuzzleModel: dendrite references a missing neuron (%d-%d)." % [dendrite.a, dendrite.b])
			return null
		var edge_id := model._edges.size()
		model._edges.append(Vector2i(dendrite.a, dendrite.b))
		if dendrite.is_tension():
			model._tension_limits[edge_id] = Vector2(dendrite.rest_length, dendrite.max_length)
			for neuron_id in [dendrite.a, dendrite.b]:
				if not model._tension_edges_by_neuron.has(neuron_id):
					model._tension_edges_by_neuron[neuron_id] = []
				model._tension_edges_by_neuron[neuron_id].append(edge_id)
			model._tension_ratios[edge_id] = model._compute_tension_ratio(edge_id)
	model._update_crossings(false)
	return model


# --- Input -------------------------------------------------------------------

## Grabs a neuron for dragging. Refused (false) for unknown or fixed neurons, or while
## another neuron is grabbed (single pointer). Grabbing the already grabbed neuron is true.
func grab(id: int) -> bool:
	if _broken or not _positions.has(id) or _fixed[id]:
		return false
	if _grabbed_id != NO_NEURON:
		return _grabbed_id == id
	_grabbed_id = id
	_moved_during_grab = false
	return true


## Moves the grabbed neuron along the straight path to target. If the path is blocked by the
## play area outline, an obstacle or another neuron, the neuron stops at the last valid point
## (no sliding, no pushing), stays grabbed and neuron_blocked(id, stop_position) is emitted on
## every blocked call. Dendrites never block neurons.
## If the move stretches a TENSION dendrite beyond max_length, edge_broke is emitted, the grab
## is released and the model ignores further input (the owner rebuilds it).
func drag_to(target: Vector2) -> void:
	if _grabbed_id == NO_NEURON or _broken:
		return
	var id := _grabbed_id
	var start := _positions[id]
	if start == target:
		return
	var step := maxf(_radius * STEP_FACTOR, MIN_STEP)
	var steps := maxi(ceili(start.distance_to(target) / step), 1)
	var reached := target
	var blocked := false
	var last_valid_t := 0.0
	for i in range(1, steps + 1):
		var t := float(i) / steps
		if not _is_free_position(id, start.lerp(target, t)):
			reached = start.lerp(target, _bisect_contact(id, start, target, last_valid_t, t))
			blocked = true
			break
		last_valid_t = t
	if reached != start:
		_positions[id] = reached
		_moved_during_grab = true
		neuron_moved.emit(id, reached)
		_update_crossings(true)
		_update_tension(id)
	if blocked and not _broken:
		neuron_blocked.emit(id, reached)


## Ends the current drag. One move = one grab-to-release during which the neuron actually
## changed position (a grab with no displacement, e.g. fully blocked, is not a move).
## With zero crossings the model becomes solved and emits solved() once per model.
func release() -> void:
	if _grabbed_id == NO_NEURON:
		return
	if _moved_during_grab:
		_move_count += 1
	_grabbed_id = NO_NEURON
	_moved_during_grab = false
	if not _solved and _crossing_edges.is_empty():
		_solved = true
		solved.emit()


## Nearest neuron whose center is within grab_radius of point, or NO_NEURON.
## Fixed neurons are returned too (views may react); grab() refuses them.
func pick_neuron(point: Vector2, grab_radius: float) -> int:
	var best_id := NO_NEURON
	var best_distance := grab_radius
	for id in _ids:
		var distance := point.distance_to(_positions[id])
		if distance <= best_distance:
			if best_id == NO_NEURON or distance < best_distance:
				best_id = id
				best_distance = distance
	return best_id


# --- Queries -----------------------------------------------------------------

func get_grabbed_id() -> int:
	return _grabbed_id


## Completed moves (see release()).
func get_move_count() -> int:
	return _move_count


## True once a release happened with zero crossings. Never resets for this model.
func is_solved() -> bool:
	return _solved


## True after a TENSION dendrite broke. The model then ignores all input.
func is_broken() -> bool:
	return _broken


func is_tension_edge(edge_id: int) -> bool:
	return _tension_limits.has(edge_id)


## 0 at (or below) rest length, 1 at max length. Always 0 for NORMAL edges.
func get_tension_ratio(edge_id: int) -> float:
	return _tension_ratios.get(edge_id, 0.0)


func get_neuron_ids() -> Array[int]:
	return _ids.duplicate()


func has_neuron(id: int) -> bool:
	return _positions.has(id)


func get_neuron_position(id: int) -> Vector2:
	return _positions.get(id, Vector2.ZERO)


func is_fixed(id: int) -> bool:
	return _fixed.get(id, false)


func get_neuron_radius() -> float:
	return _radius


func get_play_area() -> PackedVector2Array:
	return _play_area.duplicate()


func get_obstacles() -> Array[PackedVector2Array]:
	return _obstacles.duplicate()


func get_edge_count() -> int:
	return _edges.size()


## Neuron ids at both ends of the edge (x = a, y = b).
func get_edge_endpoints(edge_id: int) -> Vector2i:
	return _edges[edge_id]


func get_edge_length(edge_id: int) -> float:
	var edge := _edges[edge_id]
	return _positions[edge.x].distance_to(_positions[edge.y])


## Sorted ids of every edge involved in at least one crossing.
func get_crossing_edges() -> Array[int]:
	return _crossing_edges.duplicate()


## Sorted ids of every neuron at the end of a crossing edge.
func get_crossing_neurons() -> Array[int]:
	return _crossing_neurons.duplicate()


## Number of crossing edge pairs.
func get_crossing_count() -> int:
	return _crossing_count


## Recomputes crossings from current positions. Pure query: no state change, no signal.
func compute_crossings() -> Array[int]:
	return _find_crossings()[0]


# --- Internals ---------------------------------------------------------------

## True when neuron id may sit at center: inside the play area, outside obstacles and not
## overlapping any other neuron (touching is allowed).
func _is_free_position(id: int, center: Vector2) -> bool:
	if not GeometryUtils.is_circle_in_playfield(center, _radius, _play_area, _obstacles):
		return false
	var min_distance := 2.0 * _radius - GeometryUtils.EPSILON
	for other in _ids:
		if other != id and center.distance_to(_positions[other]) < min_distance:
			return false
	return true


## ratio = clamp((length - rest) / (max - rest), 0, 1); 0 when max <= rest.
func _compute_tension_ratio(edge_id: int) -> float:
	var limits := _tension_limits[edge_id]
	var span := limits.y - limits.x
	if span <= 0.0:
		return 0.0
	return clampf((get_edge_length(edge_id) - limits.x) / span, 0.0, 1.0)


## Refreshes the TENSION edges attached to the moved neuron; breaks the first one past max.
func _update_tension(moved_id: int) -> void:
	for edge_id: int in _tension_edges_by_neuron.get(moved_id, []):
		var ratio := _compute_tension_ratio(edge_id)
		if ratio != _tension_ratios[edge_id]:
			_tension_ratios[edge_id] = ratio
			tension_changed.emit(edge_id, ratio)
		if get_edge_length(edge_id) > _tension_limits[edge_id].y:
			_broken = true
			_grabbed_id = NO_NEURON
			_moved_during_grab = false
			edge_broke.emit(edge_id)
			return


## Largest t in [valid_t, invalid_t] (to bisection precision) where the neuron is free.
func _bisect_contact(id: int, start: Vector2, target: Vector2, valid_t: float, invalid_t: float) -> float:
	var low := valid_t
	var high := invalid_t
	for i in BISECT_ITERATIONS:
		var mid := (low + high) * 0.5
		if _is_free_position(id, start.lerp(target, mid)):
			low = mid
		else:
			high = mid
	return low


## Returns [crossing_edges: Array[int] (sorted), pair_count: int]. O(E^2).
func _find_crossings() -> Array:
	var flagged: Dictionary[int, bool] = {}
	var pairs := 0
	for i in _edges.size():
		var e1 := _edges[i]
		var a1 := _positions[e1.x]
		var a2 := _positions[e1.y]
		for j in range(i + 1, _edges.size()):
			var e2 := _edges[j]
			if e2.x == e1.x or e2.x == e1.y or e2.y == e1.x or e2.y == e1.y:
				continue
			if GeometryUtils.segments_cross(a1, a2, _positions[e2.x], _positions[e2.y]):
				flagged[i] = true
				flagged[j] = true
				pairs += 1
	var edges: Array[int] = []
	edges.assign(flagged.keys())
	edges.sort()
	return [edges, pairs]


func _update_crossings(notify: bool) -> void:
	var result := _find_crossings()
	var edges: Array[int] = result[0]
	_crossing_count = result[1]
	if edges == _crossing_edges:
		return
	_crossing_edges = edges
	var involved: Dictionary[int, bool] = {}
	for edge_id in edges:
		involved[_edges[edge_id].x] = true
		involved[_edges[edge_id].y] = true
	_crossing_neurons.assign(involved.keys())
	_crossing_neurons.sort()
	if notify:
		crossings_changed.emit(get_crossing_edges(), get_crossing_neurons())
