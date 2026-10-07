class_name SettingsScreen
extends Control
## Minimal settings (SDD 5.5): master volume and reduced motion. Changes apply and save
## immediately through GameState; Back (or ui_cancel) emits back_pressed.

signal back_pressed()

const PERCENT := 100.0

@onready var _volume_slider: HSlider = $Center/Column/VolumeRow/VolumeSlider
@onready var _volume_value: Label = $Center/Column/VolumeRow/VolumeValue
@onready var _motion_toggle: CheckButton = $Center/Column/ReducedMotionToggle
@onready var _back_button: Button = $Center/Column/BackButton


func _ready() -> void:
	# Show the saved values before listening, so filling the controls does not re-save.
	_volume_slider.value = GameState.master_volume
	_motion_toggle.button_pressed = GameState.reduced_motion
	_update_volume_label(_volume_slider.value)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_motion_toggle.toggled.connect(GameState.set_reduced_motion)
	_back_button.pressed.connect(back_pressed.emit)
	_volume_slider.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()


func get_volume_slider() -> HSlider:
	return _volume_slider


func get_reduced_motion_toggle() -> CheckButton:
	return _motion_toggle


func get_back_button() -> Button:
	return _back_button


func _on_volume_changed(value: float) -> void:
	GameState.set_master_volume(value)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	_volume_value.text = "%d%%" % roundi(value * PERCENT)
