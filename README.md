# Neural Connect

A 2D puzzle game about untangling a living neural network. Drag the neurons so that no dendrite
crosses another, and let the signal through.

Made by **Federico Iacono** at **Chainsaw Games - iaTech**.

- Engine: Godot 4.7, GDScript only. Desktop uses the GL Compatibility renderer; Android uses
  Vulkan (Forward Mobile), because the OpenGL ES driver of the test device (Mali-G52) crashed with
  SIGSEGV. To go back, set `renderer/rendering_method.mobile` to `gl_compatibility`.
- Platforms: Windows (desktop) and Android (touch-first layout)
- Content: 48 hand-designed missions in 9 chapters, each ending in a boss
- Languages: English and Spanish
- Art and sound: generated entirely with code, shaders and particles

## Game

- Win a mission by reaching zero dendrite crossings; crossing dendrites and their neurons are
  highlighted live.
- Neurons are solid against each other, obstacles block them, and some missions add fixed (red)
  neurons, tension dendrites that break when over-stretched, lethal walls, receptors, toxic
  neurons and diseased dendrites.
- Stars are earned for moves and time.
- Settings: master volume, reduced motion, language and a low memory mode (no background spores,
  still crossing sparks, smaller particle bursts, trimmed neuron shading).
- The same project serves both platforms: on mobile the UI uses larger touch targets, a more
  generous grab radius and a paged, swipeable mission map. Preview it on a PC with
  `godot --path . -- --mobile-ui`.

## Run

Requires Godot 4.7.

```
godot --path . 
```

## Tests

Tests use [gdUnit4](https://github.com/MikeSchulze/gdUnit4) (bundled in `addons/`).

```
./run_tests.ps1
```

## Project layout

| Path | Content |
| --- | --- |
| `scripts/model` | Pure puzzle model (`PuzzleModel`), no nodes or drawing |
| `scripts/views`, `scripts/ui`, `scripts/screens` | Views and screens; logic stays separate from drawing |
| `scripts/platform` | Per-platform UI profile (desktop / mobile) |
| `scripts/autoloads` | `GameState` (progress, settings) and `ExitReport` (diagnostics) |
| `data`, `tools` | Mission data and the level build tooling |
| `locale` | Translations (`translations.csv`) |
| `brand` | Studio logo |
| `docs` | Design document and implementation plan |

## Diagnostics

If the app closes unexpectedly, the next launch shows a report (device, a one-second heartbeat with
process and GPU memory, key events, the tail of the engine log and, on Android, the system's own
exit reason) with a button to copy it. It is also written to `exit_report.txt` in the app's user
folder. After an abnormal close on a device, the next launch turns on low memory mode (it skips the
extra shaders and particles) and says so in the report; it can be switched off in Settings.

Settings > Diagnostics runs an automatic battery (about six minutes, `scripts/diagnostics`) that
isolates each suspect of a native crash in its own step and survives the crash: the next launch marks
the step the app died in as crashed and continues with the next one. It ends with a matrix report
(also written to `diagnostics_report.txt` and the Downloads folder) that can be copied.

## Credits

Developed by Federico Iacono.

Copyright © 2026 Chainsaw Games - iaTech. All rights reserved.
