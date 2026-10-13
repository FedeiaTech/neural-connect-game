class_name NativeTrace
extends RefCounted
## Pulls the readable lines out of the tombstone Android keeps for a native crash
## (ApplicationExitInfo.getTraceInputStream(): a protobuf where the library paths, function names and
## the abort message are plain ASCII). Pure: it only looks at bytes.

const MIN_RUN := 5
const MAX_LINES := 40
const MAX_LINE_LENGTH := 200
## Text worth keeping: libraries, namespaces, the engine, the GPU drivers and abort messages.
const KEYWORDS: Array[String] = [".so", "/", "::", "libgodot", "libvulkan", "libgles", "mali", "abort", "sigsegv"]


## Every run of printable ASCII (space to ~) at least min_length characters long, in file order.
static func printable_runs(bytes: PackedByteArray, min_length := MIN_RUN) -> PackedStringArray:
	var runs := PackedStringArray()
	var start := -1
	for i in bytes.size() + 1:
		var printable := i < bytes.size() and bytes[i] >= 0x20 and bytes[i] < 0x7F
		if printable and start < 0:
			start = i
		elif not printable and start >= 0:
			if i - start >= min_length:
				runs.append(bytes.slice(start, i).get_string_from_ascii())
			start = -1
	return runs


## The runs that look like part of a crash trace, without repeats, capped at max_lines.
static func relevant_lines(bytes: PackedByteArray, max_lines := MAX_LINES) -> PackedStringArray:
	var lines := PackedStringArray()
	for run in printable_runs(bytes):
		if lines.size() >= max_lines:
			break
		if _is_relevant(run) and not lines.has(run.left(MAX_LINE_LENGTH)):
			lines.append(run.left(MAX_LINE_LENGTH))
	return lines


## The report section: the lines, or a note about why there are none. "" when there is nothing to say.
static func format_section(lines: PackedStringArray, note: String) -> String:
	if lines.is_empty():
		return "" if note == "" else "Native crash trace: not available (%s)" % note
	return "Native crash trace (readable text of the system tombstone):\n  " + "\n  ".join(lines)


static func _is_relevant(run: String) -> bool:
	var lower := run.to_lower()
	for keyword in KEYWORDS:
		if lower.contains(keyword):
			return true
	return false
