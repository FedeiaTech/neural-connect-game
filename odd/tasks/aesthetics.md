# Feature: aesthetics

Objective: Phase 4 of `docs/plans/implementation-plan.md` — bioluminescent look, animated menus and procedural audio (SDD 5.3–5.5), plus phase 3 review follow-ups.
Constraints: no external images or audio files — everything from code, shaders, particles and synthesized sound (SDD 5.5, 8.8). GL Compatibility. Respect `GameState.reduced_motion`.
Branch: `feat/mvp-foundation`. Last reviewed boundary: `4d8a73d` (phase 3 review approved, lineage review-d040a9cde8341cd4).

## Tasks (route: delegated direct — writer trigger; split in two writer runs: 4a = T3.3, T4.1–T4.4; 4b = T4.5–T4.7)

- [ ] **T3.3 Save hardening (phase 3 review follow-ups)** — check temp write before rename; keep a backup of unreadable saves instead of overwriting; preserve unknown fields/newer version on save; `play_mission` returns false when busy.
- [ ] **T4.1 Neuron and dendrite look**
- [ ] **T4.2 Living boundary and obstacles**
- [ ] **T4.3 Background**
- [ ] **T4.4 Crossing feedback, tension effects, completion wave**
- [ ] **T4.5 Animated interactive menus**
- [ ] **T4.6 Procedural audio**
- [ ] **T4.7 Glow and performance pass**

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
