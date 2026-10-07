class_name LinksView
extends Node2D
## Dynamic receptor links (T7.3, SDD 5.4), drawn additively: one glowing cyan line per link
## (keyed Vector2i(receptor_id, neuron_id) like the model).
## - Formation: the line grows from the receptor to the neuron in GROW_TIME with a cyan flash at
##   the neuron (the AudioDirector plays the synaptic click).
## - Strain: past WARNING_START the line thins towards MIN_WIDTH and flickers.
## - Crossing: same identity color and solid line (like tension dendrites); the crossing shows
##   through the spark markers and the latency glow on the involved neurons.
## - Break: the line stretches and trembles, then snaps into two retracting halves with a few
##   sparks (not a loss).
## - Completion wave: a light front runs along each link (NetworkWave "links" entries).
## Reduced motion: no growth, tremble, flicker, sparks or travelling front; breaks just fade.
## Endpoints are read from the model when drawing.

const WIDTH := 3.0
const MIN_WIDTH := 1.0
const WARNING_START := 0.6
const GROW_TIME := 0.25
const FLASH_TIME := 0.35
const BREAK_TIME := 0.4
## Fraction of BREAK_TIME spent stretching before the snap.
const SNAP_AT := 0.45
const SPARKS_PER_SNAP := 10

var _model: PuzzleModel
## pair -> {"grow": float, "crossing": bool}
var _links: Dictionary[Vector2i, Dictionary] = {}
## {"a": Vector2, "b": Vector2, "age": float, "snapped": bool}
var _breaking: Array[Dictionary] = []
## {"pos": Vector2, "age": float}
var _flashes: Array[Dictionary] = []
## {"pos": Vector2, "vel": Vector2, "age": float}
var _sparks: Array[Dictionary] = []
## pair -> {"delay": float, "from_a": bool, "duration": float, "age": float}
var _waves: Dictionary[Vector2i, Dictionary] = {}
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 4242


func setup(model: PuzzleModel) -> void:
	_model = model
	_links.clear()
	_breaking.clear()
	_flashes.clear()
	_sparks.clear()
	_waves.clear()
	var crossing := model.get_crossing_links()
	for pair in model.get_link_pairs():
		_links[pair] = {"grow": 1.0, "crossing": crossing.has(pair)}
	model.link_formed.connect(_on_link_formed)
	model.link_broken.connect(_on_link_broken)
	model.crossings_changed.connect(_on_crossings_changed)
	model.neuron_moved.connect(_on_neuron_moved)
	queue_redraw()


func get_link_count() -> int:
	return _links.size()


func get_breaking_count() -> int:
	return _breaking.size()


func get_flash_count() -> int:
	return _flashes.size()


func get_wave_count() -> int:
	return _waves.size()


## 0..1 drawn length of a link (1 = fully grown), 0 for unknown links.
func get_grow(pair: Vector2i) -> float:
	return _links.get(pair, {}).get("grow", 0.0)


func get_strain(pair: Vector2i) -> float:
	return _model.get_link_strain(pair.x, pair.y) if _model != null else 0.0


func get_width(pair: Vector2i) -> float:
	return lerpf(WIDTH, MIN_WIDTH, _warning(get_strain(pair)))


func is_link_crossing(pair: Vector2i) -> bool:
	return _links.get(pair, {}).get("crossing", false)


## Starts the light front along every link listed by NetworkWave.schedule()["links"].
func play_wave(entries: Array) -> void:
	_waves.clear()
	for entry: Dictionary in entries:
		var pair: Vector2i = entry["pair"]
		if _links.has(pair):
			_waves[pair] = {"delay": entry["delay"], "from_a": entry["from_a"],
				"duration": entry["duration"], "age": 0.0}


func _process(delta: float) -> void:
	_time += delta
	var motion := VisualTuning.is_motion_enabled()
	for pair: Vector2i in _links:
		var link := _links[pair]
		if link["grow"] < 1.0:
			link["grow"] = minf(1.0, link["grow"] + delta / GROW_TIME) if motion else 1.0
	for broken in _breaking:
		broken["age"] += delta
		if motion and not broken["snapped"] and broken["age"] >= BREAK_TIME * SNAP_AT:
			broken["snapped"] = true
			_spawn_sparks((broken["a"] + broken["b"]) * 0.5)
	_breaking = _breaking.filter(func(b: Dictionary) -> bool: return b["age"] < BREAK_TIME)
	for flash in _flashes:
		flash["age"] += delta
	_flashes = _flashes.filter(func(f: Dictionary) -> bool: return f["age"] < FLASH_TIME)
	for spark in _sparks:
		spark["age"] += delta
		spark["pos"] += spark["vel"] * delta
		spark["vel"] *= exp(-5.0 * delta)
	_sparks = _sparks.filter(func(s: Dictionary) -> bool: return s["age"] < 0.35)
	for pair: Vector2i in _waves.keys():
		var wave := _waves[pair]
		wave["age"] += delta
		if wave["age"] > wave["delay"] + wave["duration"] + VisualTuning.WAVE_TAIL:
			_waves.erase(pair)
	if not _links.is_empty() or not _breaking.is_empty() or not _sparks.is_empty() or not _flashes.is_empty():
		queue_redraw()


func _draw() -> void:
	if _model == null:
		return
	var motion := VisualTuning.motion_scale()
	for pair: Vector2i in _links:
		var a := _model.get_neuron_position(pair.x)
		var b := _model.get_neuron_position(pair.y)
		var link := _links[pair]
		var end := a.lerp(b, link["grow"])
		var warning := _warning(get_strain(pair))
		var flicker := 1.0
		if motion > 0.0 and warning > 0.0 and _rng.randf() < 0.35 * warning:
			flicker = 0.35
		var boost := _wave_boost(pair, a, b)
		var width := get_width(pair)
		draw_line(a, end, Color(Palette.RECEPTOR_GLOW, (0.12 + 0.25 * boost) * flicker), width * 4.0 + 6.0)
		draw_line(a, end, Color(Palette.LINK, minf(1.0, (0.9 + boost) * flicker)), width, true)
		if link["grow"] < 1.0:
			draw_circle(end, 4.0, Color(Palette.LINK, 0.9))
	for broken in _breaking:
		_draw_breaking(broken, motion)
	for flash in _flashes:
		var t: float = flash["age"] / FLASH_TIME
		draw_circle(flash["pos"], 16.0 + 40.0 * t, Color(Palette.RECEPTOR_GLOW, 0.4 * (1.0 - t)))
		draw_arc(flash["pos"], 30.0 + 30.0 * t, 0.0, TAU, 32, Color(Palette.LINK, 0.6 * (1.0 - t)), 2.0, true)
	for spark in _sparks:
		var fade: float = 1.0 - spark["age"] / 0.35
		var pos: Vector2 = spark["pos"]
		draw_line(pos - (spark["vel"] as Vector2) * 0.03, pos, Color(Palette.LINK, fade), 1.5, true)


## Stretch and tremble, then two halves retract to their ends while fading.
func _draw_breaking(broken: Dictionary, motion: float) -> void:
	var a: Vector2 = broken["a"]
	var b: Vector2 = broken["b"]
	var t: float = broken["age"] / BREAK_TIME
	var fade := 1.0 - t
	if motion <= 0.0:
		draw_line(a, b, Color(Palette.LINK, 0.6 * fade), MIN_WIDTH, true)
		return
	if t < SNAP_AT:
		var side := (b - a).orthogonal().normalized()
		var mid := (a + b) * 0.5 + side * sin(_time * 70.0) * 4.0
		draw_polyline(PackedVector2Array([a, mid, b]), Color(Palette.LINK, 0.9), MIN_WIDTH, true)
		return
	var k := (t - SNAP_AT) / (1.0 - SNAP_AT)
	var mid := (a + b) * 0.5
	draw_line(a, mid.lerp(a, k), Color(Palette.LINK, fade), MIN_WIDTH + 1.0, true)
	draw_line(b, mid.lerp(b, k), Color(Palette.LINK, fade), MIN_WIDTH + 1.0, true)


func _wave_boost(pair: Vector2i, _a: Vector2, _b: Vector2) -> float:
	if not _waves.has(pair):
		return 0.0
	var wave := _waves[pair]
	var local: float = wave["age"] - wave["delay"]
	if local < 0.0:
		return 0.0
	var duration: float = wave["duration"]
	if local <= duration:
		return 1.0
	return maxf(0.0, 1.0 - (local - duration) / VisualTuning.WAVE_TAIL)


func _spawn_sparks(center: Vector2) -> void:
	for i in SPARKS_PER_SNAP:
		_sparks.append({"pos": center, "vel": Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(60.0, 180.0),
			"age": 0.0})


static func _warning(strain: float) -> float:
	var t := clampf((strain - WARNING_START) / (1.0 - WARNING_START), 0.0, 1.0)
	return t * t


func _on_link_formed(receptor_id: int, neuron_id: int) -> void:
	var pair := Vector2i(receptor_id, neuron_id)
	var motion := VisualTuning.is_motion_enabled()
	_links[pair] = {"grow": 0.0 if motion else 1.0, "crossing": _model.get_crossing_links().has(pair)}
	_flashes.append({"pos": _model.get_neuron_position(neuron_id), "age": 0.0})
	queue_redraw()


func _on_link_broken(receptor_id: int, neuron_id: int) -> void:
	var pair := Vector2i(receptor_id, neuron_id)
	_links.erase(pair)
	_waves.erase(pair)
	_breaking.append({"a": _model.get_neuron_position(receptor_id), "b": _model.get_neuron_position(neuron_id),
		"age": 0.0, "snapped": false})
	queue_redraw()


func _on_crossings_changed(_edges: Array[int], _neurons: Array[int]) -> void:
	var crossing := _model.get_crossing_links()
	for pair: Vector2i in _links:
		_links[pair]["crossing"] = crossing.has(pair)


func _on_neuron_moved(_id: int, _pos: Vector2) -> void:
	queue_redraw()
