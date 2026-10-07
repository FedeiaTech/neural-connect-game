extends GdUnitTestSuite
## SoftLine: wide glow bands as one triangle strip that fades to zero alpha at the edges (no hard
## band edges, no AA seams at segment ends).


func test_band_fades_from_the_center_to_transparent_edges() -> void:
	var band := SoftLine.Band.new()
	band.add(PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]), Color(1, 0, 0, 0.5), 10.0)
	var columns := SoftLine.PROFILE_OFFSETS.size()
	assert_int(band.vertices.size()).is_equal(2 * columns)
	assert_int(band.colors.size()).is_equal(band.vertices.size())
	# 2 triangles per column gap per segment.
	assert_int(band.indices.size()).is_equal((columns - 1) * 6)
	var center := columns / 2
	assert_float(band.colors[center].a).is_equal_approx(0.5, 0.0001)
	assert_float(band.colors[0].a).is_equal(0.0)
	assert_float(band.colors[columns - 1].a).is_equal(0.0)
	# Edges sit half_width away from the line, on both sides.
	assert_float(absf(band.vertices[0].y)).is_equal_approx(10.0, 0.0001)
	assert_float(absf(band.vertices[columns - 1].y)).is_equal_approx(10.0, 0.0001)
	assert_float(band.vertices[0].y * band.vertices[columns - 1].y).is_less(0.0)


func test_closed_polyline_joints_are_mitered() -> void:
	var band := SoftLine.Band.new()
	var square := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100),
		Vector2(0, 0)])
	band.add(square, Color.WHITE, 10.0)
	# The first point of a closed outline joins the last segment: its edge lies on the diagonal
	# at sqrt(2) * half_width (a 90 degree miter), not straight up or down.
	var edge := band.vertices[0]
	assert_float(absf(edge.x)).is_equal_approx(10.0, 0.001)
	assert_float(absf(edge.y)).is_equal_approx(10.0, 0.001)


## Lethal segments sharing endpoints become one polyline, so the glow corners are mitered.
func test_lethal_segments_join_into_chains() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 10),
		Vector2(10, 10), Vector2(0, 10), Vector2(0, 10), Vector2(0, 0)])
	var chains := LethalWallView.chain_segments(square)
	assert_int(chains.size()).is_equal(1)
	assert_int(chains[0].size()).is_equal(5)
	assert_vector(chains[0][4]).is_equal(chains[0][0])
	var apart := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(50, 50), Vector2(60, 50)])
	assert_int(LethalWallView.chain_segments(apart).size()).is_equal(2)
	# A loop listed from its second edge still closes.
	var rotated := PackedVector2Array([Vector2(10, 0), Vector2(10, 10), Vector2(10, 10), Vector2(0, 0),
		Vector2(0, 0), Vector2(10, 0)])
	var loop := LethalWallView.chain_segments(rotated)
	assert_int(loop.size()).is_equal(1)
	assert_vector(loop[0][loop[0].size() - 1]).is_equal(loop[0][0])


func test_short_or_empty_input_adds_nothing() -> void:
	var band := SoftLine.Band.new()
	band.add(PackedVector2Array([Vector2(5, 5)]), Color.WHITE, 10.0)
	band.add(PackedVector2Array([Vector2(5, 5), Vector2(5, 5)]), Color.WHITE, 10.0)
	assert_bool(band.is_empty()).is_true()
