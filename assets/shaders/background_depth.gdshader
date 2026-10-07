// Background base for BackgroundView (SDD 5.4): pure black with a barely visible cool lift in
// the middle so the void has some depth. Kept very dark so contrast stays maximal. A tiny
// screen-space dither hides 8-bit banding in the dark gradient.
shader_type canvas_item;

uniform vec4 center_color : source_color = vec4(0.03, 0.035, 0.045, 1.0);
uniform vec4 edge_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float d = clamp(length(UV - vec2(0.5)) * 1.41421356, 0.0, 1.0);
	vec3 rgb = mix(center_color.rgb, edge_color.rgb, smoothstep(0.0, 0.9, d));
	rgb += (hash(FRAGCOORD.xy) - 0.5) / 255.0;
	COLOR = vec4(max(rgb, vec3(0.0)), 1.0);
}
