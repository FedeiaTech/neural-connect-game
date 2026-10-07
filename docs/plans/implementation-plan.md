# Neural Connect — Implementation Plan

Source of truth: `docs/SDD.md`. Each task is small, testable and ends with a runnable state.
The pure model (`PuzzleModel`) is built and tested first, before any visuals.

## Phase 0 — Foundation

- [x] **T0.1 Project setup** — folders (`scripts/model`, `scripts/views`, `scripts/ui`, `scenes`, `data/levels`, `tests`), stretch mode `canvas_items`, base viewport, black clear color, input actions, `GameState` autoload.
  Skills: `godot-prompter:godot-project-setup`, `godot-prompter:responsive-ui`
- [x] **T0.2 Test framework** — install **gdUnit4** (decided), one passing smoke test.
  Skills: `godot-prompter:godot-testing`

## Phase 1 — Pure model (no nodes, test-first)

- [x] **T1.1 LevelData resource** — play area polygon, obstacles, neurons, dendrites, reference solution, par values, mission/chapter ids, optional `story_text`.
  Skills: `godot-prompter:resource-pattern`
- [x] **T1.2 Crossing detection** — segment intersection for edge pairs not sharing a neuron; emits `crossings_changed`.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:godot-testing`
- [x] **T1.3 Drag and collisions** — `grab/drag_to/release`; boundary and obstacle clamping, neuron-vs-neuron stop at contact while staying grabbed; fixed (red) neurons ignored.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:godot-testing`
- [x] **T1.4 Tension dendrites** — ratio, `tension_changed`, `edge_broke`.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:godot-testing`
- [x] **T1.5 Win condition and moves** — `solved` on release with zero crossings; move counting.
  Skills: `godot-prompter:godot-testing`
- [x] **T1.6 Level validation** — reference solution of every `LevelData` must have zero crossings (test).
  Skills: `godot-prompter:godot-testing`
- [x] **T1.7 Review follow-ups** — pair-count `crossings_changed`, start layout must be tangled, loud import failure in `run_tests.ps1`, tension guard tests.
  Skills: `godot-prompter:godot-testing`

## Phase 2 — Playable core (placeholder visuals)

- [x] **T2.1 NeuronView / DendriteView / ObstacleView / Boundary** — plain white/red/green drawing driven by model signals.
  Skills: `godot-prompter:2d-essentials`, `godot-prompter:scene-organization`
- [x] **T2.2 InputController** — mouse drag with generous grab radius, written to extend to touch.
  Skills: `godot-prompter:input-handling`
- [x] **T2.3 LevelController** — builds the model from `LevelData`, timer, moves, restart, scoring and stars.
  Skills: `godot-prompter:state-machine`, `godot-prompter:scene-organization`
- [x] **T2.4 Minimal HUD** — moves, time, restart, story text overlay.
  Skills: `godot-prompter:hud-system`, `godot-prompter:godot-ui`
- [x] **T2.5 First 4-neuron level playable end to end.** (`m01`, plus `m02` with a multi-dendrite neuron)

## Phase 3 — Flow and persistence

- [x] **T3.1 ScreenHost and screens** — Main, MissionSelect, Level, summary; transition layer.
  Skills: `godot-prompter:scene-organization`, `godot-prompter:godot-ui`
- [x] **T3.2 Progress save/load** — stars and completed missions, local.
  Skills: `godot-prompter:save-load`, `godot-prompter:resource-pattern`
- [x] **T3.3 Save hardening (phase 3 review follow-ups)** — verified temp writes, backup of unusable saves, unknown fields and newer versions preserved, busy transitions reported.
  Skills: `godot-prompter:save-load`

## Phase 4 — Aesthetics (all procedural, no external images)

- [x] **T4.1 Neuron and dendrite look** — glow, idle pulse, electric pulse along dendrites, grab feedback.
  Skills: `godot-prompter:shader-basics`, `godot-prompter:tween-animation`
- [x] **T4.2 Living boundary** — animated membrane, contact ripple.
  Skills: `godot-prompter:shader-basics`, `godot-prompter:2d-essentials`
- [x] **T4.3 Background** — drifting particles, vignette.
  Skills: `godot-prompter:particles-vfx`, `godot-prompter:shader-basics`
- [x] **T4.4 Crossing feedback and tension effects** — pulsing highlights, green tremble, break flash and burst.
  Skills: `godot-prompter:particles-vfx`, `godot-prompter:tween-animation`
- [x] **T4.5 Interactive animated menus** — living main menu, network-style mission map, star summary, theme.
  Skills: `godot-prompter:godot-ui`, `godot-prompter:tween-animation`, `godot-prompter:shader-basics`
- [x] **T4.6 Audio** — ambient, grab/release blips, tension tone, completion chord (all synthesized; scene-local AudioDirector).
  Skills: `godot-prompter:audio-system`
- [x] **T4.7 Glow and performance pass** — verify in GL Compatibility (WorldEnvironment glow stays off on this GPU; perf numbers in `odd/tasks/aesthetics.md`).
  Skills: `godot-prompter:godot-optimization`

## Phase 5 — Content

- [x] **T5.1 Hand-design missions** — chapter 1: basics (4 neurons) → multi-dendrite; chapter 2: shapes and obstacles; chapter 3: red fixed neurons; chapter 4: tension dendrites; combinations. Story text every 2–3 missions. Generous par values, tuned later.
  Skills: `godot-prompter:resource-pattern`
  (21 missions in 5 chapters, specs in `tools/level_specs.gd`, built by `tools/build_levels.gd`; see `odd/tasks/campaign-content.md`)
- [x] **T5.2 Playtest and tune** — par values, grab radius, difficulty curve.
  Automated tuning checks done (`tests/content/`: solvability replayed on the real model, pars, difficulty curve, readability).
  Pending: human playtest of pars, grab radius and the difficulty curve.

## Open items (SDD section 10)

- GDScript only; restart button in every level; local save format; chapter unlock rules. (Test framework decided: gdUnit4.)
