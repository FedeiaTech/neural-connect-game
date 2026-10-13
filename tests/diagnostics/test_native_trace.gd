extends GdUnitTestSuite
## NativeTrace: pulls the readable lines (libraries, functions, abort message) out of the binary
## tombstone Android keeps for a native crash.


func _bytes(parts: Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	for part in parts:
		if part is String:
			bytes.append_array(part.to_ascii_buffer())
		else:
			bytes.append_array(PackedByteArray(part))
	return bytes


func test_printable_runs_skip_binary_noise_and_short_runs() -> void:
	var bytes := _bytes([[0, 1, 2], "hello world", [0, 200, 7], "ab", [1], "libgodot_android.so", [255]])
	var runs := NativeTrace.printable_runs(bytes)
	assert_array(Array(runs)).is_equal(["hello world", "libgodot_android.so"])


func test_relevant_lines_keep_only_library_and_function_text() -> void:
	var bytes := _bytes([[10, 0], "unrelated words here", [0],
		"/vendor/lib64/egl/libGLES_mali.so", [0, 4],
		"RasterizerCanvasGLES3::_render_batch", [0],
		"Abort message: boom", [0], "some plain text"])
	var lines := NativeTrace.relevant_lines(bytes)
	assert_array(Array(lines)).contains_exactly([
		"/vendor/lib64/egl/libGLES_mali.so",
		"RasterizerCanvasGLES3::_render_batch",
		"Abort message: boom"])


func test_duplicates_are_dropped_and_order_is_kept() -> void:
	var bytes := _bytes(["libvulkan.so", [0], "libgodot.so", [0], "libvulkan.so"])
	assert_array(Array(NativeTrace.relevant_lines(bytes))).is_equal(["libvulkan.so", "libgodot.so"])


func test_the_result_is_capped() -> void:
	var parts: Array = []
	for i in 100:
		parts.append("/system/lib64/lib%03d.so" % i)
		parts.append([0])
	assert_int(NativeTrace.relevant_lines(_bytes(parts), 40).size()).is_equal(40)


func test_long_lines_are_truncated() -> void:
	var bytes := _bytes(["/" + "x".repeat(500)])
	assert_int(NativeTrace.relevant_lines(bytes)[0].length()).is_less_equal(NativeTrace.MAX_LINE_LENGTH)


func test_empty_input_gives_no_lines() -> void:
	assert_bool(NativeTrace.relevant_lines(PackedByteArray()).is_empty()).is_true()


func test_the_section_text_is_left_empty_without_lines() -> void:
	assert_str(NativeTrace.format_section(PackedStringArray(), "")).is_empty()
	assert_str(NativeTrace.format_section(PackedStringArray(["libfoo.so"]), "")).contains("libfoo.so")
	assert_str(NativeTrace.format_section(PackedStringArray(), "no tombstone")).contains("no tombstone")
