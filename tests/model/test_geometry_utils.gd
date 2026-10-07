extends GdUnitTestSuite
## Pure geometry helpers used by PuzzleModel.

const SQUARE := [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]


func test_segments_cross_when_they_intersect() -> void:
	assert_bool(GeometryUtils.segments_cross(
		Vector2(0, 0), Vector2(10, 10), Vector2(0, 10), Vector2(10, 0))).is_true()


func test_segments_do_not_cross_when_apart() -> void:
	assert_bool(GeometryUtils.segments_cross(
		Vector2(0, 0), Vector2(10, 0), Vector2(0, 5), Vector2(10, 5))).is_false()


func test_segment_touching_another_with_an_endpoint_crosses() -> void:
	assert_bool(GeometryUtils.segments_cross(
		Vector2(0, 0), Vector2(10, 0), Vector2(5, 0), Vector2(5, 10))).is_true()


func test_collinear_overlapping_segments_cross() -> void:
	assert_bool(GeometryUtils.segments_cross(
		Vector2(0, 0), Vector2(10, 0), Vector2(5, 0), Vector2(15, 0))).is_true()


func test_collinear_disjoint_segments_do_not_cross() -> void:
	assert_bool(GeometryUtils.segments_cross(
		Vector2(0, 0), Vector2(10, 0), Vector2(11, 0), Vector2(20, 0))).is_false()


func test_circle_inside_polygon() -> void:
	var square := PackedVector2Array(SQUARE)
	assert_bool(GeometryUtils.is_circle_inside_polygon(Vector2(50, 50), 10.0, square)).is_true()
	assert_bool(GeometryUtils.is_circle_inside_polygon(Vector2(5, 50), 10.0, square)).is_false()
	assert_bool(GeometryUtils.is_circle_inside_polygon(Vector2(150, 50), 10.0, square)).is_false()


func test_circle_overlaps_polygon() -> void:
	var square := PackedVector2Array(SQUARE)
	assert_bool(GeometryUtils.does_circle_overlap_polygon(Vector2(50, 50), 10.0, square)).is_true()
	assert_bool(GeometryUtils.does_circle_overlap_polygon(Vector2(105, 50), 10.0, square)).is_true()
	assert_bool(GeometryUtils.does_circle_overlap_polygon(Vector2(115, 50), 10.0, square)).is_false()
