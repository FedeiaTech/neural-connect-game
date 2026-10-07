extends GdUnitTestSuite
## T2.1: BoundaryView and ObstacleView build closed outlines from model polygons.

const LevelFactory := preload("res://tests/model/level_factory.gd")
const BoundaryScene := preload("res://scenes/views/boundary.tscn")
const ObstacleScene := preload("res://scenes/views/obstacle_view.tscn")


func test_boundary_outline_is_closed_play_area() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view: BoundaryView = auto_free(BoundaryScene.instantiate())
	view.setup(model)
	var outline := view.get_outline()
	assert_int(outline.size()).is_equal(5)
	assert_vector(outline[0]).is_equal(outline[4])
	assert_float(view.get_line_width()).is_greater(DendriteView.WIDTH)


func test_boundary_records_last_contact() -> void:
	var model := PuzzleModel.from_level(LevelFactory.x_level())
	var view: BoundaryView = auto_free(BoundaryScene.instantiate())
	view.setup(model)
	model.grab(0)
	model.drag_to(Vector2(-100, 100))
	assert_vector(view.get_last_contact()).is_equal(model.get_neuron_position(0))


func test_obstacle_outline_is_closed_polygon() -> void:
	var view: ObstacleView = auto_free(ObstacleScene.instantiate())
	view.setup(LevelFactory.rect(Vector2(10, 10), Vector2(50, 50)))
	var outline := view.get_outline()
	assert_int(outline.size()).is_equal(5)
	assert_vector(outline[4]).is_equal(Vector2(10, 10))
	assert_float(view.get_line_width()).is_greater(DendriteView.WIDTH)
