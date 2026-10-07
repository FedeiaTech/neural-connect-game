extends GdUnitTestSuite
## T7.2: lethal walls look (violet crackling membrane glowing with proximity) and the overload
## explosion (tremble, burst, flash, shake) when a neuron touches one.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const LevelScene := preload("res://scenes/level/level.tscn")

var _level: Level
var _saved_reduced_motion := false


func before_test() -> void:
	_saved_reduced_motion = GameState.reduced_motion
	GameState.reduced_motion = false
	_level = auto_free(LevelScene.instantiate())
	add_child(_level)


func after_test() -> void:
	GameState.reduced_motion = _saved_reduced_motion


## X tangle plus neuron 4 at (500, 300); right side (edge 1) lethal, island 0 lethal.
func _lethal_level() -> LevelData:
	var level := LevelFactory.x_level()
	level.neurons.append(LevelFactory.neuron(4, Vector2(500, 300)))
	level.obstacles = [LevelFactory.rect(Vector2(700, 700), Vector2(100, 100)),
		LevelFactory.rect(Vector2(200, 750), Vector2(80, 80))]
	level.lethal_edges = PackedInt32Array([1])
	level.lethal_obstacles = PackedInt32Array([0])
	return level


func _load() -> LevelController:
	_level.load_level(_lethal_level())
	_level.get_controller().start_playing()
	return _level.get_controller()


func _walls() -> LethalWallView:
	return _level.get_node(^"Playfield/LethalWalls")


func test_boundary_paints_only_lethal_sides_violet() -> void:
	_load()
	var boundary: BoundaryView = _level.get_node(^"Playfield/Boundary")
	var colors := boundary.get_point_colors()
	assert_bool(colors.has(Palette.LETHAL)).is_true()
	assert_bool(colors.has(Palette.BOUNDARY)).is_true()
	# Mid-point of the lethal right side, and of the safe left side.
	assert_that(boundary.get_color_at(Vector2(1000, 500))).is_equal(Palette.LETHAL)
	assert_that(boundary.get_color_at(Vector2(0, 500))).is_equal(Palette.BOUNDARY)


func test_lethal_obstacle_is_violet_and_plain_one_white() -> void:
	_load()
	var obstacles := _level.get_node(^"Playfield/Obstacles").get_children()
	assert_that((obstacles[0] as ObstacleView).get_color()).is_equal(Palette.LETHAL)
	assert_bool((obstacles[0] as ObstacleView).is_lethal()).is_true()
	assert_that((obstacles[1] as ObstacleView).get_color()).is_equal(Palette.OBSTACLE)


func test_lethal_wall_view_covers_every_lethal_segment() -> void:
	_load()
	assert_int(_walls().get_segment_count()).is_equal(5)


func test_wall_glows_stronger_as_the_grabbed_neuron_approaches() -> void:
	var controller := _load()
	var walls := _walls()
	walls._process(0.1)
	var calm := walls.get_glow()
	var model := controller.get_model()
	model.grab(4)
	model.drag_to(Vector2(1000.0 - 28.0 - 10.0, 300))
	for i in 20:
		walls._process(0.05)
	assert_float(walls.get_glow()).is_greater(calm + 0.5)
	assert_vector(walls.get_hotspot()).is_equal_approx(Vector2(1000, 300), Vector2(0.5, 0.5))
	assert_int(walls.get_crackle_count()).is_greater(0)


func test_reduced_motion_keeps_the_wall_still() -> void:
	GameState.reduced_motion = true
	_load()
	var walls := _walls()
	walls._process(0.1)
	assert_int(walls.get_crackle_count()).is_equal(0)


func test_contact_overloads_the_neuron_then_explodes() -> void:
	var controller := _load()
	var model := controller.get_model()
	var fx: LevelFx = _level.get_node(^"Playfield/Fx")
	var view := controller.get_neuron_view(4)
	var shakes_before := fx.get_explosion_count()
	model.grab(4)
	model.drag_to(Vector2(1200, 300))
	assert_bool(model.is_destroyed()).is_true()
	assert_bool(view.is_overloading()).is_true()
	assert_bool(view.visible).is_true()
	# The explosion follows the overload tremble.
	assert_int(fx.get_explosion_count()).is_equal(shakes_before)
	for i in 30:
		fx._process(0.03)
		view._process(0.03)
	assert_int(fx.get_explosion_count()).is_equal(shakes_before + 1)
	assert_bool(view.visible).is_false()
	assert_bool(fx.is_flashing() or fx.is_shaking()).is_true()


func test_reduced_motion_explosion_is_a_flash_only() -> void:
	GameState.reduced_motion = true
	var controller := _load()
	var model := controller.get_model()
	var fx: LevelFx = _level.get_node(^"Playfield/Fx")
	model.grab(4)
	model.drag_to(Vector2(1200, 300))
	for i in 30:
		fx._process(0.03)
	assert_bool(fx.is_shaking()).is_false()
	assert_int(fx.get_burst_count()).is_equal(0)
