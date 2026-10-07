class_name LevelResult
extends RefCounted
## Outcome of a completed level (SDD 6, 8.5): moves, time and stars.

## Multiplier of the par values that still earns two stars.
const TWO_STAR_FACTOR := 1.5

var moves := 0
## Seconds spent in the PLAYING state.
var time := 0.0
var stars := 1


static func create(p_moves: int, p_time: float, par_moves: int, par_time: float) -> LevelResult:
	var result := LevelResult.new()
	result.moves = p_moves
	result.time = p_time
	result.stars = compute_stars(p_moves, p_time, par_moves, par_time)
	return result


## 3 stars: moves <= par_moves AND time <= par_time.
## 2 stars: moves <= par_moves * 1.5 AND time <= par_time * 1.5.
## 1 star: completed. Pars are intentionally generous (tuned later).
static func compute_stars(p_moves: int, p_time: float, par_moves: int, par_time: float) -> int:
	if p_moves <= par_moves and p_time <= par_time:
		return 3
	if p_moves <= par_moves * TWO_STAR_FACTOR and p_time <= par_time * TWO_STAR_FACTOR:
		return 2
	return 1
