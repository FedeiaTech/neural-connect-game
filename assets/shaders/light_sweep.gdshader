// Light wave across the level summary (SDD 5.5): a soft diagonal band of cold light that runs
// once from left to right over the completion overlay. `progress` goes from about -0.3 to 1.3;
// outside [0, 1] nothing is visible. Additive, so it only brightens.
shader_type canvas_item;
render_mode blend_add, unshaded;

uniform float progress = -1.0;
uniform vec4 band_color : source_color = vec4(0.6, 0.82, 1.0, 1.0);
uniform float width = 0.12;
uniform float strength = 0.16;
uniform float slant = 0.18;

void fragment() {
	float x = UV.x + (UV.y - 0.5) * slant;
	float band = exp(-pow((x - progress) / width, 2.0));
	float core = exp(-pow((x - progress) / (width * 0.18), 2.0));
	COLOR = vec4(band_color.rgb * (band * strength + core * strength * 0.8), 1.0);
}
