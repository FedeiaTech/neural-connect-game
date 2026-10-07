extends RefCounted
## Builds LevelData instances in code for model tests.
## Preload it: `const LevelFactory := preload("res://tests/model/level_factory.gd")`.

const DEFAULT_RADIUS := 28.0


static func rect(origin: Vector2, size: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		origin,
		origin + Vector2(size.x, 0.0),
		origin + size,
		origin + Vector2(0.0, size.y),
	])


## A neuron whose solution position defaults to its start position.
static func neuron(id: int, position: Vector2, solution: Variant = null, fixed := false) -> NeuronData:
	var data := NeuronData.new()
	data.id = id
	data.position = position
	data.solution_position = position if solution == null else solution
	data.fixed = fixed
	return data


static func edge(a: int, b: int) -> DendriteData:
	var data := DendriteData.new()
	data.a = a
	data.b = b
	return data


static func tension_edge(a: int, b: int, rest_length: float, max_length: float) -> DendriteData:
	var data := edge(a, b)
	data.kind = DendriteData.Kind.TENSION
	data.rest_length = rest_length
	data.max_length = max_length
	return data


static func level(
	neurons: Array[NeuronData],
	dendrites: Array[DendriteData],
	obstacles: Array[PackedVector2Array] = [],
	play_area: PackedVector2Array = rect(Vector2.ZERO, Vector2(1000.0, 1000.0)),
) -> LevelData:
	var data := LevelData.new()
	data.mission_id = &"test"
	data.mission_name = "Test"
	data.play_area = play_area
	data.obstacles = obstacles
	data.neurons = neurons
	data.dendrites = dendrites
	data.neuron_radius = DEFAULT_RADIUS
	data.par_moves = 3
	data.par_time = 30.0
	return data


## Four neurons, two edges forming an X at the start (edge 0: 0-1, edge 1: 2-3).
## Solution: two parallel horizontal edges with zero crossings.
static func x_level() -> LevelData:
	var neurons: Array[NeuronData] = [
		neuron(0, Vector2(100, 100), Vector2(100, 100)),
		neuron(1, Vector2(500, 500), Vector2(500, 100)),
		neuron(2, Vector2(500, 100), Vector2(100, 500)),
		neuron(3, Vector2(100, 500), Vector2(500, 500)),
	]
	var dendrites: Array[DendriteData] = [edge(0, 1), edge(2, 3)]
	return level(neurons, dendrites)
