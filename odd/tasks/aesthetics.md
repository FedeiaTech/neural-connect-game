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
- [x] **T4.5 Animated interactive menus** — commits `9293e67` (main menu, theme, settings, iris
  transition), `123b6b3` (mission network map, chapter headers), `0d2ebd4` (summary, HUD, pause).
- [x] **T4.6 Procedural audio** — commit `cbe6ea8`.
- [x] **T4.7 Glow and performance pass** — commit `f94e2fa` (glow still off: artifact on this GPU).

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

### Run 4b (route: delegated direct, one writer; trigger: 2+ non-trivial files per task)

- **T4.5** (test-first: RED = missing `DriftNetwork`/`GlowTitle`/`GlowButton`, `MissionMap`,
  `Hud.star_reveal_times` parse errors, then GREEN).
  - Main menu: `background.tscn` + `MenuNetworkView` drawing a pure, seeded `DriftNetwork`
    (26 neurons, min spacing, 2 nearest links, keeps the title/buttons area clear, slow drift,
    cursor brightens and pushes neurons within 230 px; reduced motion = anchors fixed, glow only,
    redraw only while the cursor glow settles). `GlowTitle`: letters fade in (0.07 s stagger),
    then a slow pulse; glow = layered `draw_char_outline` with an additive material.
    `GlowButton` (script on Buttons): theme hover/focus StyleBoxes with a shadow halo, swell and
    press punch via the 4.7 `offset_transform_*` (no re-layout), ripple ring on press.
  - Mission select: `ChapterHeader` (procedural Voronoi cell-membrane shader
    `chapter_header.gdshader`, seed and accent per chapter) + `MissionMap` (missions on a gentle
    wave, dendrites lit/open/dim by state, ambient pulse on lit ones). Selecting plays a 0.45 s
    dendrite pulse, then emits `mission_selected` (instant with reduced motion; repeat presses
    ignored meanwhile).
  - Summary: panel eases in, title re-reveals, stars light one by one with a pop
    (`Hud.star_revealed(i)`), moves/time count up, `light_sweep.gdshader` wave crosses the screen.
    `StarRow` separates score (`stars`) from `lit`. Pause/settings use the same glowing panel,
    `GlowTitle` and `GlowButton`s; HUD labels get a soft glow outline.
  - Transition: `iris_fade.gdshader` on the Fade rect; its color alpha stays the progress, so the
    Transition logic and tests are unchanged.
  - Test change: `tests/ui/test_hud.gd` now pins reduced motion (the stats count up); the animated
    path is covered by `tests/ui/test_summary.gd`.
- **T4.6** (test-first: RED = missing `Synth`, then GREEN).
  - `Synth` (pure PCM: tone with harmonics/glide/attack/decay/release, seeded soft noise, mix,
    normalize, seamless `loop_tone`/`drone`, 16-bit `to_stream`), `SoundBank` (recipes + static
    cache): ambient drone (8 s loop at 11025 Hz: 55 Hz + fifth + 0.125 Hz-detuned octave + swelling
    upper fifth), grab 620→880 Hz blip, release 880→560 Hz, blocked tick (noise + 1.4 kHz click),
    tension 1 s loop 330 Hz with 6 Hz tremolo, snap (noise + 900→160 Hz), crossing chime (bell:
    fundamental + 2.76x partial), completion A-major arpeggio, star bell ping, UI hover/click.
  - `AudioDirector` is a **scene-local node under Main, not an autoload** (SDD 8.4: only
    GameState). `ScreenHost.audio` hands it every new screen: `bind_ui` (any BaseButton: click,
    hover/focus with a 0.25 s quiet window after binding) or `bind_level` (InputController grab/
    release, model blocked/crossings/tension/break, completion, `Hud.star_revealed`).
    `LevelController.model_built` lets it rebind after restarts; `Level.get_input_controller()`.
    Tension tone: silent below ratio 0.3, pitch 0.7→2.0 (quadratic), −30→−9 dB, stops on release/
    break/completion. Buses Music/SFX in `default_bus_layout.tres` (feed Master = settings volume).
  - Synthesis costs ~0.49 s of GDScript (chord 0.26 s), so streams render on a
    `WorkerThreadPool` task (pure code, no scene access), polled and handed over on the main
    thread (`sounds_ready`), then the drone fades in over 3 s.
  - Headless: the Dummy driver never mixes, so started playbacks were reported as leaked at exit;
    the director skips the actual `play()` under the headless display server (logic, signals and
    parameters unchanged) and stops all voices on exit.
  - Not done (optional): separate Music/SFX sliders in Settings.
- **T4.7** Perf, windowed, GL Compatibility, Intel UHD 600, vsync off, 5 s after 60 warm-up frames
  (`capture_level.tscn` perf/perf_drag on m02, `capture_screens.tscn ... perf`):

  | Scene | Before the T4.7 fixes (fps / frame avg / draw calls) | After |
  |---|---|---|
  | Level m02 idle | 225 / 4.44 ms / 33 | 225 / 4.44 ms (p99 6.1, max 7.4) / 33 |
  | Level m02 dragging | 174 / 5.75 ms / 33 | 175 / 5.71 ms (p99 7.2, max 8.3) / 33 |
  | Main menu | 177 / 5.66 ms / 142 | 188 / 5.32 ms (p99 7.2) / 44 |
  | Mission select | 183 / 5.47 ms / 84 | 193 / 5.18 ms (p99 7.0) / 48 |
  | Level summary (wave + sweep) | 116 / 8.66 ms / 96 | 119 / 8.39 ms (p99 12.2) / 49 |

  Fixes: separate glow-sprite and untextured passes in `_draw` (batching), title outline drawn
  layer by layer, neuron/dendrite views push only changed uniforms, membrane displaced buffer
  reused, HUD time reformatted once per second. Idle redraws: neurons/dendrites never redraw when
  idle (shader TIME); membranes, menu network, titles and lit map segments redraw per frame only
  with motion on (intended animation); hidden titles skip work. `Performance.TIME_PROCESS` is not
  reported: the engine refreshes it once per second, so frame times come from wall-clock ticks.
  WorldEnvironment glow re-checked (`glow` and `glow_alt`: additive, finest 2 levels, threshold
  1.0): checkerboard artifact on this GPU in both, so it stays off (look = additive/premultiplied
  blending). Other GPUs not available here.
- Visual checks (windowed captures, all reviewed): main menu (motion and reduced), settings,
  mission select, completed summary, pause, level m02, glow experiments.
- Verification (final): `./run_tests.ps1` → 326 test cases, 0 failures, exit 0;
  `godot --headless --path . --import` → exit 0, no errors; `godot --headless --path . --quit-after
  300` → exit 0, no errors or leak warnings; `godot --path . --quit-after 240` (windowed) → exit 0,
  no errors.

Next: phase 4 complete; Phase 5 content (T5.1). Review slice base for run 4b: `33099fd`.

Engram mirror: pending (engram MCP unavailable in runs 4a and 4b).

- Review 4b: slice `8c183a4..6e67a3e` medium, `slice_budget_reached` (3169 lines); user **declined** (candidate-scoped). Parent spot check `./run_tests.ps1` -> 326 cases, exit 0. Next slice base: `6e67a3e`.

## Neuron shape

Decision (revised twice): the first attempt (convex blob, then blob plus faint wisps) read as a
slime, so neurons are now classic multipolar neurons, modeled on the Wikimedia Commons illustration
"Blausen 0657 MultipolarNeuron" (visual reference only, not in the repo): a small angular soma with a
visible nucleus, thick-rooted tapered dendrites that slim quickly and fork (Y) one or two times with
the odd side twig, and one thin, nearly straight axon ending in a bulb or 2-3 end-feet. Concave
regions between processes are wanted.
- `NeuronMorphology` (scripts/views/neuron_morphology.gd) generates everything once per neuron from its
  id (deterministic) in model radii: soma about 0.55-0.66, 3-6 primary dendrites by kind, tips never
  beyond 1.5 (families are scaled down otherwise). Kinds: normal; fixed (stockier soma, short thick arms,
  no twigs); receptor (3-4 shorter arms; ReceptorView's searching stub is a tapered tendril); toxic
  (sharper soma corners, straighter spikier arms).
- Link bias: NeuronView passes the angles to its linked neighbours (edge list, longest first) once at
  setup; the axon grows towards the longest link and dendrites towards the next ones, the rest fill the
  largest gaps. The model is untouched; moving neurons keep their arms.
- Rendering: the soma stays one shader quad (`neuron.gdshader`: soma_profile() gives a corner towards
  each process, nucleus disc with darker rim, all halo/crossing/overload/contact effects) and the
  processes are one feathered triangle mesh per neuron, drawn first in the same canvas item with the same
  material (told apart by vertex COLOR.g; no child node, so no orphan nodes): 2 draw commands per neuron,
  no per-frame allocation. Only the vertex shader animates the mesh (tips sway,
  overload tremble); the soma breathes slightly; reduced motion is static.
SYNC: NeuronMorphology.SOMA_BASE / CORNER_CAP / SOMA_BREATH / SOMA_BREATH_SPEED / SWAY and the soma
formula mirror the shader; tests compare the constants and hand-computed reference values.
