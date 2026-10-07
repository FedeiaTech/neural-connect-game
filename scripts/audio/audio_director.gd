class_name AudioDirector
extends Node
## Plays the procedural sounds (SDD 5.4 audio). Scene-local, not an autoload (SDD 8.4 allows only
## GameState): it lives under Main and ScreenHost hands it every screen it creates
## (bind_ui for menus, bind_level for missions). It only listens to signals those screens already
## emit, so views and rules hold no audio logic:
##   Buttons (any BaseButton): pressed -> ui_click; mouse_entered / focus_entered -> ui_hover
##     (muted for UI_QUIET_TIME after binding, so the focus a screen grabs on open is silent).
##   InputController: grab_started -> grab; grab_ended -> release (and the tension tone stops).
##   PuzzleModel (rebound on every rebuild via LevelController.model_built): neuron_blocked ->
##     blocked (throttled); crossings_changed with fewer crossings -> chime; tension_changed ->
##     tension tone whose pitch and volume follow the highest tension ratio; edge_broke -> snap;
##     crossing_points_changed -> buzz loop while crossings exist (volume follows the count,
##     capped; fades out when resolved); hazard_proximity_changed -> alarm loop whose pitch and
##     volume follow the highest proximity (stops on release); neuron_destroyed -> explode.
##   LevelController.level_completed -> complete. Hud.star_revealed(i) -> star, pitched up per star.
## The ambient drone loops on the Music bus from start; everything else uses the SFX bus. Both
## buses come from res://default_bus_layout.tres and feed Master (the settings volume).
## Streams come from SoundBank, rendered once on a WorkerThreadPool task (pure synthesis, no
## scene access) and handed over on the main thread when done (sounds_ready); the drone then fades
## in. A sound requested before that is rendered on the spot. sound_played(name) reports every
## sound started (used by tests). Runs with PROCESS_MODE_ALWAYS so the pause menu still sounds.

signal sound_played(sound: StringName)
signal sounds_ready()

const MUSIC_BUS := &"Music"
const SFX_BUS := &"SFX"
const SILENT_DB := -80.0
const AMBIENT_DB := -12.0
const AMBIENT_FADE_IN := 3.0
## Per-sound player volumes (dB); the tension tone is set dynamically.
const VOLUMES: Dictionary[StringName, float] = {
	&"grab": -8.0, &"release": -10.0, &"blocked": -14.0, &"snap": -4.0, &"chime": -10.0,
	&"complete": -6.0, &"star": -8.0, &"ui_hover": -18.0, &"ui_click": -12.0,
}
const POLYPHONY := 4
## The tension tone is silent below this ratio and rises to TENSION_MAX_DB at the limit.
const TENSION_AUDIBLE_START := 0.3
const TENSION_PITCH_MIN := 0.7
const TENSION_PITCH_MAX := 2.0
const TENSION_MIN_DB := -30.0
const TENSION_MAX_DB := -9.0
const STAR_PITCHES: Array[float] = [1.0, 1.122, 1.26]
## Crossing buzz (T7.1): BUZZ_MIN_DB with one crossing, rising to BUZZ_MAX_DB at BUZZ_FULL_COUNT.
const BUZZ_MIN_DB := -27.0
const BUZZ_MAX_DB := -18.0
const BUZZ_FULL_COUNT := 6
const BUZZ_FADE_IN := 0.35
const BUZZ_FADE_OUT := 0.6
## Lethal-wall alarm (T7.2): audible from ALARM_AUDIBLE_START proximity, pitch and volume rise
## towards contact.
const ALARM_AUDIBLE_START := 0.15
const ALARM_PITCH_MIN := 0.8
const ALARM_PITCH_MAX := 1.6
const ALARM_MIN_DB := -32.0
const ALARM_MAX_DB := -11.0
const BLOCKED_COOLDOWN := 0.12
const CHIME_COOLDOWN := 0.25
const HOVER_COOLDOWN := 0.04
const UI_QUIET_TIME := 0.25

var _players: Dictionary[StringName, AudioStreamPlayer] = {}
var _last_play_msec: Dictionary[StringName, int] = {}
var _tension_ratios: Dictionary[int, float] = {}
var _tension_on := false
var _crossing_count := 0
var _ui_quiet_until_msec := 0
var _bound_buttons: Dictionary[int, bool] = {}
var _ambient_tween: Tween
var _sounds_ready := false
## Worker task rendering the missing streams (-1 when none). The worker only writes _built;
## the main thread reads it after the task completed.
var _build_task := -1
var _built: Dictionary = {}
var _ambient_on := false
var _buzz_on := false
var _buzz_target_db := SILENT_DB
var _buzz_tween: Tween
var _alarm_on := false
## Hazard proximity per neuron (only moved neurons report it).
var _hazard: Dictionary[int, float] = {}
## False under --headless: the Dummy audio driver never mixes, so a started playback would never
## be released (reported as leaked at exit). Logic, signals and parameters still run.
var _can_output := DisplayServer.get_name() != "headless"


## Pitch scale of the tension tone for a tension ratio (0 slack, 1 about to break).
static func tension_pitch(ratio: float) -> float:
	var t := clampf(ratio, 0.0, 1.0)
	return lerpf(TENSION_PITCH_MIN, TENSION_PITCH_MAX, t * t)


static func is_tension_audible(ratio: float) -> bool:
	return ratio >= TENSION_AUDIBLE_START


static func tension_volume_db(ratio: float) -> float:
	var t := clampf((ratio - TENSION_AUDIBLE_START) / (1.0 - TENSION_AUDIBLE_START), 0.0, 1.0)
	return lerpf(TENSION_MIN_DB, TENSION_MAX_DB, t)


## Buzz volume for a number of crossing pairs: silent at 0, then a gentle capped rise.
static func buzz_volume_db(count: int) -> float:
	if count <= 0:
		return SILENT_DB
	var t := clampf(float(count - 1) / (BUZZ_FULL_COUNT - 1), 0.0, 1.0)
	return lerpf(BUZZ_MIN_DB, BUZZ_MAX_DB, t)


static func is_alarm_audible(proximity: float) -> bool:
	return proximity >= ALARM_AUDIBLE_START


static func alarm_pitch(proximity: float) -> float:
	return lerpf(ALARM_PITCH_MIN, ALARM_PITCH_MAX, clampf(proximity, 0.0, 1.0))


static func alarm_volume_db(proximity: float) -> float:
	var t := clampf((proximity - ALARM_AUDIBLE_START) / (1.0 - ALARM_AUDIBLE_START), 0.0, 1.0)
	return lerpf(ALARM_MIN_DB, ALARM_MAX_DB, sqrt(t))


static func star_pitch(index: int) -> float:
	return STAR_PITCHES[clampi(index, 0, STAR_PITCHES.size() - 1)]


func _init() -> void:
	name = "AudioDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	for sound in SoundBank.NAMES:
		_make_player(sound)
	var missing: Array[StringName] = []
	for sound in SoundBank.NAMES:
		if not SoundBank.is_built(sound):
			missing.append(sound)
	if missing.is_empty():
		_finish_build()
		set_process(false)
	else:
		_build_task = WorkerThreadPool.add_task(_build_streams.bind(missing), false, "AudioDirector sounds")


## Stops every voice on the way out: a playback still running at quit is reported as leaked.
func _exit_tree() -> void:
	_wait_for_build()
	if _ambient_tween != null:
		_ambient_tween.kill()
	if _buzz_tween != null:
		_buzz_tween.kill()
	_buzz_on = false
	_buzz_target_db = SILENT_DB
	_alarm_on = false
	for player: AudioStreamPlayer in _players.values():
		player.stop()
	_tension_on = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_wait_for_build()


## Polls the worker; hands the streams over on the main thread once it is done.
func _process(_delta: float) -> void:
	if _build_task < 0 or not WorkerThreadPool.is_task_completed(_build_task):
		return
	_wait_for_build()
	_finish_build()
	set_process(false)


func are_sounds_ready() -> bool:
	return _sounds_ready


func get_player(sound: StringName) -> AudioStreamPlayer:
	return _players.get(sound)


func is_tension_playing() -> bool:
	return _tension_on


func is_ambient_playing() -> bool:
	return _ambient_on


## True while crossings exist (the loop may still be fading in).
func is_buzz_playing() -> bool:
	return _buzz_on


func get_buzz_target_db() -> float:
	return _buzz_target_db


func is_alarm_playing() -> bool:
	return _alarm_on


## True right after bind_ui(), while hover sounds are still muted.
func is_ui_quiet() -> bool:
	return Time.get_ticks_msec() < _ui_quiet_until_msec


## Starts a one-shot sound at the given pitch and reports it.
func play(sound: StringName, pitch := 1.0) -> void:
	var player: AudioStreamPlayer = _players.get(sound)
	if player == null:
		push_warning("AudioDirector: unknown sound '%s'." % sound)
		return
	_ensure_stream(sound)
	player.pitch_scale = pitch
	_start(player)
	_last_play_msec[sound] = Time.get_ticks_msec()
	sound_played.emit(sound)


## Hooks every BaseButton under root to the UI sounds (each button only once).
func bind_ui(root: Node) -> void:
	_ui_quiet_until_msec = Time.get_ticks_msec() + int(UI_QUIET_TIME * 1000.0)
	_bind_buttons(root)


## Hooks a mission: input, model (and every rebuilt model), completion, star reveal and HUD buttons.
func bind_level(level: Level) -> void:
	var controller := level.get_controller()
	controller.model_built.connect(_bind_model)
	if controller.get_model() != null:
		_bind_model(controller.get_model())
	controller.level_completed.connect(_on_level_completed)
	controller.level_restart_requested.connect(_stop_tension)
	var input := level.get_input_controller()
	input.grab_started.connect(_on_grab_started)
	input.grab_ended.connect(_on_grab_ended)
	level.get_hud().star_revealed.connect(_on_star_revealed)
	bind_ui(level.get_hud())


# --- Internals ---------------------------------------------------------------

## Worker thread: pure synthesis only, no scene or cache access.
func _build_streams(names: Array[StringName]) -> void:
	var built := {}
	for sound in names:
		built[sound] = SoundBank.build(sound)
	_built = built


func _wait_for_build() -> void:
	if _build_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_build_task)
		_build_task = -1
		# Keep the work even if this director goes away before using it.
		SoundBank.store(_built)


func _finish_build() -> void:
	SoundBank.store(_built)
	_built = {}
	for sound in SoundBank.NAMES:
		_ensure_stream(sound)
	_sounds_ready = true
	_start_ambient()
	sounds_ready.emit()

func _make_player(sound: StringName) -> void:
	var player := AudioStreamPlayer.new()
	player.name = String(sound).to_pascal_case()
	player.bus = MUSIC_BUS if sound == &"ambient" else SFX_BUS
	player.volume_db = VOLUMES.get(sound, -8.0)
	player.max_polyphony = 1 if SoundBank.LOOPS.has(sound) else POLYPHONY
	add_child(player)
	_players[sound] = player


func _start(player: AudioStreamPlayer) -> void:
	if _can_output:
		player.play()


func _ensure_stream(sound: StringName) -> void:
	var player: AudioStreamPlayer = _players.get(sound)
	if player != null and player.stream == null:
		player.stream = SoundBank.get_stream(sound)


func _start_ambient() -> void:
	var player: AudioStreamPlayer = _players[&"ambient"]
	_ensure_stream(&"ambient")
	player.volume_db = SILENT_DB
	_start(player)
	_ambient_on = true
	_ambient_tween = create_tween()
	_ambient_tween.tween_property(player, ^"volume_db", AMBIENT_DB, AMBIENT_FADE_IN) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _bind_buttons(node: Node) -> void:
	if node is BaseButton:
		var button := node as BaseButton
		var id := button.get_instance_id()
		if not _bound_buttons.has(id):
			_bound_buttons[id] = true
			button.pressed.connect(play.bind(&"ui_click", 1.0))
			button.mouse_entered.connect(_on_ui_hover.bind(button))
			button.focus_entered.connect(_on_ui_hover.bind(button))
	for child in node.get_children():
		_bind_buttons(child)


func _bind_model(model: PuzzleModel) -> void:
	_stop_tension()
	_stop_alarm()
	_crossing_count = model.get_crossing_edges().size()
	_set_buzz(model.get_crossing_count())
	model.neuron_blocked.connect(_on_neuron_blocked)
	model.crossings_changed.connect(_on_crossings_changed)
	model.crossing_points_changed.connect(_on_crossing_points_changed)
	model.hazard_proximity_changed.connect(_on_hazard_proximity_changed)
	model.neuron_destroyed.connect(_on_neuron_destroyed)
	model.tension_changed.connect(_on_tension_changed)
	model.edge_broke.connect(_on_edge_broke)


func _cooled_down(sound: StringName, cooldown: float) -> bool:
	return Time.get_ticks_msec() - _last_play_msec.get(sound, -100000) >= int(cooldown * 1000.0)


func _on_ui_hover(button: BaseButton) -> void:
	if button.disabled or Time.get_ticks_msec() < _ui_quiet_until_msec:
		return
	if _cooled_down(&"ui_hover", HOVER_COOLDOWN):
		play(&"ui_hover")


func _on_grab_started(_id: int) -> void:
	play(&"grab")


func _on_grab_ended(_id: int) -> void:
	_stop_tension()
	_stop_alarm()
	play(&"release")


func _on_neuron_blocked(_id: int, _contact: Vector2) -> void:
	if _cooled_down(&"blocked", BLOCKED_COOLDOWN):
		play(&"blocked")


func _on_crossings_changed(crossing_edges: Array[int], _involved: Array[int]) -> void:
	var count := crossing_edges.size()
	if count < _crossing_count and _cooled_down(&"chime", CHIME_COOLDOWN):
		play(&"chime")
	_crossing_count = count


func _on_crossing_points_changed(points: PackedVector2Array) -> void:
	_set_buzz(points.size())


## Fades the buzz loop towards the volume for count crossings; stops it once faded out.
func _set_buzz(count: int) -> void:
	var target := buzz_volume_db(count)
	if target == _buzz_target_db:
		return
	_buzz_target_db = target
	var player: AudioStreamPlayer = _players.get(&"buzz")
	if player == null:
		return
	if _buzz_tween != null:
		_buzz_tween.kill()
		_buzz_tween = null
	if count > 0 and not _buzz_on:
		_buzz_on = true
		_ensure_stream(&"buzz")
		player.volume_db = SILENT_DB
		_start(player)
	elif count <= 0:
		_buzz_on = false
	if not is_inside_tree():
		player.volume_db = target
		if not _buzz_on:
			player.stop()
		return
	_buzz_tween = create_tween()
	_buzz_tween.tween_property(player, ^"volume_db", target, BUZZ_FADE_IN if _buzz_on else BUZZ_FADE_OUT) \
		.set_trans(Tween.TRANS_SINE)
	if not _buzz_on:
		_buzz_tween.tween_callback(player.stop)


func _on_hazard_proximity_changed(id: int, proximity: float) -> void:
	_hazard[id] = proximity
	var highest := 0.0
	for value: float in _hazard.values():
		highest = maxf(highest, value)
	var player: AudioStreamPlayer = _players[&"alarm"]
	if not is_alarm_audible(highest):
		_stop_alarm()
		return
	_ensure_stream(&"alarm")
	player.pitch_scale = alarm_pitch(highest)
	player.volume_db = alarm_volume_db(highest)
	if not _alarm_on:
		_alarm_on = true
		_start(player)


func _stop_alarm() -> void:
	_hazard.clear()
	if _alarm_on:
		_players[&"alarm"].stop()
		_alarm_on = false


func _on_neuron_destroyed(_id: int, _contact: Vector2) -> void:
	_stop_alarm()
	_stop_tension()
	play(&"explode")


func _on_tension_changed(edge_id: int, ratio: float) -> void:
	_tension_ratios[edge_id] = ratio
	var highest := 0.0
	for value: float in _tension_ratios.values():
		highest = maxf(highest, value)
	_update_tension(highest)


func _update_tension(ratio: float) -> void:
	var player: AudioStreamPlayer = _players[&"tension"]
	if not is_tension_audible(ratio):
		if _tension_on:
			player.stop()
			_tension_on = false
		return
	_ensure_stream(&"tension")
	player.pitch_scale = tension_pitch(ratio)
	player.volume_db = tension_volume_db(ratio)
	if not _tension_on:
		_tension_on = true
		_start(player)


func _stop_tension() -> void:
	_tension_ratios.clear()
	if _tension_on:
		_players[&"tension"].stop()
		_tension_on = false


func _on_edge_broke(_edge_id: int) -> void:
	_stop_tension()
	play(&"snap")


func _on_level_completed(_result: LevelResult) -> void:
	_stop_tension()
	_stop_alarm()
	play(&"complete")


func _on_star_revealed(index: int) -> void:
	play(&"star", star_pitch(index))
