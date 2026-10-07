extends RefCounted
## Samples engine Performance monitors once per frame and summarizes them (T4.7 perf pass).
## Used by the windowed capture scenes in their perf modes; not a test suite.
## Frame times come from wall-clock ticks between samples. Performance.TIME_PROCESS is not used:
## the engine refreshes it once per second, so it does not describe a single frame.

var _start_usec := 0
var _last_usec := 0
var _frame_ms := PackedFloat32Array()
var _draw_sum := 0.0
var _draw_max := 0.0
var _objects_sum := 0.0
var _primitives_sum := 0.0


func start() -> void:
	_frame_ms = PackedFloat32Array()
	_start_usec = Time.get_ticks_usec()
	_last_usec = _start_usec


func sample() -> void:
	var now := Time.get_ticks_usec()
	_frame_ms.append((now - _last_usec) / 1000.0)
	_last_usec = now
	var draws := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	_draw_sum += draws
	_draw_max = maxf(_draw_max, draws)
	_objects_sum += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
	_primitives_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)


func elapsed() -> float:
	return (Time.get_ticks_usec() - _start_usec) / 1_000_000.0


func report(label: String) -> String:
	var n := maxi(_frame_ms.size(), 1)
	var sorted := _frame_ms.duplicate()
	sorted.sort()
	var total := 0.0
	for ms in sorted:
		total += ms
	var p99 := sorted[mini(int(n * 0.99), n - 1)] if not sorted.is_empty() else 0.0
	var worst := sorted[n - 1] if not sorted.is_empty() else 0.0
	return ("perf %s: %d frames in %.2f s = %.1f fps | frame avg %.2f ms p99 %.2f ms max %.2f ms | " \
		+ "draw calls avg %.1f max %d | objects avg %.1f | " \
		+ "primitives avg %.0f | nodes %d | static mem %.1f MB") % [
		label, _frame_ms.size(), elapsed(), _frame_ms.size() / maxf(elapsed(), 0.001), total / n, p99,
		worst, _draw_sum / n, int(_draw_max), _objects_sum / n, _primitives_sum / n,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0]
