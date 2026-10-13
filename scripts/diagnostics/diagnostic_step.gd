class_name DiagnosticStep
extends RefCounted
## One isolated check of the diagnostic battery (see DiagnosticRunner): it builds a small scene in
## the stage, lets it run for `duration` seconds and tears it down. Steps are independent objects so
## a new suspect is one more subclass in DiagnosticSteps.
##
## Contract: begin(stage) adds what it needs (tracked with _own so end() can free it), update() runs
## every frame, end() releases everything. A step must not need input (except `manual` ones).

var id: StringName = &""
## English description, shown in the report.
var title := ""
var duration := 10.0
## The player plays by hand during this step (touch input check).
var manual := false
## Needs a real window (rendering, audio); skipped under --headless.
var requires_window := true
## Translation key of a short instruction shown on screen while the step runs ("" for none).
var hint_key := ""

var _owned: Array[Node] = []


func begin(_stage: Control) -> void:
	pass


func update(_delta: float, _elapsed: float) -> void:
	pass


func end() -> void:
	_free_owned()


## Adds node under parent and remembers it, so end() frees it.
func _own(parent: Node, node: Node) -> Node:
	parent.add_child(node)
	_owned.append(node)
	return node


func _free_owned() -> void:
	for node in _owned:
		if is_instance_valid(node):
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.queue_free()
	_owned.clear()
