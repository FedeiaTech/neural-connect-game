extends RefCounted
## Reads locale/translations.csv directly (not through the imported Translation resources), so
## tests can check that every key has every language and look up the source text of a key.

const PATH := "res://locale/translations.csv"


## {"header": PackedStringArray, "rows": {key: {locale: text}}, "duplicates": Array[String]}.
static func load_table() -> Dictionary:
	var result := {"header": PackedStringArray(), "rows": {}, "duplicates": []}
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		return result
	var header := file.get_csv_line()
	result["header"] = header
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 2 or line[0].strip_edges().is_empty():
			continue
		var row := {}
		for i in range(1, header.size()):
			row[header[i]] = line[i] if i < line.size() else ""
		if result["rows"].has(line[0]):
			result["duplicates"].append(line[0])
		result["rows"][line[0]] = row
	return result


## Text of key in locale ("" when missing).
static func text(table: Dictionary, key: String, locale: String) -> String:
	return table["rows"].get(key, {}).get(locale, "")
