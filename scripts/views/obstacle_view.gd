class_name ObstacleView
extends MembraneView
## One obstacle polygon (SDD 5.3): thick white outline drawn as a calmer membrane than the
## boundary (smaller undulation, softer glow). Obstacles never move; with a model it ripples
## where a neuron touches it.

const LINE_WIDTH := 5.0


func _init() -> void:
	_amplitude = VisualTuning.OBSTACLE_AMPLITUDE
	_line_width = LINE_WIDTH
	_color = Palette.OBSTACLE
	_glow_scale = 0.7


func setup(polygon: PackedVector2Array, model: PuzzleModel = null) -> void:
	_setup_membrane(polygon, model)
