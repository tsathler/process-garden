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

var species := Species.WISP
var body_color: Color = SPECIES_COLORS[Species.WISP]
var selected := false


static func species_for_identity(identity: String) -> int:
	# FNV-1a keeps the visual mapping stable across runs and platforms.
	var value: int = 2166136261
	for byte in identity.to_utf8_buffer():
		value = ((value ^ int(byte)) * 16777619) & 0xffffffff
	# Higher hash bits avoid the low-bit bias for numeric PID identities.
	return (value >> 16) % SPECIES_COUNT


func set_species(value: int) -> void:
	if value < 0 or value >= SPECIES_COUNT:
		return
	if species == value:
		return
	species = value
	body_color = SPECIES_COLORS[species]
	queue_redraw()


func get_species_name() -> String:
	return str(Species.keys()[species])


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func contains_body_point(point: Vector2) -> bool:
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


func _draw() -> void:
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


func _draw_polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)


func _draw_selection_marks() -> void:
	var marker := Color("#c4fff1")
	draw_rect(Rect2(Vector2(-1, -19), Vector2(3, 2)), marker)
	draw_rect(Rect2(Vector2(-17, -1), Vector2(2, 3)), marker)
	draw_rect(Rect2(Vector2(15, -1), Vector2(2, 3)), marker)
	draw_rect(Rect2(Vector2(-1, 16), Vector2(3, 2)), marker)
