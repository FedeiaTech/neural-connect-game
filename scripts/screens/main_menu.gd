class_name MainMenu
extends Control
## Title screen (SDD 5.5): Play, Settings, Quit. Emits intent only; ScreenHost navigates.
## Quit is hidden where apps do not quit themselves (web, mobile).
## Living look (T4.5): the shared bioluminescent Background, a drifting neuron network that reacts
## to the cursor (MenuNetworkView), an animated GlowTitle and GlowButtons. The subtitle and the
## buttons fade in after the title starts; reduced motion shows everything at once.

signal play_pressed()
signal settings_pressed()
signal credits_pressed()
signal quit_pressed()

const ENTRANCE_DELAY := 0.45
const ENTRANCE_STAGGER := 0.09
const ENTRANCE_TIME := 0.5

@onready var _version_label: Label = $VersionLabel
@onready var _network: MenuNetworkView = $Network
@onready var _title: GlowTitle = $Center/Column/Title
@onready var _subtitle: Label = $Center/Column/Subtitle
@onready var _play_button: Button = $Center/Column/PlayButton
@onready var _settings_button: Button = $Center/Column/SettingsButton
@onready var _credits_button: Button = $Center/Column/CreditsButton
@onready var _quit_button: Button = $Center/Column/QuitButton


## "v1.01": the project version (Project Settings > Application > Config > Version).
static func version_text() -> String:
	return "v%s" % ProjectSettings.get_setting("application/config/version", "?")


func _ready() -> void:
	_version_label.text = version_text()
	_play_button.pressed.connect(play_pressed.emit)
	_settings_button.pressed.connect(settings_pressed.emit)
	_credits_button.pressed.connect(credits_pressed.emit)
	_quit_button.pressed.connect(quit_pressed.emit)
	_quit_button.visible = not (OS.has_feature("web") or OS.has_feature("mobile"))
	_play_button.grab_focus()
	_play_entrance()


func get_title_text() -> String:
	return _title.text


func get_network_view() -> MenuNetworkView:
	return _network


func get_play_button() -> Button:
	return _play_button


func get_settings_button() -> Button:
	return _settings_button


func get_credits_button() -> Button:
	return _credits_button


func get_quit_button() -> Button:
	return _quit_button


func _play_entrance() -> void:
	if not VisualTuning.is_motion_enabled():
		return
	var items: Array[Control] = [_subtitle, _play_button, _settings_button, _credits_button, _quit_button]
	var tween := create_tween().set_parallel(true)
	for i in items.size():
		items[i].modulate.a = 0.0
		tween.tween_property(items[i], ^"modulate:a", 1.0, ENTRANCE_TIME) \
			.set_delay(ENTRANCE_DELAY + i * ENTRANCE_STAGGER) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
