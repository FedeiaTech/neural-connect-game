extends RefCounted
## Deterministic solution planner for authored missions. Test and tooling support only: the
## game never generates or solves levels at runtime.
##
## plan(level) returns {"ok": bool, "moves": Array[Dictionary], "reason": String}. Each move is
## {"id": int, "points": Array[Vector2]}: one grab, one drag_to per point, one release.
## replay(level, moves) runs a plan on a real PuzzleModel, which is the actual proof.
##
## The planner mirrors the PuzzleModel drag rules with a safety margin, so a plan it accepts
## also succeeds on the model: same sub-step sampling along every segment, the circle at least
## CLEARANCE inside the playfield, at least CLEARANCE away from every other neuron (checked
## against the whole segment, not only the samples), and every TENSION dendrite of the dragged
## neuron at most max_length - CLEARANCE at every drag point (the model checks tension at the
## end of each drag_to call; along a straight segment the distance to a still partner peaks
## at an endpoint).
##
## Strategy (greedy, lowest misplaced id first, restarted after every move):
## 1. drag a misplaced neuron to its solution position, straight or along a grid path
##    (breadth-first search on a GRID_STEP lattice, then shortened by string pulling);
## 2. else park a misplaced neuron that sits on another neuron's solution spot at the nearest
##    reachable free spot that blocks no solution spot;
## 3. else move a neuron as close to its solution spot as its TENSION dendrites allow.
## It stops as soon as the layout has zero crossings, like the game does on release.

const CLEARANCE := 2.0
const GRID_STEP := 40.0
## Grid neighbours (8-connected).
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const MAX_MOVES_PER_NEURON := 4
## Surface gap kept from lethal walls: half the authoring margin, so every valid start
## position is still usable while no plan point ever touches a wall.
const LETHAL_MARGIN := PuzzleModel.LETHAL_SAFE_MARGIN_RADII * 28.0 * 0.5
## Step 3 only counts when it brings the neuron at least this much closer to its spot.
const MIN_APPROACH := GRID_STEP

var _radius := 28.0
var _play_area := PackedVector2Array()
var _obstacles: Array[PackedVector2Array] = []
## Lethal segments (T7.2) as point pairs; the plan keeps LETHAL_MARGIN away from them.
var _lethal := PackedVector2Array()
var _ids: Array[int] = []
var _positions: Dictionary[int, Vector2] = {}
var _targets: Dictionary[int, Vector2] = {}
var _fixed: Dictionary[int, bool] = {}
var _edges: Array[Vector2i] = []
## Neuron id -> Array of Vector2(partner id, max_length).
var _tension: Dictionary[int, Array] = {}
## Grid cell -> point, for cells whose point lies in the playfield with clearance.
var _grid: Dictionary[Vector2i, Vector2] = {}
var _grid_origin := Vector2.ZERO
## Static (playfield only) validity of grid links: "cell|direction" -> bool.
var _link_cache: Dictionary[String, bool] = {}


## Plans a solution for a valid level. See the class documentation.
func plan(level: LevelData) -> Dictionary:
	_setup(level)
	var moves: Array[Dictionary] = []
	var movable := 0
	for id in _ids:
		if not _fixed[id]:
			movable += 1
	var limit := maxi(movable, 1) * MAX_MOVES_PER_NEURON
	while _crossing_count() > 0:
		if moves.size() >= limit:
			return {"ok": false, "moves": moves, "reason": "move limit (%d) reached" % limit}
		var move := _next_move()
		if move.is_empty():
			return {"ok": false, "moves": moves, "reason": "stuck after %d moves; misplaced %s" % [
				moves.size(), _misplaced()]}
		var points: Array[Vector2] = move["points"]
		_positions[move["id"]] = points[-1]
		moves.append(move)
	return {"ok": true, "moves": moves, "reason": ""}


## Runs a plan on a fresh PuzzleModel built from the level. Returns {"model": PuzzleModel,
## "error": String}; error is empty when every grab was accepted, every drag reached its point
## and no TENSION dendrite broke. The caller asserts model.is_solved().
static func replay(level: LevelData, moves: Array) -> Dictionary:
	var model := PuzzleModel.from_level(level)
	for i in moves.size():
		var move: Dictionary = moves[i]
		var id: int = move["id"]
		if not model.grab(id):
			return {"model": model, "error": "move %d: grab of neuron %d refused" % [i, id]}
		for point: Vector2 in move["points"]:
			model.drag_to(point)
			if model.is_broken():
				return {"model": model, "error": "move %d: a tension dendrite broke" % i}
			if model.is_destroyed():
				return {"model": model, "error": "move %d: neuron %d touched a lethal wall" % [i, id]}
			if model.get_neuron_position(id) != point:
				return {"model": model, "error": "move %d: neuron %d blocked at %s before %s" % [
					i, id, model.get_neuron_position(id), point]}
		model.release()
	return {"model": model, "error": ""}


func _setup(level: LevelData) -> void:
	_radius = level.neuron_radius
	_play_area = level.play_area
	_obstacles = level.obstacles
	_lethal = PuzzleModel.lethal_segments_of(level)
	for neuron in level.neurons:
		_ids.append(neuron.id)
		_positions[neuron.id] = neuron.position
		_targets[neuron.id] = neuron.solution_position
		_fixed[neuron.id] = neuron.fixed
		_tension[neuron.id] = []
	_ids.sort()
	for dendrite in level.dendrites:
		_edges.append(Vector2i(dendrite.a, dendrite.b))
		if dendrite.is_tension():
			_tension[dendrite.a].append(Vector2(dendrite.b, dendrite.max_length))
			_tension[dendrite.b].append(Vector2(dendrite.a, dendrite.max_length))
	var bounds := Rect2(_play_area[0], Vector2.ZERO)
	for point in _play_area:
		bounds = bounds.expand(point)
	_grid_origin = bounds.position + Vector2.ONE * GRID_STEP * 0.5
	var columns := int(bounds.size.x / GRID_STEP) + 1
	var rows := int(bounds.size.y / GRID_STEP) + 1
	for x in columns:
		for y in rows:
			var point := _grid_origin + Vector2(x, y) * GRID_STEP
			if _in_playfield(point):
				_grid[Vector2i(x, y)] = point


func _misplaced() -> Array[int]:
	var result: Array[int] = []
	for id in _ids:
		if not _fixed[id] and _positions[id] != _targets[id]:
			result.append(id)
	return result


func _next_move() -> Dictionary:
	var misplaced := _misplaced()
	for id in misplaced:
		var points := _path_to(id, _targets[id])
		if not points.is_empty():
			return {"id": id, "points": points}
	for id in misplaced:
		for blocker in misplaced:
			if blocker != id and _positions[blocker].distance_to(_targets[id]) < _min_gap():
				var points := _park(blocker)
				if not points.is_empty():
					return {"id": blocker, "points": points}
	for id in misplaced:
		var points := _approach(id)
		if not points.is_empty():
			return {"id": id, "points": points}
	return {}


# --- Path search -------------------------------------------------------------

## Points to drag through to reach goal, or [] when unreachable.
func _path_to(id: int, goal: Vector2) -> Array[Vector2]:
	var from := _positions[id]
	if from == goal or not _is_free(id, goal) or not _tension_ok(id, goal):
		return []
	if _segment_free(id, from, goal):
		return [goal]
	var search := _search(id)
	for cell: Vector2i in search["order"]:
		var point := _grid[cell]
		if point.distance_to(goal) <= GRID_STEP * 1.5 and _segment_free(id, point, goal):
			return _shorten(id, from, _cell_path(search["parents"], cell), goal)
	return []


## Path to the nearest reachable free spot away from every other misplaced neuron's spot.
func _park(id: int) -> Array[Vector2]:
	var search := _search(id)
	var others := _misplaced()
	others.erase(id)
	for cell: Vector2i in search["order"]:
		var point := _grid[cell]
		var clear := true
		for other in others:
			if point.distance_to(_targets[other]) < _min_gap() + _radius:
				clear = false
				break
		if clear and point.distance_to(_positions[id]) > _radius:
			var cells := _cell_path(search["parents"], cell)
			cells.pop_back()
			return _shorten(id, _positions[id], cells, point)
	return []


## Path to the reachable spot closest to the neuron's solution spot (tension-limited moves).
func _approach(id: int) -> Array[Vector2]:
	var target := _targets[id]
	var current := _positions[id].distance_to(target)
	var search := _search(id)
	var best_cell := Vector2i.ZERO
	var best := current - MIN_APPROACH
	var found := false
	for cell: Vector2i in search["order"]:
		var distance := _grid[cell].distance_to(target)
		if distance < best:
			best = distance
			best_cell = cell
			found = true
	if not found:
		return []
	var cells := _cell_path(search["parents"], best_cell)
	cells.pop_back()
	return _shorten(id, _positions[id], cells, _grid[best_cell])


## Breadth-first search over free grid cells reachable from the neuron's position.
## Returns {"order": Array[Vector2i] (visit order), "parents": Dictionary[Vector2i, Vector2i]}
## where a start cell is its own parent.
func _search(id: int) -> Dictionary:
	var from := _positions[id]
	var order: Array[Vector2i] = []
	var parents: Dictionary[Vector2i, Vector2i] = {}
	var base := Vector2i(((from - _grid_origin) / GRID_STEP).floor())
	for dx in range(-1, 3):
		for dy in range(-1, 3):
			var cell := base + Vector2i(dx, dy)
			if _cell_usable(id, cell) and _segment_free(id, from, _grid[cell]):
				parents[cell] = cell
				order.append(cell)
	var head := 0
	while head < order.size():
		var cell := order[head]
		head += 1
		for direction in DIRECTIONS:
			var next := cell + direction
			if parents.has(next) or not _cell_usable(id, next):
				continue
			if _link_static_ok(cell, direction) and _segment_clear_of_neurons(id, _grid[cell], _grid[next]):
				parents[next] = cell
				order.append(next)
	return {"order": order, "parents": parents}


func _cell_usable(id: int, cell: Vector2i) -> bool:
	return _grid.has(cell) and _clear_of_neurons(id, _grid[cell]) and _tension_ok(id, _grid[cell])


func _cell_path(parents: Dictionary, last: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = [last]
	while parents[cells[0]] != cells[0]:
		cells.push_front(parents[cells[0]])
	return cells


## String pulling: from each point, jump to the farthest later point reachable in one segment.
func _shorten(id: int, from: Vector2, cells: Array[Vector2i], goal: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = [from]
	for cell in cells:
		points.append(_grid[cell])
	points.append(goal)
	var result: Array[Vector2] = []
	var current := 0
	while current < points.size() - 1:
		var next := points.size() - 1
		while next > current + 1 and not _segment_free(id, points[current], points[next]):
			next -= 1
		result.append(points[next])
		current = next
	return result


# --- Rules (mirroring PuzzleModel with CLEARANCE) ----------------------------

func _min_gap() -> float:
	return 2.0 * _radius + CLEARANCE


## Inside the playfield with CLEARANCE and at least LETHAL_MARGIN (surface gap) from every
## lethal wall, so a plan never touches one.
func _in_playfield(center: Vector2) -> bool:
	if not _lethal.is_empty() and PuzzleModel.lethal_gap(center, _radius, _lethal) < LETHAL_MARGIN:
		return false
	return GeometryUtils.is_circle_in_playfield(center, _radius + CLEARANCE, _play_area, _obstacles)


func _clear_of_neurons(id: int, center: Vector2) -> bool:
	for other in _ids:
		if other != id and center.distance_to(_positions[other]) < _min_gap():
			return false
	return true


func _is_free(id: int, center: Vector2) -> bool:
	return _in_playfield(center) and _clear_of_neurons(id, center)


func _tension_ok(id: int, center: Vector2) -> bool:
	for link: Vector2 in _tension[id]:
		if center.distance_to(_positions[int(link.x)]) > link.y - CLEARANCE:
			return false
	return true


## Same sub-steps as PuzzleModel.drag_to for the playfield, whole segment for other neurons.
func _segment_free(id: int, from: Vector2, to: Vector2) -> bool:
	return _segment_in_playfield(from, to) and _segment_clear_of_neurons(id, from, to)


func _segment_in_playfield(from: Vector2, to: Vector2) -> bool:
	var step := maxf(_radius * PuzzleModel.STEP_FACTOR, PuzzleModel.MIN_STEP)
	var steps := maxi(ceili(from.distance_to(to) / step), 1)
	for i in range(1, steps + 1):
		if not _in_playfield(from.lerp(to, float(i) / steps)):
			return false
	return true


func _segment_clear_of_neurons(id: int, from: Vector2, to: Vector2) -> bool:
	for other in _ids:
		if other == id:
			continue
		var closest := Geometry2D.get_closest_point_to_segment(_positions[other], from, to)
		if closest.distance_to(_positions[other]) < _min_gap():
			return false
	return true


func _link_static_ok(cell: Vector2i, direction: Vector2i) -> bool:
	var key := "%d,%d|%d,%d" % [cell.x, cell.y, direction.x, direction.y]
	if not _link_cache.has(key):
		_link_cache[key] = _segment_in_playfield(_grid[cell], _grid[cell + direction])
	return _link_cache[key]


func _crossing_count() -> int:
	var count := 0
	for i in _edges.size():
		var e1 := _edges[i]
		for j in range(i + 1, _edges.size()):
			var e2 := _edges[j]
			if e2.x == e1.x or e2.x == e1.y or e2.y == e1.x or e2.y == e1.y:
				continue
			if GeometryUtils.segments_cross(_positions[e1.x], _positions[e1.y], _positions[e2.x], _positions[e2.y]):
				count += 1
	return count
