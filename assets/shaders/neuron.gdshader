// Neuron soma with soft glow halo (SDD 5.4). Drawn on one quad per neuron by NeuronView.
// Premultiplied alpha: the soma is opaque (alpha = coverage) and covers dendrite ends, while
// the halo only adds light (alpha 0), which reads as additive bloom on the black background.
// Every animated term is multiplied by `motion` (0 when reduced motion is on).
// Crossing (T7.1): the soma keeps its own color; a soft warm "latency" glow (latency_color)
// breathes slowly in the halo, with a few small sparks twinkling around the soma (`sparkle`,
// 0 with reduced motion, when the glow is static).
// Overload (T7.2): before a lethal-wall explosion the soma trembles and burns violet-white.
// Body shape: a smooth, strictly convex organic blob (low-frequency radius modulation, see
// shape_scale()), different per neuron through the shape_* uniforms; no spikes or notches.
// The formula and constants must stay in sync with NeuronShape (scripts/views/neuron_shape.gd),
// which the tests use to prove convexity and the radius band around the collision circle.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform vec4 core_color : source_color = vec4(1.0);
uniform vec4 glow_color : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform vec4 latency_color : source_color = vec4(1.0, 0.42, 0.28, 1.0);
uniform float latency_speed = 1.1;
uniform float latency_glow = 0.5;
uniform float sparkle = 1.0;
uniform vec4 overload_color : source_color = vec4(1.0, 0.75, 1.0, 1.0);
uniform float radius_px = 28.0;
uniform float half_size_px = 80.0;
uniform float glow_strength = 0.55;
uniform float pulse_speed = 1.8;
uniform float pulse_depth = 0.1;
uniform float phase = 0.0;
uniform float motion = 1.0;
// Per-neuron body shape (NeuronShape.for_seed): phases and amplitudes of the four modes, and the
// nucleus offset in soma radii.
uniform vec4 shape_phase = vec4(0.0);
uniform vec4 shape_amp = vec4(0.0);
uniform vec2 nucleus = vec2(0.0);
uniform float shape_breath = 0.0;
uniform vec3 shape_lobe = vec3(3.0, 0.0, 0.0);
// Branching hint: faint wisps outside the solid body (angles, lengths in soma radii; 0 = absent).
uniform vec4 wisp_angle = vec4(0.0);
uniform vec4 wisp_len = vec4(0.0);
uniform float wisp_strength = 0.5;
// 0..1 crossing latency glow, contact ring, overall brightness boost and overload.
uniform float crossing = 0.0;
uniform float contact = 0.0;
uniform float brightness = 1.0;
uniform float overload = 0.0;
// Toxic neuron (T8.2): a pulsing warning halo (and a ring when contaminating), 0..1.
uniform vec4 warn_color : source_color = vec4(1.0, 0.84, 0.1, 1.0);
uniform float warn = 0.0;
uniform float warn_speed = 2.4;

// Must stay in sync with NeuronShape (MEAN_RADIUS, BREATH, BREATH_SPEED, FREQ, DRIFT).
const float SHAPE_MEAN = 0.93;
const float SHAPE_BREATH = 0.015;
const float SHAPE_BREATH_SPEED = 1.1;
const vec4 SHAPE_FREQ = vec4(1.0, 2.0, 3.0, 4.0);
const vec4 SHAPE_DRIFT = vec4(0.23, -0.31, 0.41, -0.27);
const float SHAPE_LOBE_DRIFT = 0.19;
const float WISP_SWAY = 0.14;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

// Outline radius in soma radii at angle a and time t (t = TIME * motion). Convex by construction.
float shape_scale(float a, float t) {
	float g = dot(shape_amp, cos(SHAPE_FREQ * a + shape_phase + SHAPE_DRIFT * t));
	g += shape_lobe.z * cos(shape_lobe.x * a + shape_lobe.y + SHAPE_LOBE_DRIFT * t);
	return SHAPE_MEAN * (1.0 + SHAPE_BREATH * sin(t * SHAPE_BREATH_SPEED + shape_breath)) * (1.0 + g);
}

// Faint tapered wisp i leaving the body at its seeded angle, fading to nothing; returns 0..1.
float wisp(vec2 p, float i, float t) {
	float len = wisp_len[int(i)];
	if (len <= 0.0) {
		return 0.0;
	}
	float wa = wisp_angle[int(i)] + WISP_SWAY * sin(t * 0.7 + i * 2.3 + shape_breath);
	vec2 dir = vec2(cos(wa), sin(wa));
	float along = dot(p, dir) - radius_px * shape_scale(wa, t) * 0.8;
	float u = along / (len * radius_px);
	if (u < 0.0 || u > 1.0) {
		return 0.0;
	}
	float perp = dot(p, vec2(-dir.y, dir.x)) - 0.35 * len * radius_px * u * u * sin(t * 0.9 + i * 1.9);
	float w = mix(2.6, 0.5, u);
	return exp(-perp * perp / (w * w)) * pow(1.0 - u, 1.5) * smoothstep(0.0, 0.25, u);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * half_size_px;
	float t = TIME * motion;
	// Overload tremble: the whole soma jitters (only with motion).
	p += vec2(sin(TIME * 93.0 + phase), cos(TIME * 71.0)) * overload * 4.0 * motion;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float pulse = 1.0 + pulse_depth * sin(t * pulse_speed + phase);

	// Organic convex outline: a slow, lopsided blob that breathes and drifts a little.
	float r = radius_px * shape_scale(ang, t);
	float core = 1.0 - smoothstep(r - 1.2, r + 1.2, d);

	// Soma shading: slightly dimmer body, brighter rim and a soft nucleus.
	float rn = clamp(d / max(r, 0.001), 0.0, 1.0);
	vec2 nq = (p - nucleus * radius_px) / (radius_px * 0.42);
	float nd2 = dot(nq, nq);
	float nucleus_ring = exp(-pow((sqrt(nd2) - 1.0) / 0.35, 2.0));
	float shade = mix(0.8, 1.0, smoothstep(0.45, 1.0, rn)) + 0.2 * exp(-nd2 * 2.2) - 0.05 * nucleus_ring;
	vec3 soma = core_color.rgb * shade * (0.94 + 0.06 * pulse);
	float o = clamp(overload, 0.0, 1.0);
	soma = mix(soma, overload_color.rgb * 1.3, o * 0.7);

	// Halo falls off with distance from the outline, breathing with the pulse.
	float c = clamp(crossing, 0.0, 1.0);
	float outside = max(d - r, 0.0) / (radius_px * 0.8);
	float halo = exp(-outside * 1.6) * glow_strength * pulse * (1.0 + o * 1.5);
	halo *= 1.0 - smoothstep(half_size_px * 0.72, half_size_px, d);

	// Crossing latency: a slow, soft warm breathing in the halo (static mid level without motion).
	float breath = mix(0.5, 0.5 + 0.5 * sin(TIME * latency_speed + phase), motion);
	float latency = exp(-outside * 1.1) * latency_glow * c * (0.55 + 0.45 * breath);
	latency *= 1.0 - smoothstep(half_size_px * 0.72, half_size_px, d);

	// Light sparkle: in each of seven angular cells a tiny spark blinks on at a random radius
	// for a short random slot; most slots stay dark.
	float sparks = 0.0;
	if (sparkle > 0.0 && c > 0.0) {
		const float CELLS = 7.0;
		float cell = floor((ang + PI) / TAU * CELLS);
		float seed = cell * 7.31 + phase * 3.7;
		float slot_time = TIME * 1.6 + hash(seed) * 10.0;
		float slot = floor(slot_time);
		float on = step(0.68, hash(slot * 1.93 + seed));
		float life = sin(PI * fract(slot_time));
		float sa = (cell + 0.3 + 0.4 * hash(slot + seed * 1.7)) / CELLS * TAU - PI;
		float sr = radius_px * shape_scale(sa, t) + 6.0 + 14.0 * hash(slot * 2.71 + seed);
		vec2 sp = vec2(cos(sa), sin(sa)) * sr;
		float sd2 = dot(p - sp, p - sp);
		sparks = on * life * (exp(-sd2 / 1.8) + 0.25 * exp(-sd2 / 20.0)) * sparkle * c;
	}
	float contact_ring = exp(-pow((d - r - 10.0) / 2.5, 2.0)) * contact;

	// Toxic warning: a halo pulsing faster when contaminating (steady mid level without motion).
	float w = clamp(warn, 0.0, 1.0);
	float warn_beat = mix(0.6, 0.5 + 0.5 * sin(TIME * warn_speed * (1.0 + 1.6 * w) + phase), motion);
	float warn_halo = exp(-outside * 0.9) * w * (0.3 + 0.7 * warn_beat) * 0.75;
	warn_halo *= 1.0 - smoothstep(half_size_px * 0.72, half_size_px, d);
	float warn_ring = exp(-pow((d - r - 9.0) / 2.2, 2.0)) * smoothstep(0.5, 1.0, w) * (0.35 + 0.65 * warn_beat);

	float wisps = 0.0;
	for (int i = 0; i < 4; i++) {
		wisps += wisp(p, float(i), t);
	}
	wisps = min(wisps, 1.0) * wisp_strength;
	vec3 wisp_rgb = mix(glow_color.rgb, core_color.rgb, 0.6);

	vec3 halo_rgb = mix(glow_color.rgb, overload_color.rgb, o);
	vec3 rgb = soma * core + (halo_rgb * halo + wisp_rgb * wisps + latency_color.rgb * latency
		+ vec3(1.0, 0.88, 0.74) * sparks + vec3(contact_ring * 0.8)
		+ warn_color.rgb * (warn_halo + warn_ring)) * (1.0 - core);
	COLOR = vec4(rgb * brightness, core * core_color.a);
}
