extends SceneTree

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const OUTPUT_PATH := "res://../docs/synthetic-life/captures/synthetic-garden-demo.png"


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var main := MainScene.instantiate() as Control
	if main == null:
		push_error("Could not instantiate the Process Garden main scene")
		quit(1)
		return
	root.add_child(main)
	await process_frame
	main.set_source_mode("DEMO")
	for _frame in range(180):
		await process_frame
	RenderingServer.force_draw(true)
	await process_frame
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := image.save_png(path)
	if error != OK:
		push_error("Could not save Process Garden preview (error %d)" % error)
		quit(1)
		return
	print("Saved %s (%dx%d); represented=%d" % [path, image.get_width(), image.get_height(), main.get_node("Garden").get_creature_count()])
	quit()
