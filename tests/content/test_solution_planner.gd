extends GdUnitTestSuite
## T7.2 / T7.3: the solution planner proves receptor missions through the real model (links
## included) and never plans a move that touches a lethal wall.

const SolutionPlanner := preload("res://tests/content/solution_planner.gd")
const LevelFactory := preload("res://tests/model/level_factory.gd")


func _x_tangle(neurons: Array[NeuronData], dendrites: Array[DendriteData]) -> void:
	neurons.append(LevelFactory.neuron(10, Vector2(300, 600), Vector2(300, 600)))
	neurons.append(LevelFactory.neuron(11, Vector2(600, 900), Vector2(600, 600)))
	neurons.append(LevelFactory.neuron(12, Vector2(600, 600), Vector2(300, 900)))
	neurons.append(LevelFactory.neuron(13, Vector2(300, 900), Vector2(600, 900)))
	dendrites.append(LevelFactory.edge(10, 11))
	dendrites.append(LevelFactory.edge(12, 13))


func _assert_solves(level: LevelData) -> PuzzleModel:
	assert_array(PuzzleModel.validate_level(level)).is_empty()
	var plan := SolutionPlanner.new().plan(level)
	assert_bool(plan["ok"]).override_failure_message(str(plan["reason"])).is_true()
	var replay := SolutionPlanner.replay(level, plan["moves"])
	var model: PuzzleModel = replay["model"]
	assert_str(replay["error"]).is_empty()
	assert_bool(model.is_solved()).is_true()
	return model


func test_plans_a_receptor_level_through_its_links() -> void:
	var receptor := LevelFactory.neuron(0, Vector2(500, 200))
	receptor.kind = NeuronData.Kind.RECEPTOR
	receptor.reach = 120.0
	var neurons: Array[NeuronData] = [receptor, LevelFactory.neuron(1, Vector2(850, 200), Vector2(620, 200))]
	var dendrites: Array[DendriteData] = []
	_x_tangle(neurons, dendrites)
	var model := _assert_solves(LevelFactory.level(neurons, dendrites))
	assert_array(model.get_links(0)).is_equal([1])


func test_keeps_away_from_lethal_walls() -> void:
	var neurons: Array[NeuronData] = []
	var dendrites: Array[DendriteData] = []
	_x_tangle(neurons, dendrites)
	# A lethal island right on the straight path of neuron 11 (600, 900) -> (600, 600).
	var obstacles: Array[PackedVector2Array] = [LevelFactory.rect(Vector2(560, 720), Vector2(80, 60))]
	var level := LevelFactory.level(neurons, dendrites, obstacles)
	level.lethal_obstacles = PackedInt32Array([0])
	_assert_solves(level)
