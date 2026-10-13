extends GdUnitTestSuite
## T4.5: mission select as a network map — node layout, dendrites between consecutive missions,
## per-chapter procedural headers and the dendrite pulse played before a mission loads.

const Sandbox := preload("res://tests/flow/game_state_sandbox.gd")
const SignalRecorder := preload("res://tests/model/signal_recorder.gd")
const MissionSelectScene := preload("res://scenes/screens/mission_select.tscn")

var _sandbox: Sandbox
var _recorder: SignalRecorder


func before_test() -> void:
	_sandbox = Sandbox.new()
	_sandbox.enter()
	_recorder = SignalRecorder.new()


func after_test() -> void:
	_sandbox.exit()


func _select() -> MissionSelect:
	var select: MissionSelect = auto_free(MissionSelectScene.instantiate())
	add_child(select)
	return select


# --- Layout --------------------------------------------------------------------

func test_layout_spreads_missions_left_to_right_inside_the_map() -> void:
	var size := Vector2(1600, MissionMap.MAP_HEIGHT)
	var points := MissionMap.layout(5, size)
	assert_int(points.size()).is_equal(5)
	for i in points.size():
		assert_bool(Rect2(Vector2.ZERO, size).has_point(points[i])).is_true()
		if i > 0:
			assert_float(points[i].x).is_greater(points[i - 1].x)
			assert_float(points[i].x - points[i - 1].x).is_less_equal(MissionMap.MAX_SPACING + 0.001)


func test_layout_is_centered_and_handles_tiny_counts() -> void:
	var size := Vector2(1600, MissionMap.MAP_HEIGHT)
	assert_int(MissionMap.layout(0, size).size()).is_equal(0)
	assert_float(MissionMap.layout(1, size)[0].x).is_equal_approx(800.0, 0.001)
	var two := MissionMap.layout(2, size)
	assert_float((two[0].x + two[1].x) * 0.5).is_equal_approx(800.0, 0.001)


func test_layout_shrinks_spacing_on_narrow_maps() -> void:
	var size := Vector2(600, MissionMap.MAP_HEIGHT)
	var points := MissionMap.layout(6, size)
	assert_float(points[0].x).is_greater_equal(MissionMap.MARGIN - 0.001)
	assert_float(points[5].x).is_less_equal(600.0 - MissionMap.MARGIN + 0.001)


func test_segment_state_follows_mission_states() -> void:
	var L := MissionNode.State.LOCKED
	var U := MissionNode.State.UNLOCKED
	var C := MissionNode.State.COMPLETED
	assert_int(MissionMap.segment_state(C, C)).is_equal(MissionMap.Segment.LIT)
	assert_int(MissionMap.segment_state(C, U)).is_equal(MissionMap.Segment.OPEN)
	assert_int(MissionMap.segment_state(U, L)).is_equal(MissionMap.Segment.DIM)
	assert_int(MissionMap.segment_state(C, L)).is_equal(MissionMap.Segment.DIM)


# --- Mission select as a map -----------------------------------------------------

func test_each_chapter_has_a_procedural_header_and_a_map() -> void:
	var select := _select()
	var headers := select.get_chapter_headers()
	assert_int(headers.size()).is_equal(GameState.campaign.chapters.size())
	var header := headers[0]
	assert_str(header.get_title_text()).is_equal("Chapter 1: First Signals")
	var material := header.get_backdrop().material as ShaderMaterial
	assert_object(material).is_not_null()
	assert_float(float(material.get_shader_parameter(&"seed"))).is_not_equal(0.0)
	var map := select.get_map_for(&"m01")
	assert_object(map).is_instanceof(MissionMap)
	assert_object(select.get_mission_node(&"m01").get_parent()).is_same(map)


func test_low_memory_mode_draws_a_flat_chapter_header() -> void:
	GameState.low_memory_mode = true
	var header: ChapterHeader = auto_free(ChapterHeader.new())
	header.setup(1, "X", "Y")
	GameState.low_memory_mode = false
	assert_object(header.get_backdrop().material).is_null()
	assert_float(header.get_backdrop().color.a).is_less(1.0)


func test_chapter_headers_use_different_seeds() -> void:
	assert_float(ChapterHeader.seed_for(1)).is_not_equal(ChapterHeader.seed_for(2))


func test_selection_plays_a_pulse_before_loading() -> void:
	GameState.reduced_motion = false
	var select := _select()
	_recorder.watch(select, [&"mission_selected"])
	select.get_mission_node(&"m01").pressed.emit()
	assert_int(_recorder.count(&"mission_selected")).is_equal(0)
	assert_bool(select.get_map_for(&"m01").is_pulsing()).is_true()
	# A second press while the pulse runs is ignored.
	select.get_mission_node(&"m01").pressed.emit()
	await await_millis(int(MissionMap.PULSE_TIME * 1000.0) + 200)
	assert_int(_recorder.count(&"mission_selected")).is_equal(1)
	assert_array(_recorder.last_args(&"mission_selected")).is_equal([&"m01"])


func test_reduced_motion_loads_at_once() -> void:
	GameState.reduced_motion = true
	var select := _select()
	_recorder.watch(select, [&"mission_selected"])
	select.get_mission_node(&"m01").pressed.emit()
	assert_int(_recorder.count(&"mission_selected")).is_equal(1)
	assert_bool(select.get_map_for(&"m01").is_pulsing()).is_false()
