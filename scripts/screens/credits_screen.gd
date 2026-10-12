class_name CreditsScreen
extends Control
## Credits: studio, developer and copyright, on the shared Background inside a glowing panel.
## Emits intent only: back_pressed on Back or ui_cancel; ScreenHost navigates.
## Names and the copyright line are literals (never translated); the rest are translation keys.

signal back_pressed()

const COLUMN := "Center/Panel/Column/"

@onready var _back_button: Button = get_node(COLUMN + "BackButton")


func _ready() -> void:
	_back_button.pressed.connect(back_pressed.emit)
	_back_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		back_pressed.emit()


func get_back_button() -> Button:
	return _back_button
