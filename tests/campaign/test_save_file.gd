extends GdUnitTestSuite
## T3.3: SaveFile never replaces a good save with a bad write and keeps unreadable saves aside.

const TEMP_PATH := "user://test_save_file.json"


func before_test() -> void:
	_cleanup()


func after_test() -> void:
	_cleanup()


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(TEMP_PATH + ".tmp"):
		DirAccess.remove_absolute(TEMP_PATH + ".tmp")
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with(TEMP_PATH.get_file()):
			dir.remove(file)


func _write_raw(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func test_write_json_round_trips_and_leaves_no_temp_file() -> void:
	assert_int(SaveFile.write_json(TEMP_PATH, {"version": 1, "a": "b"})).is_equal(OK)
	assert_dict(SaveFile.read_json(TEMP_PATH)).is_equal({"version": 1.0, "a": "b"})
	assert_bool(FileAccess.file_exists(TEMP_PATH + ".tmp")).is_false()


func test_unverifiable_write_keeps_the_previous_save() -> void:
	SaveFile.write_json(TEMP_PATH, {"version": 1, "keep": true})
	# The written text does not parse back into a Dictionary: the rename must not happen.
	for text in ["", "{ broken", "[1, 2]"]:
		var error := SaveFile.write_json_text(TEMP_PATH, text)
		assert_int(error).override_failure_message(text).is_not_equal(OK)
		assert_dict(SaveFile.read_json(TEMP_PATH)).is_equal({"version": 1.0, "keep": true})
		assert_bool(FileAccess.file_exists(TEMP_PATH + ".tmp")).is_false()


func test_failed_temp_open_keeps_the_previous_save() -> void:
	SaveFile.write_json(TEMP_PATH, {"version": 1, "keep": true})
	# A directory where the temp file should go makes the open fail.
	DirAccess.make_dir_absolute(TEMP_PATH + ".tmp")
	assert_int(SaveFile.write_json(TEMP_PATH, {"version": 1, "keep": false})).is_not_equal(OK)
	assert_dict(SaveFile.read_json(TEMP_PATH)).is_equal({"version": 1.0, "keep": true})


func test_backup_moves_the_file_aside_without_overwriting_older_backups() -> void:
	_write_raw(TEMP_PATH, "first bad")
	var first := SaveFile.backup(TEMP_PATH)
	assert_str(first).is_equal(TEMP_PATH + ".bak")
	assert_bool(FileAccess.file_exists(TEMP_PATH)).is_false()
	assert_str(FileAccess.get_file_as_string(first)).is_equal("first bad")
	_write_raw(TEMP_PATH, "second bad")
	var second := SaveFile.backup(TEMP_PATH)
	assert_str(second).is_not_equal(first)
	assert_str(FileAccess.get_file_as_string(first)).is_equal("first bad")
	assert_str(FileAccess.get_file_as_string(second)).is_equal("second bad")


func test_backup_of_a_missing_file_does_nothing() -> void:
	assert_str(SaveFile.backup(TEMP_PATH)).is_empty()
