extends SceneTree

const WISP_PATH := "res://scripts/synthetic_wisp.gd"
const LIFE_VISUAL_PATH := "res://scripts/synthetic_life_visual.gd"
const LAB_SCENE: PackedScene = preload("res://scenes/previews/synthetic_life_lab.tscn")
const FAMILY_NAMES: Array[String] = ["Wisp", "Beetle", "Spore", "Crystal", "Moth", "Larva"]

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var wisp_script := load(WISP_PATH)
	_check(wisp_script != null, "Synthetic Wisp public visual contract is available")
	if wisp_script != null:
		await _test_bounded_response(wisp_script)
	await _test_lab_scene()
	_test_family_silhouettes()
	_test_collector_handshake_validation()
	print("Synthetic Wisp tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_bounded_response(wisp_script: Script) -> void:
	var wisp := wisp_script.new() as Node2D
	_check(wisp != null, "Synthetic Wisp can be created as a scene node")
	if wisp == null:
		return
	root.add_child(wisp)
	await process_frame
	wisp.set_metrics(0.0, 0)
	wisp.advance_visual(3.0)
	var dormant: Dictionary = wisp.get_visual_parameters()
	_check(dormant["state"] == "Dormant", "low CPU settles into Dormant")
	_check(_is_finite_bounded(dormant["mass_scale"], 0.85, 1.35), "zero RAM has bounded mass")

	wisp.set_metrics(75.0, 2_147_483_648)
	wisp.advance_visual(0.05)
	var transition: Dictionary = wisp.get_visual_parameters()
	_check(transition["activity"] < 0.75, "CPU response is smoothed across a short step")
	wisp.advance_visual(3.0)
	var active: Dictionary = wisp.get_visual_parameters()
	_check(active["state"] == "Active", "medium CPU settles into Active")
	_check(active["pulse_hz"] > dormant["pulse_hz"], "CPU increases pulse frequency")
	_check(active["filament_amplitude"] > dormant["filament_amplitude"], "CPU increases filament motion")
	_check(active["mass_scale"] > dormant["mass_scale"], "RAM increases body mass independently")
	_check(_is_finite_bounded(active["mass_scale"], 0.85, 1.35), "large RAM remains within scale bounds")

	wisp.set_metrics(1000.0, 64 * 1024 * 1024 * 1024)
	wisp.advance_visual(3.0)
	var overclocked: Dictionary = wisp.get_visual_parameters()
	_check(overclocked["state"] == "Overclocked", "high CPU reaches the artistic Overclocked state")
	_check(_is_finite_bounded(overclocked["activity"], 0.0, 1.0), "CPU clamps above 100 percent")
	_check(_is_finite_bounded(overclocked["mass_scale"], 0.85, 1.35), "RAM clamps at maximum body scale")

	wisp.set_metrics(INF, -1)
	wisp.advance_visual(3.0)
	var invalid: Dictionary = wisp.get_visual_parameters()
	_check(_is_finite_bounded(invalid["activity"], 0.0, 1.0), "non-finite CPU input cannot leak into visuals")
	_check(_is_finite_bounded(invalid["mass_scale"], 0.85, 1.35), "negative RAM cannot make invalid scale")
	wisp.queue_free()
	await process_frame


func _is_finite_bounded(value: Variant, minimum: float, maximum: float) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return is_finite(number) and number >= minimum and number <= maximum


func _test_lab_scene() -> void:
	var lab := LAB_SCENE.instantiate() as SyntheticLifeLab
	_check(lab != null, "isolated Wisp lab scene instantiates")
	if lab == null:
		return
	root.add_child(lab)
	await process_frame
	_check(lab.get_wisp() != null, "isolated preview owns its Wisp without collector dependencies")
	var sliders := lab.find_children("*", "HSlider", true, false)
	_check(sliders.size() == 2, "preview exposes CPU and RAM sliders")
	for family_index in range(FAMILY_NAMES.size()):
		_check(lab.set_preview_species(family_index), "%s family is selectable in the preview" % FAMILY_NAMES[family_index])
		_check(lab.get_wisp().get_species_name() == FAMILY_NAMES[family_index], "%s preview uses its own silhouette" % FAMILY_NAMES[family_index])
	lab.set_preview_metrics(100.0, 8192.0)
	lab.get_wisp().advance_visual(3.0)
	var high: Dictionary = lab.get_wisp().get_visual_parameters()
	_check(high["state"] == "Overclocked", "overclocked preview preset reaches high activity")
	var high_mass: float = high["mass_scale"]
	lab.set_preview_metrics(0.0, 0.0)
	lab.get_wisp().advance_visual(3.0)
	var low: Dictionary = lab.get_wisp().get_visual_parameters()
	_check(low["state"] == "Dormant", "dormant preview preset settles to low activity")
	_check(low["mass_scale"] < high_mass, "RAM slider input changes body mass")
	lab.queue_free()
	await process_frame


func _test_family_silhouettes() -> void:
	var visual_script := load(LIFE_VISUAL_PATH) as Script
	_check(visual_script != null, "shared six-family procedural visual contract is available")
	if visual_script == null:
		return
	var signatures: Dictionary = {}
	for family_index in range(FAMILY_NAMES.size()):
		var visual: Variant = visual_script.new()
		visual.set_species(family_index)
		var outline: PackedVector2Array = visual.get_silhouette_outline()
		_check(outline.size() >= 8, "%s provides an authored monochrome silhouette" % FAMILY_NAMES[family_index])
		var bounds: Rect2 = visual.get_local_visual_bounds()
		_check(bounds.has_area(), "%s has non-empty visual bounds" % FAMILY_NAMES[family_index])
		var signature := str(outline)
		_check(not signatures.has(signature), "%s silhouette differs from earlier families" % FAMILY_NAMES[family_index])
		signatures[signature] = true
		visual.free()
	_check(signatures.size() == 6, "all six organism families have different outlines")


func _test_collector_handshake_validation() -> void:
	var manager_script := load("res://scripts/collector_process_manager.gd")
	_check(manager_script != null, "bundled collector process manager is available")
	if manager_script == null:
		return
	var valid: Dictionary = manager_script.validate_readiness({"host": "127.0.0.1", "port": 49152.0})
	_check(valid.get("port") == 49152, "collector JSON numeric port normalizes to an integer")
	_check(manager_script.validate_readiness({"host": "0.0.0.0", "port": 49152}).is_empty(), "collector handshake rejects non-loopback hosts")
	_check(manager_script.validate_readiness({"host": "127.0.0.1", "port": 49152.5}).is_empty(), "collector handshake rejects fractional ports")


func _check(condition: bool, message: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error("FAIL: " + message)
