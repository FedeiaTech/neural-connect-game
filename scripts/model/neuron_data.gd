class_name NeuronData
extends Resource
## One neuron of a level, authored by hand in the Inspector.

## NORMAL: a plain neuron (movable unless fixed). RECEPTOR (T7.3): an immovable cyan neuron
## that grows dynamic links to movable neurons within `reach` and needs `required_links` of them.
## TOXIC (T8.2): a movable yellow neuron that must stay out of every receptor's reach: inside it
## forms a contamination link that blocks the win (never a loss).
enum Kind { NORMAL, RECEPTOR, TOXIC }

## Unique id inside the level. Dendrites reference neurons by this id.
@export var id: int = 0
## Start (tangled) position in playfield coordinates.
@export var position: Vector2 = Vector2.ZERO
## Reference solution position. Used by level validation only.
@export var solution_position: Vector2 = Vector2.ZERO
## Fixed (red) neurons cannot be dragged but still block other neurons.
@export var fixed: bool = false
@export var kind: Kind = Kind.NORMAL

@export_group("Receptor")
## RECEPTOR only: a movable neuron is in reach when center distance - neuron radius <= reach
## (its center is inside the halo of radius neuron_radius + reach).
@export var reach: float = 0.0
## RECEPTOR only: links needed (1 or 2) for the receptor to be satisfied.
@export_range(1, 2) var required_links: int = 1


func is_receptor() -> bool:
	return kind == Kind.RECEPTOR


func is_toxic() -> bool:
	return kind == Kind.TOXIC
