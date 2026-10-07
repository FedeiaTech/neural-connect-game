extends GdUnitTestSuite
## T4.5: main menu motion logic — drifting decorative network, title letter fade-in and the
## reusable GlowButton hover/focus/ripple state, all honoring reduced motion.

const MainMenuScene := preload("res://scenes/screens/main_menu.tscn")

const RECT := Rect2(0, 0, 1920, 1080)

var _saved_reduced_motion := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = false


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion


func _network(seed: int = 7) -> DriftNetwork:
	var network := DriftNetwork.new()
	network.build(RECT, 24, seed)
	return network


# --- DriftNetwork ----------------------------------------------------------------

func test_network_build_is_deterministic_per_seed() -> void:
	var a := _network(7)
	var b := _network(7)
	var c := _network(8)
	assert_int(a.get_count()).is_equal(24)
	assert_array(Array(a.get_anchors())).is_equal(Array(b.get_anchors()))
	assert_array(Array(a.get_anchors())).is_not_equal(Array(c.get_anchors()))


func test_network_anchors_stay_inside_the_rect_and_apart() -> void:
	var network := _network()
	var anchors := network.get_anchors()
	for i in anchors.size():
		assert_bool(RECT.has_point(anchors[i])).is_true()
		for j in range(i + 1, anchors.size()):
			assert_float(anchors[i].distance_to(anchors[j])).is_greater(DriftNetwork.MIN_SPACING * 0.99)


func test_network_keeps_the_menu_area_clear() -> void:
	var clear := Rect2(560, 180, 800, 620)
	var network := DriftNetwork.new()
	network.build(RECT, 24, 7, clear)
	assert_int(network.get_count()).is_greater(10)
	for anchor in network.get_anchors():
		assert_bool(clear.has_point(anchor)).override_failure_message(str(anchor)).is_false()


func test_network_edges_are_valid_unique_and_cover_every_neuron() -> void:
	var network := _network()
	var seen := {}
	var degree := PackedInt32Array()
	degree.resize(network.get_count())
	for edge in network.get_edges():
		assert_bool(edge.x >= 0 and edge.x < network.get_count()).is_true()
		assert_bool(edge.y >= 0 and edge.y < network.get_count()).is_true()
		assert_bool(edge.x < edge.y).is_true()
		assert_bool(seen.has(edge)).is_false()
		seen[edge] = true
		degree[edge.x] += 1
		degree[edge.y] += 1
	for d in degree:
		assert_int(d).is_greater_equal(1)


func test_network_drifts_with_motion() -> void:
	var network := _network()
	network.step(1.5, Vector2.ZERO, false, 1.0)
	var moved := false
	for i in network.get_count():
		if network.get_position(i).distance_to(network.get_anchors()[i]) > 0.5:
			moved = true
	assert_bool(moved).is_true()


func test_cursor_brightens_and_pushes_nearby_neurons_away() -> void:
	var network := _network()
	var target := 5
	var cursor := network.get_anchors()[target] + Vector2(30, 0)
	var calm := _network()
	for frame in 30:
		network.step(1.0 / 30.0, cursor, true, 1.0)
		calm.step(1.0 / 30.0, cursor, false, 1.0)
	assert_float(network.get_brightness(target)).is_greater(0.5)
	assert_float(calm.get_brightness(target)).is_equal_approx(0.0, 0.001)
	assert_float(network.get_position(target).distance_to(cursor)) \
		.is_greater(calm.get_position(target).distance_to(cursor))


func test_reduced_motion_freezes_positions_but_still_brightens() -> void:
	var network := _network()
	var cursor := network.get_anchors()[3]
	for frame in 30:
		network.step(1.0 / 30.0, cursor, true, 0.0)
	for i in network.get_count():
		assert_vector(network.get_position(i)).is_equal(network.get_anchors()[i])
	assert_float(network.get_brightness(3)).is_greater(0.5)


func test_far_cursor_does_not_affect_a_neuron() -> void:
	var network := _network()
	var far := network.get_anchors()[0] + Vector2(DriftNetwork.CURSOR_RADIUS * 3.0, 0)
	if not RECT.has_point(far):
		far = network.get_anchors()[0] - Vector2(DriftNetwork.CURSOR_RADIUS * 3.0, 0)
	assert_float(DriftNetwork.influence(network.get_anchors()[0], far)).is_equal(0.0)
	assert_float(DriftNetwork.influence(far, far)).is_equal(1.0)


# --- GlowTitle -----------------------------------------------------------------

func test_title_letters_fade_in_one_after_another() -> void:
	assert_float(GlowTitle.letter_alpha(0, 0.0)).is_equal(0.0)
	var mid := GlowTitle.LETTER_DELAY * 3.0 + GlowTitle.LETTER_FADE * 0.5
	assert_float(GlowTitle.letter_alpha(3, mid)).is_equal_approx(0.5, 0.01)
	assert_float(GlowTitle.letter_alpha(4, mid)).is_less(GlowTitle.letter_alpha(3, mid))
	assert_float(GlowTitle.letter_alpha(0, GlowTitle.LETTER_FADE)).is_equal(1.0)
	assert_float(GlowTitle.reveal_duration(14)).is_equal_approx(
		GlowTitle.LETTER_DELAY * 13.0 + GlowTitle.LETTER_FADE, 0.0001)


func test_title_with_reduced_motion_is_fully_visible_at_once() -> void:
	GameState.reduced_motion = true
	var title: GlowTitle = auto_free(GlowTitle.new())
	title.text = "Neural Connect"
	add_child(title)
	assert_bool(title.is_revealed()).is_true()


func test_title_reveal_runs_with_motion() -> void:
	var title: GlowTitle = auto_free(GlowTitle.new())
	title.text = "Neural Connect"
	add_child(title)
	assert_bool(title.is_revealed()).is_false()
	title.advance(GlowTitle.reveal_duration(title.text.length()) + 0.01)
	assert_bool(title.is_revealed()).is_true()


# --- GlowButton ----------------------------------------------------------------

func _button() -> GlowButton:
	var button: GlowButton = auto_free(GlowButton.new())
	button.text = "Play"
	button.size = Vector2(200, 60)
	add_child(button)
	return button


func test_glow_button_glows_on_hover_and_focus() -> void:
	var button := _button()
	assert_bool(button.is_glowing()).is_false()
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_bool(button.is_glowing()).is_true()
	button.notification(Control.NOTIFICATION_MOUSE_EXIT)
	assert_bool(button.is_glowing()).is_false()
	button.grab_focus()
	assert_bool(button.is_glowing()).is_true()
	button.release_focus()
	assert_bool(button.is_glowing()).is_false()


func test_disabled_glow_button_ignores_hover() -> void:
	var button := _button()
	button.disabled = true
	button.notification(Control.NOTIFICATION_MOUSE_ENTER)
	assert_bool(button.is_glowing()).is_false()


func test_glow_button_ripples_on_press_unless_reduced_motion() -> void:
	var button := _button()
	button.button_down.emit()
	assert_bool(button.is_rippling()).is_true()
	await await_millis(int(GlowButton.RIPPLE_TIME * 1000.0) + 150)
	assert_bool(button.is_rippling()).is_false()
	GameState.reduced_motion = true
	button.button_down.emit()
	assert_bool(button.is_rippling()).is_false()


# --- MainMenu ------------------------------------------------------------------

func test_main_menu_has_living_background_network_and_glow_buttons() -> void:
	var menu: MainMenu = auto_free(MainMenuScene.instantiate())
	add_child(menu)
	assert_object(menu.get_node_or_null(^"Background")).is_instanceof(BackgroundView)
	assert_object(menu.get_network_view()).is_instanceof(MenuNetworkView)
	assert_object(menu.get_play_button()).is_instanceof(GlowButton)
	assert_object(menu.get_settings_button()).is_instanceof(GlowButton)
	assert_bool(menu.get_play_button().has_focus()).is_true()
	assert_int(menu.get_network_view().mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
