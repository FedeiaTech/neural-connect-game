// Soft full-screen vignette for BackgroundView (SDD 5.4): transparent in the middle,
// fading to `tint` towards the corners. Lives behind the playfield, so it only dims the
// background spores and never the gameplay.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 0.85);
uniform float inner = 0.35;
uniform float outer = 1.0;

void fragment() {
	// 0 at the center, 1 at the corners.
	float d = length(UV - vec2(0.5)) * 1.41421356;
	COLOR = vec4(tint.rgb, tint.a * smoothstep(inner, outer, d));
}
