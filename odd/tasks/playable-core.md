# Feature: playable-core

Objective: Phase 2 of `docs/plans/implementation-plan.md` — first mission playable end to end with placeholder visuals.
Scope: T1.7 (review follow-ups), T2.1–T2.5. Out of scope: menus/screens (Phase 3), final aesthetics (Phase 4).
Constraints: Godot 4.7.2, GDScript static typing, gdUnit4, English artifacts. Views only read the model (SDD 8.1, 8.4–8.6).
Branch: `feat/mvp-foundation`. Last reviewed boundary: `471da49` (phase 1 review approved, lineage review-d99b3cab21485c35).

## Tasks (route: delegated direct — writer trigger)

- [ ] **T1.7 Review follow-ups (advisory, phase 1)** — `crossings_changed` must also fire when the crossing-pair count changes with the same edge set; `validate_level` rejects levels whose start layout has zero crossings; `run_tests.ps1` fails loudly when import fails; tension test separates broken-guard from no-grab guard and asserts no `neuron_blocked` after break.
- [ ] **T2.1 Views** — NeuronView, DendriteView, ObstacleView, Boundary (placeholder drawing, signal-driven).
- [ ] **T2.2 InputController** — mouse drag, generous grab radius, touch-ready.
- [ ] **T2.3 LevelController** — model ownership, timer, moves, restart, stars, state machine.
- [ ] **T2.4 Minimal HUD** — moves, time, restart, story overlay, completion summary.
- [ ] **T2.5 First mission** — `data/levels/m01.tres` (4 neurons), playable from main scene.

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
