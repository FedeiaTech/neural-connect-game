extends Node
## Root scene. Phase 2: runs the first mission directly.
## Phase 3 (T3.1) replaces this with ScreenHost and Transition (SDD 8.4).

const LevelScene := preload("res://scenes/level/level.tscn")
const FIRST_MISSION: LevelData = preload("res://data/levels/m01.tres")

var _level: Level


func _ready() -> void:
	_level = LevelScene.instantiate()
	add_child(_level)
	GameState.current_mission = FIRST_MISSION.mission_id
	_level.load_level(FIRST_MISSION)


func get_level() -> Level:
	return _level
