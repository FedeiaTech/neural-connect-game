# Neural Connect — Software Design Document (SDD)

Status: Draft v0.1 — 2026-10-06
Engine: Godot 4.7 (GL Compatibility), GDScript, 2D.

## 1. Concept

A puzzle game. The screen shows neurons (nodes) the player can drag with the mouse.
Some neurons are linked by dendrites (edges). The player must rearrange the neurons so
that **no dendrite crosses another one**, like untangling bare cables.

Visual identity: black background, white neurons and white boundary, red fixed neurons.

## 2. Core rules

1. Neurons are draggable circles. Dendrites are **straight segments** between two neurons.
2. A dendrite's visual length follows the distance between its neurons (elastic look,
   no physical resistance).
3. Two dendrites **cross** when their segments intersect. Dendrites sharing a neuron
   never count as crossing at that shared point.
4. The level is **complete when there are zero crossings**.
5. Neurons cannot leave the play area (boundary, see 5.3).

### 2.1 Dragging collisions (mixed model)

- Neuron vs neuron: **solid**. Neurons cannot overlap each other. The dragged neuron
  **stops at the contact point** (no pushing, no sliding) but **stays grabbed**: it keeps
  following the mouse again as soon as the cursor moves to a free position.
- Neuron vs dendrite: **free**. A neuron may pass over other dendrites; any resulting
  crossing is simply flagged as an error.

## 3. Element types

| Element | Appearance | Behavior | Introduced |
|---|---|---|---|
| Normal neuron | White | Draggable | Level 1 |
| Fixed neuron | Red | Not draggable, still blocks other neurons | Advanced levels |
| Multi-dendrite neuron | White | Neuron with 2+ dendrites | Early/mid levels |
| Normal dendrite | White line | Unlimited stretch (visual only) | Level 1 |
| Tension dendrite | Light green line | Has a max length; thins as it stretches; **breaks at the limit → level restarts** | Advanced levels |

Tension dendrite details:
- Thickness interpolates from normal to a minimum as length goes from rest length to max length.
- At max length it breaks. The drag that caused it is canceled and the level restarts.
- Max length and rest length are per-dendrite data in the level file.

## 4. Feedback

- Crossing dendrites are highlighted (e.g. color change or blink), **and** the neurons at
  both ends of those dendrites are highlighted too.
- Feedback is a per-level/per-mode flag so harder modes can disable it later.
- Level complete: a clear visual/audio confirmation, then star summary.

## 5. Playfield

### 5.1 Resolution
Base viewport fixed, stretch mode `canvas_items`, aspect kept, so the same layout works
on other platforms later.

### 5.2 Input
- MVP target: **PC with mouse**.
- Input is written with touch in mind: a generous grab radius around each neuron and
  handling through `InputEventMouse*` plus a touch-compatible path, so mobile needs no redesign.

### 5.3 Boundary and obstacles (per-level shapes)
- Each level defines its own play area **shape** (rectangle, L-shape, ring, irregular polygon...)
  and optional **obstacles** inside it (solid polygons/islands, same white thick outline).
- Obstacles block neurons exactly like the boundary does (neurons stop at contact, stay grabbed).
- Obstacles do **not** block dendrite crossings: a dendrite may pass over an obstacle
  (it only matters for neuron placement). Revisit if a level wants obstacles to block lines.
- The play area is a polygon with holes: neurons must stay inside the outer polygon and outside every obstacle.
- White frame, drawn with a thicker line than the dendrites.
- Rendered as a living **membrane**: a slow breathing/undulation of the outline and a soft
  glow. The animation is cosmetic; the **collision shape is a fixed per-level polygon**, so
  the rules stay deterministic.
- When a neuron touches the boundary the membrane reacts locally (ripple/bulge at the contact point).
- Neuron centers are clamped so the whole circle stays inside the boundary.
- Boundary shape/size comes from `LevelData` (a rectangle by default; other shapes possible later).

## 5.4 Art direction and atmosphere

Mood: a dark, quiet, bioluminescent microscopic world. The palette stays strict
(black, white, red, light green) and the beauty comes from light, motion and sound.

- **Background:** pure black base with a very subtle drifting layer of faint particles
  (floating cells/spores) and a soft vignette. Never competes with gameplay readability.
- **Neurons:** white soma with a soft glow (additive bloom), a gentle idle pulse, and a
  small organic wobble. Grabbing one brightens it and scales it slightly; red fixed neurons
  have a slower, heavier pulse.
- **Dendrites:** thin glowing lines with a faint electrical pulse traveling along them.
  Aesthetic is isolated from logic (see 8.1) so it can later switch to curved/organic branches.
- **Tension dendrites:** light green, thinning and trembling as they near the limit, with a
  rising warning flicker; the break plays a snap flash and particle burst.
- **Crossing feedback:** involved dendrites and their neurons pulse/flicker; it calms down smoothly when resolved.
- **Level complete:** a wave of light travels through the whole network, the membrane
  exhales, then the star summary appears.
- **Juice:** easing on every transition, soft screen-wide glow (WorldEnvironment glow is
  available in GL Compatibility; verify on target platforms), and a light screen shake only on tension-dendrite break.
- **Audio (target):** ambient drone, soft synaptic "blips" on grab/release, a rising tone
  as tension increases, a resolved chord on completion.
- **Performance:** keep effects cheap (CPU/GPU particles with low counts, simple shaders) so
  the same look runs on mobile later.

## 5.5 Menus and screens

Every menu is fully interactive, animated and illustrated, in the same bioluminescent style
as the playfield. No static, plain menus.

- **Screens:** Main menu, Mission select (chapters), Level summary (stars), Settings, Pause.
- **Main menu:** living background (drifting neurons connected by pulsing dendrites that react
  to the cursor), animated title, buttons that glow and ripple on hover/press.
- **Mission select:** a map-like network of neurons, each mission is a node; completed ones
  glow with their stars, locked ones are dim. Chapters have their own illustrated header/image.
  Selecting a node animates a dendrite pulse before loading.
- **Level summary:** stars light up one by one with sound, moves/time count up, a light wave
  runs across the screen.
- **Transitions:** animated fade/pulse between screens (`Transition` layer), never a hard cut.
- **Art source:** **no external images**. All visuals are generated in Godot: procedural
  drawing (`_draw()`, `Line2D`, polygons), shaders (glow, noise, membrane distortion, chapter
  backdrops), and particles (`GPUParticles2D` / `CPUParticles2D`). Chapter headers and
  backgrounds are shader/procedural compositions, each chapter with its own seed/pattern, using
  the palette in 5.4. Fonts: use a Godot-bundled or system-safe option, or a licensed font added later.
- **Input:** all menus work with mouse now and with touch/gamepad focus later (focus-friendly layout).
- Built with `Control` nodes and containers, themed through a single `Theme` resource, with
  tweens for motion; menu motion respects a "reduced motion" setting.

## 6. Scoring

- A **move** = one complete drag (grab to release) of a neuron.
- Per level data: `par_moves` and `par_time`. Stars combine moves **and** time.
- MVP thresholds are intentionally generous and will be tuned later.
- Time is also stored as a personal best.

Initial rule (to tune):
- 3 stars: moves <= par_moves AND time <= par_time
- 2 stars: moves <= par_moves * 1.5 AND time <= par_time * 1.5
- 1 star: completed

## 7. Levels

- **All levels are hand-designed and fixed.** No procedural generation (supersedes the earlier
  "mixed" idea). Each level is authored individually: play area shape, obstacles, neurons,
  dendrites, starting (tangled) positions, par values and missions.
- Every level must be verified solvable by its author (a known solution layout is stored in the
  level data and used for validation/hints).
- Start with 4 neurons. Difficulty ramp: more neurons → multi-dendrite neurons → obstacles and
  irregular shapes → fixed red neurons → tension dendrites → combinations.

## 7.1 Missions

A **mission** is a fixed, hand-designed story level. The game is a campaign made only of
missions; there are no randomly generated levels.

Structure:
- Missions are numbered and played in a fixed order, grouped into **chapters** (themed sets,
  each introducing or combining mechanics: multi-dendrite, obstacles/shapes, red fixed neurons,
  tension dendrites).
- Each mission has an id, a name, its chapter, and its own `LevelData` (see 8.2).
- A mission selection screen shows completion state and stars per mission.
- Completing a mission unlocks the next one. Chapter unlock rules beyond that are undecided.
- **Story presentation:** minimal narrative. A short text (a line or two, poetic/scientific tone)
  appears only every 2–3 missions, not on every one. Each mission may carry an optional
  `story_text`; the author sets it only on the missions that trigger text. It is shown on
  mission start, over the playfield, and dismissed with a tap/click.

## 8. Technical design

### 8.1 Architecture
- Logic is separate from rendering: crossing detection works on data (positions + edge list),
  drawing only reads it. This allows changing dendrite aesthetics (curves, glow, pulse)
  without touching rules.
- Signals up, calls down. A small enum state machine for game state:
  `PLAYING`, `COMPLETE`, `RESTARTING`.

### 8.2 Data
- `LevelData` custom `Resource` (`.tres`): play area polygon, obstacle polygons, neurons
  (id, position, type), dendrites (neuron ids, type, max length), reference solution positions,
  feedback flag, `par_moves`, `par_time`, mission id/name, chapter id, optional `story_text`.
- Levels are authored by hand (ideally editable in the Godot Inspector/editor).

### 8.3 Crossing detection
- Test every pair of dendrites that do not share a neuron using
  `Geometry2D.segment_intersects_segment`.
- Cost is O(E²), which is fine for the expected level sizes. Recomputed while dragging.

### 8.4 Scene tree (approved)

Architecture decision: **pure data model + views**. `PuzzleModel` (`RefCounted`, no nodes) owns
all rules; views only draw. Rejected alternative: logic spread across nodes (faster to start,
but untestable and couples rules to aesthetics).

```
Main (Node)
├── ScreenHost (Node)            # loads/unloads MainMenu, MissionSelect, Level
└── Transition (CanvasLayer)     # animated transitions between screens

Level (Node2D)                   # one mission
├── Background (Node2D)          # particles, vignette
├── Playfield (Node2D)
│   ├── Boundary (Node2D)        # animated membrane (outer edge)
│   ├── Obstacles (Node2D)       # one ObstacleView per polygon
│   ├── Dendrites (Node2D)       # one DendriteView per edge
│   └── Neurons (Node2D)         # one NeuronView per neuron
├── InputController (Node)       # translates mouse/touch into model calls
├── LevelController (Node)       # owns PuzzleModel, state, scoring
└── HUD (CanvasLayer)            # moves, time, restart, story text

PuzzleModel (RefCounted)         # positions, edges, crossings, tension
LevelData (Resource, .tres)      # mission data (see 8.2)
Progress (Resource)              # stars and completed missions (local save)
```

- `LevelController` creates `PuzzleModel` from `LevelData` and is its only owner.
- `NeuronView`, `DendriteView`, `ObstacleView` are separate reusable `.tscn` scenes.
- The only autoload is `GameState` (saved progress, current mission). No global EventBus:
  signals go up, calls go down.

### 8.5 Signal map

`PuzzleModel` → views / controller:

| Signal | Payload | Listener | Purpose |
|---|---|---|---|
| `neuron_moved` | `id: int, pos: Vector2` | `NeuronView`, `DendriteView` | Reposition and redraw |
| `neuron_blocked` | `id: int, contact: Vector2` | `NeuronView`, `Boundary` | Contact effect, membrane ripple |
| `crossings_changed` | `crossing_edges: Array[int], involved_neurons: Array[int]` | `DendriteView`, `NeuronView` | Highlight or calm feedback |
| `tension_changed` | `edge_id: int, ratio: float` | `DendriteView` | Thin and tremble the green dendrite |
| `edge_broke` | `edge_id: int` | `LevelController` | Trigger restart |
| `solved` | none | `LevelController` | Close the level |

`InputController` → model (direct calls, not signals): `model.grab(id)`, `model.drag_to(pos)`,
`model.release()`. Each `release()` counts one move.

`LevelController` → up:

| Signal | Payload | Listener |
|---|---|---|
| `move_count_changed` | `n: int` | `HUD` |
| `time_changed` | `seconds: float` | `HUD` |
| `level_completed` | `result: LevelResult` (moves, time, stars) | `ScreenHost` |
| `level_restart_requested` | none | `ScreenHost` |

Others: `restart_pressed` (HUD → `LevelController`), `mission_selected(id)` (`MissionSelect` →
`ScreenHost`), `story_dismissed` (HUD → `LevelController`, which starts the timer afterwards).

### 8.6 Data flow

1. **Load mission:** `MissionSelect` emits `mission_selected(id)` → `ScreenHost` sets
   `GameState.current_mission` and loads `Level` → `LevelController` reads `LevelData`, builds
   `PuzzleModel` and one view per neuron/dendrite/obstacle. If the mission has `story_text`,
   the HUD shows it and the timer waits for `story_dismissed`.
2. **A full drag:**
   1. `InputController` detects the press near a neuron (generous grab radius) → `model.grab(id)`.
      Red (fixed) neurons are ignored by the model.
   2. On each mouse move → `model.drag_to(pos)`. The model resolves: outer boundary and obstacles,
      then other neurons. On collision it leaves the neuron at the contact point, emits
      `neuron_blocked`, and the neuron stays grabbed.
   3. The model emits `neuron_moved`, recomputes crossings (segments that do not share a neuron)
      and tension, and emits `crossings_changed` / `tension_changed`.
   4. If a tension dendrite reaches max length → `edge_broke` → `LevelController` restarts.
   5. On release → `model.release()` adds one move; with zero crossings the model emits `solved`.
3. **Complete:** `LevelController` stops the timer, computes stars from `par_moves` / `par_time`,
   emits `level_completed(result)`. `ScreenHost` stores it in `GameState` and shows the star summary.
4. **Restart:** from the button or a broken dendrite. `LevelController` rebuilds the model from
   `LevelData` and resets counters, without reloading the scene.

Data ownership: positions, crossings, tension → `PuzzleModel`; moves and time →
`LevelController`; progress and stars → `GameState`. Nothing is duplicated.

### 8.7 Testing
- `PuzzleModel` has no nodes, so crossings, collisions, tension, scoring and solvability
  (reference solution has zero crossings) are unit-tested headless with **gdUnit4** (decided).

## 8.8 Technical constraints

- Godot 4.7, GL Compatibility renderer: shaders and glow must be verified on this renderer
  and kept cheap for future mobile export.
- Visuals come entirely from code, shaders and particles (no texture assets).

## 9. Out of scope for MVP

- Mobile export and touch tuning
- Level editor tooling beyond the Godot editor
- Curved/organic dendrite shapes (straight glowing lines in MVP)
- Disabling crossing feedback for hard modes
- Final audio and art polish (MVP gets a first pass of 5.4 on the core effects)

## 10. Assumptions to confirm

- GDScript only.
- The boundary is an animated membrane with a fixed collision shape (not a boundary that moves or shrinks as a mechanic); "dynamic" also means different shapes and obstacles per level.
- Obstacles block neurons but not dendrites.
- Missions = fixed story levels (campaign). Unlock rules between chapters are undecided.
- Story text appears every 2–3 missions at mission start (exact placement/skip rules to tune).
- Restart button available in every level.
- Level progress and stars are saved locally (format to decide when persistence is built).
