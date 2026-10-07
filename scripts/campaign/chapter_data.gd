class_name ChapterData
extends Resource
## One chapter of the campaign (SDD 7.1): a themed, ordered set of missions.

@export var chapter_id: int = 0
@export var title: String = ""
## Short line shown under the title in mission select.
@export var subtitle: String = ""
## Missions in play order.
@export var missions: Array[LevelData] = []
