extends RefCounted
## Hand-designed campaign (SDD 7, 7.1): the single source for data/levels/mXX.tres and
## data/campaign.tres, built offline by tools/build_levels.gd. Nothing here runs in the game.
##
## Texts are translation keys (T6.3); their English and Spanish live in locale/translations.csv:
##   chapter title/subtitle: CHAPTER_<n>_TITLE / CHAPTER_<n>_SUBTITLE
##   mission name/story: MISSION_<ID>_NAME / MISSION_<ID>_STORY (story at most 2 lines)
##
## Mission spec keys:
##   id, name, chapter, story ("" for none), par_time (s), par_moves (optional; default is
##   twice the planned solution moves, see build_levels.gd)
##   area: play area outline (optional, default DEFAULT_AREA), obstacles: Array of outlines
##   sol: solution positions, neuron id = index
##   start: explicit start positions, or perm + offset: start[i] = sol[perm[i]] + offset
##     (a hand-picked shuffle of the solution spots, shifted so no neuron starts on a spot)
##   fixed: ids of red fixed neurons (they start on their solution spot)
##   receptors: {id: [reach, required_links]} cyan receptor neurons (T7.3; start on their spot)
##   toxic: ids of movable yellow toxic neurons (T8.2): they must end outside every receptor's reach
##   lethal_edges: play-area edge indices that destroy on contact (edge i = point i -> i + 1)
##   lethal_obstacles: indices into obstacles that destroy on contact (T7.2)
##   edges: [a, b] normal dendrite, [a, b, rest_length, max_length] tension dendrite,
##          [a, b, rest_length, max_length, "diseased"] diseased dendrite (T8.3): intact within
##          max_length at start, stretched past it in the solution (that is how it breaks)
## Coordinates are playfield units; the level view fits them into 1920x1080.
##
## Campaign layout (T7.4): 1 First Signals, 2 Shaped Minds, 3 Anchored, 4 Tension, 5 Live Wires
## (lethal walls), 6 Synapses (receptors), 7 Convergence (everything). Mission ids follow campaign
## order (m01..m30); the old Convergence missions m19/m20/m21 became m26/m28/m30 (see
## GameState save migration v2).

const Organic := preload("res://tools/organic_shapes.gd")
const Layouts := preload("res://tools/layouts.gd")
const Starts := preload("res://tools/level_starts.gd")
const DEFAULT_AREA := [160, 120, 1760, 120, 1760, 1020, 160, 1020]

## 3-star move limits (par_moves), set by the designer after the first measured streak
## (streak 20261009-231045, rule ceil(best moves x 1.15)). They override any par_moves in a spec.
const MEASURED_PAR_MOVES := {
	"m01": 2, "m02": 2, "m03": 3, "m04": 3, "m05": 4, "m06": 3, "m07": 5, "m08": 3, "m10": 3,
	"m11": 5, "m31": 5, "m32": 3, "m33": 4,
}
## Measured best moves looked inflated (exploring), so the designer fixed the limit at 5.
const INFLATED_PAR_MOVES := ["m09", "m12"]
## Missions not measured yet: 6 moves up to 10 neurons, 7 moves above that. Replace as they get measured.
const UNTESTED_PAR_MOVES_SMALL := 6
const UNTESTED_PAR_MOVES_LARGE := 7


static func par_moves_for(mission_id: String, neuron_count: int) -> int:
	if MEASURED_PAR_MOVES.has(mission_id):
		return MEASURED_PAR_MOVES[mission_id]
	if INFLATED_PAR_MOVES.has(mission_id):
		return 5
	return UNTESTED_PAR_MOVES_SMALL if neuron_count <= 10 else UNTESTED_PAR_MOVES_LARGE


static func chapters() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in range(1, 10):
		result.append({"id": id, "title": "CHAPTER_%d_TITLE" % id, "subtitle": "CHAPTER_%d_SUBTITLE" % id})
	return result


## Every mission in campaign order: each chapter's missions, its boss last. Mission ids are stable
## (they never depend on the position): the 30 original ids keep their meaning, the new missions
## are m31..m48.
static func missions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_chapter_1())
	result.append(_boss_gatekeeper())
	result.append_array(_chapter_2())
	result.append(_boss_labyrinth())
	result.append_array(_chapter_3())
	result.append(_boss_bottleneck())
	result.append_array(_chapter_4())
	result.append(_boss_crescent())
	result.append_array(_chapter_pruning())
	result.append_array(_chapter_5())
	result.append_array(_chapter_live_wires_extra())
	result.append(_boss_arc_warden())
	result.append_array(_chapter_6())
	result.append(_boss_receptor_queen())
	result.append_array(_chapter_contagion())
	result.append_array(_chapter_7())
	result.append(_boss_core())
	for spec in result:
		_finish(spec)
	return result


## Spec post-processing: "cell" builds the organic arena around every neuron position of the
## mission, "lethal_where" picks the lethal edges of the finished arena.
static func _finish(spec: Dictionary) -> void:
	if not spec.has("start") and not spec.has("perm") and Starts.STARTS.has(spec["id"]):
		spec["start"] = pts(Starts.STARTS[spec["id"]])
	if spec.has("cell"):
		var c: Array = spec["cell"]
		spec["area"] = Organic.cell(_all_points(spec), c[0], c[1], 40.0, c[2], c[3], c[4], Rect2(170, 130, 1580, 880))
	if spec.has("lethal_where"):
		spec["lethal_edges"] = Organic.edges_where(spec["area"], spec["lethal_where"])


## Start positions of a spec (explicit, derived from perm + offset, or the solution).
static func start_of(spec: Dictionary) -> PackedVector2Array:
	var sol: PackedVector2Array = spec["sol"]
	if spec.has("start"):
		return spec["start"]
	if not spec.has("perm"):
		return sol
	var result := PackedVector2Array()
	for id in sol.size():
		var anchored: bool = spec.get("fixed", []).has(id) or spec.get("receptors", {}).has(id)
		if anchored:
			result.append(sol[id])
		else:
			result.append(sol[spec["perm"][id]] + spec["offset"] + spec.get("nudge", {}).get(id, Vector2.ZERO))
	return result


static func _all_points(spec: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append_array(spec["sol"])
	points.append_array(start_of(spec))
	return points


## Pairs a flat list of numbers into points: [x0, y0, x1, y1, ...].
static func pts(values: Array) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(0, values.size(), 2):
		points.append(Vector2(values[i], values[i + 1]))
	return points


# --- Chapter 1: First Signals (basics: cycles, then hubs) ---------------------

static func _chapter_1() -> Array[Dictionary]:
	return [
		{
			# A 4-cycle drawn as a bowtie: one crossing, one drag.
			"id": "m01", "name": "MISSION_M01_NAME", "chapter": 1, "par_moves": 6, "par_time": 60.0,
			"story": "MISSION_M01_STORY",
			"sol": pts([660, 370, 1260, 370, 1260, 770, 660, 770]),
			"start": pts([700, 330, 1250, 420, 620, 760, 1300, 720]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 0]],
		},
		{
			# First hub: neuron 0 holds four dendrites and starts swapped with neuron 4.
			"id": "m02", "name": "MISSION_M02_NAME", "chapter": 1, "par_moves": 8, "par_time": 90.0,
			"story": "",
			"sol": pts([960, 570, 660, 320, 1260, 320, 1260, 820, 960, 920, 660, 820]),
			"start": pts([960, 920, 660, 320, 1260, 320, 1260, 820, 960, 570, 660, 820]),
			"edges": [[0, 1], [0, 2], [0, 3], [0, 5], [1, 2], [2, 3], [3, 4], [4, 5], [5, 1]],
		},
		{
			# A 5-cycle drawn as a pentagram (five crossings) that opens into a pentagon.
			"id": "m03", "name": "MISSION_M03_NAME", "chapter": 1, "par_time": 60.0,
			"story": "",
			"sol": pts([960, 270, 1245, 477, 1136, 813, 784, 813, 675, 477]),
			"start": pts([1160, 295, 960, 910, 760, 295, 1283, 675, 637, 675]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
		},
		{
			# Triangular prism: a triangle nested in a triangle, joined by three spokes.
			# Start: the inner triangle is mirrored and its apex swapped with the outer apex.
			"id": "m04", "name": "MISSION_M04_NAME", "chapter": 1, "par_time": 90.0,
			"story": "MISSION_M04_STORY",
			"sol": pts([960, 200, 1400, 900, 520, 900, 960, 450, 1140, 760, 780, 760]),
			"start": pts([1010, 490, 1350, 860, 570, 860, 1010, 240, 830, 720, 1090, 720]),
			"edges": [[0, 1], [1, 2], [2, 0], [3, 4], [4, 5], [5, 3], [0, 3], [1, 4], [2, 5]],
		},
		{
			# Wheel: one hub, six rim neurons, every rim neuron wired to the hub.
			"id": "m05", "name": "MISSION_M05_NAME", "chapter": 1, "par_time": 120.0,
			"story": "",
			"sol": pts([960, 570, 1290, 570, 1125, 856, 795, 856, 630, 570, 795, 284, 1125, 284]),
			"perm": [3, 0, 5, 1, 6, 2, 4], "offset": Vector2(50, 50), "nudge": {1: Vector2(55, 30)},
			"edges": [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6],
				[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1]],
		},
	]


# --- Chapter 2: Shaped Minds (irregular areas and obstacles) ------------------

static func _chapter_2() -> Array[Dictionary]:
	return [
		{
			# L-shaped area: neurons must travel around the inner corner.
			"id": "m06", "name": "MISSION_M06_NAME", "chapter": 2, "par_time": 120.0,
			"story": "MISSION_M06_STORY",
			"area": Organic.wobble(Organic.rounded(
				pts([160, 120, 900, 120, 900, 640, 1760, 640, 1760, 1020, 160, 1020]), 52.0), 9.0, 5.0, 0.4),
			"sol": pts([330, 260, 720, 260, 330, 600, 720, 560, 450, 880, 1000, 860, 1300, 730, 1600, 900]),
			"perm": [6, 4, 7, 5, 1, 2, 0, 3], "offset": Vector2(50, 50), "nudge": {0: Vector2(-18, 24)},
			"edges": [[0, 1], [0, 2], [1, 3], [2, 3], [0, 3], [2, 4], [3, 4], [3, 5], [4, 5],
				[5, 6], [5, 7], [6, 7]],
		},
		{
			# A ring around a solid hollow: square antiprism, inner square around the hole.
			"id": "m07", "name": "MISSION_M07_NAME", "chapter": 2, "par_time": 150.0,
			"story": "",
			"cell": [175.0, 120.0, 10.0, 6.0, 1.1],
			"obstacles": [Organic.polar(Vector2(960, 570), 200.0, 118.0, [[3, 0.07, 0.5]], 60)],
			"sol": pts([960, 300, 1420, 570, 960, 840, 500, 570, 400, 230, 1520, 230, 1520, 910, 400, 910]),
			"perm": [2, 7, 0, 5, 1, 3, 6, 4], "offset": Vector2(50, 50),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
				[0, 4], [0, 5], [1, 5], [1, 6], [2, 6], [2, 7], [3, 7], [3, 4]],
		},
		{
			# Two chambers and a corridor one neuron wide; neuron 4 starts inside it.
			"id": "m08", "name": "MISSION_M08_NAME", "chapter": 2, "par_time": 150.0,
			"story": "MISSION_M08_STORY",
			"area": Organic.wobble(Organic.rounded(pts([160, 120, 760, 120, 760, 500, 1160, 500, 1160, 120,
				1760, 120, 1760, 1020, 1160, 1020, 1160, 640, 760, 640, 760, 1020, 160, 1020]), 46.0), 8.0, 6.0, 1.0),
			"sol": pts([320, 280, 620, 560, 320, 860, 600, 250, 1300, 570, 1600, 280, 1600, 860, 1320, 880]),
			"start": pts([1650, 600, 1450, 300, 1250, 300, 1450, 850, 960, 570, 400, 350, 550, 900, 400, 600]),
			"edges": [[0, 3], [3, 1], [1, 2], [2, 0], [0, 1], [1, 4], [4, 5], [5, 6], [6, 4],
				[6, 7], [7, 4]],
		},
		{
			# A triangulated 3x3 lattice whose empty cells hold solid islands.
			"id": "m09", "name": "MISSION_M09_NAME", "chapter": 2, "par_time": 150.0,
			"story": "",
			"cell": [185.0, 105.0, 12.0, 5.0, 2.0],
			"obstacles": [
				Organic.polar(Vector2(680, 410), 96.0, 90.0, [[3, 0.08, 0.2]], 48),
				Organic.polar(Vector2(1240, 730), 96.0, 90.0, [[3, 0.08, 1.4]], 48),
			],
			"sol": pts([400, 250, 960, 250, 1520, 250, 400, 570, 960, 570, 1520, 570, 400, 890, 960, 890, 1520, 890]),
			"perm": [5, 7, 3, 8, 0, 6, 1, 2, 4], "offset": Vector2(50, 50),
			"nudge": {0: Vector2(60, 0), 2: Vector2(70, 0), 6: Vector2(0, 60), 8: Vector2(30, -50)},
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [6, 7], [7, 8], [0, 3], [3, 6], [1, 4],
				[4, 7], [2, 5], [5, 8], [1, 5], [3, 7]],
		},
		{
			# U-shaped area: the two arms only meet through the bottom fold.
			"id": "m10", "name": "MISSION_M10_NAME", "chapter": 2, "par_time": 150.0,
			"story": "",
			"area": Organic.wobble(Organic.rounded(
				pts([160, 120, 620, 120, 620, 700, 1300, 700, 1300, 120, 1760, 120, 1760, 1020, 160, 1020]), 50.0), 9.0, 6.0, 2.2),
			"sol": pts([390, 250, 390, 600, 390, 900, 800, 880, 1120, 880, 1530, 900, 1530, 600, 1530, 250, 960, 800]),
			"perm": [7, 5, 6, 8, 0, 1, 3, 2, 4], "offset": Vector2(50, 50), "nudge": {2: Vector2(70, 0)},
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 7], [1, 3], [4, 6],
				[3, 8], [4, 8]],
		},
	]


# --- Chapter 3: Anchored (red fixed neurons) ---------------------------------

static func _chapter_3() -> Array[Dictionary]:
	return [
		{
			# A fixed hub: the hexagon must close around it.
			"id": "m11", "name": "MISSION_M11_NAME", "chapter": 3, "par_time": 120.0,
			"story": "MISSION_M11_STORY",
			"cell": [150.0, 95.0, 10.0, 7.0, 0.3],
			"sol": pts([960, 570, 1280, 570, 1120, 847, 800, 847, 640, 570, 800, 293, 1120, 293, 960, 960]),
			"fixed": [0],
			"perm": [0, 4, 6, 7, 2, 1, 3, 5], "offset": Vector2(50, -50), "nudge": {3: Vector2(-90, -10)},
			"edges": [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1], [0, 1], [0, 3], [0, 5],
				[7, 2], [7, 3]],
		},
		{
			# Triangulated lattice pinned at two opposite corners.
			"id": "m12", "name": "MISSION_M12_NAME", "chapter": 3, "par_time": 150.0,
			"story": "",
			"cell": [165.0, 110.0, 9.0, 5.0, 1.9],
			"sol": pts([500, 250, 960, 250, 1420, 250, 500, 570, 960, 570, 1420, 570, 500, 890, 960, 890, 1420, 890]),
			"fixed": [2, 6],
			# T7.4 rebalance: start calmed from 24 to 12 crossings.
			"start": pts([462, 312, 1034, 296, 1420, 250, 1356, 600, 1005, 617, 450, 592, 500, 890, 1029, 818, 1441, 860]),
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [6, 7], [7, 8], [0, 3], [3, 6], [1, 4],
				[4, 7], [2, 5], [5, 8], [0, 4], [1, 5], [3, 7], [4, 8]],
		},
		{
			# Pentagonal prism with three anchors, inner and outer.
			"id": "m13", "name": "MISSION_M13_NAME", "chapter": 3, "par_time": 180.0,
			"story": "MISSION_M13_STORY",
			"cell": [150.0, 100.0, 11.0, 6.0, 0.9],
			"sol": pts([960, 190, 1321, 453, 1183, 877, 737, 877, 599, 453,
				960, 400, 1122, 517, 1060, 708, 860, 708, 798, 517]),
			"fixed": [0, 4, 7],
			"perm": [0, 9, 5, 6, 4, 3, 8, 7, 1, 2], "offset": Vector2(40, 40), "nudge": {1: Vector2(92, 0)},
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0], [5, 6], [6, 7], [7, 8], [8, 9], [9, 5],
				[0, 5], [1, 6], [2, 7], [3, 8], [4, 9]],
		},
		{
			# Four anchored corners pull on a hexagonal wheel; side walls narrow the field.
			"id": "m14", "name": "MISSION_M14_NAME", "chapter": 3, "par_time": 180.0,
			"story": "",
			"cell": [165.0, 100.0, 12.0, 8.0, 2.6],
			"obstacles": [
				Organic.polar(Vector2(440, 570), 62.0, 62.0, [[2, 0.1, 0.4]], 40),
				Organic.polar(Vector2(1480, 570), 62.0, 62.0, [[2, 0.1, 1.9]], 40),
			],
			"sol": pts([960, 570, 1260, 570, 1110, 830, 810, 830, 660, 570, 810, 310, 1110, 310,
				360, 230, 1560, 230, 1560, 910, 360, 910]),
			"fixed": [7, 8, 9, 10],
			# T7.4 rebalance: start calmed from 46 to 23 crossings.
			"start": pts([748, 780, 1211, 553, 736, 255, 965, 546, 1076, 792, 597, 524, 1037, 292,
				360, 230, 1560, 230, 1560, 910, 360, 910]),
			"edges": [[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6],
				[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1],
				[7, 4], [7, 5], [8, 6], [8, 1], [9, 1], [9, 2], [10, 3], [10, 4]],
		},
	]


# --- Chapter 4: Tension (light-green dendrites with a max length) -------------

static func _chapter_4() -> Array[Dictionary]:
	return [
		{
			# Wheel with two short tension spokes: rim neurons 1 and 4 start on the wrong
			# side of the hub, near breaking, and must swing around it instead of across.
			"id": "m15", "name": "MISSION_M15_NAME", "chapter": 4, "par_time": 150.0,
			"story": "MISSION_M15_STORY",
			"cell": [160.0, 100.0, 11.0, 6.0, 0.7],
			"sol": pts([960, 570, 1220, 570, 1090, 795, 830, 795, 700, 570, 830, 345, 1090, 345, 360, 570, 1560, 570]),
			"start": pts([960, 570, 680, 640, 1130, 230, 1150, 880, 1240, 500, 780, 850, 720, 360, 1600, 420, 360, 300]),
			"edges": [[0, 1, 200.0, 330.0], [0, 2], [0, 3], [0, 4, 200.0, 330.0], [0, 5], [0, 6],
				[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1],
				[7, 4], [7, 5], [7, 3], [8, 1], [8, 2], [8, 6]],
		},
		{
			# Ladder whose three tension rungs start flipped upside down.
			"id": "m16", "name": "MISSION_M16_NAME", "chapter": 4, "par_time": 180.0,
			"story": "",
			"cell": [150.0, 90.0, 10.0, 9.0, 2.1],
			"sol": pts([400, 380, 680, 380, 960, 380, 1240, 380, 1520, 380,
				400, 760, 680, 760, 960, 760, 1240, 760, 1520, 760]),
			"start": pts([450, 700, 1170, 830, 970, 640, 740, 820, 1460, 700,
				460, 440, 1170, 440, 890, 390, 740, 540, 1560, 440]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [5, 6], [6, 7], [7, 8], [8, 9],
				[0, 5, 300.0, 440.0], [1, 6], [2, 7, 300.0, 440.0], [3, 8], [4, 9, 300.0, 440.0],
				[0, 6], [1, 7], [2, 8], [3, 9]],
		},
		{
			# Triangular lattice: four tension pairs start swapped as units.
			"id": "m17", "name": "MISSION_M17_NAME", "chapter": 4, "par_time": 210.0,
			"story": "MISSION_M17_STORY",
			"cell": [165.0, 105.0, 12.0, 5.0, 1.2],
			"sol": pts([640, 250, 960, 250, 1280, 250, 480, 570, 800, 570, 1120, 570, 1440, 570,
				640, 890, 960, 890, 1280, 890, 1600, 890]),
			"start": pts([1010, 300, 620, 340, 1230, 830, 580, 830, 1170, 630, 800, 690, 1560, 840,
				540, 620, 960, 820, 1320, 300, 1390, 640]),
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [5, 6], [7, 8], [8, 9], [9, 10],
				[0, 3], [0, 4, 260.0, 420.0], [1, 4], [1, 5, 260.0, 420.0], [2, 5], [2, 6],
				[3, 7, 260.0, 420.0], [4, 7], [4, 8], [5, 8], [5, 9], [6, 9], [6, 10, 260.0, 420.0]],
		},
		{
			# Two wheels joined by a tension bridge; both rims start as pentagrams.
			"id": "m18", "name": "MISSION_M18_NAME", "chapter": 4, "par_time": 240.0,
			"story": "",
			"cell": [150.0, 85.0, 13.0, 7.0, 0.2],
			"sol": pts([600, 570, 830, 570, 671, 789, 414, 705, 414, 435, 671, 351,
				1320, 570, 1090, 570, 1249, 351, 1506, 435, 1506, 705, 1249, 789]),
			"start": pts([600, 570, 786, 705, 529, 321, 529, 789, 786, 432, 360, 587,
				1320, 570, 1134, 705, 1391, 321, 1391, 789, 1134, 432, 1560, 587]),
			"edges": [[0, 1, 160.0, 280.0], [0, 2], [0, 3, 160.0, 280.0], [0, 4], [0, 5],
				[1, 2], [2, 3], [3, 4], [4, 5], [5, 1],
				[6, 7, 160.0, 280.0], [6, 8], [6, 9], [6, 10, 160.0, 280.0], [6, 11],
				[7, 8], [8, 9], [9, 10], [10, 11], [11, 7],
				[1, 7, 220.0, 380.0], [5, 8], [2, 11]],
		},
	]



# --- Chapter 5: Live Wires (lethal walls) --------------------------------------

static func _chapter_5() -> Array[Dictionary]:
	return [
		{
			# A cube between two live side walls: plenty of room, one wrong swing is fatal.
			"id": "m19", "name": "MISSION_M19_NAME", "chapter": 6, "par_time": 120.0,
			"story": "MISSION_M19_STORY",
			"cell": [190.0, 130.0, 9.0, 6.0, 2.2],
			"lethal_where": func(mid: Vector2, n: Vector2) -> bool: return absf(n.x) > 0.55 and absf(mid.x - 960.0) > 450.0,
			"sol": pts([520, 250, 1400, 250, 1400, 890, 520, 890, 760, 430, 1160, 430, 1160, 710, 760, 710]),
			"start": pts([568, 312, 489, 829, 1348, 927, 1395, 268, 819, 417, 1098, 691, 1124, 378, 704, 732]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
				[0, 4], [1, 5], [2, 6], [3, 7]],
		},
		{
			# Lattice with two live islands in its empty cells and a live floor.
			"id": "m20", "name": "MISSION_M20_NAME", "chapter": 6, "par_time": 150.0,
			"story": "",
			"cell": [185.0, 115.0, 10.0, 5.0, 2.4],
			"lethal_where": func(mid: Vector2, n: Vector2) -> bool: return n.y > 0.55 and mid.y > 880.0,
			"obstacles": [
				Organic.polar(Vector2(680, 410), 96.0, 90.0, [[3, 0.08, 0.7]], 48),
				Organic.polar(Vector2(1240, 730), 96.0, 90.0, [[3, 0.08, 2.1]], 48),
			],
			"lethal_obstacles": [0, 1],
			"sol": pts([400, 250, 960, 250, 1520, 250, 400, 570, 960, 570, 1520, 570, 400, 870, 960, 870, 1520, 870]),
			"start": pts([1468, 280, 1025, 305, 391, 202, 368, 532, 980, 587, 1573, 629, 453, 802, 1572, 891, 899, 933]),
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [6, 7], [7, 8], [0, 3], [3, 6], [1, 4],
				[4, 7], [2, 5], [5, 8], [1, 5], [3, 7]],
		},
		{
			# U-shaped field whose inner fold is a live wire: everything bends around the core.
			"id": "m21", "name": "MISSION_M21_NAME", "chapter": 6, "par_time": 180.0,
			"story": "MISSION_M21_STORY",
			"area": Organic.wobble(Organic.rounded(
				pts([160, 120, 620, 120, 620, 640, 1300, 640, 1300, 120, 1760, 120, 1760, 1020, 160, 1020]), 50.0), 8.0, 6.0, 0.6),
			"lethal_where": func(mid: Vector2, _n: Vector2) -> bool: return mid.x > 590.0 and mid.x < 1330.0 and mid.y > 165.0 and mid.y < 700.0,
			"sol": pts([390, 250, 390, 560, 390, 880, 760, 880, 1160, 880, 1530, 880, 1530, 560, 1530, 250,
				960, 790, 560, 800]),
			"start": pts([598, 858, 370, 531, 400, 916, 777, 916, 1142, 926, 1496, 895, 404, 201, 1587, 563,
				965, 822, 1545, 230]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 8], [8, 4], [4, 5], [5, 6], [6, 7], [1, 3], [4, 6],
				[1, 9], [2, 9], [3, 9]],
		},
	]


# --- Chapter 6: Synapses (receptor neurons and dynamic links) -----------------

static func _chapter_6() -> Array[Dictionary]:
	return [
		{
			# One receptor inside a ring: bring a single neuron into its halo.
			"id": "m22", "name": "MISSION_M22_NAME", "chapter": 7, "par_time": 90.0,
			"story": "MISSION_M22_STORY",
			"cell": [160.0, 100.0, 10.0, 6.0, 0.5],
			"receptors": {6: [150.0, 1]},
			"sol": pts([960, 400, 1260, 420, 1300, 720, 960, 860, 620, 720, 660, 420, 960, 570]),
			"start": pts([1210, 471, 1000, 332, 1330, 759, 581, 781, 1011, 824, 652, 448, 960, 570]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0], [1, 3], [3, 5]],
		},
		{
			# Two receptors guard the flanks; each needs one partner.
			"id": "m23", "name": "MISSION_M23_NAME", "chapter": 7, "par_time": 120.0,
			"story": "",
			"cell": [155.0, 95.0, 11.0, 7.0, 1.7],
			"receptors": {8: [160.0, 1], 9: [160.0, 1]},
			"sol": pts([560, 300, 480, 570, 560, 840, 1360, 300, 1440, 570, 1360, 840, 960, 420, 960, 720,
				300, 570, 1620, 570]),
			"start": pts([941, 374, 1403, 363, 599, 903, 518, 503, 1413, 608, 1344, 806, 597, 284, 1009, 774,
				300, 570, 1620, 570]),
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [0, 6], [6, 3], [2, 7], [7, 5], [6, 7],
				[1, 6], [1, 7], [4, 6], [4, 7]],
		},
		{
			# A double receptor at the heart of two diamonds: it wants one neuron from each.
			"id": "m24", "name": "MISSION_M24_NAME", "chapter": 7, "par_time": 150.0,
			"story": "MISSION_M24_STORY",
			"cell": [150.0, 90.0, 12.0, 5.0, 2.8],
			"receptors": {10: [140.0, 2]},
			"sol": pts([800, 570, 1120, 570, 600, 300, 600, 840, 1320, 300, 1320, 840, 960, 250, 960, 890,
				400, 570, 1520, 570, 960, 570]),
			"start": pts([766, 542, 1075, 622, 903, 279, 657, 840, 1293, 356, 1473, 584, 347, 511, 984, 927,
				648, 252, 1306, 812, 960, 570]),
			"edges": [[8, 2], [8, 3], [2, 0], [3, 0], [8, 0], [9, 4], [9, 5], [4, 1], [5, 1], [9, 1],
				[2, 6], [6, 4], [3, 7], [7, 5], [6, 0], [7, 1]],
		},
		{
			# Receptors above and below a ladder with fragile rungs.
			"id": "m25", "name": "MISSION_M25_NAME", "chapter": 7, "par_time": 180.0,
			"story": "",
			"cell": [150.0, 95.0, 10.0, 8.0, 0.4],
			"receptors": {9: [175.0, 2], 10: [140.0, 1]},
			"sol": pts([500, 330, 780, 330, 1060, 330, 1340, 330, 500, 810, 780, 810, 1060, 810, 1340, 810,
				1600, 570, 920, 190, 980, 950]),
			"start": pts([535, 358, 1274, 379, 1052, 278, 741, 297, 532, 745, 753, 771, 1042, 764, 1377, 837,
				1577, 515, 920, 190, 980, 950]),
			"edges": [[0, 1], [1, 2], [2, 3], [4, 5], [5, 6], [6, 7],
				[0, 4, 300.0, 520.0], [1, 5], [2, 6, 300.0, 520.0], [3, 7],
				[3, 8], [7, 8], [0, 5], [1, 6], [2, 7]],
		},
	]


# --- Chapter 7: Convergence (everything combined) -----------------------------

static func _chapter_7() -> Array[Dictionary]:
	return [
		{
			# 4x3 lattice with a live island, a solid island and two anchors (was m19).
			"id": "m26", "name": "MISSION_M26_NAME", "chapter": 9, "par_time": 210.0,
			"story": "MISSION_M26_STORY",
			"cell": [165.0, 110.0, 12.0, 6.0, 1.3],
			"obstacles": [
				Organic.polar(Vector2(960, 410), 92.0, 66.0, [[3, 0.06, 0.4]], 44),
				Organic.polar(Vector2(1333, 730), 94.0, 68.0, [[3, 0.06, 1.7]], 44),
			],
			"lethal_obstacles": [0],
			"sol": pts([400, 250, 773, 250, 1146, 250, 1520, 250, 400, 570, 773, 570, 1146, 570, 1520, 570,
				400, 890, 773, 890, 1146, 890, 1520, 890]),
			"fixed": [6, 8],
			"start": pts([1200, 860, 450, 620, 850, 830, 880, 700, 1570, 940, 450, 340, 1146, 570, 680, 620,
				400, 890, 1600, 250, 1660, 640, 1196, 370]),
			"edges": [[0, 1], [1, 2], [2, 3], [4, 5], [5, 6], [6, 7], [8, 9], [9, 10], [10, 11],
				[0, 4], [4, 8], [1, 5], [5, 9], [2, 6], [6, 10], [3, 7], [7, 11],
				[0, 5], [2, 7], [4, 9], [5, 10]],
		},
		{
			# A double receptor in a hexagon between live walls; two spokes are fragile.
			"id": "m27", "name": "MISSION_M27_NAME", "chapter": 9, "par_time": 210.0,
			"story": "",
			"cell": [175.0, 115.0, 11.0, 7.0, 2.0],
			"lethal_where": func(mid: Vector2, n: Vector2) -> bool: return absf(n.x) > 0.55 and absf(mid.x - 960.0) > 400.0,
			"receptors": {12: [130.0, 2]},
			"sol": pts([960, 450, 1180, 500, 1180, 700, 960, 750, 740, 700, 740, 500,
				960, 200, 1460, 300, 1460, 840, 960, 940, 460, 840, 460, 300, 960, 600]),
			"start": pts([1492, 239, 1514, 838, 945, 360, 1232, 691, 812, 677, 698, 548, 1238, 256, 1033, 816,
				1228, 519, 1057, 876, 439, 831, 544, 249, 960, 600]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0],
				[6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 6],
				[0, 6, 180.0, 300.0], [1, 7], [2, 8], [3, 9, 180.0, 300.0], [4, 10], [5, 11]],
		},
		{
			# Hexagonal field with live slanted walls, a fixed hub and three folded tension pairs
			# (was m20; start calmed).
			"id": "m28", "name": "MISSION_M28_NAME", "chapter": 9, "par_time": 240.0,
			"story": "MISSION_M28_STORY",
			"area": Organic.wobble(Organic.rounded(
				pts([360, 120, 1560, 120, 1760, 570, 1560, 1020, 360, 1020, 160, 570]), 70.0), 9.0, 7.0, 1.4),
			"lethal_where": func(_mid: Vector2, n: Vector2) -> bool: return absf(n.x) > 0.6,
			"sol": pts([960, 570, 1190, 570, 1075, 769, 845, 769, 730, 570, 845, 371, 1075, 371,
				1306, 770, 960, 970, 614, 770, 614, 370, 960, 170, 1306, 370]),
			"fixed": [0, 8],
			"start": pts([960, 570, 1207, 609, 1300, 250, 680, 700, 1063, 656, 890, 190, 468, 334,
				1330, 540, 960, 970, 912, 741, 800, 900, 820, 344, 705, 620]),
			"edges": [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1],
				[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6],
				[7, 1, 200.0, 320.0], [7, 2], [8, 2], [8, 3], [9, 3, 200.0, 320.0], [9, 4],
				[10, 4], [10, 5], [11, 5, 200.0, 320.0], [11, 6], [12, 6], [12, 1],
				[7, 8], [9, 10], [11, 12]],
		},
		{
			# Anchored lattice around a live core; a double receptor waits below.
			"id": "m29", "name": "MISSION_M29_NAME", "chapter": 9, "par_time": 240.0,
			"story": "",
			"cell": [160.0, 100.0, 11.0, 5.0, 0.8],
			"obstacles": [Organic.polar(Vector2(960, 480), 66.0, 62.0, [[3, 0.08, 0.9]], 40)],
			"lethal_obstacles": [0],
			"receptors": {12: [140.0, 2]},
			"sol": pts([500, 260, 960, 230, 1420, 260, 500, 560, 1420, 560, 500, 860, 1420, 860,
				760, 400, 1160, 400, 840, 720, 1080, 720, 960, 960, 960, 820]),
			"fixed": [0, 2],
			"start": pts([500, 260, 534, 892, 1420, 260, 928, 176, 453, 541, 1018, 949, 1352, 497, 708, 358,
				1174, 383, 806, 752, 1093, 650, 1425, 810, 960, 820]),
			"edges": [[0, 1], [1, 2], [0, 3], [3, 5], [2, 4], [4, 6],
				[0, 7], [1, 7], [1, 8], [2, 8], [3, 7], [4, 8], [7, 8],
				[3, 9], [5, 9], [4, 10], [6, 10], [9, 10], [5, 11], [6, 11]],
		},
		{
			# Two hemispheres around a live core, bridged by tension, anchored top and bottom; a
			# receptor in each hemisphere (was m21).
			"id": "m30", "name": "MISSION_M30_NAME", "chapter": 9, "par_time": 270.0,
			"story": "MISSION_M30_STORY",
			"area": Organic.wobble(Organic.rounded(
				pts([260, 120, 1660, 120, 1760, 220, 1760, 920, 1660, 1020, 260, 1020, 160, 920, 160, 220]), 90.0), 10.0, 7.0, 2.9),
			"obstacles": [Organic.polar(Vector2(960, 570), 66.0, 82.0, [[2, 0.07, 0.3]], 44)],
			"lethal_obstacles": [0],
			"receptors": {14: [180.0, 1], 15: [140.0, 1]},
			"sol": pts([580, 310, 805, 440, 805, 700, 580, 830, 355, 700, 355, 440,
				1340, 310, 1115, 440, 1115, 700, 1340, 830, 1565, 700, 1565, 440, 960, 250, 960, 890,
				330, 900, 1450, 200]),
			"fixed": [10, 12, 13],
			"start": pts([1493, 410, 880, 380, 720, 745, 1260, 444, 1600, 520, 1260, 840,
				280, 560, 600, 500, 480, 690, 700, 640, 1565, 700, 560, 860, 960, 250, 960, 890,
				330, 900, 1450, 200]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0],
				[6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 6],
				[1, 7, 250.0, 380.0], [2, 8, 250.0, 380.0],
				[12, 0], [12, 1], [12, 6], [12, 7],
				[13, 2], [13, 3], [13, 8], [13, 9, 300.0, 440.0],
				[5, 1], [4, 2], [11, 7], [10, 8]],
		},
	]


# =============================================================================
# T8.4 / T8.5 / T8.6: new missions m31..m48. Layouts come from tools/layouts.gd (seeded, planar by
# start layout that tools/find_start.gd searches (pasted so the data stays reviewable).
# Pars: about twice the planned moves, generous times (the human retunes them from the
# measurement mode).
# =============================================================================

# --- Bosses of the first chapters --------------------------------------------

## Boss 1 (First Signals): plain cycles at scale in a tri-lobed cell.
static func _boss_gatekeeper() -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), 600.0, 380.0, [[3, 0.16, 0.5]], 120)
	var sol := Layouts.scatter(area, [], 10, 190.0, 60.0, 3101)
	return {
		"id": "m31", "name": "MISSION_M31_NAME", "chapter": 1, "boss": true, "par_time": 240.0,
		"story": "MISSION_M31_STORY",
		"area": area,
		"sol": sol,
		"edges": Layouts.planar_edges(sol, 430.0, 60.0, 0.25, 3101),
	}


## Boss 2 (Shaped Minds): a ring around a lobed island, two pillars split it into corridors.
static func _boss_labyrinth() -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), 760.0, 440.0, [[2, 0.05, 0.3]], 140)
	var obstacles := [
		Organic.polar(Vector2(960, 570), 330.0, 150.0, [[3, 0.08, 1.0]], 64),
		Organic.polar(Vector2(430, 570), 62.0, 70.0, [[2, 0.1, 0.4]], 36),
		Organic.polar(Vector2(1490, 570), 62.0, 70.0, [[2, 0.1, 1.9]], 36),
	]
	var sol := Layouts.scatter(area, obstacles, 12, 190.0, 60.0, 3201)
	return {
		"id": "m32", "name": "MISSION_M32_NAME", "chapter": 2, "boss": true, "par_time": 270.0,
		"story": "MISSION_M32_STORY",
		"area": area,
		"obstacles": obstacles,
		"sol": sol,
		"edges": Layouts.planar_edges(sol, 400.0, 60.0, 0.25, 3201),
	}


## Boss 3 (Anchored): an hourglass; three red anchors pin the tips and the neck.
static func _boss_bottleneck() -> Dictionary:
	var area := Organic.hourglass(Vector2(960, 570), 700.0, 135.0, 340.0)
	var sol := Layouts.scatter(area, [], 13, 165.0, 60.0, 3301)
	var fixed := [Layouts.nearest_index(sol, Vector2(330, 570)), Layouts.nearest_index(sol, Vector2(1590, 570)),
		Layouts.nearest_index(sol, Vector2(960, 570))]
	return {
		"id": "m33", "name": "MISSION_M33_NAME", "chapter": 3, "boss": true, "par_time": 300.0,
		"story": "MISSION_M33_STORY",
		"area": area,
		"sol": sol,
		"fixed": fixed,
		"edges": Layouts.planar_edges(sol, 400.0, 60.0, 0.2, 3301),
	}


## Boss 4 (Tension): a crescent; five taut bonds follow its curve.
static func _boss_crescent() -> Dictionary:
	var area := Organic.crescent(Vector2(960, 570), 720.0, 430.0, Vector2(1560, 570), 470.0, 260.0)
	var sol := Layouts.scatter(area, [], 13, 160.0, 60.0, 3401)
	var edges := Layouts.planar_edges(sol, 400.0, 60.0, 0.2, 3401)
	return {
		"id": "m34", "name": "MISSION_M34_NAME", "chapter": 4, "boss": true, "par_time": 300.0,
		"story": "MISSION_M34_STORY",
		"area": area,
		"sol": sol,
		"edges": Layouts.with_tension(sol, edges, 5, 200.0, 2),
	}


# --- Chapter 5: Pruning (diseased dendrites) -----------------------------------

static func _chapter_pruning() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append(_pruning_spec("m35", 7, 3501, 1, 0, 0, 520.0, 330.0, [[2, 0.14, 0.4]], 90.0, "MISSION_M35_STORY"))
	result.append(_pruning_spec("m36", 8, 3601, 2, 0, 0, 640.0, 330.0, [[2, -0.2, 0.0]], 120.0, ""))
	result.append(_pruning_spec("m37", 9, 3701, 3, 1, 0, 560.0, 360.0, [[3, 0.14, 1.0]], 150.0, "MISSION_M37_STORY"))
	result.append(_pruning_spec("m38", 10, 3801, 2, 0, 3, 640.0, 380.0, [[4, 0.1, 0.2], [2, 0.08, 0.0]], 180.0, ""))
	result.append(_boss_bramble())
	return result


## A Pruning mission: neuron count, seed, diseased chords, anchors and tension bonds.
static func _pruning_spec(id: String, count: int, seed_value: int, chords: int, anchors: int,
		tension_count: int, rx: float, ry: float, harmonics: Array, par_time: float, story: String) -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), rx, ry, harmonics, 110)
	var sol := Layouts.scatter(area, [], count, 200.0, 60.0, seed_value)
	var edges := Layouts.planar_edges(sol, 480.0, 58.0, 0.15, seed_value)
	var fixed := []
	if anchors > 0:
		fixed.append(Layouts.nearest_index(sol, Vector2(960 - rx * 0.8, 570)))
	edges = Layouts.with_tension(sol, edges, tension_count, 200.0, 1)
	var diseased := Layouts.chords(sol, edges, chords, 280.0, 480.0, 58.0, seed_value + 7, fixed)
	for pair: Array in diseased:
		edges.append(Layouts.diseased(sol, pair))
	var spec := {
		"id": id, "name": "MISSION_%s_NAME" % id.to_upper(), "chapter": 5, "par_time": par_time,
		"story": story,
		"area": area,
		"sol": sol,
		"edges": edges,
	}
	if not fixed.is_empty():
		spec["fixed"] = fixed
	return spec


## Boss 5 (Pruning): an amoeba; four diseased chords, three taut bonds and two anchors.
static func _boss_bramble() -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), 600.0, 400.0, [[2, 0.16, 0.3], [5, 0.08, 1.2], [3, 0.07, 2.0]], 160)
	var sol := Layouts.scatter(area, [], 13, 170.0, 60.0, 3901)
	var fixed := [Layouts.nearest_index(sol, Vector2(300, 570)), Layouts.nearest_index(sol, Vector2(1620, 570))]
	var edges := Layouts.with_tension(sol, Layouts.planar_edges(sol, 400.0, 60.0, 0.2, 3901), 3, 200.0, 2)
	for pair: Array in Layouts.chords(sol, edges, 4, 280.0, 480.0, 58.0, 3908, fixed):
		edges.append(Layouts.diseased(sol, pair))
	return {
		"id": "m39", "name": "MISSION_M39_NAME", "chapter": 5, "boss": true, "par_time": 300.0,
		"story": "MISSION_M39_STORY",
		"area": area,
		"sol": sol,
		"fixed": fixed,
		"edges": edges,
	}


# --- Chapter 6: Live Wires (one more regular mission and the boss) ---------------

static func _chapter_live_wires_extra() -> Array[Dictionary]:
	var area := Organic.polar(Vector2(960, 570), 640.0, 380.0, [[4, 0.08, 0.0]], 120)
	var lethal := Organic.edges_where(area, func(mid: Vector2, n: Vector2) -> bool:
		return absf(n.x) > 0.5 and absf(mid.x - 960.0) > 380.0)
	var sol := Layouts.scatter(area, [], 11, 200.0, 60.0, 4001, Organic.edge_segments(area, lethal), 60.0)
	var fixed := [Layouts.nearest_index(sol, Vector2(960, 570))]
	return [{
		"id": "m40", "name": "MISSION_M40_NAME", "chapter": 6, "par_time": 210.0,
		"story": "",
		"area": area,
		"lethal_edges": lethal,
		"sol": sol,
		"fixed": fixed,
		"edges": Layouts.planar_edges(sol, 420.0, 60.0, 0.2, 4001),
	}]


## Boss 6 (Live Wires): two bubbles joined by a live waist, live caps at both ends.
static func _boss_arc_warden() -> Dictionary:
	var left := Organic.polar(Vector2(690, 570), 430.0, 390.0, [[3, 0.05, 0.4]], 100)
	var right := Organic.polar(Vector2(1230, 570), 430.0, 390.0, [[3, 0.05, 1.8]], 100)
	var area := Organic.union(left, right)
	var lethal := Organic.edges_where(area, func(mid: Vector2, n: Vector2) -> bool:
		return (absf(n.y) > 0.45 and absf(mid.x - 960.0) < 150.0) or (absf(n.x) > 0.7 and absf(mid.x - 960.0) > 560.0))
	var sol := Layouts.scatter(area, [], 14, 190.0, 60.0, 4101, Organic.edge_segments(area, lethal), 60.0)
	var edges := Layouts.with_tension(sol, Layouts.planar_edges(sol, 410.0, 60.0, 0.2, 4101), 2, 200.0, 3)
	return {
		"id": "m41", "name": "MISSION_M41_NAME", "chapter": 6, "boss": true, "par_time": 300.0,
		"story": "MISSION_M41_STORY",
		"area": area,
		"lethal_edges": lethal,
		"sol": sol,
		"fixed": [Layouts.nearest_index(sol, Vector2(960, 570))],
		"edges": edges,
	}


# --- Chapter 7: Synapses boss ---------------------------------------------------------

## Boss 7 (Synapses): a quatrefoil with three receptors (one needs two partners) and taut bonds.
static func _boss_receptor_queen() -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), 650.0, 380.0, [[4, 0.16, 0.4]], 140)
	var sol := Layouts.scatter(area, [], 14, 170.0, 60.0, 4201)
	var required := [2, 1, 1]
	var sites := Layouts.dense_sites(sol, required, 380.0)
	var defs: Array = []
	for k in sites.size():
		defs.append([sites[k], required[k], 0])
	var receptors: Dictionary = Layouts.receptor_plans(sol, defs)["receptors"]
	var edges := Layouts.planar_edges(sol, 480.0, 58.0, 0.0, 4201)
	edges = edges.filter(func(e: Array) -> bool: return not receptors.has(e[0]) and not receptors.has(e[1]))
	return {
		"id": "m42", "name": "MISSION_M42_NAME", "chapter": 7, "boss": true, "par_time": 300.0,
		"story": "MISSION_M42_STORY",
		"area": area,
		"sol": sol,
		"receptors": receptors,
		"edges": Layouts.with_tension(sol, edges, 2, 200.0, 1),
	}


# --- Chapter 8: Contagion (toxic neurons) ------------------------------------------------

static func _chapter_contagion() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append(_contagion_spec("m43", 7, 4301, [[1, 1]], 0, 520.0, 330.0,
		[[2, 0.1, 1.2], [3, 0.05, 0.0]], 120.0, "MISSION_M43_STORY"))
	result.append(_contagion_spec("m44", 9, 4401, [[1, 1], [1, 1]], 0, 600.0, 360.0,
		[[3, 0.12, 2.0]], 150.0, ""))
	result.append(_contagion_spec("m45", 10, 4501, [[2, 2]], 2, 640.0, 380.0,
		[[5, 0.09, 0.7], [2, 0.1, 0.0]], 180.0, "MISSION_M45_STORY"))
	result.append(_contagion_spec("m46", 11, 4601, [[1, 1], [2, 1]], 2, 660.0, 400.0,
		[[3, 0.1, 0.4], [2, 0.08, 1.1]], 210.0, ""))
	result.append(_boss_patient_zero())
	return result


## A Contagion mission: a blob arena, receptor_defs [[required_links, toxic_count], ...] (the
## receptors are the points nearest to evenly spread spots), taut bonds when asked.
static func _contagion_spec(id: String, count: int, seed_value: int, receptor_defs: Array,
		tension_count: int, rx: float, ry: float, harmonics: Array, par_time: float,
		story: String) -> Dictionary:
	var center := Vector2(960, 570)
	var area := Organic.polar(center, rx, ry, harmonics, 110)
	var sol := Layouts.scatter(area, [], count, 190.0, 60.0, seed_value)
	var defs: Array = []
	for k in receptor_defs.size():
		var angle := TAU * (k + 0.35) / receptor_defs.size()
		var target := center + Vector2(cos(angle) * rx * 0.45, sin(angle) * ry * 0.45)
		defs.append([Layouts.nearest_index(sol, target), receptor_defs[k][0], receptor_defs[k][1]])
	var plan := Layouts.receptor_plans(sol, defs)
	var receptors: Dictionary = plan["receptors"]
	var edges := Layouts.planar_edges(sol, 480.0, 58.0, 0.0, seed_value)
	edges = edges.filter(func(e: Array) -> bool: return not receptors.has(e[0]) and not receptors.has(e[1]))
	return {
		"id": id, "name": "MISSION_%s_NAME" % id.to_upper(), "chapter": 8, "par_time": par_time,
		"story": story,
		"area": area,
		"sol": sol,
		"receptors": receptors,
		"toxic": plan["toxic"],
		"edges": Layouts.with_tension(sol, edges, tension_count, 200.0, 1),
	}


## Boss 8 (Contagion), HARD toxic: a ring around a lobed island, three receptors, three toxic
## neurons: one contamination link and the toxic neuron explodes.
static func _boss_patient_zero() -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), 690.0, 440.0, [[2, 0.05, 0.3]], 140)
	var obstacles := [Organic.polar(Vector2(960, 570), 230.0, 130.0, [[3, 0.1, 0.0]], 56)]
	var sol := Layouts.scatter(area, obstacles, 14, 170.0, 60.0, 4701)
	var required := [2, 1, 1]
	var sites := Layouts.dense_sites(sol, required, 380.0)
	var defs: Array = []
	for k in 3:
		defs.append([sites[k], required[k], 1])
	var plan := Layouts.receptor_plans(sol, defs)
	var receptors: Dictionary = plan["receptors"]
	var edges := Layouts.planar_edges(sol, 480.0, 58.0, 0.0, 4701)
	edges = edges.filter(func(e: Array) -> bool: return not receptors.has(e[0]) and not receptors.has(e[1]))
	return {
		"id": "m47", "name": "MISSION_M47_NAME", "chapter": 8, "boss": true, "hard_toxic": true,
		"par_time": 300.0,
		"story": "MISSION_M47_STORY",
		"area": area,
		"obstacles": obstacles,
		"sol": sol,
		"receptors": receptors,
		"toxic": plan["toxic"],
		"edges": Layouts.with_tension(sol, edges, 2, 200.0, 2),
	}


# --- Chapter 9: Convergence boss -----------------------------------------------------------

## Final boss: every mechanic on a big lobed cell with a live island and live arcs: anchors, taut
## bonds, diseased chords, receptors, toxic neurons (HARD).
static func _boss_core() -> Dictionary:
	var area := Organic.polar(Vector2(960, 570), 760.0, 440.0, [[3, 0.1, 0.2], [2, 0.07, 1.4]], 180)
	var obstacles := [Organic.polar(Vector2(960, 570), 120.0, 90.0, [[3, 0.08, 0.6]], 48)]
	var lethal := Organic.edges_where(area, func(mid: Vector2, n: Vector2) -> bool:
		return n.y < -0.6 and absf(mid.x - 960.0) < 330.0)
	var sol := Layouts.scatter(area, obstacles, 16, 180.0, 60.0, 4801, Organic.edge_segments(area, lethal), 60.0)
	var fixed := [Layouts.nearest_index(sol, Vector2(330, 570)), Layouts.nearest_index(sol, Vector2(1590, 570))]
	var sites := Layouts.dense_sites(sol, [2, 1], 400.0, fixed)
	var defs := [[sites[0], 2, 1], [sites[1], 1, 1]]
	var plan := Layouts.receptor_plans(sol, defs, fixed)
	var receptors: Dictionary = plan["receptors"]
	var toxic: Array = plan["toxic"]
	var receptor_ids: Array = receptors.keys()
	var edges := Layouts.planar_edges(sol, 480.0, 58.0, 0.1, 4801)
	edges = edges.filter(func(e: Array) -> bool: return not receptors.has(e[0]) and not receptors.has(e[1]))
	edges = Layouts.with_tension(sol, edges, 3, 200.0, 2)
	for pair: Array in Layouts.chords(sol, edges, 2, 280.0, 480.0, 58.0, 4808, fixed + receptor_ids + toxic):
		edges.append(Layouts.diseased(sol, pair))
	return {
		"id": "m48", "name": "MISSION_M48_NAME", "chapter": 9, "boss": true, "hard_toxic": true,
		"par_time": 300.0,
		"story": "MISSION_M48_STORY",
		"area": area,
		"obstacles": obstacles,
		"lethal_edges": lethal,
		"lethal_obstacles": [0],
		"sol": sol,
		"fixed": fixed,
		"receptors": receptors,
		"toxic": toxic,
		"edges": edges,
	}
