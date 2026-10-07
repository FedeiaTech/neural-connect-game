extends GdUnitTestSuite
## Line smoothing: every line, arc and circle the views draw is antialiased (including the wide
## glow passes), and the dendrite shader feathers its core with fwidth-based AA.

const VIEWS_DIR := "res://scripts/views/"
const DRAW_CALLS := ["draw_line(", "draw_polyline(", "draw_polyline_colors(", "draw_arc(", "draw_circle(",
	"draw_multiline(", "draw_multiline_colors("]


func test_every_view_draw_call_is_antialiased() -> void:
	var offenders: Array[String] = []
	for file in DirAccess.get_files_at(VIEWS_DIR):
		if not file.ends_with(".gd"):
			continue
		var source := FileAccess.get_file_as_string(VIEWS_DIR + file)
		for call in _draw_calls(source):
			if not call.replace(" ", "").ends_with(",true)"):
				offenders.append("%s: %s" % [file, call])
	assert_array(offenders).is_empty()


func test_dendrite_core_uses_fwidth_antialiasing() -> void:
	assert_bool(DendriteView.DendriteShader.code.contains("fwidth(")).is_true()


## Full text of every draw call in source (balanced parentheses, may span lines).
static func _draw_calls(source: String) -> Array[String]:
	var calls: Array[String] = []
	for name: String in DRAW_CALLS:
		var from := source.find(name)
		while from >= 0:
			# Skip longer names that contain this one (draw_polyline_colors vs draw_polyline).
			var before := source[from - 1] if from > 0 else " "
			if before == "_" or before.is_valid_identifier():
				from = source.find(name, from + 1)
				continue
			var depth := 0
			var i := from + name.length() - 1
			while i < source.length():
				if source[i] == "(":
					depth += 1
				elif source[i] == ")":
					depth -= 1
					if depth == 0:
						break
				i += 1
			calls.append(source.substr(from, i - from + 1).replace("\n", " ").replace("\t", ""))
			from = source.find(name, i)
	return calls
