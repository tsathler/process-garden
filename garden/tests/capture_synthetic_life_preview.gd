extends SceneTree

const LabScene: PackedScene = preload("res://scenes/previews/synthetic_life_lab.tscn")
const OUTPUT_DIRECTORY := "res://../docs/synthetic-life/captures"
const SETTLE_FRAMES := 150
const STATES: Array[Dictionary] = [
	{"name": "wisp-dormant", "cpu": 4.0, "ram_mib": 256.0},
	{"name": "wisp-active", "cpu": 44.0, "ram_mib": 2048.0},
	{"name": "wisp-overclocked", "cpu": 94.0, "ram_mib": 6144.0},
	{"name": "wisp-ram-low", "cpu": 44.0, "ram_mib": 256.0},
	{"name": "wisp-ram-high", "cpu": 44.0, "ram_mib": 6144.0},
]
const FAMILIES: Array[String] = ["Wisp", "Beetle", "Spore", "Crystal", "Moth", "Larva"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var directory := DirAccess.make_dir_recursive_absolute(output_path)
	if directory != OK:
		push_error("Could not create Synthetic Life preview output directory: %s" % output_path)
		quit(1)
		return
	var lab := LabScene.instantiate() as SyntheticLifeLab
	if lab == null:
		push_error("Synthetic Life preview scene did not instantiate")
		quit(1)
		return
	root.add_child(lab)
	await process_frame
	for state in STATES:
		lab.set_preview_metrics(float(state["cpu"]), float(state["ram_mib"]))
		for frame in range(SETTLE_FRAMES):
			await process_frame
		if not await _save_capture(output_path, str(state["name"])):
			quit(1)
			return
	for family_index in range(FAMILIES.size()):
		lab.set_preview_species(family_index)
		lab.set_preview_metrics(44.0, 2048.0)
		for frame in range(SETTLE_FRAMES):
			await process_frame
		if not await _save_capture(output_path, "family-%s" % FAMILIES[family_index].to_lower()):
			quit(1)
	quit()


func _save_capture(output_path: String, capture_name: String) -> bool:
	RenderingServer.force_draw(true)
	await process_frame
	var image := root.get_texture().get_image()
	var output_file := "%s/%s.png" % [output_path, capture_name]
	var error := image.save_png(output_file)
	if error != OK:
		push_error("Could not write preview capture %s (error %d)" % [output_file, error])
		return false
	print("Saved %s (%dx%d)" % [output_file, image.get_width(), image.get_height()])
	return true
