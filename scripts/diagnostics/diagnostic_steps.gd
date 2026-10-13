class_name DiagnosticSteps
extends RefCounted
## The checks of the diagnostic battery, in the order they run. Each one isolates one suspect of the
## native crash seen on the Moto G15 (SIGSEGV about 20 s after launch, on OpenGL ES and on Vulkan):
## the bare app, the menu, each custom draw path (triangle arrays, meshes, the neuron and dendrite
## shaders), the audio (one-shots, loops, the synthesis worker threads), transitions, screen changes,
## a simulated game and, last, two manual steps where the player touches the screen. A step that
## crashes is the one that holds the cause; the matrix of passed and crashed steps narrows it down.

const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")
const BrandIntroScene := preload("res://scenes/screens/brand_intro.tscn")
const BackgroundScene := preload("res://scenes/views/background.tscn")
const LevelScene := preload("res://scenes/level/level.tscn")
const NeuronScene := preload("res://scenes/views/neuron_view.tscn")
const DendriteScene := preload("res://scenes/views/dendrite_view.tscn")
const IrisShader := preload("res://assets/shaders/iris_fade.gdshader")
## Loaded at run time: the main scene reaches the screens that reach this battery.
const MAIN_SCENE_PATH := "res://scenes/main.tscn"


static func build_all() -> Array[DiagnosticStep]:
	var steps: Array[DiagnosticStep] = [
		BaselineEmpty.new(), IdleMenu.new(), BackgroundOnly.new(), SoftLineTriangles.new(),
		PlainMeshes.new(), NeuronViewsOnly.new(), DendriteViewsOnly.new(), LevelStatic.new(),
		LevelSimulatedPlay.new(), ParticleBursts.new(), AudioOneShots.new(), AudioLoops.new(),
		WorkerSynth.new(), TransitionIris.new(), MissionSelectLoop.new(), BrandLogo.new(),
		NavigationNoAudio.new(), NavigationFullApp.new(), ManualLevel.new(), ManualFullApp.new(),
	]
	return steps


## A mission with enough neurons to be a fair load (the first one with at least min_neurons).
static func pick_level(min_neurons: int) -> LevelData:
	var fallback: LevelData = null
	for id in GameState.campaign.get_mission_ids():
		var level := GameState.get_level(id)
		if level == null:
			continue
		if fallback == null:
			fallback = level
		if level.neurons.size() >= min_neurons:
			return level
	return fallback


## The transform the Level scene gives its playfield: the model's play area fitted to the screen.
static func fit_transform(model: PuzzleModel) -> Transform2D:
	var area := model.get_play_area()
	if area.is_empty():
		return Transform2D.IDENTITY
	var bounds := Rect2(area[0], Vector2.ZERO)
	for point in area:
		bounds = bounds.expand(point)
	return LevelController.compute_fit(bounds, LevelController.get_fit_area())


static func fill(control: Control) -> Control:
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control


## A Transition built in code (the scene has it inline in main.tscn): a black rect drawing the iris shader.
static func make_transition() -> Transition:
	var transition := Transition.new()
	transition.layer = 5
	var fade := ColorRect.new()
	fade.name = "Fade"
	fade.color = Color.BLACK
	var material := ShaderMaterial.new()
	material.shader = IrisShader
	fade.material = material
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	transition.add_child(fade)
	return transition


# --- Steps ---------------------------------------------------------------------------

## Nothing but a black rect: if the app dies here the cause is not in the game at all.
class BaselineEmpty extends DiagnosticStep:
	func _init() -> void:
		id = &"baseline_empty"
		title = "Nothing drawn at all"
		duration = 8.0

	func begin(stage: Control) -> void:
		var rect := ColorRect.new()
		rect.color = Color(0.02, 0.03, 0.05)
		_own(stage, DiagnosticSteps.fill(rect))


## The real main menu, left alone: the first report of the crash was taken here.
class IdleMenu extends DiagnosticStep:
	func _init() -> void:
		id = &"idle_menu"
		title = "Main menu idle, no input"
		duration = 25.0

	func begin(stage: Control) -> void:
		_own(stage, DiagnosticSteps.fill(DiagnosticSteps.MainMenuScene.instantiate()))


class BackgroundOnly extends DiagnosticStep:
	func _init() -> void:
		id = &"background_only"
		title = "Shared background (spores, vignette)"
		duration = 10.0

	func begin(stage: Control) -> void:
		_own(stage, DiagnosticSteps.BackgroundScene.instantiate())


## Triangle arrays through RenderingServer.canvas_item_add_triangle_array, redrawn every frame
## (membranes, lethal walls and dendrites draw this way).
class SoftLineTriangles extends DiagnosticStep:
	func _init() -> void:
		id = &"softline_triangles"
		title = "Soft line bands drawn as triangle arrays every frame"
		duration = 10.0

	func begin(stage: Control) -> void:
		_own(stage, _Probe.new())

	class _Probe extends Node2D:
		var _time := 0.0

		func _process(delta: float) -> void:
			_time += delta
			queue_redraw()

		func _draw() -> void:
			var band := SoftLine.Band.new()
			for ring in 8:
				var points := PackedVector2Array()
				var center := Vector2(300.0 + 200.0 * (ring % 4), 300.0 + 280.0 * (ring / 4))
				for k in 65:
					var angle := TAU * (k % 64) / 64.0
					var radius := 90.0 + 12.0 * sin(angle * 5.0 + _time * 1.5 + ring)
					points.append(center + Vector2.from_angle(angle) * radius)
				band.add(points, Color(0.3, 0.9, 1.0, 0.4), 18.0)
			band.draw(self)


## NeuronMorphology meshes with draw_mesh and no shader (the arms of every neuron).
class PlainMeshes extends DiagnosticStep:
	func _init() -> void:
		id = &"plain_meshes"
		title = "Neuron arm meshes drawn with draw_mesh, no shader"
		duration = 10.0

	func begin(stage: Control) -> void:
		_own(stage, _Probe.new())

	class _Probe extends Node2D:
		var _meshes: Array[ArrayMesh] = []

		func _init() -> void:
			for i in 24:
				_meshes.append(NeuronMorphology.generate(i, NeuronMorphology.Kind.NORMAL).build_mesh())

		func _process(_delta: float) -> void:
			queue_redraw()

		func _draw() -> void:
			for i in _meshes.size():
				var origin := Vector2(160.0 + 220.0 * (i % 8), 200.0 + 260.0 * (i / 8))
				draw_set_transform(origin, 0.0, Vector2(70.0, 70.0))
				draw_mesh(_meshes[i], null)


## Real NeuronViews (neuron.gdshader plus the arm mesh) of a mission, without anything else.
class NeuronViewsOnly extends DiagnosticStep:
	var _model: PuzzleModel

	func _init() -> void:
		id = &"neuron_views"
		title = "Neuron views: shader and arm mesh only"
		duration = 12.0

	func begin(stage: Control) -> void:
		_model = PuzzleModel.from_level(DiagnosticSteps.pick_level(8))
		var root := Node2D.new()
		root.transform = DiagnosticSteps.fit_transform(_model)
		_own(stage, root)
		for neuron_id in _model.get_neuron_ids():
			var view: NeuronView = DiagnosticSteps.NeuronScene.instantiate()
			root.add_child(view)
			view.setup(neuron_id, _model, true)


## Real DendriteViews (dendrite.gdshader plus triangle arrays), without anything else.
class DendriteViewsOnly extends DiagnosticStep:
	var _model: PuzzleModel

	func _init() -> void:
		id = &"dendrite_views"
		title = "Dendrite views: shader and triangle arrays only"
		duration = 12.0

	func begin(stage: Control) -> void:
		_model = PuzzleModel.from_level(DiagnosticSteps.pick_level(8))
		var root := Node2D.new()
		root.transform = DiagnosticSteps.fit_transform(_model)
		_own(stage, root)
		for edge_id in _model.get_edge_count():
			var view: DendriteView = DiagnosticSteps.DendriteScene.instantiate()
			root.add_child(view)
			view.setup(edge_id, _model, true)


## A whole mission (every view, HUD, background) that nobody touches.
class LevelStatic extends DiagnosticStep:
	func _init() -> void:
		id = &"level_static"
		title = "Whole mission on screen, no input"
		duration = 12.0

	func begin(stage: Control) -> void:
		var level: Level = DiagnosticSteps.LevelScene.instantiate()
		_own(stage, level)
		level.load_level(DiagnosticSteps.pick_level(8))
		level.get_hud().hide_story()
		level.get_controller().start_playing()


## A mission played by a script that drags neurons through the model (crossings, sparks,
## highlights, bursts, links) without going through the touch input path.
class LevelSimulatedPlay extends DiagnosticStep:
	const SPEED := 700.0
	var _level: Level
	var _rng := RandomNumberGenerator.new()
	var _moving := PuzzleModel.NO_NEURON
	var _target := Vector2.ZERO
	var _pause := 0.5

	func _init() -> void:
		id = &"level_simulated_play"
		title = "Mission played by script: neurons dragged through the model"
		duration = 16.0
		_rng.seed = 7

	func begin(stage: Control) -> void:
		_level = DiagnosticSteps.LevelScene.instantiate()
		_own(stage, _level)
		_level.load_level(DiagnosticSteps.pick_level(8))
		_level.get_hud().hide_story()
		_level.get_controller().start_playing()

	func update(delta: float, _elapsed: float) -> void:
		var controller := _level.get_controller()
		var model := controller.get_model()
		if model == null:
			return
		if controller.get_state() == LevelController.State.COMPLETE:
			controller.restart()
			_moving = PuzzleModel.NO_NEURON
			return
		if controller.get_state() != LevelController.State.PLAYING:
			_moving = PuzzleModel.NO_NEURON
			return
		if _moving == PuzzleModel.NO_NEURON:
			_pause -= delta
			if _pause > 0.0:
				return
			var ids := model.get_neuron_ids()
			var pick := ids[_rng.randi_range(0, ids.size() - 1)]
			if model.grab(pick):
				_moving = pick
				_target = model.get_neuron_position(pick) + Vector2.from_angle(_rng.randf() * TAU) \
					* _rng.randf_range(80.0, 260.0)
			_pause = 0.2
			return
		var position := model.get_neuron_position(_moving)
		var remaining := _target - position
		if remaining.length() < 8.0:
			model.release()
			_moving = PuzzleModel.NO_NEURON
			_pause = 0.2
		else:
			model.drag_to(position + remaining.limit_length(SPEED * delta))


## CPUParticles2D bursts like the spark and break effects.
class ParticleBursts extends DiagnosticStep:
	func _init() -> void:
		id = &"particle_bursts"
		title = "Particle bursts every 0.3 s"
		duration = 10.0

	func begin(stage: Control) -> void:
		_own(stage, _Probe.new())

	class _Probe extends Node2D:
		var _clock := 0.0

		func _process(delta: float) -> void:
			_clock += delta
			if _clock >= 0.3:
				_clock = 0.0
				_burst(Vector2(randf_range(200.0, 1700.0), randf_range(200.0, 900.0)))

		func _burst(at: Vector2) -> void:
			var burst := CPUParticles2D.new()
			burst.position = at
			burst.one_shot = true
			burst.explosiveness = 0.9
			burst.amount = 48
			burst.lifetime = 0.8
			burst.texture = GlowTexture.radial()
			burst.spread = 180.0
			burst.gravity = Vector2.ZERO
			burst.initial_velocity_min = 40.0
			burst.initial_velocity_max = 220.0
			burst.scale_amount_min = 0.15
			burst.scale_amount_max = 0.4
			burst.color = Color(0.6, 0.9, 1.0)
			burst.finished.connect(burst.queue_free)
			add_child(burst)
			burst.emitting = true


## Every one-shot sound of the game, one every half second, from players of this step.
class AudioOneShots extends DiagnosticStep:
	var _players: Array[AudioStreamPlayer] = []
	var _next_index := 0

	func _init() -> void:
		id = &"audio_oneshots"
		title = "Every one-shot sound played in sequence"
		duration = 12.0

	func begin(stage: Control) -> void:
		for sound in SoundBank.NAMES:
			if SoundBank.LOOPS.has(sound):
				continue
			var player := AudioStreamPlayer.new()
			player.stream = SoundBank.get_stream(sound)
			player.bus = AudioDirector.SFX_BUS
			player.volume_db = -12.0
			_own(stage, player)
			_players.append(player)

	func update(_delta: float, elapsed: float) -> void:
		if _next_index < _players.size() and elapsed >= 0.5 * _next_index:
			_players[_next_index].play()
			_next_index += 1

	func end() -> void:
		for player in _players:
			if is_instance_valid(player):
				player.stop()
		_players.clear()
		super.end()


## All the looping sounds at once.
class AudioLoops extends DiagnosticStep:
	var _players: Array[AudioStreamPlayer] = []

	func _init() -> void:
		id = &"audio_loops"
		title = "Every looping sound at the same time"
		duration = 10.0

	func begin(stage: Control) -> void:
		for sound in SoundBank.LOOPS:
			var player := AudioStreamPlayer.new()
			player.stream = SoundBank.get_stream(sound)
			player.bus = AudioDirector.MUSIC_BUS if sound == &"ambient" else AudioDirector.SFX_BUS
			player.volume_db = -14.0
			_own(stage, player)
			_players.append(player)
			player.play()

	func end() -> void:
		for player in _players:
			if is_instance_valid(player):
				player.stop()
		_players.clear()
		super.end()


## WorkerThreadPool tasks synthesizing sounds back to back (the game renders them on a worker at startup).
class WorkerSynth extends DiagnosticStep:
	const SOUNDS: Array[StringName] = [&"complete", &"boss_stinger", &"ambient", &"boss_fanfare"]
	var _tasks: Array[int] = []
	var rounds := 0

	func _init() -> void:
		id = &"worker_synth"
		title = "Sound synthesis on worker threads, repeated"
		duration = 10.0

	func begin(_stage: Control) -> void:
		_spawn()

	func update(_delta: float, _elapsed: float) -> void:
		for task in _tasks:
			if not WorkerThreadPool.is_task_completed(task):
				return
		_join()
		_spawn()

	func end() -> void:
		_join()
		super.end()

	func _spawn() -> void:
		rounds += 1
		for sound in SOUNDS:
			_tasks.append(WorkerThreadPool.add_task(_work.bind(sound), false, "diagnostics synth"))

	func _join() -> void:
		for task in _tasks:
			WorkerThreadPool.wait_for_task_completion(task)
		_tasks.clear()

	func _work(sound: StringName) -> void:
		SoundBank.build(sound)


## The iris transition (its shader) closing and opening again and again.
class TransitionIris extends DiagnosticStep:
	var _transition: Transition
	var _fade: ColorRect
	var _covering := false

	func _init() -> void:
		id = &"transition_iris"
		title = "Iris transition shader, cover and reveal repeated"
		duration = 10.0

	func begin(stage: Control) -> void:
		_transition = DiagnosticSteps.make_transition()
		_fade = _transition.get_node("Fade")
		_own(stage, _transition)

	func update(_delta: float, _elapsed: float) -> void:
		# The transition blocks input while covering; the diagnostics controls must stay usable.
		_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if _transition.is_animating():
			return
		if _covering:
			_transition.reveal()
		else:
			_transition.cover()
		_covering = not _covering


## The mission map built and freed again and again (chapter header shader, map drawing) with its
## scroll tweened when there is more than one page.
class MissionSelectLoop extends DiagnosticStep:
	const LIFETIME := 3.5
	var _stage: Control
	var _screen: MissionSelect
	var _age := 0.0
	var _page_clock := 0.0

	func _init() -> void:
		id = &"mission_select_loop"
		title = "Mission map built and freed repeatedly, scroll glide"
		duration = 14.0

	func begin(stage: Control) -> void:
		_stage = stage
		_spawn()

	func update(delta: float, _elapsed: float) -> void:
		_age += delta
		_page_clock += delta
		if _age >= LIFETIME:
			_age = 0.0
			_release()
			_spawn()
		elif _page_clock >= 1.0 and is_instance_valid(_screen):
			_page_clock = 0.0
			var scroll := _screen.get_scroll()
			var top := scroll.scroll_vertical == 0
			var tween := _screen.create_tween()
			tween.tween_property(scroll, ^"scroll_vertical", 600 if top else 0, 0.4)

	func end() -> void:
		_release()
		super.end()

	func _spawn() -> void:
		_screen = DiagnosticSteps.MissionSelectScene.instantiate()
		_screen.mobile_layout = true
		_own(_stage, _screen)

	func _release() -> void:
		if is_instance_valid(_screen):
			_owned.erase(_screen)
			if _screen.get_parent() != null:
				_screen.get_parent().remove_child(_screen)
			_screen.queue_free()


## The studio splash with its 1254x1254 logo texture.
class BrandLogo extends DiagnosticStep:
	func _init() -> void:
		id = &"brand_logo"
		title = "Studio splash, large logo texture"
		duration = 6.0

	func begin(stage: Control) -> void:
		_own(stage, DiagnosticSteps.fill(DiagnosticSteps.BrandIntroScene.instantiate()))


## Screens swapped through a ScreenHost with its own transition and no audio, as fast as it allows.
class NavigationNoAudio extends DiagnosticStep:
	var _host: ScreenHost
	var _index := 0
	var _dwell := 0.0

	func _init() -> void:
		id = &"navigation_no_audio"
		title = "Screen changes with transitions, no audio"
		duration = 16.0

	func begin(stage: Control) -> void:
		_host = ScreenHost.new()
		_host.diagnostics_enabled = false
		_host.transition = DiagnosticSteps.make_transition()
		_own(stage, _host.transition)
		_own(stage, _host)

	func update(delta: float, _elapsed: float) -> void:
		_dwell -= delta
		if _dwell > 0.0 or _host.is_busy():
			return
		_index = DiagnosticSteps.navigate(_host, _index)
		_dwell = 1.2


## The whole app (menu, map, levels, audio, transitions) in the stage, driven through its ScreenHost.
class NavigationFullApp extends DiagnosticStep:
	var _host: ScreenHost
	var _index := 0
	var _dwell := 0.0

	func _init() -> void:
		id = &"navigation_full_app"
		title = "Screen changes in the full app, with audio"
		duration = 16.0

	func begin(stage: Control) -> void:
		_host = DiagnosticSteps.add_full_app(self, stage)

	func update(delta: float, _elapsed: float) -> void:
		_dwell -= delta
		if _dwell > 0.0 or _host.is_busy():
			return
		_index = DiagnosticSteps.navigate(_host, _index)
		_dwell = 1.2


## The player plays a real mission with the real touch input; no audio.
class ManualLevel extends DiagnosticStep:
	func _init() -> void:
		id = &"manual_level"
		title = "MANUAL: play a mission by hand (touch input), no audio"
		duration = 40.0
		manual = true
		hint_key = "DIAG_HINT_PLAY"

	func begin(stage: Control) -> void:
		var level: Level = DiagnosticSteps.LevelScene.instantiate()
		_own(stage, level)
		level.load_level(GameState.get_level(GameState.campaign.first_mission_id()))
		level.get_hud().hide_story()
		level.get_controller().start_playing()


## The player uses the whole app by hand, audio included.
class ManualFullApp extends DiagnosticStep:
	func _init() -> void:
		id = &"manual_full_app"
		title = "MANUAL: use the full app by hand, with audio"
		duration = 40.0
		manual = true
		hint_key = "DIAG_HINT_APP"

	func begin(stage: Control) -> void:
		DiagnosticSteps.add_full_app(self, stage)


# --- Shared by the navigation steps ---------------------------------------------------

## The screens the navigation steps cycle through (a function, not a constant: ScreenHost reaches this
## battery through its screens, and a constant would make the two scripts depend on each other).
static func navigation_sequence() -> Array[ScreenHost.Screen]:
	var sequence: Array[ScreenHost.Screen] = [ScreenHost.Screen.MAIN_MENU, ScreenHost.Screen.MISSION_SELECT,
		ScreenHost.Screen.LEVEL, ScreenHost.Screen.MISSION_SELECT, ScreenHost.Screen.SETTINGS,
		ScreenHost.Screen.MAIN_MENU, ScreenHost.Screen.MISSION_SELECT, ScreenHost.Screen.LEVEL]
	return sequence


## Goes to the next screen of the sequence; returns the next index.
static func navigate(host: ScreenHost, index: int) -> int:
	var sequence := navigation_sequence()
	host.go_to(sequence[index % sequence.size()], GameState.campaign.first_mission_id())
	return index + 1


## Instantiates the main scene without its brand intro under the stage and returns its ScreenHost.
static func add_full_app(step: DiagnosticStep, stage: Control) -> ScreenHost:
	var main: Node = (load(MAIN_SCENE_PATH) as PackedScene).instantiate()
	main.show_brand_intro = false
	# The battery's own run must not take this inner app over (see main.gd).
	main.diagnostics_state_path = ""
	step._own(stage, main)
	var host: ScreenHost = main.get_screen_host()
	host.diagnostics_enabled = false
	return host
