class_name NeuronData
extends Resource
## One neuron of a level, authored by hand in the Inspector.

## Unique id inside the level. Dendrites reference neurons by this id.
@export var id: int = 0
## Start (tangled) position in playfield coordinates.
@export var position: Vector2 = Vector2.ZERO
## Reference solution position. Used by level validation only.
@export var solution_position: Vector2 = Vector2.ZERO
## Fixed (red) neurons cannot be dragged but still block other neurons.
@export var fixed: bool = false
