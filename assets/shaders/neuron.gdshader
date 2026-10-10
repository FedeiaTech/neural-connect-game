// Neuron soma with soft glow halo (SDD 5.4). Drawn on one quad per neuron by NeuronView.
// Premultiplied alpha: the soma is opaque (alpha = coverage) and covers dendrite ends, while
// the halo only adds light (alpha 0), which reads as additive bloom on the black background.
// Every animated term is multiplied by `motion` (0 when reduced motion is on).
// Crossing (T7.1): the soma keeps its own color; a soft warm "latency" glow (latency_color)
// breathes slowly in the halo, with a few small sparks twinkling around the soma (`sparkle`,
// 0 with reduced motion, when the glow is static).
// Overload (T7.2): before a lethal-wall explosion the soma trembles and burns violet-white.
// Body (multipolar neuron): the quad draws the compact, angular soma with a visible nucleus, its
// halo and all effects; the tapered dendrites and the axon are a per-neuron feathered mesh drawn
// behind it in the same canvas item (same material, told apart by vertex COLOR.g: 1 = soma quad,
// 0 = process mesh, whose alpha is the coverage, COLOR.r a shade, UV.x the distance from the soma
// in model radii and UV.y the process phase; mesh_scale converts radii to pixels). The soma outline has a corner (a point) towards each process, see
// soma_profile(). Formula and constants must stay in sync with NeuronMorphology
// (scripts/views/neuron_morphology.gd), which the tests use to check the soma bounds.
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
// Soma shape (NeuronMorphology): size in model radii, corner amplitude and width, the angles of
// the processes the corners point to, and the nucleus offset in soma radii.
uniform float soma_radius = 0.6;
uniform float corner_amp = 0.28;
uniform float corner_width = 0.5;
uniform int corner_count = 0;
uniform float corners[8];
uniform vec2 nucleus = vec2(0.0);
uniform float shape_breath = 0.0;
// Process mesh (NeuronMorphology.build_mesh): model radii to pixels, opacity.
uniform float mesh_scale = 28.0;
uniform float arm_alpha = 0.92;
// 0..1 crossing latency glow, contact ring, overall brightness boost and overload.
uniform float crossing = 0.0;
uniform float contact = 0.0;
uniform float brightness = 1.0;
uniform float overload = 0.0;
// Toxic neuron (T8.2): a pulsing warning halo (and a ring when contaminating), 0..1.
uniform vec4 warn_color : source_color = vec4(1.0, 0.84, 0.1, 1.0);
uniform float warn = 0.0;
uniform float warn_speed = 2.4;

// Must stay in sync with NeuronMorphology (SOMA_BASE, CORNER_CAP, SOMA_BREATH, SOMA_BREATH_SPEED).
const float SOMA_BASE = 0.86;
const float CORNER_CAP = 1.2;
const float SOMA_BREATH = 0.025;
const float SOMA_BREATH_SPEED = 1.1;

// Process sway amplitude in model radii; keep in sync with NeuronMorphology.SWAY.
const float SWAY = 0.045;

void vertex() {
	if (COLOR.g < 0.5) {
		float t = TIME * motion;
		float reach = UV.x;
		vec2 sway = vec2(sin(t * 0.8 + UV.y), cos(t * 0.65 + UV.y * 1.3)) * SWAY * reach * reach;
		vec2 tremble = vec2(sin(TIME * 93.0 + UV.y), cos(TIME * 71.0)) * overload * 0.14 * motion;
		VERTEX = (VERTEX + sway + tremble) * mesh_scale;
	}
}

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

// Soma outline factor at angle a: a rounded body with a corner towards each process.
float soma_profile(float a) {
	float s = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= corner_count) {
			break;
		}
		float dd = atan(sin(a - corners[i]), cos(a - corners[i]));
		s += exp(-dd * dd / corner_width);
	}
	return SOMA_BASE + corner_amp * min(s, CORNER_CAP);
}

float soma_outline(float a, float t) {
	return radius_px * soma_radius * (1.0 + SOMA_BREATH * sin(t * SOMA_BREATH_SPEED + shape_breath)) * soma_profile(a);
}

void fragment() {
	if (COLOR.g < 0.5) {
		// Dendrites and axon: a dimmer tint of the soma color, feathered by the vertex alpha.
		float ov = clamp(overload, 0.0, 1.0);
		vec3 arm_rgb = mix(core_color.rgb * (0.72 + 0.28 * COLOR.r), overload_color.rgb * 1.3, ov * 0.7);
		float arm_a = COLOR.a * arm_alpha * core_color.a;
		COLOR = vec4(arm_rgb * brightness * arm_a, arm_a);
	} else {
	vec2 p = (UV - vec2(0.5)) * 2.0 * half_size_px;
	float t = TIME * motion;
	// Overload tremble: the whole soma jitters (only with motion).
	p += vec2(sin(TIME * 93.0 + phase), cos(TIME * 71.0)) * overload * 4.0 * motion;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float pulse = 1.0 + pulse_depth * sin(t * pulse_speed + phase);

	// Compact angular soma that breathes a little.
	float r = soma_outline(ang, t);
	float core = 1.0 - smoothstep(r - 1.2, r + 1.2, d);

	// Soma shading: a dimmer body with a brighter rim, and a visible nucleus (disc, darker rim,
	// bright nucleolus).
	float rn = clamp(d / max(r, 0.001), 0.0, 1.0);
	vec2 nq = (p - nucleus * r) / (r * 0.48);
	float nd = length(nq);
	float nuc = 1.0 - smoothstep(0.82, 1.0, nd);
	float nuc_rim = exp(-pow((nd - 0.97) / 0.12, 2.0));
	float shade = mix(0.72, 0.96, smoothstep(0.4, 1.0, rn)) + 0.3 * nuc - 0.16 * nuc_rim
		+ 0.18 * exp(-nd * nd * 28.0);
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
		float sr = soma_outline(sa, t) + 6.0 + 14.0 * hash(slot * 2.71 + seed);
		vec2 sp = vec2(cos(sa), sin(sa)) * sr;
		float sd2 = dot(p - sp, p - sp);
		sparks = on * life * (exp(-sd2 / 1.8) + 0.25 * exp(-sd2 / 20.0)) * sparkle * c;
	}
	float contact_ring = exp(-pow((d - radius_px - 10.0) / 2.5, 2.0)) * contact;

	// Toxic warning: a halo pulsing faster when contaminating (steady mid level without motion).
	float w = clamp(warn, 0.0, 1.0);
	float warn_beat = mix(0.6, 0.5 + 0.5 * sin(TIME * warn_speed * (1.0 + 1.6 * w) + phase), motion);
	float warn_halo = exp(-outside * 0.9) * w * (0.3 + 0.7 * warn_beat) * 0.75;
	warn_halo *= 1.0 - smoothstep(half_size_px * 0.72, half_size_px, d);
	float warn_ring = exp(-pow((d - radius_px - 9.0) / 2.2, 2.0)) * smoothstep(0.5, 1.0, w) * (0.35 + 0.65 * warn_beat);

	vec3 halo_rgb = mix(glow_color.rgb, overload_color.rgb, o);
	vec3 rgb = soma * core + (halo_rgb * halo + latency_color.rgb * latency
		+ vec3(1.0, 0.88, 0.74) * sparks + vec3(contact_ring * 0.8)
		+ warn_color.rgb * (warn_halo + warn_ring)) * (1.0 - core);
	COLOR = vec4(rgb * brightness, core * core_color.a);
	}
}
