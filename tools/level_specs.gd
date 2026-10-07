extends RefCounted
## Hand-designed campaign (SDD 7, 7.1): the single source for data/levels/mXX.tres and
## data/campaign.tres, built offline by tools/build_levels.gd. Nothing here runs in the game.
##
## Mission spec keys:
##   id, name, chapter, story ("" for none), par_time (s), par_moves (optional; default is
##   twice the planned solution moves, see build_levels.gd)
##   area: play area outline (optional, default DEFAULT_AREA), obstacles: Array of outlines
##   sol: solution positions, neuron id = index
##   start: explicit start positions, or perm + offset: start[i] = sol[perm[i]] + offset
##     (a hand-picked shuffle of the solution spots, shifted so no neuron starts on a spot)
##   fixed: ids of red fixed neurons (they start on their solution spot)
##   edges: [a, b] normal dendrite, [a, b, rest_length, max_length] tension dendrite
## Coordinates are playfield units; the level view fits them into 1920x1080.

const DEFAULT_AREA := [160, 120, 1760, 120, 1760, 1020, 160, 1020]


static func chapters() -> Array[Dictionary]:
	return [
		{"id": 1, "title": "First Signals",
			"subtitle": "A dormant network wakes. Untangle its first connections."},
		{"id": 2, "title": "Shaped Minds",
			"subtitle": "Thought bends to the shape of its vessel. Walls and hollows guide every move."},
		{"id": 3, "title": "Anchored",
			"subtitle": "Some memories will not move. Build the network around the red anchors."},
		{"id": 4, "title": "Tension",
			"subtitle": "Strained bonds glow green. Pull them too far apart and they snap."},
		{"id": 5, "title": "Convergence",
			"subtitle": "Walls, anchors and fragile bonds. Everything the network has learned, at once."},
	]


static func missions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	result.append_array(_chapter_1())
	result.append_array(_chapter_2())
	result.append_array(_chapter_3())
	result.append_array(_chapter_4())
	result.append_array(_chapter_5())
	return result


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
			"id": "m01", "name": "First Spark", "chapter": 1, "par_moves": 6, "par_time": 60.0,
			"story": "In the dark, a first spark is looking for a way through.\nUntangle the threads so the signal can pass.",
			"sol": pts([660, 370, 1260, 370, 1260, 770, 660, 770]),
			"start": pts([700, 330, 1250, 420, 620, 760, 1300, 720]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 0]],
		},
		{
			# First hub: neuron 0 holds four dendrites and starts swapped with neuron 4.
			"id": "m02", "name": "Branching Paths", "chapter": 1, "par_moves": 8, "par_time": 90.0,
			"story": "",
			"sol": pts([960, 570, 660, 320, 1260, 320, 1260, 820, 960, 920, 660, 820]),
			"start": pts([960, 920, 660, 320, 1260, 320, 1260, 820, 960, 570, 660, 820]),
			"edges": [[0, 1], [0, 2], [0, 3], [0, 5], [1, 2], [2, 3], [3, 4], [4, 5], [5, 1]],
		},
		{
			# A 5-cycle drawn as a pentagram (five crossings) that opens into a pentagon.
			"id": "m03", "name": "Echo Loop", "chapter": 1, "par_time": 60.0,
			"story": "",
			"sol": pts([960, 270, 1245, 477, 1136, 813, 784, 813, 675, 477]),
			"start": pts([1160, 295, 960, 910, 760, 295, 1283, 675, 637, 675]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
		},
		{
			# Triangular prism: a triangle nested in a triangle, joined by three spokes.
			# Start: the inner triangle is mirrored and its apex swapped with the outer apex.
			"id": "m04", "name": "Twin Circuits", "chapter": 1, "par_time": 90.0,
			"story": "Two loops hum in parallel, one inside the other.\nGive each its own orbit.",
			"sol": pts([960, 200, 1400, 900, 520, 900, 960, 450, 1140, 760, 780, 760]),
			"start": pts([1010, 490, 1350, 860, 570, 860, 1010, 240, 830, 720, 1090, 720]),
			"edges": [[0, 1], [1, 2], [2, 0], [3, 4], [4, 5], [5, 3], [0, 3], [1, 4], [2, 5]],
		},
		{
			# Wheel: one hub, six rim neurons, every rim neuron wired to the hub.
			"id": "m05", "name": "Relay Hub", "chapter": 1, "par_time": 120.0,
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
			"id": "m06", "name": "Bent Corridor", "chapter": 2, "par_time": 120.0,
			"story": "Not every mind is a perfect square.\nHere the walls bend, and so must the signal.",
			"area": pts([160, 120, 900, 120, 900, 640, 1760, 640, 1760, 1020, 160, 1020]),
			"sol": pts([330, 260, 720, 260, 330, 600, 720, 560, 450, 880, 1000, 860, 1300, 730, 1600, 900]),
			"perm": [6, 4, 7, 5, 1, 2, 0, 3], "offset": Vector2(50, 50), "nudge": {0: Vector2(-18, 24)},
			"edges": [[0, 1], [0, 2], [1, 3], [2, 3], [0, 3], [2, 4], [3, 4], [3, 5], [4, 5],
				[5, 6], [5, 7], [6, 7]],
		},
		{
			# A ring around a solid hollow: square antiprism, inner square around the hole.
			"id": "m07", "name": "The Hollow", "chapter": 2, "par_time": 150.0,
			"story": "",
			"obstacles": [pts([760, 450, 1160, 450, 1160, 690, 760, 690])],
			"sol": pts([960, 300, 1420, 570, 960, 840, 500, 570, 400, 230, 1520, 230, 1520, 910, 400, 910]),
			"perm": [2, 7, 0, 5, 1, 3, 6, 4], "offset": Vector2(50, 50),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4],
				[0, 4], [0, 5], [1, 5], [1, 6], [2, 6], [2, 7], [3, 7], [3, 4]],
		},
		{
			# Two chambers and a corridor one neuron wide; neuron 4 starts inside it.
			"id": "m08", "name": "Narrow Passage", "chapter": 2, "par_time": 150.0,
			"story": "Two chambers, one narrow bridge.\nOnly one neuron fits through at a time.",
			"area": pts([160, 120, 760, 120, 760, 500, 1160, 500, 1160, 120, 1760, 120,
				1760, 1020, 1160, 1020, 1160, 640, 760, 640, 760, 1020, 160, 1020]),
			"sol": pts([320, 280, 620, 560, 320, 860, 600, 250, 1300, 570, 1600, 280, 1600, 860, 1320, 880]),
			"start": pts([1650, 600, 1450, 300, 1250, 300, 1450, 850, 960, 570, 400, 350, 550, 900, 400, 600]),
			"edges": [[0, 3], [3, 1], [1, 2], [2, 0], [0, 1], [1, 4], [4, 5], [5, 6], [6, 4],
				[6, 7], [7, 4]],
		},
		{
			# A triangulated 3x3 lattice whose empty cells hold solid islands.
			"id": "m09", "name": "Scattered Islands", "chapter": 2, "par_time": 150.0,
			"story": "",
			"obstacles": [
				pts([600, 330, 760, 330, 760, 490, 600, 490]),
				pts([1160, 650, 1320, 650, 1320, 810, 1160, 810]),
				pts([170, 700, 260, 700, 260, 780, 170, 780]),
			],
			"sol": pts([400, 250, 960, 250, 1520, 250, 400, 570, 960, 570, 1520, 570, 400, 890, 960, 890, 1520, 890]),
			"perm": [5, 7, 3, 8, 0, 6, 1, 2, 4], "offset": Vector2(50, 50),
			"nudge": {0: Vector2(60, 0), 2: Vector2(70, 0), 6: Vector2(0, 60), 8: Vector2(30, -50)},
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [6, 7], [7, 8], [0, 3], [3, 6], [1, 4],
				[4, 7], [2, 5], [5, 8], [1, 5], [3, 7]],
		},
		{
			# U-shaped area: the two arms only meet through the bottom fold.
			"id": "m10", "name": "Folded Cortex", "chapter": 2, "par_time": 150.0,
			"story": "",
			"area": pts([160, 120, 620, 120, 620, 700, 1300, 700, 1300, 120, 1760, 120, 1760, 1020, 160, 1020]),
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
			"id": "m11", "name": "Anchor Point", "chapter": 3, "par_time": 120.0,
			"story": "A red neuron holds its ground: an old, stubborn memory.\nIt will not move. Weave the rest around it.",
			"sol": pts([960, 570, 1280, 570, 1120, 847, 800, 847, 640, 570, 800, 293, 1120, 293, 960, 960]),
			"fixed": [0],
			"perm": [0, 4, 6, 7, 2, 1, 3, 5], "offset": Vector2(50, -50), "nudge": {3: Vector2(-90, -10)},
			"edges": [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1], [0, 1], [0, 3], [0, 5],
				[7, 2], [7, 3]],
		},
		{
			# Triangulated lattice pinned at two opposite corners.
			"id": "m12", "name": "Pinned Lattice", "chapter": 3, "par_time": 150.0,
			"story": "",
			"sol": pts([500, 250, 960, 250, 1420, 250, 500, 570, 960, 570, 1420, 570, 500, 890, 960, 890, 1420, 890]),
			"fixed": [2, 6],
			"perm": [4, 7, 2, 1, 8, 0, 6, 3, 5], "offset": Vector2(50, 50),
			"nudge": {0: Vector2(50, -80), 3: Vector2(0, 50)},
			"edges": [[0, 1], [1, 2], [3, 4], [4, 5], [6, 7], [7, 8], [0, 3], [3, 6], [1, 4],
				[4, 7], [2, 5], [5, 8], [0, 4], [1, 5], [3, 7], [4, 8]],
		},
		{
			# Pentagonal prism with three anchors, inner and outer.
			"id": "m13", "name": "Red Constellation", "chapter": 3, "par_time": 180.0,
			"story": "Three fixed stars in the dark.\nEvery other light must find its orbit between them.",
			"sol": pts([960, 190, 1321, 453, 1183, 877, 737, 877, 599, 453,
				960, 400, 1122, 517, 1060, 708, 860, 708, 798, 517]),
			"fixed": [0, 4, 7],
			"perm": [0, 9, 5, 6, 4, 3, 8, 7, 1, 2], "offset": Vector2(40, 40), "nudge": {1: Vector2(92, 0)},
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0], [5, 6], [6, 7], [7, 8], [8, 9], [9, 5],
				[0, 5], [1, 6], [2, 7], [3, 8], [4, 9]],
		},
		{
			# Four anchored corners pull on a hexagonal wheel; side walls narrow the field.
			"id": "m14", "name": "Iron Synapse", "chapter": 3, "par_time": 180.0,
			"story": "",
			"obstacles": [
				pts([160, 520, 260, 520, 260, 620, 160, 620]),
				pts([1660, 520, 1760, 520, 1760, 620, 1660, 620]),
			],
			"sol": pts([960, 570, 1260, 570, 1110, 830, 810, 830, 660, 570, 810, 310, 1110, 310,
				360, 230, 1560, 230, 1560, 910, 360, 910]),
			"fixed": [7, 8, 9, 10],
			"perm": [3, 5, 0, 6, 1, 2, 4, 7, 8, 9, 10], "offset": Vector2(50, 50), "nudge": {2: Vector2(52, 30)},
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
			"id": "m15", "name": "Taut Thread", "chapter": 4, "par_time": 150.0,
			"story": "Some bonds are short and fragile.\nGreen threads snap if their neurons drift too far apart.",
			"sol": pts([960, 570, 1220, 570, 1090, 795, 830, 795, 700, 570, 830, 345, 1090, 345, 360, 570, 1560, 570]),
			"start": pts([960, 570, 680, 640, 1130, 230, 1150, 880, 1240, 500, 780, 850, 720, 360, 1600, 420, 360, 300]),
			"edges": [[0, 1, 200.0, 330.0], [0, 2], [0, 3], [0, 4, 200.0, 330.0], [0, 5], [0, 6],
				[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1],
				[7, 4], [7, 5], [7, 3], [8, 1], [8, 2], [8, 6]],
		},
		{
			# Ladder whose three tension rungs start flipped upside down.
			"id": "m16", "name": "Elastic Bond", "chapter": 4, "par_time": 180.0,
			"story": "",
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
			"id": "m17", "name": "Tight Weave", "chapter": 4, "par_time": 210.0,
			"story": "Pairs that must stay close, tangled with pairs that must not touch.\nMove them together.",
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
			"id": "m18", "name": "Breaking Point", "chapter": 4, "par_time": 240.0,
			"story": "",
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


# --- Chapter 5: Convergence (everything combined) -----------------------------

static func _chapter_5() -> Array[Dictionary]:
	return [
		{
			# 4x3 lattice with two islands and two anchors.
			"id": "m19", "name": "Converging Paths", "chapter": 5, "par_time": 210.0,
			"story": "Walls, anchors and fragile threads meet in one network.\nEverything it has learned is tested here.",
			"obstacles": [
				pts([880, 355, 1040, 355, 1040, 465, 880, 465]),
				pts([1253, 675, 1413, 675, 1413, 785, 1253, 785]),
			],
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
			# Hexagonal field, fixed hub, three folded tension pairs.
			"id": "m20", "name": "Neural Storm", "chapter": 5, "par_time": 240.0,
			"story": "",
			"area": pts([360, 120, 1560, 120, 1760, 570, 1560, 1020, 360, 1020, 160, 570]),
			"sol": pts([960, 570, 1190, 570, 1075, 769, 845, 769, 730, 570, 845, 371, 1075, 371,
				1306, 770, 960, 970, 614, 770, 614, 370, 960, 170, 1306, 370]),
			"fixed": [0, 8],
			"start": pts([960, 570, 1240, 810, 1300, 250, 680, 700, 1360, 700, 890, 190, 480, 470,
				1330, 540, 960, 970, 960, 760, 800, 900, 780, 430, 560, 580]),
			"edges": [[1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 1],
				[0, 1], [0, 2], [0, 3], [0, 4], [0, 5], [0, 6],
				[7, 1, 200.0, 320.0], [7, 2], [8, 2], [8, 3], [9, 3, 200.0, 320.0], [9, 4],
				[10, 4], [10, 5], [11, 5, 200.0, 320.0], [11, 6], [12, 6], [12, 1],
				[7, 8], [9, 10], [11, 12]],
		},
		{
			# Two hemispheres around a solid core, bridged by tension, anchored top and bottom.
			"id": "m21", "name": "Awakening", "chapter": 5, "par_time": 240.0,
			"story": "Two hemispheres, one mind.\nUntangle them and the network finally wakes.",
			"area": pts([260, 120, 1660, 120, 1760, 220, 1760, 920, 1660, 1020, 260, 1020, 160, 920, 160, 220]),
			"obstacles": [pts([900, 500, 1020, 500, 1020, 640, 900, 640])],
			"sol": pts([580, 310, 805, 440, 805, 700, 580, 830, 355, 700, 355, 440,
				1340, 310, 1115, 440, 1115, 700, 1340, 830, 1565, 700, 1565, 440, 960, 250, 960, 890]),
			"fixed": [10, 12, 13],
			"start": pts([1500, 330, 880, 380, 720, 760, 1250, 420, 1600, 520, 1260, 840,
				280, 560, 600, 500, 430, 700, 700, 640, 1565, 700, 520, 900, 960, 250, 960, 890]),
			"edges": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0],
				[6, 7], [7, 8], [8, 9], [9, 10], [10, 11], [11, 6],
				[1, 7, 250.0, 380.0], [2, 8, 250.0, 380.0],
				[12, 0], [12, 1], [12, 6], [12, 7],
				[13, 2], [13, 3], [13, 8], [13, 9, 300.0, 440.0],
				[5, 1], [4, 2], [11, 7], [10, 8]],
		},
	]
