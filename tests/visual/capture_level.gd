extends Node
## Debug capture (not a test suite): renders a mission in a real window on the project renderer
## (GL Compatibility) for a few frames, saves a PNG and quits, to check that the shaders compile
## and to eyeball the look. Run the scene (not with -s, so the GameState autoload exists):
##   godot --path . res://tests/visual/capture_level.tscn -- <mission_id> <out.png> [frames] [mode]
## mode: play (default), grab (first neuron grabbed), wave (completion wave), break (tension
## break), reduced (play with reduced motion), glow (WorldEnvironment glow experiment),
## perf (idle level, vsync off: logs Performance monitors over PERF_SECONDS, then captures),
## perf_drag (same while a neuron is dragged in circles every frame), approach (a neuron held
## 8 px from a lethal wall: warning glow), explode (a neuron driven into a lethal wall, captured
## mid explosion). approach / explode mark the right play-area side lethal on a copy of a
## mission without lethal walls. link / strain (receptor missions): pulls the nearest free
## neuron into the first receptor's reach (fresh link growing / near the reach limit).
## T8: mission ids fixture_toxic / fixture_diseased load the test levels of
## tests/visual/fixtures.gd. contam (fixture_toxic): the toxic neuron is dragged into the first
## receptor's reach (contamination link, alarm glow, HUD hint). dstrain / dsnap (fixture_diseased):
## the first diseased dendrite is stretched to 90 % of its strain range (cracks, tremble, embers) /
## past its break length (snap effect, captured shortly after). measure: the developer measurement
## tag is shown (rows go to a throwaway CSV).
## T8.6: boss keeps the boss intro card on screen (capture about 1 s after the load); toxicboom
## (hard toxic missions) drags a toxic neuron into a receptor's reach and captures the overload.

const LevelScene := preload("res://scenes/level/level.tscn")
const PerfProbe := preload("res://tests/visual/perf_probe.gd")
const Fixtures := preload("res://tests/visual/fixtures.gd")
const PERF_WARMUP_FRAMES := 60
const PERF_SECONDS := 5.0

var _frames := 0
var _target := 90
var _mode := "play"
var _out := "user://capture.png"
var _level: Level
var _saved_reduced_motion := false
var _probe: PerfProbe
var _drag_id := -1
var _drag_center := Vector2.ZERO


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
	elif _mode == "glow_alt":
		_add_environment_glow(true)
	if _mode.begins_with("perf"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_level = LevelScene.instantiate()
	add_child(_level)
	var data := Fixtures.load_fixture(mission) if Fixtures.is_fixture(mission) else GameState.get_level(mission)
	if _mode in ["approach", "explode"] and data.lethal_edges.is_empty() and data.lethal_obstacles.is_empty():
		# Debug only: a copy with the right play-area side lethal.
		data = data.duplicate(true)
		data.lethal_edges = PackedInt32Array([1])
	if _mode == "explode":
		_target = maxi(_target, 90)
	_level.load_level(data)
	if _mode == "measure":  # MEASURE-MODE
		_level.get_measurement().csv_path = "user://capture_measure.csv"  # MEASURE-MODE
		_level.get_measurement().set_enabled(true)  # MEASURE-MODE
	if _mode != "boss":
		_level.get_hud().hide_story()
		_level.get_controller().start_playing()


func _process(_delta: float) -> void:
	_frames += 1
	if _mode.begins_with("perf"):
		_process_perf()
		return
	if _frames == _target / 2:
		_trigger()
	if _frames == _target:
		_capture_and_quit()


func _process_perf() -> void:
	if _mode == "perf_drag":
		_drag_step()
	if _frames == PERF_WARMUP_FRAMES:
		_probe = PerfProbe.new()
		_probe.start()
	elif _probe != null:
		_probe.sample()
		if _probe.elapsed() >= PERF_SECONDS:
			print(_probe.report("%s %s" % [_mode, GameState.current_mission]))
			_capture_and_quit()


## Drags the first movable neuron around a small circle (the model resolves collisions).
func _drag_step() -> void:
	var model := _level.get_controller().get_model()
	if _drag_id < 0:
		for id in model.get_neuron_ids():
			if not model.is_fixed(id):
				_drag_id = id
				break
		_drag_center = model.get_neuron_position(_drag_id)
		model.grab(_drag_id)
	var angle := _frames * 0.05
	model.drag_to(_drag_center + Vector2(cos(angle), sin(angle)) * 90.0)


func _capture_and_quit() -> void:
	var image := get_viewport().get_texture().get_image()
	var error := image.save_png(_out)
	print("capture_level: saved %s (%s)" % [_out, error_string(error)])
	GameState.reduced_motion = _saved_reduced_motion
	get_tree().quit()


## Experiment for T4.4/T4.7: screen-wide WorldEnvironment glow over the 2D canvas.
## Result 2026-10-07 (Godot 4.7.2, GL Compatibility, Intel UHD 600 / OpenGL 3.3): the whole
## background turns into a checkerboard artifact, so the game does not use it and relies on
## additive / premultiplied blending in its shaders instead. Re-checked in T4.7 (see
## odd/tasks/aesthetics.md) with this setup and an alternative one (glow_alt: additive blend,
## only the two finest levels, threshold 1.0, no bloom): both show the artifact, still not used.
func _add_environment_glow(alternative := false) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CANVAS
	environment.glow_enabled = true
	environment.glow_intensity = 1.0
	environment.glow_strength = 1.2
	environment.glow_bloom = 0.15
	environment.glow_hdr_threshold = 0.7
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	if alternative:
		environment.glow_bloom = 0.0
		environment.glow_hdr_threshold = 1.0
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		for level in 7:
			environment.set_glow_level(level, 1.0 if level < 2 else 0.0)
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
		"approach", "explode":
			_drive_to_lethal(model, 8.0 if _mode == "approach" else -20.0)
		"link", "strain":
			_drive_to_receptor(model, 0.45 if _mode == "link" else 0.96)
		"contam":
			_drive_toxic_into_reach(model)
		"toxicboom":
			_drive_toxic_into_reach(model)
			_frames = maxi(_frames, _target - 30)
		"dstrain", "dsnap":
			_drive_diseased(model, 0.9 if _mode == "dstrain" else 1.2)


## Pulls the movable neuron closest to the first receptor into its reach, ending at the given
## strain (0.45: freshly formed link, captured a few frames later; 0.96: near the limit).
func _drive_to_receptor(model: PuzzleModel, strain: float) -> void:
	var receptors := model.get_receptor_ids()
	if receptors.is_empty():
		return
	var receptor := receptors[0]
	var center := model.get_neuron_position(receptor)
	var best := -1
	for id in model.get_neuron_ids():
		if model.is_fixed(id) or model.get_links(receptor).has(id):
			continue
		if best < 0 or model.get_neuron_position(id).distance_to(center) \
				< model.get_neuron_position(best).distance_to(center):
			best = id
	if best < 0:
		return
	var direction := (model.get_neuron_position(best) - center).normalized()
	model.grab(best)
	_level.get_controller().get_neuron_view(best).set_grabbed(true)
	var distance := model.get_neuron_radius() + model.get_receptor_reach(receptor) * strain
	model.drag_to(center + direction * distance)
	_frames = maxi(_frames, _target - 12)


## Grabs the movable neuron closest to a lethal wall and drags it straight towards the wall
## until its surface gap is gap (negative: into the wall, which destroys it). Frames keep
## running so the capture shows the warning glow or the explosion (explode captures about
## 0.4 s after contact).
func _drive_to_lethal(model: PuzzleModel, gap: float) -> void:
	var best := -1
	var best_gap := INF
	for id in model.get_neuron_ids():
		if model.is_fixed(id):
			continue
		var g := PuzzleModel.lethal_gap(model.get_neuron_position(id), model.get_neuron_radius(),
			model.get_lethal_segments())
		if g < best_gap:
			best_gap = g
			best = id
	if best < 0:
		return
	var from := model.get_neuron_position(best)
	var wall := model.nearest_lethal_point(from)
	var direction := (wall - from).normalized()
	model.grab(best)
	_level.get_controller().get_neuron_view(best).set_grabbed(true)
	model.drag_to(wall - direction * (model.get_neuron_radius() + gap))
	if _mode == "explode":
		_frames = _target - 26


## Drags the first toxic neuron into the first receptor's reach (contamination).
func _drive_toxic_into_reach(model: PuzzleModel) -> void:
	var receptors := model.get_receptor_ids()
	if receptors.is_empty():
		return
	var receptor := receptors[0]
	for id in model.get_neuron_ids():
		if not model.is_toxic(id):
			continue
		var center := model.get_neuron_position(receptor)
		var direction := (model.get_neuron_position(id) - center).normalized()
		model.grab(id)
		_level.get_controller().get_neuron_view(id).set_grabbed(true)
		model.drag_to(center + direction * (model.get_neuron_radius() + model.get_receptor_reach(receptor) * 0.9))
		_frames = maxi(_frames, _target - 20)
		return


## Stretches the first diseased dendrite along its own direction to rest + ratio * (max - rest);
## a ratio above 1 breaks it. The grabbed end is the second endpoint.
func _drive_diseased(model: PuzzleModel, ratio: float) -> void:
	var edges := model.get_diseased_edges()
	if edges.is_empty():
		return
	var edge_id := edges[0]
	var data: DendriteData = _level.get_controller().get_level().dendrites[edge_id]
	var ends := model.get_edge_endpoints(edge_id)
	var anchor := model.get_neuron_position(ends.x)
	var direction := (model.get_neuron_position(ends.y) - anchor).normalized()
	model.grab(ends.y)
	_level.get_controller().get_neuron_view(ends.y).set_grabbed(true)
	model.drag_to(anchor + direction * (data.rest_length + ratio * (data.max_length - data.rest_length)))
	if _mode == "dsnap":
		_frames = _target - 9
