# Version history

Newest first. The version shown on the main menu (`v1.03`) comes from `application/config/version` in
`project.godot`; the Android preset (`export_presets.cfg`) keeps the same name and an increasing
version code. Exported APKs are named `NeuralConnect-<version>.apk`.

## 1.04 (2026-10-13) - Diagnostic battery

- New Settings > Diagnostics: about six minutes of automatic checks that each isolate one suspect of
  the native crash (bare app, menu, triangle-array drawing, meshes, neuron and dendrite shaders,
  whole mission, simulated play, particles, every sound, audio loops, synthesis worker threads, iris
  transition, mission map, studio logo, screen changes with and without audio, and two manual steps
  where the player touches the screen).
- It survives the crash it is hunting: each step is written to disk before it starts, so after the
  app dies the next launch records the step as CRASHED (with how long it ran and the process uptime)
  and continues with the next one by itself. Open the app again, nothing else to do.
- The final report is a matrix of steps (OK / CRASHED / SKIPPED with fps and memory), hints (a time
  pattern between crashes, touch input) and a device block (renderer, GPU, audio, display). It is
  saved to the app folder and Downloads, with a Copy button.
- The exit report reads the readable part of the system tombstone of a native crash (library and
  function names) and shows it in a "Native crash trace" section.
- A run in progress suppresses the exit-report overlay and the automatic safe visuals, so the
  battery is not disturbed.

## 1.03 (2026-10-12) - Vulkan on Android

- Android now renders with Vulkan (Forward Mobile) instead of OpenGL ES. Desktop keeps GL
  Compatibility. Reason: the OpenGL ES driver of the test phone (Moto G15, Mali-G52) crashed the app
  with a native SIGSEGV.
- The exit report states the active renderer (`renderer=mobile/vulkan`).
- The debug APK is named after the version.
- To go back to OpenGL: set `renderer/rendering_method.mobile` to `gl_compatibility`.

## 1.02 (2026-10-12) - Crash diagnostics

- The exit report reads Android's own record of why the previous process died (reason, signal,
  memory at death).
- After an abnormal close on a mobile device, the next launch turns on the low memory mode
  automatically and says so in the report.
- The start line of each session records the visual modes in use.
- Low memory mode also skips the background, transition, chapter header and completion light
  shaders.

## 1.01 (2026-10-12) - Version label and richer report

- Main menu shows the app version.
- Exit report: heartbeat every second with GPU memory, object, node and draw call counts; key events
  section; tail of the engine log; readable Android version; wrapped text in the overlay.
- Low memory mode in Settings: hides the background spores, makes crossing sparks static and reduces
  particle bursts.

## 0.1.0 (2026-10-11) - First Android build

- Touch profile: larger buttons and fonts, bigger grab radius for neurons.
- Mission map for mobile: no scrollbar, paged chapters with a glide transition, locked chapters
  hidden.
- Studio splash after the Godot one, and a credits screen.
- Exit report shown after an abnormal close, with a copy button.

## Known issues

- 0.1.0 to 1.02 (OpenGL ES): the app can close about 20 seconds after launch on the Moto G15 with
  `CRASH_NATIVE` / SIGSEGV. 1.03 switches the renderer to test whether the driver is the cause.
