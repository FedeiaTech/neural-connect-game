class_name CrossingSparksView
extends Node2D
## Crackling spark markers at every exact crossing point (T7.1, SDD 5.4). Listens to
## PuzzleModel.crossing_points_changed. Each marker: a hot glow, a few short jittered lightning
## arcs re-rolled every ARC_INTERVAL and tiny spark streaks flying off. Drawn with additive
## blending (the level scene gives this node a CanvasItemMaterial with BLEND_MODE_ADD).
## Reduced motion: no arcs or particles, only a static four-pointed star with a glow.
## Purely visual: the model is the only source of the points.

const MAX_PARTICLES := 160
const ARC_INTERVAL := 0.06
const ARCS_PER_POINT := 3
const ARC_LENGTH_MIN := 9.0
const ARC_LENGTH_MAX := 20.0
const ARC_SEGMENTS := 4
const ARC_JITTER := 4.0
## Seconds between two particle spawns at one point.
const SPAWN_INTERVAL := 0.07
const PARTICLE_SPEED_MIN := 50.0
const PARTICLE_SPEED_MAX := 150.0
const PARTICLE_LIFE_MIN := 0.18
const PARTICLE_LIFE_MAX := 0.4
const PARTICLE_DAMPING := 4.0
const STAR_SIZE := 9.0
## Radius of the soft glow sprite around each marker.
const GLOW_RADIUS := 24.0

static var _glow: GradientTexture2D

var _points := PackedVector2Array()
var _show_feedback := true
var _arcs: Array[PackedVector2Array] = []
## Every arc as segment pairs for one draw_multiline call.
var _arc_segments := PackedVector2Array()
var _arc_timer := 0.0
var _spawn_timer := 0.0
## Each particle: {"pos": Vector2, "vel": Vector2, "age": float, "life": float}.
var _particles: Array[Dictionary] = []
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.seed = 7177


func setup(model: PuzzleModel, show_feedback := true) -> void:
	_show_feedback = show_feedback
	_particles.clear()
	_arcs.clear()
	_set_points(model.get_crossing_points())
	model.crossing_points_changed.connect(_set_points)


func get_points() -> PackedVector2Array:
	return _points.duplicate()


func get_marker_count() -> int:
	return _points.size()


func get_particle_count() -> int:
	return _particles.size()


func get_arc_count() -> int:
	return _arcs.size()


## True with reduced motion or low memory mode: markers are drawn as still stars.
func is_static() -> bool:
	return not VisualTuning.is_motion_enabled() or VisualTuning.is_low_memory()


## A short jagged lightning line of segments pieces leaving center in a random direction,
## each joint pushed sideways by up to jitter. Every point stays within length + jitter.
static func make_arc(center: Vector2, rng: RandomNumberGenerator, length: float, segments: int,
		jitter: float) -> PackedVector2Array:
	var direction := Vector2.from_angle(rng.randf() * TAU)
	var side := direction.orthogonal()
	var arc := PackedVector2Array([center])
	for i in range(1, segments + 1):
		var along := length * float(i) / segments
		var offset := rng.randf_range(-jitter, jitter) if i < segments else rng.randf_range(-jitter, jitter) * 0.5
		arc.append(center + direction * along + side * offset)
	return arc


func _set_points(points: PackedVector2Array) -> void:
	_points = points if _show_feedback else PackedVector2Array()
	_arc_timer = 0.0
	_regenerate_arcs()
	queue_redraw()


func _process(delta: float) -> void:
	_time += delta
	if is_static():
		if not _particles.is_empty() or not _arcs.is_empty():
			_particles.clear()
			_arcs.clear()
			_arc_segments.clear()
			queue_redraw()
		return
	_arc_timer += delta
	if _arc_timer >= ARC_INTERVAL:
		_arc_timer = 0.0
		_regenerate_arcs()
	_spawn_timer += delta
	while _spawn_timer >= SPAWN_INTERVAL:
		_spawn_timer -= SPAWN_INTERVAL
		for point in _points:
			_spawn(point)
	for particle in _particles:
		particle["age"] += delta
		particle["pos"] += particle["vel"] * delta
		particle["vel"] *= exp(-PARTICLE_DAMPING * delta)
	_particles = _particles.filter(func(p: Dictionary) -> bool: return p["age"] < p["life"])
	if not _points.is_empty() or not _particles.is_empty():
		queue_redraw()


func _regenerate_arcs() -> void:
	_arcs.clear()
	_arc_segments.clear()
	if is_static():
		return
	for point in _points:
		for i in ARCS_PER_POINT:
			var arc := make_arc(point, _rng, _rng.randf_range(ARC_LENGTH_MIN, ARC_LENGTH_MAX),
				ARC_SEGMENTS, ARC_JITTER)
			_arcs.append(arc)
			for k in arc.size() - 1:
				_arc_segments.append(arc[k])
				_arc_segments.append(arc[k + 1])


func _spawn(point: Vector2) -> void:
	if _particles.size() >= MAX_PARTICLES:
		return
	var velocity := Vector2.from_angle(_rng.randf() * TAU) \
		* _rng.randf_range(PARTICLE_SPEED_MIN, PARTICLE_SPEED_MAX)
	_particles.append({"pos": point, "vel": velocity, "age": 0.0,
		"life": _rng.randf_range(PARTICLE_LIFE_MIN, PARTICLE_LIFE_MAX)})


## Smooth and batched: one radial-gradient glow sprite per point (instead of stacked discs with
## hard edges), and every arc / particle / star stroke in a single antialiased multiline call.
func _draw() -> void:
	var flicker := 1.0
	if not is_static():
		flicker = 0.75 + 0.25 * sin(_time * 37.0) * sin(_time * 23.0)
	var glow := _glow_texture()
	var glow_size := Vector2.ONE * GLOW_RADIUS * 2.0
	for point in _points:
		draw_texture_rect(glow, Rect2(point - glow_size * 0.5, glow_size), false, Color(Palette.SPARK_GLOW, flicker))
	for point in _points:
		draw_circle(point, 3.0, Color(Palette.SPARK, 1.0), true, -1.0, true)
	if is_static():
		var stars := PackedVector2Array()
		for point in _points:
			stars.append_array(_star_segments(point))
		if not stars.is_empty():
			draw_multiline(stars, Color(Palette.SPARK, 0.9), 1.6, true)
	if not _arc_segments.is_empty():
		draw_multiline(_arc_segments, Color(Palette.SPARK_GLOW, 0.45), 3.5, true)
		draw_multiline(_arc_segments, Color(Palette.SPARK, 0.95), 1.4, true)
	if not _particles.is_empty():
		var streaks := PackedVector2Array()
		var colors := PackedColorArray()
		for particle in _particles:
			var fade: float = 1.0 - particle["age"] / particle["life"]
			var pos: Vector2 = particle["pos"]
			streaks.append(pos - (particle["vel"] as Vector2) * 0.035)
			streaks.append(pos)
			colors.append(Color(Palette.SPARK, 0.9 * fade))
		draw_multiline_colors(streaks, colors, 1.4, true)


## Four-pointed star (long axis-aligned, short diagonal) as multiline segment pairs.
static func _star_segments(point: Vector2) -> PackedVector2Array:
	var segments := PackedVector2Array()
	for angle in [0.0, PI * 0.5, PI * 0.25, PI * 0.75]:
		var length: float = STAR_SIZE if fmod(angle / (PI * 0.25), 2.0) < 0.5 else STAR_SIZE * 0.55
		var direction := Vector2.from_angle(angle) * length
		segments.append(point - direction)
		segments.append(point + direction)
	return segments


## Shared soft radial glow (white, alpha falling off like the old three stacked discs).
static func _glow_texture() -> GradientTexture2D:
	if _glow != null:
		return _glow
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.27, 0.4, 0.54, 0.75, 1.0])
	gradient.colors = PackedColorArray([Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.5),
		Color(1, 1, 1, 0.38), Color(1, 1, 1, 0.14), Color(1, 1, 1, 0.0)])
	_glow = GradientTexture2D.new()
	_glow.gradient = gradient
	_glow.fill = GradientTexture2D.FILL_RADIAL
	_glow.fill_from = Vector2(0.5, 0.5)
	_glow.fill_to = Vector2(1.0, 0.5)
	_glow.width = 64
	_glow.height = 64
	return _glow
