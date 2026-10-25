extends AnimatedSprite2D
class_name CozyMysticVisual

const SpriteLibrary = preload("res://scripts/cozy_mystic_sprite_library.gd")
const DISPLAY_SIZE := 34.0
const HITBOX_PADDING := 8.0
const SELECTION_COLOR := Color("#76e1d3")

var species := SpriteLibrary.Species.WISP
var process_identity := ""
var selected := false
var activity_level := 0.0
var _body_center := Vector2.ZERO
var _body_radius := Vector2(48.0, 48.0)


func _ready() -> void:
	centered = true
	offset = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	scale = Vector2.ONE * (DISPLAY_SIZE / float(SpriteLibrary.FRAME_SIZE))


func configure(identity: String, species_index: int) -> bool:
	if species_index < 0 or species_index >= SpriteLibrary.SPECIES_COUNT:
		return false
	var shared_frames := SpriteLibrary.frames_for_species(species_index)
	if shared_frames == null:
		return false
	var identity_changed := process_identity != identity or species != species_index
	process_identity = identity
	species = species_index
	if not identity_changed and sprite_frames == shared_frames:
		return true
	sprite_frames = shared_frames
	animation = "idle"
	play("idle")
	var phase := SpriteLibrary.phase_offset_for_identity(identity, species_index)
	var frame_position := phase * float(sprite_frames.get_frame_count("idle"))
	frame = floori(frame_position) % sprite_frames.get_frame_count("idle")
	frame_progress = fposmod(frame_position, 1.0)
	_update_hitbox()
	return true


func set_activity(value: float) -> void:
	activity_level = clampf(value if is_finite(value) else 0.0, 0.0, 1.0)
	speed_scale = clampf(0.82 + activity_level * 0.85, 0.82, 1.67)


func set_playback_active(active: bool) -> void:
	if not active:
		if sprite_frames != null:
			pause()
		return
	if sprite_frames == null:
		return
	var saved_frame := frame
	var saved_progress := frame_progress
	play("idle")
	set_frame_and_progress(saved_frame, saved_progress)


func set_selected(value: bool) -> void:
	if selected == value:
		return
	selected = value
	queue_redraw()


func contains_body_point(point: Vector2) -> bool:
	var normalized := Vector2(
		(point.x - _body_center.x) / maxf(_body_radius.x, 1.0),
		(point.y - _body_center.y) / maxf(_body_radius.y, 1.0)
	)
	return normalized.length_squared() <= 1.0


func get_species_name() -> String:
	return SpriteLibrary.species_name(species)


func _update_hitbox() -> void:
	_body_center = Vector2.ZERO
	_body_radius = Vector2(48.0, 48.0)
	var used := SpriteLibrary.opaque_bounds(species)
	if not used.has_area():
		return
	_body_center = Vector2(used.position) + Vector2(used.size) * 0.5 - Vector2.ONE * 64.0
	_body_radius = Vector2(used.size) * 0.5 + Vector2.ONE * HITBOX_PADDING


func _draw() -> void:
	if not selected:
		return
	var radius := maxf(_body_radius.x, _body_radius.y) + 5.0
	draw_arc(_body_center, radius, 0.0, TAU, 28, SELECTION_COLOR, 3.0, true)
