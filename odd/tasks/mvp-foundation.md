# Feature: mvp-foundation

Objective: Phase 0 of `docs/plans/implementation-plan.md` — project foundation ready for the pure model work.
Problem/why: the project is an empty Godot 4.7 template; tasks T1.x need folders, settings, an autoload and a test runner.
Scope: T0.1 project setup, T0.2 gdUnit4 smoke test. Out of scope: any gameplay code.
Constraints: Godot 4.7.2, GL Compatibility, GDScript only, English artifacts. See `docs/SDD.md`.
Branch: `feat/mvp-foundation` (base `main` @ 7c2ef1a). Delivery strategy: ask-on-risk. Forecast: ~150 authored lines.

## Tasks

- [x] **T0.1 Project setup** — route: direct inline (mechanical config, few files, no research).
  - Folders: `scripts/{model,views,ui,autoloads}`, `scenes/{screens,level,views}`, `data/levels`, `assets/shaders`, `tests`.
  - `project.godot`: viewport 1920x1080, stretch `canvas_items` + aspect `keep`, black clear color, main scene, input actions, `GameState` autoload.
  - `.gitignore` extended (exports, OS/IDE files).
  - Check: `godot --headless --path . --quit` loads with no errors; run main scene headless for a few frames.
  - Test-first exception: configuration only, no meaningful runnable RED.
- [ ] **T0.2 gdUnit4** — install addon, one passing smoke test, headless runner command documented.

## Acceptance

- Project opens/runs headless without errors; `GameState` autoload resolves.
- gdUnit4 smoke test passes headless.

## Progress / evidence

- T0.1: `godot --headless --path . --import` → no errors; `godot --headless --path . --quit-after 30` → exit 0, no errors.
  Input actions: `grab` (LMB), `restart` (R), `pause` (Esc); touch emulates mouse. Aspect `keep` per SDD 5.1.

## Next step

T0.2.

Engram mirror: pending (engram MCP unavailable this session).
