# Neural Connect

2D puzzle game in Godot 4.7 (GL Compatibility, GDScript). The player drags neurons so that
dendrites (straight segments) do not cross. Design: `docs/SDD.md`. Plan: `docs/plans/implementation-plan.md`.

## Handoff (read first)

Status (2026-10-07): **MVP implemented** on branch `feat/mvp-foundation` - phases 0-5 of
`docs/plans/implementation-plan.md` done; Phases 6-7 add reset, en/es, crossing sparks, lethal walls and
receptor neurons (30 missions in 7 chapters, 457 tests, save format v2 with id migration). Per-feature evidence in `odd/tasks/*.md`.
Phase 8 (2026-10-09): 48 missions in 9 chapters with a boss at the end of each (stable ids: m01..m30 unchanged,
m31..m48 new; order = explicit list in `tools/level_specs.gd`), toxic neurons, diseased dendrites, organic arenas,
the temporary measurement mode was used once and removed (pars are now fixed from the measured streak plus designer estimates in `MEASURED_PAR_MOVES`; to measure again, recover the code from git history commit 96c58f0), 604 tests. See `odd/tasks/measure-toxic-bosses.md`.
Next step: human playtest (grab radius, difficulty, pars); retune via `tools/level_specs.gd` +
`godot --headless --path . -s res://tools/build_levels.gd`. Not pushed; no remote configured.

Decisions already made (all details in `docs/SDD.md`, do not re-ask):
- Straight-segment dendrites; elasticity is visual only. Aesthetics must stay swappable (logic separate from drawing).
- Special tension dendrite: light green, thins when stretched, breaks at max length, restarts the level. Advanced levels only.
- Win = zero crossings. Crossing dendrites and their neurons are highlighted live.
- Neuron vs neuron: solid, stops at contact but stays grabbed. Neuron vs dendrite: free (crossing is flagged). Obstacles block neurons, not dendrites.
- Red neurons are fixed. Per-level play-area shape and obstacles; living (animated) boundary with fixed collision shape.
- All levels hand-designed ("missions" = fixed story levels in chapters). No procedural levels. Story text every 2-3 missions.
- Scoring: moves AND time to give stars; generous par values, tune later. Move = one full drag.
- Mouse first, touch-ready input. Multi-platform is the long-term goal.
- No external images: all art via code, shaders and particles. Interactive animated menus.
- Architecture: pure `PuzzleModel` (RefCounted) + views; two autoloads (`GameState`; `ExitReport` = exit diagnostics, kept out of GameState because tests instantiate that; it loads after GameState because it turns on low memory mode after an abnormal close on a device and asks Android for the system's exit reason); signals up, calls down; no EventBus.
- Settings (saved in `progress.json`): volume, reduced motion, language, low memory mode (`VisualTuning.is_low_memory()`: forces low quality, static crossing sparks, quarter-size bursts).
- GDScript only. Tests with gdUnit4. Write the model test-first.

Versions: every exported build bumps `config/version` (project.godot) and the Android preset
(`version/name`, `version/code`, `export_path`), adds an entry to `version.md` and copies that file to
`export/` next to the APK.

Run tests: `./run_tests.ps1` (gdUnit4 v6.2.1 in `addons/gdUnit4`, tests in `tests/`, files `test_*.gd`
extending `GdUnitTestSuite`). Godot binary on PATH: `godot` (4.7.2). Task tracking: `odd/tasks/`.

Post-MVP (Phase 6): progress reset (Settings + per mission) and en/es localization via `locale/translations.csv`
(semantic keys; content `.tres` store keys). New UI text must be a CSV key with both `en` and `es` (neutral Spanish).

Conventions: code, comments, identifiers and source strings in English. Conversation with the user in Spanish (Rioplatense).
Use commits as conventional commits, no AI attribution. The user wanted to be told before implementation starts (they were switching model).

## GodotPrompter

This is a Godot project with GodotPrompter skills available. Before implementing any game system, you MUST check for a matching `godot-prompter:*` skill and invoke it. This applies to all agents, subagents, and sessions working in this repository.

Key skills: `player-controller`, `state-machine`, `event-bus`, `scene-organization`, `component-system`, `resource-pattern`, `godot-ui`, `hud-system`, `ai-navigation`, `camera-system`, `audio-system`, `save-load`, `inventory-system`, `godot-testing`.

For the full skill list, invoke `godot-prompter:using-godot-prompter`.
