# Feature: puzzle-model

Objective: Phase 1 of `docs/plans/implementation-plan.md` — the pure, node-free puzzle model, test-first.
Problem/why: all rules (crossings, drag collisions, tension, win) must live outside the views (SDD 8.1, 8.4–8.7).
Scope: T1.1–T1.6. Out of scope: any scene, view or input node.
Constraints: Godot 4.7.2, GDScript static typing, gdUnit4 (`./run_tests.ps1`), English artifacts.
Branch: `feat/mvp-foundation`. Last reviewed boundary: `84c69e1` (see mvp-foundation.md). Forecast: ~700 authored lines (code + tests).

## Tasks (route: delegated direct — writer trigger, 2+ non-trivial files)

- [x] **T1.1 LevelData resources** — `scripts/model/level_data.gd`, `neuron_data.gd`, `dendrite_data.gd`.
  Evidence: RED (types missing, parse errors) → GREEN `tests/model/test_level_data.gd` 7/7, suite 9/9.
- [x] **T1.2 Crossing detection** — `PuzzleModel.compute_crossings()`, `crossings_changed`.
  Evidence: RED (GeometryUtils/PuzzleModel undeclared) → GREEN `test_geometry_utils.gd` 7/7,
  `test_puzzle_model_crossings.gd` 8/8, suite 24/24. `crossings_changed` emission is exercised by the
  drag tests (T1.3) since only a position change can trigger it.
  Decision: touching endpoints and collinear overlaps of edges with no shared neuron count as crossings.
- [x] **T1.3 Drag and collisions** — `grab/drag_to/release`, boundary/obstacles/neurons, fixed neurons.
  Evidence: RED (`grab` nonexistent) → GREEN `test_puzzle_model_drag.gd` 21/21, suite 45/45.
  Decisions: path sub-stepped at radius*0.25 plus 16-step bisection for the contact point (no
  tunneling; max corner clip ~0.2 px at r=28); `neuron_blocked` carries the neuron's stop center and
  fires on every blocked `drag_to`; `grab` refuses while another neuron is grabbed (single pointer).
- [x] **T1.4 Tension dendrites** — `tension_changed`, `edge_broke`.
  Evidence: RED (`get_tension_ratio` nonexistent) → GREEN `test_puzzle_model_tension.gd` 11/11, suite 56/56.
  Decisions: break when length > max_length (exactly max does not break); the move that breaks is
  applied (`neuron_moved`, `tension_changed` 1.0) then `edge_broke`; broken model refuses grab/drag
  and `neuron_blocked` is suppressed; ratio is 0 when max_length <= rest_length.
- [x] **T1.5 Win and moves** — `solved`, move count.
  Evidence: RED (`is_solved` nonexistent) → GREEN `test_puzzle_model_win.gd` 10/10, suite 66/66.
  Decisions: a move counts only if the neuron actually changed position during the grab; `solved`
  is checked on release only (never mid-drag) and emitted at most once per model.
- [x] **T1.6 Level validation helper** — reference solution has zero crossings and valid placement.
  Evidence: RED (`validate_level()` not found) → GREEN `test_level_validation.gd` 19/19 (incl. a guard
  that validates every `.tres` under `res://data/levels`, currently none), suite 85/85.
  Decisions: also rejects null entries, radius <= 0, fixed neurons whose solution differs from start,
  and TENSION edges with max_length <= rest_length; crossing check is skipped when structure is broken.

## Acceptance

- All model tests pass headless; RED observed before GREEN per task.
- `PuzzleModel` extends `RefCounted` and references no Node.

## Progress / evidence

- Route: every task delegated direct (single bounded writer), test-first with RED observed before GREEN.
- Commits (one per task): T1.1 `20ae5cc`, T1.2 `b780bc7`, T1.3 `38768d4`, T1.4 `61df38f`,
  T1.5 `f885a49`, T1.6 `af9c343`.
- Final checks: `./run_tests.ps1` exit 0, 85 test cases, 0 errors/failures/orphans;
  `godot --headless --path . --import` exit 0, no SCRIPT ERROR or warnings.
- `PuzzleModel` extends `RefCounted`; no Node references in `scripts/model/`.
- Next: Phase 2 (T2.1 views driven by model signals). Native review not run by this writer.

- Review: assessed medium, `slice_budget_reached` (1626 lines, range `84c69e1..471da49`); user granted;
  lens review-reliability → approved, acknowledged (lineage review-d99b3cab21485c35, authority burned).
  Advisory follow-ups moved to `odd/tasks/playable-core.md` T1.7. Reviewed boundary → `471da49`.

Engram mirror: pending (engram MCP unavailable this session).
