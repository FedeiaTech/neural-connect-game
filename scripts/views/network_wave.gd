class_name NetworkWave
extends RefCounted
## Timing of the level-complete light wave (SDD 5.4): it starts at the last moved neuron and
## spreads through the network by graph distance (breadth-first over dendrites). Neurons light
## up WAVE_STEP seconds per step; each dendrite carries the light from its nearer end to the
## other in WAVE_TRAVEL seconds. Pure data: views only consume the schedule.


## Steps from origin to every neuron. Neurons not connected to origin continue from
## (furthest reached + 1), one component after another in id order, so every neuron lights up.
## An unknown origin starts at the first id.
static func graph_distances(ids: Array[int], edges: Array[Vector2i], origin: int) -> Dictionary:
	var neighbours := {}
	for id in ids:
		neighbours[id] = []
	for edge in edges:
		if neighbours.has(edge.x) and neighbours.has(edge.y):
			neighbours[edge.x].append(edge.y)
			neighbours[edge.y].append(edge.x)
	var distances := {}
	if ids.is_empty():
		return distances
	var start := origin if neighbours.has(origin) else ids[0]
	var base := 0
	while start != PuzzleModel.NO_NEURON:
		base = _breadth_first(start, base, neighbours, distances) + 1
		start = PuzzleModel.NO_NEURON
		for id in ids:
			if not distances.has(id):
				start = id
				break
	return distances


## {"neurons": {id: delay}, "edges": [{"delay", "from_a", "duration"}] (by edge id),
##  "duration": seconds until the wave has fully faded}.
static func schedule(model: PuzzleModel, origin: int) -> Dictionary:
	var edges: Array[Vector2i] = []
	for edge_id in model.get_edge_count():
		edges.append(model.get_edge_endpoints(edge_id))
	var distances := graph_distances(model.get_neuron_ids(), edges, origin)
	var neuron_delays := {}
	var last := 0.0
	for id: int in distances:
		neuron_delays[id] = distances[id] * VisualTuning.WAVE_STEP
		last = maxf(last, neuron_delays[id])
	var edge_entries: Array[Dictionary] = []
	for edge in edges:
		var a: int = distances.get(edge.x, 0)
		var b: int = distances.get(edge.y, 0)
		var delay := mini(a, b) * VisualTuning.WAVE_STEP
		edge_entries.append({"delay": delay, "from_a": a <= b, "duration": VisualTuning.WAVE_TRAVEL})
		last = maxf(last, delay + VisualTuning.WAVE_TRAVEL)
	return {"neurons": neuron_delays, "edges": edge_entries, "duration": last + VisualTuning.WAVE_TAIL}


## Returns the largest distance assigned.
static func _breadth_first(start: int, base: int, neighbours: Dictionary, distances: Dictionary) -> int:
	distances[start] = base
	var furthest := base
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var current: int = queue.pop_front()
		for next: int in neighbours[current]:
			if not distances.has(next):
				distances[next] = distances[current] + 1
				furthest = maxi(furthest, distances[next])
				queue.append(next)
	return furthest
