# Feature: sparks-hazards-synapses

Objective: user-approved design (2026-10-07) — three gameplay/readability additions, all with animations and procedural sounds.
Branch: `feat/mvp-foundation`. Slice base: `b9b3de8` (phase 6 slice review started, blocked by a tool timeout).

## Approved design
1. **Crossing marks without recoloring**: a dendrite keeps its identity color (white / tension green / receptor cyan) when crossing. Crossing is shown by (a) crackling spark markers at each exact intersection point, (b) flicker of involved dendrites (no color replacement), (c) soft electric buzz loop while crossings exist. Neuron crossing highlight must not be confused with red fixed neurons.
2. **Lethal walls**: some boundary segments and/or obstacles are lethal (electric violet/magenta, crackling membrane). Proximity warning (glow + rising alarm tone) as a neuron approaches; on contact the neuron overloads, trembles, explodes in particles with flash + sound → level lost → quick restart (like a tension break). Variants: lethal boundary sides; lethal interior obstacles in advanced levels.
3. **Receptor neurons** (cyan, immovable): show a reach halo (soft pulsing ring) and a searching dendrite stub; need N connections (dots indicator; N=1 early, 2 later). When a movable neuron enters the halo, a dendrite grows to it (closest candidate wins) with an ascending synaptic click and cyan flash. Moving it out beyond reach: the dendrite stretches, trembles, snaps with sparks/sound (no loss, just disconnected). Near the reach limit the link thins and flickers. Win = all receptors fully connected AND zero crossings (dynamic links count). Completion wave travels through dynamic links. New chapter "Synapses" before "Convergence"; later combine with lethal walls and tension.

## Tasks (route: delegated direct)
- [ ] T7.1 Crossing points + spark markers + identity-preserving highlight + buzz
- [ ] T7.2 Lethal walls (model, validation, views, fx, audio)
- [ ] T7.3 Receptor neurons and dynamic links (model, validation, views, fx, audio)
- [ ] T7.4 Content: chapter "Synapses" + lethal-wall missions + combinations; translations en/es; solvability proofs
- [ ] T7.5 Docs: SDD + plan

## Progress / evidence

(none yet)

Engram mirror: pending (engram MCP unavailable this session).
