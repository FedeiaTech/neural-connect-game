class_name ScreenHost
extends Node
## Loads and unloads the current screen (SDD 8.4-8.6): MainMenu, MissionSelect, Level, Settings.
## Exactly one screen is a child at a time. Every swap goes through the Transition (fade out,
## swap, fade in); requests that arrive while a transition runs are ignored.
## Screens only emit intent (signals up); ScreenHost decides where to go (calls down) and is the
## one that stores level results in GameState.
## level_restart_requested needs no ScreenHost action: restarts never reload the scene (SDD 8.6.4),
## the Level resets its own HUD.

signal screen_changed(screen: Screen)

enum Screen { NONE, MAIN_MENU, MISSION_SELECT, LEVEL, SETTINGS, BRAND_INTRO, CREDITS, DIAGNOSTICS }

const BrandIntroScene := preload("res://scenes/screens/brand_intro.tscn")
const CreditsScene := preload("res://scenes/screens/credits_screen.tscn")
const DiagnosticsScene := preload("res://scenes/screens/diagnostics_screen.tscn")
const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")
const SettingsScene := preload("res://scenes/screens/settings_screen.tscn")
const LevelScene := preload("res://scenes/level/level.tscn")

## Optional; without it screens swap instantly (used by isolated tests).
@export var transition: Transition
## Optional; receives every new screen so it can play sounds from that screen's signals.
@export var audio: AudioDirector
## False for a host nested inside the diagnostic battery: its Settings screen hides the
## Diagnostics button so a check can never open the battery inside itself.
var diagnostics_enabled := true

var _screen := Screen.NONE
var _current: Node
var _busy := false


func _ready() -> void:
	PlatformProfile.apply_to_theme(ThemeDB.get_project_theme())


## Fades to the given screen. For Screen.LEVEL use play_mission() instead.
## Returns false (and does nothing) when a transition is already running.
func go_to(screen: Screen, mission_id: StringName = &"") -> bool:
	if _busy:
		return false
	_busy = true
	_run_transition(screen, mission_id)
	return true


## Starts a mission if it exists and is unlocked (SDD 7.1). Returns false otherwise, or when
## the request is dropped because a transition is running.
func play_mission(mission_id: StringName) -> bool:
	if GameState.get_level(mission_id) == null or not GameState.is_unlocked(mission_id):
		push_warning("ScreenHost: mission '%s' is unknown or locked." % mission_id)
		return false
	return go_to(Screen.LEVEL, mission_id)


func get_current_screen() -> Screen:
	return _screen


func get_current_node() -> Node:
	return _current


func is_busy() -> bool:
	return _busy


# --- Internals ---------------------------------------------------------------

func _run_transition(screen: Screen, mission_id: StringName) -> void:
	if transition != null:
		await transition.cover()
	_swap(screen, mission_id)
	if transition != null:
		await transition.reveal()
	_busy = false


func _swap(screen: Screen, mission_id: StringName) -> void:
	if _current != null:
		remove_child(_current)
		_current.queue_free()
		_current = null
	match screen:
		Screen.MAIN_MENU:
			_current = _enter_main_menu()
		Screen.MISSION_SELECT:
			_current = _enter_mission_select()
		Screen.SETTINGS:
			_current = _enter_settings()
		Screen.BRAND_INTRO:
			_current = _enter_brand_intro()
		Screen.CREDITS:
			_current = _enter_credits()
		Screen.DIAGNOSTICS:
			_current = _enter_diagnostics()
		Screen.LEVEL:
			_current = _enter_level(mission_id)
	_screen = screen if _current != null else Screen.NONE
	PlatformProfile.adapt_buttons(_current)
	_attach_audio(_current)
	screen_changed.emit(_screen)


func _attach_audio(node: Node) -> void:
	if audio == null or node == null:
		return
	if node is Level:
		audio.bind_level(node as Level)
	else:
		audio.bind_ui(node)


func _enter_main_menu() -> Node:
	var menu: MainMenu = MainMenuScene.instantiate()
	add_child(menu)
	menu.play_pressed.connect(go_to.bind(Screen.MISSION_SELECT))
	menu.settings_pressed.connect(go_to.bind(Screen.SETTINGS))
	menu.credits_pressed.connect(go_to.bind(Screen.CREDITS))
	menu.quit_pressed.connect(get_tree().quit)
	return menu


func _enter_brand_intro() -> Node:
	var intro: BrandIntro = BrandIntroScene.instantiate()
	add_child(intro)
	intro.finished.connect(go_to.bind(Screen.MAIN_MENU))
	return intro


func _enter_credits() -> Node:
	var credits: CreditsScreen = CreditsScene.instantiate()
	add_child(credits)
	credits.back_pressed.connect(go_to.bind(Screen.MAIN_MENU))
	return credits


func _enter_diagnostics() -> Node:
	var diagnostics: DiagnosticsScreen = DiagnosticsScene.instantiate()
	add_child(diagnostics)
	diagnostics.back_pressed.connect(go_to.bind(Screen.SETTINGS))
	return diagnostics


func _enter_mission_select() -> Node:
	var select: MissionSelect = MissionSelectScene.instantiate()
	add_child(select)
	select.mission_selected.connect(play_mission)
	select.back_pressed.connect(go_to.bind(Screen.MAIN_MENU))
	return select


func _enter_settings() -> Node:
	var settings: SettingsScreen = SettingsScene.instantiate()
	add_child(settings)
	settings.back_pressed.connect(go_to.bind(Screen.MAIN_MENU))
	if diagnostics_enabled:
		settings.diagnostics_pressed.connect(go_to.bind(Screen.DIAGNOSTICS))
	else:
		settings.set_diagnostics_available(false)
	return settings


func _enter_level(mission_id: StringName) -> Node:
	var data := GameState.get_level(mission_id)
	if data == null:
		push_error("ScreenHost: no LevelData for mission '%s'." % mission_id)
		return null
	GameState.current_mission = mission_id
	var level: Level = LevelScene.instantiate()
	add_child(level)
	level.get_controller().level_completed.connect(_on_level_completed)
	level.next_mission_requested.connect(_on_next_mission_requested)
	level.mission_select_requested.connect(go_to.bind(Screen.MISSION_SELECT))
	level.load_level(data)
	return level


func _on_level_completed(result: LevelResult) -> void:
	var mission_id := GameState.current_mission
	GameState.record_result(mission_id, result)
	var next := GameState.next_mission_after(mission_id)
	var level := _current as Level
	if level != null:
		level.set_next_mission_available(next != &"" and GameState.is_unlocked(next))


func _on_next_mission_requested() -> void:
	var next := GameState.next_mission_after(GameState.current_mission)
	if next != &"":
		play_mission(next)
