class_name SaveFile
extends RefCounted
## JSON file helpers for the local save (SDD 8.4). Reading never fails loudly: a missing,
## unreadable or corrupt file yields an empty Dictionary. Writing goes through a temp file
## that is then renamed, so a crash mid-write cannot leave a half-written save.


## Parsed top-level Dictionary, or {} when the file is missing, unreadable or not a JSON object.
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_warning("SaveFile: '%s' is empty or unreadable, starting fresh." % path)
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		push_warning("SaveFile: '%s' is corrupt, starting fresh." % path)
		return {}
	return json.data


static func write_json(path: String, data: Dictionary) -> Error:
	var dir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if dir_error != OK:
		push_error("SaveFile: cannot create '%s' (%s)." % [path.get_base_dir(), error_string(dir_error)])
		return dir_error
	var temp_path := path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		var open_error := FileAccess.get_open_error()
		push_error("SaveFile: cannot write '%s' (%s)." % [temp_path, error_string(open_error)])
		return open_error
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var rename_error := DirAccess.rename_absolute(temp_path, path)
	if rename_error != OK:
		push_error("SaveFile: cannot replace '%s' (%s)." % [path, error_string(rename_error)])
	return rename_error
