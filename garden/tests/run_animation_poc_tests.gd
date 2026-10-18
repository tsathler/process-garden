extends SceneTree

const Assets = preload("res://scripts/sprite_animation_poc_assets.gd")
const PreviewScene: PackedScene = preload("res://scenes/previews/animation_poc_preview.tscn")
const DensityScene: PackedScene = preload("res://scenes/previews/animation_poc_density_preview.tscn")
const ProductionVisual = preload("res://scripts/creature_visual.gd")
const APPROVED_SPECIES: Array[String] = ["wisp", "beetle", "spore", "crystal", "moth", "larva"]
const EXPECTED_FRAME_COUNTS: Dictionary = {
	"wisp": 4, "beetle": 2, "spore": 2, "crystal": 2, "moth": 3, "larva": 2
}
const APPROVED_SHA256: Array[String] = [
	"a560c4523358c87e2630b4f273494880b72b91b0fd354d26c76bc45d039efd9e",
	"30459d42813e0eaed4cb7da0e04e13ca369480510029c4be3b8075e9b3073f59",
	"ddec4e8d1f6d3ad61219caba25d0e05625718fc6968f559742dfdd5c1f2e13e9",
	"4e12b7dbdd34a0b89392c85b0fb2487854f42ad58fbf862f4e4af98a1e7df69c",
	"385f92378aea51d5a2476d58a9e7ec7e33f1fa9a122b5503ef2335c3237794f4",
	"b654340d4fe5f967fd301a1b5f310edbfd66e4b8a5de65a7bc08fe347d24c5e7",
]

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_originals()
	_test_identity_phase()
	for species in APPROVED_SPECIES:
		_test_prepared_frames(species, int(EXPECTED_FRAME_COUNTS[species]))
	await _test_previews()
	print("Animation proof tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_originals() -> void:
	for index in range(APPROVED_SPECIES.size()):
		var species := APPROVED_SPECIES[index]
		var path := "%s/%s_idle.png" % [Assets.ASSET_ROOT, species]
		var absolute_path := ProjectSettings.globalize_path(path)
		_check(FileAccess.get_sha256(absolute_path) == APPROVED_SHA256[index], "approved %s source is byte-identical" % species)
		var original := Image.new()
		var original_error := original.load(absolute_path)
		_check(original_error == OK, "%s original source loads" % species)
		if original_error == OK:
			_check(original.get_width() == 1254 and original.get_height() == 1254, "%s original remains 1254x1254" % species)
			_check(original.get_format() == Image.FORMAT_RGBA8, "%s original retains RGBA8 alpha" % species)
			_check(original.get_pixel(0, 0).a == 0.0, "%s original retains a transparent corner" % species)
	_check(ProductionVisual.SPECIES_COUNT == 4, "legacy renderer retains its four original procedural forms")


func _test_identity_phase() -> void:
	var identity := "pid:4242:create_time:1720000000.25"
	var first_phase := Assets.phase_offset_for_identity(identity, "beetle")
	_check(first_phase == Assets.phase_offset_for_identity(identity, "beetle"), "phase offset is deterministic for the same identity")
	_check(first_phase >= 0.0 and first_phase < 1.0, "phase offset stays within one animation cycle")
	_check(first_phase != Assets.phase_offset_for_identity(identity, "spore"), "species contributes to the animation phase")
	_check(
		first_phase != Assets.phase_offset_for_identity("pid:4243:create_time:1720000000.25", "beetle"),
		"different identities receive different animation phases"
	)


func _test_prepared_frames(species: String, expected_unique_frames: int) -> void:
	var files := Assets.frame_files(species)
	var inputs := Assets.input_paths(species)
	_check(files.size() == expected_unique_frames, "%s has the expected unique-frame manifest" % species)
	_check(inputs.size() == files.size(), "%s input and output manifests match" % species)
	if inputs.size() != files.size():
		return
	var images: Array[Image] = []
	for frame_index in range(files.size()):
		var file_name := files[frame_index]
		var image := Image.new()
		var path := ProjectSettings.globalize_path(Assets.PREPARED_ROOT + "/" + file_name)
		var error := image.load(path)
		_check(error == OK, "%s prepared frame loads: %s" % [species, file_name])
		if error != OK:
			continue
		_check(image.get_width() == 128 and image.get_height() == 128, "%s frame is 128x128: %s" % [species, file_name])
		_check(image.get_format() == Image.FORMAT_RGBA8, "%s frame keeps RGBA8: %s" % [species, file_name])
		_check(image.get_pixel(0, 0).a == 0.0, "%s frame keeps transparent corners: %s" % [species, file_name])
		_check(image.get_used_rect().has_area(), "%s frame is not empty: %s" % [species, file_name])
		images.append(image)
		if frame_index > 0:
			var source := Image.new()
			var source_error := source.load(ProjectSettings.globalize_path(inputs[frame_index]))
			_check(source_error == OK, "%s pose source loads: %s" % [species, inputs[frame_index]])
			if source_error == OK:
				_check(source.get_format() == Image.FORMAT_RGBA8, "%s pose source has RGBA alpha" % species)
				_check(source.get_width() == 1254 and source.get_height() == 1254, "%s pose source matches the approved canvas" % species)
				_check(source.get_used_rect().has_area(), "%s pose source is not empty" % species)
				_check(source.get_pixel(0, 0).a == 0.0, "%s pose source keeps transparent corners" % species)
	var unique_count := 0
	for index in range(images.size()):
		var unique := true
		for previous_index in range(index):
			if images[index].get_data() == images[previous_index].get_data():
				unique = false
				break
		if unique:
			unique_count += 1
	_check(unique_count == expected_unique_frames, "%s poses contain distinct frame pixels" % species)
	if images.size() > 1:
		var first_rect := images[0].get_used_rect()
		var first_center := Vector2(first_rect.position) + Vector2(first_rect.size) * 0.5
		for index in range(1, images.size()):
			var current_rect := images[index].get_used_rect()
			var current_center := Vector2(current_rect.position) + Vector2(current_rect.size) * 0.5
			_check(first_center.distance_to(current_center) <= 12.0, "%s frame pivot and silhouette center stay aligned" % species)
	var frames := Assets.build_sprite_frames(species)
	_check(frames != null, "%s SpriteFrames resource builds" % species)
	if frames == null:
		return
	for animation_name in ["idle", "active"]:
		_check(frames.has_animation(animation_name), "%s has %s animation" % [species, animation_name])
		_check(frames.get_animation_loop(animation_name), "%s %s animation loops" % [species, animation_name])
		_check(frames.get_frame_count(animation_name) == Assets.cycle_indices(species).size(), "%s %s cycle sequence has expected length" % [species, animation_name])
	_check(frames.get_animation_speed("active") > frames.get_animation_speed("idle"), "%s active playback is faster than idle" % species)
	for frame_index in range(Assets.cycle_indices(species).size()):
		var idle_texture := frames.get_frame_texture("idle", frame_index)
		var active_texture := frames.get_frame_texture("active", frame_index)
		_check(idle_texture != null and idle_texture == active_texture, "%s reuses frame texture between states" % species)


func _test_previews() -> void:
	var preview_node := PreviewScene.instantiate()
	_check(preview_node != null, "comparison preview scene instantiates")
	if preview_node == null:
		return
	root.add_child(preview_node)
	await process_frame
	var preview := preview_node as AnimationPocPreview
	_check(preview != null and preview.get_sample_count() == 24, "preview shows four comparison views for all six species")
	if preview != null:
		for species_index in range(APPROVED_SPECIES.size()):
			var shared_frames := preview.get_shared_frames(species_index)
			var idle_sprite := preview.get_animated_sprite(species_index)
			_check(shared_frames != null, "preview shares one SpriteFrames resource per species")
			_check(idle_sprite != null, "preview animates species %s" % APPROVED_SPECIES[species_index])
			if idle_sprite != null:
				_check(idle_sprite.sprite_frames == shared_frames, "animated preview uses shared SpriteFrames")
	preview_node.queue_free()
	await process_frame

	var density_node := DensityScene.instantiate()
	_check(density_node != null, "context preview scene instantiates")
	if density_node == null:
		return
	root.add_child(density_node)
	await process_frame
	var density := density_node as AnimationPocDensityPreview
	_check(density != null and density.get_creature_count() == 48, "context preview creates 48 animated organisms")
	if density != null:
		var counts: Dictionary = {}
		for species in APPROVED_SPECIES:
			counts[species] = 0
		for index in range(density.get_creature_count()):
			var species := density.get_creature_species(index)
			counts[species] = int(counts[species]) + 1
		for species in APPROVED_SPECIES:
			_check(counts[species] == 8, "context preview contains eight %s organisms" % species)
		var shared_counts: Dictionary = {}
		for species in APPROVED_SPECIES:
			shared_counts[species] = 0
		for child in density.get_children():
			var sprite := child as AnimatedSprite2D
			if sprite == null:
				continue
			for species in APPROVED_SPECIES:
				if sprite.sprite_frames == density.get_shared_frames(species):
					shared_counts[species] = int(shared_counts[species]) + 1
		for species in APPROVED_SPECIES:
			_check(shared_counts[species] == 8, "context %s instances share one SpriteFrames resource" % species)
	density_node.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + message)
