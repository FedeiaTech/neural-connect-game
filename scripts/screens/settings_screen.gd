class_name SettingsScreen
extends Control
## Minimal settings (SDD 5.5): master volume and reduced motion. Changes apply and save
## immediately through GameState; Back (or ui_cancel) emits back_pressed.
## T4.5: shown on the shared Background inside a glowing panel, with a GlowTitle and GlowButton.
## T6.1: "Reset progress" swaps itself for an inline confirmation (Cancel has focus, ui_cancel
## closes it); confirming calls GameState.reset_progress() and shows a short feedback line.
## T6.2: language selector (names shown in their own language, never translated); switching
## calls GameState.set_language() and every visible text follows at once.

signal back_pressed()

const PERCENT := 100.0
const COLUMN := "Center/Panel/Column/"
const RESET := COLUMN + "ResetBox/"
const FEEDBACK_TIME := 2.5
## GameState.LANGUAGES code -> name in that language.
const LANGUAGE_NAMES := {"en": "English", "es": "Español"}

@onready var _volume_slider: HSlider = get_node(COLUMN + "VolumeRow/VolumeSlider")
@onready var _volume_value: Label = get_node(COLUMN + "VolumeRow/VolumeValue")
@onready var _motion_toggle: CheckButton = get_node(COLUMN + "ReducedMotionToggle")
@onready var _back_button: Button = get_node(COLUMN + "BackButton")
@onready var _title: GlowTitle = get_node(COLUMN + "Title")
@onready var _language_selector: OptionButton = get_node(COLUMN + "LanguageRow/LanguageSelector")
@onready var _reset_button: Button = get_node(RESET + "ResetButton")
@onready var _confirm_row: Control = get_node(RESET + "ConfirmRow")
@onready var _confirm_button: Button = get_node(RESET + "ConfirmRow/ConfirmButton")
@onready var _cancel_button: Button = get_node(RESET + "ConfirmRow/CancelButton")
@onready var _feedback_label: Label = get_node(RESET + "FeedbackLabel")

var _feedback_serial := 0


func _ready() -> void:
	# Show the saved values before listening, so filling the controls does not re-save.
	_volume_slider.value = GameState.master_volume
	_motion_toggle.button_pressed = GameState.reduced_motion
	_update_volume_label(_volume_slider.value)
	_fill_languages()
	_language_selector.item_selected.connect(_on_language_selected)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_motion_toggle.toggled.connect(GameState.set_reduced_motion)
	_back_button.pressed.connect(back_pressed.emit)
	_reset_button.pressed.connect(_ask_reset)
	_confirm_button.pressed.connect(_confirm_reset)
	_cancel_button.pressed.connect(_close_reset)
	_volume_slider.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_cancel"):
		_mark_handled()
		if is_reset_confirm_visible():
			_close_reset()
		else:
			back_pressed.emit()


func get_volume_slider() -> HSlider:
	return _volume_slider


func get_reduced_motion_toggle() -> CheckButton:
	return _motion_toggle


func get_language_selector() -> OptionButton:
	return _language_selector


func get_title() -> GlowTitle:
	return _title


func get_back_button() -> Button:
	return _back_button


func get_reset_button() -> Button:
	return _reset_button


func get_reset_confirm_button() -> Button:
	return _confirm_button


func get_reset_cancel_button() -> Button:
	return _cancel_button


func is_reset_confirm_visible() -> bool:
	return _confirm_row.visible


func is_reset_feedback_visible() -> bool:
	return _feedback_label.visible


func _on_volume_changed(value: float) -> void:
	GameState.set_master_volume(value)
	_update_volume_label(value)


func _update_volume_label(value: float) -> void:
	_volume_value.text = "%d%%" % roundi(value * PERCENT)


func _fill_languages() -> void:
	for code in GameState.LANGUAGES:
		_language_selector.add_item(LANGUAGE_NAMES.get(code, code))
	_language_selector.select(maxi(GameState.LANGUAGES.find(GameState.language), 0))


func _on_language_selected(index: int) -> void:
	if index >= 0 and index < GameState.LANGUAGES.size():
		GameState.set_language(GameState.LANGUAGES[index])


func _ask_reset() -> void:
	_feedback_label.hide()
	_reset_button.hide()
	_confirm_row.show()
	_cancel_button.grab_focus()


func _confirm_reset() -> void:
	GameState.reset_progress()
	_close_reset()
	_feedback_label.show()
	_feedback_serial += 1
	if is_inside_tree():
		get_tree().create_timer(FEEDBACK_TIME).timeout.connect(_hide_feedback.bind(_feedback_serial))


func _close_reset() -> void:
	_confirm_row.hide()
	_reset_button.show()
	_reset_button.grab_focus()


func _hide_feedback(serial: int) -> void:
	if serial == _feedback_serial:
		_feedback_label.hide()


func _mark_handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()
