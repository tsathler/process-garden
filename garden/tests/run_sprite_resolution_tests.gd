extends SceneTree

const PreviewScene: PackedScene = preload("res://scenes/previews/sprite_resolution_preview.tscn")
const SpritePaths: Array[String] = [
	"res://assets/creatures/prototypes/cozy_mystic/wisp_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/beetle_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/spore_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/crystal_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/moth_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/larva_idle.png",
]
const ExpectedHashes: Array[String] = [
	"a560c4523358c87e2630b4f273494880b72b91b0fd354d26c76bc45d039efd9e",
	"30459d42813e0eaed4cb7da0e04e13ca369480510029c4be3b8075e9b3073f59",
	"ddec4e8d1f6d3ad61219caba25d0e05625718fc6968f559742dfdd5c1f2e13e9",
	"4e12b7dbdd34a0b89392c85b0fb2487854f42ad58fbf862f4e4af98a1e7df69c",
	"385f92378aea51d5a2476d58a9e7ec7e33f1fa9a122b5503ef2335c3237794f4",
	"b654340d4fe5f967fd301a1b5f310edbfd66e4b8a5de65a7bc08fe347d24c5e7",
]
const CandidateSizes: Array[int] = [64, 96, 128, 192]

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview_node := PreviewScene.instantiate()
	_check(preview_node != null, "resolution comparison scene instantiates")
	if preview_node == null:
		_finish()
		return
	root.add_child(preview_node)
	await process_frame
	var preview := preview_node as SpriteResolutionPreview
	_check(preview != null, "resolution scene uses the expected preview controller")
	if preview == null:
		preview_node.queue_free()
		await process_frame
		_finish()
		return
	_check(preview.get_sample_count() == 30, "six approved sources appear at source and four candidate resolutions")
	for species_index in range(SpritePaths.size()):
		var texture := load(SpritePaths[species_index]) as Texture2D
		_check(texture != null, "approved source %d loads" % species_index)
		if texture == null:
			continue
		_check(texture.get_width() == 1254 and texture.get_height() == 1254, "approved source %d stays 1254 square" % species_index)
		_check(FileAccess.get_sha256(ProjectSettings.globalize_path(SpritePaths[species_index])) == ExpectedHashes[species_index], "approved source %d remains byte-identical" % species_index)
		var image := texture.get_image()
		_check(image.get_format() == Image.FORMAT_RGBA8, "approved source %d retains RGBA pixels" % species_index)
		_check(image.get_pixel(0, 0).a == 0.0, "approved source %d retains transparent canvas" % species_index)
		for row_index in range(5):
			var sample := preview.get_sample(species_index, row_index)
			_check(sample != null, "species %d row %d has a preview sample" % [species_index, row_index])
			if sample == null:
				continue
			_check(sample.centered and sample.offset == Vector2.ZERO, "species %d row %d uses a centered pivot" % [species_index, row_index])
			_check(sample.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "species %d row %d uses nearest filtering" % [species_index, row_index])
			_check(is_equal_approx(sample.scale.x, 34.0 / float(sample.texture.get_width())), "species %d row %d is displayed at the game target size" % [species_index, row_index])
		for dimension in CandidateSizes:
			var candidate := preview.get_candidate_texture(species_index, dimension)
			_check(candidate != null, "species %d has %d px candidate" % [species_index, dimension])
			if candidate == null:
				continue
			_check(candidate.get_width() == dimension and candidate.get_height() == dimension, "species %d candidate has exact %d px dimensions" % [species_index, dimension])
			var candidate_image := candidate.get_image()
			_check(candidate_image.get_format() == Image.FORMAT_RGBA8, "species %d candidate keeps RGBA at %d px" % [species_index, dimension])
			_check(candidate_image.get_pixel(0, 0).a == 0.0, "species %d candidate keeps transparent corners at %d px" % [species_index, dimension])
			var duplicate := preview.get_candidate_texture(species_index, dimension)
			_check(candidate == duplicate, "species %d candidate texture is shared for %d px" % [species_index, dimension])
	preview_node.queue_free()
	await process_frame
	_finish()


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + message)


func _finish() -> void:
	print("Sprite resolution tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)
