extends SceneTree

const Assets = preload("res://scripts/sprite_animation_poc_assets.gd")
const APPROVED_SHA256: Dictionary = {
	"wisp": "a560c4523358c87e2630b4f273494880b72b91b0fd354d26c76bc45d039efd9e",
	"beetle": "30459d42813e0eaed4cb7da0e04e13ca369480510029c4be3b8075e9b3073f59",
	"spore": "ddec4e8d1f6d3ad61219caba25d0e05625718fc6968f559742dfdd5c1f2e13e9",
	"crystal": "4e12b7dbdd34a0b89392c85b0fb2487854f42ad58fbf862f4e4af98a1e7df69c",
	"moth": "385f92378aea51d5a2476d58a9e7ec7e33f1fa9a122b5503ef2335c3237794f4",
	"larva": "b654340d4fe5f967fd301a1b5f310edbfd66e4b8a5de65a7bc08fe347d24c5e7",
}


func _initialize() -> void:
	call_deferred("_build")


func _build() -> void:
	if not _source_hashes_match():
		quit(1)
		return
	var output_directory := ProjectSettings.globalize_path(Assets.PREPARED_ROOT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_directory)
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		push_error("Could not create standardized animation output directory: %s" % error_string(directory_error))
		quit(1)
		return
	var failed := false
	for species in Assets.species_names():
		var sources := Assets.input_paths(species)
		var outputs := Assets.frame_files(species)
		if sources.size() != outputs.size():
			push_error("Input/output frame count mismatch for %s" % species)
			failed = true
			continue
		for index in range(sources.size()):
			var output_path := output_directory.path_join(outputs[index])
			if FileAccess.file_exists(output_path):
				var existing := Image.new()
				var existing_error := existing.load(output_path)
				if (
					existing_error == OK
					and existing.get_width() == Assets.FRAME_SIZE
					and existing.get_height() == Assets.FRAME_SIZE
					and existing.get_format() == Image.FORMAT_RGBA8
				):
					print("Preserved existing prepared frame: %s" % output_path)
					continue
				push_error("Refusing to overwrite an existing invalid prepared frame: %s" % output_path)
				failed = true
				continue
			var image := Image.new()
			var source_path := ProjectSettings.globalize_path(sources[index])
			var load_error := image.load(source_path)
			if load_error != OK:
				push_error("Could not load %s: %s" % [sources[index], error_string(load_error)])
				failed = true
				continue
			if image.get_width() != 1254 or image.get_height() != 1254:
				push_error("Unexpected source dimensions: %s" % sources[index])
				failed = true
				continue
			if image.get_format() != Image.FORMAT_RGBA8 or image.get_pixel(0, 0).a != 0.0:
				push_error("Source must be transparent RGBA8: %s" % sources[index])
				failed = true
				continue
			image.resize(Assets.FRAME_SIZE, Assets.FRAME_SIZE, Image.INTERPOLATE_NEAREST)
			var save_error := image.save_png(output_path)
			if save_error != OK:
				push_error("Could not save %s: %s" % [output_path, error_string(save_error)])
				failed = true
			else:
				print("Prepared %s at %dx%d: %s" % [species, Assets.FRAME_SIZE, Assets.FRAME_SIZE, output_path])
	quit(1 if failed else 0)


func _source_hashes_match() -> bool:
	var valid := true
	for species in Assets.species_names():
		var source_path := ProjectSettings.globalize_path(Assets.input_paths(species)[0])
		valid = valid and FileAccess.get_sha256(source_path) == str(APPROVED_SHA256[species])
	if not valid:
		push_error("Approved source hash differs; refusing to prepare standardized animation frames")
	return valid
