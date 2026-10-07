class_name DendriteData
extends Resource
## A straight dendrite (edge) between two neurons, referenced by neuron id.

enum Kind { NORMAL, TENSION }

## Neuron id at one end.
@export var a: int = 0
## Neuron id at the other end.
@export var b: int = 0
@export var kind: Kind = Kind.NORMAL

@export_group("Tension")
## TENSION only: the dendrite breaks when its length exceeds this value.
@export var max_length: float = 0.0
## TENSION only: length at which the tension ratio is 0.
@export var rest_length: float = 0.0


func is_tension() -> bool:
	return kind == Kind.TENSION
