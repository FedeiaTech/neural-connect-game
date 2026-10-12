class_name VisualTuning
extends RefCounted
## Tunables and pure helpers for the bioluminescent look (SDD 5.3, 5.4). Views read these;
## nothing here touches the model. Colors live in Palette.
##
## Every animated effect is scaled by motion_scale(): 0 when GameState.reduced_motion is on.

# --- Neurons -------------------------------------------------------------------
## Quad half size in soma radii (soma, processes and halo).
const NEURON_QUAD_EXTENT := 2.9
const NEURON_GLOW_STRENGTH := 0.38
const NEURON_PULSE_SPEED := 1.8
const NEURON_PULSE_DEPTH := 0.1
## Fixed (red) neurons: slower, heavier pulse.
const FIXED_PULSE_SPEED := 0.85
const FIXED_PULSE_DEPTH := 0.22
## Opacity of the dendrites and axon behind the soma (they sit above the connection lines).
const NEURON_ARM_ALPHA := 0.92
const GRAB_BRIGHTNESS := 1.35
const GRAB_TWEEN_TIME := 0.16
## Crossing warmth fades in/out at this rate (amount per second).
const HIGHLIGHT_RATE := 4.0
## Crossing "latency" glow on involved neurons: slow breathing (rad/s), halo strength, and the
## strength of the occasional light sparkle around the soma (0 with reduced motion).
const LATENCY_SPEED := 1.1
const LATENCY_GLOW := 0.5
const LATENCY_SPARKLE := 1.0

# --- Dendrites -----------------------------------------------------------------
## Glow quad half thickness (beyond the core).
const DENDRITE_HALF_WIDTH := 16.0
const DENDRITE_GLOW_STRENGTH := 0.35
const DENDRITE_SEGMENT_LENGTH := 24.0
## Seconds between two electrical pulses on one dendrite, and pulse speed in px/s.
const PULSE_INTERVAL := 4.5
const PULSE_SPEED := 380.0
const PULSE_STRENGTH := 0.7
## Tension warning (tremble + flicker) starts at this ratio and peaks at 1.
const TENSION_WARNING_START := 0.6
const MAX_TREMBLE := 3.0
const MAX_FLICKER := 0.55

# --- Membrane (boundary and obstacles) -------------------------------------------
const MEMBRANE_SPACING := 12.0
const BOUNDARY_AMPLITUDE := 2.8
const OBSTACLE_AMPLITUDE := 1.5
const MEMBRANE_WAVELENGTH_A := 680.0
const MEMBRANE_WAVELENGTH_B := 310.0
const MEMBRANE_SPEED_A := 0.55
const MEMBRANE_SPEED_B := 0.9
const MEMBRANE_BREATH_SPEED := 0.45
const RIPPLE_AMPLITUDE := 7.0
const RIPPLE_WIDTH := 40.0
const RIPPLE_SPREAD := 140.0
const RIPPLE_LIFETIME := 1.6
const RIPPLE_COOLDOWN := 0.35
const RIPPLE_MAX := 4
const EXHALE_AMPLITUDE := 9.0

# --- Completion wave -----------------------------------------------------------
## Delay per graph step and time for the light to cross one dendrite.
const WAVE_STEP := 0.18
const WAVE_TRAVEL := 0.22
const WAVE_BRIGHTNESS := 2.2
const WAVE_TAIL := 0.45

# --- Tension break -------------------------------------------------------------
const BREAK_FLASH_TIME := 0.45
const SHAKE_TIME := 0.3
const SHAKE_STRENGTH := 9.0

# --- Lethal walls (T7.2) ---------------------------------------------------------
## Overload tremble before the explosion; the restart waits LevelController.DESTROY_RESTART_DELAY.
const OVERLOAD_TIME := 0.35
## Soma overload tint at full hazard proximity (warning while approaching a lethal wall).
const HAZARD_OVERLOAD := 0.35
const EXPLOSION_FLASH_TIME := 0.6
const EXPLOSION_SHAKE_STRENGTH := 14.0

# --- Toxic neurons (T8.2) -----------------------------------------------------------
## Faint warning glow of a toxic neuron at rest (1.0 while it contaminates a receptor).
const TOXIC_WARN_IDLE := 0.3
## Warning glow eases at this rate (amount per second).
const TOXIC_WARN_RATE := 5.0

# --- Diseased dendrites (T8.3) --------------------------------------------------------
## Cracks start opening at this strain ratio and peak at 1.
const DISEASED_CRACK_START := 0.35
const DISEASED_SNAP_TIME := 0.5
const DISEASED_WIDTH_REST := 3.8
const DISEASED_WIDTH_BREAK := 1.7
## Light shake of a snap (a fraction of the tension break shake).
const DISEASED_SHAKE_FACTOR := 0.45

const GOLDEN_ANGLE := 2.39996323


## -1 = automatic (low quality on Android), 0 = forced off, 1 = forced on. Tests use the override.
static var _low_quality_override := -1


## Low quality trims the costliest GPU/CPU extras (neuron nucleus shading, crossing sparkle,
## background spores, half-size particle bursts) for weak mobile GPUs. Gameplay is unchanged.
static func is_low_quality() -> bool:
	if _low_quality_override >= 0:
		return _low_quality_override == 1
	return OS.has_feature("android")


static func set_low_quality_override(mode: int) -> void:
	_low_quality_override = clampi(mode, -1, 1)


static func is_motion_enabled() -> bool:
	return not GameState.reduced_motion


## 1.0 normally, 0.0 with reduced motion. Multiplies every animated term.
static func motion_scale() -> float:
	return 1.0 if is_motion_enabled() else 0.0


## Per-element phase in [0, TAU) so neighbours never pulse in sync.
static func phase_for(id: int) -> float:
	return fposmod(float(id) * GOLDEN_ANGLE, TAU)


static func tension_width(ratio: float) -> float:
	return lerpf(DendriteView.WIDTH, DendriteView.MIN_TENSION_WIDTH, clampf(ratio, 0.0, 1.0))


## Sideways tremble amplitude in px: 0 below TENSION_WARNING_START, MAX_TREMBLE at the limit.
static func tension_tremble(ratio: float) -> float:
	return MAX_TREMBLE * _warning(ratio)


## Line width of a diseased dendrite: thick and rotten at rest, thinning towards the break.
static func diseased_width(ratio: float) -> float:
	return lerpf(DISEASED_WIDTH_REST, DISEASED_WIDTH_BREAK, clampf(ratio, 0.0, 1.0))


## Crack amount 0..1 of a diseased dendrite: 0 below DISEASED_CRACK_START, 1 at its break length.
static func diseased_crack(ratio: float) -> float:
	var t := clampf((ratio - DISEASED_CRACK_START) / (1.0 - DISEASED_CRACK_START), 0.0, 1.0)
	return t * t


## Warning flicker depth 0..MAX_FLICKER, rising towards the limit.
static func tension_flicker(ratio: float) -> float:
	return MAX_FLICKER * _warning(ratio)


## Moves current towards target by rate * delta without overshooting.
static func approach(current: float, target: float, rate: float, delta: float) -> float:
	return move_toward(current, target, rate * delta)


static func _warning(ratio: float) -> float:
	var t := clampf((ratio - TENSION_WARNING_START) / (1.0 - TENSION_WARNING_START), 0.0, 1.0)
	return t * t
