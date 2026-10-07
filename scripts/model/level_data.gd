class_name LevelData
extends Resource
## Hand-authored mission data (SDD 8.2). Read-only at runtime: PuzzleModel copies it.

@export_group("Mission")
@export var mission_id: StringName = &""
@export var mission_name: String = ""
@export var chapter_id: int = 0
## Optional story shown before the level starts.
@export_multiline var story_text: String = ""

@export_group("Playfield")
## Outer play area polygon. Neuron circles must stay fully inside it.
@export var play_area: PackedVector2Array = PackedVector2Array()
## Solid islands inside the play area. Neuron circles must stay fully outside them.
@export var obstacles: Array[PackedVector2Array] = []
@export var neuron_radius: float = 28.0
## Highlight crossing dendrites and their neurons while playing.
@export var show_crossing_feedback: bool = true

@export_group("Graph")
@export var neurons: Array[NeuronData] = []
## Edge id = index in this array.
@export var dendrites: Array[DendriteData] = []

@export_group("Scoring")
@export var par_moves: int = 0
@export var par_time: float = 0.0


## Returns the neuron with this id, or null.
func find_neuron(id: int) -> NeuronData:
	for neuron: NeuronData in neurons:
		if neuron != null and neuron.id == id:
			return neuron
	return null


## Neuron ids in authoring order (null entries skipped).
func get_neuron_ids() -> Array[int]:
	var ids: Array[int] = []
	for neuron: NeuronData in neurons:
		if neuron != null:
			ids.append(neuron.id)
	return ids
