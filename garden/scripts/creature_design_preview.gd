extends Node2D
class_name CreatureDesignPreview

const VisualScript = preload("res://scripts/creature_visual.gd")
const BACKGROUND := Color("#090e1c")
const CARD := Color("#111a2c")
const CARD_BORDER := Color("#34516a")
const TEXT_PRIMARY := Color("#f2f7fd")
const TEXT_SECONDARY := Color("#91acc2")
const ACCENT := Color("#76e1d3")
const COLUMN_CENTERS: Array[float] = [150.0, 275.0, 400.0, 525.0]
const SAMPLE_ROWS: Array[float] = [124.0, 222.0, 316.0]
const VIEW_SCALES: Array[float] = [1.0, 2.0, 1.0]
const VIEW_LABELS: Array[String] = ["GAME SCALE", "NEAREST ×2", "MONO SILHOUETTE"]

var _samples: Array[CreatureVisual] = []
var _animated_sample_count := 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_build_samples()
	queue_redraw()


func get_preview_sample_count() -> int:
	return _samples.size()


func get_animated_sample_count() -> int:
	return _animated_sample_count


func _build_samples() -> void:
	var columns: Array[Dictionary] = [
		{"species": VisualScript.Species.WISP, "v2": false, "label": "WISP · CURRENT"},
		{"species": VisualScript.Species.WISP, "v2": true, "label": "WISP · V2"},
		{"species": VisualScript.Species.BEETLE, "v2": false, "label": "BEETLE · CURRENT"},
		{"species": VisualScript.Species.BEETLE, "v2": true, "label": "BEETLE · V2"},
	]
	for column_index in range(columns.size()):
		var column: Dictionary = columns[column_index]
		var is_v2: bool = column["v2"]
		for row_index in range(SAMPLE_ROWS.size()):
			var visual := VisualScript.new() as CreatureVisual
			visual.set_species(int(column["species"]))
			visual.configure_design_preview(is_v2, row_index == 2)
			visual.position = Vector2(COLUMN_CENTERS[column_index], SAMPLE_ROWS[row_index])
			visual.scale = Vector2.ONE * VIEW_SCALES[row_index]
			if is_v2 and row_index == 0:
				visual.set_preview_motion(true, 0.55)
				_animated_sample_count += 1
			add_child(visual)
			_samples.append(visual)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(640.0, 360.0)), BACKGROUND)
	draw_rect(Rect2(Vector2(0.0, 0.0), Vector2(640.0, 2.0)), Color("#1b2a40"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(18.0, 27.0), "CREATURE DESIGN STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 16, TEXT_PRIMARY)
	draw_string(
		font,
		Vector2(18.0, 45.0),
		"DIGITAL WILDLIFE SANCTUARY  ·  CURRENT SHAPES / V2 PROTOTYPES",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		9,
		TEXT_SECONDARY
	)
	for index in range(COLUMN_CENTERS.size()):
		var x := COLUMN_CENTERS[index]
		var column_label: String = [
			"WISP · CURRENT", "WISP · V2", "BEETLE · CURRENT", "BEETLE · V2"
		][index]
		var label_color := ACCENT if index == 1 or index == 3 else TEXT_PRIMARY
		draw_string(
			font,
			Vector2(x - 60.0, 76.0),
			column_label,
			HORIZONTAL_ALIGNMENT_CENTER,
			122.0,
			10,
			label_color
		)
	for row_index in range(SAMPLE_ROWS.size()):
		var y := SAMPLE_ROWS[row_index]
		var card_height := 60.0 if row_index == 0 else (82.0 if row_index == 1 else 48.0)
		var card_top := y - card_height * 0.5
		for x in COLUMN_CENTERS:
			draw_rect(Rect2(Vector2(x - 56.0, card_top), Vector2(112.0, card_height)), CARD)
			draw_rect(
				Rect2(Vector2(x - 56.0, card_top), Vector2(112.0, card_height)),
				CARD_BORDER,
				false,
				1.0
			)
		draw_string(
			font,
			Vector2(8.0, y + 4.0),
			VIEW_LABELS[row_index],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1.0,
			8,
			TEXT_SECONDARY
		)
	draw_string(
		font,
		Vector2(18.0, 354.0),
		"V2 MOTION SAMPLE: WISP FLOAT / CORE PULSE  ·  BEETLE SWAY / ACTIVITY RESPONSE",
		HORIZONTAL_ALIGNMENT_LEFT,
		604.0,
		8,
		TEXT_SECONDARY
	)
