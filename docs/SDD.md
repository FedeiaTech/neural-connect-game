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
4. The level is **complete when there are zero crossings** (dendrites and dynamic receptor
   links, see 3) **and every receptor holds its required links**, checked on release.
5. Neurons cannot leave the play area (boundary, see 5.3).
6. **Lethal walls** (T7.2): a neuron that touches a lethal play-area side or lethal obstacle
   stops at the contact, overloads and is destroyed: the level is lost and restarts after the
   explosion (like a tension break). Non-lethal geometry keeps blocking as before.

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
| Lethal wall | Electric violet membrane with magenta crackle | Play-area side (`LevelData.lethal_edges`) or obstacle (`lethal_obstacles`); touching it destroys the neuron → level lost, quick restart; glows and an alarm rises as a grabbed neuron approaches (warning range 2 radii) | Chapter 5 Live Wires |
| Receptor neuron | Cyan soma, pulsing reach halo, searching stub, one dot per required link | Immovable; `reach` and `required_links` (1 or 2); links the closest movable neuron(s) in reach | Chapter 6 Synapses |
| Receptor link | Cyan line grown from the receptor | Dynamic: forms when a movable neuron enters reach (center distance − radius ≤ reach), breaks when it leaves (not a loss); thins and flickers near the limit; counts as a dendrite for crossings | Chapter 6 Synapses |
| Toxic neuron | Lemon-yellow soma with a faint pulsing warning glow | Movable like a normal neuron; never a link candidate. Inside a receptor's reach it forms a **contamination link** (yellow dashed line with a warning triangle, alarm beeps, HUD hint) that does not count towards `required_links`, is only a warning (never a crossing, never a loss) and blocks the win until the toxic neuron leaves the reach | Content in run B (T8.4+) |
| Diseased dendrite | Dark orange ember line that thins, heats, trembles and cracks near its limit | `max_length` / `rest_length` like a tension dendrite, but **stretching it past `max_length` breaks it on purpose**: it disappears (no more crossings), sparks and a snap sound play, never a loss; broken stays broken until restart; the win needs every diseased dendrite broken (HUD counter "Diseased: n/m") | Content in run B (T8.4+) |

Receptor link rule: after every move each receptor drops links whose neuron left its reach, then
links the closest in-reach candidates (ties: lower id) until it has `required_links`. Candidates
are movable (not fixed, not receptors), not yet linked to that receptor and not statically
connected to it. Links are identified as `(receptor_id, neuron_id)`; they never get an edge id.

Toxic neuron rule (T8.2, SOFT): after every move the model recomputes, per receptor, the toxic
neurons in reach (same distance rule as links). They form a separate sorted set of contamination
links keyed `(receptor_id, neuron_id)`; a static dendrite between the two does not prevent it.
They use no slot, are not segments for crossing detection and never end the level. Signals:
`contamination_formed` / `contamination_cleared`; queries `is_contaminated()`,
`get_contamination_links()`. Win on release = zero crossings + every receptor satisfied by
non-toxic neurons + zero contamination links. A toxic neuron in a level without receptors is a
harmless decoy (allowed). Validation: start and solution layouts must have no contamination, a toxic
neuron is never fixed. A HARD variant (explode + restart) is reserved for boss missions.

Diseased dendrite rule (T8.3): `DendriteData.Kind.DISEASED`. When a move leaves an intact diseased
edge longer than `max_length` it joins the broken set (`diseased_broken(edge_id)`); a broken edge is
skipped by crossing detection, keeps its edge id and stays broken for this model (restart rebuilds
it). Strain uses `diseased_strain_changed`, separate from `tension_changed`. Validation: start
length <= `max_length` and solution length > `max_length` (the models built with `use_solution`
start with those edges broken, so solution crossings of a broken edge do not count).

Tension dendrite details:
- Thickness interpolates from normal to a minimum as length goes from rest length to max length.
- At max length it breaks. The drag that caused it is canceled and the level restarts.
- Max length and rest length are per-dendrite data in the level file.

## 4. Feedback

- Crossing **normal dendrites turn red** (a bright warm red, distinct from the deeper red of a
  fixed neuron's soma) while they cross; **tension dendrites stay green** and receptor links
  stay cyan. Every crossing line stays a plain solid line with its normal glow (no pattern).
  A crackling **spark marker** sits on every exact crossing point (one per crossing pair; the
  midpoint for collinear overlaps). The neurons at both ends keep their soma color and get a
  soft, slowly breathing warm "latency" glow with a light sparkle around the soma, never a
  tint that could read as a red fixed neuron. A soft electric buzz loops while crossings exist.
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
(black, white, red, light green, plus red crossing lines with amber sparks, violet lethal walls and cyan
receptors since Phase 7) and the beauty comes from light, motion and sound.

- **Background:** pure black base with a very subtle drifting layer of faint particles
  (floating cells/spores) and a soft vignette. Never competes with gameplay readability.
- **Neurons:** white soma with a soft glow (additive bloom), a gentle idle pulse, and a
  small organic wobble. Grabbing one brightens it and scales it slightly; red fixed neurons
  have a slower, heavier pulse.
- **Dendrites:** thin glowing lines with a faint electrical pulse traveling along them.
  Aesthetic is isolated from logic (see 8.1) so it can later switch to curved/organic branches.
- **Line smoothing:** every line is antialiased. Dendrite cores feather over about one screen
  pixel (fwidth-based AA in the shader); thin lines, arcs and circles use Godot's antialiased
  draw calls; wide glows (membranes, lethal walls, receptor links) are soft bands that fade to
  zero at their edges with mitered corners (`SoftLine`), and spark-marker glows are one radial
  gradient sprite. 2D MSAA is not used: Godot 4.7 reports it unsupported on GL Compatibility.
- **Tension dendrites:** light green, thinning and trembling as they near the limit, with a
  rising warning flicker; the break plays a snap flash and particle burst.
- **Crossing feedback:** involved normal dendrites fade to red (tension stays green, links
  cyan), drawn as solid lines; spark markers crackle at each crossing point (static stars with
  reduced motion); involved neurons breathe a soft warm glow with a light sparkle (a static
  warm tint, no sparkle, with reduced motion); everything calms down smoothly when resolved.
- **Lethal walls:** violet membrane with magenta lightning crackling along it, glowing
  stronger (and a hot spot on the nearest wall point) as a grabbed neuron approaches; on
  contact the neuron trembles and burns violet-white, then explodes (particles, flash, shock
  ring, light shake) before the restart.
- **Receptors:** cyan soma, soft pulsing halo at the reach limit, a searching stub swaying
  towards the nearest candidate and link dots. A link grows from the receptor with a cyan flash;
  near the limit it thins and flickers; a broken link stretches, trembles and snaps with sparks.
  The completion wave also travels through the links.
- **Level complete:** a wave of light travels through the whole network, the membrane
  exhales, then the star summary appears.
- **Juice:** easing on every transition, soft screen-wide glow (WorldEnvironment glow is
  available in GL Compatibility; verify on target platforms), and a light screen shake only on tension-dendrite break.
- **Audio (target):** ambient drone, soft synaptic "blips" on grab/release, a rising tone
  as tension increases, a resolved chord on completion; a soft electric buzz while crossings
  exist (volume follows the count, capped), a rising alarm near lethal walls and an overload
  explosion, an ascending synaptic click when a receptor link forms and a small snap when it
  breaks. All synthesized (Synth/SoundBank).
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
- **Settings:** master volume, reduced motion, language (5.6) and **Reset progress** (inline
  confirmation; clears every mission record, keeps the settings).
- **Progress reset per mission:** in Mission select, hovering/focusing a completed mission shows
  a small "Reset record: mission N" button (also Delete on a focused mission, or right-click);
  after an inline confirmation only that mission's record is cleared and the map refreshes.
  Later missions that were completed stay unlocked. In-level restart stays as before: HUD
  Restart button (tooltip names the R key), R key and pause-menu Restart.

## 5.6 Localization

- Languages: English (`en`) and Spanish (`es`, neutral register, "tú" imperatives).
- One Godot CSV translation table, `locale/translations.csv` (`keys,en,es`, semantic
  UPPER_SNAKE keys), registered in Project Settings. Its importer writes
  `locale/translations.{en,es}.translation`, which are committed (the project loads them).
- Scenes and data hold keys: UI texts, and the campaign content (`LevelData.mission_name` /
  `story_text`, `ChapterData.title` / `subtitle` = `MISSION_<ID>_NAME` / `_STORY`,
  `CHAPTER_<n>_TITLE` / `_SUBTITLE`). Formatted texts use `tr("KEY") % value` and are rebuilt on
  `NOTIFICATION_TRANSLATION_CHANGED`; custom-drawn text (`GlowTitle`) draws `atr(text)`.
- The language is a setting (`settings.language` in the save). Default when absent or invalid:
  Spanish if the OS language is Spanish, English otherwise. Switching in Settings updates the
  whole UI live, no restart. The game name "Neural Connect" is not translated.

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
  irregular shapes → fixed red neurons → tension dendrites → lethal walls → receptor neurons →
  combinations.
- Chapters (30 missions, ids `m01`..`m30` in campaign order): 1 First Signals (m01–m05),
  2 Shaped Minds (m06–m10), 3 Anchored (m11–m14), 4 Tension (m15–m18), 5 Live Wires (m19–m21),
  6 Synapses (m22–m25), 7 Convergence (m26–m30, every mechanic including receptors and lethal
  walls). The old Convergence missions m19/m20/m21 became m26/m28/m30; save format v2 migrates
  their records.
- Difficulty curve (content tests): a start may have at most 14 crossings more than the hardest
  of the three missions before it; the first mission of a new-mechanic chapter starts with at
  most 6; the most tangled start is in Convergence. New-mechanic chapters may restart with
  smaller networks (mean size never below Shaped Minds).

## 7.1 Missions

A **mission** is a fixed, hand-designed story level. The game is a campaign made only of
missions; there are no randomly generated levels.

Structure:
- Missions are numbered and played in a fixed order, grouped into **chapters** (themed sets,
  each introducing or combining mechanics: multi-dendrite, obstacles/shapes, red fixed neurons,
  tension dendrites, lethal walls, receptor neurons).
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
  `PLAYING`, `COMPLETE`, `RESTARTING`. A loss (`LevelController.LossReason`: `TENSION_BREAK`
  or `OVERLOAD` from a lethal wall) emits `level_lost(reason)` and restarts after the reason's
  delay (0.6 s break, 1.2 s overload explosion).

### 8.2 Data
- `LevelData` custom `Resource` (`.tres`): play area polygon, obstacle polygons, neurons
  (id, position, type), dendrites (neuron ids, type, max length), reference solution positions,
  feedback flag, `par_moves`, `par_time`, mission id/name, chapter id, optional `story_text`.
- Hazards (T7.2): `lethal_edges: PackedInt32Array` (play-area edge i = point i → i + 1) and
  `lethal_obstacles: PackedInt32Array` (indices into `obstacles`). Validation keeps start and
  solution positions at least 0.75 radii (surface gap) away from lethal geometry.
- Receptors (T7.3): `NeuronData.kind = RECEPTOR` with `reach` and `required_links` (1–2); the
  solution must satisfy every receptor with zero crossings and the start must not be solved.
- Levels are authored by hand (ideally editable in the Godot Inspector/editor).

### 8.3 Crossing detection
- Test every pair of dendrites that do not share a neuron using
  `Geometry2D.segment_intersects_segment`.
- Cost is O(E²), which is fine for the expected level sizes. Recomputed while dragging.
- The segment set is the static dendrites (edge id = index) plus the dynamic receptor links.
  `get_crossing_edges()` lists static ids, `get_crossing_links()` the links; the count, the
  involved neurons and `get_crossing_points()` (exact points, one per pair, emitted through
  `crossing_points_changed`) include both.

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
| `contamination_formed` / `contamination_cleared` | `receptor_id: int, neuron_id: int` | `NeuronView`, `ReceptorView`, `LinksView`, `LevelController`, `AudioDirector` | Warning glow, yellow link, HUD hint, toxic alarm |
| `diseased_strain_changed` | `edge_id: int, ratio: float` | `DendriteView`, `AudioDirector` | Thin, crack and tremble the ember dendrite; crack loop |
| `diseased_broken` | `edge_id: int` | `DendriteView`, `DiseasedView`, `LevelFx`, `LevelController`, `AudioDirector` | Hide the line, snap effect and sound, HUD counter |
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
- Level progress and stars are saved locally (versioned JSON, see 8.4); the player can reset all
  progress (Settings) or one mission's record (Mission select).
- Languages: English and Spanish only for now; more languages would be new CSV columns.
