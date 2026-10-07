extends RefCounted
## Points the GameState autoload at a temp save file for one test and restores it afterwards,
## so flow/UI tests never read or write the real user://progress.json.
## reduced_motion is forced on (not saved) so screen transitions complete synchronously.

const TEMP_PATH := "user://test_flow_progress.json"

var _previous_mission: StringName


func enter() -> void:
	_previous_mission = GameState.current_mission
	_delete_temp()
	GameState.save_path = TEMP_PATH
	GameState.load_game()
	GameState.reduced_motion = true


func exit() -> void:
	_delete_temp()
	GameState.save_path = GameState.DEFAULT_SAVE_PATH
	GameState.load_game()
	GameState.current_mission = _previous_mission


static func _delete_temp() -> void:
	for path in [TEMP_PATH, TEMP_PATH + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
