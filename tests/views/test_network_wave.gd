extends GdUnitTestSuite
## T4.4: the completion wave spreads from the last moved neuron by graph distance.

const LevelFactory := preload("res://tests/model/level_factory.gd")


func _ids(values: Array) -> Array[int]:
	var ids: Array[int] = []
	ids.assign(values)
	return ids


func _edges(pairs: Array) -> Array[Vector2i]:
	var edges: Array[Vector2i] = []
	for pair: Array in pairs:
		edges.append(Vector2i(pair[0], pair[1]))
	return edges


func test_distances_along_a_chain() -> void:
	var ids := _ids([0, 1, 2, 3])
	var edges := _edges([[0, 1], [1, 2], [2, 3]])
	assert_dict(NetworkWave.graph_distances(ids, edges, 0)).is_equal({0: 0, 1: 1, 2: 2, 3: 3})
	assert_dict(NetworkWave.graph_distances(ids, edges, 2)).is_equal({0: 2, 1: 1, 2: 0, 3: 1})


func test_distances_take_the_shortest_path() -> void:
	var ids := _ids([0, 1, 2, 3, 4])
	# Ring 0-1-2-3-4-0: from 0 the far side is two steps away either way.
	var edges := _edges([[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]])
	assert_dict(NetworkWave.graph_distances(ids, edges, 0)).is_equal({0: 0, 1: 1, 2: 2, 3: 2, 4: 1})


func test_disconnected_neurons_light_up_after_the_reached_ones() -> void:
	var ids := _ids([0, 1, 5, 6])
	var edges := _edges([[0, 1], [5, 6]])
	var distances := NetworkWave.graph_distances(ids, edges, 1)
	assert_int(distances[1]).is_equal(0)
	assert_int(distances[0]).is_equal(1)
	assert_int(distances[5]).is_equal(2)
	assert_int(distances[6]).is_equal(3)


func test_unknown_origin_starts_at_the_first_neuron() -> void:
	var ids := _ids([3, 4])
	var edges := _edges([[3, 4]])
	assert_dict(NetworkWave.graph_distances(ids, edges, PuzzleModel.NO_NEURON)).is_equal({3: 0, 4: 1})


func test_schedule_orders_neurons_and_dendrites_by_distance() -> void:
	# x_level: edges 0-1 and 2-3 (two components). Origin 1.
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var schedule := NetworkWave.schedule(model, 1)
	var neurons: Dictionary = schedule["neurons"]
	assert_float(neurons[1]).is_equal(0.0)
	assert_float(neurons[0]).is_equal_approx(VisualTuning.WAVE_STEP, 0.0001)
	assert_float(neurons[2]).is_greater(neurons[0])
	var edges: Array = schedule["edges"]
	assert_int(edges.size()).is_equal(2)
	# Edge 0 (0-1) starts at neuron 1, i.e. at its B end, right away.
	assert_float(edges[0]["delay"]).is_equal(0.0)
	assert_bool(edges[0]["from_a"]).is_false()
	assert_float(edges[1]["delay"]).is_greater(edges[0]["delay"])
	assert_float(schedule["duration"]).is_greater(edges[1]["delay"])
