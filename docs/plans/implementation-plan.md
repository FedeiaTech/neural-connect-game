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

## Phase 6 — Post-MVP requests

- [x] **T6.1 Progress reset** — `GameState.reset_progress()` / `reset_mission(id)`; Settings "Reset progress" with inline confirmation; per-mission record reset in Mission select; restart hints in the HUD.
  Skills: `godot-prompter:save-load`, `godot-prompter:godot-ui`
- [x] **T6.2 Localization infrastructure** — `locale/translations.csv` (en, es), keys in every scene, formatted texts rebuilt on locale change, language setting saved (default from the OS locale), live switch from Settings.
  Skills: `godot-prompter:localization`, `godot-prompter:godot-ui`
- [x] **T6.3 Content translation** — mission names, stories and chapter titles/subtitles as keys, Spanish texts, levels rebuilt; layout checked in Spanish.
  Skills: `godot-prompter:localization`, `godot-prompter:resource-pattern`
- [x] **T6.4 Docs** — SDD 5.5/5.6/10 and this plan.
  (Evidence in `odd/tasks/localization-and-reset.md`.)

## Phase 7 — Sparks, hazards and synapses

- [x] **T7.1 Crossing marks** — `PuzzleModel.get_crossing_points()` + `crossing_points_changed`; dendrites keep their identity color (dash/crackle modulation), neurons get an amber dashed ring, `CrossingSparksView` crackles at every crossing point (static stars with reduced motion), electric buzz loop.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:shader-basics`, `godot-prompter:particles-vfx`, `godot-prompter:audio-system`
- [x] **T7.2 Lethal walls** — `LevelData.lethal_edges` / `lethal_obstacles`; destroy on contact (`neuron_destroyed`, `is_lost()`), hazard proximity, validation margin, planner keeps away; violet crackling walls, overload explosion, `LossReason.OVERLOAD` restart, alarm and explosion sounds.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:particles-vfx`, `godot-prompter:tween-animation`, `godot-prompter:audio-system`
- [x] **T7.3 Receptor neurons** — `NeuronData.Kind.RECEPTOR` (`reach`, `required_links`); dynamic links keyed `(receptor, neuron)` that count for crossings and the win; receptor halo/stub/dots, growing/straining/snapping links, wave through links, link sounds; planner replays on a shadow model.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:tween-animation`, `godot-prompter:resource-pattern`
- [x] **T7.4 Content** — chapters 5 Live Wires (m19–m21) and 6 Synapses (m22–m25), Convergence becomes chapter 7 (m26–m30, reworked to combine everything); campaign rebalanced (no crossing spikes), stories revised, en/es texts, save v2 migration (m19/m20/m21 → m26/m28/m30), `tools/find_start.gd` authoring helper.
  Skills: `godot-prompter:resource-pattern`, `godot-prompter:localization`, `godot-prompter:save-load`, `godot-prompter:godot-testing`
- [x] **T7.5 Docs** — SDD 2/3/4/5.4/7/8 and this plan.
  (Evidence in `odd/tasks/sparks-hazards-synapses.md`.)

## Phase 8 — Measurement, toxic neurons and diseased dendrites (run A)

- [x] **T8.1 Measurement mode** — developer-only, off by default (`--measure` user arg or F9, small MEASURE tag); `scripts/dev/measurement.gd` logs one CSV row per attempt to `user://measurements.csv`; `tools/analyze_measurements.gd` summarizes per mission and proposes pars (3 stars ~ best x 1.15), `--apply` rewrites `tools/level_specs.gd`. Removal list in `odd/tasks/measure-toxic-bosses.md`.
  Skills: `godot-prompter:godot-testing`, `godot-prompter:save-load`
- [x] **T8.2 Toxic neurons** — `NeuronData.Kind.TOXIC`, contamination links (soft rule), validation, yellow soma and warning glow, yellow dashed contamination link, HUD hint, alarm / clear sounds, planner keeps toxic neurons out of reach.
  Skills: `godot-prompter:math-essentials`, `godot-prompter:shader-basics`, `godot-prompter:audio-system`, `godot-prompter:localization`
- [x] **T8.3 Diseased dendrites** — `DendriteData.Kind.DISEASED`, broken set and win rule, validation, dark orange ember line with cracks, ember sparks and snap effect, crack / snap sounds, HUD counter, planner breaks them.
  Skills: `godot-prompter:particles-vfx`, `godot-prompter:shader-basics`, `godot-prompter:audio-system`
- [x] **T8.4 Campaign reorganization** — nine chapters (Pruning after Tension, Contagion after Synapses), 48 missions with stable ids (m31..m48 new, nothing renumbered, save stays v2), content tests pin the order, teaching rules and difficulty curve; stories en/es.
- [x] **T8.5 Organic arenas** — `tools/organic_shapes.gd` + `tools/layouts.gd` (seeded, planar layouts) + `tools/level_starts.gd`; every mission from chapter 2 on has a many-vertex outline.
- [x] **T8.6 Bosses** — last mission of each chapter: intro card, tag, boss look, fanfare, map crown nodes, HARD toxic (`hard_toxic`, `TOXIC_OVERLOAD`).
- [x] **T8.7 Docs** — SDD 3 / 7 and the feature document.
  (Evidence in `odd/tasks/measure-toxic-bosses.md`.)

## Open items (SDD section 10)

- GDScript only; restart button in every level; local save format; chapter unlock rules. (Test framework decided: gdUnit4.)
