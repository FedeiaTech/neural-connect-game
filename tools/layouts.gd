extends RefCounted
## Authoring helpers (T8.4/T8.5), not game code: deterministic solution layouts for the new
## missions of tools/level_specs.gd. A layout is a spread of neuron positions inside an arena
## (best-candidate sampling with a seeded generator) wired by the Delaunay triangulation of those
## points, which is planar by construction, then thinned so the solution stays readable:
## no dendrite grazes a neuron it does not connect and the hand-picked degree stays high enough
## for cycles. The same seed always gives the same layout, so the generated .tres files are
## byte-stable. Everything is rounded to whole pixels.

const RADIUS := 28.0


## count positions inside the arena (neuron circle plus `margin` fully inside, outside the
## obstacles), at least min_dist apart, each at least RADIUS + avoid_gap from the avoid segments
## (pairs a0, b0, a1, b1, ...; e.g. lethal walls). `fixed` positions are kept first and count
## towards the total. Best-candidate sampling: of 28 random candidates the one farthest from the
## points chosen so far wins, which spreads the network evenly like cells in a tissue.
static func scatter(area: PackedVector2Array, obstacles: Array, count: int, min_dist: float,
		margin: float, seed_value: int, avoid := PackedVector2Array(), avoid_gap := 0.0,
		fixed := PackedVector2Array()) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var bounds := Rect2(area[0], Vector2.ZERO)
	for point in area:
		bounds = bounds.expand(point)
	var typed: Array[PackedVector2Array] = []
	for outline: PackedVector2Array in obstacles:
		typed.append(outline)
	var points := fixed.duplicate()
	var attempts := 0
	while points.size() < count and attempts < 20000:
		var best := Vector2.INF
		var best_distance := -1.0
		for k in 28:
			attempts += 1
			var candidate := Vector2(rng.randf_range(bounds.position.x, bounds.end.x),
				rng.randf_range(bounds.position.y, bounds.end.y)).round()
			if not GeometryUtils.is_circle_in_playfield(candidate, RADIUS + margin, area, typed):
				continue
			if not _clear_of_segments(candidate, avoid, RADIUS + avoid_gap):
				continue
			var nearest := INF
			for other in points:
				nearest = minf(nearest, candidate.distance_to(other))
			if nearest < min_dist:
				continue
			if nearest > best_distance:
				best = candidate
				best_distance = nearest
		if best != Vector2.INF:
			points.append(best)
	if points.size() < count:
		push_error("Layouts.scatter: only %d of %d points fit (seed %d)." % [points.size(), count, seed_value])
	return points


## Planar dendrite list [[a, b], ...] (a < b, sorted) over the points: Delaunay edges no longer
## than max_len, minus edges passing within `clearance` of a point they do not connect, minus a
## `drop` share of the longest ones (seeded) while both ends keep at least min_degree edges.
static func planar_edges(points: PackedVector2Array, max_len: float, clearance: float,
		drop: float, seed_value: int, min_degree := 2, protected: Array = []) -> Array:
	var triangles := Geometry2D.triangulate_delaunay(points)
	var pairs := {}
	for t in range(0, triangles.size(), 3):
		for k in 3:
			var a := triangles[t + k]
			var b := triangles[t + (k + 1) % 3]
			pairs[Vector2i(mini(a, b), maxi(a, b))] = true
	var edges: Array[Vector2i] = []
	for pair: Vector2i in pairs:
		if points[pair.x].distance_to(points[pair.y]) <= max_len:
			edges.append(pair)
	edges.sort_custom(func(l: Vector2i, r: Vector2i) -> bool:
		var dl := points[l.x].distance_to(points[l.y])
		var dr := points[r.x].distance_to(points[r.y])
		return dl > dr or (dl == dr and (l.x < r.x or (l.x == r.x and l.y < r.y))))
	var kept: Array[Vector2i] = []
	for edge in edges:
		if _grazes(points, edge, clearance):
			continue
		kept.append(edge)
	var degree := {}
	for edge in kept:
		degree[edge.x] = degree.get(edge.x, 0) + 1
		degree[edge.y] = degree.get(edge.y, 0) + 1
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var result: Array[Vector2i] = []
	for edge in kept:
		var roll := rng.randf()
		var removable: bool = degree.get(edge.x, 0) > min_degree and degree.get(edge.y, 0) > min_degree
		if roll < drop and removable and not protected.has([edge.x, edge.y]):
			degree[edge.x] -= 1
			degree[edge.y] -= 1
			continue
		result.append(edge)
	result.sort_custom(func(l: Vector2i, r: Vector2i) -> bool:
		return l.x < r.x or (l.x == r.x and l.y < r.y))
	var list := []
	for edge in result:
		list.append([edge.x, edge.y])
	return list


## Up to `count` extra "chord" pairs [a, b] (not in edges, no shared ends, distance between
## min_d and max_d, no other point within `clearance` of the segment), chosen with a seeded
## shuffle. Diseased dendrites are chords: long in the solution (they break), short at start.
static func chords(points: PackedVector2Array, edges: Array, count: int, min_d: float, max_d: float,
		clearance: float, seed_value: int, exclude: Array = []) -> Array:
	var existing := {}
	for edge: Array in edges:
		existing[Vector2i(mini(edge[0], edge[1]), maxi(edge[0], edge[1]))] = true
	var candidates: Array[Vector2i] = []
	for a in points.size():
		for b in range(a + 1, points.size()):
			var distance := points[a].distance_to(points[b])
			if distance < min_d or distance > max_d or existing.has(Vector2i(a, b)):
				continue
			if exclude.has(a) or exclude.has(b):
				continue
			if _grazes(points, Vector2i(a, b), clearance):
				continue
			candidates.append(Vector2i(a, b))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var chosen := []
	var used := {}
	while chosen.size() < count and not candidates.is_empty():
		var pick := rng.randi_range(0, candidates.size() - 1)
		var pair := candidates[pick]
		candidates.remove_at(pick)
		if used.has(pair.x) or used.has(pair.y):
			continue
		used[pair.x] = true
		used[pair.y] = true
		chosen.append([pair.x, pair.y])
	return chosen


## Tension limits for an existing edge: [a, b, rest, max] where max = about 1.25 x the solution
## length (the solution sits at 80% of the limit, never above it) and rest = 0.78 x the solution
## length, both rounded down to whole 10s.
static func tension(points: PackedVector2Array, edge: Array) -> Array:
	var length := points[edge[0]].distance_to(points[edge[1]])
	return [edge[0], edge[1], floorf(length * 0.78 / 10.0) * 10.0, floorf(length * 1.25 / 10.0) * 10.0]


## Diseased limits for a chord: [a, b, rest, max, "diseased"] with max = 0.8 x the solution
## length (so the solution length breaks it) and rest = 0.55 x the solution length, rounded down.
static func diseased(points: PackedVector2Array, edge: Array) -> Array:
	var length := points[edge[0]].distance_to(points[edge[1]])
	return [edge[0], edge[1], floorf(length * 0.55 / 10.0) * 10.0, floorf(length * 0.8 / 10.0) * 10.0, "diseased"]


## Turns `count` of the edges (a stride of 3 through the list from `offset`) whose solution length
## is at least min_len into tension dendrites.
static func with_tension(points: PackedVector2Array, edges: Array, count: int, min_len: float,
		offset := 0) -> Array:
	var result := edges.duplicate(true)
	var picked := 0
	var visited := 0
	var i := offset % maxi(result.size(), 1)
	while picked < count and visited < result.size():
		var edge: Array = result[i]
		if edge.size() == 2 and points[edge[0]].distance_to(points[edge[1]]) >= min_len:
			result[i] = tension(points, edge)
			picked += 1
			i = (i + 3) % result.size()
		else:
			i = (i + 1) % result.size()
		visited += 1
	return result


## Receptor wiring for one receptor of a layout: its `required` nearest eligible neurons are the
## partners, the reach just holds the farthest of them, and `toxic_count` toxic neurons are the
## next ones out that are at least 70 px beyond (so they sit outside the halo). `exclude` lists
## ids that can be neither (other receptors, anchors, already chosen toxic neurons).
## Returns {"reach": float, "partners": Array, "toxic": Array}.
static func receptor_plan(points: PackedVector2Array, receptor: int, required: int, toxic_count: int,
		exclude: Array = []) -> Dictionary:
	var others: Array[int] = []
	for i in points.size():
		if i != receptor and not exclude.has(i):
			others.append(i)
	others.sort_custom(func(l: int, r: int) -> bool:
		return points[receptor].distance_to(points[l]) < points[receptor].distance_to(points[r]))
	var partners := others.slice(0, required)
	var last := points[receptor].distance_to(points[partners[required - 1]])
	var toxic := []
	for i in range(required, others.size()):
		if toxic.size() >= toxic_count:
			break
		if points[receptor].distance_to(points[others[i]]) >= last + 70.0:
			toxic.append(others[i])
	return {"reach": snappedf(last - RADIUS + 14.0, 5.0), "partners": partners, "toxic": toxic}


## Several receptors at once. defs: [[receptor_id, required_links, toxic_count], ...]. Each
## receptor's partners are its `required` nearest eligible neurons and its reach just holds the
## farthest of them; every toxic neuron is the point nearest to its receptor that lies outside
## EVERY receptor's reach by at least 70 px (and is no partner). `exclude`: ids that can be
## neither (anchors). Returns {"receptors": {id: [reach, required]}, "toxic": Array}.
static func receptor_plans(points: PackedVector2Array, defs: Array, exclude: Array = []) -> Dictionary:
	var receptor_ids: Array = []
	for def: Array in defs:
		receptor_ids.append(def[0])
	var blocked: Array = receptor_ids + exclude
	var receptors := {}
	var partners: Array = []
	for def: Array in defs:
		var plan := receptor_plan(points, def[0], def[1], 0, blocked)
		receptors[def[0]] = [plan["reach"], def[1]]
		partners.append_array(plan["partners"])
	var toxic: Array = []
	for def: Array in defs:
		for k in def[2]:
			var best := -1
			var best_distance := INF
			for p in points.size():
				if blocked.has(p) or partners.has(p) or toxic.has(p):
					continue
				var outside := true
				for r: int in receptor_ids:
					if points[p].distance_to(points[r]) - RADIUS < receptors[r][0] + 70.0:
						outside = false
						break
				var distance := points[p].distance_to(points[def[0]])
				if outside and distance < best_distance:
					best = p
					best_distance = distance
			if best >= 0:
				toxic.append(best)
			else:
				push_error("Layouts.receptor_plans: no room for a toxic neuron")
	return {"receptors": receptors, "toxic": toxic}


## Receptor sites: for each entry of `required` (links needed) the point whose required-th nearest
## neighbor is closest (a dense spot keeps the halo small), at least min_sep from the sites
## already chosen and not in `exclude`. Returns the point indices in order.
static func dense_sites(points: PackedVector2Array, required: Array, min_sep: float, exclude: Array = []) -> Array:
	var sites: Array = []
	for need: int in required:
		var best := -1
		var best_reach := INF
		for p in points.size():
			if exclude.has(p) or sites.has(p):
				continue
			var far_enough := true
			for site: int in sites:
				if points[p].distance_to(points[site]) < min_sep:
					far_enough = false
			if not far_enough:
				continue
			var distances: Array[float] = []
			for q in points.size():
				if q != p and not exclude.has(q) and not sites.has(q):
					distances.append(points[p].distance_to(points[q]))
			distances.sort()
			if distances[need - 1] < best_reach:
				best_reach = distances[need - 1]
				best = p
		sites.append(best)
	return sites


## Index of the point nearest to target.
static func nearest_index(points: PackedVector2Array, target: Vector2) -> int:
	var best := 0
	for i in points.size():
		if points[i].distance_to(target) < points[best].distance_to(target):
			best = i
	return best


static func _clear_of_segments(point: Vector2, segments: PackedVector2Array, distance: float) -> bool:
	for i in range(0, segments.size() - 1, 2):
		if GeometryUtils.distance_to_segment(point, segments[i], segments[i + 1]) < distance:
			return false
	return true


static func _grazes(points: PackedVector2Array, edge: Vector2i, clearance: float) -> bool:
	for i in points.size():
		if i == edge.x or i == edge.y:
			continue
		if GeometryUtils.distance_to_segment(points[i], points[edge.x], points[edge.y]) < clearance:
			return true
	return false
