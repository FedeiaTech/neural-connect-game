class_name Palette
extends RefCounted
## Strict palette (SDD 1, 3, 5.4): black, white, red, light green, plus an amber crossing
## accent, violet lethal walls and cyan receptors (T7).
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
## Crossing feedback (T7.1): electric amber used for the neuron crossing ring and the spark
## markers. Dendrites never take this color: they keep their identity color and flicker.
const CROSSING := Color(1.0, 0.82, 0.32)
## Crossing spark markers: hot white-yellow core and amber glow.
const SPARK := Color(1.0, 0.95, 0.75)
const SPARK_GLOW := Color(1.0, 0.72, 0.25)
## Lethal walls (T7.2): electric violet membrane with a magenta crackle.
const LETHAL := Color(0.72, 0.32, 1.0)
const LETHAL_CRACKLE := Color(1.0, 0.45, 1.0)
## Overload explosion of a destroyed neuron.
const OVERLOAD_FLASH := Color(1.0, 0.75, 1.0)
## Receptor neurons and their dynamic links (T7.3).
const RECEPTOR := Color(0.36, 0.95, 1.0)
const RECEPTOR_GLOW := Color(0.35, 0.85, 1.0)
const LINK := Color(0.45, 0.96, 1.0)
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
