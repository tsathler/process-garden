extends Node2D
class_name CaveEnvironment

const FIELD_SIZE := Vector2(640.0, 360.0)
const PARTICLE_COUNT := 18
const PARTICLE_SEED := 20_250
const AMBIENCE_UPDATE_SECONDS := 0.05
const NIGHT := Color("#080d1b")
const DISTANT_ROCK := Color("#101326")
const FAR_ROCK := Color("#11182b")
const MID_ROCK := Color("#192136")
const SOIL := Color("#111b26")
const SOIL_LIGHT := Color("#1a2d31")
const PARTICLE_COLOR := Color("#9bf4e6")

const PAINTER_ORDER := [
	"background", "distant_rock", "midground", "ground", "foreground_edges", "ambient"
]

var _ambient_time := 0.0
var _redraw_accumulator := 0.0
var _particle_origins: Array[Vector2] = []
var _particle_phases: Array[float] = []
var _particle_speeds: Array[float] = []


func _ready() -> void:
	_seed_particles()
	set_process(true)


func _process(delta: float) -> void:
	advance_ambience(delta)


func advance_ambience(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0:
		return
	_ambient_time += delta
	_redraw_accumulator += delta
	if _redraw_accumulator < AMBIENCE_UPDATE_SECONDS:
		return
	_redraw_accumulator = fposmod(_redraw_accumulator, AMBIENCE_UPDATE_SECONDS)
	queue_redraw()


func get_ambient_particle_count() -> int:
	return _particle_origins.size()


func get_ambient_particle_positions() -> Array[Vector2]:
	var positions: Array[Vector2] = []
	for index in range(_particle_origins.size()):
		var phase := _ambient_time * _particle_speeds[index] + _particle_phases[index]
		positions.append(
			_particle_origins[index]
			+ Vector2(cos(phase * 0.31) * 2.0, sin(phase) * 5.0)
		)
	return positions


func get_painter_order() -> PackedStringArray:
	return PackedStringArray(PAINTER_ORDER)


func _seed_particles() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = PARTICLE_SEED
	for index in range(PARTICLE_COUNT):
		_particle_origins.append(
			Vector2(random.randf_range(18.0, 622.0), random.randf_range(112.0, 292.0))
		)
		_particle_phases.append(random.randf_range(0.0, TAU))
		_particle_speeds.append(random.randf_range(0.22, 0.48))


func _draw() -> void:
	_draw_background()
	_draw_distant_rock()
	_draw_midground()
	_draw_ground()
	_draw_foreground_edges()
	_draw_ambient()


func _draw_background() -> void:
	draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), NIGHT)
	draw_circle(Vector2(104.0, 156.0), 104.0, Color("#0d172b"))
	draw_circle(Vector2(534.0, 178.0), 116.0, Color("#11142b"))
	draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(640.0, 80.0)), Color("#070b18"))
	draw_rect(Rect2(Vector2(0.0, 80.0), Vector2(640.0, 2.0)), Color("#1a2033"))


func _draw_distant_rock() -> void:
	_draw_polygon(
		[
			Vector2(0, 224), Vector2(0, 61), Vector2(54, 92), Vector2(112, 72),
			Vector2(177, 104), Vector2(241, 75), Vector2(315, 106), Vector2(384, 66),
			Vector2(447, 104), Vector2(520, 70), Vector2(587, 103), Vector2(640, 76),
			Vector2(640, 239),
		],
		DISTANT_ROCK
	)
	draw_line(Vector2(32, 118), Vector2(60, 136), Color("#182039"), 2.0)
	draw_line(Vector2(497, 113), Vector2(530, 127), Color("#191b36"), 2.0)
	draw_rect(Rect2(Vector2(118, 99), Vector2(16, 2)), Color("#1a2136"))
	draw_rect(Rect2(Vector2(384, 91), Vector2(21, 2)), Color("#191d35"))


func _draw_midground() -> void:
	_draw_polygon(
		[
			Vector2(0, 221), Vector2(67, 190), Vector2(119, 206), Vector2(174, 171),
			Vector2(230, 191), Vector2(285, 163), Vector2(343, 193), Vector2(400, 166),
			Vector2(466, 194), Vector2(521, 166), Vector2(581, 196), Vector2(640, 164),
			Vector2(640, 267), Vector2(0, 264),
		],
		FAR_ROCK
	)
	_draw_ledge(Vector2(20, 236), 112.0, Color("#20283c"))
	_draw_ledge(Vector2(506, 237), 114.0, Color("#20223a"))
	_draw_mushroom(Vector2(82, 301), 1.2, Color("#53d9cb"))
	_draw_mushroom(Vector2(546, 301), 1.65, Color("#65d9ad"))
	_draw_mushroom(Vector2(445, 301), 0.72, Color("#9b9af0"))
	_draw_mushroom(Vector2(204, 288), 0.52, Color("#57adc2"))
	_draw_plant(Vector2(26, 307), 1.0, Color("#24564f"), Color("#4ec8ac"))
	_draw_plant(Vector2(611, 308), 0.9, Color("#28574c"), Color("#6bd0b1"))
	_draw_plant(Vector2(166, 312), 0.58, Color("#214b46"), Color("#4bb5a6"))
	_draw_plant(Vector2(481, 310), 0.65, Color("#244a4b"), Color("#8a88d4"))
	_draw_wall_glimmers()


func _draw_ground() -> void:
	_draw_polygon(
		[
			Vector2(0, 300), Vector2(61, 289), Vector2(126, 300), Vector2(194, 293),
			Vector2(263, 302), Vector2(332, 291), Vector2(403, 300), Vector2(473, 292),
			Vector2(543, 302), Vector2(640, 288), Vector2(640, 360), Vector2(0, 360),
		],
		SOIL
	)
	draw_line(Vector2(0, 302), Vector2(640, 302), SOIL_LIGHT, 2.0)
	draw_line(Vector2(24, 306), Vector2(142, 306), Color("#22353a"), 1.0)
	draw_line(Vector2(489, 305), Vector2(620, 303), Color("#263339"), 1.0)
	for stone in [Vector2(118, 329), Vector2(251, 342), Vector2(386, 326), Vector2(570, 340)]:
		draw_rect(Rect2(stone, Vector2(12, 4)), Color("#203038"))
		draw_rect(Rect2(stone + Vector2(3, -2), Vector2(7, 2)), Color("#27353d"))
	_draw_ground_reflections()


func _draw_foreground_edges() -> void:
	# Edge-only silhouettes add a near plane while leaving the central garden open.
	_draw_polygon(
		[
			Vector2(0, 360), Vector2(0, 324), Vector2(14, 312), Vector2(20, 330),
			Vector2(34, 319), Vector2(39, 360),
		],
		Color("#0b1821")
	)
	_draw_polygon(
		[
			Vector2(640, 360), Vector2(640, 321), Vector2(626, 310), Vector2(619, 332),
			Vector2(605, 321), Vector2(600, 360),
		],
		Color("#0c1823")
	)
	draw_line(Vector2(6, 350), Vector2(17, 337), Color("#286158"), 2.0)
	draw_line(Vector2(634, 350), Vector2(621, 337), Color("#305f5e"), 2.0)


func _draw_mushroom(center: Vector2, size: float, glow: Color) -> void:
	var cap_center := center + Vector2(0, -16.0 * size)
	_draw_soft_halo(cap_center, 16.0 * size, glow, 0.16)
	draw_rect(
		Rect2(center + Vector2(-2.5, -14.0) * size, Vector2(5.0, 14.0) * size),
		Color("#35565a")
	)
	draw_rect(
		Rect2(center + Vector2(-2.5, -14.0) * size, Vector2(2.0, 14.0) * size),
		Color("#568987")
	)
	_draw_polygon(
		[
			center + Vector2(-13, -12) * size, center + Vector2(-10, -19) * size,
			center + Vector2(-5, -23) * size, center + Vector2(5, -23) * size,
			center + Vector2(11, -18) * size, center + Vector2(14, -11) * size,
			center + Vector2(9, -9) * size, center + Vector2(-10, -9) * size,
		],
		glow.darkened(0.38)
	)
	draw_rect(
		Rect2(center + Vector2(-6, -17) * size, Vector2(4, 2) * size),
		glow.lightened(0.2)
	)
	draw_rect(
		Rect2(center + Vector2(4, -14) * size, Vector2(3, 2) * size),
		glow.lightened(0.2)
	)


func _draw_plant(base: Vector2, size: float, color: Color, tip_color: Color) -> void:
	var left_tip := base + Vector2(-12, -27) * size
	var center_tip := base + Vector2(11, -47) * size
	var right_tip := base + Vector2(15, -23) * size
	_draw_soft_halo(center_tip, 7.0 * size, tip_color, 0.1)
	draw_polyline(
		PackedVector2Array(
			[base, base + Vector2(-3, -17) * size, left_tip, base + Vector2(-3, -17) * size,
			base + Vector2(2, -35) * size, center_tip, base + Vector2(3, -16) * size,
			 right_tip, base + Vector2(8, -12) * size]
		),
		color,
		2.0
	)
	draw_line(left_tip, left_tip + Vector2(-5, 5) * size, tip_color.darkened(0.2), 1.0)
	draw_rect(Rect2(center_tip - Vector2(1, 1), Vector2(2, 2)), tip_color)
	draw_line(right_tip, right_tip + Vector2(5, 3) * size, tip_color.darkened(0.2), 1.0)


func _draw_ledge(origin: Vector2, width: float, color: Color) -> void:
	_draw_polygon(
		[
			origin, origin + Vector2(18, -18), origin + Vector2(44, -11),
			origin + Vector2(66, -24), origin + Vector2(width, -12),
			origin + Vector2(width - 12, 0),
		],
		color
	)
	draw_line(origin + Vector2(20, -15), origin + Vector2(width - 20, -11), color.lightened(0.1))


func _draw_wall_glimmers() -> void:
	var glimmers := [
		Vector2(42, 139), Vector2(139, 203), Vector2(188, 126), Vector2(254, 215),
		Vector2(302, 151), Vector2(369, 202), Vector2(427, 132), Vector2(474, 224),
		Vector2(583, 143), Vector2(215, 253), Vector2(331, 246), Vector2(394, 259),
	]
	for index in range(glimmers.size()):
		var color := Color("#5de5d0") if index % 3 != 1 else Color("#938ce0")
		draw_circle(glimmers[index], 3.0, color.darkened(0.58))
		draw_circle(glimmers[index], 1.0, color)


func _draw_ground_reflections() -> void:
	_draw_soft_halo(Vector2(82, 299), 15.0, Color("#43c9bb"), 0.08)
	_draw_soft_halo(Vector2(546, 300), 18.0, Color("#54cda9"), 0.07)
	_draw_soft_halo(Vector2(445, 299), 9.0, Color("#8e87dc"), 0.07)


func _draw_ambient() -> void:
	var positions := get_ambient_particle_positions()
	for index in range(positions.size()):
		var pulse := 0.5 + 0.5 * sin(_ambient_time * _particle_speeds[index] * 2.0 + _particle_phases[index])
		var color := Color(PARTICLE_COLOR, 0.12 + pulse * 0.16)
		draw_circle(positions[index], 2.2, Color(color, color.a * 0.2))
		draw_rect(Rect2(positions[index] - Vector2(0.5, 0.5), Vector2.ONE), color)


func _draw_soft_halo(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for ring in range(3):
		var factor := float(ring + 1)
		var alpha := strength / factor
		var halo_color := Color(color.r, color.g, color.b, alpha)
		draw_circle(center, radius * (2.0 - factor * 0.28), halo_color)


func _draw_polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
