extends Node2D
class_name CreatureSpritePreview

const CreatureVisualScript = preload("res://scripts/creature_visual.gd")
const WISP_TEXTURE: Texture2D = preload(
	"res://assets/creatures/prototypes/cozy_mystic/wisp_idle.png"
)
const BEETLE_TEXTURE: Texture2D = preload(
	"res://assets/creatures/prototypes/cozy_mystic/beetle_idle.png"
)
const MOTH_TEXTURE: Texture2D = preload(
	"res://assets/creatures/prototypes/cozy_mystic/moth_idle.png"
)
const SPORE_TEXTURE: Texture2D = preload(
	"res://assets/creatures/prototypes/cozy_mystic/spore_idle.png"
)
const CRYSTAL_TEXTURE: Texture2D = preload(
	"res://assets/creatures/prototypes/cozy_mystic/crystal_idle.png"
)
const LARVA_TEXTURE: Texture2D = preload(
	"res://assets/creatures/prototypes/cozy_mystic/larva_idle.png"
)

const PREVIEW_SIZE := Vector2(640.0, 360.0)
const TARGET_SPRITE_SIZE := 34.0
const COLUMN_CENTERS: Array[float] = [44.0, 122.0, 200.0, 278.0, 356.0, 434.0, 512.0, 590.0]
const ROW_CENTERS: Array[float] = [151.0, 239.0, 322.0]
const GAME_SCALE := 1.0
const NEAREST_SCALE := 2.0
const SILHOUETTE_SCALE := 1.0

const BACKGROUND := Color("#090e1c")
const CARD := Color("#111a2c")
const CARD_BORDER := Color("#34516a")
const TEXT_PRIMARY := Color("#f2f7fd")
const TEXT_SECONDARY := Color("#91acc2")
const ACCENT := Color("#76e1d3")

var _samples: Array[Node2D] = []
var _silhouette_material: ShaderMaterial


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_silhouette_material = _make_silhouette_material()
	_build_comparison()
	queue_redraw()


func get_sample_count() -> int:
	return _samples.size()


func get_sprite_sample_count() -> int:
	var count := 0
	for sample in _samples:
		if sample is Sprite2D:
			count += 1
	return count


func get_sprite_texture(species_name: String) -> Texture2D:
	match species_name.to_lower():
		"wisp":
			return WISP_TEXTURE
		"beetle":
			return BEETLE_TEXTURE
		"moth":
			return MOTH_TEXTURE
		"spore":
			return SPORE_TEXTURE
		"crystal":
			return CRYSTAL_TEXTURE
		"larva":
			return LARVA_TEXTURE
	return null


func _build_comparison() -> void:
	var columns: Array[Dictionary] = [
		{"species": CreatureVisualScript.Species.WISP, "texture": "wisp", "current": true, "label": "WISP V1"},
		{"species": CreatureVisualScript.Species.WISP, "texture": "wisp", "current": false, "label": "WISP"},
		{"species": CreatureVisualScript.Species.BEETLE, "texture": "beetle", "current": true, "label": "BEETLE V1"},
		{"species": CreatureVisualScript.Species.BEETLE, "texture": "beetle", "current": false, "label": "BEETLE"},
		{"species": -1, "texture": "spore", "current": false, "label": "SPORE"},
		{"species": -1, "texture": "crystal", "current": false, "label": "CRYSTAL"},
		{"species": -1, "texture": "moth", "current": false, "label": "MOTH"},
		{"species": -1, "texture": "larva", "current": false, "label": "LARVA"},
	]
	for column_index in range(columns.size()):
		var column: Dictionary = columns[column_index]
		for row_index in range(ROW_CENTERS.size()):
			var sample := _make_sample(column, row_index)
			sample.position = Vector2(COLUMN_CENTERS[column_index], ROW_CENTERS[row_index])
			add_child(sample)
			_samples.append(sample)


func _make_sample(column: Dictionary, row_index: int) -> Node2D:
	var species := int(column["species"])
	var is_current: bool = column["current"]
	var sample: Node2D
	if not is_current:
		var sprite := Sprite2D.new()
		sprite.texture = get_sprite_texture(str(column["texture"]))
		sprite.centered = true
		sprite.offset = Vector2.ZERO
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var base_scale := _scale_for_texture(sprite.texture, TARGET_SPRITE_SIZE)
		var row_scale := NEAREST_SCALE if row_index == 1 else SILHOUETTE_SCALE
		sprite.scale = Vector2.ONE * base_scale * row_scale
		if row_index == 2:
			sprite.material = _silhouette_material
		sample = sprite
	else:
		var visual := CreatureVisualScript.new() as CreatureVisual
		visual.set_species(species)
		visual.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		visual.scale = Vector2.ONE * (NEAREST_SCALE if row_index == 1 else GAME_SCALE)
		if row_index == 2:
			visual.configure_design_preview(false, true)
		sample = visual
	return sample


func _scale_for_texture(texture: Texture2D, rendered_size: float) -> float:
	if texture == null:
		return 1.0
	return rendered_size / maxf(float(texture.get_width()), float(texture.get_height()))


func _make_silhouette_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
	shader_type canvas_item;
	void fragment() {
		float alpha = texture(TEXTURE, UV).a * COLOR.a;
		COLOR = vec4(vec3(0.86, 0.91, 0.96), alpha);
	}
	"""
	var material := ShaderMaterial.new()
	material.shader = shader
	return material


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, PREVIEW_SIZE), BACKGROUND)
	draw_rect(Rect2(Vector2.ZERO, Vector2(PREVIEW_SIZE.x, 2.0)), Color("#1b2a40"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(16.0, 25.0), "COZY MYSTIC · CREATURE SPRITE STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, TEXT_PRIMARY)
	draw_string(font, Vector2(16.0, 43.0), "ORIGINAL PNG SPRITES · STATIC IDLE ART · NO COLLECTOR REQUIRED", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 8, TEXT_SECONDARY)
	var labels: Array[String] = ["WISP V1", "WISP", "BEETLE V1", "BEETLE", "SPORE", "CRYSTAL", "MOTH", "LARVA"]
	for index in range(COLUMN_CENTERS.size()):
		var label_color := TEXT_PRIMARY if index == 0 or index == 2 else ACCENT
		draw_string(font, Vector2(COLUMN_CENTERS[index] - 36.0, 76.0), labels[index], HORIZONTAL_ALIGNMENT_CENTER, 72.0, 7, label_color)
	var card_sizes: Array[Vector2] = [Vector2(72.0, 62.0), Vector2(72.0, 82.0), Vector2(72.0, 44.0)]
	var row_labels: Array[String] = ["GAME SCALE", "NEAREST ×2", "MONO SILHOUETTE"]
	var row_label_y: Array[float] = [112.0, 192.0, 294.0]
	for row_index in range(ROW_CENTERS.size()):
		var card_size := card_sizes[row_index]
		for x in COLUMN_CENTERS:
			var rect := Rect2(Vector2(x - card_size.x * 0.5, ROW_CENTERS[row_index] - card_size.y * 0.5), card_size)
			draw_rect(rect, CARD)
			draw_rect(rect, CARD_BORDER, false, 1.0)
		draw_string(font, Vector2(16.0, row_label_y[row_index]), row_labels[row_index], HORIZONTAL_ALIGNMENT_LEFT, 608.0, 7, TEXT_SECONDARY)
	draw_string(font, Vector2(16.0, 354.0), "SIX STATIC IDLE SPRITES · NO FRAME-BY-FRAME ANIMATION", HORIZONTAL_ALIGNMENT_LEFT, 608.0, 8, TEXT_SECONDARY)
