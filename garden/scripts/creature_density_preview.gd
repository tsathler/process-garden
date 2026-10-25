extends Node2D
class_name CreatureDensityPreview

const PreviewScript = preload("res://scripts/creature_sprite_preview.gd")
const PREVIEW_SIZE := Vector2(640.0, 360.0)
const SAMPLE_COUNT := 48
const COLUMN_COUNT := 8
const ROW_COUNT := 6
const LEFT := 40.0
const TOP := 77.0
const STEP := Vector2(80.0, 46.0)
const BACKGROUND := Color("#090e1c")
const LIGHT_DOT := Color("#173144")
const TEXT_PRIMARY := Color("#f2f7fd")
const TEXT_SECONDARY := Color("#91acc2")

var _sprites: Array[Sprite2D] = []
var _preview := PreviewScript.new() as CreatureSpritePreview
const SPECIES_NAMES: Array[String] = ["WISP", "BEETLE", "SPORE", "CRYSTAL", "MOTH", "LARVA"]


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for index in range(SAMPLE_COUNT):
		var row := floori(float(index) / COLUMN_COUNT)
		var column := index % COLUMN_COUNT
		var sprite := Sprite2D.new()
		var species_name := SPECIES_NAMES[index % SPECIES_NAMES.size()].to_lower()
		sprite.texture = _preview.get_sprite_texture(species_name)
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var size := 23.0 + float((index * 7) % 4)
		sprite.scale = Vector2.ONE * (size / maxf(sprite.texture.get_width(), sprite.texture.get_height()))
		sprite.position = Vector2(LEFT + column * STEP.x, TOP + row * STEP.y)
		sprite.z_index = 1
		add_child(sprite)
		_sprites.append(sprite)
	_preview.free()
	queue_redraw()


func get_context_sprite_count() -> int:
	return _sprites.size()


func get_context_species_name(index: int) -> String:
	if index < 0 or index >= _sprites.size():
		return ""
	return SPECIES_NAMES[index % SPECIES_NAMES.size()]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PREVIEW_SIZE), BACKGROUND)
	draw_rect(Rect2(Vector2.ZERO, Vector2(PREVIEW_SIZE.x, 2.0)), Color("#1b2a40"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(16.0, 25.0), "DIGITAL WILDLIFE SANCTUARY · DENSITY STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 14, TEXT_PRIMARY)
	draw_string(font, Vector2(16.0, 43.0), "48 DECORATIVE SPRITES · 8 PER SPECIES · NO PROCESS DATA", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, TEXT_SECONDARY)
	for row in range(ROW_COUNT):
		for column in range(COLUMN_COUNT):
			var center := Vector2(LEFT + column * STEP.x, TOP + row * STEP.y)
			draw_circle(center + Vector2(-8.0, 3.0), 1.0, LIGHT_DOT)
			if (row + column) % 3 == 0:
				draw_circle(center + Vector2(10.0, -4.0), 1.0, Color("#21404e"))
	draw_string(font, Vector2(16.0, 354.0), "DENSITY STUDY ONLY · DOES NOT CHANGE GARDEN CONTROLLER LIMIT", HORIZONTAL_ALIGNMENT_LEFT, 608.0, 8, TEXT_SECONDARY)
