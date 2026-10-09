extends SceneTree
## Offline authoring tool, not game code: builds the hand-designed missions of
## tools/level_specs.gd into data/levels/mXX.tres and data/campaign.tres, then prints a report
## (validation, start crossings, planned solution moves, pars). Deterministic: the same specs
## always produce the same files. The game itself never generates levels.
##
## Run from the project root (PowerShell):
##   godot --headless --path . -s res://tools/build_levels.gd            # build and report
##   godot --headless --path . -s res://tools/build_levels.gd -- --check # report only
##   godot --headless --path . -s res://tools/build_levels.gd -- --only=m19,m20 # report some
## Exit code 1 when any mission is invalid or the planner cannot solve it.
## (-s scripts cannot use autoloads; this one only needs global classes.)

const Specs := preload("res://tools/level_specs.gd")
const SolutionPlanner := preload("res://tests/content/solution_planner.gd")
const LEVELS_DIR := "res://data/levels"
const CAMPAIGN_PATH := "res://data/campaign.tres"
const RADIUS := 28.0
## Readability: at start no dendrite may pass this close to a neuron it does not connect.
const MIN_START_CLEARANCE := 40.0


func _init() -> void:
	var check_only := OS.get_cmdline_user_args().has("--check")
	# --only=m19,m20: report just these missions (implies --check).
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.trim_prefix("--only=").split(",")
			check_only = true
	var ok := true
	var levels: Array[LevelData] = []
	var rows := PackedStringArray([
		"| id | name | ch | neurons | dendrites | fixed | tension | lethal | receptors | start crossings | planned moves | par_moves | par_time | story | min spacing | edge clearance start / solution |",
		"|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
	])
	for spec in Specs.missions():
		if not only.is_empty() and not only.has(spec["id"]):
			continue
		var level := build_level(spec)
		var errors := PuzzleModel.validate_level(level)
		var moves := -1
		if errors.is_empty():
			var plan := SolutionPlanner.new().plan(level)
			if plan["ok"]:
				var replay := SolutionPlanner.replay(level, plan["moves"])
				var model: PuzzleModel = replay["model"]
				if replay["error"] != "" or not model.is_solved():
					errors.append("replay failed: %s (solved %s)" % [replay["error"], model.is_solved()])
				moves = plan["moves"].size()
			else:
				errors.append("planner: " + plan["reason"])
		level.par_moves = spec.get("par_moves", maxi(2 * moves, 4))
		var tight := tight_spots(level)
		if not tight.is_empty():
			errors.append("dendrites too close to neurons at start (neuron: dendrite = distance): %s" % tight)
		if not errors.is_empty():
			ok = false
			printerr("%s: %s" % [level.mission_id, errors])
		rows.append(_row(level, moves))
		levels.append(level)
		if not check_only and errors.is_empty():
			_write(LEVELS_DIR.path_join("%s.tres" % level.mission_id), level_text(level))
	if not check_only and ok:
		_write(CAMPAIGN_PATH, campaign_text(levels))
	print("\n".join(rows))
	print("build_levels: %s, %d missions%s" % [
		"OK" if ok else "FAILED", levels.size(), " (check only)" if check_only else ""])
	quit(0 if ok else 1)


## Builds the LevelData of one spec (see tools/level_specs.gd for the keys).
static func build_level(spec: Dictionary) -> LevelData:
	var level := LevelData.new()
	level.mission_id = StringName(spec["id"])
	level.mission_name = spec["name"]
	level.chapter_id = spec["chapter"]
	level.story_text = spec.get("story", "")
	level.play_area = spec.get("area", Specs.pts(Specs.DEFAULT_AREA))
	var obstacles: Array[PackedVector2Array] = []
	for outline: PackedVector2Array in spec.get("obstacles", []):
		obstacles.append(outline)
	level.obstacles = obstacles
	level.neuron_radius = RADIUS
	level.par_time = spec["par_time"]
	level.lethal_edges = PackedInt32Array(spec.get("lethal_edges", []))
	level.lethal_obstacles = PackedInt32Array(spec.get("lethal_obstacles", []))
	var solution: PackedVector2Array = spec["sol"]
	var fixed: Array = spec.get("fixed", [])
	var receptors: Dictionary = spec.get("receptors", {})
	var toxic: Array = spec.get("toxic", [])
	var neurons: Array[NeuronData] = []
	for id in solution.size():
		var neuron := NeuronData.new()
		neuron.id = id
		neuron.solution_position = solution[id]
		neuron.fixed = fixed.has(id)
		if receptors.has(id):
			neuron.kind = NeuronData.Kind.RECEPTOR
			neuron.reach = receptors[id][0]
			neuron.required_links = receptors[id][1]
		if toxic.has(id):
			neuron.kind = NeuronData.Kind.TOXIC
		if neuron.fixed or neuron.is_receptor():
			neuron.position = solution[id]
		elif spec.has("start"):
			neuron.position = spec["start"][id]
		else:
			neuron.position = solution[spec["perm"][id]] + spec["offset"]
		if not neuron.fixed and not neuron.is_receptor():
			neuron.position += spec.get("nudge", {}).get(id, Vector2.ZERO)
		neurons.append(neuron)
	level.neurons = neurons
	var dendrites: Array[DendriteData] = []
	for edge: Array in spec["edges"]:
		var dendrite := DendriteData.new()
		dendrite.a = edge[0]
		dendrite.b = edge[1]
		if edge.size() == 4:
			dendrite.kind = DendriteData.Kind.TENSION
			dendrite.rest_length = edge[2]
			dendrite.max_length = edge[3]
		dendrites.append(dendrite)
	level.dendrites = dendrites
	return level


## Text resource in the same layout as the hand-written m01/m02 files.
static func level_text(level: LevelData) -> String:
	var lines := PackedStringArray([
		'[gd_resource type="Resource" script_class="LevelData" format=3]',
		"",
		'[ext_resource type="Script" path="res://scripts/model/level_data.gd" id="1_level"]',
		'[ext_resource type="Script" path="res://scripts/model/neuron_data.gd" id="2_neuron"]',
		'[ext_resource type="Script" path="res://scripts/model/dendrite_data.gd" id="3_dendrite"]',
		"",
	])
	var neuron_refs := PackedStringArray()
	for i in level.neurons.size():
		var neuron := level.neurons[i]
		lines.append('[sub_resource type="Resource" id="Neuron_%d"]' % i)
		lines.append('script = ExtResource("2_neuron")')
		lines.append("id = %d" % neuron.id)
		lines.append("position = %s" % _vector(neuron.position))
		lines.append("solution_position = %s" % _vector(neuron.solution_position))
		if neuron.fixed:
			lines.append("fixed = true")
		if neuron.is_receptor():
			lines.append("kind = %d" % neuron.kind)
			lines.append("reach = %s" % _float(neuron.reach))
			lines.append("required_links = %d" % neuron.required_links)
		elif neuron.is_toxic():
			lines.append("kind = %d" % neuron.kind)
		lines.append("")
		neuron_refs.append('SubResource("Neuron_%d")' % i)
	var dendrite_refs := PackedStringArray()
	for i in level.dendrites.size():
		var dendrite := level.dendrites[i]
		lines.append('[sub_resource type="Resource" id="Dendrite_%d"]' % i)
		lines.append('script = ExtResource("3_dendrite")')
		lines.append("a = %d" % dendrite.a)
		lines.append("b = %d" % dendrite.b)
		if dendrite.is_tension():
			lines.append("kind = %d" % dendrite.kind)
			lines.append("max_length = %s" % _float(dendrite.max_length))
			lines.append("rest_length = %s" % _float(dendrite.rest_length))
		lines.append("")
		dendrite_refs.append('SubResource("Dendrite_%d")' % i)
	var obstacles := PackedStringArray()
	for outline in level.obstacles:
		obstacles.append(_packed(outline))
	lines.append("[resource]")
	lines.append('script = ExtResource("1_level")')
	lines.append('mission_id = &"%s"' % level.mission_id)
	lines.append("mission_name = %s" % _string(level.mission_name))
	lines.append("chapter_id = %d" % level.chapter_id)
	if not level.story_text.is_empty():
		lines.append("story_text = %s" % _string(level.story_text))
	lines.append("play_area = %s" % _packed(level.play_area))
	lines.append("obstacles = Array[PackedVector2Array]([%s])" % ", ".join(obstacles))
	lines.append("neuron_radius = %s" % _float(level.neuron_radius))
	lines.append("show_crossing_feedback = true")
	if not level.lethal_edges.is_empty():
		lines.append("lethal_edges = PackedInt32Array(%s)" % _ints(level.lethal_edges))
	if not level.lethal_obstacles.is_empty():
		lines.append("lethal_obstacles = PackedInt32Array(%s)" % _ints(level.lethal_obstacles))
	lines.append('neurons = Array[ExtResource("2_neuron")]([%s])' % ", ".join(neuron_refs))
	lines.append('dendrites = Array[ExtResource("3_dendrite")]([%s])' % ", ".join(dendrite_refs))
	lines.append("par_moves = %d" % level.par_moves)
	lines.append("par_time = %s" % _float(level.par_time))
	return "\n".join(lines) + "\n"


static func campaign_text(levels: Array[LevelData]) -> String:
	var lines := PackedStringArray([
		'[gd_resource type="Resource" script_class="Campaign" format=3]',
		"",
		'[ext_resource type="Script" path="res://scripts/campaign/campaign.gd" id="1_campaign"]',
		'[ext_resource type="Script" path="res://scripts/campaign/chapter_data.gd" id="2_chapter"]',
		'[ext_resource type="Script" path="res://scripts/model/level_data.gd" id="3_level"]',
	])
	var refs: Dictionary[StringName, String] = {}
	for i in levels.size():
		var id := levels[i].mission_id
		var ref_id := "%d_%s" % [i + 4, id]
		lines.append('[ext_resource type="Resource" path="%s/%s.tres" id="%s"]' % [LEVELS_DIR, id, ref_id])
		refs[id] = 'ExtResource("%s")' % ref_id
	lines.append("")
	var chapter_refs := PackedStringArray()
	for chapter in Specs.chapters():
		var missions := PackedStringArray()
		for level in levels:
			if level.chapter_id == chapter["id"]:
				missions.append(refs[level.mission_id])
		lines.append('[sub_resource type="Resource" id="Chapter_%d"]' % chapter["id"])
		lines.append('script = ExtResource("2_chapter")')
		lines.append("chapter_id = %d" % chapter["id"])
		lines.append("title = %s" % _string(chapter["title"]))
		lines.append("subtitle = %s" % _string(chapter["subtitle"]))
		lines.append('missions = Array[ExtResource("3_level")]([%s])' % ", ".join(missions))
		lines.append("")
		chapter_refs.append('SubResource("Chapter_%d")' % chapter["id"])
	lines.append("[resource]")
	lines.append('script = ExtResource("1_campaign")')
	lines.append('chapters = Array[ExtResource("2_chapter")]([%s])' % ", ".join(chapter_refs))
	return "\n".join(lines) + "\n"


static func _row(level: LevelData, moves: int) -> String:
	var fixed := 0
	for neuron in level.neurons:
		fixed += int(neuron.fixed)
	var tension := 0
	for dendrite in level.dendrites:
		tension += int(dendrite.is_tension())
	var spacing := INF
	for i in level.neurons.size():
		for j in range(i + 1, level.neurons.size()):
			spacing = minf(spacing, level.neurons[i].solution_position.distance_to(level.neurons[j].solution_position))
	var receptors := PackedStringArray()
	for neuron in level.neurons:
		if neuron.is_receptor():
			receptors.append("%dx%d" % [int(neuron.reach), neuron.required_links])
	var lethal := "%d+%d" % [level.lethal_edges.size(), level.lethal_obstacles.size()] \
		if level.lethal_edges.size() + level.lethal_obstacles.size() > 0 else ""
	return "| %s | %s | %d | %d | %d | %d | %d | %s | %s | %d | %d | %d | %d | %s | %d | %d / %d |" % [
		level.mission_id, level.mission_name, level.chapter_id, level.neurons.size(),
		level.dendrites.size(), fixed, tension, lethal, " ".join(receptors),
		PuzzleModel.from_level(level).get_crossing_count(),
		moves, level.par_moves, int(level.par_time), "yes" if not level.story_text.is_empty() else "",
		int(spacing), int(edge_clearance(level, false)), int(edge_clearance(level, true))]


## Start positions where a dendrite passes closer than MIN_START_CLEARANCE to a neuron
## that is not one of its ends, as "neuron: a-b = distance" strings.
static func tight_spots(level: LevelData) -> PackedStringArray:
	var result := PackedStringArray()
	for dendrite in level.dendrites:
		var from := level.find_neuron(dendrite.a).position
		var to := level.find_neuron(dendrite.b).position
		for neuron in level.neurons:
			if neuron.id == dendrite.a or neuron.id == dendrite.b:
				continue
			var distance := neuron.position.distance_to(Geometry2D.get_closest_point_to_segment(neuron.position, from, to))
			if distance < MIN_START_CLEARANCE:
				result.append("%d: %d-%d = %d" % [neuron.id, dendrite.a, dendrite.b, int(distance)])
	return result


## Smallest distance from a neuron center to a dendrite not attached to it (readability:
## below the radius a dendrite visibly runs through a neuron).
static func edge_clearance(level: LevelData, use_solution: bool) -> float:
	var best := INF
	for dendrite in level.dendrites:
		var a := level.find_neuron(dendrite.a)
		var b := level.find_neuron(dendrite.b)
		var from := a.solution_position if use_solution else a.position
		var to := b.solution_position if use_solution else b.position
		for neuron in level.neurons:
			if neuron.id == dendrite.a or neuron.id == dendrite.b:
				continue
			var center := neuron.solution_position if use_solution else neuron.position
			best = minf(best, center.distance_to(Geometry2D.get_closest_point_to_segment(center, from, to)))
	return best


static func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("build_levels: cannot write %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(text)


static func _number(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, roundf(value)) else str(value)


static func _float(value: float) -> String:
	return "%d.0" % int(value) if is_equal_approx(value, roundf(value)) else str(value)


static func _vector(point: Vector2) -> String:
	return "Vector2(%s, %s)" % [_number(point.x), _number(point.y)]


static func _packed(points: PackedVector2Array) -> String:
	var values := PackedStringArray()
	for point in points:
		values.append(_number(point.x))
		values.append(_number(point.y))
	return "PackedVector2Array(%s)" % ", ".join(values)


static func _ints(values: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return ", ".join(parts)


static func _string(text: String) -> String:
	return '"%s"' % text.replace("\\", "\\\\").replace('"', '\\"')
