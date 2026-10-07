extends RefCounted
## Points the GameState autoload at a temp save file for one test and restores it afterwards,
## so flow/UI tests never read or write the real user://progress.json.
## reduced_motion is forced on (not saved) so screen transitions complete synchronously.
## The language is forced to English (not saved) so text assertions do not depend on the OS;
## exit() reloads the real save, which re-applies the player's language.

const TEMP_PATH := "user://test_flow_progress.json"

var _previous_mission: StringName


func enter() -> void:
	_previous_mission = GameState.current_mission
	_delete_temp()
	GameState.save_path = TEMP_PATH
	GameState.load_game()
	GameState.reduced_motion = true
	GameState.language = "en"
	GameState.apply_settings()


func exit() -> void:
	_delete_temp()
	GameState.save_path = GameState.DEFAULT_SAVE_PATH
	GameState.load_game()
	GameState.current_mission = _previous_mission


static func _delete_temp() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(TEMP_PATH.get_file()):
			dir.remove(file)
