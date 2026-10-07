// Neuron soma with soft glow halo (SDD 5.4). Drawn on one quad per neuron by NeuronView.
// Premultiplied alpha: the soma is opaque (alpha = coverage) and covers dendrite ends, while
// the halo only adds light (alpha 0), which reads as additive bloom on the black background.
// Every animated term is multiplied by `motion` (0 when reduced motion is on).
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform vec4 core_color : source_color = vec4(1.0);
uniform vec4 glow_color : source_color = vec4(0.78, 0.9, 1.0, 1.0);
uniform vec4 warm_color : source_color = vec4(1.0, 0.5, 0.38, 1.0);
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
// 0..1 crossing warmth (warm flicker), contact ring and overall brightness boost.
uniform float warm = 0.0;
uniform float contact = 0.0;
uniform float brightness = 1.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0 * half_size_px;
	float d = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME * motion;
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
	float flick = 0.65 + 0.35 * sin(t * 9.0 + phase) * sin(t * 15.3 + phase * 1.7);
	float w = clamp(warm, 0.0, 1.0) * flick;
	vec3 soma = mix(core_color.rgb * shade, warm_color.rgb, w * 0.35) * (0.94 + 0.06 * pulse);

	// Halo falls off with distance from the outline, breathing with the pulse.
	float outside = max(d - r, 0.0) / (radius_px * 0.8);
	float halo = exp(-outside * 1.6) * glow_strength * pulse * (1.0 + w * 0.9);
	halo *= 1.0 - smoothstep(half_size_px * 0.72, half_size_px, d);
	float ring = exp(-pow((d - r - 6.0) / 3.0, 2.0)) * w;
	float contact_ring = exp(-pow((d - r - 10.0) / 2.5, 2.0)) * contact;
	vec3 glow_rgb = mix(glow_color.rgb, warm_color.rgb, clamp(warm, 0.0, 1.0));

	vec3 rgb = soma * core + (glow_rgb * (halo + ring) + vec3(contact_ring * 0.8)) * (1.0 - core);
	COLOR = vec4(rgb * brightness, core * core_color.a);
}
