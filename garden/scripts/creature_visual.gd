extends Node2D
class_name CreatureVisual

var body_color := Color("#55d5c2")
var selected := false


func set_body_color(value: Color) -> void:
	if body_color == value:
		return
	body_color = value
	queue_redraw()


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func _draw() -> void:
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-10.0, -1.0), Vector2(-8.0, -8.0), Vector2(-4.0, -12.0),
				Vector2(4.0, -12.0), Vector2(8.0, -8.0), Vector2(10.0, -1.0),
				Vector2(8.0, 6.0), Vector2(5.0, 10.0), Vector2(-5.0, 10.0),
				Vector2(-8.0, 6.0),
			]
		),
		Color("#07151e")
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-8.0, -2.0), Vector2(-6.0, -7.0), Vector2(-3.0, -10.0),
				Vector2(3.0, -10.0), Vector2(6.0, -7.0), Vector2(8.0, -2.0),
				Vector2(6.0, 5.0), Vector2(4.0, 8.0), Vector2(-4.0, 8.0),
				Vector2(-6.0, 5.0),
			]
		),
		body_color
	)
	draw_rect(Rect2(Vector2(-4.0, 1.0), Vector2(8.0, 3.0)), body_color.lightened(0.25))
	draw_rect(Rect2(Vector2(-5.0, -3.0), Vector2(3.0, 3.0)), Color("#07151e"))
	draw_rect(Rect2(Vector2(2.0, -3.0), Vector2(3.0, 3.0)), Color("#07151e"))
	draw_rect(Rect2(Vector2(-4.0, -2.0), Vector2(1.0, 1.0)), Color("#c8fff0"))
	draw_rect(Rect2(Vector2(3.0, -2.0), Vector2(1.0, 1.0)), Color("#c8fff0"))
	draw_rect(Rect2(Vector2(-3.0, 11.0), Vector2(5.0, 2.0)), Color("#183c43"))
	if selected:
		var marker := Color("#a4ffe9")
		draw_rect(Rect2(Vector2(-1.0, -17.0), Vector2(3.0, 2.0)), marker)
		draw_rect(Rect2(Vector2(-14.0, -1.0), Vector2(2.0, 3.0)), marker)
		draw_rect(Rect2(Vector2(12.0, -1.0), Vector2(2.0, 3.0)), marker)
		draw_rect(Rect2(Vector2(-1.0, 14.0), Vector2(3.0, 2.0)), marker)
