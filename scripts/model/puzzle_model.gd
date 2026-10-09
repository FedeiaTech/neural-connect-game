class_name PuzzleModel
extends RefCounted
## Pure puzzle rules (SDD 2, 8.1, 8.5): neuron positions, dendrite crossings, drag
## collisions, tension and win state. Holds no Node references; views listen to its signals.
##
## Crossing rule: two dendrites cross when their segments intersect (endpoints touching and
## collinear overlaps included) and they share no neuron. Edge id = index in LevelData.dendrites.
##
## Receptors and dynamic links (T7.3): a RECEPTOR neuron is immovable (is_fixed() is true). After
## every move each receptor first drops links whose neuron left its reach, then, while it has
## fewer than required_links, links the closest in-reach candidate (ties: lower id). Candidate =
## movable (not fixed, not a receptor), not yet linked to this receptor, no static dendrite to
## it. In reach: center distance - neuron radius <= reach. Links never get an edge id: they are
## keyed Vector2i(receptor_id, neuron_id). Crossings are computed over static edges + links with
## the same rule; get_crossing_edges() lists static ids only, get_crossing_links() the links,
## get_crossing_count() / get_crossing_points() / get_crossing_neurons() include both.
## Win (on release): zero crossings, every receptor holding required_links links and no
## contamination link.
##
## Toxic neurons (T8.2, SOFT rule): a TOXIC neuron is movable and never a link candidate. Whenever
## it is within a receptor's reach (same distance rule as links) it forms a contamination link,
## keyed Vector2i(receptor_id, neuron_id) in a separate sorted set: it uses no slot, does not count
## towards required_links and is a warning only (it is not a segment for crossing detection and
## never loses the level). A static dendrite between the two does not prevent it. It clears when
## the toxic neuron leaves the reach. contamination_formed / contamination_cleared notify changes;
## the layout built by from_level() has its contamination set without signals.

signal neuron_moved(id: int, pos: Vector2)
signal neuron_blocked(id: int, contact: Vector2)
signal crossings_changed(crossing_edges: Array[int], involved_neurons: Array[int])
## Separate from crossings_changed (whose payload stays as is for existing listeners): emitted
## whenever any crossing point moves, appears or disappears (see get_crossing_points()).
signal crossing_points_changed(points: PackedVector2Array)
signal tension_changed(edge_id: int, ratio: float)
signal edge_broke(edge_id: int)
## T7.2: the grabbed neuron touched a lethal wall. It stopped at the contact position, contact
## is the touched point on the wall, the grab is released and the model ignores all input.
signal neuron_destroyed(id: int, contact: Vector2)
## T7.2: lethal-wall proximity (0..1, see get_hazard_proximity) of a moved neuron changed.
signal hazard_proximity_changed(id: int, proximity: float)
## T7.3: dynamic receptor links.
signal link_formed(receptor_id: int, neuron_id: int)
signal link_broken(receptor_id: int, neuron_id: int)
## ratio 0..1 (see link_strain()), 1 at the reach limit. Emitted when a linked neuron moves.
signal link_strain_changed(receptor_id: int, neuron_id: int, ratio: float)
## T8.2: toxic neuron entered / left a receptor's reach.
signal contamination_formed(receptor_id: int, neuron_id: int)
signal contamination_cleared(receptor_id: int, neuron_id: int)
signal solved()

const NO_NEURON := -1
## Proximity warning range, in neuron radii of surface gap to the nearest lethal wall.
const HAZARD_WARNING_RADII := 2.0
## Authoring rule: start and solution positions keep at least this surface gap (in radii)
## from lethal walls.
const LETHAL_SAFE_MARGIN_RADII := 0.75
## Drag sub-step as a fraction of the neuron radius. A circle can clip a sharp corner between
## two samples by at most radius * (1 - sqrt(1 - (STEP_FACTOR / 2)^2)), about 0.2 px at radius 28.
const STEP_FACTOR := 0.25
const MIN_STEP := 1.0
## Binary search iterations to locate the contact point inside the blocked sub-step.
const BISECT_ITERATIONS := 16

var _ids: Array[int] = []
var _positions: Dictionary[int, Vector2] = {}
var _fixed: Dictionary[int, bool] = {}
var _edges: Array[Vector2i] = []
var _radius := 28.0
var _play_area := PackedVector2Array()
var _obstacles: Array[PackedVector2Array] = []

var _crossing_edges: Array[int] = []
var _crossing_neurons: Array[int] = []
var _crossing_count := 0
var _crossing_points := PackedVector2Array()
var _crossing_links: Array[Vector2i] = []

## Receptors (T7.3): id -> reach / required links; links per receptor (sorted neuron ids) and
## last notified strain per link.
var _reach: Dictionary[int, float] = {}
var _required: Dictionary[int, int] = {}
var _links: Dictionary[int, Array] = {}
var _strain: Dictionary[Vector2i, float] = {}
## Toxic neuron ids (T8.2) and the current contamination links (sorted Vector2i(receptor, neuron)).
var _toxic: Dictionary[int, bool] = {}
var _contamination: Array[Vector2i] = []
## Static neighbour pairs Vector2i(min, max), to exclude statically connected candidates.
var _static_pairs: Dictionary[Vector2i, bool] = {}

## TENSION edges only: edge id -> Vector2(rest_length, max_length).
var _tension_limits: Dictionary[int, Vector2] = {}
var _tension_ratios: Dictionary[int, float] = {}
## Neuron id -> ids of the TENSION edges attached to it.
var _tension_edges_by_neuron: Dictionary[int, Array] = {}
var _broken := false

## Lethal geometry (T7.2): valid play-area edge and obstacle indices, and every lethal segment
## as consecutive point pairs (edges first, then obstacle outlines).
var _lethal_edges: Dictionary[int, bool] = {}
var _lethal_obstacles: Dictionary[int, bool] = {}
var _lethal_segments := PackedVector2Array()
var _destroyed_id := NO_NEURON
## Last notified hazard proximity per neuron.
var _proximity: Dictionary[int, float] = {}

var _grabbed_id := NO_NEURON
var _moved_during_grab := false
var _move_count := 0
var _solved := false


## Builds a model from level data. The resource is copied, never mutated.
## With use_solution, neurons start at their reference solution positions (for validation).
## Expects a structurally valid level (see validate_level); returns null otherwise.
static func from_level(level: LevelData, use_solution := false) -> PuzzleModel:
	var model := PuzzleModel.new()
	model._radius = level.neuron_radius
	model._play_area = level.play_area.duplicate()
	for obstacle: PackedVector2Array in level.obstacles:
		model._obstacles.append(obstacle.duplicate())
	for index in level.lethal_edges:
		if index >= 0 and index < level.play_area.size():
			model._lethal_edges[index] = true
	for index in level.lethal_obstacles:
		if index >= 0 and index < level.obstacles.size():
			model._lethal_obstacles[index] = true
	model._lethal_segments = lethal_segments_of(level)
	for neuron: NeuronData in level.neurons:
		model._ids.append(neuron.id)
		model._positions[neuron.id] = neuron.solution_position if use_solution else neuron.position
		model._fixed[neuron.id] = neuron.fixed or neuron.is_receptor()
		if neuron.is_toxic():
			model._toxic[neuron.id] = true
		if neuron.is_receptor():
			model._reach[neuron.id] = neuron.reach
			model._required[neuron.id] = neuron.required_links
			model._links[neuron.id] = []
	for dendrite: DendriteData in level.dendrites:
		if not model._positions.has(dendrite.a) or not model._positions.has(dendrite.b):
			push_error("PuzzleModel: dendrite references a missing neuron (%d-%d)." % [dendrite.a, dendrite.b])
			return null
		var edge_id := model._edges.size()
		model._edges.append(Vector2i(dendrite.a, dendrite.b))
		model._static_pairs[Vector2i(mini(dendrite.a, dendrite.b), maxi(dendrite.a, dendrite.b))] = true
		if dendrite.is_tension():
			model._tension_limits[edge_id] = Vector2(dendrite.rest_length, dendrite.max_length)
			for neuron_id in [dendrite.a, dendrite.b]:
				if not model._tension_edges_by_neuron.has(neuron_id):
					model._tension_edges_by_neuron[neuron_id] = []
				model._tension_edges_by_neuron[neuron_id].append(edge_id)
			model._tension_ratios[edge_id] = model._compute_tension_ratio(edge_id)
	model._update_links(PuzzleModel.NO_NEURON, false)
	model._update_crossings(false)
	for id in model._ids:
		model._proximity[id] = model.get_hazard_proximity(id)
	return model


## Checks a hand-authored level and returns human-readable errors (empty = valid).
## Covers: play area and radius, null entries, duplicate neuron ids, dendrites referencing
## missing neurons, self-loops, duplicate edges, tension limits, start and solution placement
## (inside the area, outside obstacles, no overlaps), fixed neurons moved in the solution,
## a start layout without crossings (levels must start tangled) and crossings in the
## reference solution. Never mutates the level.
static func validate_level(level: LevelData) -> PackedStringArray:
	var errors := PackedStringArray()
	if level == null:
		errors.append("Level is null.")
		return errors
	var area_ok := level.play_area.size() >= 3
	if not area_ok:
		errors.append("Play area must have at least 3 points.")
	if level.neuron_radius <= 0.0:
		errors.append("Neuron radius must be greater than 0.")

	var structure_ok := true
	var neurons: Array[NeuronData] = []
	var by_id: Dictionary[int, NeuronData] = {}
	for i in level.neurons.size():
		var neuron := level.neurons[i]
		if neuron == null:
			errors.append("Neuron entry %d is null." % i)
			structure_ok = false
		elif by_id.has(neuron.id):
			errors.append("Duplicate neuron id %d." % neuron.id)
			structure_ok = false
		else:
			by_id[neuron.id] = neuron
			neurons.append(neuron)
			if neuron.fixed and neuron.solution_position != neuron.position:
				errors.append("Fixed neuron %d: solution_position must equal position." % neuron.id)
			if neuron.is_receptor():
				_validate_receptor(neuron, errors)
			if neuron.is_toxic() and neuron.fixed:
				errors.append("Toxic neuron %d must be movable (not fixed)." % neuron.id)

	var seen_pairs: Dictionary[Vector2i, int] = {}
	for i in level.dendrites.size():
		var dendrite := level.dendrites[i]
		if dendrite == null:
			errors.append("Dendrite entry %d is null." % i)
			structure_ok = false
			continue
		var missing := false
		for neuron_id: int in [dendrite.a, dendrite.b]:
			if not by_id.has(neuron_id):
				errors.append("Dendrite %d references missing neuron %d." % [i, neuron_id])
				missing = true
		if missing:
			structure_ok = false
			continue
		if dendrite.a == dendrite.b:
			errors.append("Dendrite %d is a self-loop on neuron %d." % [i, dendrite.a])
			continue
		var key := Vector2i(mini(dendrite.a, dendrite.b), maxi(dendrite.a, dendrite.b))
		if seen_pairs.has(key):
			errors.append("Dendrite %d duplicates dendrite %d (%d-%d)." % [i, seen_pairs[key], key.x, key.y])
		else:
			seen_pairs[key] = i
		if dendrite.is_tension():
			_validate_tension(i, dendrite, by_id, errors)

	for index in level.lethal_edges:
		if index < 0 or index >= level.play_area.size():
			errors.append("Lethal edge %d does not exist (play area has %d edges)." % [
				index, level.play_area.size()])
	for index in level.lethal_obstacles:
		if index < 0 or index >= level.obstacles.size():
			errors.append("Lethal obstacle %d does not exist (%d obstacles)." % [index, level.obstacles.size()])

	if area_ok and level.neuron_radius > 0.0:
		var lethal := lethal_segments_of(level)
		for use_solution in [false, true]:
			_validate_placement(level, neurons, use_solution, errors)
			_validate_lethal_margin(level, neurons, lethal, use_solution, errors)

	if structure_ok:
		var start := PuzzleModel.from_level(level)
		if start.is_contaminated():
			errors.append("Start layout has contamination link(s) %s: a toxic neuron starts inside a receptor's reach." % [
				start.get_contamination_links()])
		elif start.get_crossing_count() == 0:
			if start.get_receptor_ids().is_empty():
				errors.append("Start layout has no crossings: a level must start tangled.")
			elif start.are_receptors_satisfied():
				errors.append("Start layout is already solved: no crossings and every receptor linked.")
		var solution := PuzzleModel.from_level(level, true)
		if solution.get_crossing_count() > 0:
			errors.append("Solution layout has %d crossing(s) between dendrites %s and links %s." % [
				solution.get_crossing_count(), solution.get_crossing_edges(), solution.get_crossing_links()])
		if solution.is_contaminated():
			errors.append("Solution layout has contamination link(s) %s: a toxic neuron ends inside a receptor's reach." % [
				solution.get_contamination_links()])
		for receptor_id in solution.get_receptor_ids():
			if not solution.is_receptor_satisfied(receptor_id):
				errors.append("Solution layout leaves receptor %d with %d of %d link(s)." % [
					receptor_id, solution.get_link_count(receptor_id), solution.get_required_links(receptor_id)])
	return errors


static func _validate_receptor(neuron: NeuronData, errors: PackedStringArray) -> void:
	if neuron.reach <= 0.0:
		errors.append("Receptor %d: reach must be greater than 0." % neuron.id)
	if neuron.required_links < 1 or neuron.required_links > 2:
		errors.append("Receptor %d: required_links must be 1 or 2 (got %d)." % [neuron.id, neuron.required_links])
	if neuron.solution_position != neuron.position:
		errors.append("Receptor %d: solution_position must equal position (receptors never move)." % neuron.id)


static func _validate_tension(
	edge_id: int,
	dendrite: DendriteData,
	by_id: Dictionary[int, NeuronData],
	errors: PackedStringArray,
) -> void:
	if dendrite.max_length <= dendrite.rest_length:
		errors.append("Tension dendrite %d: max_length must be greater than rest_length." % edge_id)
		return
	var a := by_id[dendrite.a]
	var b := by_id[dendrite.b]
	var start_length := a.position.distance_to(b.position)
	var solution_length := a.solution_position.distance_to(b.solution_position)
	if start_length > dendrite.max_length:
		errors.append("Tension dendrite %d exceeds max_length at start positions (%.1f > %.1f)." % [
			edge_id, start_length, dendrite.max_length])
	if solution_length > dendrite.max_length:
		errors.append("Tension dendrite %d exceeds max_length at solution positions (%.1f > %.1f)." % [
			edge_id, solution_length, dendrite.max_length])


## Every lethal segment of a level as consecutive point pairs: lethal play-area edges first
## (in index order of lethal_edges), then the outline of each lethal obstacle. Invalid indices
## are skipped (validate_level reports them).
static func lethal_segments_of(level: LevelData) -> PackedVector2Array:
	var segments := PackedVector2Array()
	var area := level.play_area
	for index in level.lethal_edges:
		if index >= 0 and index < area.size():
			segments.append(area[index])
			segments.append(area[(index + 1) % area.size()])
	for index in level.lethal_obstacles:
		if index >= 0 and index < level.obstacles.size():
			var outline := level.obstacles[index]
			for i in outline.size():
				segments.append(outline[i])
				segments.append(outline[(i + 1) % outline.size()])
	return segments


## Surface gap between a circle and the nearest lethal segment (INF without lethal geometry).
static func lethal_gap(center: Vector2, radius: float, segments: PackedVector2Array) -> float:
	var best := INF
	for i in range(0, segments.size() - 1, 2):
		best = minf(best, GeometryUtils.distance_to_segment(center, segments[i], segments[i + 1]))
	return best - radius


## Proximity 0..1 for a surface gap: 1 at contact, 0 at (or beyond) the warning distance.
static func proximity_for_gap(gap: float, warning: float) -> float:
	if is_inf(gap) or warning <= 0.0:
		return 0.0
	return clampf(1.0 - gap / warning, 0.0, 1.0)


static func _validate_lethal_margin(
	level: LevelData,
	neurons: Array[NeuronData],
	lethal: PackedVector2Array,
	use_solution: bool,
	errors: PackedStringArray,
) -> void:
	if lethal.is_empty():
		return
	var margin := LETHAL_SAFE_MARGIN_RADII * level.neuron_radius
	for neuron in neurons:
		var center := neuron.solution_position if use_solution else neuron.position
		var gap := lethal_gap(center, level.neuron_radius, lethal)
		if gap < margin:
			errors.append("Neuron %d %s position is too close to a lethal wall (gap %.1f < %.1f)." % [
				neuron.id, "solution" if use_solution else "start", gap, margin])


static func _validate_placement(
	level: LevelData,
	neurons: Array[NeuronData],
	use_solution: bool,
	errors: PackedStringArray,
) -> void:
	var layout := "solution" if use_solution else "start"
	var radius := level.neuron_radius
	var min_distance := 2.0 * radius - GeometryUtils.EPSILON
	for i in neurons.size():
		var neuron := neurons[i]
		var center := neuron.solution_position if use_solution else neuron.position
		if not GeometryUtils.is_circle_in_playfield(center, radius, level.play_area, level.obstacles):
			errors.append("Neuron %d %s position is outside the play area or overlaps an obstacle." % [
				neuron.id, layout])
		for j in range(i + 1, neurons.size()):
			var other := neurons[j]
			var other_center := other.solution_position if use_solution else other.position
			if center.distance_to(other_center) < min_distance:
				errors.append("Neurons %d and %d overlap at %s positions." % [neuron.id, other.id, layout])


# --- Input -------------------------------------------------------------------

## Grabs a neuron for dragging. Refused (false) for unknown or fixed neurons, or while
## another neuron is grabbed (single pointer). Grabbing the already grabbed neuron is true.
func grab(id: int) -> bool:
	if is_lost() or not _positions.has(id) or _fixed[id]:
		return false
	if _grabbed_id != NO_NEURON:
		return _grabbed_id == id
	_grabbed_id = id
	_moved_during_grab = false
	return true


## Moves the grabbed neuron along the straight path to target. If the path is blocked by the
## play area outline, an obstacle or another neuron, the neuron stops at the last valid point
## (no sliding, no pushing), stays grabbed and neuron_blocked(id, stop_position) is emitted on
## every blocked call. Dendrites never block neurons.
## If the move stretches a TENSION dendrite beyond max_length, edge_broke is emitted, the grab
## is released and the model ignores further input (the owner rebuilds it).
## Lethal walls (T7.2): if the circle would touch a lethal segment first, the neuron stops at
## the contact position, neuron_destroyed is emitted (instead of neuron_blocked) and the model
## ignores further input as well.
func drag_to(target: Vector2) -> void:
	if _grabbed_id == NO_NEURON or is_lost():
		return
	var id := _grabbed_id
	var start := _positions[id]
	if start == target:
		return
	var step := maxf(_radius * STEP_FACTOR, MIN_STEP)
	var steps := maxi(ceili(start.distance_to(target) / step), 1)
	var reached := target
	var blocked := false
	var lethal_contact: Variant = null
	var last_valid_t := 0.0
	for i in range(1, steps + 1):
		var t := float(i) / steps
		if not _is_allowed_position(id, start.lerp(target, t)):
			var bounds := _bisect_contact(id, start, target, last_valid_t, t)
			reached = start.lerp(target, bounds.x)
			var beyond := start.lerp(target, bounds.y)
			if _touches_lethal(beyond):
				lethal_contact = nearest_lethal_point(beyond)
			blocked = true
			break
		last_valid_t = t
	if reached != start:
		_positions[id] = reached
		_moved_during_grab = true
		neuron_moved.emit(id, reached)
		_update_links(id, true)
		_update_crossings(true)
		_update_proximity(id)
		if lethal_contact == null:
			_update_tension(id)
	if lethal_contact != null:
		_destroy(id, lethal_contact)
	elif blocked and not _broken:
		neuron_blocked.emit(id, reached)


## Ends the current drag. One move = one grab-to-release during which the neuron actually
## changed position (a grab with no displacement, e.g. fully blocked, is not a move).
## With zero crossings (static edges and links) and every receptor fully linked the model
## becomes solved and emits solved() once per model.
func release() -> void:
	if _grabbed_id == NO_NEURON:
		return
	if _moved_during_grab:
		_move_count += 1
	_grabbed_id = NO_NEURON
	_moved_during_grab = false
	if not _solved and _crossing_count == 0 and are_receptors_satisfied() and _contamination.is_empty():
		_solved = true
		solved.emit()


## Nearest neuron whose center is within grab_radius of point, or NO_NEURON.
## Fixed neurons are returned too (views may react); grab() refuses them.
func pick_neuron(point: Vector2, grab_radius: float) -> int:
	var best_id := NO_NEURON
	var best_distance := grab_radius
	for id in _ids:
		var distance := point.distance_to(_positions[id])
		if distance <= best_distance:
			if best_id == NO_NEURON or distance < best_distance:
				best_id = id
				best_distance = distance
	return best_id


# --- Queries -----------------------------------------------------------------

func get_grabbed_id() -> int:
	return _grabbed_id


## Completed moves (see release()).
func get_move_count() -> int:
	return _move_count


## True once a release happened with zero crossings. Never resets for this model.
func is_solved() -> bool:
	return _solved


## True after a TENSION dendrite broke. The model then ignores all input.
func is_broken() -> bool:
	return _broken


## True after a neuron touched a lethal wall (T7.2). The model then ignores all input.
func is_destroyed() -> bool:
	return _destroyed_id != NO_NEURON


## The neuron destroyed by a lethal wall, or NO_NEURON.
func get_destroyed_id() -> int:
	return _destroyed_id


## True once the level is lost (tension break or destroyed neuron): input is ignored.
func is_lost() -> bool:
	return _broken or is_destroyed()


func has_lethal_geometry() -> bool:
	return not _lethal_segments.is_empty()


## Lethal segments as consecutive point pairs (see lethal_segments_of()).
func get_lethal_segments() -> PackedVector2Array:
	return _lethal_segments.duplicate()


func is_lethal_edge(index: int) -> bool:
	return _lethal_edges.has(index)


func is_lethal_obstacle(index: int) -> bool:
	return _lethal_obstacles.has(index)


## 0..1 danger of a neuron: 0 while its surface is HAZARD_WARNING_RADII radii or more from every
## lethal wall (or without lethal walls), rising linearly to 1 at contact.
func get_hazard_proximity(id: int) -> float:
	if _lethal_segments.is_empty() or not _positions.has(id):
		return 0.0
	return proximity_for_gap(lethal_gap(_positions[id], _radius, _lethal_segments),
		HAZARD_WARNING_RADII * _radius)


func is_tension_edge(edge_id: int) -> bool:
	return _tension_limits.has(edge_id)


## 0 at (or below) rest length, 1 at max length. Always 0 for NORMAL edges.
func get_tension_ratio(edge_id: int) -> float:
	return _tension_ratios.get(edge_id, 0.0)


func get_neuron_ids() -> Array[int]:
	return _ids.duplicate()


func has_neuron(id: int) -> bool:
	return _positions.has(id)


func get_neuron_position(id: int) -> Vector2:
	return _positions.get(id, Vector2.ZERO)


func is_fixed(id: int) -> bool:
	return _fixed.get(id, false)


func get_neuron_radius() -> float:
	return _radius


func get_play_area() -> PackedVector2Array:
	return _play_area.duplicate()


func get_obstacles() -> Array[PackedVector2Array]:
	return _obstacles.duplicate()


func get_edge_count() -> int:
	return _edges.size()


## Neuron ids at both ends of the edge (x = a, y = b).
func get_edge_endpoints(edge_id: int) -> Vector2i:
	return _edges[edge_id]


func get_edge_length(edge_id: int) -> float:
	var edge := _edges[edge_id]
	return _positions[edge.x].distance_to(_positions[edge.y])


## Sorted ids of every edge involved in at least one crossing.
func get_crossing_edges() -> Array[int]:
	return _crossing_edges.duplicate()


## Sorted ids of every neuron at the end of a crossing edge.
func get_crossing_neurons() -> Array[int]:
	return _crossing_neurons.duplicate()


## Number of crossing edge pairs.
func get_crossing_count() -> int:
	return _crossing_count


## Links involved in at least one crossing, as Vector2i(receptor_id, neuron_id), sorted.
func get_crossing_links() -> Array[Vector2i]:
	return _crossing_links.duplicate()


# --- Receptors (T7.3) --------------------------------------------------------------

## Strain of a link: (center distance - radius) / reach, clamped to 0..1 (1 at the reach limit).
static func link_strain(receptor_pos: Vector2, neuron_pos: Vector2, radius: float, reach: float) -> float:
	if reach <= 0.0:
		return 1.0
	return clampf((receptor_pos.distance_to(neuron_pos) - radius) / reach, 0.0, 1.0)


## Receptor ids in authoring order.
func get_receptor_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _ids:
		if _reach.has(id):
			ids.append(id)
	return ids


func is_receptor(id: int) -> bool:
	return _reach.has(id)


func get_receptor_reach(id: int) -> float:
	return _reach.get(id, 0.0)


func get_required_links(id: int) -> int:
	return _required.get(id, 0)


## Neuron ids linked to a receptor, sorted.
func get_links(receptor_id: int) -> Array[int]:
	var result: Array[int] = []
	result.assign(_links.get(receptor_id, []))
	return result


func get_link_count(receptor_id: int) -> int:
	return (_links.get(receptor_id, []) as Array).size()


func is_receptor_satisfied(receptor_id: int) -> bool:
	return get_link_count(receptor_id) >= get_required_links(receptor_id)


## True when every receptor holds its required links (true without receptors).
func are_receptors_satisfied() -> bool:
	for receptor_id: int in _reach:
		if not is_receptor_satisfied(receptor_id):
			return false
	return true


## True for a TOXIC neuron (T8.2).
func is_toxic(id: int) -> bool:
	return _toxic.has(id)


## True while any toxic neuron is within a receptor's reach.
func is_contaminated() -> bool:
	return not _contamination.is_empty()


## Contamination links as Vector2i(receptor_id, neuron_id), sorted.
func get_contamination_links() -> Array[Vector2i]:
	return _contamination.duplicate()


func has_contamination(receptor_id: int, neuron_id: int) -> bool:
	return _contamination.has(Vector2i(receptor_id, neuron_id))


## Every link as Vector2i(receptor_id, neuron_id), sorted by receptor then neuron.
func get_link_pairs() -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	for receptor_id in get_receptor_ids():
		for neuron_id: int in _links[receptor_id]:
			pairs.append(Vector2i(receptor_id, neuron_id))
	pairs.sort()
	return pairs


func has_link(receptor_id: int, neuron_id: int) -> bool:
	return (_links.get(receptor_id, []) as Array).has(neuron_id)


## Current strain of a link (0..1), 0 for an unknown link.
func get_link_strain(receptor_id: int, neuron_id: int) -> float:
	if not has_link(receptor_id, neuron_id):
		return 0.0
	return link_strain(_positions[receptor_id], _positions[neuron_id], _radius, _reach[receptor_id])


## Exact crossing positions, one per crossing pair (count == get_crossing_count()), in pair
## order. A collinear overlap is marked at the midpoint of the shared part.
func get_crossing_points() -> PackedVector2Array:
	return _crossing_points.duplicate()


## Recomputes crossings from current positions. Pure query: no state change, no signal.
func compute_crossings() -> Array[int]:
	return _find_crossings()[0]


# --- Internals ---------------------------------------------------------------

## True when neuron id may sit at center: inside the play area, outside obstacles and not
## overlapping any other neuron (touching is allowed).
func _is_free_position(id: int, center: Vector2) -> bool:
	if not GeometryUtils.is_circle_in_playfield(center, _radius, _play_area, _obstacles):
		return false
	var min_distance := 2.0 * _radius - GeometryUtils.EPSILON
	for other in _ids:
		if other != id and center.distance_to(_positions[other]) < min_distance:
			return false
	return true


## ratio = clamp((length - rest) / (max - rest), 0, 1); 0 when max <= rest.
func _compute_tension_ratio(edge_id: int) -> float:
	var limits := _tension_limits[edge_id]
	var span := limits.y - limits.x
	if span <= 0.0:
		return 0.0
	return clampf((get_edge_length(edge_id) - limits.x) / span, 0.0, 1.0)


## Refreshes the TENSION edges attached to the moved neuron; breaks the first one past max.
func _update_tension(moved_id: int) -> void:
	for edge_id: int in _tension_edges_by_neuron.get(moved_id, []):
		var ratio := _compute_tension_ratio(edge_id)
		if ratio != _tension_ratios[edge_id]:
			_tension_ratios[edge_id] = ratio
			tension_changed.emit(edge_id, ratio)
		if get_edge_length(edge_id) > _tension_limits[edge_id].y:
			_broken = true
			_grabbed_id = NO_NEURON
			_moved_during_grab = false
			edge_broke.emit(edge_id)
			return


## Bracket (x = last allowed t, y = first refused t) of the contact inside [valid_t, invalid_t],
## to bisection precision.
func _bisect_contact(id: int, start: Vector2, target: Vector2, valid_t: float, invalid_t: float) -> Vector2:
	var low := valid_t
	var high := invalid_t
	for i in BISECT_ITERATIONS:
		var mid := (low + high) * 0.5
		if _is_allowed_position(id, start.lerp(target, mid)):
			low = mid
		else:
			high = mid
	return Vector2(low, high)


## Free (see _is_free_position) and not touching a lethal wall.
func _is_allowed_position(id: int, center: Vector2) -> bool:
	return not _touches_lethal(center) and _is_free_position(id, center)


func _touches_lethal(center: Vector2) -> bool:
	return not _lethal_segments.is_empty() \
		and lethal_gap(center, _radius, _lethal_segments) <= GeometryUtils.EPSILON


## Closest point on any lethal segment to center (Vector2.INF without lethal geometry).
func nearest_lethal_point(center: Vector2) -> Vector2:
	var best := Vector2.INF
	var best_distance := INF
	for i in range(0, _lethal_segments.size() - 1, 2):
		var point := Geometry2D.get_closest_point_to_segment(center, _lethal_segments[i], _lethal_segments[i + 1])
		var distance := center.distance_to(point)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


## Receptor link maintenance (see the class documentation). moved_id: the neuron that moved
## (strain notifications only concern its links); NO_NEURON at build time.
func _update_links(moved_id: int, notify: bool) -> void:
	if _reach.is_empty():
		return
	for receptor_id in get_receptor_ids():
		var linked: Array = _links[receptor_id]
		for neuron_id: int in linked.duplicate():
			if not _in_reach(receptor_id, neuron_id):
				linked.erase(neuron_id)
				_strain.erase(Vector2i(receptor_id, neuron_id))
				if notify:
					link_broken.emit(receptor_id, neuron_id)
		while linked.size() < _required[receptor_id]:
			var candidate := _closest_candidate(receptor_id)
			if candidate == NO_NEURON:
				break
			linked.append(candidate)
			linked.sort()
			_strain[Vector2i(receptor_id, candidate)] = get_link_strain(receptor_id, candidate)
			if notify:
				link_formed.emit(receptor_id, candidate)
		if notify and linked.has(moved_id):
			var key := Vector2i(receptor_id, moved_id)
			var strain := get_link_strain(receptor_id, moved_id)
			if strain != _strain.get(key, -1.0):
				_strain[key] = strain
				link_strain_changed.emit(receptor_id, moved_id, strain)
	_update_contamination(notify)


## Recomputes the contamination links (toxic neuron within a receptor's reach); clears are
## announced before formations.
func _update_contamination(notify: bool) -> void:
	if _toxic.is_empty():
		return
	var current: Array[Vector2i] = []
	for receptor_id in get_receptor_ids():
		for id in _ids:
			if _toxic.has(id) and _in_reach(receptor_id, id):
				current.append(Vector2i(receptor_id, id))
	current.sort()
	if current == _contamination:
		return
	var before := _contamination
	_contamination = current
	if not notify:
		return
	for pair in before:
		if not current.has(pair):
			contamination_cleared.emit(pair.x, pair.y)
	for pair in current:
		if not before.has(pair):
			contamination_formed.emit(pair.x, pair.y)


func _in_reach(receptor_id: int, neuron_id: int) -> bool:
	return _positions[receptor_id].distance_to(_positions[neuron_id]) - _radius \
		<= _reach[receptor_id] + GeometryUtils.EPSILON


## Closest unlinked candidate within reach (ties: lower id), or NO_NEURON.
func _closest_candidate(receptor_id: int) -> int:
	var best := NO_NEURON
	var best_distance := INF
	var linked: Array = _links[receptor_id]
	for id in _ids:
		if _fixed[id] or _toxic.has(id) or linked.has(id) or not _in_reach(receptor_id, id):
			continue
		if _static_pairs.has(Vector2i(mini(id, receptor_id), maxi(id, receptor_id))):
			continue
		var distance := _positions[receptor_id].distance_to(_positions[id])
		if distance < best_distance or (distance == best_distance and id < best):
			best = id
			best_distance = distance
	return best


func _destroy(id: int, contact: Vector2) -> void:
	_destroyed_id = id
	_grabbed_id = NO_NEURON
	_moved_during_grab = false
	neuron_destroyed.emit(id, contact)


func _update_proximity(id: int) -> void:
	if _lethal_segments.is_empty():
		return
	var proximity := get_hazard_proximity(id)
	if proximity != _proximity.get(id, 0.0):
		_proximity[id] = proximity
		hazard_proximity_changed.emit(id, proximity)


## Returns [crossing_edges: Array[int] (sorted static ids), pair_count: int,
## points: PackedVector2Array (one per pair, in pair order), crossing_links: Array[Vector2i]
## (sorted)]. Segments = static edges (index = edge id) followed by the links. O(S^2).
func _find_crossings() -> Array:
	var segments: Array[Vector2i] = _edges.duplicate()
	segments.append_array(get_link_pairs())
	var edge_count := _edges.size()
	var flagged: Dictionary[int, bool] = {}
	var pairs := 0
	var points := PackedVector2Array()
	for i in segments.size():
		var e1 := segments[i]
		var a1 := _positions[e1.x]
		var a2 := _positions[e1.y]
		for j in range(i + 1, segments.size()):
			var e2 := segments[j]
			if e2.x == e1.x or e2.x == e1.y or e2.y == e1.x or e2.y == e1.y:
				continue
			var point: Variant = GeometryUtils.crossing_point(a1, a2, _positions[e2.x], _positions[e2.y])
			if point != null:
				flagged[i] = true
				flagged[j] = true
				pairs += 1
				points.append(point)
	var edges: Array[int] = []
	var links: Array[Vector2i] = []
	for index: int in flagged:
		if index < edge_count:
			edges.append(index)
		else:
			links.append(segments[index])
	edges.sort()
	links.sort()
	return [edges, pairs, points, links]


func _update_crossings(notify: bool) -> void:
	var result := _find_crossings()
	var edges: Array[int] = result[0]
	var count: int = result[1]
	var points: PackedVector2Array = result[2]
	var links: Array[Vector2i] = result[3]
	var points_changed := points != _crossing_points
	_crossing_points = points
	# The pair count can change while the set of crossing edges stays the same.
	if edges != _crossing_edges or count != _crossing_count or links != _crossing_links:
		_crossing_count = count
		_crossing_edges = edges
		_crossing_links = links
		var involved: Dictionary[int, bool] = {}
		for edge_id in edges:
			involved[_edges[edge_id].x] = true
			involved[_edges[edge_id].y] = true
		for link in links:
			involved[link.x] = true
			involved[link.y] = true
		_crossing_neurons.assign(involved.keys())
		_crossing_neurons.sort()
		if notify:
			crossings_changed.emit(get_crossing_edges(), get_crossing_neurons())
	if notify and points_changed:
		crossing_points_changed.emit(get_crossing_points())
