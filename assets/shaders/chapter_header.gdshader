// Procedural chapter illustration (SDD 5.5: each chapter has its own seed/pattern, no images).
// A slowly drifting field of cells: glowing membranes between Voronoi cells and a faint nucleus in
// each, tinted with the chapter accent from the palette, quiet behind the title on the left and
// fading out towards the right and the top/bottom edges. Additive over the black background.
// `seed` changes the cell layout and scale, `motion` (0 with reduced motion) freezes the drift.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float seed = 1.0;
uniform float motion = 1.0;
uniform vec4 accent : source_color = vec4(0.75, 0.88, 1.0, 1.0);
uniform vec2 rect_size = vec2(1600.0, 150.0);
uniform float strength = 1.0;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p + seed * 17.13) * 43758.5453);
}

void fragment() {
	vec2 px = UV * rect_size;
	float t = TIME * motion;
	float scale = 58.0 + mod(seed * 7.0, 3.0) * 14.0;
	vec2 p = (px + vec2(seed * 131.0, seed * 57.0)) / scale;
	vec2 cell = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = hash2(cell + g);
			o = 0.5 + 0.36 * sin(t * 0.3 + 6.2831 * o);
			float d = length(g + o - f);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	float membrane = 1.0 - smoothstep(0.0, 0.09, d2 - d1);
	float nucleus = exp(-d1 * d1 * 38.0);
	float breathe = 0.85 + 0.15 * sin(t * 0.8 + seed);
	// Quiet behind the title (left), fullest in the middle, fading out at the right edge.
	float fade_x = mix(0.3, 1.0, smoothstep(0.2, 0.6, UV.x)) * mix(1.0, 0.25, smoothstep(0.7, 1.0, UV.x));
	float fade_y = smoothstep(0.0, 0.3, UV.y) * smoothstep(0.0, 0.3, 1.0 - UV.y);
	float glow = (membrane * 0.22 + nucleus * 0.2 * breathe) * fade_x * fade_y * strength;
	// A thin bright line along the bottom anchors the header to the map below.
	float line = exp(-pow((1.0 - UV.y) * rect_size.y - 2.0, 2.0) * 0.5) * 0.35 * fade_x;
	COLOR = vec4(accent.rgb * (glow + line), 1.0);
}
