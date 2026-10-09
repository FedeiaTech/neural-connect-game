extends SceneTree
## Offline authoring helper (T7.4), not game code: searches a start layout for one mission of
## tools/level_specs.gd and prints it as a "start" entry to paste into the spec. Deterministic
## for a given seed. A candidate is the solution with a few movable neurons swapped and every
## movable neuron jittered; it is accepted when:
##   - validate_level() passes (placement, tension, lethal margin, not already solved),
##   - start crossings lie in [min, max],
##   - no dendrite passes closer than build_levels.MIN_START_CLEARANCE to a foreign neuron,
##   - every receptor starts unsatisfied (the player has to make the links),
##   - the solution planner solves it and the replay on the real model succeeds.
##
##   godot --headless --path . -s res://tools/find_start.gd -- <mission_id> <min> <max> [seed] [swaps] [jitter] [write]
##
## With `write` the found start is stored in tools/level_starts.gd (missions without an inline
## "start" in tools/level_specs.gd read it from there).

const Specs := preload("res://tools/level_specs.gd")
const Builder := preload("res://tools/build_levels.gd")
const SolutionPlanner := preload("res://tests/content/solution_planner.gd")
const TRIES := 4000
const STARTS_PATH := "res://tools/level_starts.gd"
const STARTS_HEADER := "extends RefCounted
## Start layouts of the missions authored with tools/layouts.gd (m31 and up), found by
## tools/find_start.gd (write) and committed so the campaign stays reviewable: mission id ->
## flat [x0, y0, x1, y1, ...] positions (neuron id = index). Edit freely; the builder validates.

const STARTS := {
"

var _write := false


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		printerr("usage: -- <mission_id> <min> <max> [seed] [swaps] [jitter]")
		quit(2)
		return
	var spec := _spec(args[0])
	if spec.is_empty():
		printerr("unknown mission %s" % args[0])
		quit(2)
		return
	var low := int(args[1])
	var high := int(args[2])
	var rng := RandomNumberGenerator.new()
	rng.seed = int(args[3]) if args.size() > 3 else 1
	var max_swaps := int(args[4]) if args.size() > 4 else 3
	var jitter := float(args[5]) if args.size() > 5 else 70.0
	_write = args.has("write")
	var base := Builder.build_level(spec)
	if args.has("calm"):
		_calm(base, low, high)
		return
	for attempt in TRIES:
		var level := base.duplicate(true) as LevelData
		_shuffle(level, rng, rng.randi_range(1, max_swaps), jitter)
		var result := _check(level, low, high)
		if result >= 0:
			print("attempt %d: %d crossings, %d planned moves" % [attempt, PuzzleModel.from_level(level).get_crossing_count(), result])
			print('"start": pts([%s]),' % _format(level))
			if _write:
				_store(args[0], level)
			quit(0)
			return
	printerr("no start found in %d tries; rejections %s; crossings seen %d..%d; sample error %s" % [
		TRIES, _rejections, _min_seen, _max_seen, _sample_error])
	quit(1)


## "calm" mode: from the spec's own start, repeatedly applies the single move (one movable
## neuron going 1/3, 1/2 or all the way back to its solution spot) that removes the most
## crossings while the layout stays valid and readable, until the count is in [low, high].
func _calm(level: LevelData, low: int, high: int) -> void:
	var count := PuzzleModel.from_level(level).get_crossing_count()
	while count > high:
		var best_count := count
		var best_neuron: NeuronData = null
		var best_position := Vector2.ZERO
		for neuron in level.neurons:
			if neuron.fixed or neuron.is_receptor():
				continue
			var original := neuron.position
			for fraction in [0.34, 0.5, 1.0]:
				neuron.position = original.lerp(neuron.solution_position, fraction).round()
				var errors := PuzzleModel.validate_level(level)
				var tight := Builder.tight_spots(level)
				if not errors.is_empty():
					_sample_error = "%d: %s" % [neuron.id, errors[0]]
				elif not tight.is_empty():
					_sample_error = "%d: tight %s" % [neuron.id, tight]
				if errors.is_empty():
					var candidate := PuzzleModel.from_level(level).get_crossing_count()
					# Prefer the smallest step that still lands at or above low.
					if candidate < best_count and candidate >= low:
						best_count = candidate
						best_neuron = neuron
						best_position = neuron.position
			neuron.position = original
		if best_neuron == null:
			break
		best_neuron.position = best_position
		count = best_count
	_untighten(level, low, high)
	var result := _check(level, low, high)
	if result < 0:
		printerr("calm: stuck at %d crossings; rejections %s; %s" % [count, _rejections, _sample_error])
		quit(1)
		return
	print("calm: %d crossings, %d planned moves" % [count, result])
	print('"start": pts([%s]),' % _format(level))
	if _write:
		_store(str(level.mission_id), level)
	quit(0)


## Nudges the neurons named in tight spots (seeded, up to TRIES times) until no dendrite grazes
## a foreign neuron, keeping the layout valid and the crossings in range.
func _untighten(level: LevelData, low: int, high: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for attempt in TRIES:
		var tight := Builder.tight_spots(level)
		if tight.is_empty():
			return
		var id := int(tight[rng.randi_range(0, tight.size() - 1)].get_slice(":", 0))
		var neuron := level.find_neuron(id)
		if neuron.fixed or neuron.is_receptor():
			# Move one end of the grazing dendrite instead.
			var ends := tight[0].get_slice(":", 1).get_slice("=", 0).strip_edges().split("-")
			neuron = level.find_neuron(int(ends[rng.randi_range(0, 1)]))
			if neuron.fixed or neuron.is_receptor():
				continue
		var original := neuron.position
		neuron.position = (original + Vector2(rng.randf_range(-45, 45), rng.randf_range(-45, 45))).round()
		var count := PuzzleModel.from_level(level).get_crossing_count()
		if not PuzzleModel.validate_level(level).is_empty() or count < low or count > high \
				or Builder.tight_spots(level).size() > tight.size():
			neuron.position = original


func _spec(id: String) -> Dictionary:
	for spec in Specs.missions():
		if spec["id"] == id:
			return spec
	return {}


func _shuffle(level: LevelData, rng: RandomNumberGenerator, swaps: int, jitter: float) -> void:
	var movable: Array[NeuronData] = []
	for neuron in level.neurons:
		neuron.position = neuron.solution_position
		if not neuron.fixed and not neuron.is_receptor():
			movable.append(neuron)
	for i in swaps:
		var a := movable[rng.randi_range(0, movable.size() - 1)]
		var b := movable[rng.randi_range(0, movable.size() - 1)]
		var swap := a.position
		a.position = b.position
		b.position = swap
	for neuron in movable:
		var base := neuron.position
		neuron.position += Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
		neuron.position = neuron.position.round()
		# A jitter that lands on a wall, a lethal margin or another neuron is dropped (T8.4).
		if not _spot_ok(level, neuron):
			neuron.position = base
	_unlink_receptors(level, movable)
	# Tension (and diseased, T8.4) repair: pull a movable end back to 85% of max_length from its
	# partner, so the start respects the limit.
	for _pass in 4:
		for dendrite in level.dendrites:
			if not (dendrite.is_tension() or dendrite.is_diseased()):
				continue
			var a := level.find_neuron(dendrite.a)
			var b := level.find_neuron(dendrite.b)
			if a.position.distance_to(b.position) <= 0.9 * dendrite.max_length:
				continue
			var moving := b if movable.has(b) else a
			var anchor := a if moving == b else b
			if not movable.has(moving):
				continue
			var direction := (moving.position - anchor.position).normalized()
			moving.position = (anchor.position + direction * 0.85 * dendrite.max_length).round()


## Receptor/toxic repair (T8.4): while a receptor starts satisfied or a toxic neuron starts inside
## a reach, swap the offending neuron with the movable neuron farthest from that receptor.
func _unlink_receptors(level: LevelData, movable: Array[NeuronData]) -> void:
	for receptor in level.neurons:
		if not receptor.is_receptor():
			continue
		for round in 8:
			var inside: Array[NeuronData] = []
			var excess := 0
			for neuron in movable:
				if neuron.position.distance_to(receptor.position) - level.neuron_radius <= receptor.reach:
					inside.append(neuron)
			var partners := 0
			for neuron in inside:
				partners += int(not neuron.is_toxic())
			var offender: NeuronData = null
			for neuron in inside:
				if neuron.is_toxic():
					offender = neuron
					break
			if offender == null and partners >= receptor.required_links:
				offender = inside[0]
			if offender == null:
				break
			var far: NeuronData = null
			for neuron in movable:
				if neuron == offender or neuron in inside:
					continue
				if far == null or neuron.position.distance_to(receptor.position) > far.position.distance_to(receptor.position):
					far = neuron
			if far == null:
				break
			var swap := offender.position
			offender.position = far.position
			far.position = swap


func _spot_ok(level: LevelData, neuron: NeuronData) -> bool:
	if not GeometryUtils.is_circle_in_playfield(neuron.position, level.neuron_radius + 2.0, level.play_area, level.obstacles):
		return false
	for other in level.neurons:
		if other != neuron and other.position.distance_to(neuron.position) < 2.0 * level.neuron_radius + 6.0:
			return false
	var lethal := PuzzleModel.lethal_segments_of(level)
	return lethal.is_empty() or PuzzleModel.lethal_gap(neuron.position, level.neuron_radius, lethal) >= 26.0


var _rejections := {"invalid": 0, "crossings": 0, "receptor": 0, "tight": 0, "planner": 0}
var _min_seen := 1 << 30
var _max_seen := -1
var _sample_error := ""


## Planned moves, or -1 when the candidate is rejected.
func _check(level: LevelData, low: int, high: int) -> int:
	var errors := PuzzleModel.validate_level(level)
	if not errors.is_empty():
		_rejections["invalid"] += 1
		_sample_error = errors[0]
		return -1
	var model := PuzzleModel.from_level(level)
	var crossings := model.get_crossing_count()
	_min_seen = mini(_min_seen, crossings)
	_max_seen = maxi(_max_seen, crossings)
	if crossings < low or crossings > high:
		_rejections["crossings"] += 1
		return -1
	for receptor_id in model.get_receptor_ids():
		if model.is_receptor_satisfied(receptor_id):
			_rejections["receptor"] += 1
			return -1
	if not Builder.tight_spots(level).is_empty():
		_rejections["tight"] += 1
		return -1
	var plan := SolutionPlanner.new().plan(level)
	if not plan["ok"]:
		_rejections["planner"] += 1
		return -1
	var replay := SolutionPlanner.replay(level, plan["moves"])
	if replay["error"] != "" or not (replay["model"] as PuzzleModel).is_solved():
		_rejections["planner"] += 1
		return -1
	return plan["moves"].size()


## Stores the level's current neuron positions as the mission's start in tools/level_starts.gd
## (entries sorted by id, one per line, so the file stays diff-friendly).
func _store(id: String, level: LevelData) -> void:
	var entries := {}
	for line in FileAccess.get_file_as_string(STARTS_PATH).split("
"):
		var text := line.strip_edges()
		if text.begins_with('"m') and text.contains('": ['):
			entries[text.get_slice('"', 1)] = text.substr(text.find("[")).trim_suffix(",")
	entries[id] = "[%s]" % _format(level)
	var keys := entries.keys()
	keys.sort()
	var out := STARTS_HEADER
	for key in keys:
		out += '	"%s": %s,
' % [key, entries[key]]
	out += "}
"
	var file := FileAccess.open(STARTS_PATH, FileAccess.WRITE)
	file.store_string(out)
	print("stored start of %s in %s" % [id, STARTS_PATH])


func _format(level: LevelData) -> String:
	var values := PackedStringArray()
	for neuron in level.neurons:
		values.append("%d, %d" % [int(neuron.position.x), int(neuron.position.y)])
	return ", ".join(values)
