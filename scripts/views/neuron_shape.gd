class_name NeuronShape
extends RefCounted
## Organic, strictly convex soma outline of one neuron (SDD 5.4), as a radius function
## r(theta, t) in units of the model neuron radius:
##
##   r = MEAN_RADIUS * (1 + BREATH * sin(t * BREATH_SPEED + breath_phase)) * (1 + g)
##   g = sum_k amp[k] * cos(FREQ[k] * theta + phase[k] + DRIFT[k] * t)      k = 1..4
##       + lobe.z * cos(lobe.x * theta + lobe.y + LOBE_DRIFT * t)   (3..5 gentle lobes)
##
## Low-frequency modes only (1 = lopsided, 2 = oval, 3 = three soft lobes, 4 = squarish), small
## amplitudes, so the outline never gets a concave notch: the polar convexity condition
## r^2 + 2 r'^2 - r r'' >= 0 holds at every angle and time (see tests/views/test_neuron_shape.gd).
## The radius stays inside ~0.82..1.05 of the collision circle.
##
## SYNC: assets/shaders/neuron.gdshader evaluates the same formula (shape_scale()); the constants
## and the formula below must stay in sync with it. Per-neuron parameters (phase, amp, nucleus)
## come from for_seed() and are pushed to the shader as uniforms, so the GPU never hashes.
## Time t is TIME * motion: 0 with reduced motion, which freezes drift and breathing.

const MEAN_RADIUS := 0.93
const BREATH := 0.015
const BREATH_SPEED := 1.1
## Mode numbers, and phase drift in rad/s per mode (alternating directions, very slow).
const FREQ := Vector4(1.0, 2.0, 3.0, 4.0)
const DRIFT := Vector4(0.23, -0.31, 0.41, -0.27)
## Largest amplitude of each mode (a per-seed factor scales it down).
const MAX_AMP := Vector4(0.02, 0.045, 0.024, 0.009)
## Lobes where branches could emerge: count 3..5 (per seed), amplitude and phase drift.
const LOBE_MIN := 3
const LOBE_MAX := 5
const LOBE_AMP := 0.014
const LOBE_DRIFT := 0.19
## Branching hint: 2..4 faint wisps outside the solid body (not part of the silhouette), at most
## WISP_MAX_LENGTH soma radii long, swaying by WISP_SWAY radians.
const WISP_MIN := 2
const WISP_MAX := 4
const WISP_MAX_LENGTH := 0.35
const WISP_MIN_LENGTH := 0.2
const WISP_SWAY := 0.14
const MIN_AMP_FACTOR := 0.85
## Nucleus offset from the center, in soma radii.
const NUCLEUS_OFFSET_MIN := 0.04
const NUCLEUS_OFFSET_MAX := 0.13

var phase := Vector4.ZERO
var amp := Vector4.ZERO
var breath_phase := 0.0
var nucleus := Vector2.ZERO
## (count, phase, amplitude) of the lobe mode.
var lobe := Vector3(3.0, 0.0, 0.0)
## Wisp angles (radians) and lengths (soma radii); a length of 0 means the wisp is absent.
var wisp_angle := Vector4.ZERO
var wisp_len := Vector4.ZERO


## Deterministic per-seed shape (the same seed always gives the same shape, on every platform).
static func for_seed(seed_value: int) -> NeuronShape:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_value * 7919 + 104729)
	var shape := NeuronShape.new()
	shape.phase = Vector4(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	shape.amp = Vector4(
		MAX_AMP.x * rng.randf_range(MIN_AMP_FACTOR, 1.0),
		MAX_AMP.y * rng.randf_range(MIN_AMP_FACTOR, 1.0),
		MAX_AMP.z * rng.randf_range(MIN_AMP_FACTOR, 1.0),
		MAX_AMP.w * rng.randf_range(MIN_AMP_FACTOR, 1.0))
	shape.breath_phase = rng.randf() * TAU
	shape.nucleus = Vector2.from_angle(rng.randf() * TAU) \
		* rng.randf_range(NUCLEUS_OFFSET_MIN, NUCLEUS_OFFSET_MAX)
	shape.lobe = Vector3(float(rng.randi_range(LOBE_MIN, LOBE_MAX)), rng.randf() * TAU,
		LOBE_AMP * rng.randf_range(0.6, 1.0))
	var count := rng.randi_range(WISP_MIN, WISP_MAX)
	var base := rng.randf() * TAU
	var angles: Array[float] = []
	var lengths: Array[float] = []
	for i in WISP_MAX:
		angles.append(base + TAU * float(i) / float(count) + rng.randf_range(-0.35, 0.35))
		lengths.append(rng.randf_range(WISP_MIN_LENGTH, WISP_MAX_LENGTH) if i < count else 0.0)
	shape.wisp_angle = Vector4(angles[0], angles[1], angles[2], angles[3])
	shape.wisp_len = Vector4(lengths[0], lengths[1], lengths[2], lengths[3])
	return shape


func wisp_count() -> int:
	var n := 0
	for i in 4:
		if wisp_len[i] > 0.0:
			n += 1
	return n


## Outline radius at angle theta (radians) and time t, in model radii.
func radius_at(theta: float, t: float) -> float:
	return _breathing(t) * (1.0 + _g(theta, t, 0))


## Polar convexity value r^2 + 2 r'^2 - r r'' (>= 0 means convex at that angle).
func convexity_at(theta: float, t: float) -> float:
	var b := _breathing(t)
	var r := b * (1.0 + _g(theta, t, 0))
	var dr := b * _g(theta, t, 1)
	var ddr := b * _g(theta, t, 2)
	return r * r + 2.0 * dr * dr - r * ddr


## The outline as a polygon of `count` points (model radii), for tests and debugging.
func outline(t: float, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in count:
		var theta := TAU * float(i) / float(count)
		points.append(Vector2.from_angle(theta) * radius_at(theta, t))
	return points


## True when every consecutive triple turns the same way (no concave vertex).
static func is_convex_polygon(points: PackedVector2Array) -> bool:
	var n := points.size()
	var sign_seen := 0.0
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var c := points[(i + 2) % n]
		var cross := (b - a).cross(c - b)
		if absf(cross) < 1e-9:
			continue
		if sign_seen == 0.0:
			sign_seen = signf(cross)
		elif signf(cross) != sign_seen:
			return false
	return true


func _breathing(t: float) -> float:
	return MEAN_RADIUS * (1.0 + BREATH * sin(t * BREATH_SPEED + breath_phase))


## Relative radius modulation g (derivative 0), g' (1) or g'' (2) with respect to theta.
func _g(theta: float, t: float, derivative: int) -> float:
	var total := 0.0
	for k in 4:
		var f: float = FREQ[k]
		var angle: float = f * theta + phase[k] + DRIFT[k] * t
		match derivative:
			0:
				total += amp[k] * cos(angle)
			1:
				total -= amp[k] * f * sin(angle)
			_:
				total -= amp[k] * f * f * cos(angle)
	var lobe_angle := lobe.x * theta + lobe.y + LOBE_DRIFT * t
	match derivative:
		0:
			total += lobe.z * cos(lobe_angle)
		1:
			total -= lobe.z * lobe.x * sin(lobe_angle)
		_:
			total -= lobe.z * lobe.x * lobe.x * cos(lobe_angle)
	return total
