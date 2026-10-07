// Soft iris transition (SDD 5.5: fade/pulse, never a hard cut). Drawn on Transition's full-screen
// ColorRect; its color alpha (COLOR.a) is the progress: 0 = fully transparent, 1 = fully covered.
// Covering closes from the screen edges towards the center with a faint cold rim of light at the
// iris edge; revealing opens from the center. Progress 0 and 1 are exact, so the logic and tests
// that read the alpha are unaffected. Reduced motion jumps straight to 0 or 1 (Transition).
shader_type canvas_item;

uniform vec4 rim_color : source_color = vec4(0.55, 0.8, 1.0, 1.0);
// How much later the center covers than the corners (0 = flat fade).
uniform float softness = 0.65;
uniform float aspect = 1.7777778;

void fragment() {
	float p = COLOR.a;
	vec2 q = (UV - vec2(0.5)) * vec2(aspect, 1.0);
	float d = clamp(length(q) / length(vec2(aspect * 0.5, 0.5)), 0.0, 1.0);
	float a = clamp(p * (1.0 + softness) - (1.0 - d) * softness, 0.0, 1.0);
	float cover = a * a * (3.0 - 2.0 * a);
	float rim = 4.0 * a * (1.0 - a);
	COLOR = vec4(rim_color.rgb * rim * 0.3, cover);
}
