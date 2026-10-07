extends Node
## Debug capture (not a test suite): renders one menu screen in a real window on the project
## renderer (GL Compatibility), saves a PNG after a number of frames and quits. Run the scene (not
## with -s, so the GameState autoload exists):
##   godot --path . res://tests/visual/capture_screens.tscn -- <screen> <out.png> [frames] [reduced]
## screen: main_menu, settings, settings_reset (reset confirmation open), mission_select,
## mission_reset (m01 record reset confirmation), story (story overlay of m01, or of mXX with
## story=mXX), summary (m02
## completion panel), pause (m02).
## Uses a temporary save (m01 completed with 2 stars) so the real progress is never touched.
## Optional 4th argument: "reduced" captures with reduced motion; "perf" turns vsync off and logs
## Performance monitors over 5 s (after a warm-up) before capturing.
## Any argument "lang=<code>" (e.g. lang=es) shows the UI in that language (not saved).

const PerfProbe := preload("res://tests/visual/perf_probe.gd")
const PERF_WARMUP_FRAMES := 60
const PERF_SECONDS := 5.0
const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const SettingsScene := preload("res://scenes/screens/settings_screen.tscn")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")
const LevelScene := preload("res://scenes/level/level.tscn")
const TEMP_SAVE := "user://capture_progress.json"

var _frames := 0
var _target := 120
var _screen := "main_menu"
var _out := "user://capture_screen.png"
var _saved_reduced_motion := false
var _level: Level
var _perf := false
var _probe: PerfProbe


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_screen = args[0]
	var story_mission := &"m01"
	if _screen.begins_with("story="):
		story_mission = StringName(_screen.trim_prefix("story="))
		_screen = "story"
	if args.size() > 1:
		_out = args[1]
	if args.size() > 2:
		_target = int(args[2])
	_saved_reduced_motion = GameState.reduced_motion
	GameState.save_path = TEMP_SAVE
	GameState.load_game()
	GameState.reduced_motion = args.size() > 3 and args[3] == "reduced"
	for arg in args:
		if arg.begins_with("lang="):
			GameState.language = arg.trim_prefix("lang=")
			GameState.apply_settings()
	_perf = args.size() > 3 and args[3] == "perf"
	if _perf:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		_target = 1_000_000
	GameState.record_result(&"m01", LevelResult.create(5, 40.0, 4, 30.0))
	match _screen:
		"settings", "settings_reset":
			var settings: SettingsScreen = SettingsScene.instantiate()
			add_child(settings)
			if _screen == "settings_reset":
				settings.get_reset_button().pressed.emit()
		"mission_select", "mission_reset":
			var select: MissionSelect = MissionSelectScene.instantiate()
			add_child(select)
			if _screen == "mission_reset":
				select.request_mission_reset(&"m01")
		"story":
			_level = LevelScene.instantiate()
			add_child(_level)
			_level.load_level(GameState.get_level(story_mission))
		"summary", "pause":
			_level = LevelScene.instantiate()
			add_child(_level)
			_level.load_level(GameState.get_level(&"m02"))
			_level.get_hud().hide_story()
			_level.get_controller().start_playing()
		_:
			add_child(MainMenuScene.instantiate())
	# Pretend the cursor rests near the left of the title so the network reacts.
	get_viewport().warp_mouse(Vector2(560, 380))


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == 10 and _level != null and _screen != "story":
		if _screen == "summary":
			_level.get_controller().level_completed.emit(LevelResult.create(7, 83.0, 8, 90.0))
			_level.set_next_mission_available(true)
		else:
			_level.pause()
	if _perf:
		if _frames == PERF_WARMUP_FRAMES:
			_probe = PerfProbe.new()
			_probe.start()
		elif _probe != null:
			_probe.sample()
			if _probe.elapsed() >= PERF_SECONDS:
				print(_probe.report(_screen))
				_target = _frames
	if _frames == _target:
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(_out)
		print("capture_screens: saved %s (%s)" % [_out, error_string(error)])
		_finish()


func _finish() -> void:
	get_tree().paused = false
	GameState.reduced_motion = _saved_reduced_motion
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE))
	GameState.save_path = GameState.DEFAULT_SAVE_PATH
	GameState.load_game()
	get_tree().quit()
