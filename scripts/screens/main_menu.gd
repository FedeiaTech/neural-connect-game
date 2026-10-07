class_name MainMenu
extends Control
## Title screen (SDD 5.5): Play, Settings, Quit. Emits intent only; ScreenHost navigates.
## Quit is hidden where apps do not quit themselves (web, mobile). Phase 4 adds the living background.

signal play_pressed()
signal settings_pressed()
signal quit_pressed()

@onready var _title: Label = $Center/Column/Title
@onready var _play_button: Button = $Center/Column/PlayButton
@onready var _settings_button: Button = $Center/Column/SettingsButton
@onready var _quit_button: Button = $Center/Column/QuitButton


func _ready() -> void:
	_play_button.pressed.connect(play_pressed.emit)
	_settings_button.pressed.connect(settings_pressed.emit)
	_quit_button.pressed.connect(quit_pressed.emit)
	_quit_button.visible = not (OS.has_feature("web") or OS.has_feature("mobile"))
	_play_button.grab_focus()


func get_title_text() -> String:
	return _title.text


func get_play_button() -> Button:
	return _play_button


func get_settings_button() -> Button:
	return _settings_button


func get_quit_button() -> Button:
	return _quit_button
