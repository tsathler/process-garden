extends Node2D
class_name CaveEnvironment

const HabitatLayout = preload("res://scripts/habitat_layout.gd")
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
@export var show_habitat_debug := false
var _particle_origins: Array[Vector2] = []
var _particle_phases: Array[float] = []
var _particle_speeds: Array[float] = []
var _ground_points := PackedVector2Array()
var _habitat_profiles: Array[Dictionary] = []
var _support_profiles: Array[Dictionary] = []
var _mushroom_profiles: Array[Dictionary] = []
var _ground_bank_profiles: Array[Dictionary] = []
var _synthetic_theme := false


func _ready() -> void:
	_ground_points = HabitatLayout.ground_surface_points()
	_habitat_profiles = HabitatLayout.all_profiles()
	_support_profiles = HabitatLayout.ledge_profiles()
	_mushroom_profiles = HabitatLayout.mushroom_profiles()
	_ground_bank_profiles = HabitatLayout.ground_bank_profiles()
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


func get_habitat_ground_points() -> PackedVector2Array:
	return _ground_points.duplicate()


func get_habitat_ledge_profiles() -> Array[Dictionary]:
	return _support_profiles.duplicate()


func set_habitat_debug_visible(value: bool) -> void:
	if show_habitat_debug == value:
		return
	show_habitat_debug = value
	queue_redraw()


func set_synthetic_theme(value: bool) -> void:
	if _synthetic_theme == value:
		return
	_synthetic_theme = value
	queue_redraw()


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
	if _synthetic_theme:
		_draw_synthetic_environment()
		if show_habitat_debug:
			_draw_habitat_debug()
		return
	_draw_background()
	_draw_distant_rock()
	_draw_midground()
	_draw_ground()
	_draw_foreground_edges()
	_draw_ambient()
	if show_habitat_debug:
		_draw_habitat_debug()


func _draw_synthetic_environment() -> void:
	draw_rect(Rect2(Vector2.ZERO, FIELD_SIZE), Color("#070d18"))
	draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(FIELD_SIZE.x, 55.0)), Color("#091421"))
	draw_circle(Vector2(132.0, 151.0), 126.0, Color("#12313c", 0.11))
	draw_circle(Vector2(509.0, 176.0), 144.0, Color("#142849", 0.12))
	draw_rect(Rect2(Vector2(0.0, 54.0), Vector2(FIELD_SIZE.x, 1.0)), Color("#28424e", 0.72))
	draw_rect(Rect2(Vector2(0.0, 74.0), Vector2(FIELD_SIZE.x, 1.0)), Color("#173541", 0.42))
	for x in [52.0, 161.0, 270.0, 379.0, 488.0, 597.0]:
		draw_line(Vector2(x, 72.0), Vector2(x - 11.0, 214.0), Color("#1d3745", 0.31), 1.0, true)
	_draw_polygon(
		[
			Vector2(0, 236), Vector2(0, 122), Vector2(75, 146), Vector2(142, 119),
			Vector2(221, 149), Vector2(301, 124), Vector2(376, 151), Vector2(463, 117),
			Vector2(540, 145), Vector2(640, 120), Vector2(640, 253),
		],
		Color("#0c1b29")
	)
	for profile in _support_profiles:
		var style := str(profile.get("structure_style", "wall_shelf"))
		var fill := Color("#172c3a") if style == "mineral_shelf" else Color("#132b31")
		var edge := Color("#47788c") if style == "mineral_shelf" else Color("#397d78")
		draw_colored_polygon(HabitatLayout.structure_polygon(profile), fill)
		var surface: PackedVector2Array = profile["points"]
		draw_polyline(surface, edge, 2.0, true)
		for point in surface:
			draw_circle(point, 1.4, Color(edge, 0.72))
	for profile in _ground_bank_profiles:
		draw_colored_polygon(HabitatLayout.ground_bank_polygon(profile), Color("#10232d"))
		draw_polyline(profile["points"], Color("#28545b", 0.65), 1.0, true)
	for profile in _mushroom_profiles:
		var pad := HabitatLayout.mushroom_cap_polygon(profile)
		draw_colored_polygon(pad, Color("#12323b"))
		draw_polyline(pad, Color("#3b8887", 0.78), 1.3, true)
		var pad_center: Vector2 = profile["mushroom_center"]
		draw_line(pad_center + Vector2(-8.0, -13.0), pad_center + Vector2(8.0, -13.0), Color("#64c5b9", 0.38), 1.0, true)
	var ground_fill := _ground_points.duplicate()
	ground_fill.append(Vector2(FIELD_SIZE.x, FIELD_SIZE.y))
	ground_fill.append(Vector2(0.0, FIELD_SIZE.y))
	draw_colored_polygon(ground_fill, Color("#0d1a25"))
	draw_polyline(_ground_points, Color("#3d8b84", 0.72), 2.0, true)
	for index in [1, 4, 8, 12, 16, 18]:
		var anchor := _ground_points[index]
		draw_circle(anchor, 3.0, Color("#142c36"))
		draw_arc(anchor, 5.0, 0.25, PI - 0.25, 20, Color("#4ba69b", 0.45), 1.0, true)
	for y in [316.0, 330.0, 344.0]:
		draw_line(Vector2(18.0, y), Vector2(622.0, y), Color("#182d38", 0.62), 1.0, true)
	draw_line(Vector2(0.0, 359.0), Vector2(FIELD_SIZE.x, 359.0), Color("#315e61", 0.42), 1.0, true)
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
	for index in range(_ground_bank_profiles.size()):
		_draw_ground_bank(_ground_bank_profiles[index], index)
	for profile in _support_profiles:
		_draw_support_structure(profile)
	for profile in _mushroom_profiles:
		_draw_mushroom(profile, _mushroom_color(str(profile["id"])))
	_draw_plant(Vector2(26, 307), 1.0, Color("#24564f"), Color("#4ec8ac"))
	_draw_plant(Vector2(611, 308), 0.9, Color("#28574c"), Color("#6bd0b1"))
	_draw_plant(Vector2(166, 312), 0.58, Color("#214b46"), Color("#4bb5a6"))
	_draw_plant(Vector2(481, 310), 0.65, Color("#244a4b"), Color("#8a88d4"))
	_draw_wall_glimmers()


func _draw_ground() -> void:
	var fill_points := _ground_points.duplicate()
	fill_points.append(Vector2(FIELD_SIZE.x, FIELD_SIZE.y))
	fill_points.append(Vector2(0.0, FIELD_SIZE.y))
	draw_colored_polygon(fill_points, SOIL)
	draw_polyline(_ground_points, SOIL_LIGHT, 2.0, true)
	_draw_moss_ribbons(_ground_points)
	draw_line(Vector2(24, 306), Vector2(142, 306), Color("#22353a"), 1.0)
	draw_line(Vector2(489, 305), Vector2(620, 303), Color("#263339"), 1.0)
	for stone in [Vector2(118, 329), Vector2(251, 342), Vector2(386, 326), Vector2(570, 340)]:
		draw_rect(Rect2(stone, Vector2(12, 4)), Color("#203038"))
		draw_rect(Rect2(stone + Vector2(3, -2), Vector2(7, 2)), Color("#27353d"))
	_draw_ground_reflections()


func _draw_moss_ribbons(ground_points: PackedVector2Array) -> void:
	# Ground contour remains the source of truth for these small moss marks.
	for index: int in [2, 6, 10, 14, 17]:
		var point := ground_points[index]
		var moss_color := Color("#29483f") if index % 2 == 0 else Color("#30424d")
		draw_line(point + Vector2(-8.0, 5.0), point + Vector2(0.0, 2.0), moss_color, 2.0, true)
		draw_line(point + Vector2(1.0, 2.0), point + Vector2(8.0, 5.0), moss_color.lightened(0.08), 2.0, true)


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


func _draw_mushroom(profile: Dictionary, glow: Color) -> void:
	var center: Vector2 = profile["mushroom_center"]
	var size := float(profile["mushroom_size"])
	var cap_center := center + Vector2(0, -16.0 * size)
	_draw_soft_halo(cap_center, 16.0 * size, glow, 0.16)
	draw_rect(HabitatLayout.mushroom_stem_rect(profile), Color("#35565a"))
	draw_rect(
		Rect2(center + Vector2(-2.5, -14.0) * size, Vector2(2.0, 14.0) * size),
		Color("#568987")
	)
	draw_colored_polygon(HabitatLayout.mushroom_cap_polygon(profile), glow.darkened(0.38))
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


func _draw_support_structure(profile: Dictionary) -> void:
	var identifier := str(profile["id"])
	var style := str(profile.get("structure_style", "wall_shelf"))
	var surface: PackedVector2Array = profile["points"]
	var polygon := HabitatLayout.structure_polygon(profile)
	match style:
		"root_branch":
			draw_colored_polygon(polygon, Color("#26363a"))
			draw_polyline(surface, Color("#60786a"), 2.0, true)
			for twig in HabitatLayout.root_branch_twigs(profile):
				draw_line(twig[0], twig[1], Color("#344c45"), 4.0, true)
				draw_line(twig[0], twig[1], Color("#49665b"), 1.0, true)
			var branch_mid := (surface[0] + surface[1]) * 0.5
			draw_line(branch_mid + Vector2(-12.0, 2.0), branch_mid + Vector2(-4.0, 1.0), Color("#30483f"), 2.0, true)
			draw_line(branch_mid + Vector2(8.0, 1.0), branch_mid + Vector2(16.0, 2.0), Color("#30483f"), 2.0, true)
			var glint_x := (surface[0].x + surface[1].x) * 0.5
			_draw_soft_halo(Vector2(glint_x, surface[0].y - 2.0), 8.0, Color("#55c6a8"), 0.08)
		"mineral_shelf":
			draw_colored_polygon(polygon, Color("#283246"))
			draw_polyline(surface, Color("#64758e"), 2.0, true)
			draw_line(surface[0] + Vector2(10.0, 4.0), surface[1] + Vector2(-10.0, 4.0), Color("#3f6275"), 1.0, true)
			draw_line(surface[0] + Vector2(26.0, 12.0), surface[0] + Vector2(38.0, 2.0), Color("#43566e"), 1.0, true)
			draw_line(surface[1] + Vector2(-34.0, 3.0), surface[1] + Vector2(-23.0, 11.0), Color("#394e66"), 1.0, true)
			_draw_soft_halo((surface[0] + surface[1]) * 0.5, 13.0, Color("#8bc9ec"), 0.07)
		_:
			var color := Color("#20283c") if identifier == "low_perch_west" else Color("#20223a")
			draw_colored_polygon(polygon, color)
			draw_line(surface[0], surface[1], color.lightened(0.16), 2.0, true)
			var midpoint := (surface[0] + surface[1]) * 0.5
			draw_line(midpoint + Vector2(-12.0, 6.0), midpoint + Vector2(-4.0, 5.0), color.lightened(0.11), 1.0, true)
			draw_line(midpoint + Vector2(9.0, 6.0), midpoint + Vector2(16.0, 7.0), color.darkened(0.1), 1.0, true)
			# Wall shelves visibly meet the cave edge through short stone supports.
			var wall_x := 0.0 if identifier == "low_perch_west" else FIELD_SIZE.x
			for point in surface:
				draw_line(point + Vector2(0.0, 2.0), Vector2(wall_x, point.y + 9.0), color.darkened(0.12), 3.0, true)


func _draw_ground_bank(profile: Dictionary, index: int) -> void:
	var polygon := HabitatLayout.ground_bank_polygon(profile)
	var surface: PackedVector2Array = profile["points"]
	var body_color := Color("#1b2d31") if index % 2 == 0 else Color("#202a36")
	draw_colored_polygon(polygon, body_color)
	draw_polyline(surface, Color("#344d48"), 2.0, true)
	var crest := surface[2] if surface.size() > 2 else surface[0]
	draw_line(crest + Vector2(-10.0, 3.0), crest + Vector2(-2.0, 1.0), Color("#42675b"), 2.0, true)
	draw_line(crest + Vector2(4.0, 2.0), crest + Vector2(12.0, 4.0), Color("#2f5149"), 2.0, true)
	_draw_soft_halo(crest + Vector2(0.0, 2.0), 8.0, Color("#5cc9a9"), 0.035)


func _mushroom_color(identifier: String) -> Color:
	match identifier:
		"fungal_perch_west":
			return Color("#53d9cb")
		"fungal_perch_east":
			return Color("#65d9ad")
		"fungal_perch_lilac":
			return Color("#9b9af0")
		"fungal_perch_center":
			return Color("#a58ad4")
		"fungal_perch_center_east":
			return Color("#57c9c2")
		_:
			return Color("#57adc2")


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


func _draw_habitat_debug() -> void:
	for profile in _habitat_profiles:
		var color := HabitatLayout.debug_color(int(profile["kind"]))
		if profile["kind"] == HabitatLayout.Kind.AIR:
			draw_rect(profile["area"], Color(color, 0.1), false, 1.0)
		else:
			draw_polyline(profile["points"], Color(color, 0.8), 1.0, true)
		for candidate in HabitatLayout.candidate_positions(profile):
			draw_circle(candidate, 1.5, color)


func _draw_soft_halo(center: Vector2, radius: float, color: Color, strength: float) -> void:
	for ring in range(3):
		var factor := float(ring + 1)
		var alpha := strength / factor
		var halo_color := Color(color.r, color.g, color.b, alpha)
		draw_circle(center, radius * (2.0 - factor * 0.28), halo_color)


func _draw_polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
