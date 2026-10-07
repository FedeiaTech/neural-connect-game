extends RefCounted
## Records every emission of the watched signals, synchronously, so tests can count
## emissions and assert "not emitted" without waiting for a timeout.

var _events: Array[Array] = []


func watch(source: Object, signal_names: Array[StringName]) -> void:
	for signal_name in signal_names:
		source.connect(signal_name, func(...args: Array) -> void: _events.append([signal_name, args]))


func count(signal_name: StringName) -> int:
	return _events.filter(func(event: Array) -> bool: return event[0] == signal_name).size()


## Arguments of every emission of the signal, in order.
func args_of(signal_name: StringName) -> Array[Array]:
	var result: Array[Array] = []
	for event in _events:
		if event[0] == signal_name:
			result.append(event[1])
	return result


func last_args(signal_name: StringName) -> Array:
	var all := args_of(signal_name)
	return all.back() if not all.is_empty() else []


func clear() -> void:
	_events.clear()
