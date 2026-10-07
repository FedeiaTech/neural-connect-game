class_name Campaign
extends Resource
## The whole campaign (SDD 7.1): chapters in order, each with its missions in order.
## Campaign order = chapter order, then mission order inside the chapter. Read-only at runtime.

@export var chapters: Array[ChapterData] = []


## Every mission id in campaign order.
func get_mission_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for level in _levels():
		ids.append(level.mission_id)
	return ids


## LevelData of the mission, or null if it is not in the campaign.
func get_level(mission_id: StringName) -> LevelData:
	for level in _levels():
		if level.mission_id == mission_id:
			return level
	return null


## 1-based position in campaign order (the number shown to the player), 0 if unknown.
func get_mission_number(mission_id: StringName) -> int:
	return get_mission_ids().find(mission_id) + 1


func get_chapter_of(mission_id: StringName) -> ChapterData:
	for chapter in chapters:
		if chapter == null:
			continue
		for level in chapter.missions:
			if level != null and level.mission_id == mission_id:
				return chapter
	return null


func first_mission_id() -> StringName:
	var ids := get_mission_ids()
	return ids[0] if not ids.is_empty() else &""


## Next mission in campaign order (crossing chapter borders), or &"" after the last / if unknown.
func next_mission_after(mission_id: StringName) -> StringName:
	var ids := get_mission_ids()
	var index := ids.find(mission_id)
	if index < 0 or index + 1 >= ids.size():
		return &""
	return ids[index + 1]


## Previous mission in campaign order, or &"" for the first / unknown mission.
func previous_mission_before(mission_id: StringName) -> StringName:
	var ids := get_mission_ids()
	var index := ids.find(mission_id)
	if index <= 0:
		return &""
	return ids[index - 1]


func _levels() -> Array[LevelData]:
	var result: Array[LevelData] = []
	for chapter in chapters:
		if chapter == null:
			continue
		for level in chapter.missions:
			if level != null:
				result.append(level)
	return result
