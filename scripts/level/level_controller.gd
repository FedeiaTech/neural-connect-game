class_name LevelController
extends Node
## Owns the PuzzleModel of one mission (SDD 8.4-8.6): builds it from LevelData, creates one
## view per neuron / dendrite / obstacle, runs the level state machine, counts time (PLAYING
## only) and moves, restarts without reloading the scene and scores the result.
##
## State machine (enum, SDD 8.1):
##   INTRO      story text shown, input off, timer stopped. start_playing() -> PLAYING.
##   PLAYING    input on, timer running. solved -> COMPLETE, edge_broke -> RESTARTING.
##   COMPLETE   input off, timer stopped, result emitted. restart() -> PLAYING.
##   RESTARTING input off; after a broken dendrite it waits BREAK_RESTART_DELAY, then restart().
## Restart never shows the story again.

signal move_count_changed(n: int)
signal time_changed(seconds: float)
signal level_completed(result: LevelResult)
signal level_restart_requested()
## Emitted after every (re)build with the new model, so listeners (e.g. AudioDirector) can rebind.
signal model_built(model: PuzzleModel)

enum State { INTRO, PLAYING, COMPLETE, RESTARTING }

const BREAK_RESTART_DELAY := 0.6
## Space kept free around the play area; the top margin leaves room for the HUD bar.
const FIT_MARGIN := 48.0
const FIT_TOP_MARGIN := 96.0

const NeuronScene := preload("res://scenes/views/neuron_view.tscn")
const DendriteScene := preload("res://scenes/views/dendrite_view.tscn")
const ObstacleScene := preload("res://scenes/views/obstacle_view.tscn")

@export var playfield: Node2D
@export var boundary: BoundaryView
@export var obstacles_root: Node2D
@export var dendrites_root: Node2D
@export var neurons_root: Node2D
@export var input_controller: InputController
## Optional one-off effects layer (break flash, completion wave).
@export var fx: LevelFx
## Optional crossing spark markers (T7.1).
@export var sparks: CrossingSparksView

var _level: LevelData
var _model: PuzzleModel
var _state := State.INTRO
var _elapsed := 0.0
var _move_count := 0
var _restart_countdown := 0.0
var _neuron_views: Dictionary[int, NeuronView] = {}
## Indexed by edge id.
var _dendrite_views: Array[DendriteView] = []


func _ready() -> void:
	if input_controller != null:
		input_controller.grab_started.connect(_on_grab_started)
		input_controller.grab_ended.connect(_on_grab_ended)
		input_controller.restart_requested.connect(_on_restart_requested)


func _process(delta: float) -> void:
	tick(delta)


## Starts a mission. With story text the level waits in INTRO for start_playing().
func load_level(level: LevelData) -> void:
	_level = level
	_build()
	_fit_playfield()
	_set_state(State.INTRO if not level.story_text.strip_edges().is_empty() else State.PLAYING)


## Leaves INTRO (story dismissed). Ignored in any other state.
func start_playing() -> void:
	if _state == State.INTRO:
		_set_state(State.PLAYING)


## Rebuilds the model and views from the LevelData and resets counters (no scene reload).
func restart() -> void:
	if _level == null:
		return
	_set_state(State.RESTARTING)
	_build()
	level_restart_requested.emit()
	_set_state(State.PLAYING)


## Advances the level clock. Called every frame by _process; public for tests.
func tick(delta: float) -> void:
	match _state:
		State.PLAYING:
			_elapsed += delta
			time_changed.emit(_elapsed)
		State.RESTARTING:
			if _restart_countdown > 0.0:
				_restart_countdown -= delta
				if _restart_countdown <= 0.0:
					restart()


func get_state() -> State:
	return _state


func get_model() -> PuzzleModel:
	return _model


func get_level() -> LevelData:
	return _level


func get_elapsed_time() -> float:
	return _elapsed


func get_move_count() -> int:
	return _move_count


func get_neuron_view(id: int) -> NeuronView:
	return _neuron_views.get(id)


func get_dendrite_view(edge_id: int) -> DendriteView:
	if edge_id < 0 or edge_id >= _dendrite_views.size():
		return null
	return _dendrite_views[edge_id]


## Transform that centers bounds inside area, scaling down (never up) to fit.
static func compute_fit(bounds: Rect2, area: Rect2) -> Transform2D:
	var scale := 1.0
	if bounds.size.x > 0.0 and bounds.size.y > 0.0:
		scale = minf(1.0, minf(area.size.x / bounds.size.x, area.size.y / bounds.size.y))
	var origin := area.get_center() - bounds.get_center() * scale
	return Transform2D(0.0, Vector2(scale, scale), 0.0, origin)


## Region of the base viewport (project size, stretch mode canvas_items) the playfield fits in.
static func get_fit_area() -> Rect2:
	var size := Vector2(
		ProjectSettings.get_setting("display/window/size/viewport_width", 1920),
		ProjectSettings.get_setting("display/window/size/viewport_height", 1080))
	return Rect2(FIT_MARGIN, FIT_TOP_MARGIN,
		size.x - 2.0 * FIT_MARGIN, size.y - FIT_TOP_MARGIN - FIT_MARGIN)


# --- Internals ---------------------------------------------------------------

func _set_state(state: State) -> void:
	_state = state
	if input_controller != null:
		input_controller.set_enabled(state == State.PLAYING)


func _build() -> void:
	_model = PuzzleModel.from_level(_level)
	_model.solved.connect(_on_solved)
	_model.edge_broke.connect(_on_edge_broke)
	if input_controller != null:
		input_controller.bind(_model)
	_build_views()
	_elapsed = 0.0
	_move_count = 0
	_restart_countdown = 0.0
	move_count_changed.emit(_move_count)
	time_changed.emit(_elapsed)
	model_built.emit(_model)


func _build_views() -> void:
	for container: Node2D in [obstacles_root, dendrites_root, neurons_root]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
	_neuron_views = {}
	_dendrite_views = []
	var membranes: Array[MembraneView] = [boundary]
	var feedback := _level.show_crossing_feedback
	boundary.setup(_model)
	for polygon in _model.get_obstacles():
		var obstacle: ObstacleView = ObstacleScene.instantiate()
		obstacles_root.add_child(obstacle)
		obstacle.setup(polygon, _model)
		membranes.append(obstacle)
	for edge_id in _model.get_edge_count():
		var dendrite: DendriteView = DendriteScene.instantiate()
		dendrites_root.add_child(dendrite)
		dendrite.setup(edge_id, _model, feedback)
		_dendrite_views.append(dendrite)
	for id in _model.get_neuron_ids():
		var neuron: NeuronView = NeuronScene.instantiate()
		neurons_root.add_child(neuron)
		neuron.setup(id, _model, feedback)
		_neuron_views[id] = neuron
	if sparks != null:
		sparks.setup(_model, feedback)
	if fx != null:
		fx.setup(_model, _neuron_views, _dendrite_views, membranes)


func _fit_playfield() -> void:
	var play_area := _model.get_play_area()
	if play_area.is_empty():
		return
	var bounds := Rect2(play_area[0], Vector2.ZERO)
	for point in play_area:
		bounds = bounds.expand(point)
	playfield.transform = compute_fit(bounds, get_fit_area())


func _sync_move_count() -> void:
	var count := _model.get_move_count()
	if count != _move_count:
		_move_count = count
		move_count_changed.emit(count)


func _on_grab_started(id: int) -> void:
	var view := get_neuron_view(id)
	if view != null:
		view.set_grabbed(true)


func _on_grab_ended(id: int) -> void:
	var view := get_neuron_view(id)
	if view != null:
		view.set_grabbed(false)
	_sync_move_count()


func _on_restart_requested() -> void:
	if _state != State.INTRO:
		restart()


func _on_solved() -> void:
	_sync_move_count()
	_set_state(State.COMPLETE)
	level_completed.emit(LevelResult.create(_move_count, _elapsed, _level.par_moves, _level.par_time))


func _on_edge_broke(_edge_id: int) -> void:
	_set_state(State.RESTARTING)
	_restart_countdown = BREAK_RESTART_DELAY
