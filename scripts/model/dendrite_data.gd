class_name DendriteData
extends Resource
## A straight dendrite (edge) between two neurons, referenced by neuron id.

## NORMAL: a plain dendrite. TENSION: breaks the level when stretched past max_length.
## DISEASED (T8.3): a dendrite that must be broken on purpose: stretched past max_length it snaps,
## disappears (no more crossings) and counts towards the win; never a loss.
enum Kind { NORMAL, TENSION, DISEASED }

## Neuron id at one end.
@export var a: int = 0
## Neuron id at the other end.
@export var b: int = 0
@export var kind: Kind = Kind.NORMAL

@export_group("Tension")
## TENSION and DISEASED: the dendrite breaks when its length exceeds this value.
@export var max_length: float = 0.0
## TENSION and DISEASED: length at which the strain ratio is 0.
@export var rest_length: float = 0.0


func is_tension() -> bool:
	return kind == Kind.TENSION


func is_diseased() -> bool:
	return kind == Kind.DISEASED
