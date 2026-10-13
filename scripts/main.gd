extends Node
## Root scene (SDD 8.4): ScreenHost swaps the screens, Transition fades between them and the
## scene-local AudioDirector plays the procedural sounds for whatever screen ScreenHost shows.
## Starts on the studio brand splash, which leads to the main menu. Tests that only need the
## menu turn it off before adding the scene.

## Show the Chainsaw Games splash first. Set before the node enters the tree.
var show_brand_intro := true
## A diagnostic run in progress (DiagnosticRunner) takes over the launch: its screen continues with
## the step after the one the app died in. Set before the node enters the tree.
var diagnostics_state_path := DiagnosticState.DEFAULT_PATH

@onready var _screen_host: ScreenHost = $ScreenHost


func _ready() -> void:
	if DiagnosticState.is_active_on_disk(diagnostics_state_path):
		_screen_host.go_to(ScreenHost.Screen.DIAGNOSTICS)
		return
	_screen_host.go_to(ScreenHost.Screen.BRAND_INTRO if show_brand_intro else ScreenHost.Screen.MAIN_MENU)


func get_screen_host() -> ScreenHost:
	return _screen_host
