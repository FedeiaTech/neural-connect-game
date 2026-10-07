extends Node
## Global game state: the only autoload (see docs/SDD.md 8.4).
## Owns the campaign catalog, the current mission, the saved progress and the settings.
##
## Save: one versioned JSON file (default user://progress.json) holding progress AND settings:
##   {"version": 2,
##    "progress": {"missions": {"m01": {"completed": true, "stars": 3, "moves": 5, "time": 31.2}}},
##    "settings": {"master_volume": 1.0, "reduced_motion": false, "language": "en"}}
## A missing or corrupt file means fresh progress and default settings, never a crash; a corrupt
## file is moved to <save_path>.bak first. Unknown fields (newer saves) survive a save.
## Unlock rule (SDD 7.1, chapter rules undecided -> linear): the first campaign mission is always
## unlocked; any other mission is unlocked once the mission before it in campaign order (across
## chapters) is completed.
## Language (T6.2): "en" or "es", applied with TranslationServer.set_locale(). A missing or
## unsupported saved value falls back to the OS locale (Spanish OS -> "es", anything else -> "en").

signal current_mission_changed(mission_id: StringName)
signal progress_changed()
signal settings_changed()

## v2 (T7.4): Live Wires and Synapses chapters were inserted before Convergence, so the old
## Convergence missions moved to new ids (see V1_MISSION_ID_MAP).
const SAVE_VERSION := 2
## v1 -> v2 mission renames (old Convergence m19/m20/m21 -> m26/m28/m30). Records keep their
## stars and bests under the new id; the new missions m19..m25 start uncompleted.
const V1_MISSION_ID_MAP: Dictionary = {"m19": "m26", "m20": "m28", "m21": "m30"}
const DEFAULT_SAVE_PATH := "user://progress.json"
const DEFAULT_CAMPAIGN: Campaign = preload("res://data/campaign.tres")
const MASTER_BUS := 0
## Supported UI languages (locale/translations.csv columns). The first one is the fallback.
const LANGUAGES: Array[String] = ["en", "es"]

## Injectable for tests so they never touch the real save.
var save_path := DEFAULT_SAVE_PATH
var campaign: Campaign = DEFAULT_CAMPAIGN
var progress := Progress.new()
## Linear 0..1.
var master_volume := 1.0
var reduced_motion := false
## One of LANGUAGES.
var language := "en"
## Data read by the last load_game(); save_game() merges into it to keep unknown fields.
var _loaded_data := {}

var current_mission: StringName = &"":
	set(value):
		if current_mission == value:
			return
		current_mission = value
		current_mission_changed.emit(value)


func _ready() -> void:
	load_game()


## Replaces progress and settings with the content of save_path (defaults when unusable).
## An unusable file is moved to a .bak first, so the next save never overwrites it.
func load_game() -> void:
	var data := _migrate(SaveFile.read_json(save_path))
	if data.is_empty() and FileAccess.file_exists(save_path):
		SaveFile.backup(save_path)
	_loaded_data = data
	progress = Progress.from_dict(data.get("progress"))
	var settings: Variant = data.get("settings")
	if not settings is Dictionary:
		settings = {}
	var volume: Variant = settings.get("master_volume", 1.0)
	master_volume = clampf(float(volume), 0.0, 1.0) if (volume is float or volume is int) else 1.0
	var motion: Variant = settings.get("reduced_motion", false)
	reduced_motion = motion if motion is bool else false
	var saved_language: Variant = settings.get("language")
	language = saved_language if saved_language is String and LANGUAGES.has(saved_language) \
		else default_language_for(OS.get_locale_language())
	apply_settings()
	progress_changed.emit()
	settings_changed.emit()


## Writes the save. Fields this version does not know (e.g. from a newer game version) are
## kept from the loaded file, and the version number is never downgraded.
func save_game() -> Error:
	var known := {
		"version": SAVE_VERSION,
		"progress": progress.to_dict(),
		"settings": {"master_volume": master_volume, "reduced_motion": reduced_motion, "language": language},
	}
	return SaveFile.write_json(save_path, merge_save_data(_loaded_data, known))


## Deep merge: known values win, unknown keys of the loaded data survive (missions included),
## and the result keeps max(loaded version, SAVE_VERSION).
static func merge_save_data(loaded: Dictionary, known: Dictionary) -> Dictionary:
	var merged := _merge_dicts(loaded, known)
	var loaded_version: Variant = loaded.get("version")
	if (loaded_version is int or loaded_version is float) and int(loaded_version) > SAVE_VERSION:
		merged["version"] = int(loaded_version)
	return merged


static func _merge_dicts(base: Dictionary, override: Dictionary) -> Dictionary:
	var merged := base.duplicate(true)
	for key: Variant in override:
		var value: Variant = override[key]
		if value is Dictionary and merged.get(key) is Dictionary:
			merged[key] = _merge_dicts(merged[key], value)
		else:
			merged[key] = value
	return merged


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


## Back to fresh progress (only the first mission unlocked) and saves. Settings are kept.
## Every mission record is dropped from the save, including unknown per-mission keys and
## missions this version does not know; unknown fields outside the records survive.
func reset_progress() -> void:
	progress.clear()
	var loaded_progress: Variant = _loaded_data.get("progress")
	if loaded_progress is Dictionary:
		(loaded_progress as Dictionary).erase("missions")
	save_game()
	progress_changed.emit()


## Clears one mission's record (completed flag, stars, best moves and time, unknown keys) and
## saves. Unlocks follow the linear rule: later missions that were completed stay completed
## (so they and the mission after them stay unlocked); a later mission that was only unlocked
## by this one locks again. Unknown missions are ignored.
func reset_mission(mission_id: StringName) -> void:
	if campaign.get_level(mission_id) == null:
		push_warning("GameState: reset of unknown mission '%s' ignored." % mission_id)
		return
	progress.erase(mission_id)
	var loaded_progress: Variant = _loaded_data.get("progress")
	if loaded_progress is Dictionary:
		var missions: Variant = (loaded_progress as Dictionary).get("missions")
		if missions is Dictionary:
			(missions as Dictionary).erase(String(mission_id))
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


## Spanish when the OS language is Spanish, English otherwise.
static func default_language_for(os_language: String) -> String:
	return os_language if LANGUAGES.has(os_language) else LANGUAGES[0]


## Switches the UI language live (every visible text follows) and saves. Unsupported codes are
## ignored.
func set_language(code: String) -> void:
	if not LANGUAGES.has(code):
		push_warning("GameState: unsupported language '%s' ignored." % code)
		return
	language = code
	apply_settings()
	save_game()
	settings_changed.emit()


## Pushes the settings to the engine (master bus volume, UI locale).
func apply_settings() -> void:
	TranslationServer.set_locale(language)
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
	return migrate_save(data)


## Pure migration of a parsed save with a numeric version. v1 -> v2 renames the per-mission
## records of V1_MISSION_ID_MAP (unknown keys inside a record survive); other fields are kept.
## Saves at v2 or newer are returned unchanged.
static func migrate_save(data: Dictionary) -> Dictionary:
	var version := int(data.get("version", SAVE_VERSION))
	if version >= 2:
		return data
	var migrated := data.duplicate(true)
	var progress: Variant = migrated.get("progress")
	if progress is Dictionary and (progress as Dictionary).get("missions") is Dictionary:
		var old: Dictionary = progress["missions"]
		var renamed := {}
		for key: Variant in old:
			var new_key: Variant = V1_MISSION_ID_MAP.get(key, key)
			renamed[new_key] = old[key]
		progress["missions"] = renamed
	migrated["version"] = 2
	return migrated
