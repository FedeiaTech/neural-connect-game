# Feature: campaign-content

Objective: Phase 5 of `docs/plans/implementation-plan.md` — hand-designed fixed story missions grouped in chapters (SDD 7, 7.1).
Scope: T5.1 author missions for chapters 1–4 (+ combinations), story text every 2–3 missions; T5.2 automated tuning checks (solvability, pars, difficulty curve) since human playtest happens after delivery.
Branch: `feat/mvp-foundation`. Slice base: `6e67a3e` (phase 4b review declined by user; phase 4a also declined).

## Tasks (route: delegated direct — writer trigger)

- [x] **T5.1 Hand-design missions** — 21 fixed missions in 5 chapters. Single source `tools/level_specs.gd`
  (hand-written solution spots, edges, kinds and hand-picked start positions / shuffles with per-neuron nudges),
  built offline by `tools/build_levels.gd` into `data/levels/m01.tres`–`m21.tres` and `data/campaign.tres`
  (deterministic; a rebuild over the committed files is a no-op; m01/m02 regenerate byte-identical). No runtime generation.
- [x] **T5.2 Tuning checks (automated)** — `tests/content/test_campaign_content.gd` + `tests/content/solution_planner.gd`.
  Human playtest of pars, grab radius and difficulty curve is still pending (after delivery).

## Campaign

| id | name | ch | neurons | dendrites | fixed | tension | start crossings | planned moves | par_moves | par_time | story |
|---|---|---|---|---|---|---|---|---|---|---|---|
| m01 | First Spark | 1 | 4 | 4 | 0 | 0 | 1 | 4 | 6 | 60 | yes |
| m02 | Branching Paths | 1 | 6 | 9 | 0 | 0 | 2 | 3 | 8 | 90 |  |
| m03 | Echo Loop | 1 | 5 | 5 | 0 | 0 | 5 | 4 | 8 | 60 |  |
| m04 | Twin Circuits | 1 | 6 | 9 | 0 | 0 | 3 | 5 | 10 | 90 | yes |
| m05 | Relay Hub | 1 | 7 | 12 | 0 | 0 | 10 | 7 | 14 | 120 |  |
| m06 | Bent Corridor | 2 | 8 | 12 | 0 | 0 | 3 | 7 | 14 | 120 | yes |
| m07 | The Hollow | 2 | 8 | 16 | 0 | 0 | 16 | 8 | 16 | 150 |  |
| m08 | Narrow Passage | 2 | 8 | 11 | 0 | 0 | 3 | 8 | 16 | 150 | yes |
| m09 | Scattered Islands | 2 | 9 | 14 | 0 | 0 | 7 | 9 | 18 | 150 |  |
| m10 | Folded Cortex | 2 | 9 | 11 | 0 | 0 | 3 | 8 | 16 | 150 |  |
| m11 | Anchor Point | 3 | 8 | 11 | 1 | 0 | 6 | 7 | 14 | 120 | yes |
| m12 | Pinned Lattice | 3 | 9 | 16 | 2 | 0 | 24 | 5 | 10 | 150 |  |
| m13 | Red Constellation | 3 | 10 | 15 | 3 | 0 | 7 | 7 | 14 | 180 | yes |
| m14 | Iron Synapse | 3 | 11 | 20 | 4 | 0 | 46 | 7 | 14 | 180 |  |
| m15 | Taut Thread | 4 | 9 | 18 | 0 | 2 | 9 | 8 | 16 | 150 | yes |
| m16 | Elastic Bond | 4 | 10 | 17 | 0 | 3 | 21 | 9 | 18 | 180 |  |
| m17 | Tight Weave | 4 | 11 | 21 | 0 | 4 | 29 | 11 | 22 | 210 | yes |
| m18 | Breaking Point | 4 | 12 | 23 | 0 | 5 | 31 | 10 | 20 | 240 |  |
| m19 | Converging Paths | 5 | 12 | 21 | 2 | 0 | 24 | 10 | 20 | 210 | yes |
| m20 | Neural Storm | 5 | 13 | 27 | 2 | 3 | 56 | 11 | 22 | 240 |  |
| m21 | Awakening | 5 | 14 | 26 | 3 | 3 | 35 | 11 | 22 | 240 | yes |

"Planned moves" = moves of the deterministic planner's solution replayed on the real `PuzzleModel` (an upper
bound, not the human minimum; m01 needs 1 move by hand). `par_moves` = 2 × planned moves (m01/m02 keep their
original 6/8). Chapter mean neuron counts: 5.6, 8.4, 9.5, 10.5, 13.0.

## Design notes

- Ch1 First Signals: 4-cycle bowtie, first hub, pentagram 5-cycle, triangular prism (mirrored inner triangle), 6-rim wheel. Plain rectangle, no special neurons.
- Ch2 Shaped Minds: L area, ring around a solid core, two chambers joined by a one-neuron corridor (neuron 4 starts in it and must leave first), triangulated lattice with islands, U area.
- Ch3 Anchored: fixed hub, two fixed lattice corners, pentagonal prism with three anchors, four fixed corners plus side walls.
- Ch4 Tension: tension spokes starting on the wrong side of the hub near breaking (0.88 of max), flipped ladder rungs, tension pairs swapped as units, two pentagram wheels with a tension bridge (0.92 of max at start).
- Ch5 Convergence: islands + anchors; hexagonal field + fixed hub + folded tension pairs; two hemispheres around a core with anchors and tension bridges.
- Readability rules (enforced by build tool and tests): solution neurons ≥ 3 radii apart (actual min 178 units), no
  solution dendrite within 2 radii of a foreign neuron, no start dendrite within 40 units of a foreign neuron (start
  shuffles were hand-nudged until they pass). Play areas stay within 1600x900 units.

## Tuning checks (`tests/content/test_campaign_content.gd`)

- Campaign: 5 chapters with ids 1..5, titles, subtitles, ≥ 2 missions each, mission `chapter_id` matches; mission i is `m%02d` and lives at `res://data/levels/mXX.tres`; unique ids and names; every level file is in the campaign.
- Every mission passes `PuzzleModel.validate_level`.
- Solvability proof: `SolutionPlanner` (greedy, lowest misplaced id first: straight or grid-BFS path with string pulling, else park a neuron sitting on another's spot, else approach as far as tension allows; mirrors the model rules with a 2-unit margin) produces drags that are replayed on a real `PuzzleModel` via `grab/drag_to/release`; asserts every drag reaches its point, nothing breaks, `is_solved()`.
- Pars: `par_moves` ≥ planned moves and ≤ 4 × neurons; `par_time` in [45, 300].
- Difficulty: start crossings ≥ 1 (ch1) / ≥ 3 (ch2+); chapter mean neuron count non-decreasing; 4–14 neurons.
- Mechanics: ch1 plain; ch2 shaped area or obstacles; ch3 ≥ 1 fixed; ch4 ≥ 1 tension dendrite at ≥ 0.8 × max_length at start or solution; ch5 ≥ 2 mechanics.
- Readability (see above) and story cadence (first mission has story, at most 2 missions in a row without, ≤ 2 lines).

## Progress / evidence

- RED: `./run_tests.ps1 res://tests/content` before authoring → fails at `test_campaign_has_the_five_chapters_in_order` (expected 5 chapters, was 1; gdUnit CI runner is fail-fast).
- GREEN: `./run_tests.ps1` → exit 0, 337/337 (baseline 326 + 10 content tests + 1 readability test; 3 existing tests adapted to the longer campaign: `test_campaign`, `test_game_state_save`, `test_screen_host`).
- Intermediate state after the chapter 1 commit: `./run_tests.ps1` → exit 0, 326/326.
- `godot --headless --path . --import` → exit 0, no errors. `godot --headless --path . --quit-after 300` → exit 0.
- `godot --headless --path . -s res://tools/build_levels.gd` → `build_levels: OK, 21 missions`, rebuild leaves the tree unchanged (~5 s).
- Visual: `tests/visual/capture_level.tscn` windowed on m07, m08, m14, m18, m20, m21: shapes, corridor, obstacles, fixed (red) and tension (green) neurons/dendrites readable; an m21 collinear start (dendrite through a neuron) was found this way and led to the start-clearance rule.
- Commits: `dd0d83b` tool + planner, `5079635` ch1, `7f0cfa0` ch2, `3f264c7` ch3, `006ac02` ch4, `a3e0bfd` ch5, `55e1d4e` tests.

Pending: human playtest (pars, grab radius, difficulty curve) — T5.2 human part.
Engram mirror: pending (engram MCP unavailable this session).

## Next step

Human playtest of the 21 missions; retune pars from real moves/times by editing `tools/level_specs.gd` and rerunning the builder.

- Review: slice `6e67a3e..8126eab` medium, `slice_budget_reached` (4410 lines); user **declined** (candidate-scoped). Parent spot check `./run_tests.ps1` -> 337 cases, exit 0.
