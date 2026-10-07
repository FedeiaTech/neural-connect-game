# Feature: flow-and-persistence

Objective: Phase 3 of `docs/plans/implementation-plan.md` — screens flow and local progress save.
Scope: T3.1 ScreenHost + screens (Main menu, Mission select, Level, summary flow, Settings minimal, Pause) and Transition layer; T3.2 progress save/load.
Out of scope: final aesthetics of menus (Phase 4 T4.5 restyles them).
Constraints: Godot 4.7.2, GDScript, gdUnit4, English artifacts. One autoload (`GameState`), signals up / calls down (SDD 8.4–8.6).
Branch: `feat/mvp-foundation`. Slice base: `13a078c` (phase 2 review declined by user).

## Tasks (route: delegated direct — writer trigger, 2+ non-trivial files per task)

- [x] **T3.2 Progress save/load** (done first) — campaign catalog, Progress, versioned JSON save, settings.
  Commit `b54699b`. Evidence: RED (`Campaign`/`ChapterData`/`Progress`/`SAVE_VERSION` missing, parse errors)
  → GREEN `tests/campaign/*` 23 tests, suite 185/185.
  Decisions:
  - `Campaign` (Resource, `data/campaign.tres`) → `ChapterData` (id, title, subtitle, `missions: Array[LevelData]`).
    Chapter 1 "First Signals" = m01, m02. Campaign order = chapter order then mission order.
  - `Progress` (RefCounted, plain data): per mission `completed`, best `stars` (1–3), best `moves`, best `time`;
    each best is kept independently. `to_dict()` / tolerant `from_dict()` (malformed entries skipped).
  - Unlock rule (chapter rules undecided → linear): first campaign mission always unlocked; any other mission
    unlocks when the previous mission in campaign order (across chapters) is completed. Completed = unlocked.
  - Save: ONE file `user://progress.json` holding progress AND settings (no separate settings.cfg) so there is one
    injectable path (`GameState.save_path`) and one atomic write:
    `{"version": 1, "progress": {"missions": {"m01": {"completed", "stars", "moves", "time"}}}, "settings": {"master_volume", "reduced_motion"}}`.
    Missing / empty / corrupt / non-object / no numeric version → fresh progress + default settings (warning, no crash).
    `SaveFile.write_json` writes `<path>.tmp` then renames (no half-written saves). `_migrate()` hook for future versions.
  - `GameState` API: `campaign`, `progress`, `current_mission`, `save_path`, `master_volume`, `reduced_motion`,
    `load_game()`, `save_game()`, `record_result(id, LevelResult)`, `is_unlocked(id)`, `next_mission_after(id)`,
    `get_level(id)`, `set_master_volume(v)` (clamped, applied to master bus, saved), `set_reduced_motion(b)`,
    `apply_settings()`; signals `progress_changed`, `settings_changed`, `current_mission_changed`.
  - Tests use a fresh GameState instance on `user://test_progress.json` (deleted after each test).
- [x] **T3.1 ScreenHost and screens** — Main = ScreenHost + Transition; MainMenu, MissionSelect, Level, Settings, Pause.
  Commits `0fe2ef1` (pause overlay + completion navigation in Level/HUD) and `061b6a6` (ScreenHost, screens,
  Transition, theme). Evidence: RED (`ScreenHost`, `Transition`, `MainMenu`, `MissionSelect`, `SettingsScreen` missing,
  parse errors) → GREEN suite 217/217 (+32: `tests/flow/*` 14, `tests/ui/test_screens.gd` 8, HUD +4, Level +6).
  Decisions:
  - `scenes/main.tscn`: Main → ScreenHost (Node, `transition` export) + Transition (CanvasLayer, layer 100,
    PROCESS_MODE_ALWAYS, `Fade` ColorRect). Main starts on the main menu; Transition starts opaque so the first
    screen fades in.
  - ScreenHost keeps exactly one screen child; `go_to(screen)` = cover → swap → reveal; requests during a
    transition are ignored (`is_busy()`); `play_mission(id)` refuses unknown/locked missions. Swapped-out screens are
    `queue_free()`d (they can be inside their own signal emission).
  - Transition: tween on `Fade.color:a`, `FADE_DURATION` 0.35 s per full transition; `GameState.reduced_motion` →
    instant. Blocks mouse while covered.
  - Level flow: ScreenHost listens to `LevelController.level_completed` → `GameState.record_result` →
    `Level.set_next_mission_available(next unlocked)`. HUD completion panel: Next mission (hidden if none), Replay,
    Missions. `level_restart_requested` needs no ScreenHost action (restart never reloads the scene, SDD 8.6.4); the
    Level resets its HUD itself.
  - Pause: `pause` action (Esc) or HUD Pause button → `Level.pause()` (only in PLAYING) sets `SceneTree.paused`;
    the HUD is PROCESS_MODE_ALWAYS, LevelController/InputController are pausable so the timer stops. Resume,
    Restart (resume + restart) and Mission select (resume + navigate). Level unpauses in `_exit_tree`.
  - MissionSelect: chapter sections (title "Chapter N: Title", subtitle) with `MissionNode` (BaseButton, procedural
    circle + number + 3 stars; locked = dim/disabled, unlocked = outline, completed = filled). Emits
    `mission_selected(id)` only for unlocked missions. ui_cancel = Back.
  - Settings: master volume HSlider (0–1, step 0.05) and Reduced motion CheckButton, applied and saved on change.
  - One shared Theme `scenes/ui/theme.tres` (white on black, default font, size 28) set as `gui/theme/custom`.
  - Test changes: `test_main_scene_runs_the_first_mission` removed from `tests/level/test_level_scene.gd`; the new
    flow is covered by `tests/flow/test_screen_host.gd`. Flow/UI tests redirect the GameState autoload with
    `tests/flow/game_state_sandbox.gd` (temp save, reduced motion on, restored afterwards).

## Progress / evidence

- Final checks (after T3.1):
  - `./run_tests.ps1`: exit 0, 217 test cases, 0 errors / failures / orphans.
  - `godot --headless --path . --import`: exit 0, no SCRIPT ERROR / parse errors.
  - `godot --headless --path . --quit-after 120`: exit 0, only the engine banner (main menu loads).
- Not covered by automated checks: visual layout of the new screens and real mouse/keyboard play in a window.
- Known: saving on every volume slider step writes the save file repeatedly while dragging (small file; fine for now).
- Next: native review of the phase 3 slice (base `13a078c`), then Phase 4.

Engram mirror: pending (engram MCP unavailable this session).
