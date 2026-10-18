extends RefCounted
class_name SpriteAnimationPocAssets

const FRAME_SIZE := 128
const ASSET_ROOT := "res://assets/creatures/prototypes/cozy_mystic"
const PREPARED_ROOT := ASSET_ROOT + "/cv22b/128"
const SPECIES: Array[String] = ["wisp", "beetle", "spore", "crystal", "moth", "larva"]

const WISP_INPUTS: Array[String] = [
	ASSET_ROOT + "/wisp_idle.png",
	ASSET_ROOT + "/cv22a/source/wisp_tendril_pose.png",
	ASSET_ROOT + "/cv22a/source/wisp_middle_tail_pose.png",
	ASSET_ROOT + "/cv22a/source/wisp_tail_left_pose.png",
]
const BEETLE_INPUTS: Array[String] = [
	ASSET_ROOT + "/beetle_idle.png",
	ASSET_ROOT + "/cv22b/source/beetle_step_pose.png",
]
const SPORE_INPUTS: Array[String] = [
	ASSET_ROOT + "/spore_idle.png",
	ASSET_ROOT + "/cv22b/source/spore_cap_sway_pose.png",
]
const CRYSTAL_INPUTS: Array[String] = [
	ASSET_ROOT + "/crystal_idle.png",
	ASSET_ROOT + "/cv22b/source/crystal_stance_pose.png",
]
const MOTH_INPUTS: Array[String] = [
	ASSET_ROOT + "/moth_idle.png",
	ASSET_ROOT + "/cv22a/source/moth_midbeat_pose.png",
	ASSET_ROOT + "/cv22a/source/moth_downbeat_pose.png",
]
const LARVA_INPUTS: Array[String] = [
	ASSET_ROOT + "/larva_idle.png",
	ASSET_ROOT + "/cv22b/source/larva_wave_pose.png",
]

const WISP_FRAME_FILES: Array[String] = [
	"wisp_idle_0.png", "wisp_idle_1.png", "wisp_idle_2.png", "wisp_idle_3.png"
]
const BEETLE_FRAME_FILES: Array[String] = ["beetle_idle_0.png", "beetle_idle_1.png"]
const SPORE_FRAME_FILES: Array[String] = ["spore_idle_0.png", "spore_idle_1.png"]
const CRYSTAL_FRAME_FILES: Array[String] = ["crystal_idle_0.png", "crystal_idle_1.png"]
const MOTH_FRAME_FILES: Array[String] = ["moth_idle_0.png", "moth_idle_1.png", "moth_idle_2.png"]
const LARVA_FRAME_FILES: Array[String] = ["larva_idle_0.png", "larva_idle_1.png"]

const WISP_CYCLE_INDICES: Array[int] = [0, 1, 2, 3, 2, 1]
const BEETLE_CYCLE_INDICES: Array[int] = [0, 1, 0, 1]
const SPORE_CYCLE_INDICES: Array[int] = [0, 1, 0, 1]
const CRYSTAL_CYCLE_INDICES: Array[int] = [0, 1, 0, 1]
const MOTH_CYCLE_INDICES: Array[int] = [0, 1, 2, 1]
const LARVA_CYCLE_INDICES: Array[int] = [0, 1, 0, 1]


static func species_names() -> Array[String]:
	return SPECIES.duplicate()


static func input_paths(species: String) -> Array[String]:
	match species.to_lower():
		"wisp":
			return WISP_INPUTS.duplicate()
		"beetle":
			return BEETLE_INPUTS.duplicate()
		"spore":
			return SPORE_INPUTS.duplicate()
		"crystal":
			return CRYSTAL_INPUTS.duplicate()
		"moth":
			return MOTH_INPUTS.duplicate()
		"larva":
			return LARVA_INPUTS.duplicate()
	return []


static func frame_files(species: String) -> Array[String]:
	match species.to_lower():
		"wisp":
			return WISP_FRAME_FILES.duplicate()
		"beetle":
			return BEETLE_FRAME_FILES.duplicate()
		"spore":
			return SPORE_FRAME_FILES.duplicate()
		"crystal":
			return CRYSTAL_FRAME_FILES.duplicate()
		"moth":
			return MOTH_FRAME_FILES.duplicate()
		"larva":
			return LARVA_FRAME_FILES.duplicate()
	return []


static func cycle_indices(species: String) -> Array[int]:
	match species.to_lower():
		"wisp":
			return WISP_CYCLE_INDICES.duplicate()
		"beetle":
			return BEETLE_CYCLE_INDICES.duplicate()
		"spore":
			return SPORE_CYCLE_INDICES.duplicate()
		"crystal":
			return CRYSTAL_CYCLE_INDICES.duplicate()
		"moth":
			return MOTH_CYCLE_INDICES.duplicate()
		"larva":
			return LARVA_CYCLE_INDICES.duplicate()
	return []


static func phase_offset_for_identity(identity: String, species: String) -> float:
	var value := 2166136261
	for byte_value in (species.to_lower() + "|" + identity).to_utf8_buffer():
		value = ((value ^ int(byte_value)) * 16777619) & 0x7fffffff
	return float(value) / 2147483647.0


static func build_sprite_frames(species: String) -> SpriteFrames:
	var files := frame_files(species)
	var sequence := cycle_indices(species)
	if files.is_empty() or sequence.is_empty():
		return null
	var textures: Array[Texture2D] = []
	for file_name in files:
		var image := Image.new()
		var error := image.load(ProjectSettings.globalize_path(PREPARED_ROOT + "/" + file_name))
		if error != OK or image.get_width() != FRAME_SIZE or image.get_height() != FRAME_SIZE:
			return null
		textures.append(ImageTexture.create_from_image(image))
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	for animation_name in ["idle", "active"]:
		frames.add_animation(animation_name)
		frames.set_animation_loop(animation_name, true)
		frames.set_animation_speed(animation_name, _fps_for(species.to_lower(), animation_name))
		for frame_index in sequence:
			frames.add_frame(animation_name, textures[frame_index])
	return frames


static func _fps_for(species: String, animation_name: String) -> float:
	if animation_name == "active":
		return 8.0 if species == "moth" else (6.0 if species == "wisp" else 3.0)
	match species:
		"moth":
			return 5.0
		"wisp":
			return 3.5
		"beetle", "larva":
			return 2.5
		_:
			return 2.0
