extends Node
## Root scene (SDD 8.4): ScreenHost swaps the screens, Transition fades between them and the
## scene-local AudioDirector plays the procedural sounds for whatever screen ScreenHost shows.
## Starts on the main menu.

@onready var _screen_host: ScreenHost = $ScreenHost


func _ready() -> void:
	_screen_host.go_to(ScreenHost.Screen.MAIN_MENU)


func get_screen_host() -> ScreenHost:
	return _screen_host
