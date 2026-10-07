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
- [ ] **T1.3 Drag and collisions** — `grab/drag_to/release`, boundary/obstacles/neurons, fixed neurons.
- [ ] **T1.4 Tension dendrites** — `tension_changed`, `edge_broke`.
- [ ] **T1.5 Win and moves** — `solved`, move count.
- [ ] **T1.6 Level validation helper** — reference solution has zero crossings and valid placement.

## Acceptance

- All model tests pass headless; RED observed before GREEN per task.
- `PuzzleModel` extends `RefCounted` and references no Node.

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
