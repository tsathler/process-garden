extends Node2D

const NIGHT := Color("#080d1b")
const WALL := Color("#11152b")
const WALL_LIGHT := Color("#1b1b36")
const ROCK := Color("#101b2b")
const SOIL := Color("#111b26")
const SOIL_LIGHT := Color("#1a2d31")
const SPORE := Color("#5de5d0")


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(640.0, 360.0)), NIGHT)
	draw_circle(Vector2(112.0, 152.0), 92.0, Color("#122039"))
	draw_circle(Vector2(526.0, 176.0), 104.0, Color("#151633"))

	_draw_back_wall()
	_draw_mushroom(Vector2(82.0, 300.0), 1.2, Color("#387f91"))
	_draw_mushroom(Vector2(546.0, 300.0), 1.65, Color("#3c8d79"))
	_draw_mushroom(Vector2(445.0, 300.0), 0.72, Color("#6874b7"))
	_draw_plant(Vector2(26.0, 304.0), 1.0, Color("#1c514d"))
	_draw_plant(Vector2(611.0, 305.0), 0.9, Color("#214e48"))
	_draw_plant(Vector2(166.0, 312.0), 0.58, Color("#19423d"))
	_draw_plant(Vector2(481.0, 310.0), 0.65, Color("#19423d"))
	_draw_ground()
	_draw_spores()


func _draw_back_wall() -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, 222.0),
				Vector2(0.0, 66.0),
				Vector2(46.0, 91.0),
				Vector2(79.0, 64.0),
				Vector2(123.0, 105.0),
				Vector2(177.0, 74.0),
				Vector2(225.0, 114.0),
				Vector2(277.0, 83.0),
				Vector2(333.0, 117.0),
				Vector2(382.0, 72.0),
				Vector2(432.0, 111.0),
				Vector2(490.0, 79.0),
				Vector2(543.0, 115.0),
				Vector2(594.0, 77.0),
				Vector2(640.0, 104.0),
				Vector2(640.0, 230.0),
			]
		),
		WALL
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, 199.0),
				Vector2(94.0, 157.0),
				Vector2(152.0, 184.0),
				Vector2(218.0, 144.0),
				Vector2(293.0, 176.0),
				Vector2(354.0, 143.0),
				Vector2(422.0, 177.0),
				Vector2(495.0, 145.0),
				Vector2(566.0, 179.0),
				Vector2(640.0, 150.0),
				Vector2(640.0, 249.0),
				Vector2(0.0, 253.0),
			]
		),
		WALL_LIGHT
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(19.0, 223.0),
				Vector2(57.0, 193.0),
				Vector2(69.0, 224.0),
				Vector2(102.0, 214.0),
				Vector2(122.0, 247.0),
				Vector2(0.0, 264.0),
			]
		),
		ROCK
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(510.0, 226.0),
				Vector2(547.0, 193.0),
				Vector2(563.0, 225.0),
				Vector2(603.0, 210.0),
				Vector2(640.0, 228.0),
				Vector2(640.0, 267.0),
				Vector2(520.0, 256.0),
			]
		),
		ROCK
	)


func _draw_ground() -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(0.0, 300.0),
				Vector2(61.0, 289.0),
				Vector2(126.0, 300.0),
				Vector2(194.0, 293.0),
				Vector2(263.0, 302.0),
				Vector2(332.0, 291.0),
				Vector2(403.0, 300.0),
				Vector2(473.0, 292.0),
				Vector2(543.0, 302.0),
				Vector2(640.0, 288.0),
				Vector2(640.0, 360.0),
				Vector2(0.0, 360.0),
			]
		),
		SOIL
	)
	draw_line(Vector2(0.0, 302.0), Vector2(640.0, 302.0), SOIL_LIGHT, 2.0)
	for stone in [Vector2(118.0, 329.0), Vector2(251.0, 342.0), Vector2(386.0, 326.0), Vector2(570.0, 340.0)]:
		draw_rect(Rect2(stone, Vector2(12.0, 4.0)), Color("#203038"))
		draw_rect(Rect2(stone + Vector2(3.0, -2.0), Vector2(7.0, 2.0)), Color("#27353d"))


func _draw_mushroom(center: Vector2, size: float, glow: Color) -> void:
	var stem_width := 5.0 * size
	var stem_height := 14.0 * size
	draw_rect(
		Rect2(center + Vector2(-stem_width / 2.0, -stem_height), Vector2(stem_width, stem_height)),
		Color("#35565a")
	)
	draw_rect(
		Rect2(center + Vector2(-stem_width / 2.0, -stem_height), Vector2(2.0 * size, stem_height)),
		Color("#568987")
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				center + Vector2(-13.0, -12.0) * size,
				center + Vector2(-10.0, -19.0) * size,
				center + Vector2(-5.0, -23.0) * size,
				center + Vector2(5.0, -23.0) * size,
				center + Vector2(11.0, -18.0) * size,
				center + Vector2(14.0, -11.0) * size,
				center + Vector2(9.0, -9.0) * size,
				center + Vector2(-10.0, -9.0) * size,
			]
		),
		glow.darkened(0.38)
	)
	draw_rect(
		Rect2(center + Vector2(-6.0, -17.0) * size, Vector2(4.0, 2.0) * size),
		glow.lightened(0.2)
	)
	draw_rect(
		Rect2(center + Vector2(4.0, -14.0) * size, Vector2(3.0, 2.0) * size),
		glow.lightened(0.2)
	)


func _draw_plant(base: Vector2, size: float, color: Color) -> void:
	var points := PackedVector2Array(
		[
			base,
			base + Vector2(-3.0, -17.0) * size,
			base + Vector2(-12.0, -27.0) * size,
			base + Vector2(-16.0, -43.0) * size,
			base + Vector2(-8.0, -31.0) * size,
			base + Vector2(-3.0, -17.0) * size,
			base + Vector2(2.0, -35.0) * size,
			base + Vector2(11.0, -47.0) * size,
			base + Vector2(7.0, -29.0) * size,
			base + Vector2(3.0, -16.0) * size,
			base + Vector2(15.0, -23.0) * size,
			base + Vector2(8.0, -12.0) * size,
		]
	)
	draw_polyline(points, color, 2.0)


func _draw_spores() -> void:
	var lights := [
		Vector2(42.0, 139.0), Vector2(139.0, 203.0), Vector2(188.0, 126.0),
		Vector2(254.0, 215.0), Vector2(302.0, 151.0), Vector2(369.0, 202.0),
		Vector2(427.0, 132.0), Vector2(474.0, 224.0), Vector2(583.0, 143.0),
		Vector2(215.0, 253.0), Vector2(331.0, 246.0), Vector2(394.0, 259.0),
	]
	for index in range(lights.size()):
		var color := SPORE if index % 3 != 1 else Color("#8a82d1")
		draw_circle(lights[index], 4.0, color.darkened(0.48))
		draw_circle(lights[index], 1.5, color)
