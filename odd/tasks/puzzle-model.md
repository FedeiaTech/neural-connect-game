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
- [ ] **T1.5 Win and moves** — `solved`, move count.
- [ ] **T1.6 Level validation helper** — reference solution has zero crossings and valid placement.

## Acceptance

- All model tests pass headless; RED observed before GREEN per task.
- `PuzzleModel` extends `RefCounted` and references no Node.

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
