extends RefCounted
## Test-only levels for the visual captures and the mechanics runs (T8.2, T8.3). They are not
## part of the campaign: capture_level.gd loads them with the mission ids `fixture_toxic` and
## `fixture_diseased`.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const AREA := [160.0, 120.0, 1760.0, 120.0, 1760.0, 1020.0, 160.0, 1020.0]


static func is_fixture(mission_id: StringName) -> bool:
	return String(mission_id).begins_with("fixture_")


static func load_fixture(mission_id: StringName) -> LevelData:
	match mission_id:
		&"fixture_toxic":
			return toxic_level()
		&"fixture_diseased":
			return diseased_level()
	return null


static func _area() -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, AREA.size(), 2):
		points.append(Vector2(AREA[i], AREA[i + 1]))
	return points


## Receptor 0 (needs 1 link) with a normal neuron 1 and a toxic neuron 2 that start outside its
## reach, plus a tangled X (3-6) so the level starts tangled.
static func toxic_level() -> LevelData:
	var neurons: Array[NeuronData] = [
		LevelFactory.receptor(0, Vector2(1000, 560), 150.0, 1),
		LevelFactory.neuron(1, Vector2(1450, 560), Vector2(1150, 560)),
		LevelFactory.toxic(2, Vector2(1000, 880), Vector2(1450, 880)),
		LevelFactory.neuron(3, Vector2(360, 300), Vector2(360, 300)),
		LevelFactory.neuron(4, Vector2(760, 700), Vector2(760, 300)),
		LevelFactory.neuron(5, Vector2(760, 300), Vector2(360, 700)),
		LevelFactory.neuron(6, Vector2(360, 700), Vector2(760, 700)),
	]
	var dendrites: Array[DendriteData] = [LevelFactory.edge(3, 4), LevelFactory.edge(5, 6),
		LevelFactory.edge(1, 4), LevelFactory.edge(2, 6)]
	var level := LevelFactory.level(neurons, dendrites, [], _area())
	level.mission_id = &"fixture_toxic"
	level.mission_name = "Toxic fixture"
	return level


static func diseased_level() -> LevelData:
	return null
