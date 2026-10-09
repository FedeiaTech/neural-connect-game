extends GdUnitTestSuite
## T8.5: the authoring helpers are deterministic (committed data stays byte-stable) and produce
## sound outlines and layouts.

const Organic := preload("res://tools/organic_shapes.gd")
const Layouts := preload("res://tools/layouts.gd")
const Builder := preload("res://tools/build_levels.gd")


func test_polar_is_deterministic_and_positively_oriented() -> void:
	var a := Organic.polar(Vector2(960, 570), 600.0, 380.0, [[3, 0.16, 0.5]], 120)
	var b := Organic.polar(Vector2(960, 570), 600.0, 380.0, [[3, 0.16, 0.5]], 120)
	assert_array(Array(a)).is_equal(Array(b))
	assert_int(a.size()).is_equal(120)
	assert_float(Organic.signed_area(a)).is_greater(0.0)


func test_cell_contains_every_point_and_stays_simple() -> void:
	var points := PackedVector2Array([Vector2(400, 300), Vector2(1500, 320), Vector2(900, 800), Vector2(450, 850)])
	var area := Organic.cell(points, 150.0, 90.0, 40.0, 10.0, 6.0, 0.5)
	assert_int(area.size()).is_greater(40)
	for point in points:
		assert_bool(GeometryUtils.is_circle_inside_polygon(point, 28.0, area)).is_true()
	assert_bool(Builder.self_intersects(area)).is_false()
	assert_array(Array(area)).is_equal(Array(Organic.cell(points, 150.0, 90.0, 40.0, 10.0, 6.0, 0.5)))


func test_cell_clip_keeps_the_arena_inside_the_frame() -> void:
	var points := PackedVector2Array([Vector2(400, 150), Vector2(1500, 1000), Vector2(900, 500)])
	var frame := Rect2(170, 130, 1580, 880)
	var area := Organic.cell(points, 190.0, 90.0, 40.0, 10.0, 6.0, 0.0, frame)
	for point in area:
		assert_bool(frame.grow(12.0).has_point(point)).is_true()


func test_hourglass_has_a_narrow_neck() -> void:
	var area := Organic.hourglass(Vector2(960, 570), 700.0, 135.0, 340.0)
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(960, 570), area)).is_true()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(960, 570 - 200), area)).is_false()
	assert_bool(Geometry2D.is_point_in_polygon(Vector2(500, 570 - 200), area)).is_true()
	assert_bool(Builder.self_intersects(area)).is_false()


func test_edges_where_picks_the_matching_sides() -> void:
	var area := Organic.polar(Vector2(960, 570), 600.0, 380.0, [], 120)
	var right := Organic.edges_where(area, func(mid: Vector2, n: Vector2) -> bool: return n.x > 0.9)
	assert_bool(right.is_empty()).is_false()
	for index: int in right:
		assert_float(area[index].x).is_greater(960.0)


func test_scatter_is_deterministic_and_respects_spacing() -> void:
	var area := Organic.polar(Vector2(960, 570), 600.0, 380.0, [], 120)
	var a := Layouts.scatter(area, [], 9, 190.0, 60.0, 7)
	var b := Layouts.scatter(area, [], 9, 190.0, 60.0, 7)
	assert_array(Array(a)).is_equal(Array(b))
	assert_int(a.size()).is_equal(9)
	for i in a.size():
		assert_bool(GeometryUtils.is_circle_inside_polygon(a[i], 88.0, area)).is_true()
		for j in range(i + 1, a.size()):
			assert_float(a[i].distance_to(a[j])).is_greater_equal(190.0)


func test_planar_edges_never_cross_and_keep_clearance() -> void:
	var area := Organic.polar(Vector2(960, 570), 600.0, 380.0, [], 120)
	var points := Layouts.scatter(area, [], 10, 190.0, 60.0, 11)
	var edges := Layouts.planar_edges(points, 480.0, 58.0, 0.1, 11)
	assert_int(edges.size()).is_greater_equal(points.size() - 1)
	for i in edges.size():
		for j in range(i + 1, edges.size()):
			var e: Array = edges[i]
			var f: Array = edges[j]
			if e[0] in f or e[1] in f:
				continue
			assert_bool(GeometryUtils.segments_cross(points[e[0]], points[e[1]], points[f[0]], points[f[1]])).is_false()
		for k in points.size():
			if k != edges[i][0] and k != edges[i][1]:
				assert_float(GeometryUtils.distance_to_segment(points[k], points[edges[i][0]], points[edges[i][1]])) \
					.is_greater_equal(58.0)


func test_limits_helpers_respect_the_validation_rules() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(300, 0)])
	var tension := Layouts.tension(points, [0, 1])
	assert_float(tension[3]).is_greater(300.0)
	assert_float(300.0 / tension[3]).is_greater_equal(0.8)
	assert_float(tension[2]).is_less(300.0)
	var diseased := Layouts.diseased(points, [0, 1])
	assert_float(diseased[3]).is_less(300.0)
	assert_float(diseased[2]).is_less(diseased[3])
	assert_str(diseased[4]).is_equal("diseased")


func test_receptor_plans_keep_toxic_neurons_outside_every_reach() -> void:
	var area := Organic.polar(Vector2(960, 570), 600.0, 380.0, [], 120)
	var points := Layouts.scatter(area, [], 10, 190.0, 60.0, 21)
	var sites := Layouts.dense_sites(points, [1, 1], 380.0)
	var plan := Layouts.receptor_plans(points, [[sites[0], 1, 1], [sites[1], 1, 1]])
	for toxic: int in plan["toxic"]:
		for receptor: int in plan["receptors"]:
			assert_float(points[toxic].distance_to(points[receptor]) - 28.0).is_greater(plan["receptors"][receptor][0] + 60.0)
