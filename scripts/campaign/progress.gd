class_name Progress
extends RefCounted
## Player progress (SDD 6, 7.1, 8.4): per mission the completed flag and personal bests.
## Plain data, serialized to a Dictionary for the JSON save (GameState owns the file).
## Best stars, best moves and best time are kept independently: each one only improves.

const NO_MOVES := -1
const NO_TIME := -1.0
const MIN_STARS := 1
const MAX_STARS := 3

## mission_id -> {"completed": bool, "stars": int, "moves": int, "time": float}
var _missions: Dictionary[StringName, Dictionary] = {}


## Stores a completed run, keeping the best value of each stat.
func record(mission_id: StringName, stars: int, moves: int, time: float) -> void:
	stars = clampi(stars, MIN_STARS, MAX_STARS)
	var entry: Dictionary = _missions.get(mission_id, {})
	if entry.get("completed", false):
		entry["stars"] = maxi(entry["stars"], stars)
		entry["moves"] = mini(entry["moves"], moves)
		entry["time"] = minf(entry["time"], time)
	else:
		entry = {"completed": true, "stars": stars, "moves": moves, "time": time}
	_missions[mission_id] = entry


func is_completed(mission_id: StringName) -> bool:
	return _missions.get(mission_id, {}).get("completed", false)


func get_best_stars(mission_id: StringName) -> int:
	return _missions.get(mission_id, {}).get("stars", 0)


func get_best_moves(mission_id: StringName) -> int:
	return _missions.get(mission_id, {}).get("moves", NO_MOVES)


func get_best_time(mission_id: StringName) -> float:
	return _missions.get(mission_id, {}).get("time", NO_TIME)


func get_completed_count() -> int:
	var count := 0
	for id in _missions:
		if is_completed(id):
			count += 1
	return count


func to_dict() -> Dictionary:
	var missions := {}
	for id in _missions:
		missions[String(id)] = _missions[id].duplicate()
	return {"missions": missions}


## Builds progress from saved data. Anything malformed is skipped, never fatal.
static func from_dict(data: Variant) -> Progress:
	var progress := Progress.new()
	if not data is Dictionary:
		return progress
	var missions: Variant = (data as Dictionary).get("missions")
	if not missions is Dictionary:
		return progress
	for key: Variant in missions:
		var entry: Variant = missions[key]
		if not key is String or not entry is Dictionary:
			continue
		var completed: Variant = entry.get("completed")
		var stars: Variant = entry.get("stars")
		var moves: Variant = entry.get("moves")
		var time: Variant = entry.get("time")
		if not (completed is bool and completed) or not _is_number(stars) or not _is_number(moves) \
				or not _is_number(time):
			continue
		progress.record(StringName(key), int(stars), int(moves), float(time))
	return progress


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
