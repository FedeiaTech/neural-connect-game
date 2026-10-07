extends Node
## Global game state: the only autoload (see docs/SDD.md 8.4).
## Owns the campaign catalog, the current mission, the saved progress and the settings.
##
## Save: one versioned JSON file (default user://progress.json) holding progress AND settings:
##   {"version": 1,
##    "progress": {"missions": {"m01": {"completed": true, "stars": 3, "moves": 5, "time": 31.2}}},
##    "settings": {"master_volume": 1.0, "reduced_motion": false}}
## A missing or corrupt file means fresh progress and default settings, never a crash.
## Unlock rule (SDD 7.1, chapter rules undecided -> linear): the first campaign mission is always
## unlocked; any other mission is unlocked once the mission before it in campaign order (across
## chapters) is completed.

signal current_mission_changed(mission_id: StringName)
signal progress_changed()
signal settings_changed()

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://progress.json"
const DEFAULT_CAMPAIGN: Campaign = preload("res://data/campaign.tres")
const MASTER_BUS := 0

## Injectable for tests so they never touch the real save.
var save_path := DEFAULT_SAVE_PATH
var campaign: Campaign = DEFAULT_CAMPAIGN
var progress := Progress.new()
## Linear 0..1.
var master_volume := 1.0
var reduced_motion := false

var current_mission: StringName = &"":
	set(value):
		if current_mission == value:
			return
		current_mission = value
		current_mission_changed.emit(value)


func _ready() -> void:
	load_game()


## Replaces progress and settings with the content of save_path (defaults when unusable).
func load_game() -> void:
	var data := SaveFile.read_json(save_path)
	data = _migrate(data)
	progress = Progress.from_dict(data.get("progress"))
	var settings: Variant = data.get("settings")
	if not settings is Dictionary:
		settings = {}
	var volume: Variant = settings.get("master_volume", 1.0)
	master_volume = clampf(float(volume), 0.0, 1.0) if (volume is float or volume is int) else 1.0
	var motion: Variant = settings.get("reduced_motion", false)
	reduced_motion = motion if motion is bool else false
	apply_settings()
	progress_changed.emit()
	settings_changed.emit()


func save_game() -> Error:
	return SaveFile.write_json(save_path, {
		"version": SAVE_VERSION,
		"progress": progress.to_dict(),
		"settings": {"master_volume": master_volume, "reduced_motion": reduced_motion},
	})


func get_level(mission_id: StringName) -> LevelData:
	return campaign.get_level(mission_id)


func next_mission_after(mission_id: StringName) -> StringName:
	return campaign.next_mission_after(mission_id)


func is_unlocked(mission_id: StringName) -> bool:
	if campaign.get_level(mission_id) == null:
		return false
	if mission_id == campaign.first_mission_id() or progress.is_completed(mission_id):
		return true
	return progress.is_completed(campaign.previous_mission_before(mission_id))


## Stores a completed run (best values kept) and saves. Unknown missions are ignored.
func record_result(mission_id: StringName, result: LevelResult) -> void:
	if campaign.get_level(mission_id) == null:
		push_warning("GameState: result for unknown mission '%s' ignored." % mission_id)
		return
	progress.record(mission_id, result.stars, result.moves, result.time)
	save_game()
	progress_changed.emit()


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_settings()
	save_game()
	settings_changed.emit()


func set_reduced_motion(value: bool) -> void:
	reduced_motion = value
	save_game()
	settings_changed.emit()


## Pushes the settings to the engine (master bus volume).
func apply_settings() -> void:
	AudioServer.set_bus_mute(MASTER_BUS, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(MASTER_BUS, linear_to_db(maxf(master_volume, 0.0001)))


## Upgrades older save data to SAVE_VERSION. Data without a numeric version is unusable.
func _migrate(data: Dictionary) -> Dictionary:
	var version: Variant = data.get("version")
	if not (version is int or version is float):
		return {}
	if int(version) > SAVE_VERSION:
		push_warning("GameState: save version %d is newer than %d; reading known fields." \
			% [int(version), SAVE_VERSION])
	# v1 is the first format: nothing to migrate yet.
	return data
