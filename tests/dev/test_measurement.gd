extends GdUnitTestSuite
## T8.1: measurement mode (developer-only, off by default). CSV rows, first-move timing, active
## time (story and pause excluded) and attempt results.

const LevelScene := preload("res://scenes/level/level.tscn")
const LevelFactory := preload("res://tests/model/level_factory.gd")
const TEST_CSV := "user://test_measurements.csv"

var _level: Level
var _measurement: Measurement
var _saved_reduced_motion := false


func before_test() -> void:
	_remove_csv()
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = true
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)
	_measurement = _level.get_measurement()
	_measurement.csv_path = TEST_CSV


func after_test() -> void:
	_measurement.set_enabled(false)
	GameState.reduced_motion = _saved_reduced_motion
	get_tree().paused = false
	_remove_csv()


func _remove_csv() -> void:
	if FileAccess.file_exists(TEST_CSV):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_CSV))


func _rows() -> PackedStringArray:
	var file := FileAccess.open(TEST_CSV, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var lines := PackedStringArray()
	while not file.eof_reached():
		var line := file.get_line()
		if not line.is_empty():
			lines.append(line)
	return lines


## A story-less mission so the level is PLAYING right after load_level.
func _playing_level() -> LevelData:
	var data := LevelFactory.x_level()
	data.mission_id = &"t_measure"
	return data


func _drag(controller: LevelController, id: int, target: Vector2) -> void:
	var model := controller.get_model()
	model.grab(id)
	model.drag_to(target)
	model.release()


func test_is_off_by_default_and_writes_nothing() -> void:
	assert_bool(_measurement.enabled).is_false()
	_level.load_level(_playing_level())
	_drag(_level.get_controller(), 1, Vector2(500, 300))
	_level.get_controller().restart()
	assert_bool(FileAccess.file_exists(TEST_CSV)).is_false()


func test_is_requested_reads_the_user_argument() -> void:
	assert_bool(Measurement.is_requested(PackedStringArray(["--measure"]))).is_true()
	assert_bool(Measurement.is_requested(PackedStringArray(["m01", "x.png"]))).is_false()
	assert_bool(Measurement.is_requested(PackedStringArray())).is_false()


func test_format_row_columns_and_blank_first_move() -> void:
	var row := Measurement.format_row("2026-10-08T10:00:00Z", &"m05", "completed", 3.456, 41.2, 7, 2, 3)
	assert_str(row).is_equal("2026-10-08T10:00:00Z,m05,completed,3.46,41.20,7,2,3")
	var no_move := Measurement.format_row("t", &"m05", "abandoned", -1.0, 0.0, 0, 0, 0)
	assert_str(no_move).is_equal("t,m05,abandoned,,0.00,0,0,0")


func test_header_matches_the_row_columns() -> void:
	var header := Measurement.HEADER.split(",")
	var row := Measurement.format_row("t", &"m", "completed", 1.0, 2.0, 3, 0, 1).split(",")
	assert_int(header.size()).is_equal(row.size())
	assert_str(header[0]).is_equal("timestamp")
	assert_str(header[3]).is_equal("seconds_to_first_move")


func test_append_row_creates_the_header_once() -> void:
	assert_bool(Measurement.append_row(TEST_CSV, "a,b")).is_true()
	assert_bool(Measurement.append_row(TEST_CSV, "c,d")).is_true()
	var rows := _rows()
	assert_array(Array(rows)).is_equal([Measurement.HEADER, "a,b", "c,d"])


func test_append_row_survives_an_unwritable_path() -> void:
	assert_bool(Measurement.append_row("user://no_such_dir_xyz/never.csv", "a,b")).is_false()


func test_story_time_is_not_counted() -> void:
	var data := _playing_level()
	data.story_text = "STORY"
	_level.load_level(data)
	assert_int(_level.get_controller().get_state()).is_equal(LevelController.State.INTRO)
	_measurement.tick(5.0)
	assert_float(_measurement.get_active_seconds()).is_equal(0.0)
	_level.get_controller().start_playing()
	_measurement.tick(2.0)
	assert_float(_measurement.get_active_seconds()).is_equal(2.0)


func test_pause_stops_the_measurement_clock() -> void:
	_level.load_level(_playing_level())
	assert_bool(_measurement.can_process()).is_true()
	_level.pause()
	assert_bool(_measurement.can_process()).is_false()
	_level.resume()
	assert_bool(_measurement.can_process()).is_true()


func test_first_move_time_is_the_active_time_of_the_first_displacement() -> void:
	_level.load_level(_playing_level())
	_measurement.tick(3.0)
	assert_float(_measurement.get_first_move_seconds()).is_equal(-1.0)
	_drag(_level.get_controller(), 1, Vector2(500, 300))
	_measurement.tick(4.0)
	_drag(_level.get_controller(), 2, Vector2(500, 150))
	assert_float(_measurement.get_first_move_seconds()).is_equal(3.0)


func test_restart_logs_a_restarted_attempt() -> void:
	_measurement.set_enabled(true)
	_level.load_level(_playing_level())
	_measurement.tick(3.0)
	_drag(_level.get_controller(), 1, Vector2(500, 300))
	_measurement.tick(1.5)
	_level.get_controller().restart()
	var rows := _rows()
	assert_int(rows.size()).is_equal(2)
	var cells := rows[1].split(",")
	assert_str(cells[1]).is_equal("t_measure")
	assert_str(cells[2]).is_equal("restarted")
	assert_str(cells[3]).is_equal("3.00")
	assert_str(cells[4]).is_equal("4.50")
	assert_str(cells[5]).is_equal("1")
	assert_str(cells[6]).is_equal("0")
	# The next attempt knows one restart came before it.
	assert_int(_measurement.get_restarts_before()).is_equal(1)


func test_completion_logs_the_attempt() -> void:
	_measurement.set_enabled(true)
	_level.load_level(_playing_level())
	_measurement.tick(10.0)
	var controller := _level.get_controller()
	# Untangle the X: neuron 1 moves beside neuron 0.
	_drag(controller, 1, Vector2(100, 300))
	assert_int(controller.get_state()).is_equal(LevelController.State.COMPLETE)
	var rows := _rows()
	assert_int(rows.size()).is_equal(2)
	var cells := rows[1].split(",")
	assert_str(cells[2]).is_equal("completed")
	assert_int(int(cells[7])).is_greater_equal(1)


func test_leaving_the_level_logs_an_abandoned_attempt() -> void:
	_measurement.set_enabled(true)
	_level.load_level(_playing_level())
	_measurement.tick(2.0)
	_drag(_level.get_controller(), 1, Vector2(500, 300))
	remove_child(_level)
	var rows := _rows()
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[1].split(",")[2]).is_equal("abandoned")
	add_child(_level)


func test_an_untouched_attempt_is_not_logged_on_restart() -> void:
	_measurement.set_enabled(true)
	_level.load_level(_playing_level())
	_level.get_controller().restart()
	assert_bool(FileAccess.file_exists(TEST_CSV)).is_false()


func test_enabling_shows_the_hud_indicator() -> void:
	assert_bool(_level.get_hud().is_measure_indicator_visible()).is_false()
	_measurement.set_enabled(true)
	assert_bool(_level.get_hud().is_measure_indicator_visible()).is_true()
	_measurement.set_enabled(false)
	assert_bool(_level.get_hud().is_measure_indicator_visible()).is_false()
