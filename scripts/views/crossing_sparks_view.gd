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

var _points := PackedVector2Array()
var _show_feedback := true
var _arcs: Array[PackedVector2Array] = []
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


## True with reduced motion: markers are drawn as still stars.
func is_static() -> bool:
	return not VisualTuning.is_motion_enabled()


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
	if is_static():
		return
	for point in _points:
		for i in ARCS_PER_POINT:
			_arcs.append(make_arc(point, _rng, _rng.randf_range(ARC_LENGTH_MIN, ARC_LENGTH_MAX),
				ARC_SEGMENTS, ARC_JITTER))


func _spawn(point: Vector2) -> void:
	if _particles.size() >= MAX_PARTICLES:
		return
	var velocity := Vector2.from_angle(_rng.randf() * TAU) \
		* _rng.randf_range(PARTICLE_SPEED_MIN, PARTICLE_SPEED_MAX)
	_particles.append({"pos": point, "vel": velocity, "age": 0.0,
		"life": _rng.randf_range(PARTICLE_LIFE_MIN, PARTICLE_LIFE_MAX)})


func _draw() -> void:
	var flicker := 1.0
	if not is_static():
		flicker = 0.75 + 0.25 * sin(_time * 37.0) * sin(_time * 23.0)
	for point in _points:
		draw_circle(point, 24.0, Color(Palette.SPARK_GLOW, 0.12 * flicker))
		draw_circle(point, 13.0, Color(Palette.SPARK_GLOW, 0.3 * flicker))
		draw_circle(point, 6.5, Color(Palette.SPARK_GLOW, 0.55 * flicker))
		draw_circle(point, 3.0, Color(Palette.SPARK, 1.0))
		if is_static():
			_draw_star(point)
	for arc in _arcs:
		draw_polyline(arc, Color(Palette.SPARK_GLOW, 0.45), 3.5)
		draw_polyline(arc, Color(Palette.SPARK, 0.95), 1.4, true)
	for particle in _particles:
		var fade: float = 1.0 - particle["age"] / particle["life"]
		var pos: Vector2 = particle["pos"]
		var tail: Vector2 = pos - (particle["vel"] as Vector2) * 0.035
		draw_line(tail, pos, Color(Palette.SPARK, 0.9 * fade), 1.4, true)


func _draw_star(point: Vector2) -> void:
	for angle in [0.0, PI * 0.5, PI * 0.25, PI * 0.75]:
		var length: float = STAR_SIZE if fmod(angle / (PI * 0.25), 2.0) < 0.5 else STAR_SIZE * 0.55
		var direction := Vector2.from_angle(angle) * length
		draw_line(point - direction, point + direction, Color(Palette.SPARK, 0.9), 1.6, true)
