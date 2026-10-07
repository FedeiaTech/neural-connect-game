class_name SaveFile
extends RefCounted
## JSON file helpers for the local save (SDD 8.4). Reading never fails loudly: a missing,
## unreadable or corrupt file yields an empty Dictionary. Writing goes through a temp file that
## is verified (fully written, non-empty, parses back into a Dictionary) and only then renamed
## over the real save, so a failed or interrupted write never replaces a good save.
## backup() moves an unusable save aside so it is never silently overwritten.

const TEMP_SUFFIX := ".tmp"
const BACKUP_SUFFIX := ".bak"


## Parsed top-level Dictionary, or {} when the file is missing, unreadable or not a JSON object.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("SaveFile: '%s' is empty or unreadable." % path)
		return {}
	var parsed: Variant = _parse_object(text)
	if parsed == null:
		push_warning("SaveFile: '%s' is corrupt." % path)
		return {}
	return parsed


static func write_json(path: String, data: Dictionary) -> Error:
	return write_json_text(path, JSON.stringify(data, "\t"))


## Writes already serialized JSON. The text must parse back into a Dictionary, otherwise the
## previous save is kept and an error is returned.
static func write_json_text(path: String, text: String) -> Error:
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		push_error("SaveFile: cannot create '%s' (%s)." % [path.get_base_dir(), error_string(dir_error)])
		return dir_error
	var temp_path := path + TEMP_SUFFIX
	var write_error := _write_temp(temp_path, text)
	if write_error == OK:
		write_error = _verify_temp(temp_path)
	if write_error != OK:
		push_error("SaveFile: write of '%s' failed (%s); previous save kept." \
			% [path, error_string(write_error)])
		if FileAccess.file_exists(temp_path):
			DirAccess.remove_absolute(temp_path)
		return write_error
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		push_error("SaveFile: cannot replace '%s' (%s)." % [path, error_string(rename_error)])
	return rename_error


## Moves the file at path to path + ".bak" (or a numbered .bak when one already exists) and
## returns the backup path. Returns "" when there is nothing to back up or the move failed.
static func backup(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var backup_path := path + BACKUP_SUFFIX
	var index := 1
	while FileAccess.file_exists(backup_path):
		backup_path = "%s.%d%s" % [path, index, BACKUP_SUFFIX]
		index += 1
	var error := DirAccess.rename_absolute(path, backup_path)
	if error != OK:
		push_error("SaveFile: cannot back up '%s' (%s)." % [path, error_string(error)])
		return ""
	push_warning("SaveFile: unusable save moved to '%s'." % backup_path)
	return backup_path


static func _write_temp(temp_path: String, text: String) -> Error:
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	var stored := file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if not stored:
		return ERR_FILE_CANT_WRITE
	return error


## The temp file must be non-empty and parse back into a Dictionary.
static func _verify_temp(temp_path: String) -> Error:
	var text := FileAccess.get_file_as_string(temp_path)
	if text.is_empty():
		return ERR_FILE_CANT_WRITE
	return OK if _parse_object(text) != null else ERR_FILE_CORRUPT


## The parsed Dictionary, or null when text is not a JSON object.
static func _parse_object(text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return null
	return json.data
