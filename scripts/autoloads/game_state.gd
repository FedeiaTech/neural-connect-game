extends Node
## Global game state: the only autoload (see docs/SDD.md 8.4).
## Holds the current mission and, later, the saved progress (T3.2).

signal current_mission_changed(mission_id: StringName)

var current_mission: StringName = &"":
	set(value):
		if current_mission == value:
			return
		current_mission = value
		current_mission_changed.emit(value)
