extends Node
## Debug capture (not a test suite): renders one menu screen in a real window on the project
## renderer (GL Compatibility), saves a PNG after a number of frames and quits. Run the scene (not
## with -s, so the GameState autoload exists):
##   godot --path . res://tests/visual/capture_screens.tscn -- <screen> <out.png> [frames] [reduced]
## screen: main_menu, settings, mission_select, summary (m02 completion panel), pause (m02).
## Uses a temporary save (m01 completed with 2 stars) so the real progress is never touched.
## Optional 4th argument "reduced" captures with reduced motion.

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		_screen = args[0]
	if args.size() > 1:
		_out = args[1]
	if args.size() > 2:
		_target = int(args[2])
	_saved_reduced_motion = GameState.reduced_motion
	GameState.save_path = TEMP_SAVE
	GameState.load_game()
	GameState.reduced_motion = args.size() > 3 and args[3] == "reduced"
	GameState.record_result(&"m01", LevelResult.create(5, 40.0, 4, 30.0))
	match _screen:
		"settings":
			add_child(SettingsScene.instantiate())
		"mission_select":
			add_child(MissionSelectScene.instantiate())
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
	if _frames == 10 and _level != null:
		if _screen == "summary":
			_level.get_controller().level_completed.emit(LevelResult.create(7, 83.0, 8, 90.0))
			_level.set_next_mission_available(true)
		else:
			_level.pause()
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
