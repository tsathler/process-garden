extends Node2D
class_name SpriteResolutionPreview

const SPECIES_NAMES: Array[String] = ["WISP", "BEETLE", "SPORE", "CRYSTAL", "MOTH", "LARVA"]
const SPECIES_PATHS: Array[String] = [
	"res://assets/creatures/prototypes/cozy_mystic/wisp_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/beetle_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/spore_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/crystal_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/moth_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/larva_idle.png",
]
const CANDIDATE_SIZES: Array[int] = [64, 96, 128, 192]
const SAMPLE_SIZE := 34.0
const VIEWPORT_SIZE := Vector2(640.0, 360.0)
const COLUMN_CENTERS: Array[float] = [85.0, 184.0, 283.0, 382.0, 481.0, 580.0]
const ROW_CENTERS: Array[float] = [87.0, 143.0, 199.0, 255.0, 311.0]

const BACKGROUND := Color("#090e1c")
const SURFACE := Color("#111a2c")
const BORDER := Color("#34516a")
const TEXT := Color("#f2f7fd")
const MUTED := Color("#91acc2")
const ACCENT := Color("#76e1d3")

var _source_textures: Array[Texture2D] = []
var _candidate_textures: Dictionary = {}
var _samples: Array[Sprite2D] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_textures()
	_build_samples()
	queue_redraw()


func get_sample_count() -> int:
	return _samples.size()


func get_source_texture(species_index: int) -> Texture2D:
	if species_index < 0 or species_index >= _source_textures.size():
		return null
	return _source_textures[species_index]


func get_candidate_texture(species_index: int, dimension: int) -> Texture2D:
	return _candidate_textures.get(_candidate_key(species_index, dimension)) as Texture2D


func get_sample(species_index: int, row_index: int) -> Sprite2D:
	var sample_index := row_index * SPECIES_NAMES.size() + species_index
	if sample_index < 0 or sample_index >= _samples.size():
		return null
	return _samples[sample_index]


func _build_textures() -> void:
	for species_index in range(SPECIES_PATHS.size()):
		var source := load(SPECIES_PATHS[species_index]) as Texture2D
		_source_textures.append(source)
		var source_image := source.get_image()
		for dimension in CANDIDATE_SIZES:
			var candidate_image := source_image.duplicate() as Image
			candidate_image.resize(dimension, dimension, Image.INTERPOLATE_NEAREST)
			_candidate_textures[_candidate_key(species_index, dimension)] = ImageTexture.create_from_image(candidate_image)


func _build_samples() -> void:
	for row_index in range(ROW_CENTERS.size()):
		for species_index in range(SPECIES_NAMES.size()):
			var sprite := Sprite2D.new()
			sprite.centered = true
			sprite.offset = Vector2.ZERO
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.texture = _texture_for_row(species_index, row_index)
			sprite.scale = Vector2.ONE * (SAMPLE_SIZE / float(sprite.texture.get_width()))
			sprite.position = Vector2(COLUMN_CENTERS[species_index], ROW_CENTERS[row_index])
			add_child(sprite)
			_samples.append(sprite)


func _texture_for_row(species_index: int, row_index: int) -> Texture2D:
	if row_index == 0:
		return _source_textures[species_index]
	return get_candidate_texture(species_index, CANDIDATE_SIZES[row_index - 1])


func _candidate_key(species_index: int, dimension: int) -> String:
	return "%d:%d" % [species_index, dimension]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEWPORT_SIZE), BACKGROUND)
	draw_rect(Rect2(Vector2.ZERO, Vector2(VIEWPORT_SIZE.x, 2.0)), Color("#1b2a40"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(14.0, 19.0), "COZY MYSTIC · RESOLUTION GATE", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 13, TEXT)
	draw_string(font, Vector2(14.0, 35.0), "SAME 34 px GAME DISPLAY · ORIGINALS ARE NEVER MODIFIED", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 7, MUTED)
	for species_index in range(SPECIES_NAMES.size()):
		draw_string(
			font,
			Vector2(COLUMN_CENTERS[species_index] - 43.0, 55.0),
			SPECIES_NAMES[species_index],
			HORIZONTAL_ALIGNMENT_CENTER,
			86.0,
			7,
			ACCENT
		)
	var row_labels: Array[String] = ["SOURCE", "64 px", "96 px", "128 px", "192 px"]
	for row_index in range(ROW_CENTERS.size()):
		var center_y := ROW_CENTERS[row_index]
		draw_rect(Rect2(Vector2(4.0, center_y - 25.0), Vector2(632.0, 50.0)), SURFACE)
		draw_rect(Rect2(Vector2(4.0, center_y - 25.0), Vector2(632.0, 50.0)), BORDER, false, 1.0)
		draw_string(font, Vector2(7.0, center_y + 3.0), row_labels[row_index], HORIZONTAL_ALIGNMENT_LEFT, 47.0, 7, TEXT if row_index == 0 else MUTED)
	draw_string(font, Vector2(14.0, 355.0), "NEAREST FILTER · CANDIDATES RESAMPLED IN MEMORY ONLY · NOT AUTHORED PIXEL ART", HORIZONTAL_ALIGNMENT_LEFT, 612.0, 7, MUTED)
