extends Node2D
class_name AnimationPocPreview

const Assets = preload("res://scripts/sprite_animation_poc_assets.gd")
const BACKGROUND := Color("#090e1c")
const PANEL := Color("#111a2c")
const BORDER := Color("#34516a")
const PRIMARY := Color("#f2f7fd")
const MUTED := Color("#91acc2")
const ACCENT := Color("#76e1d3")
const COLUMN_X: Array[float] = [76.0, 174.0, 272.0, 370.0, 468.0, 566.0]
const ROW_Y: Array[float] = [103.0, 174.0, 247.0, 320.0]
const ROW_LABELS: Array[String] = ["STATIC", "ANIM", "2×", "SIL"]
const DISPLAY_NAMES: Array[String] = ["WISP", "BEETLE", "SPORE", "CRYSTAL", "MOTH", "LARVA"]

var _samples: Array[CanvasItem] = []
var _animated: Array[AnimatedSprite2D] = []
var _frames_by_species: Array[SpriteFrames] = []
var _silhouette_material: ShaderMaterial
var _elapsed := 0.0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_silhouette_material = _make_silhouette_material()
	_build_preview()
	queue_redraw()


func get_sample_count() -> int:
	return _samples.size()


func get_animated_sprite(species_index: int) -> AnimatedSprite2D:
	if species_index < 0 or species_index >= _animated.size():
		return null
	return _animated[species_index]


func get_shared_frames(species_index: int) -> SpriteFrames:
	if species_index < 0 or species_index >= _frames_by_species.size():
		return null
	return _frames_by_species[species_index]


func _build_preview() -> void:
	for species_index in range(Assets.SPECIES.size()):
		var species := Assets.SPECIES[species_index]
		var frames := Assets.build_sprite_frames(species)
		if frames == null:
			push_error("Prepared frames are missing for %s; run build_animation_poc_assets.gd first" % species)
			return
		_frames_by_species.append(frames)
		var source_path := Assets.ASSET_ROOT + "/" + species + "_idle.png"
		var source_texture := load(source_path) as Texture2D
		if source_texture == null:
			push_error("Could not load approved source texture: %s" % source_path)
			return
		var prepared_texture := frames.get_frame_texture("idle", 0)
		var center_x := COLUMN_X[species_index]

		var source_sprite := _make_sprite(source_texture, Vector2(center_x, ROW_Y[0]), 32.0)
		add_child(source_sprite)
		_samples.append(source_sprite)

		var animated := AnimatedSprite2D.new()
		animated.sprite_frames = frames
		animated.animation = "idle"
		animated.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		animated.position = Vector2(center_x, ROW_Y[1])
		animated.scale = Vector2.ONE * (34.0 / float(Assets.FRAME_SIZE))
		add_child(animated)
		animated.play()
		_animated.append(animated)
		_samples.append(animated)
		animated.set_meta("poc_home_y", ROW_Y[1])
		animated.set_meta("poc_phase", float(species_index) * 1.31)

		var enlarged := _make_sprite(prepared_texture, Vector2(center_x, ROW_Y[2]), 58.0)
		add_child(enlarged)
		_samples.append(enlarged)

		var silhouette := _make_sprite(prepared_texture, Vector2(center_x, ROW_Y[3]), 32.0)
		silhouette.material = _silhouette_material
		add_child(silhouette)
		_samples.append(silhouette)
	set_process(true)


func _make_sprite(texture: Texture2D, at: Vector2, display_size: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = true
	sprite.offset = Vector2.ZERO
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = at
	sprite.scale = Vector2.ONE * (display_size / float(texture.get_width()))
	return sprite


func _process(delta: float) -> void:
	_elapsed += delta
	for sprite in _animated:
		var home_y: float = sprite.get_meta("poc_home_y")
		var phase: float = sprite.get_meta("poc_phase")
		sprite.position.y = home_y + sin(_elapsed * 1.1 + phase) * 1.0


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
	draw_rect(Rect2(Vector2.ZERO, Vector2(640.0, 360.0)), BACKGROUND)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(8.0, 18.0), "COZY MYSTIC · SIX SPECIES ANIMATION STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, PRIMARY)
	draw_string(font, Vector2(8.0, 33.0), "FRAME-BY-FRAME POSES + 1 PX PROCEDURAL FLOAT · PREVIEW ONLY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 7, MUTED)
	for species_index in range(DISPLAY_NAMES.size()):
		draw_string(font, Vector2(COLUMN_X[species_index] - 47.0, 54.0), DISPLAY_NAMES[species_index], HORIZONTAL_ALIGNMENT_CENTER, 94.0, 8, ACCENT)
	for row_index in range(ROW_Y.size()):
		var row_height := 62.0 if row_index == 2 else 54.0
		var rect := Rect2(Vector2(3.0, ROW_Y[row_index] - row_height * 0.5), Vector2(634.0, row_height))
		draw_rect(rect, PANEL)
		draw_rect(rect, BORDER, false, 1.0)
		draw_string(font, Vector2(5.0, ROW_Y[row_index] + 2.0), ROW_LABELS[row_index], HORIZONTAL_ALIGNMENT_LEFT, 35.0, 6, MUTED)
	for column_index in range(COLUMN_X.size()):
		draw_line(Vector2(COLUMN_X[column_index] + 48.0, 63.0), Vector2(COLUMN_X[column_index] + 48.0, 348.0), BORDER, 1.0)
