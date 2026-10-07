// Neuron soma with soft glow halo (SDD 5.4). Drawn on one quad per neuron by NeuronView.
// Premultiplied alpha: the soma is opaque (alpha = coverage) and covers dendrite ends, while
// the halo only adds light (alpha 0), which reads as additive bloom on the black background.
// Every animated term is multiplied by `motion` (0 when reduced motion is on).
// Crossing (T7.1): the soma keeps its own color; a dashed, crackling amber ring (ring_color)
// turns around it, which can never be mistaken for a red fixed neuron.
// Overload (T7.2): before a lethal-wall explosion the soma trembles and burns violet-white.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform vec4 core_color : source_color = vec4(1.0);
uniform vec4 glow_color : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform vec4 ring_color : source_color = vec4(1.0, 0.82, 0.32, 1.0);
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
// 0..1 crossing ring, contact ring, overall brightness boost and overload.
uniform float crossing = 0.0;
uniform float contact = 0.0;
uniform float brightness = 1.0;
uniform float overload = 0.0;

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

	// Crossing ring: eight dashes turning around the soma with a stepped crackle.
	float dashes = smoothstep(0.35, 0.55, fract(ang / TAU * 8.0 + t * 0.35));
	float crackle = 0.55 + 0.45 * step(0.3, hash(floor(t * 20.0) + phase));
	float ring = exp(-pow((d - r - 7.0) / 2.6, 2.0)) * c * dashes * crackle * 1.6;
	float ring_glow = exp(-pow((d - r - 7.0) / 9.0, 2.0)) * c * 0.25 * crackle;
	float contact_ring = exp(-pow((d - r - 10.0) / 2.5, 2.0)) * contact;

	vec3 halo_rgb = mix(glow_color.rgb, overload_color.rgb, o);
	vec3 rgb = soma * core + (halo_rgb * halo + ring_color.rgb * (ring + ring_glow)
		+ vec3(contact_ring * 0.8)) * (1.0 - core);
	COLOR = vec4(rgb * brightness, core * core_color.a);
}
