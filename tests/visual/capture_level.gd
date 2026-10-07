extends Node
## Debug capture (not a test suite): renders a mission in a real window on the project renderer
## (GL Compatibility) for a few frames, saves a PNG and quits, to check that the shaders compile
## and to eyeball the look. Run the scene (not with -s, so the GameState autoload exists):
##   godot --path . res://tests/visual/capture_level.tscn -- <mission_id> <out.png> [frames] [mode]
## mode: play (default), grab (first neuron grabbed), wave (completion wave), break (tension
## break), reduced (play with reduced motion), glow (WorldEnvironment glow experiment).

const LevelScene := preload("res://scenes/level/level.tscn")

var _frames := 0
var _target := 90
var _mode := "play"
var _out := "user://capture.png"
var _level: Level
var _saved_reduced_motion := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mission := StringName(args[0]) if args.size() > 0 else &"m01"
	if args.size() > 1:
		_out = args[1]
	if args.size() > 2:
		_target = int(args[2])
	if args.size() > 3:
		_mode = args[3]
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = _mode == "reduced"
	if _mode == "glow":
		_add_environment_glow()
	_level = LevelScene.instantiate()
	add_child(_level)
	_level.load_level(GameState.get_level(mission))
	_level.get_hud().hide_story()
	_level.get_controller().start_playing()


func _process(_delta: float) -> void:
	_frames += 1
	if _frames == _target / 2:
		_trigger()
	if _frames == _target:
		var image := get_viewport().get_texture().get_image()
		var error := image.save_png(_out)
		print("capture_level: saved %s (%s)" % [_out, error_string(error)])
		GameState.reduced_motion = _saved_reduced_motion
		get_tree().quit()


## Experiment for T4.4/T4.7: screen-wide WorldEnvironment glow over the 2D canvas.
## Result 2026-10-07 (Godot 4.7.2, GL Compatibility, Intel UHD 600 / OpenGL 3.3): the whole
## background turns into a checkerboard artifact, so the game does not use it and relies on
## additive / premultiplied blending in its shaders instead. Re-check on other GPUs in T4.7.
func _add_environment_glow() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment.glow_strength = 1.2
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 0.7
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)


func _trigger() -> void:
	var controller := _level.get_controller()
	var model := controller.get_model()
	match _mode:
		"grab":
			var id: int = model.get_neuron_ids()[0]
			model.grab(id)
			controller.get_neuron_view(id).set_grabbed(true)
		"wave":
			var fx := _level.get_node_or_null(^"Playfield/Fx")
			if fx != null:
				fx.call(&"play_completion_wave")
		"break":
			for edge in model.get_edge_count():
				if model.is_tension_edge(edge):
					model.edge_broke.emit(edge)
					break
