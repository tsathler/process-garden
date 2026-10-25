extends SceneTree

const PreviewScene: PackedScene = preload("res://scenes/previews/creature_sprite_preview.tscn")
const DensityScene: PackedScene = preload("res://scenes/previews/creature_density_preview.tscn")
const VisualScript = preload("res://scripts/creature_visual.gd")
const SPRITE_PATHS: Array[String] = [
	"res://assets/creatures/prototypes/cozy_mystic/wisp_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/beetle_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/moth_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/spore_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/crystal_idle.png",
	"res://assets/creatures/prototypes/cozy_mystic/larva_idle.png",
]

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_sprite_resources()
	_test_existing_species_and_hitboxes()
	await _test_previews()
	print("Sprite prototype tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_sprite_resources() -> void:
	for path in SPRITE_PATHS:
		var texture := load(path) as Texture2D
		_check(texture != null, "%s loads as a Texture2D" % path)
		if texture == null:
			continue
		_check(texture.get_width() > 0 and texture.get_height() > 0, "%s has valid dimensions" % path)
		var image := texture.get_image()
		_check(image != null and not image.is_empty(), "%s exposes pixel data" % path)
		if image == null or image.is_empty():
			continue
		_check(image.get_used_rect().has_area(), "%s contains nontransparent sprite pixels" % path)
		_check(image.get_pixel(0, 0).a == 0.0, "%s retains transparent canvas corners" % path)
		_check(
			texture.get_width() == 1254 and texture.get_height() == 1254,
			"%s retains its authored prototype canvas dimensions" % path
		)
	_check(
		ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility",
		"sprite prototype preserves the project's Compatibility renderer"
	)


func _test_existing_species_and_hitboxes() -> void:
	var identity := "pid:314:create_time:1700.0"
	var species := VisualScript.species_for_identity(identity)
	_check(
		VisualScript.species_for_identity(identity) == species,
		"the existing visual species hash remains deterministic"
	)
	_check(VisualScript.SPECIES_COUNT == 4, "legacy renderer retains its four original procedural forms")
	var wisp := VisualScript.new() as CreatureVisual
	wisp.set_species(VisualScript.Species.WISP)
	_check(wisp.contains_body_point(Vector2.ZERO), "the existing Wisp hitbox remains available")
	_check(not wisp.contains_body_point(Vector2(0.0, 15.0)), "the Wisp production hitbox is unchanged")
	var beetle := VisualScript.new() as CreatureVisual
	beetle.set_species(VisualScript.Species.BEETLE)
	_check(beetle.contains_body_point(Vector2.ZERO), "the existing Beetle hitbox remains available")
	_check(not beetle.contains_body_point(Vector2(17.0, 0.0)), "the Beetle production hitbox is unchanged")
	wisp.free()
	beetle.free()


func _test_previews() -> void:
	var preview_node := PreviewScene.instantiate()
	_check(preview_node != null, "comparison preview scene instantiates")
	if preview_node == null:
		return
	root.add_child(preview_node)
	await process_frame
	var preview := preview_node as CreatureSpritePreview
	_check(preview != null and preview.get_sample_count() == 24, "comparison has six species plus Wisp and Beetle baselines in three views")
	if preview != null:
		_check(preview.get_sprite_sample_count() == 18, "all six sprite species have game, 2x, and silhouette views")
		var centered_nearest_sprites := 0
		for sample in preview.get_children():
			var sprite := sample as Sprite2D
			if sprite == null:
				continue
			if (
				sprite.centered
				and sprite.offset == Vector2.ZERO
				and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
				and sprite.texture != null
			):
				centered_nearest_sprites += 1
		_check(centered_nearest_sprites == 18, "sprite origins are centered and all comparisons use nearest filtering")
		for path in ["wisp", "beetle", "spore", "crystal", "moth", "larva"]:
			_check(preview.get_sprite_texture(path) != null, "%s sprite is exposed by the opt-in preview" % path)
	preview_node.queue_free()
	await process_frame

	var density_node := DensityScene.instantiate()
	_check(density_node != null, "context density scene instantiates")
	if density_node == null:
		return
	root.add_child(density_node)
	await process_frame
	var density := density_node as CreatureDensityPreview
	_check(density != null and density.get_context_sprite_count() == 48, "context preview creates exactly 48 decorative sprites")
	if density != null:
		_check(density.get_context_species_name(0) == "WISP", "context species layout is deterministic")
		_check(density.get_context_species_name(2) == "SPORE", "context includes the Spore pilot")
		_check(density.get_context_species_name(3) == "CRYSTAL", "context includes the Crystal pilot")
		_check(density.get_context_species_name(5) == "LARVA", "context includes the Larva pilot")
		var species_counts: Dictionary = {}
		for index in range(density.get_context_sprite_count()):
			var species_name := density.get_context_species_name(index)
			species_counts[species_name] = int(species_counts.get(species_name, 0)) + 1
		_check(species_counts.size() == 6, "context preview represents all six species")
		var balanced := true
		for count in species_counts.values():
			balanced = balanced and int(count) == 8
		_check(balanced, "context preview has exactly eight samples of each species")
		var valid_context_sprites := 0
		for sample in density.get_children():
			var sprite := sample as Sprite2D
			if (
				sprite != null
				and sprite.texture != null
				and sprite.centered
				and sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
			):
				valid_context_sprites += 1
		_check(valid_context_sprites == 48, "context sprites use loaded centered textures with nearest filtering")
	density_node.queue_free()
	await process_frame


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
		print("PASS: " + message)
	else:
		_failed += 1
		push_error("FAIL: " + message)
