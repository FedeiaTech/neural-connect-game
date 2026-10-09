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
Run A (mechanics + measurement):
- [ ] **T8.1 Measurement mode** — dev toggle (`--measure` arg and F9, on-screen indicator), per-attempt log (mission id, attempt result, time to first move, total time, moves, restarts, loss reason) to `user://measurements.csv`; `tools/analyze_measurements.*` summarizing per mission and proposing `par_moves`/`par_time` (3★ ≈ best × 1.15, 2★ ≈ median) plus a way to apply them to `tools/level_specs.gd`; easy to disable/remove; tests.
- [ ] **T8.2 Toxic neurons** — model (kind TOXIC, contamination links, win blocked), validation, views (yellow), fx and procedural sounds, planner/content tests, translations en/es for any new text.
- [ ] **T8.3 Diseased dendrites** — model (kind DISEASED, break length, broken set, win requires all broken, no loss), validation, views (dark orange, crack/tremble, snap effect), sounds, planner support, tests, translations.
Run B (content):
- [ ] **T8.4 Campaign reorganization** — reorder chapters/missions so each mechanic is introduced in order (receptors → toxic; tension → diseased, etc.), renumber with tested save-id migration (SAVE_VERSION bump), update stories en/es.
- [ ] **T8.5 Organic arenas** — many-vertex polygon play areas (cell/lobe/spiral/ring-with-corridors) for advanced missions.
- [ ] **T8.6 Bosses** — last mission of each chapter: unique large arena, boss intro (name card, stinger), combines the chapter's mechanics, HARD toxic variant allowed; interactive effects and sounds.
- [ ] **T8.7 Docs** — SDD + plan.

## Progress / evidence

(none yet)

Engram mirror: `odd/measure-toxic-bosses/tasks` (see Engram).
