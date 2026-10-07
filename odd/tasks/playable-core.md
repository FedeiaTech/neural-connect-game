# Feature: playable-core

Objective: Phase 2 of `docs/plans/implementation-plan.md` — first mission playable end to end with placeholder visuals.
Scope: T1.7 (review follow-ups), T2.1–T2.5. Out of scope: menus/screens (Phase 3), final aesthetics (Phase 4).
Constraints: Godot 4.7.2, GDScript static typing, gdUnit4, English artifacts. Views only read the model (SDD 8.1, 8.4–8.6).
Branch: `feat/mvp-foundation`. Last reviewed boundary: `471da49` (phase 1 review approved, lineage review-d99b3cab21485c35).

## Tasks (route: delegated direct — writer trigger, 2+ non-trivial files per task)

- [x] **T1.7 Review follow-ups (advisory, phase 1)** — `crossings_changed` must also fire when the crossing-pair count changes with the same edge set; `validate_level` rejects levels whose start layout has zero crossings; `run_tests.ps1` fails loudly when import fails; tension test separates broken-guard from no-grab guard and asserts no `neuron_blocked` after break.
  Commit `07e59dc`. Evidence: RED (pair-count emission test and start-untangled test failing) → GREEN suite 89/89.
  `run_tests.ps1` import-failure branch checked with a stubbed `godot` (prints output, exits 3).
  Decisions: the tension tests are hardening of already-correct guards (no RED possible); the drag
  guard is isolated white-box by forcing `_grabbed_id` after the break. `_two_neuron_level` fixtures in
  `test_level_validation.gd` now add a tangled X pair so the new start-layout rule does not leak into them.
- [x] **T2.1 Views** — NeuronView, DendriteView, ObstacleView, Boundary (placeholder drawing, signal-driven).
  Commit `4842471`. Evidence: RED (scenes/classes missing) → GREEN `tests/views/*` 18 tests, suite 107/107.
  Decisions: each view connects to the model signals it needs in `setup()` and filters by id; grabbed
  state (not a model concept) is pushed down by LevelController via `NeuronView.set_grabbed()`. Colors in
  `Palette`, drawing isolated in one `_draw_*` method per view. Broken tension dendrite hides itself;
  NeuronView flashes a contact ring on `neuron_blocked`; BoundaryView records the last contact (ripple hook).
- [x] **T2.2 InputController** — mouse drag, generous grab radius, touch-ready.
  Commit `934e2bc`. Evidence: RED (`InputController` missing) → GREEN `test_input_controller.gd` 13/13, suite 120/120.
  Decisions: grab radius = radius * 1.6; viewport → playfield via `get_global_transform_with_canvas()`;
  touch tracked per finger index, emulated mouse ignored during a touch drag; drag ends on focus loss and
  when the grab action is no longer held (release outside the window); `restart` action always emits.
- [x] **T2.3 LevelController** — model ownership, timer, moves, restart, stars, state machine.
  Commit `1075bbb`. Evidence: RED (`LevelController` missing, scripts hidden to observe it) → GREEN
  `test_level_controller.gd` 18/18 + `test_level_result.gd` 7/7, suite 145/145.
  Decisions: enum FSM INTRO/PLAYING/COMPLETE/RESTARTING; `tick(delta)` drives the clock (public for tests);
  break → RESTARTING for 0.6 s then `restart()`; restart never re-shows the story and ignores the R key in
  INTRO; moves synced from the model on `grab_ended`; playfield fitted with `compute_fit()` (centered,
  never upscaled, 96 px top margin for the HUD). Only the four SDD 8.5 signals are emitted.
- [x] **T2.4 Minimal HUD** — moves, time, restart, story overlay, completion summary.
  Commit `b46ce03`. Evidence: RED (`hud.tscn` missing) → GREEN `test_hud.gd` 8/8, suite 153/153.
  Decisions: stars drawn procedurally by `StarRow` (no glyph/font dependency); non-interactive Controls use
  `mouse_filter = IGNORE` so drags reach `_unhandled_input`; story dismiss on click/tap or `ui_accept`.
- [x] **T2.5 First mission** — `data/levels/m01.tres` (4 neurons), playable from main scene.
  Commit `90264e5`. Evidence: RED (`level.tscn` missing) → GREEN `test_level_scene.gd` 9/9, suite 162/162.
  Content: m01 "First Spark" (4-cycle bowtie, story, par 6 moves / 60 s), m02 "Branching Paths" (6 neurons,
  hub with 4 dendrites, no story, par 8 / 90 s); both pass `validate_level` (guard test).
  `scripts/main.gd` instantiates `scenes/level/level.tscn` and loads m01 (Phase 3 replaces it).

## Progress / evidence

- Final checks (after T2.5):
  - `./run_tests.ps1`: exit 0, 162 test cases, 0 errors / failures / orphans.
  - `godot --headless --path . --import`: exit 0, no SCRIPT ERROR / parse errors / warnings.
  - `godot --headless --path . --quit-after 120`: exit 0, only the engine banner (main scene loads m01).
- Observed once: the first full-suite run right after new `class_name` scripts were added aborted with exit -1
  and no summary; the immediate rerun passed. Not reproduced since; watch for it.
- Not covered by automated checks: visual look and real mouse play in a window (rendering is not unit-tested).
- Next: native review of the phase 2 slice (base `471da49`), then Phase 3 (ScreenHost, progress save).

- Review: slice `471da49..13a078c` assessed medium, `slice_budget_reached` (2355 lines); user **declined**
  review for this candidate (candidate-scoped). Parent spot check: `./run_tests.ps1` → 162 cases, exit 0.
  Next slice base: `13a078c`.

Engram mirror: pending (engram MCP unavailable this session).
