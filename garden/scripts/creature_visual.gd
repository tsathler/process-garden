extends Node2D
class_name CreatureVisual

enum Species { WISP, BEETLE, SPORE, CRYSTAL }

const SPECIES_COUNT := 4
const SPECIES_COLORS: Array[Color] = [
	Color("#69dfd2"),
	Color("#8bd18d"),
	Color("#c58bd9"),
	Color("#78b9f2"),
]
const OUTLINE_COLOR := Color("#07131d")
const SHADOW_COLOR := Color("#19323d")
const V2_WISP_COLOR := Color("#45dcc2")
const V2_BEETLE_COLOR := Color("#88d89b")
const V2_HIGHLIGHT_COLOR := Color("#d6fff1")
const SILHOUETTE_COLOR := Color("#dce7f2")

var species := Species.WISP
var body_color: Color = SPECIES_COLORS[Species.WISP]
var selected := false
var _preview_v2 := false
var _preview_silhouette := false
var _preview_motion := false
var _preview_activity := 0.0
var _preview_phase := 0.0
var _preview_redraw_accumulator := 0.0


static func species_for_identity(identity: String) -> int:
	# FNV-1a keeps the visual mapping stable across runs and platforms.
	var value: int = 2166136261
	for byte in identity.to_utf8_buffer():
		value = ((value ^ int(byte)) * 16777619) & 0xffffffff
	# Higher hash bits avoid the low-bit bias for numeric PID identities.
	return (value >> 16) % SPECIES_COUNT


static func body_bottom_extent(species_index: int) -> float:
	match species_index:
		Species.WISP:
			return 16.0
		Species.BEETLE:
			return 12.0
		Species.SPORE:
			return 13.0
		Species.CRYSTAL:
			return 15.0
	return 14.0


func set_species(value: int) -> void:
	if value < 0 or value >= SPECIES_COUNT:
		return
	if species == value:
		return
	species = value
	_update_body_color()
	queue_redraw()


func configure_design_preview(v2: bool, silhouette: bool = false) -> void:
	_preview_v2 = v2 and (species == Species.WISP or species == Species.BEETLE)
	_preview_silhouette = silhouette
	_update_body_color()
	queue_redraw()


func set_preview_motion(enabled: bool, activity: float = 0.45) -> void:
	_preview_motion = enabled and _preview_v2 and not _preview_silhouette
	_preview_activity = clampf(activity, 0.0, 1.0)
	_preview_redraw_accumulator = 0.0
	set_process(_preview_motion)
	queue_redraw()


func is_design_v2() -> bool:
	return _preview_v2


func is_silhouette_preview() -> bool:
	return _preview_silhouette


func is_preview_animating() -> bool:
	return _preview_motion


func _process(delta: float) -> void:
	if not _preview_motion or not is_finite(delta) or delta <= 0.0:
		return
	_preview_phase = fposmod(_preview_phase + delta, TAU * 8.0)
	_preview_redraw_accumulator += delta
	if _preview_redraw_accumulator < 0.05:
		return
	_preview_redraw_accumulator = fposmod(_preview_redraw_accumulator, 0.05)
	queue_redraw()


func _update_body_color() -> void:
	if _preview_silhouette:
		body_color = SILHOUETTE_COLOR
	elif _preview_v2 and species == Species.WISP:
		body_color = V2_WISP_COLOR
	elif _preview_v2 and species == Species.BEETLE:
		body_color = V2_BEETLE_COLOR
	else:
		body_color = SPECIES_COLORS[species]


func get_species_name() -> String:
	return str(Species.keys()[species])


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func contains_body_point(point: Vector2) -> bool:
	if _preview_silhouette:
		return _contains_preview_silhouette_point(point)
	if _preview_v2:
		return _contains_v2_body_point(point)
	return _contains_current_body_point(point)


func _contains_preview_silhouette_point(point: Vector2) -> bool:
	return _contains_v2_body_point(point) if _preview_v2 else _contains_current_body_point(point)


func _contains_current_body_point(point: Vector2) -> bool:
	match species:
		Species.WISP:
			return Vector2(point.x / 9.0, (point.y + 0.5) / 13.0).length_squared() <= 1.0
		Species.BEETLE:
			return Vector2(point.x / 15.0, (point.y + 1.0) / 10.0).length_squared() <= 1.0
		Species.SPORE:
			var in_cap := Vector2(point.x / 14.0, (point.y + 6.0) / 9.0).length_squared() <= 1.0
			var in_stem := absf(point.x) <= 5.0 and point.y >= 0.0 and point.y <= 13.0
			return in_cap or in_stem
		Species.CRYSTAL:
			return absf(point.x) / 12.0 + absf(point.y) / 15.0 <= 1.0
	return false


func _contains_v2_body_point(point: Vector2) -> bool:
	match species:
		Species.WISP:
			var body := Vector2(point.x / 11.0, (point.y + 0.5) / 18.5).length_squared() <= 1.0
			var fins := absf(point.x) >= 10.0 and absf(point.x) <= 15.5 and point.y >= 3.0 and point.y <= 13.0
			return body or fins
		Species.BEETLE:
			return Vector2(point.x / 19.0, (point.y + 0.5) / 12.5).length_squared() <= 1.0
	return false


func _draw() -> void:
	if _preview_motion:
		var bob := sin(_preview_phase * 1.15) * (0.7 + _preview_activity * 0.45)
		var sway := 0.0
		if species == Species.BEETLE:
			sway = sin(_preview_phase * 2.1) * (0.012 + _preview_activity * 0.035)
		draw_set_transform(Vector2(0.0, bob), sway, Vector2.ONE)
	if _preview_silhouette:
		_draw_silhouette()
	elif _preview_v2:
		if species == Species.WISP:
			_draw_wisp_v2()
		elif species == Species.BEETLE:
			_draw_beetle_v2()
	else:
		match species:
			Species.WISP:
				_draw_wisp()
			Species.BEETLE:
				_draw_beetle()
			Species.SPORE:
				_draw_spore()
			Species.CRYSTAL:
				_draw_crystal()
	if selected:
		_draw_selection_marks()
	if _preview_motion:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_silhouette() -> void:
	match species:
		Species.WISP:
			if _preview_v2:
				_draw_polygon(
					[Vector2(-7, 3), Vector2(-15, 7), Vector2(-13, 13), Vector2(-5, 9)],
					SILHOUETTE_COLOR
				)
				_draw_polygon(
					[Vector2(7, 3), Vector2(15, 7), Vector2(13, 13), Vector2(5, 9)],
					SILHOUETTE_COLOR
				)
				_draw_polygon(
					[
						Vector2(0, -19), Vector2(-6, -16), Vector2(-10, -10), Vector2(-12, -3),
						Vector2(-11, 6), Vector2(-8, 13), Vector2(-4, 17), Vector2(0, 20),
						Vector2(5, 17), Vector2(9, 12), Vector2(12, 4), Vector2(12, -4),
						Vector2(9, -12), Vector2(5, -17),
					],
					SILHOUETTE_COLOR
				)
			else:
				_draw_polygon(
					[
						Vector2(0, -13), Vector2(-5, -10), Vector2(-8, -5), Vector2(-9, 1),
						Vector2(-7, 7), Vector2(-4, 10), Vector2(0, 14), Vector2(4, 10),
						Vector2(7, 6), Vector2(8, 0), Vector2(6, -6), Vector2(3, -11),
					],
					SILHOUETTE_COLOR
				)
		Species.BEETLE:
			if _preview_v2:
				draw_line(Vector2(-12, 5), Vector2(-16, 12), SILHOUETTE_COLOR, 3.0)
				draw_line(Vector2(-3, 8), Vector2(-5, 14), SILHOUETTE_COLOR, 3.0)
				draw_line(Vector2(7, 7), Vector2(10, 13), SILHOUETTE_COLOR, 3.0)
				draw_line(Vector2(13, 1), Vector2(17, 6), SILHOUETTE_COLOR, 3.0)
				draw_line(Vector2(15, -5), Vector2(18, -11), SILHOUETTE_COLOR, 2.0)
				draw_line(Vector2(17, -6), Vector2(22, -10), SILHOUETTE_COLOR, 2.0)
				_draw_polygon(
					[
						Vector2(-18, 2), Vector2(-17, -5), Vector2(-12, -10), Vector2(-4, -12),
						Vector2(6, -11), Vector2(11, -7), Vector2(16, -6), Vector2(20, -2),
						Vector2(19, 5), Vector2(15, 9), Vector2(8, 11), Vector2(-11, 10),
						Vector2(-17, 7),
					],
					SILHOUETTE_COLOR
				)
			else:
				_draw_polygon(
					[
						Vector2(-12, -2), Vector2(-10, -8), Vector2(-5, -11), Vector2(3, -12),
						Vector2(9, -9), Vector2(13, -4), Vector2(15, 2), Vector2(12, 7),
						Vector2(8, 10), Vector2(-8, 10), Vector2(-12, 6), Vector2(-14, 1),
					],
					SILHOUETTE_COLOR
				)


func _draw_wisp() -> void:
	_draw_polygon(
		[
			Vector2(0, -13), Vector2(-5, -10), Vector2(-8, -5), Vector2(-9, 1),
			Vector2(-7, 7), Vector2(-4, 10), Vector2(0, 14), Vector2(4, 10),
			Vector2(7, 6), Vector2(8, 0), Vector2(6, -6), Vector2(3, -11),
		],
		OUTLINE_COLOR
	)
	_draw_polygon(
		[
			Vector2(0, -11), Vector2(-4, -8), Vector2(-6, -4), Vector2(-7, 1),
			Vector2(-5, 6), Vector2(-2, 9), Vector2(0, 11), Vector2(3, 8),
			Vector2(5, 4), Vector2(6, 0), Vector2(4, -5), Vector2(2, -9),
		],
		body_color
	)
	draw_rect(Rect2(Vector2(-4, -3), Vector2(2, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(2, -3), Vector2(2, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(-3, -2), Vector2(1, 1)), Color("#e5fff4"))
	draw_rect(Rect2(Vector2(3, -2), Vector2(1, 1)), Color("#e5fff4"))
	draw_rect(Rect2(Vector2(-2, 12), Vector2(2, 2)), SHADOW_COLOR)
	draw_rect(Rect2(Vector2(1, 15), Vector2(1, 1)), body_color.lightened(0.28))


func _draw_beetle() -> void:
	draw_rect(Rect2(Vector2(-9, 8), Vector2(3, 4)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(6, 8), Vector2(3, 4)), OUTLINE_COLOR)
	draw_line(Vector2(-5, -8), Vector2(-9, -13), OUTLINE_COLOR, 2.0)
	draw_line(Vector2(5, -8), Vector2(9, -13), OUTLINE_COLOR, 2.0)
	draw_rect(Rect2(Vector2(-12, -2), Vector2(24, 13)), OUTLINE_COLOR)
	_draw_polygon(
		[
			Vector2(-12, -2), Vector2(-10, -8), Vector2(-5, -11), Vector2(3, -12),
			Vector2(9, -9), Vector2(13, -4), Vector2(15, 2), Vector2(12, 7),
			Vector2(8, 10), Vector2(-8, 10), Vector2(-12, 6), Vector2(-14, 1),
		],
		OUTLINE_COLOR
	)
	_draw_polygon(
		[
			Vector2(-10, -2), Vector2(-8, -7), Vector2(-4, -9), Vector2(3, -10),
			Vector2(8, -7), Vector2(11, -3), Vector2(13, 2), Vector2(10, 6),
			Vector2(7, 8), Vector2(-7, 8), Vector2(-10, 5), Vector2(-12, 1),
		],
		body_color
	)
	draw_line(Vector2(0, -9), Vector2(0, 7), SHADOW_COLOR, 2.0)
	draw_rect(Rect2(Vector2(-12, -5), Vector2(4, 5)), SHADOW_COLOR)
	draw_rect(Rect2(Vector2(9, -5), Vector2(3, 5)), body_color.lightened(0.2))
	draw_rect(Rect2(Vector2(-8, -1), Vector2(3, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(8, -1), Vector2(3, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(-7, 0), Vector2(1, 1)), Color("#edfff0"))
	draw_rect(Rect2(Vector2(9, 0), Vector2(1, 1)), Color("#edfff0"))
	draw_rect(Rect2(Vector2(-10, 11), Vector2(4, 2)), SHADOW_COLOR)
	draw_rect(Rect2(Vector2(6, 11), Vector2(4, 2)), SHADOW_COLOR)


func _draw_spore() -> void:
	draw_rect(Rect2(Vector2(-4, 0), Vector2(8, 13)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(-2, 4), Vector2(4, 8)), body_color.darkened(0.15))
	_draw_polygon(
		[
			Vector2(-14, -4), Vector2(-12, -8), Vector2(-8, -9), Vector2(-6, -13),
			Vector2(-2, -14), Vector2(0, -11), Vector2(3, -14), Vector2(7, -12),
			Vector2(8, -9), Vector2(12, -8), Vector2(14, -4), Vector2(13, 0),
			Vector2(9, 3), Vector2(-9, 3), Vector2(-13, 0),
		],
		OUTLINE_COLOR
	)
	_draw_polygon(
		[
			Vector2(-12, -4), Vector2(-10, -7), Vector2(-7, -7), Vector2(-5, -11),
			Vector2(-2, -12), Vector2(0, -9), Vector2(3, -12), Vector2(6, -10),
			Vector2(7, -7), Vector2(10, -7), Vector2(12, -4), Vector2(11, -1),
			Vector2(8, 1), Vector2(-8, 1), Vector2(-11, -1),
		],
		body_color
	)
	draw_rect(Rect2(Vector2(-7, -5), Vector2(3, 2)), body_color.lightened(0.34))
	draw_rect(Rect2(Vector2(3, -8), Vector2(3, 2)), body_color.lightened(0.34))
	draw_rect(Rect2(Vector2(-5, 5), Vector2(2, 2)), SHADOW_COLOR)
	draw_rect(Rect2(Vector2(3, 5), Vector2(2, 2)), SHADOW_COLOR)
	draw_rect(Rect2(Vector2(-4, 5), Vector2(1, 1)), Color("#f7eaff"))
	draw_rect(Rect2(Vector2(4, 5), Vector2(1, 1)), Color("#f7eaff"))


func _draw_crystal() -> void:
	_draw_polygon(
		[
			Vector2(0, -16), Vector2(7, -10), Vector2(12, -1), Vector2(9, 9),
			Vector2(1, 15), Vector2(-8, 10), Vector2(-12, 1), Vector2(-7, -9),
		],
		OUTLINE_COLOR
	)
	_draw_polygon(
		[
			Vector2(0, -13), Vector2(5, -9), Vector2(9, -1), Vector2(7, 7),
			Vector2(1, 12), Vector2(-6, 8), Vector2(-9, 1), Vector2(-5, -8),
		],
		body_color
	)
	_draw_polygon(
		[Vector2(0, -13), Vector2(5, -9), Vector2(1, 0), Vector2(-1, 1)],
		body_color.lightened(0.3)
	)
	_draw_polygon(
		[Vector2(-5, -8), Vector2(-1, 1), Vector2(-6, 8), Vector2(-9, 1)],
		body_color.darkened(0.22)
	)
	_draw_polygon(
		[Vector2(1, 1), Vector2(7, 7), Vector2(1, 12), Vector2(-1, 1)],
		body_color.darkened(0.12)
	)
	draw_rect(Rect2(Vector2(-2, -5), Vector2(2, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(3, -5), Vector2(2, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(-1, -4), Vector2(1, 1)), Color("#effaff"))
	draw_rect(Rect2(Vector2(4, -4), Vector2(1, 1)), Color("#effaff"))


func _draw_wisp_v2() -> void:
	var outer: Array[Vector2] = [
		Vector2(0, -19), Vector2(-6, -16), Vector2(-10, -10), Vector2(-12, -3),
		Vector2(-11, 6), Vector2(-8, 13), Vector2(-4, 17), Vector2(0, 20),
		Vector2(5, 17), Vector2(9, 12), Vector2(12, 4), Vector2(12, -4),
		Vector2(9, -12), Vector2(5, -17),
	]
	_draw_polygon(
		[Vector2(-7, 3), Vector2(-15, 7), Vector2(-13, 13), Vector2(-5, 9)], OUTLINE_COLOR
	)
	_draw_polygon(
		[Vector2(7, 3), Vector2(15, 7), Vector2(13, 13), Vector2(5, 9)], OUTLINE_COLOR
	)
	_draw_polygon(
		[Vector2(-7, 5), Vector2(-13, 8), Vector2(-12, 11), Vector2(-6, 8)], body_color.darkened(0.2)
	)
	_draw_polygon(
		[Vector2(7, 5), Vector2(13, 8), Vector2(12, 11), Vector2(6, 8)], body_color.darkened(0.2)
	)
	_draw_polygon(outer, OUTLINE_COLOR)
	_draw_polygon(
		[
			Vector2(0, -16), Vector2(-4, -14), Vector2(-8, -9), Vector2(-10, -3),
			Vector2(-9, 5), Vector2(-6, 11), Vector2(-3, 15), Vector2(0, 17),
			Vector2(4, 15), Vector2(7, 10), Vector2(10, 3), Vector2(10, -4),
			Vector2(7, -10), Vector2(4, -14),
		],
		body_color
	)
	_draw_polygon(
		[Vector2(-8, -5), Vector2(-5, -12), Vector2(-2, -14), Vector2(-3, -3)],
		body_color.lightened(0.18)
	)
	_draw_polygon(
		[Vector2(2, -13), Vector2(7, -9), Vector2(9, -3), Vector2(4, -1)],
		body_color.lightened(0.28)
	)
	var pulse := 1.0
	if _preview_motion:
		pulse = 0.78 if sin(_preview_phase * (1.0 + _preview_activity)) < -0.2 else 1.0
	var core_color := body_color.lightened(0.42).lerp(V2_HIGHLIGHT_COLOR, 0.35)
	core_color = core_color.darkened(1.0 - pulse)
	draw_rect(Rect2(Vector2(-4, -3), Vector2(8, 9)), body_color.darkened(0.3))
	draw_rect(Rect2(Vector2(-3, -4), Vector2(6, 9)), core_color)
	draw_rect(Rect2(Vector2(-2, -2), Vector2(4, 5)), V2_HIGHLIGHT_COLOR)
	draw_rect(Rect2(Vector2(-5, 5), Vector2(3, 2)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(2, 5), Vector2(3, 2)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(-4, 5), Vector2(1, 1)), V2_HIGHLIGHT_COLOR)
	draw_rect(Rect2(Vector2(3, 5), Vector2(1, 1)), V2_HIGHLIGHT_COLOR)
	draw_rect(Rect2(Vector2(-2, 17), Vector2(4, 2)), body_color.lightened(0.18))


func _draw_beetle_v2() -> void:
	# Feet and antennae sit behind the armored body and stay deliberately broad.
	draw_line(Vector2(-12, 5), Vector2(-16, 12), OUTLINE_COLOR, 3.0)
	draw_line(Vector2(-3, 8), Vector2(-5, 14), OUTLINE_COLOR, 3.0)
	draw_line(Vector2(7, 7), Vector2(10, 13), OUTLINE_COLOR, 3.0)
	draw_line(Vector2(13, 1), Vector2(17, 6), OUTLINE_COLOR, 3.0)
	draw_line(Vector2(15, -5), Vector2(18, -11), OUTLINE_COLOR, 2.0)
	draw_line(Vector2(18, -11), Vector2(20, -13), OUTLINE_COLOR, 1.0)
	draw_line(Vector2(17, -6), Vector2(22, -10), OUTLINE_COLOR, 2.0)
	draw_line(Vector2(22, -10), Vector2(24, -11), OUTLINE_COLOR, 1.0)
	_draw_polygon(
		[
			Vector2(-18, 2), Vector2(-17, -5), Vector2(-12, -10), Vector2(-4, -12),
			Vector2(6, -11), Vector2(11, -7), Vector2(16, -6), Vector2(20, -2),
			Vector2(19, 5), Vector2(15, 9), Vector2(8, 11), Vector2(-11, 10),
			Vector2(-17, 7),
		],
		OUTLINE_COLOR
	)
	_draw_polygon(
		[
			Vector2(-15, 1), Vector2(-14, -4), Vector2(-10, -8), Vector2(-3, -9),
			Vector2(5, -8), Vector2(9, -5), Vector2(12, -1), Vector2(11, 4),
			Vector2(7, 8), Vector2(-10, 7), Vector2(-14, 5),
		],
		body_color
	)
	_draw_polygon(
		[Vector2(8, -6), Vector2(15, -6), Vector2(19, -2), Vector2(18, 4), Vector2(14, 7), Vector2(8, 5)],
		body_color.darkened(0.18)
	)
	_draw_polygon(
		[Vector2(11, -4), Vector2(15, -5), Vector2(18, -2), Vector2(17, 1), Vector2(12, 1)],
		body_color.lightened(0.16)
	)
	# Carapace plates and a single luminous mark keep the body readable at game scale.
	draw_line(Vector2(-3, -8), Vector2(-2, 7), body_color.darkened(0.3), 2.0)
	draw_line(Vector2(-10, -6), Vector2(-9, 6), body_color.darkened(0.18), 1.0)
	draw_line(Vector2(4, -7), Vector2(5, 6), body_color.lightened(0.12), 1.0)
	draw_rect(Rect2(Vector2(-11, -6), Vector2(4, 2)), body_color.lightened(0.28))
	draw_rect(Rect2(Vector2(1, -8), Vector2(4, 2)), body_color.lightened(0.2))
	draw_rect(Rect2(Vector2(-3, -2), Vector2(5, 5)), body_color.darkened(0.34))
	draw_rect(Rect2(Vector2(-2, -1), Vector2(3, 3)), V2_HIGHLIGHT_COLOR)
	draw_rect(Rect2(Vector2(14, -2), Vector2(2, 3)), OUTLINE_COLOR)
	draw_rect(Rect2(Vector2(15, -1), Vector2(1, 1)), V2_HIGHLIGHT_COLOR)
	draw_rect(Rect2(Vector2(-13, 10), Vector2(4, 2)), body_color.darkened(0.22))
	draw_rect(Rect2(Vector2(-4, 12), Vector2(4, 2)), body_color.darkened(0.22))
	draw_rect(Rect2(Vector2(8, 10), Vector2(4, 2)), body_color.darkened(0.22))


func _draw_polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)


func _draw_selection_marks() -> void:
	var marker := Color("#c4fff1")
	draw_rect(Rect2(Vector2(-1, -19), Vector2(3, 2)), marker)
	draw_rect(Rect2(Vector2(-17, -1), Vector2(2, 3)), marker)
	draw_rect(Rect2(Vector2(15, -1), Vector2(2, 3)), marker)
	draw_rect(Rect2(Vector2(-1, 16), Vector2(3, 2)), marker)
