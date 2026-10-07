class_name Palette
extends RefCounted
## Strict palette (SDD 1, 3, 5.4): black, white, red, light green, plus a warm crossing accent.
## Keeping every color here means the aesthetics can change without touching view logic.

const BACKGROUND := Color(0.0, 0.0, 0.0)
const NEURON := Color(1.0, 1.0, 1.0)
const NEURON_GRABBED := Color(1.0, 1.0, 0.92)
const NEURON_FIXED := Color(0.9, 0.16, 0.2)
## Halo colors (added on top of the black background).
const NEURON_GLOW := Color(0.78, 0.9, 1.0)
const NEURON_FIXED_GLOW := Color(1.0, 0.22, 0.24)
const DENDRITE := Color(1.0, 1.0, 1.0, 0.9)
const TENSION := Color(0.62, 1.0, 0.62)
## Crossing feedback (dendrites and the neurons at their ends).
const CROSSING := Color(1.0, 0.5, 0.38)
const CONTACT := Color(1.0, 1.0, 1.0, 0.6)
const BOUNDARY := Color(1.0, 1.0, 1.0)
const OBSTACLE := Color(1.0, 1.0, 1.0)
## Soft glow drawn around the membrane outlines (additive).
const MEMBRANE_GLOW := Color(0.75, 0.88, 1.0, 0.09)
const MEMBRANE_GLOW_WIDE := Color(0.75, 0.88, 1.0, 0.035)
## Background spores and vignette.
const SPORE := Color(0.8, 0.92, 1.0, 0.16)
const VIGNETTE := Color(0.0, 0.0, 0.0, 0.85)
## Tension break flash.
const BREAK_FLASH := Color(0.85, 1.0, 0.85)
