extends GdUnitTestSuite
## T6.2: English + Spanish through Godot CSV translations (locale/translations.csv). Checks the
## table itself, its registration, the language setting in GameState (saved, default from the
## OS locale) and that visible UI follows a live locale switch.
## Restores the TranslationServer locale and the GameState autoload after every test.

const GameStateScript := preload("res://scripts/autoloads/game_state.gd")
const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const Csv := preload("res://tests/localization/translation_table.gd")
const SettingsScene := preload("res://scenes/screens/settings_screen.tscn")
const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")
const HudScene := preload("res://scenes/ui/hud.tscn")
const TEMP_PATH := "user://test_language_progress.json"
const SCENES_DIR := "res://scenes"
## Text in scenes that is not translated on purpose (the game's name).
## Game name and credit literals (names and the copyright line are never translated).
const UNTRANSLATED := ["Neural Connect", "Federico Iacono", "Copyright © 2026 Chainsaw Games - iaTech"]

var _locale := ""
var _sandbox: Sandbox


func before_test() -> void:
	_locale = TranslationServer.get_locale()
	_delete_temp()
	_sandbox = Sandbox.new()
	_sandbox.enter()


func after_test() -> void:
	_sandbox.exit()
	_delete_temp()
	TranslationServer.set_locale(_locale)


func _new_state() -> Node:
	var state: Node = auto_free(GameStateScript.new())
	state.save_path = TEMP_PATH
	state.load_game()
	return state


func _delete_temp() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(TEMP_PATH.get_file()):
			dir.remove(file)


func _write_temp(data: Dictionary) -> void:
	var file := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _add(scene: PackedScene) -> Node:
	var node: Node = auto_free(scene.instantiate())
	add_child(node)
	return node


# --- The table ------------------------------------------------------------------

func test_table_has_english_and_spanish_for_every_key() -> void:
	var table := Csv.load_table()
	assert_array(table["header"]).is_equal(["keys", "en", "es"])
	assert_int(table["rows"].size()).is_greater(20)
	for key: String in table["rows"]:
		var row: Dictionary = table["rows"][key]
		assert_str(key).override_failure_message("key '%s' is not UPPER_SNAKE" % key) \
			.is_equal(key.to_upper().replace(" ", "_"))
		assert_str(String(row["en"]).strip_edges()).override_failure_message(key + ": en").is_not_empty()
		assert_str(String(row["es"]).strip_edges()).override_failure_message(key + ": es").is_not_empty()
	assert_array(table["duplicates"]).is_empty()


func test_format_placeholders_match_between_languages() -> void:
	var table := Csv.load_table()
	for key: String in table["rows"]:
		var row: Dictionary = table["rows"][key]
		for placeholder in ["%d", "%s"]:
			assert_int(String(row["es"]).count(placeholder)).override_failure_message(
				"%s: %s count differs" % [key, placeholder]).is_equal(String(row["en"]).count(placeholder))


func test_translations_are_registered_for_both_locales() -> void:
	var loaded := TranslationServer.get_loaded_locales()
	assert_bool(loaded.has("en")).is_true()
	assert_bool(loaded.has("es")).is_true()
	TranslationServer.set_locale("es")
	assert_str(tr("MENU_PLAY")).is_equal("Jugar")
	TranslationServer.set_locale("en")
	assert_str(tr("MENU_PLAY")).is_equal("Play")


## Every text with letters in a scene is a translation key (or the untranslated game name).
func test_scene_texts_are_translation_keys() -> void:
	var keys: Dictionary = Csv.load_table()["rows"]
	var regex := RegEx.create_from_string('^(text|tooltip_text) = "(.*)"$')
	var letters := RegEx.create_from_string("[A-Za-z]")
	for path in _scene_files(SCENES_DIR):
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var found := regex.search(line)
			if found == null:
				continue
			var value := found.get_string(2)
			if letters.search(value) == null or UNTRANSLATED.has(value):
				continue
			assert_bool(keys.has(value)).override_failure_message(
				"%s: '%s' is not a translation key" % [path, value]).is_true()


func _scene_files(dir_path: String) -> PackedStringArray:
	var files := PackedStringArray()
	for file in DirAccess.get_files_at(dir_path):
		if file.ends_with(".tscn"):
			files.append(dir_path.path_join(file))
	for dir in DirAccess.get_directories_at(dir_path):
		files.append_array(_scene_files(dir_path.path_join(dir)))
	return files


# --- Language setting -----------------------------------------------------------

func test_default_language_follows_the_os_locale() -> void:
	assert_str(GameStateScript.default_language_for("es")).is_equal("es")
	assert_str(GameStateScript.default_language_for("en")).is_equal("en")
	assert_str(GameStateScript.default_language_for("fr")).is_equal("en")
	assert_str(GameStateScript.default_language_for("")).is_equal("en")


func test_missing_or_invalid_language_falls_back_to_the_os_default() -> void:
	var expected := GameStateScript.default_language_for(OS.get_locale_language())
	assert_str(_new_state().language).is_equal(expected)
	_write_temp({"version": 1, "settings": {"language": "fr"}})
	assert_str(_new_state().language).is_equal(expected)
	_write_temp({"version": 1, "settings": {"language": 5}})
	assert_str(_new_state().language).is_equal(expected)


func test_language_is_saved_and_applied() -> void:
	var state := _new_state()
	state.set_language("es")
	assert_str(state.language).is_equal("es")
	assert_str(TranslationServer.get_locale()).is_equal("es")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))
	assert_str(saved["settings"]["language"]).is_equal("es")
	TranslationServer.set_locale("en")
	var reloaded := _new_state()
	assert_str(reloaded.language).is_equal("es")
	assert_str(TranslationServer.get_locale()).is_equal("es")
	state.set_language("en")
	assert_str(_new_state().language).is_equal("en")


func test_unsupported_language_is_ignored() -> void:
	var state := _new_state()
	state.set_language("en")
	state.set_language("fr")
	assert_str(state.language).is_equal("en")
	assert_str(TranslationServer.get_locale()).is_equal("en")


func test_language_survives_a_progress_reset() -> void:
	var state := _new_state()
	state.set_language("es")
	state.reset_progress()
	assert_str(_new_state().language).is_equal("es")


# --- Live switch ----------------------------------------------------------------

func test_settings_language_selector_switches_the_game_language() -> void:
	var settings: SettingsScreen = _add(SettingsScene)
	var selector := settings.get_language_selector()
	assert_int(selector.item_count).is_equal(2)
	assert_str(selector.get_item_text(0)).is_equal("English")
	assert_str(selector.get_item_text(1)).is_equal("Español")
	assert_int(selector.selected).is_equal(0)
	selector.select(1)
	selector.item_selected.emit(1)
	assert_str(GameState.language).is_equal("es")
	assert_str(TranslationServer.get_locale()).is_equal("es")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Sandbox.TEMP_PATH))
	assert_str(saved["settings"]["language"]).is_equal("es")


func test_glow_titles_follow_a_live_switch() -> void:
	var settings: SettingsScreen = _add(SettingsScene)
	assert_str(settings.get_title().get_display_text()).is_equal("Settings")
	GameState.set_language("es")
	await await_idle_frame()
	assert_str(settings.get_title().get_display_text()).is_equal("Ajustes")
	var menu: MainMenu = _add(MainMenuScene)
	assert_str(menu.get_title_text()).is_equal("Neural Connect")


func test_hud_formatted_texts_follow_a_live_switch() -> void:
	var hud: Hud = _add(HudScene)
	hud.set_moves(3)
	assert_str(hud.get_moves_text()).is_equal("Moves 3")
	GameState.set_language("es")
	await await_idle_frame()
	assert_str(hud.get_moves_text()).is_equal("Movimientos 3")
	assert_str(Hud.stats_text(8, 61.0, 1.0)).is_equal("Movimientos 8    Tiempo 01:01")
	assert_str(hud.get_restart_button().tooltip_text).is_equal("Reiniciar la misión (R)")


func test_mission_select_headings_follow_a_live_switch() -> void:
	var select: MissionSelect = _add(MissionSelectScene)
	assert_str(select.get_chapter_titles()[0]).starts_with("Chapter 1: ")
	GameState.set_language("es")
	await await_idle_frame()
	assert_str(select.get_chapter_titles()[0]).starts_with("Capítulo 1: ")
	assert_str(select.get_mission_node(&"m02").tooltip_text).is_equal("Bloqueada")
