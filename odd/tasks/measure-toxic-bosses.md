# Feature: measure-toxic-bosses

Objective (user, 2026-10-08): (1) a temporary measurement mode to record how long each mission takes so 3-star thresholds are based on real data; (2) new mechanics: toxic neurons (must not get connected) and diseased dendrites (must be broken on purpose); (3) more organic, non-rectangular arenas in advanced missions; (4) a "boss" final mission per chapter; (5) reorganize/renumber the campaign so the progression makes sense; (6) interactivity, animations and procedural sound effects for everything.
Branch: `feat/mvp-foundation`. Review tooling is OFF for this clone (gentle-ai upstream #5094); ordinary checks apply.

## Decisions (user answered)
- Toxic neuron rule = SOFT (A): a toxic neuron inside a receptor's reach forms a yellow contamination link with an alarm; it does NOT count toward required links, blocks winning until the toxic neuron is moved away, and never restarts the level. A HARD variant (explode + restart, like lethal walls) is reserved for boss missions later.
- Diseased dendrite = dark-orange dendrite that must be stretched past its break length on purpose; breaking is required to win, never a loss; broken stays broken (restart to retry).
- Measurement mode is temporary and developer-only (off by default, easy to remove), logs to a CSV in user://.
- Pars/stars are retuned AFTER the new content exists, from measured data.
- Campaign gets reorganized so mechanics are introduced in a sensible order (see run B).

## Tasks (route: delegated direct, one writer per run)
Run A (mechanics + measurement) — route: delegated direct (one writer; trigger: 2+ non-trivial files and 4+ files to understand):
- [x] **T8.1 Measurement mode** — commit `bcb176e`; streaks in `96c58f0`. Implemented, used once (streak 20261009-231045, 15 missions), then REMOVED (see the T8.1 note).
- [x] **T8.2 Toxic neurons** — commit `72381cd`.
- [x] **T8.3 Diseased dendrites** — commit `1ced3a1`.
Run B (content):
- [x] **T8.4 Campaign reorganization** — reorder chapters/missions so each mechanic is introduced in order (receptors → toxic; tension → diseased, etc.), renumber with tested save-id migration (SAVE_VERSION bump), update stories en/es.
- [x] **T8.5 Organic arenas** — many-vertex polygon play areas (cell/lobe/spiral/ring-with-corridors) for advanced missions.
- [x] **T8.6 Bosses** — last mission of each chapter: unique large arena, boss intro (name card, stinger), combines the chapter's mechanics, HARD toxic variant allowed; interactive effects and sounds.
- [x] **T8.7 Docs** — SDD + plan (run A already added the toxic / diseased rows, rules and signals to SDD 3 / 8.5 and Phase 8 to the plan).

## Run A evidence

Verification (observed): `./run_tests.ps1` exit 0, 566 test cases (466 baseline + 100 new), 0 failures, 0 orphans; `godot --headless --path . --import` exit 0 no errors; `godot --headless --path . --quit-after 300` exit 0 no errors; `godot --headless --path . -s res://tools/build_levels.gd` OK (30 missions), `data/` unchanged (tree clean). Windowed captures (`tests/visual/capture_level.tscn`, read as PNG): `fixture_toxic` idle / `contam`, `fixture_diseased` idle / `dstrain` / `dsnap`, and `m01 measure` (tag). Readability fixes made from the captures: toxic yellow moved to (1.0, 0.95, 0.1); diseased line made thicker at rest (3.8 px) and brighter (0.84, 0.39, 0.05) so it reads against the red crossing lines; HUD hints kept inside the 48 px margin below the play area.
TDD: RED observed for the model suites (parse errors on the missing `TOXIC` / `DISEASED` kinds before the code existed); the T8.1 suites were written before the code but not run before it (the classes did not exist, so they could not compile either).

### T8.1 Measurement mode (REMOVED)
Implemented (commits `bcb176e`, `96c58f0`), used once (streak 20261009-231045, 15 missions) and then REMOVED. The 3-star move limits it produced live in `MEASURED_PAR_MOVES` of `tools/level_specs.gd` (commit `b2d9a3c`); the raw CSV is archived at `docs/data/measurements-2026-10-09.csv`. The code (F9 / `--measure`, `scripts/dev/measurement.gd`, `tools/analyze_measurements.gd`) can be recovered from git history at commit `96c58f0`.

### T8.2 Toxic neurons (SOFT rule)
- `NeuronData.Kind.TOXIC` (+ `is_toxic()`); movable, never fixed (validation error otherwise), never a link candidate. Palette `TOXIC` = (1.0, 0.95, 0.1) lemon yellow, `TOXIC_GLOW` (1.0, 0.86, 0.1); distinct from white, red fixed, cyan receptor, violet lethal, green tension, the orange-red crossing feedback and the amber spark markers (palette-distance test).
- Model (`PuzzleModel`): a separate sorted set of contamination links keyed `Vector2i(receptor_id, neuron_id)`, recomputed after every move with the same reach rule as links; signals `contamination_formed` / `contamination_cleared` (clears first); queries `is_toxic`, `is_contaminated`, `get_contamination_links`, `has_contamination`. Win on release needs zero crossings, receptors satisfied by non-toxic neurons and zero contamination; never a loss.
- Decisions: contamination links are warnings only, NOT segments for crossing detection; a static dendrite between a receptor and a toxic neuron does not prevent contamination; a toxic neuron in a level with no receptors is allowed (harmless decoy, no error, no warning); validation rejects contamination in the start layout ("Start layout has contamination link(s)") and in the solution layout, and a fixed toxic neuron; toxic neurons need a solution position like any movable one.
- Views: toxic soma + faint pulsing warning glow (neuron shader `warn`, 0.3 idle, 1.0 and a ring while contaminating, eased; snapped and still with reduced motion); `LinksView` draws a flickering yellow dashed line from the receptor with a pulsing warning triangle and a yellow flash on formation (cyan relief flash on clear; steady solid line with reduced motion); `ReceptorView` turns its halo ring yellow and faster while contaminated and its searching stub ignores toxic neurons; HUD hint `HUD_CONTAMINATED` ("Contaminated link: move the yellow neuron away" / "Enlace contaminado: aleja la neurona amarilla"), driven by `LevelController.contamination_changed`.
- Audio: `toxic_alarm` (1 s loop of four dry 1250 Hz beeps, distinct from the lethal-wall warble) plays while any contamination exists (also after release; stops on clear, restart, loss and completion) and `toxic_clear` (two ascending bell notes) when the last one clears.
- Planner: `SolutionPlanner` forbids contamination while planning (a toxic neuron never gets a grid cell, goal or path segment within radius + reach + 2 px of a receptor) and keeps replaying on its shadow model; `build_levels.gd` accepts a `toxic: [ids]` spec key (serialized as `kind = 2`).
- Tests: `test_puzzle_model_toxic.gd`, `test_level_validation_toxic.gd`, `test_toxic_views.gd`, `test_level_toxic.gd` (controller, HUD en/es, alarm and chime), planner test around a receptor reach, `tests/content/test_fixtures.gd` (the `fixture_toxic` level validates and is solved by the planner).

### T8.3 Diseased dendrites
- `DendriteData.Kind.DISEASED` (+ `is_diseased()`), same `rest_length` / `max_length` data as tension. Model: a broken set (edge ids stay stable; a broken edge is skipped by crossing detection and stays broken until the model is rebuilt), `diseased_broken(edge_id)`, separate `diseased_strain_changed(edge_id, ratio)` (tension listeners never hear it), queries `is_diseased_edge`, `is_edge_broken`, `get_diseased_ratio`, `get_diseased_edges`, `get_diseased_count`, `get_diseased_broken_count`, `are_diseased_broken`. A move that leaves an intact diseased edge longer than `max_length` breaks it; the grab continues, never a loss. Win needs every diseased edge broken (plus the other conditions).
- Validation: `max_length > rest_length`; start length <= `max_length`; solution length > `max_length` ("cannot break in the solution"); other tension dendrites keep their existing limits; models built with `use_solution` start with the stretched diseased edges broken, so a broken edge's solution crossings do not count; a level whose only goal is breaking diseased dendrites may start without crossings.
- Views: `DendriteView` dark orange ember line (`Palette.DISEASED` (0.84, 0.39, 0.05) heating to `DISEASED_HOT` (1.0, 0.56, 0.14)), thick at rest (3.8 px) thinning to 1.7 px, trembling and flickering like tension, plus a shader `crack` that cuts dark gaps into the core near the limit; it keeps its own color while crossing and hides when it snaps. `DiseasedView` (new additive layer, `Playfield/Diseased`) spawns ember sparks on strained edges (rate grows from 50 % strain) and plays the snap (flash, shock ring, two retracting halves, 18 embers); `LevelFx` adds a spark burst and a light shake (45 % of a tension break); the completion wave no longer travels through broken edges. HUD counter `HUD_DISEASED` ("Diseased: n/m" / "Dendritas enfermas: n/m"), shown only when the level has diseased dendrites (`LevelController.diseased_progress_changed`). Reduced motion: no embers, burst, shake, tremble or retraction; the snap is a fading flash.
- Audio: `diseased_crack` (1 s loop: wooden crackle over a 140 Hz buzz; pitch 0.8 to 1.7 and volume -30 to -12 dB with the highest strain from 35 %, stops on release, break, loss and completion) and `diseased_snap` (dry crack: noise burst, two falling tones, embers).
- Planner: diseased edges are not distance limits (breaking is the goal); the shadow model decides the win, so the plan stretches them past `max_length`. `build_levels.gd` accepts `[a, b, rest, max, "diseased"]` edges (serialized as `kind = 2`).
- Tests: `test_puzzle_model_diseased.gd`, `test_level_validation_diseased.gd`, `test_diseased_views.gd` (view, ember layer, snap, LevelFx, wave), `test_level_diseased.gd` (counter en/es, controller signal, no restart, crack / snap sounds), planner test that breaks a diseased dendrite, fixture test for `fixture_diseased`.

### Shared run A changes
- `tests/visual/fixtures.gd` (`fixture_toxic`, `fixture_diseased`; test-only levels, not in the campaign) and `capture_level.gd` modes `contam`, `dstrain`, `dsnap`; `LevelFactory` helpers `toxic`, `receptor`, `diseased_edge`.
- Translations: `HUD_CONTAMINATED`, `HUD_DISEASED` (en + neutral es); `.translation` files regenerated by the import and committed. No campaign content was added or changed (`data/` untouched).
- Docs: SDD sections 3 and 8.5 and the plan's Phase 8 describe the rules.

## Run B evidence (T8.4-T8.7)

### Decisions
- **Stable ids, no renumbering.** The 30 original ids keep their meaning; new missions are m31..m48; the campaign order is the explicit chapter/mission list built by `tools/level_specs.gd` (and pinned by `EXPECTED_ORDER` in the content tests). Chosen over a v2 -> v3 id map because it cannot lose progress and needs no format change: `SAVE_VERSION` stays 2 (v1 saves still migrate m19/m20/m21 -> m26/m28/m30). Tested in `tests/campaign/test_stable_ids.gd`: every legacy id exists, an old v2 save keeps every record, unknown fields survive, unlocking follows the new order (a boss may wait for the mission before it; completed missions stay playable), displayed numbers are positions.
- **Chapter order:** 1 First Signals, 2 Shaped Minds, 3 Anchored, 4 Tension, **5 Pruning** (diseased: the tension bond turned inside out, so right after Tension), 6 Live Wires, 7 Synapses, **8 Contagion** (toxic only matters near receptors, so right after Synapses), 9 Convergence. Chapter ids = positions (headings show "Chapter n"), so the CHAPTER_n translation keys were renumbered.
- **Hard toxic:** per-level flag `LevelData.hard_toxic` (only bosses m47, m48). Model: a contamination link that forms during a drag emits `toxic_overloaded` then `neuron_destroyed`; `get_destroy_cause()` is TOXIC; controller `LossReason.TOXIC_OVERLOAD` (same flow/delay as OVERLOAD); `toxic_overload` sound, yellow blast in `LevelFx`.
- **Arenas:** `Organic.cell()` (union of discs around every neuron position + shrunken hull, closed/opened, clipped to a rounded 1580 x 880 frame, outward wobble) for existing missions; designed rounded polygons for the L / U / chambers / hexagon / octagon missions; polar lobes, hourglass, crescent, rings with island and pillars, double bubble for the new ones. Outlines are rounded to whole pixels, so the `.tres` are byte-stable. Many-vertex outlines are cheap: the membrane resamples them anyway; the planner got a Lipschitz-margin fast path (`_segment_in_playfield`) so verification of 48 levels takes seconds.
- **Layouts:** `tools/layouts.gd` (best-candidate scatter, Delaunay edges thinned for readability, chords for diseased dendrites, tension/diseased limits, receptor/toxic planning, dense receptor sites); start layouts found by `tools/find_start.gd ... write` into `tools/level_starts.gd` (repairs tension / diseased limits, receptor links and toxic reach).
- Existing missions changed only in arena (organic), chapter id and, for m14 / m09 / m20 / m26 / m29 / m30, obstacle shapes (moved inside the new arenas; m09 lost its third island). Stories m17, m21, m30 reworded for the new order. Pars of new missions = 2 x planned moves (builder default), the human retunes them.

### Before / after mapping
Before (30 missions, ids = position): ch1 m01-m05, ch2 m06-m10, ch3 m11-m14, ch4 m15-m18, ch5 Live Wires m19-m21, ch6 Synapses m22-m25, ch7 Convergence m26-m30. After: ids unchanged; chapter ids shift (Live Wires 5 -> 6, Synapses 6 -> 7, Convergence 7 -> 9) and the new chapters/missions slot in as below. Display numbers = position: e.g. m06 shows 7, m19 shows 25.

New order: ch1 m01-m05, **m31**; ch2 m06-m10, **m32**; ch3 m11-m14, **m33**; ch4 m15-m18, **m34**; ch5 (new) m35-m38, **m39**; ch6 m19-m21, m40, **m41**; ch7 m22-m25, **m42**; ch8 (new) m43-m46, **m47**; ch9 m26-m30, **m48** (bold = boss).

### Final campaign table (build_levels.gd report; names are translation keys MISSION_<ID>_NAME)
Columns: ch, neurons, tension / diseased / toxic counts, lethal edges+obstacles, receptors (reach x links), start crossings, planned moves, par moves / time, story, boss, arena vertices and size.

| id | name | ch | neurons | tension | diseased | toxic | lethal | receptors | start crossings | planned moves | par_moves | par_time | story | boss | area pts | size |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| m01 | MISSION_M01_NAME | 1 | 4 | 0 | 0 | 0 |  |  | 1 | 4 | 6 | 60 | yes |  | 4 | 1600x900 |
| m02 | MISSION_M02_NAME | 1 | 6 | 0 | 0 | 0 |  |  | 2 | 3 | 8 | 90 |  |  | 4 | 1600x900 |
| m03 | MISSION_M03_NAME | 1 | 5 | 0 | 0 | 0 |  |  | 5 | 4 | 8 | 60 |  |  | 4 | 1600x900 |
| m04 | MISSION_M04_NAME | 1 | 6 | 0 | 0 | 0 |  |  | 3 | 5 | 10 | 90 | yes |  | 4 | 1600x900 |
| m05 | MISSION_M05_NAME | 1 | 7 | 0 | 0 | 0 |  |  | 10 | 7 | 14 | 120 |  |  | 4 | 1600x900 |
| m31 | MISSION_M31_NAME | 1 | 10 | 0 | 0 | 0 |  |  | 14 | 11 | 22 | 240 | yes | BOSS | 120 | 1254x812 |
| m06 | MISSION_M06_NAME | 2 | 8 | 0 | 0 | 0 |  |  | 3 | 7 | 14 | 120 | yes |  | 162 | 1612x914 |
| m07 | MISSION_M07_NAME | 2 | 8 | 0 | 0 | 0 |  |  | 16 | 8 | 16 | 150 |  |  | 181 | 1523x894 |
| m08 | MISSION_M08_NAME | 2 | 8 | 0 | 0 | 0 |  |  | 3 | 8 | 16 | 150 | yes |  | 209 | 1614x915 |
| m09 | MISSION_M09_NAME | 2 | 9 | 0 | 0 | 0 |  |  | 7 | 9 | 18 | 150 |  |  | 185 | 1552x902 |
| m10 | MISSION_M10_NAME | 2 | 9 | 0 | 0 | 0 |  |  | 3 | 8 | 16 | 150 |  |  | 199 | 1617x917 |
| m32 | MISSION_M32_NAME | 2 | 12 | 0 | 0 | 0 |  |  | 16 | 9 | 18 | 270 | yes | BOSS | 140 | 1592x838 |
| m11 | MISSION_M11_NAME | 3 | 8 | 0 | 0 | 0 |  |  | 6 | 7 | 14 | 120 | yes |  | 105 | 989x890 |
| m12 | MISSION_M12_NAME | 3 | 9 | 0 | 0 | 0 |  |  | 12 | 5 | 10 | 150 |  |  | 163 | 1325x897 |
| m13 | MISSION_M13_NAME | 3 | 10 | 0 | 0 | 0 |  |  | 7 | 7 | 14 | 180 | yes |  | 136 | 1061x899 |
| m14 | MISSION_M14_NAME | 3 | 11 | 0 | 0 | 0 |  |  | 23 | 6 | 12 | 180 |  |  | 193 | 1534x901 |
| m33 | MISSION_M33_NAME | 3 | 13 | 0 | 0 | 0 |  |  | 14 | 10 | 20 | 300 | yes | BOSS | 131 | 1398x680 |
| m15 | MISSION_M15_NAME | 4 | 9 | 2 | 0 | 0 |  |  | 9 | 8 | 16 | 150 | yes |  | 162 | 1564x893 |
| m16 | MISSION_M16_NAME | 4 | 10 | 3 | 0 | 0 |  |  | 21 | 9 | 18 | 180 |  |  | 144 | 1469x755 |
| m17 | MISSION_M17_NAME | 4 | 11 | 4 | 0 | 0 |  |  | 29 | 11 | 22 | 210 | yes |  | 137 | 1445x901 |
| m18 | MISSION_M18_NAME | 4 | 12 | 5 | 0 | 0 |  |  | 31 | 10 | 20 | 240 |  |  | 138 | 1514x782 |
| m34 | MISSION_M34_NAME | 4 | 13 | 5 | 0 | 0 |  |  | 15 | 16 | 32 | 300 | yes | BOSS | 130 | 1195x868 |
| m35 | MISSION_M35_NAME | 5 | 7 | 0 | 1 | 0 |  |  | 3 | 7 | 14 | 90 | yes |  | 110 | 1177x583 |
| m36 | MISSION_M36_NAME | 5 | 8 | 0 | 2 | 0 |  |  | 7 | 7 | 14 | 120 |  |  | 110 | 1024x791 |
| m37 | MISSION_M37_NAME | 5 | 9 | 0 | 3 | 0 |  |  | 12 | 7 | 14 | 150 | yes |  | 110 | 1180x747 |
| m38 | MISSION_M38_NAME | 5 | 10 | 3 | 2 | 0 |  |  | 8 | 9 | 18 | 180 |  |  | 110 | 1507x774 |
| m39 | MISSION_M39_NAME | 5 | 13 | 3 | 4 | 0 |  |  | 12 | 12 | 24 | 300 | yes | BOSS | 160 | 1457x712 |
| m19 | MISSION_M19_NAME | 6 | 8 | 0 | 0 | 0 | 48+0 |  | 4 | 7 | 14 | 120 | yes |  | 166 | 1287x897 |
| m20 | MISSION_M20_NAME | 6 | 9 | 0 | 0 | 0 | 41+2 |  | 7 | 8 | 16 | 150 |  |  | 184 | 1569x898 |
| m21 | MISSION_M21_NAME | 6 | 10 | 0 | 0 | 0 | 53+0 |  | 11 | 10 | 20 | 180 | yes |  | 195 | 1614x914 |
| m40 | MISSION_M40_NAME | 6 | 11 | 0 | 0 | 0 | 52+0 |  | 14 | 9 | 18 | 210 |  |  | 120 | 1382x820 |
| m41 | MISSION_M41_NAME | 6 | 14 | 2 | 0 | 0 | 64+0 |  | 15 | 14 | 28 | 300 | yes | BOSS | 125 | 1380x795 |
| m22 | MISSION_M22_NAME | 7 | 7 | 0 | 0 | 0 |  | 150x1 | 4 | 5 | 10 | 90 | yes |  | 115 | 1075x848 |
| m23 | MISSION_M23_NAME | 7 | 10 | 0 | 0 | 0 |  | 160x1 160x1 | 6 | 8 | 16 | 120 |  |  | 162 | 1592x896 |
| m24 | MISSION_M24_NAME | 7 | 11 | 0 | 0 | 0 |  | 140x2 | 9 | 10 | 20 | 150 | yes |  | 142 | 1476x898 |
| m25 | MISSION_M25_NAME | 7 | 11 | 2 | 0 | 0 |  | 175x2 140x1 | 14 | 7 | 14 | 180 |  |  | 147 | 1404x889 |
| m42 | MISSION_M42_NAME | 7 | 14 | 2 | 0 | 0 |  | 160x1 205x1 170x2 | 9 | 12 | 24 | 300 | yes | BOSS | 140 | 1501x877 |
| m43 | MISSION_M43_NAME | 8 | 7 | 0 | 0 | 1 |  | 185x1 | 4 | 6 | 12 | 120 | yes |  | 110 | 1094x653 |
| m44 | MISSION_M44_NAME | 8 | 9 | 0 | 0 | 2 |  | 200x1 230x1 | 4 | 8 | 16 | 150 |  |  | 110 | 1252x735 |
| m45 | MISSION_M45_NAME | 8 | 10 | 2 | 0 | 2 |  | 295x2 | 7 | 8 | 16 | 180 | yes |  | 110 | 1450x730 |
| m46 | MISSION_M46_NAME | 8 | 11 | 2 | 0 | 2 |  | 320x2 195x1 | 7 | 9 | 18 | 210 |  |  | 110 | 1378x799 |
| m47 | MISSION_M47_NAME | 8 | 14 | 2 | 0 | 3 |  hard | 170x1 160x1 170x2 | 12 | 14 | 28 | 300 | yes | BOSS | 140 | 1446x838 |
| m26 | MISSION_M26_NAME | 9 | 12 | 0 | 0 | 0 | 0+1 |  | 24 | 10 | 20 | 210 | yes |  | 168 | 1526x902 |
| m27 | MISSION_M27_NAME | 9 | 13 | 2 | 0 | 0 | 59+0 | 130x2 | 16 | 14 | 28 | 210 |  |  | 177 | 1425x900 |
| m28 | MISSION_M28_NAME | 9 | 13 | 3 | 0 | 0 | 65+0 |  | 28 | 11 | 22 | 240 | yes |  | 144 | 1591x916 |
| m29 | MISSION_M29_NAME | 9 | 13 | 0 | 0 | 0 | 0+1 | 140x2 | 28 | 10 | 20 | 240 |  |  | 155 | 1292x899 |
| m30 | MISSION_M30_NAME | 9 | 16 | 3 | 0 | 0 | 0+1 | 180x1 140x1 | 35 | 11 | 22 | 270 | yes |  | 158 | 1617x918 |
| m48 | MISSION_M48_NAME | 9 | 16 | 3 | 2 | 2 | 26+1 hard | 170x1 185x2 | 31 | 13 | 26 | 300 | yes | BOSS | 180 | 1556x902 |

### Verification (run B, observed)
- `./run_tests.ps1` exit 0, 625 test cases, 0 failures, 0 orphans (566 baseline + new suites: stable ids, authoring tools, hard toxic model / level, boss UI; the content suite was rewritten).
- `godot --headless --path . --import` no errors; `godot --headless --path . --quit-after 300` quits cleanly; `godot --headless --path . -s res://tools/build_levels.gd` OK (48 missions), a second build leaves the tree unchanged.
- Windowed captures reviewed (`/tests/visual/capture_level.tscn`, `capture_screens.tscn` with new modes `boss`, `toxicboom`, `boss=mXX`): m31 boss intro, m33 hourglass, m34 crescent (+ intro), m41 double bubble with live waist, m47 hard toxic overload, m48 final arena, m07 organic ring, m19, mission map around the m34 boss node (crown, orange Pruning header). Fixes from captures: m34 bay opened to the outside (it was a hole), cell arenas clipped to the view frame, thin hull tips bridged.
- Pending: human playtest of difficulty, pars (fixed from the measured streak plus designer estimates; retune in `tools/level_specs.gd`), the boss stinger / fanfare / toxic overload sounds (checked only structurally, not heard), the Spanish stories. Known: the toxic hint stays visible during the 1.2 s overload restart delay.

## Pending
- Human playtest of the new look and sounds (the ember crackle, alarm beeps and the yellow / dark orange colors were only checked on captures, not heard).
- Measurement data: the mode was used once (streak 20261009-231045) and then removed; raw CSV archived at `docs/data/measurements-2026-10-09.csv`.

Engram mirror: `odd/measure-toxic-bosses/tasks` (see Engram).
