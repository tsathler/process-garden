extends RefCounted
class_name CozyMysticSpriteLibrary

enum Species { WISP, BEETLE, SPORE, CRYSTAL, MOTH, LARVA }

const FRAME_SIZE := 128
const FRAME_ROOT := "res://assets/creatures/cozy_mystic/128"
const SPECIES_NAMES: Array[String] = ["Wisp", "Beetle", "Spore", "Crystal", "Moth", "Larva"]
const SPECIES_COUNT := 6

const FRAME_FILES: Dictionary = {
	"wisp": ["wisp_idle_0.png", "wisp_idle_1.png", "wisp_idle_2.png", "wisp_idle_3.png"],
	"beetle": ["beetle_idle_0.png", "beetle_idle_1.png"],
	"spore": ["spore_idle_0.png", "spore_idle_1.png"],
	"crystal": ["crystal_idle_0.png", "crystal_idle_1.png"],
	"moth": ["moth_idle_0.png", "moth_idle_1.png", "moth_idle_2.png"],
	"larva": ["larva_idle_0.png", "larva_idle_1.png"],
}
const CYCLE_INDICES: Dictionary = {
	"wisp": [0, 1, 2, 3, 2, 1],
	"beetle": [0, 1, 0, 1],
	"spore": [0, 1, 0, 1],
	"crystal": [0, 1, 0, 1],
	"moth": [0, 1, 2, 1],
	"larva": [0, 1, 0, 1],
}

static var _frames_by_species: Dictionary = {}
static var _bottom_extent_by_species: Dictionary = {}
static var _opaque_bounds_by_species: Dictionary = {}


static func species_for_identity(identity: String) -> int:
	var value: int = 2166136261
	for byte_value in identity.to_utf8_buffer():
		value = ((value ^ int(byte_value)) * 16777619) & 0xffffffff
	# Use higher bits like the legacy species hash to avoid numeric PID low-bit bias.
	return (value >> 16) % SPECIES_COUNT


static func species_name(species_index: int) -> String:
	if species_index < 0 or species_index >= SPECIES_COUNT:
		return "Unknown"
	return SPECIES_NAMES[species_index]


static func phase_offset_for_identity(identity: String, species_index: int) -> float:
	var value: int = 2166136261
	var input := "%s|%s" % [identity, species_name(species_index).to_lower()]
	for byte_value in input.to_utf8_buffer():
		value = ((value ^ int(byte_value)) * 16777619) & 0x7fffffff
	return float(value) / 2147483647.0


static func frame_paths(species_index: int) -> Array[String]:
	var name := species_name(species_index).to_lower()
	if not FRAME_FILES.has(name):
		return []
	var paths: Array[String] = []
	for file_name: String in FRAME_FILES[name]:
		paths.append(FRAME_ROOT + "/" + file_name)
	return paths


static func cycle_for_species(species_index: int) -> Array[int]:
	var name := species_name(species_index).to_lower()
	if not CYCLE_INDICES.has(name):
		return []
	var cycle: Array[int] = []
	for frame_index: int in CYCLE_INDICES[name]:
		cycle.append(frame_index)
	return cycle


static func load_all() -> bool:
	for species_index in range(SPECIES_COUNT):
		if frames_for_species(species_index) == null:
			return false
	return true


static func frames_for_species(species_index: int) -> SpriteFrames:
	if species_index < 0 or species_index >= SPECIES_COUNT:
		return null
	if _frames_by_species.has(species_index):
		return _frames_by_species[species_index] as SpriteFrames
	var paths := frame_paths(species_index)
	var cycle := cycle_for_species(species_index)
	if paths.is_empty() or cycle.is_empty():
		return null
	var textures: Array[Texture2D] = []
	for path in paths:
		var texture := load(path) as Texture2D
		if texture == null or texture.get_width() != FRAME_SIZE or texture.get_height() != FRAME_SIZE:
			push_error("Cozy Mystic frame is missing or invalid: %s" % path)
			return null
		textures.append(texture)
	var sprite_frames := SpriteFrames.new()
	if sprite_frames.has_animation("default"):
		sprite_frames.remove_animation("default")
	sprite_frames.add_animation("idle")
	sprite_frames.set_animation_loop_mode("idle", SpriteFrames.LOOP_LINEAR)
	sprite_frames.set_animation_speed("idle", _idle_fps(species_index))
	for frame_index in cycle:
		if frame_index < 0 or frame_index >= textures.size():
			push_error("Cozy Mystic frame sequence is invalid for %s" % species_name(species_index))
			return null
		sprite_frames.add_frame("idle", textures[frame_index])
	_frames_by_species[species_index] = sprite_frames
	return sprite_frames


static func cached_species_count() -> int:
	return _frames_by_species.size()


static func opaque_bottom_extent(species_index: int) -> float:
	if species_index < 0 or species_index >= SPECIES_COUNT:
		return 0.0
	if _bottom_extent_by_species.has(species_index):
		return float(_bottom_extent_by_species[species_index])
	var bounds := opaque_bounds(species_index)
	var greatest_extent := maxf(float(bounds.end.y - 1) - FRAME_SIZE * 0.5, 0.0)
	_bottom_extent_by_species[species_index] = greatest_extent
	return greatest_extent


static func opaque_bounds(species_index: int) -> Rect2i:
	if species_index < 0 or species_index >= SPECIES_COUNT:
		return Rect2i()
	if _opaque_bounds_by_species.has(species_index):
		var cached_bounds: Rect2i = _opaque_bounds_by_species[species_index]
		return cached_bounds
	var bounds := Rect2i()
	for path in frame_paths(species_index):
		var texture := load(path) as Texture2D
		if texture == null:
			push_error("Cannot measure Cozy Mystic visual bounds: %s" % path)
			return Rect2i()
		var image := texture.get_image()
		if image == null or image.is_empty():
			push_error("Cannot read Cozy Mystic visual bounds: %s" % path)
			return Rect2i()
		var frame_bounds := image.get_used_rect()
		if frame_bounds.has_area():
			bounds = frame_bounds if not bounds.has_area() else bounds.merge(frame_bounds)
	_opaque_bounds_by_species[species_index] = bounds
	return bounds


static func visual_bounds_at(
	species_index: int, navigation_position: Vector2, supported: bool, ram_scale: float, margin: float = 2.0
) -> Rect2:
	var pixels := opaque_bounds(species_index)
	if not pixels.has_area():
		return Rect2(navigation_position - Vector2.ONE * 17.0, Vector2.ONE * 34.0).grow(margin)
	var scale_factor := 34.0 / float(FRAME_SIZE) * clampf(ram_scale, 0.85, 1.35)
	var pixel_origin := Vector2(pixels.position) - Vector2.ONE * (FRAME_SIZE * 0.5)
	var visual_origin := navigation_position
	if supported:
		visual_origin.y -= opaque_bottom_extent(species_index) * scale_factor
	var bounds := Rect2(
		visual_origin + pixel_origin * scale_factor,
		Vector2(pixels.size) * scale_factor
	)
	return bounds.grow(maxf(margin, 0.0))


static func support_offset(species_index: int, visual_scale: float) -> float:
	if not is_finite(visual_scale) or visual_scale <= 0.0:
		return 0.0
	return opaque_bottom_extent(species_index) * (34.0 / float(FRAME_SIZE)) * visual_scale


static func _idle_fps(species_index: int) -> float:
	match species_index:
		Species.WISP:
			return 3.5
		Species.MOTH:
			return 5.0
		Species.BEETLE, Species.LARVA:
			return 2.5
		_:
			return 2.0
