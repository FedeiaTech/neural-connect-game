extends GdUnitTestSuite


func _theme_with_button_styles() -> Theme:
	var theme := Theme.new()
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style := StyleBoxFlat.new()
		style.content_margin_top = 12.0
		theme.set_stylebox(style_name, &"Button", style)
	return theme


func test_desktop_theme_is_left_untouched() -> void:
	var theme := _theme_with_button_styles()
	var font_before := theme.default_font_size
	PlatformProfile.apply_to_theme(theme, false)
	assert_int(theme.default_font_size).is_equal(font_before)
	assert_float(theme.get_stylebox(&"normal", &"Button").content_margin_top).is_equal(12.0)


func test_mobile_theme_gets_bigger_font_and_margins() -> void:
	var theme := _theme_with_button_styles()
	PlatformProfile.apply_to_theme(theme, true)
	assert_int(theme.default_font_size).is_equal(PlatformProfile.MOBILE_FONT_SIZE)
	for style_name: StringName in [&"normal", &"hover", &"pressed", &"hover_pressed", &"disabled"]:
		var style: StyleBox = theme.get_stylebox(style_name, &"Button")
		assert_float(style.content_margin_top).is_equal(PlatformProfile.MOBILE_BUTTON_MARGIN.y)
		assert_float(style.content_margin_left).is_equal(PlatformProfile.MOBILE_BUTTON_MARGIN.x)


func test_mobile_raises_small_buttons_and_keeps_big_ones() -> void:
	var root: Control = auto_free(Control.new())
	var small := Button.new()
	small.custom_minimum_size = Vector2(100, 40)
	var big := Button.new()
	big.custom_minimum_size = Vector2(500, 300)
	root.add_child(small)
	root.add_child(big)
	PlatformProfile.adapt_buttons(root, true)
	assert_vector(small.custom_minimum_size).is_equal(PlatformProfile.MOBILE_MIN_BUTTON_SIZE)
	assert_vector(big.custom_minimum_size).is_equal(Vector2(500, 300))


func test_compact_group_buttons_get_the_smaller_touch_minimum() -> void:
	var root: Control = auto_free(Control.new())
	var compact := Button.new()
	compact.add_to_group(PlatformProfile.COMPACT_GROUP)
	root.add_child(compact)
	PlatformProfile.adapt_buttons(root, true)
	assert_vector(compact.custom_minimum_size).is_equal(PlatformProfile.MOBILE_COMPACT_BUTTON_SIZE)


func test_mobile_grab_radius_is_more_generous_than_desktop() -> void:
	assert_float(PlatformProfile.grab_radius_factor(false)).is_equal(1.6)
	assert_float(PlatformProfile.grab_radius_factor(true)).is_greater(PlatformProfile.grab_radius_factor(false))


func test_desktop_leaves_buttons_alone() -> void:
	var root: Control = auto_free(Control.new())
	var button := Button.new()
	button.custom_minimum_size = Vector2(100, 40)
	root.add_child(button)
	PlatformProfile.adapt_buttons(root, false)
	assert_vector(button.custom_minimum_size).is_equal(Vector2(100, 40))
