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
		model._edges.append(Vector2i(dendrite.a, dendrite.b))
	model._update_crossings(false)
	return model


# --- Queries -----------------------------------------------------------------

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
