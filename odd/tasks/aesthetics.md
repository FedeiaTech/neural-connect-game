# Feature: aesthetics

Objective: Phase 4 of `docs/plans/implementation-plan.md` — bioluminescent look, animated menus and procedural audio (SDD 5.3–5.5), plus phase 3 review follow-ups.
Constraints: no external images or audio files — everything from code, shaders, particles and synthesized sound (SDD 5.5, 8.8). GL Compatibility. Respect `GameState.reduced_motion`.
Branch: `feat/mvp-foundation`. Last reviewed boundary: `4d8a73d` (phase 3 review approved, lineage review-d040a9cde8341cd4).

## Tasks (route: delegated direct — writer trigger; split in two writer runs: 4a = T3.3, T4.1–T4.4; 4b = T4.5–T4.7)

- [x] **T3.3 Save hardening (phase 3 review follow-ups)** — check temp write before rename; keep a backup of unreadable saves instead of overwriting; preserve unknown fields/newer version on save; `play_mission` returns false when busy. Commit `b71c389`.
- [x] **T4.1 Neuron and dendrite look** — commit `9f0c7ea`.
- [x] **T4.2 Living boundary and obstacles** — commit `7e9989c`.
- [x] **T4.3 Background** — commit `eaf9d89`.
- [x] **T4.4 Crossing feedback, tension effects, completion wave** — commit `ac90d0e`.
- [ ] **T4.5 Animated interactive menus** (run 4b; reuse `scenes/views/background.tscn`)
- [ ] **T4.6 Procedural audio** (run 4b)
- [ ] **T4.7 Glow and performance pass** (run 4b; re-check WorldEnvironment glow on other GPUs)

## Progress / evidence

### Run 4a (route: delegated direct, one writer; trigger: 2+ non-trivial files per task)

- **T3.3** (test-first; RED = missing `SaveFile.write_json_text`/`backup` parse errors, then GREEN).
  - `SaveFile.write_json_text` writes the temp file, checks `store_string` result and `get_error()`
    after flush, re-reads it (non-empty, parses into a Dictionary) and only then renames; on failure
    the temp file is removed, the old save kept and an error returned.
  - `SaveFile.backup(path)` moves an unusable save to `<path>.bak` (or `<path>.N.bak` if one exists);
    `GameState.load_game` calls it before falling back to fresh progress.
  - `GameState.save_game` deep-merges known values into the loaded data (`merge_save_data`):
    unknown top-level, progress, per-mission and settings keys survive; version = max(loaded, SAVE_VERSION).
  - `ScreenHost.go_to` / `play_mission` return false when a transition is busy (`go_to` is no longer
    a coroutine; `_run_transition` is).
- **T4.1** Neurons: `assets/shaders/neuron.gdshader` on one quad per neuron (premultiplied alpha:
  opaque soma, additive halo), per-neuron golden-angle phase, idle pulse (fixed neurons slower and
  deeper), wobbling membrane outline with 5 short dendrite stubs, grab = tween of scale/brightness,
  crossing = warm flicker that eases in/out, contact ring. Dendrites: `assets/shaders/dendrite.gdshader`
  on a subdivided strip (`RenderingServer.canvas_item_add_triangle_array`, UV.x along the length),
  core + glow + travelling electrical pulse every 4.5 s; tension: thinning, tremble (vertex bow) and
  warning flicker from ratio 0.6 (`VisualTuning.tension_*`). Geometry stays in `_draw_dendrite()`.
- **T4.2** `MembraneOutline` (resampled outline, outward normals, seamless bounded undulation,
  contact ripples with cooldown, exhale) shared by `MembraneView` → `BoundaryView` / `ObstacleView`
  (calmer). `_draw` polylines with an additive `CanvasItemMaterial`; collision polygons untouched.
  Ripples start from `neuron_blocked` only when the contact is within 1.3 radii of that outline.
- **T4.3** `scenes/views/background.tscn` (`BackgroundView`, CanvasLayer -10): dithered near-black
  depth shader, 40 additive `CPUParticles2D` spores with a procedural `GradientTexture2D`, vignette
  shader; all Controls ignore the mouse. Reduced motion freezes the spores. Used as the Level's
  `Background`; phase 4b menus can instance it.
- **T4.4** `NetworkWave` (pure BFS schedule from the last moved neuron; disconnected parts follow);
  `LevelFx` (Playfield/Fx, additive) plays the wave, exhales the membranes, and on tension break draws
  a snap flash, spawns a one-shot CPU particle burst and shakes the Level root (HUD/background are
  CanvasLayers and stay still). `Level` shows the summary after the wave via a bound timer callback
  (serial-guarded, cancelled by restart/reload; instant with reduced motion) and re-offers the Next
  button after showing it.
- Decisions: per-view `ShaderMaterial` (≈20–40 items, cheap) instead of instance uniforms (not
  available for canvas items); CPU particles over GPU for low counts on Compatibility; shader `TIME`
  drives idle motion, a `motion` uniform (0/1) implements reduced motion; existing level-scene tests
  run with reduced motion, the delayed path has its own tests.
- GL Compatibility verified with `tests/visual/capture_level.tscn` (windowed captures, Intel UHD 600,
  OpenGL 3.3): neuron, dendrite, vignette and depth shaders compile and render; modes play/grab/wave/
  reduced render without errors. **WorldEnvironment glow** (BG_CANVAS, glow on) was tried: it turns
  the background into a checkerboard artifact on this GPU, so it is not used; the look relies on
  additive / premultiplied blending. Re-check in T4.7.
- Verification (final): `./run_tests.ps1` → 269 test cases, 0 failures, exit 0;
  `godot --headless --path . --import` → no errors; `godot --headless --path . --quit-after 300` →
  exit 0, no errors; `godot --path . --quit-after 180` (windowed, GL Compatibility) → exit 0, no errors.
- Not visually captured: the tension break (no shipped mission has a tension dendrite yet); its code
  path is covered headless by `tests/level/test_level_fx.gd`.

- Review 4a: slice `4d8a73d..8c183a4` medium, `slice_budget_reached` (2445 lines); user **declined** (candidate-scoped).
  Parent spot check `./run_tests.ps1` → 269 cases, exit 0. Next slice base: `8c183a4`.

Next: run 4b (T4.5–T4.7).

Engram mirror: pending (engram MCP unavailable this session).
