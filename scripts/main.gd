extends Node
## Root scene (SDD 8.4): ScreenHost swaps the screens, Transition fades between them and the
## scene-local AudioDirector plays the procedural sounds for whatever screen ScreenHost shows.
## Starts on the studio brand splash, which leads to the main menu. Tests that only need the
## menu turn it off before adding the scene.

## Show the Chainsaw Games splash first. Set before the node enters the tree.
var show_brand_intro := true

@onready var _screen_host: ScreenHost = $ScreenHost


func _ready() -> void:
	_screen_host.go_to(ScreenHost.Screen.BRAND_INTRO if show_brand_intro else ScreenHost.Screen.MAIN_MENU)


func get_screen_host() -> ScreenHost:
	return _screen_host
