extends RefCounted
## MEASURE-MODE (T8.1) pure helpers behind tools/analyze_measurements.gd: parse
## user://measurements.csv, summarize completed runs per mission and propose pars.
##
## Pars map to the existing star rule (LevelResult): par_moves / par_time are the 3-star
## thresholds and 2 stars are earned up to TWO_STAR_FACTOR (1.5) times those values. So:
##   proposed par_moves = ceil(best_moves * BEST_FACTOR)      (3 stars ~ best run + 15 %)
##   proposed par_time  = ceil(best_time  * BEST_FACTOR) s
## The 2-star threshold is therefore 1.5 x par ~ 1.7 x best; the median of the measured runs is
## reported next to it so the human can judge whether 2 stars is reachable by a typical run.
## Only `completed` rows count. A mission without one has no data and is never touched.

const BEST_FACTOR := 1.15
const TWO_STAR_FACTOR := 1.5
const COLUMNS := 8


## Rows as dictionaries {timestamp, mission_id, result, first_move (-1 when blank), total_seconds,
## moves, restarts_before, stars}. The header, blank lines and malformed rows are skipped.
static func parse_csv(text: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for line in text.split("\n"):
		var cells := line.strip_edges().split(",")
		if cells.size() != COLUMNS or cells[0] == "timestamp":
			continue
		if not cells[4].is_valid_float() or not cells[5].is_valid_int():
			continue
		rows.append({
			"timestamp": cells[0], "mission_id": cells[1], "result": cells[2],
			"first_move": cells[3].to_float() if cells[3].is_valid_float() else -1.0,
			"total_seconds": cells[4].to_float(), "moves": cells[5].to_int(),
			"restarts_before": cells[6].to_int() if cells[6].is_valid_int() else 0,
			"stars": cells[7].to_int() if cells[7].is_valid_int() else 0,
		})
	return rows


## Mission id -> {"runs": completed runs, "best_moves", "median_moves", "best_time",
## "median_time"} (the last four are 0 without runs). Missions seen in any row are listed.
static func analyze(rows: Array[Dictionary]) -> Dictionary:
	var moves_by_mission := {}
	var times_by_mission := {}
	var stats := {}
	for row in rows:
		var mission: String = row["mission_id"]
		if not stats.has(mission):
			stats[mission] = {"runs": 0, "best_moves": 0, "median_moves": 0.0, "best_time": 0.0, "median_time": 0.0}
			moves_by_mission[mission] = []
			times_by_mission[mission] = []
		if row["result"] == "completed":
			moves_by_mission[mission].append(row["moves"])
			times_by_mission[mission].append(row["total_seconds"])
	for mission: String in stats:
		var moves: Array = moves_by_mission[mission]
		var times: Array = times_by_mission[mission]
		if moves.is_empty():
			continue
		stats[mission] = {"runs": moves.size(), "best_moves": moves.min(), "median_moves": median(moves),
			"best_time": times.min(), "median_time": median(times)}
	return stats


static func median(values: Array) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n == 0:
		return 0.0
	if n % 2 == 1:
		return float(sorted[n / 2])
	return (float(sorted[n / 2 - 1]) + float(sorted[n / 2])) * 0.5


## Proposed pars for one mission's stats, or {} without completed runs ("no data").
static func propose(stat: Dictionary) -> Dictionary:
	if stat.get("runs", 0) < 1:
		return {}
	var par_moves := maxi(ceili(stat["best_moves"] * BEST_FACTOR - 0.0001), 1)
	var par_time := maxf(ceilf(stat["best_time"] * BEST_FACTOR - 0.0001), 1.0)
	return {"par_moves": par_moves, "par_time": par_time,
		"two_star_moves": par_moves * TWO_STAR_FACTOR, "two_star_time": par_time * TWO_STAR_FACTOR}


## Rewrites par_moves / par_time on the `"id": "mNN"` line of every mission in proposals
## (id -> {"par_moves", "par_time"}) inside the text of tools/level_specs.gd. A missing
## par_moves is inserted before par_time. Missions not in proposals are left untouched.
static func apply_to_specs(text: String, proposals: Dictionary) -> String:
	var lines := text.split("\n")
	var time_re := RegEx.create_from_string('"par_time": [0-9.]+')
	var moves_re := RegEx.create_from_string('"par_moves": [0-9]+')
	for i in lines.size():
		for mission: String in proposals:
			if not lines[i].contains('"id": "%s"' % mission):
				continue
			var proposal: Dictionary = proposals[mission]
			var line := lines[i]
			var par_time := '"par_time": %s' % _float(proposal["par_time"])
			var par_moves := '"par_moves": %d' % proposal["par_moves"]
			if moves_re.search(line) != null:
				line = moves_re.sub(line, par_moves)
				line = time_re.sub(line, par_time)
			else:
				line = time_re.sub(line, par_moves + ", " + par_time)
			lines[i] = line
	return "\n".join(lines)


## Float with at least one decimal, like the spec file ("46.0", "46.5").
static func _float(value: float) -> String:
	var text := str(value)
	return text if text.contains(".") else text + ".0"
