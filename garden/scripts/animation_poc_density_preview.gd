extends Node2D
class_name AnimationPocDensityPreview

const Assets = preload("res://scripts/sprite_animation_poc_assets.gd")
const EnvironmentScene: PackedScene = preload("res://scenes/environment.tscn")
const BACKGROUND := Color("#090e1c")
const MUTED := Color("#91acc2")
const SPECIES_PER_KIND := 8
const POPULATION_SIZE := 48

var _frames_by_species: Dictionary = {}
var _sprites: Array[AnimatedSprite2D] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for species in Assets.SPECIES:
		var frames := Assets.build_sprite_frames(species)
		if frames == null:
			push_error("Prepared frames are missing for %s; run build_animation_poc_assets.gd first" % species)
			return
		_frames_by_species[species] = frames
	add_child(EnvironmentScene.instantiate())
	_build_population()
	queue_redraw()


func get_creature_count() -> int:
	return _sprites.size()


func get_creature_species(index: int) -> String:
	if index < 0 or index >= _sprites.size():
		return ""
	return str(_sprites[index].get_meta("poc_species"))


func get_shared_frames(species: String) -> SpriteFrames:
	return _frames_by_species.get(species.to_lower()) as SpriteFrames


func _build_population() -> void:
	for index in range(POPULATION_SIZE):
		var species_index := index % Assets.SPECIES.size()
		var species := Assets.SPECIES[species_index]
		var sprite := AnimatedSprite2D.new()
		sprite.sprite_frames = _frames_by_species[species]
		sprite.animation = "idle"
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.centered = true
		sprite.offset = Vector2.ZERO
		sprite.scale = Vector2.ONE * (25.0 / float(Assets.FRAME_SIZE))
		var column := index % SPECIES_PER_KIND
		var row := floori(float(index) / float(SPECIES_PER_KIND))
		sprite.position = Vector2(43.0 + float(column) * 79.0, 88.0 + float(row) * 51.0)
		var identity := "preview:%02d" % index
		sprite.set_meta("poc_species", species)
		sprite.set_meta("poc_identity", identity)
		add_child(sprite)
		sprite.play()
		var frame_count := sprite.sprite_frames.get_frame_count("idle")
		var phase := Assets.phase_offset_for_identity(identity, species)
		sprite.frame = int(phase * float(frame_count)) % frame_count
		sprite.frame_progress = fmod(phase * 17.0, 1.0)
		_sprites.append(sprite)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(640.0, 360.0)), BACKGROUND)
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(10.0, 18.0), "SIX SPECIES · 48 SPRITE ANIMATION STUDY", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 12, Color("#f2f7fd"))
	draw_string(font, Vector2(10.0, 34.0), "8 EACH · DETERMINISTIC PHASES · SHARED SPRITEFRAMES · NO PROCESS DATA", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 7, MUTED)
