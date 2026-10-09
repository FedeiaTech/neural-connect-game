// Neuron soma with soft glow halo (SDD 5.4). Drawn on one quad per neuron by NeuronView.
// Premultiplied alpha: the soma is opaque (alpha = coverage) and covers dendrite ends, while
// the halo only adds light (alpha 0), which reads as additive bloom on the black background.
// Every animated term is multiplied by `motion` (0 when reduced motion is on).
// Crossing (T7.1): the soma keeps its own color; a soft warm "latency" glow (latency_color)
// breathes slowly in the halo, with a few small sparks twinkling around the soma (`sparkle`,
// 0 with reduced motion, when the glow is static).
// Overload (T7.2): before a lethal-wall explosion the soma trembles and burns violet-white.
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
uniform float wobble = 0.045;
uniform float stub_count = 5.0;
uniform float stub_length = 0.3;
// 0..1 crossing latency glow, contact ring, overall brightness boost and overload.
uniform float crossing = 0.0;
uniform float contact = 0.0;
uniform float brightness = 1.0;
uniform float overload = 0.0;
// Toxic neuron (T8.2): a pulsing warning halo (and a ring when contaminating), 0..1.
uniform vec4 warn_color : source_color = vec4(1.0, 0.84, 0.1, 1.0);
uniform float warn = 0.0;
uniform float warn_speed = 2.4;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * half_size_px;
	float t = TIME * motion;
	// Overload tremble: the whole soma jitters (only with motion).
	p += vec2(sin(TIME * 93.0 + phase), cos(TIME * 71.0)) * overload * 4.0 * motion;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float pulse = 1.0 + pulse_depth * sin(t * pulse_speed + phase);

	// Organic outline: slow membrane wobble plus a few short dendrite stubs.
	float membrane = wobble * (0.5 * sin(3.0 * ang + t * 0.9 + phase)
		+ 0.3 * sin(5.0 * ang - t * 1.3 + phase * 2.1)
		+ 0.2 * sin(8.0 * ang + t * 0.7 + phase * 0.5));
	float stubs = pow(max(cos(stub_count * (ang - phase)), 0.0), 14.0);
	float r = radius_px * (1.0 + membrane + stub_length * stubs * (0.85 + 0.15 * sin(t * 1.1 + phase)));
	float core = 1.0 - smoothstep(r - 1.2, r + 1.2, d);

	// Soma shading: slightly dimmer body, brighter rim and a soft nucleus.
	float rn = clamp(d / max(r, 0.001), 0.0, 1.0);
	float shade = mix(0.8, 1.0, smoothstep(0.45, 1.0, rn)) + 0.22 * exp(-rn * rn * 14.0);
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
		float sr = r + 6.0 + 14.0 * hash(slot * 2.71 + seed);
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

	vec3 halo_rgb = mix(glow_color.rgb, overload_color.rgb, o);
	vec3 rgb = soma * core + (halo_rgb * halo + latency_color.rgb * latency
		+ vec3(1.0, 0.88, 0.74) * sparks + vec3(contact_ring * 0.8)
		+ warn_color.rgb * (warn_halo + warn_ring)) * (1.0 - core);
	COLOR = vec4(rgb * brightness, core * core_color.a);
}
