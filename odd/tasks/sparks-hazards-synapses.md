# Feature: sparks-hazards-synapses

Objective: user-approved design (2026-10-07) — three gameplay/readability additions, all with animations and procedural sounds.
Branch: `feat/mvp-foundation`. Slice base: `b9b3de8` (phase 6 slice review started, blocked by a tool timeout).

## Approved design
1. **Crossing marks without recoloring**: a dendrite keeps its identity color (white / tension green / receptor cyan) when crossing. Crossing is shown by (a) crackling spark markers at each exact intersection point, (b) flicker of involved dendrites (no color replacement), (c) soft electric buzz loop while crossings exist. Neuron crossing highlight must not be confused with red fixed neurons.
2. **Lethal walls**: some boundary segments and/or obstacles are lethal (electric violet/magenta, crackling membrane). Proximity warning (glow + rising alarm tone) as a neuron approaches; on contact the neuron overloads, trembles, explodes in particles with flash + sound → level lost → quick restart (like a tension break). Variants: lethal boundary sides; lethal interior obstacles in advanced levels.
3. **Receptor neurons** (cyan, immovable): show a reach halo (soft pulsing ring) and a searching dendrite stub; need N connections (dots indicator; N=1 early, 2 later). When a movable neuron enters the halo, a dendrite grows to it (closest candidate wins) with an ascending synaptic click and cyan flash. Moving it out beyond reach: the dendrite stretches, trembles, snaps with sparks/sound (no loss, just disconnected). Near the reach limit the link thins and flickers. Win = all receptors fully connected AND zero crossings (dynamic links count). Completion wave travels through dynamic links. New chapter "Synapses" before "Convergence"; later combine with lethal walls and tension.

Added user requirement (T7.4, 2026-10-07): adapt the rest of the campaign — rebalance it as one curve (no spikes like m14 46 / m20 56 crossings), revise stories so the narrative flows into and out of the new chapters, rework Convergence to genuinely combine the new mechanics, keep a tested save migration, and document retuning with a before/after table.

## Tasks (route: delegated direct — one bounded writer for all tasks; trigger: 2+ non-trivial files per task)
- [x] T7.1 Crossing points + spark markers + identity-preserving highlight + buzz — `7c8cc9c`
- [x] T7.2 Lethal walls (model, validation, views, fx, audio) — `058ddd2`
- [x] T7.3 Receptor neurons and dynamic links (model, validation, views, fx, audio) — `4b1439a`
- [x] T7.4 Content: chapters Live Wires + Synapses, Convergence reworked, campaign rebalanced, translations en/es, save v2 migration, solvability proofs — `9323583` (save), `3fec5b4` (content)
- [x] T7.5 Docs: SDD + plan — commit recorded in the final report (this document is committed with it)

## Decisions

### Model and data
- **Crossing points**: `PuzzleModel.get_crossing_points()` (one point per crossing pair, pair order; collinear overlap = midpoint of the shared part, `GeometryUtils.crossing_point`). New signal `crossing_points_changed(points)` instead of changing `crossings_changed`, so existing listeners keep their payload. It fires whenever any point moves/appears/disappears.
- **Lethal data**: `LevelData.lethal_edges: PackedInt32Array` (play-area edge i = point i → i+1) and `lethal_obstacles: PackedInt32Array` (indices into `obstacles`), in an Inspector group "Hazards". Invalid indices are reported by validation and ignored by the model.
- **Lethal rule**: a neuron touches a lethal segment when its surface gap ≤ `GeometryUtils.EPSILON`. `drag_to` sub-steps treat lethal contact like a block (bisection), stop at contact, emit `neuron_destroyed(id, contact_point_on_wall)` (instead of `neuron_blocked`), release the grab and lock input (`is_lost()` = tension break or destroyed; `is_broken()` stays tension-only). A neuron blocked first by something non-lethal is not destroyed.
- **Proximity**: `get_hazard_proximity(id)` = clamp(1 − gap / (2 radii)); `hazard_proximity_changed(id, p)` after each move when it changes. `proximity_for_gap()` and `lethal_gap()` are static helpers.
- **Validation margin**: start and solution surface gap ≥ 0.75 radii (21 px) from lethal geometry. The planner keeps half of it (≈10.5 px) so every valid start is usable and no plan point ever touches a wall.
- **Receptors**: `NeuronData.kind = Kind.RECEPTOR` with `reach` and `required_links` (1–2, `@export_range`). Receptors are immovable (`is_fixed()` true) whatever `fixed` says. In reach: center distance − radius ≤ reach (the halo is drawn at radius + reach). Candidates: movable (not fixed, not receptor), not linked to that receptor, no static dendrite to it; closest first, ties lower id. After every move: breaks first, then fills; at build time links form silently.
- **Link id scheme**: links are keyed `Vector2i(receptor_id, neuron_id)` and never get an edge id. Crossings run over static edges (index = edge id) + links; `get_crossing_edges()` stays static-only, `get_crossing_links()` lists links; count, neurons and points include both. `crossings_changed` also fires when only the crossing link set changes.
- **Win**: on release, zero crossings (incl. links) and every receptor satisfied. Validation: solution satisfies every receptor with zero crossings; start must not be solved (for levels without receptors the old "start has no crossings" error stays).
- **Loss flow**: `LevelController.LossReason {NONE, TENSION_BREAK, OVERLOAD}`, `level_lost(reason)`, `get_loss_reason()`; restart after 0.6 s (break) or 1.2 s (overload: 0.35 s tremble + explosion).
- **NetworkWave**: graph distances use dendrites + links; the schedule has a new `"links"` list (`pair`, `delay`, `from_a`, `duration`).

### Views, fx, audio
- Palette: `CROSSING` became electric amber (crossing ring), new `SPARK`, `SPARK_GLOW`, `LETHAL` (violet), `LETHAL_CRACKLE` (magenta), `OVERLOAD_FLASH`, `RECEPTOR`, `RECEPTOR_GLOW`, `LINK` (cyan).
- Dendrite shader: `warm` → `crossing`; no recolor, travelling dashes + stepped crackle with a 0.62 floor so thin green tension dendrites stay visible. Neuron shader: soma never tinted; dashed rotating amber ring; new `overload` term (tremble + violet-white burn) also used at 0.35 × hazard proximity as a warning.
- New nodes in `level.tscn` (all additive): `LethalWalls` (`LethalWallView`), `Links` (`LinksView`), `Sparks` (`CrossingSparksView`), `Receptors` (one `ReceptorView` per receptor). LevelFx gets `links_view` for the completion wave and plays the overload explosion.
- Membranes draw lethal play-area sides violet per point (`draw_polyline_colors`); lethal obstacles are violet `ObstacleView`s.
- Audio (SoundBank recipes, all synthesized): `buzz` loop (100 Hz hum + crackle, volume −27→−18 dB over 1→6 crossings, fades), `alarm` loop (two-tone warble, pitch/volume follow proximity, stops on release), `explode`, `link` (two ticks + rising chirp), `unlink` (small snap). All five recipes landed in the T7.1 commit; their wiring in T7.2/T7.3.
- Reduced motion: static spark stars, no crackle/particles/tremble/growth/shake; glows and fades still follow state.

### Content (T7.4)
- **Chapter layout**: 1 First Signals m01–m05, 2 Shaped Minds m06–m10, 3 Anchored m11–m14, 4 Tension m15–m18, **5 Live Wires m19–m21** (new, lethal walls), **6 Synapses m22–m25** (new, receptors), **7 Convergence m26–m30** (old m19/m20/m21 reworked as m26/m28/m30 + new m27/m29). Lethal walls got their own chapter (cleaner teaching curve) placed before Synapses, so Convergence became chapter 7 (not 6 as the brief assumed with Synapses only).
- **Save migration**: `SAVE_VERSION` 2; `GameState.migrate_save()` renames v1 records m19→m26, m20→m28, m21→m30 (stars, bests and unknown keys kept). Impact: a player who had finished the old campaign keeps those records; the new m19 (Live Wires 1) is unlocked by m18; m20–m25 stay locked until played in order, while m26–m30 stay playable because completed missions are always unlocked (linear rule unchanged).
- **Authoring helper**: `tools/find_start.gd` searches seeded starts (swaps + jitter of the solution, tension repair) that are valid, readable (40 px clearance), receptor-unsatisfied, inside a crossing range and planner-proven; `calm` mode lowers an existing start's crossings move by move and then fixes tight spots. Its output is pasted into `level_specs.gd` as explicit `start` lists (the build stays deterministic).
- **Planner**: replays every planned move on a shadow `PuzzleModel` (links are history dependent) and stops when it reports solved; receptors are immovable; lethal walls kept at a margin.
- **Content tests**: 7 chapters, ≥ 30 missions; chapter mechanics (no lethal/receptors before chapter 5; Live Wires lethal only; Synapses receptors only; Convergence ≥ 3 mechanics including lethal or receptor); neuron-count rule relaxed for new-mechanic chapters (mean ≥ Shaped Minds; Convergence holds the largest mean; size 4–16); new no-spike curve rule (start ≤ max of previous three + 14; first mission of chapters 5/6 ≤ 6 crossings; most tangled start in Convergence); receptor missions start unlinked and Synapses has a two-link receptor.

## Mission table (new and renumbered)

| id | name (en / es) | ch | neurons | lethal (edges+obstacles) | receptors (reach x links) | other | start crossings | planned moves | par_moves | par_time | story |
|---|---|---|---|---|---|---|---|---|---|---|---|
| m19 | Live Wire / Cable vivo | 5 | 8 | 2+0 (both sides) | | cube | 4 | 7 | 14 | 120 | yes (intro) |
| m20 | Arc Flash / Arco eléctrico | 5 | 9 | 1+2 (floor, islands) | | lattice | 7 | 8 | 16 | 150 | |
| m21 | Short Circuit / Cortocircuito | 5 | 10 | 3+0 (U fold) | | U area | 11 | 10 | 20 | 180 | yes (foreshadows receptors) |
| m22 | First Synapse / Primera sinapsis | 6 | 7 | | 150x1 | ring | 4 | 5 | 10 | 90 | yes (intro) |
| m23 | Twin Receptors / Receptores gemelos | 6 | 10 | | 160x1, 160x1 | | 6 | 8 | 16 | 120 | |
| m24 | Double Bond / Doble enlace | 6 | 11 | | 140x2 | | 9 | 10 | 20 | 150 | yes (two links, links cross too) |
| m25 | Synaptic Strain / Tensión sináptica | 6 | 11 | | 175x2, 140x1 | 2 tension | 14 | 7 | 14 | 180 | |
| m26 (was m19) | Converging Paths / Caminos convergentes | 7 | 12 | 0+1 | | 2 fixed, islands | 24 | 10 | 20 | 210 | yes (revised) |
| m27 | Live Synapse / Sinapsis viva | 7 | 13 | 2+0 | 130x2 | 2 tension | 16 | 14 | 28 | 210 | |
| m28 (was m20) | Neural Storm / Tormenta neuronal | 7 | 13 | 4+0 (slants) | | 2 fixed, 3 tension, hex area | 28 | 11 | 22 | 240 | yes (new) |
| m29 | Charged Core / Núcleo cargado | 7 | 13 | 0+1 (core) | 140x2 | 2 fixed | 28 | 10 | 20 | 240 | |
| m30 (was m21) | Awakening / Despertar | 7 | 16 | 0+1 (core) | 180x1, 140x1 | 3 fixed, 3 tension, octagon | 35 | 11 | 22 | 270 | yes (finale, revised) |

## Rebalance: before / after

| mission | before | after | why |
|---|---|---|---|
| m12 Pinned Lattice | 24 start crossings, par_moves 10 | 12 crossings, par_moves 10 | spike after 6–7 crossing neighbours |
| m14 Iron Synapse | 46 crossings, par_moves 14 | 23 crossings, par_moves 12 | biggest early spike |
| m17 Tight Weave | story "Move them together." | + "Somewhere ahead, the walls begin to hum." | foreshadows Live Wires |
| old m19 → m26 | chapter 5, islands + anchors | chapter 7, island 0 lethal, story mentions live wires | Convergence combines new mechanics |
| old m20 → m28 | 56 crossings, no story | 28 crossings (calmed), 4 lethal slanted sides, new story | removes the worst spike, adds lethal |
| old m21 → m30 | 14 neurons, par_time 240 | 16 neurons (+2 receptors), lethal core, start adjusted (35 crossings), par_time 270 | finale uses every mechanic |
| chapter 5 title | Convergence | Live Wires (Convergence → chapter 7) | new chapters inserted |

Resulting start-crossing curve: ch1 1,2,5,3,10 · ch2 3,16,3,7,3 · ch3 6,12,7,23 · ch4 9,21,29,31 · ch5 4,7,11 · ch6 4,6,9,14 · ch7 24,16,28,28,35. Missions m01–m11, m13, m15, m16, m18 are unchanged (their curve already fitted the rule).

## Progress / evidence

Test-first: RED observed (parse errors for the missing API) before GREEN for crossing points, lethal model, receptor model, save migration; dendrite/neuron view tests updated first and observed failing (identity color, ring). Exceptions: NetworkWave links test, receptor/link view tests and the lethal view tests were written before their code but not run red first; visual look is checked by captures, not unit tests.

- T7.1: suite 392/392 after T7.1 (372 baseline). Captures m15/m16 play (green tension dendrite crossing stays green and readable; amber sparks), m15 reduced motion.
- T7.2: suite 419/419. Captures (debug lethal right side on m07) `approach` (violet crackle, hot spot, neuron warning tint) and `explode` (shock ring, flash).
- T7.3: suite 447/447 (+ planner tests). Content tests 15/15.
- T7.4: suite 457/457; `build_levels: OK, 30 missions` and a second build leaves the tree unchanged. Captures: m19 play (idle live walls were too faint → raised base glow and crackle), m21 approach (clear crackling fold), m22 link (halo, stub, dots, growing link), m25 strain (thin cyan link near the limit, two dots filled), m30 play (finale; top-right halo moved/shrunk to stay out of the HUD), mission select (7 chapters).
- T7.5: SDD sections 2, 3, 4, 5.4, 7, 7.1, 8.1, 8.2, 8.3 and plan Phase 7 updated.

Verification (final): `./run_tests.ps1` exit 0, 457 test cases, 0 failures; `godot --headless --path . --import` exit 0, no errors; `godot --headless --path . --quit-after 300` exit 0, no errors; `godot --headless --path . -s res://tools/build_levels.gd` OK, 30 missions, no data diff.

Pending: human playtest of the new chapters (pars, reach sizes, how dangerous the live walls feel), receptor halos of m25 still extend slightly above the play area (cosmetic), Engram mirror.

Engram mirror: pending (engram MCP unavailable this session).
