// Glowing dendrite (SDD 5.4): thin bright core, soft wide glow and a faint electrical pulse
// travelling from end A to end B. Drawn by DendriteView on a strip whose UV.x runs along the
// dendrite (0 at A, 1 at B) and UV.y across it. Premultiplied alpha: the core is opaque, the
// glow only adds light. Every animated term is multiplied by `motion`.
// Crossing (T7.1): the line eases from `line_color` to `cross_color` by `crossing` (red for a
// normal dendrite, its own green for a tension one) and stays a plain solid line with its
// normal glow.
shader_type canvas_item;
render_mode blend_premul_alpha, unshaded;

uniform vec4 line_color : source_color = vec4(1.0);
uniform vec4 cross_color : source_color = vec4(1.0);
uniform float length_px = 100.0;
uniform float core_width_px = 3.0;
uniform float half_width_px = 16.0;
uniform float glow_strength = 0.35;
uniform float motion = 1.0;
uniform float phase = 0.0;
uniform float pulse_interval = 4.5;
uniform float pulse_speed_px = 380.0;
uniform float pulse_strength = 0.7;
// 0..1 crossing color blend.
uniform float crossing = 0.0;
// Tension warning: sideways tremble (px, along `normal`) and brightness flicker depth.
uniform float tremble_px = 0.0;
uniform vec2 normal = vec2(0.0, 1.0);
uniform float flicker = 0.0;
// Diseased dendrite (T8.3): 0..1 share of short dark gaps cutting the core (cracks).
uniform float crack = 0.0;
uniform float brightness = 1.0;
// Completion wave: light front position along UV.x and its strength.
uniform float wave_pos = -1.0;
uniform float wave_strength = 0.0;

float hash(float n) {
	return fract(sin(n) * 43758.5453);
}

void vertex() {
	// Bow the strip sideways; the ends stay attached to their neurons.
	float bow = sin(PI * UV.x);
	float shake = 0.6 * sin(TIME * 47.0 + UV.x * 9.0 + phase) + 0.4 * sin(TIME * 31.0 - UV.x * 5.0);
	VERTEX += normal * tremble_px * motion * bow * shake;
}

void fragment() {
	float t = TIME * motion;
	float x = UV.x * length_px;
	float d = abs(UV.y - 0.5) * 2.0 * half_width_px;
	float hw = core_width_px * 0.5;
	// Smooth edge: feather the core over about one screen pixel (fwidth of the px distance),
	// with a small floor so very thin tension lines still read as a soft line, never jagged.
	float aa = max(fwidth(d), 0.001) * 0.75 + 0.3;
	float core = 1.0 - smoothstep(hw - aa, hw + aa, d);
	if (crack > 0.001) {
		// Cracks: cells along the line randomly lose their core, more of them as `crack` grows.
		float cell_x = x / 16.0;
		float cell = floor(cell_x);
		float flick = floor(TIME * 5.0 * motion);
		float cut = step(1.0 - crack * 0.55, hash(cell * 3.17 + phase * 7.0 + flick * 0.37));
		core *= 1.0 - 0.9 * cut * smoothstep(0.1, 0.3, fract(cell_x)) * (1.0 - smoothstep(0.45, 0.65, fract(cell_x)));
	}
	float sigma = hw * 2.0 + 3.0;
	float glow = exp(-(d * d) / (2.0 * sigma * sigma));

	float cycle = max(pulse_interval, length_px / pulse_speed_px + 0.5);
	float head = mod(t + phase, cycle) * pulse_speed_px;
	float pulse = exp(-pow((x - head) / 28.0, 2.0)) * pulse_strength * motion;

	// Crossing: a plain color blend, no pattern.
	float c = clamp(crossing, 0.0, 1.0);

	float warn = 1.0 - flicker * motion * step(0.45, hash(floor(TIME * 18.0) + phase));
	float wave = wave_strength * exp(-pow((UV.x - wave_pos) * length_px / 70.0, 2.0));

	vec3 base = mix(line_color.rgb, cross_color.rgb, c);
	float lum_core = (1.0 + pulse * 0.8 + wave * 1.5) * warn * brightness;
	float lum_glow = (glow_strength + pulse * 0.6 + wave * 1.2) * warn * brightness;
	// Fade the glow near the ends so the strip never shows square caps.
	float end_fade = smoothstep(0.0, 12.0, x) * smoothstep(0.0, 12.0, length_px - x);
	vec3 rgb = base * (core * lum_core + glow * lum_glow * (1.0 - core) * end_fade);
	COLOR = vec4(rgb, core * line_color.a);
}
