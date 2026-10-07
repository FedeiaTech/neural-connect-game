class_name MenuNetworkView
extends Control
## Living decoration behind the main menu (SDD 5.5): a DriftNetwork of soft glowing neurons joined
## by faint dendrites, each carrying an occasional electrical pulse. Neurons near the cursor
## brighten and drift away gently. Purely decorative: it ignores the mouse (it reads the cursor
## position itself) and never takes focus.
##
## Drawing: one Control, additive material, every glow is the shared GlowTexture so the whole
## network batches into a handful of draw calls. With motion it redraws every frame (intended
## animation); with reduced motion it only redraws while the cursor glow is still changing.

const NEURON_COUNT := 26
const SEED := 20261007
## No neuron rests behind the title and buttons (readability).
const KEEP_CLEAR := Vector2(900, 600)
const CORE_RADIUS := 3.6
const GLOW_RADIUS := 28.0
const EDGE_COLOR := Color(0.72, 0.86, 1.0, 0.14)
const EDGE_HOT_COLOR := Color(0.85, 0.94, 1.0, 0.45)
const NEURON_COLOR := Color(0.85, 0.93, 1.0)
## A pulse runs along each dendrite once per cycle (seconds), with a per-edge offset.
const PULSE_CYCLE := 5.0
const PULSE_TRAVEL := 1.2
const PULSE_RADIUS := 10.0
## Margin outside the screen so drifting neurons can enter from the edges.
const OVERSCAN := 60.0

var _network := DriftNetwork.new()
var _last_cursor := Vector2(-1.0e6, -1.0e6)
var _settled_frames := 0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = additive


func _ready() -> void:
	_rebuild()
	resized.connect(_rebuild)


func get_network() -> DriftNetwork:
	return _network


func _rebuild() -> void:
	var area := Rect2(Vector2.ZERO, size if size != Vector2.ZERO else Vector2(1920, 1080))
	var clear := Rect2(area.get_center() - KEEP_CLEAR * 0.5, KEEP_CLEAR)
	_network.build(area.grow(OVERSCAN), NEURON_COUNT, SEED, clear)
	queue_redraw()


func _process(delta: float) -> void:
	var cursor := get_local_mouse_position()
	var has_cursor := Rect2(Vector2.ZERO, size).has_point(cursor)
	var motion := VisualTuning.motion_scale()
	if motion <= 0.0:
		# Reduced motion: only react while the cursor moves and the glow settles.
		if cursor.is_equal_approx(_last_cursor):
			_settled_frames += 1
			if _settled_frames > 45:
				return
		else:
			_settled_frames = 0
	_last_cursor = cursor
	_network.step(delta, cursor, has_cursor, motion)
	queue_redraw()


## Drawn in three passes by primitive kind (lines, glow sprites, cores) so the canvas batches
## them into a few draw calls instead of alternating textured and untextured commands.
func _draw() -> void:
	var positions := _network.get_positions()
	var time := _network.get_time()
	var edges := _network.get_edges()
	for edge in edges:
		var heat := maxf(_network.get_brightness(edge.x), _network.get_brightness(edge.y))
		draw_line(positions[edge.x], positions[edge.y], EDGE_COLOR.lerp(EDGE_HOT_COLOR, heat), 1.4 + heat, true)
	if VisualTuning.is_motion_enabled():
		for e in edges.size():
			var u := (fposmod(time + float(e) * 0.73, PULSE_CYCLE)) / PULSE_TRAVEL
			if u <= 1.0:
				var edge := edges[e]
				GlowTexture.draw(self, positions[edge.x].lerp(positions[edge.y], u), PULSE_RADIUS,
					Color(NEURON_COLOR, 0.55 * sin(u * PI)))
	for i in positions.size():
		var glow := _network.get_brightness(i)
		GlowTexture.draw(self, positions[i], GLOW_RADIUS * (1.0 + glow * 0.8), Color(NEURON_COLOR, 0.3 + 0.5 * glow))
	for i in positions.size():
		var glow := _network.get_brightness(i)
		draw_circle(positions[i], CORE_RADIUS * (1.0 + glow * 0.5), Color(NEURON_COLOR, 0.55 + 0.45 * glow))
