class_name NeuronMorphology
extends RefCounted
## Multipolar neuron body (SDD 5.4), generated once per neuron from its id (deterministic): a
## compact angular soma with a nucleus, 3-6 tapered, slightly curved primary dendrites that fork
## into thinner branches (with the odd side twig), and ONE thinner, straighter axon ending in a
## small bulb or a few tiny end-feet. Pure data plus a mesh builder; no node access.
##
## Units are model neuron radii (the collision circle has radius 1). The soma is about 0.6, all
## process tips stay within MAX_REACH (1.5). Processes can be oriented towards linked neighbours
## (link_angles, longest link first: the axon takes the first, dendrites the following ones; the
## remaining processes fill the largest angular gaps with seeded jitter).
##
## The soma outline is drawn by assets/shaders/neuron.gdshader, which mirrors soma_radius_at()
## (SOMA_BASE, CORNER_CAP, SOMA_BREATH, SOMA_BREATH_SPEED must stay in sync, see the tests). The
## processes are drawn from build_mesh() by assets/shaders/neuron.gdshader in the same canvas item (SWAY in sync).

enum Kind { NORMAL, FIXED, RECEPTOR, TOXIC }
enum Role { DENDRITE, AXON, TWIG }

const MAX_REACH := 1.5
const SOMA_BASE := 0.86
const CORNER_CAP := 1.2
const SOMA_BREATH := 0.025
const SOMA_BREATH_SPEED := 1.1
const SWAY := 0.045
## Feather (soft edge) width of the mesh in radii, and sections per process.
const FEATHER := 0.03
const SECTIONS := 6
## Processes start this far from the soma center (inside the soma, so they grow out of it).
const ROOT_DISTANCE := 0.2
const MAX_CORNERS := 8

## Per-kind look. soma: size; corner: soma point amplitude; corner_width: softness of the points;
## arms: primary dendrite count range; length / width: scale of dendrites; taper: tip sharpness
## exponent; spread: fork angle scale; fork_depth: max fork levels; twig: side twig chance;
## axon: axon length scale (0 = none).
const PRESETS := {
	Kind.NORMAL: {"soma": 0.55, "corner": 0.4, "corner_width": 0.45, "arms_min": 4, "arms_max": 6,
		"length": 1.0, "width": 0.5, "taper": 1.1, "spread": 1.0, "fork_depth": 2,
		"twig": 0.6, "axon": 1.0},
	# Fixed (red): stockier soma, shorter thicker arms, no fine twigs.
	Kind.FIXED: {"soma": 0.66, "corner": 0.16, "corner_width": 0.8, "arms_min": 4, "arms_max": 5,
		"length": 0.85, "width": 0.58, "taper": 1.0, "spread": 0.8, "fork_depth": 1,
		"twig": 0.0, "axon": 0.7},
	# Receptor (cyan): fewer, shorter arms.
	Kind.RECEPTOR: {"soma": 0.6, "corner": 0.24, "corner_width": 0.6, "arms_min": 3, "arms_max": 4,
		"length": 0.88, "width": 0.4, "taper": 1.1, "spread": 0.9, "fork_depth": 1,
		"twig": 0.2, "axon": 0.55},
	# Toxic (yellow): sharper, spikier points.
	Kind.TOXIC: {"soma": 0.57, "corner": 0.42, "corner_width": 0.22, "arms_min": 5, "arms_max": 6,
		"length": 1.0, "width": 0.36, "taper": 1.6, "spread": 1.25, "fork_depth": 1,
		"twig": 0.0, "axon": 0.9},
}


## One tapered process: a centerline with a width per point (full width, never increasing).
class Process:
	extends RefCounted
	var points := PackedVector2Array()
	var widths := PackedFloat32Array()
	var role := Role.DENDRITE
	var phase := 0.0
	## Id of the primary process family it belongs to (arm index; the axon has its own).
	var family := 0
	## True for the first segment of a primary dendrite (it starts inside the soma).
	var is_root := false


var kind := Kind.NORMAL
var soma_radius := 0.6
var corner_amp := 0.3
var corner_width := 0.5
var corners := PackedFloat32Array()
var nucleus := Vector2.ZERO
var breath_phase := 0.0
var arm_count := 0
var has_axon := false
var processes: Array[Process] = []
## Axon terminal bulb as (x, y, radius); radius 0 when the axon ends in end-feet instead.
var bulb := Vector3.ZERO


## Deterministic morphology for a seed and kind. link_angles (radians, longest link first)
## orient processes towards linked neighbours.
static func generate(seed_value: int, kind_value: int, link_angles := PackedFloat32Array()) -> NeuronMorphology:
	var preset: Dictionary = PRESETS[kind_value]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 7919 + 104729)
	var m := NeuronMorphology.new()
	m.kind = kind_value as Kind
	m.soma_radius = float(preset.soma) * rng.randf_range(0.96, 1.04)
	m.corner_amp = preset.corner
	m.corner_width = preset.corner_width
	m.breath_phase = rng.randf() * TAU
	m.nucleus = Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.06, 0.2)
	m.arm_count = rng.randi_range(int(preset.arms_min), int(preset.arms_max))
	m.has_axon = float(preset.axon) > 0.0
	var total := m.arm_count + (1 if m.has_axon else 0)
	var angles := _assign_angles(rng, total, link_angles)
	for a in angles:
		m.corners.append(a)
	var index := 0
	if m.has_axon:
		m._add_axon(rng, preset, angles[0])
		index = 1
	for i in m.arm_count:
		m._add_dendrite(rng, preset, angles[index + i], i)
	return m


## Soma outline radius at angle theta and time t (t = TIME * motion, 0 when reduced motion).
func soma_radius_at(theta: float, t: float) -> float:
	var s := 0.0
	for a in corners:
		var dd := atan2(sin(theta - a), cos(theta - a))
		s += exp(-dd * dd / corner_width)
	var breath := 1.0 + SOMA_BREATH * sin(t * SOMA_BREATH_SPEED + breath_phase)
	return soma_radius * breath * (SOMA_BASE + corner_amp * minf(s, CORNER_CAP))


## Farthest centerline point, bulb included, from the soma center (model radii).
func max_reach() -> float:
	var reach := 0.0
	for p in processes:
		for point in p.points:
			reach = maxf(reach, point.length())
	if bulb.z > 0.0:
		reach = maxf(reach, Vector2(bulb.x, bulb.y).length() + bulb.z)
	return reach


func get_axon() -> Process:
	for p in processes:
		if p.role == Role.AXON and p.family == -1:
			return p
	return null


## Angles (radians) of the primary dendrite roots, in arm order.
func dendrite_angles() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for p in processes:
		if p.role == Role.DENDRITE and p.is_root:
			out.append(p.points[0].angle())
	return out


## The whole neuron as one feathered triangle mesh: alpha 1 in the cores and 0 on the outer
## feather edge; COLOR.r a shade, UV.x section distance from the soma, UV.y process phase.
func build_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for p in processes:
		_add_strip(p, verts, colors, uvs, indices)
	if bulb.z > 0.0:
		_add_bulb(verts, colors, uvs, indices)
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _assign_angles(rng: RandomNumberGenerator, total: int, link_angles: PackedFloat32Array) -> Array[float]:
	var angles: Array[float] = []
	for a in link_angles:
		if angles.size() < total:
			angles.append(a)
	if angles.is_empty():
		angles.append(rng.randf() * TAU)
	# Fill the largest angular gaps (seeded jitter) until every process has a direction.
	while angles.size() < total:
		var sorted := angles.duplicate()
		sorted.sort()
		var best_gap := -1.0
		var best_mid := 0.0
		for i in sorted.size():
			var a: float = sorted[i]
			var b: float = sorted[(i + 1) % sorted.size()] + (TAU if i == sorted.size() - 1 else 0.0)
			var gap := b - a
			if sorted.size() == 1:
				gap = TAU
			if gap > best_gap:
				best_gap = gap
				best_mid = a + gap * (0.5 + rng.randf_range(-0.15, 0.15))
		angles.append(fposmod(best_mid, TAU))
	return angles


func _add_dendrite(rng: RandomNumberGenerator, preset: Dictionary, angle: float, family: int) -> void:
	var local: Array[Process] = []
	var depth := int(preset.fork_depth)
	if depth > 1 and rng.randf() < 0.4:
		depth = 1
	var length: float = rng.randf_range(0.62, 0.82) * float(preset.length)
	var width: float = float(preset.width) * rng.randf_range(0.92, 1.08)
	_branch(rng, preset, local, Vector2.from_angle(angle) * ROOT_DISTANCE, angle, length, width,
		depth, family, Role.DENDRITE, true)
	_commit(local)


## Builds one process and, when depth > 0, its two child forks (Y), recursively.
func _branch(rng: RandomNumberGenerator, preset: Dictionary, out: Array[Process], origin: Vector2,
		angle: float, length: float, w_start: float, depth: int, family: int, role: Role,
		primary: bool) -> void:
	var p := Process.new()
	p.role = role
	p.family = family
	p.is_root = primary and role == Role.DENDRITE
	p.phase = rng.randf() * TAU
	var curve := rng.randf_range(-0.5, 0.5) * (0.6 if role == Role.AXON else 1.0)
	var step := length / float(SECTIONS)
	var pos := origin
	var taper: float = preset.taper
	var end_frac := 0.2 if depth > 0 else 0.0
	p.points.append(pos)
	p.widths.append(w_start)
	for k in range(1, SECTIONS + 1):
		var u0 := float(k - 1) / float(SECTIONS)
		var u1 := float(k) / float(SECTIONS)
		pos += Vector2.from_angle(angle + curve * (u0 + u1) * 0.5) * step
		p.points.append(pos)
		if depth > 0:
			# Thick root that slims quickly into a slender process (like the textbook drawing).
			p.widths.append(w_start * (end_frac + (1.0 - end_frac) * pow(1.0 - u1, 2.2)))
		else:
			p.widths.append(w_start * pow(1.0 - u1, taper))
	out.append(p)
	var tangent := angle + curve
	if primary and depth > 0 and float(preset.twig) > 0.0 and rng.randf() < float(preset.twig):
		var at := int(SECTIONS * 0.5)
		var twig_angle := angle + curve * 0.5 + (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(0.8, 1.2)
		_branch(rng, preset, out, p.points[at], twig_angle, rng.randf_range(0.12, 0.2),
			p.widths[at] * 0.4, 0, family, Role.TWIG, false)
	if depth > 0:
		var w_end: float = p.widths[SECTIONS]
		var spread: float = rng.randf_range(0.4, 0.7) * float(preset.spread)
		var child_len := length * rng.randf_range(0.7, 0.9)
		for side in [-1.0, 1.0]:
			var jitter := rng.randf_range(-0.12, 0.12)
			_branch(rng, preset, out, pos, tangent + side * spread + jitter, child_len * rng.randf_range(0.9, 1.1),
				w_end * 1.0, depth - 1, family, role, false)


func _add_axon(rng: RandomNumberGenerator, preset: Dictionary, angle: float) -> void:
	var local: Array[Process] = []
	var length: float = rng.randf_range(0.8, 0.95) * float(preset.axon)
	var p := Process.new()
	p.role = Role.AXON
	p.family = -1
	p.phase = rng.randf() * TAU
	var curve := rng.randf_range(-0.22, 0.22)
	var step := length / float(SECTIONS)
	var pos := Vector2.from_angle(angle) * ROOT_DISTANCE
	var w0 := 0.12
	p.points.append(pos)
	p.widths.append(w0)
	for k in range(1, SECTIONS + 1):
		var u0 := float(k - 1) / float(SECTIONS)
		var u1 := float(k) / float(SECTIONS)
		pos += Vector2.from_angle(angle + curve * (u0 + u1) * 0.5) * step
		p.points.append(pos)
		p.widths.append(w0 * lerpf(1.0, 0.55, u1))
	local.append(p)
	var tangent := angle + curve
	if rng.randf() < 0.5:
		_pending_bulb = Vector3(pos.x, pos.y, 0.085)
		_pending_bulb_tip = pos
	else:
		_pending_bulb = Vector3.ZERO
		for side in [-0.6, 0.0, 0.6]:
			var foot := Process.new()
			foot.role = Role.AXON
			foot.family = -2
			foot.phase = rng.randf() * TAU
			var foot_angle: float = tangent + side + rng.randf_range(-0.12, 0.12)
			var foot_len := rng.randf_range(0.1, 0.16)
			for k in range(0, 4):
				var u := float(k) / 3.0
				foot.points.append(pos + Vector2.from_angle(foot_angle) * foot_len * u)
				foot.widths.append(0.055 * pow(1.0 - u, 1.2))
			local.append(foot)
	_commit(local)
	bulb = _pending_bulb
	_pending_bulb = Vector3.ZERO


var _pending_bulb := Vector3.ZERO
var _pending_bulb_tip := Vector2.ZERO


## Scales a family's geometry down when it would reach beyond MAX_REACH, then stores it.
func _commit(local: Array[Process]) -> void:
	var reach := 0.0
	for p in local:
		for point in p.points:
			reach = maxf(reach, point.length())
	if _pending_bulb.z > 0.0:
		reach = maxf(reach, Vector2(_pending_bulb.x, _pending_bulb.y).length() + _pending_bulb.z)
	var factor := minf(1.0, MAX_REACH / maxf(reach, 0.0001))
	if factor < 1.0:
		for p in local:
			for i in p.points.size():
				p.points[i] = p.points[i] * factor
		_pending_bulb = Vector3(_pending_bulb.x * factor, _pending_bulb.y * factor, _pending_bulb.z)
	for p in local:
		processes.append(p)


func _add_strip(p: Process, verts: PackedVector2Array, colors: PackedColorArray,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> void:
	var n := p.points.size()
	var first := verts.size()
	for k in n:
		var prev: Vector2 = p.points[maxi(k - 1, 0)]
		var next: Vector2 = p.points[mini(k + 1, n - 1)]
		var tangent := (next - prev).normalized()
		var normal := Vector2(-tangent.y, tangent.x)
		var center: Vector2 = p.points[k]
		var half := maxf(p.widths[k], 0.0) * 0.5
		var core := maxf(half - FEATHER * 0.5, 0.0)
		var outer := half + FEATHER
		var cover := clampf(half / (FEATHER * 0.5), 0.0, 1.0)
		var shade := 1.0 - 0.3 * float(k) / float(maxi(n - 1, 1))
		var uv := Vector2(center.length(), p.phase)
		verts.append(center + normal * outer)
		verts.append(center + normal * core)
		verts.append(center - normal * core)
		verts.append(center - normal * outer)
		colors.append(Color(shade, 0.0, 0.0, 0.0))
		colors.append(Color(shade, 0.0, 0.0, cover))
		colors.append(Color(shade, 0.0, 0.0, cover))
		colors.append(Color(shade, 0.0, 0.0, 0.0))
		for j in 4:
			uvs.append(uv)
	for k in n - 1:
		var a := first + k * 4
		var b := a + 4
		for j in 3:
			indices.append_array([a + j, a + j + 1, b + j, a + j + 1, b + j + 1, b + j])


func _add_bulb(verts: PackedVector2Array, colors: PackedColorArray, uvs: PackedVector2Array,
		indices: PackedInt32Array) -> void:
	var center := Vector2(bulb.x, bulb.y)
	var first := verts.size()
	var segments := 14
	var uv := Vector2(center.length(), 1.0)
	verts.append(center)
	colors.append(Color(0.75, 0.0, 0.0, 1.0))
	uvs.append(uv)
	for k in segments:
		var dir := Vector2.from_angle(TAU * float(k) / segments)
		verts.append(center + dir * bulb.z)
		colors.append(Color(0.75, 0.0, 0.0, 1.0))
		uvs.append(uv)
	for k in segments:
		verts.append(center + Vector2.from_angle(TAU * float(k) / segments) * (bulb.z + FEATHER))
		colors.append(Color(0.75, 0.0, 0.0, 0.0))
		uvs.append(uv)
	for k in segments:
		var k2 := (k + 1) % segments
		indices.append_array([first, first + 1 + k, first + 1 + k2])
		var inner := first + 1 + k
		var inner2 := first + 1 + k2
		var outer := first + 1 + segments + k
		var outer2 := first + 1 + segments + k2
		indices.append_array([inner, outer, inner2, inner2, outer, outer2])
