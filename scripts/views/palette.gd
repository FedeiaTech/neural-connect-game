class_name Palette
extends RefCounted
## Placeholder MVP palette (SDD 1, 3, 5.4). Phase 4 restyles the views; keeping every color
## here means the aesthetics can change without touching view logic.

const BACKGROUND := Color(0.0, 0.0, 0.0)
const NEURON := Color(1.0, 1.0, 1.0)
const NEURON_GRABBED := Color(1.0, 1.0, 0.92)
const NEURON_FIXED := Color(0.9, 0.16, 0.2)
const DENDRITE := Color(1.0, 1.0, 1.0, 0.9)
const TENSION := Color(0.62, 1.0, 0.62)
## Crossing feedback (dendrites and the neurons at their ends).
const CROSSING := Color(1.0, 0.5, 0.38)
const CONTACT := Color(1.0, 1.0, 1.0, 0.6)
const BOUNDARY := Color(1.0, 1.0, 1.0)
const OBSTACLE := Color(1.0, 1.0, 1.0)
