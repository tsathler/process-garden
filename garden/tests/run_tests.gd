extends SceneTree

const Parser = preload("res://scripts/snapshot_parser.gd")
const Registry = preload("res://scripts/process_registry.gd")
const Selector = preload("res://scripts/process_selector.gd")
const CreatureVisualScript = preload("res://scripts/creature_visual.gd")
const SpriteLibrary = preload("res://scripts/cozy_mystic_sprite_library.gd")
const CozyVisualScript = preload("res://scripts/cozy_mystic_visual.gd")
const SyntheticVisualScript = preload("res://scripts/synthetic_life_visual.gd")
const HabitatLayoutScript = preload("res://scripts/habitat_layout.gd")
const GardenControllerScript = preload("res://scripts/garden_controller.gd")
const DemoSnapshotSourceScript = preload("res://scripts/demo_snapshot_source.gd")
const CreatureScene: PackedScene = preload("res://scenes/creature.tscn")
const EnvironmentScene: PackedScene = preload("res://scenes/environment.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")
const CreatureDesignPreviewScene: PackedScene = preload(
	"res://scenes/previews/creature_design_preview.tscn"
)

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_valid_snapshot_and_null_cpu()
	_test_invalid_json_and_contract()
	await _test_snapshot_client_recovers_after_http_failure()
	_test_timestamp_calendar_validation()
	_test_duplicate_identity_and_negative_metric()
	_test_pid_zero_regression()
	_test_process_selection()
	_test_visible_population_limit()
	await _test_species_identity_mapping()
	await _test_visual_renderer_integration()
	await _test_synthetic_renderer_integration()
	await _test_habitat_layout()
	await _test_creature_design_preview()
	await _test_environment_ambience()
	await _test_garden_controller_reconciliation()
	await _test_creature_behavior_and_lifecycle()
	await _test_despawn_reuse_and_capacity()
	_test_separation_and_click_selection()
	await _test_click_routing_and_process_details()
	await _test_observatory_ui_states_and_demo_controls()
	await _test_demo_snapshot_source()
	await _test_demo_mode_switching()
	_test_add_persist_remove_and_pid_reuse()
	_test_repeat_and_partial_preserve_processes()
	_test_restart_and_freshness()
	print("Godot tests: %d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _test_valid_snapshot_and_null_cpu() -> void:
	var parsed: Dictionary = Parser.parse_text(JSON.stringify(_snapshot(1, 1000.0, "ok", [_proc(41, 10.5, null)])))
	_check(parsed["ok"], "valid snapshot accepted")
	_check(parsed["snapshot"]["processes"][0]["cpu_percent"] == null, "null CPU preserved")
	_check(parsed["snapshot"]["sequence"] == 1, "sequence normalized to integer")
	_check(Parser.parse_text("{")["category"] == "json", "invalid JSON rejected")


func _test_snapshot_client_recovers_after_http_failure() -> void:
	var server := TCPServer.new()
	var listen_result := server.listen(0, "127.0.0.1")
	_check(listen_result == OK, "local SnapshotClient fixture binds only loopback")
	if listen_result != OK:
		return
	var client := SnapshotClient.new()
	client.endpoint_url = "http://127.0.0.1:%d/v1/snapshot" % server.get_local_port()
	client.poll_interval_seconds = 0.25
	client.request_timeout_seconds = 1.0
	client.set_polling_enabled(false)
	var failures: Array[String] = []
	var received: Array[Dictionary] = []
	client.request_failed.connect(func(category: String, _detail: String): failures.append(category))
	client.snapshot_received.connect(func(snapshot: Dictionary): received.append(snapshot))
	root.add_child(client)
	await process_frame
	client.set_polling_enabled(true)
	var peers: Array[StreamPeerTCP] = []
	var request_count := 0
	var response := JSON.stringify(
		_snapshot(
			1,
			Time.get_unix_time_from_system(),
			"ok",
			[_proc(402, 20.5, null, 8192)]
		)
	).to_utf8_buffer()
	for _frame in range(240):
		if server.is_connection_available():
			var peer := server.take_connection()
			request_count += 1
			var reply := PackedByteArray()
			if request_count == 1:
				reply = "HTTP/1.1 503 Service Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".to_utf8_buffer()
			else:
				reply = (
					"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
					% response.size()
				).to_utf8_buffer()
				reply.append_array(response)
			peer.put_data(reply)
			peers.append(peer)
		await process_frame
		if not received.is_empty():
			break
	_check(failures == ["http_status"], "SnapshotClient reports a failed request and keeps polling")
	_check(request_count >= 2, "SnapshotClient reconnects after the first HTTP failure")
	_check(received.size() == 1, "SnapshotClient accepts a valid snapshot after reconnecting")
	if not received.is_empty():
		_check(received[0]["processes"][0]["cpu_percent"] == null, "reconnected snapshot preserves null CPU")
	client.set_polling_enabled(false)
	client.queue_free()
	server.stop()
	await process_frame


func _test_invalid_json_and_contract() -> void:
	var wrong_version := _snapshot(1, 1000.0, "ok", [])
	wrong_version["schema_version"] = 2
	_check(not Parser.validate_data(wrong_version)["ok"], "unsupported schema rejected")
	var missing := _snapshot(1, 1000.0, "ok", [])
	missing.erase("skipped_count")
	_check(not Parser.validate_data(missing)["ok"], "missing field rejected")
	var wrong_type := _snapshot(1, 1000.0, "ok", [])
	wrong_type["processes"] = "none"
	_check(not Parser.validate_data(wrong_type)["ok"], "wrong field type rejected")
	var bad_time := _snapshot(1, 1000.0, "ok", [])
	bad_time["collected_at"] = "2026-02-30T00:00:00Z"
	_check(not Parser.validate_data(bad_time)["ok"], "invalid calendar date rejected")
	var fractional_integer := _snapshot(1, 1000.0, "ok", [])
	fractional_integer["sequence"] = 1.5
	_check(not Parser.validate_data(fractional_integer)["ok"], "fractional integer rejected")
	var inconsistent_ok := _snapshot(1, 1000.0, "ok", [])
	inconsistent_ok["skipped_count"] = 1
	_check(not Parser.validate_data(inconsistent_ok)["ok"], "ok snapshot rejects skipped records")
	var inconsistent_partial := _snapshot(1, 1000.0, "partial", [])
	inconsistent_partial["skipped_count"] = 0
	_check(not Parser.validate_data(inconsistent_partial)["ok"], "partial snapshot requires skipped records")


func _test_timestamp_calendar_validation() -> void:
	_check(_timestamp_is_valid("2023-02-28T23:59:59.123456+00:00"), "ordinary February date with Python UTC fraction accepted")
	_check(_timestamp_is_valid("2024-02-29T12:00:00Z"), "leap day accepted")
	_check(_timestamp_is_valid("2000-02-29T12:00:00+00:00"), "400-year leap rule accepted")
	_check(not _timestamp_is_valid("2023-02-29T12:00:00Z"), "non-leap February 29 rejected")
	_check(not _timestamp_is_valid("1900-02-29T12:00:00Z"), "non-leap century February 29 rejected")
	_check(not _timestamp_is_valid("2024-02-30T12:00:00Z"), "February 30 rejected")
	_check(not _timestamp_is_valid("2024-04-31T12:00:00Z"), "April 31 rejected")
	_check(not _timestamp_is_valid("2024-02-29T24:00:00Z"), "out-of-range hour rejected")


func _timestamp_is_valid(timestamp: String) -> bool:
	var snapshot := _snapshot(1, 1000.0, "ok", [])
	snapshot["collected_at"] = timestamp
	return Parser.parse_text(JSON.stringify(snapshot))["ok"]


func _test_duplicate_identity_and_negative_metric() -> void:
	var duplicate := _snapshot(1, 1000.0, "ok", [_proc(8, 2.0, 1.0), _proc(8, 2.0, 2.0)])
	_check(not Parser.validate_data(duplicate)["ok"], "duplicate identity rejected")
	var negative := _snapshot(1, 1000.0, "ok", [_proc(8, 2.0, -1.0)])
	_check(not Parser.validate_data(negative)["ok"], "negative CPU rejected")
	var bad_memory := _snapshot(1, 1000.0, "ok", [_proc(8, 2.0, 0.0)])
	bad_memory["processes"][0]["memory_rss_bytes"] = -1
	_check(not Parser.validate_data(bad_memory)["ok"], "negative memory rejected")


func _test_pid_zero_regression() -> void:
	var zero_process := _proc(0, 1234.5, null)
	var parsed: Dictionary = Parser.parse_text(
		JSON.stringify(_snapshot(1, 1000.0, "ok", [zero_process]))
	)
	_check(parsed["ok"], "Windows PID 0 accepted through JSON parser")
	if parsed["ok"]:
		_check(
			Parser.identity_key(parsed["snapshot"]["processes"][0]) == "0|1234.50000000000000000",
			"PID 0 identity includes create_time"
		)

	var negative := _snapshot(1, 1000.0, "ok", [_proc(-1, 1234.5, null)])
	_check(not Parser.validate_data(negative)["ok"], "negative PID rejected")
	var null_pid := _snapshot(1, 1000.0, "ok", [_proc(0, 1234.5, null)])
	null_pid["processes"][0]["pid"] = null
	_check(not Parser.validate_data(null_pid)["ok"], "null PID rejected")
	var string_pid := _snapshot(1, 1000.0, "ok", [_proc(0, 1234.5, null)])
	string_pid["processes"][0]["pid"] = "0"
	_check(not Parser.validate_data(string_pid)["ok"], "text PID rejected")


func _test_species_identity_mapping() -> void:
	var observed_species: Dictionary = {}
	var stable := true
	for pid in range(1, 129):
		var record := _proc(pid, 1700.0 + float(pid), 0.0)
		var identity := Parser.identity_key(record)
		var first_species: int = SpriteLibrary.species_for_identity(identity)
		var repeated_species: int = SpriteLibrary.species_for_identity(identity)
		stable = stable and first_species == repeated_species
		observed_species[first_species] = true
	_check(stable, "six-species mapping remains stable for a complete process identity")
	_check(observed_species.size() == SpriteLibrary.SPECIES_COUNT, "identity mapping distributes across all six species")

	var reused_pid_first := Parser.identity_key(_proc(77, 1777.0, 0.0))
	var reused_pid_second := Parser.identity_key(_proc(77, 2777.0, 0.0))
	_check(reused_pid_first != reused_pid_second, "species input identity distinguishes reused PIDs")
	_check(
		SpriteLibrary.species_for_identity(reused_pid_first)
		!= SpriteLibrary.species_for_identity(reused_pid_second),
		"create_time participates in visual species mapping after PID reuse"
	)

	var creature := CreatureScene.instantiate() as ProcessCreature
	root.add_child(creature)
	var first_record := _proc(77, 1777.0, 4.0, 8_388_608)
	creature.set_process_record(first_record, reused_pid_first)
	var first_species := creature.species
	_check(
		creature._visual.species == creature._legacy_species_for(first_species),
		"legacy visual receives the compatible form for its stable six-species identity"
	)
	_check(creature.get_species_name() == SpriteLibrary.species_name(first_species), "details expose the stable art species")
	var updated_record := _proc(77, 1777.0, 35.0, 64_000_000)
	creature.set_process_record(updated_record, reused_pid_first)
	_check(creature.species == first_species, "metric updates preserve a persistent identity's species")
	creature.set_process_record(_proc(77, 2777.0, 1.0), reused_pid_second)
	_check(
		creature.species == SpriteLibrary.species_for_identity(reused_pid_second),
		"reused PID receives the species mapped from its new create_time identity"
	)
	creature.queue_free()
	await process_frame


func _test_visual_renderer_integration() -> void:
	_check(SpriteLibrary.load_all(), "all production Cozy Mystic SpriteFrames load")
	_check(SpriteLibrary.cached_species_count() == SpriteLibrary.SPECIES_COUNT, "one shared SpriteFrames resource is cached per species")
	var total_unique_frames := 0
	for species_index in range(SpriteLibrary.SPECIES_COUNT):
		var paths := SpriteLibrary.frame_paths(species_index)
		total_unique_frames += paths.size()
		var frames := SpriteLibrary.frames_for_species(species_index)
		_check(frames != null, "%s has a production SpriteFrames resource" % SpriteLibrary.species_name(species_index))
		if frames == null:
			continue
		_check(frames.has_animation("idle") and frames.get_animation_loop("idle"), "%s has a looping idle cycle" % SpriteLibrary.species_name(species_index))
		_check(frames.get_frame_count("idle") == SpriteLibrary.cycle_for_species(species_index).size(), "%s uses its approved frame cycle" % SpriteLibrary.species_name(species_index))
		for path in paths:
			var texture := load(path) as Texture2D
			_check(texture != null, "%s production frame loads" % path)
			if texture != null:
				_check(texture.get_width() == 128 and texture.get_height() == 128, "%s production frame stays 128x128" % path)
				var image := texture.get_image()
				_check(image != null and not image.is_empty() and image.get_pixel(0, 0).a == 0.0, "%s keeps RGBA transparency" % path)
			var prototype_path := path.replace("res://assets/creatures/cozy_mystic/128/", "res://assets/creatures/prototypes/cozy_mystic/cv22b/128/")
			_check(
				FileAccess.get_sha256(ProjectSettings.globalize_path(path))
				== FileAccess.get_sha256(ProjectSettings.globalize_path(prototype_path)),
				"%s matches the approved CV2.2-B frame byte-for-byte" % path
			)
			_check(SpriteLibrary.frames_for_species(species_index) == frames, "%s SpriteFrames remains shared" % SpriteLibrary.species_name(species_index))
	_check(total_unique_frames == 15, "production manifest contains exactly the approved 15 frames")

	var controller := GardenControllerScript.new() as GardenController
	var layer := Node2D.new()
	layer.name = "Creatures"
	controller.add_child(layer)
	root.add_child(controller)
	await process_frame
	_check(controller.set_visual_renderer(ProcessCreature.RENDERER_COZY_MYSTIC), "controller enables Cozy Mystic after resource preflight")
	var record := _proc(54321, 1723456789.25, null, 16_777_216)
	var identity := Parser.identity_key(record)
	controller.reconcile_processes([record])
	await process_frame
	var creature := controller.get_creature(identity)
	_check(creature != null, "Cozy Mystic renderer receives the standard process record")
	if creature == null:
		controller.queue_free()
		await process_frame
		return
	creature.position = Vector2(140.0, 160.0)
	var cozy_visual := creature.get_node("CozyVisual") as CozyMysticVisual
	var legacy_visual := creature.get_node("Visual") as CreatureVisual
	_check(cozy_visual.visible and not legacy_visual.visible, "Cozy renderer swaps visuals without replacing the process node")
	_check(cozy_visual.sprite_frames == SpriteLibrary.frames_for_species(creature.species), "creature uses the shared SpriteFrames for its stable species")
	_check(cozy_visual.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "production sprite uses nearest-neighbor filtering")
	var initial_frame := cozy_visual.frame
	var initial_progress := cozy_visual.frame_progress
	_check(controller.select_at(creature.get_visual_center_position()) == identity, "Cozy sprite hitbox selects its process")
	_check(creature.is_selected and controller.get_selected_identity() == identity, "selection highlight stays on the same identity")
	_check(controller.set_visual_renderer(ProcessCreature.RENDERER_LEGACY), "controller returns to LEGACY")
	_check(
		controller.get_creature(identity) == creature
		and creature.is_selected
		and creature.species == SpriteLibrary.species_for_identity(identity),
		"renderer switch preserves creature, selection, and species identity"
	)
	_check(not cozy_visual.visible and legacy_visual.visible, "LEGACY renderer is restored")
	_check(controller.set_visual_renderer(ProcessCreature.RENDERER_COZY_MYSTIC), "controller can switch back to Cozy Mystic")
	_check(controller.get_creature(identity) == creature and creature.species == SpriteLibrary.species_for_identity(identity), "switching renderer preserves identity and species")
	_check(cozy_visual.frame == initial_frame and is_equal_approx(cozy_visual.frame_progress, initial_progress), "renderer switch preserves sprite animation phase")
	controller.reconcile_processes([_proc(54321, 1723456789.25, 85.0, 268_435_456)])
	_check(controller.get_creature(identity) == creature, "metric update does not recreate a Cozy creature")
	_check(creature.is_selected and creature.species == SpriteLibrary.species_for_identity(identity), "metric update preserves selection and art species")
	creature.advance_simulation(1.0)
	_check(cozy_visual.speed_scale > 0.82 and cozy_visual.speed_scale <= 1.67, "CPU activity adjusts bounded per-instance animation speed")
	_check(cozy_visual.sprite_frames == SpriteLibrary.frames_for_species(creature.species), "activity does not replace shared SpriteFrames")
	var peer_visual := CozyVisualScript.new() as CozyMysticVisual
	root.add_child(peer_visual)
	peer_visual.configure("pid:54322:create_time:1723456789.25", creature.species)
	peer_visual.set_activity(0.0)
	_check(peer_visual.sprite_frames == cozy_visual.sprite_frames, "different creatures reuse the same species SpriteFrames")
	_check(
		is_equal_approx(peer_visual.speed_scale, 0.82)
		and cozy_visual.speed_scale > peer_visual.speed_scale,
		"CPU playback speed is stored per creature, not on shared frames"
	)
	peer_visual.queue_free()
	_check(controller.get_creature_count() == 1, "renderer changes do not duplicate process nodes")
	controller.queue_free()
	await process_frame


func _test_synthetic_renderer_integration() -> void:
	var controller := GardenControllerScript.new() as GardenController
	var layer := Node2D.new()
	layer.name = "Creatures"
	controller.add_child(layer)
	root.add_child(controller)
	await process_frame
	_check(controller.set_visual_renderer(ProcessCreature.RENDERER_SYNTHETIC_LIFE), "garden enables the Synthetic Life renderer")
	var record := _proc(61321, 1723456789.25, 42.0, 268_435_456)
	var identity := Parser.identity_key(record)
	controller.reconcile_processes([record])
	await process_frame
	var creature := controller.get_creature(identity)
	_check(creature != null, "Synthetic Life renderer uses the existing process node")
	if creature == null:
		controller.queue_free()
		await process_frame
		return
	var synthetic := creature.get_node_or_null("SyntheticVisual") as SyntheticLifeVisual
	_check(synthetic != null and synthetic.visible, "Synthetic Life visual replaces the fallback without duplication")
	_check(not (creature.get_node("Visual") as CreatureVisual).visible, "legacy visual stays hidden while Synthetic Life is active")
	_check(synthetic != null and synthetic.species == creature.species, "process identity keeps its deterministic family mapping")
	_check(controller.select_at(creature.get_visual_center_position()) == identity, "Synthetic Life bounds remain selectable")
	_check(creature.is_selected, "Synthetic Life selection remains on its process identity")
	controller.reconcile_processes([_proc(61321, 1723456789.25, 96.0, 2_147_483_648)])
	creature.advance_simulation(2.0)
	if synthetic != null:
		synthetic.advance_visual(2.0)
		var metrics := synthetic.get_visual_parameters()
		_check(metrics["state"] == "Overclocked", "Synthetic Life receives CPU activity from the process record")
		_check(metrics["mass_scale"] > 1.0, "Synthetic Life receives RAM mass from the process record")
	_check(controller.set_visual_renderer(ProcessCreature.RENDERER_LEGACY), "legacy fallback remains selectable")
	_check(controller.get_creature(identity) == creature and creature.is_selected, "renderer fallback preserves selection and process identity")
	controller.queue_free()
	await process_frame


func _test_habitat_layout() -> void:
	_check(SpriteLibrary.load_all(), "habitat support metadata loads from Cozy Mystic frames")
	for species in range(SpriteLibrary.SPECIES_COUNT):
		var opaque_bounds := SpriteLibrary.opaque_bounds(species)
		var bounds_cover_every_frame := opaque_bounds.has_area()
		for frame_path in SpriteLibrary.frame_paths(species):
			var frame_texture := load(frame_path) as Texture2D
			if frame_texture == null:
				bounds_cover_every_frame = false
				continue
			var frame_image := frame_texture.get_image()
			var frame_used := frame_image.get_used_rect() if frame_image != null else Rect2i()
			bounds_cover_every_frame = bounds_cover_every_frame and frame_used.has_area()
			bounds_cover_every_frame = bounds_cover_every_frame and opaque_bounds.position.x <= frame_used.position.x
			bounds_cover_every_frame = bounds_cover_every_frame and opaque_bounds.position.y <= frame_used.position.y
			bounds_cover_every_frame = bounds_cover_every_frame and opaque_bounds.end.x >= frame_used.end.x
			bounds_cover_every_frame = bounds_cover_every_frame and opaque_bounds.end.y >= frame_used.end.y
		_check(bounds_cover_every_frame, "%s visual envelope includes every animated frame's opaque bounds" % SpriteLibrary.species_name(species))
		var profiles := HabitatLayoutScript.profiles_for_species(species)
		_check(not profiles.is_empty(), "%s has at least one eligible habitat" % SpriteLibrary.species_name(species))
		for profile in profiles:
			_check(profile["eligible_species"].has(species), "habitat %s explicitly allows its assigned species" % profile["id"])
			_check(HabitatLayoutScript.candidate_positions(profile).size() > 0, "habitat %s provides usable anchor positions" % profile["id"])
	var expected_kinds := {
		SpriteLibrary.Species.WISP: [HabitatLayoutScript.Kind.AIR],
		SpriteLibrary.Species.MOTH: [HabitatLayoutScript.Kind.AIR],
		SpriteLibrary.Species.BEETLE: [HabitatLayoutScript.Kind.GROUND, HabitatLayoutScript.Kind.PERCH_LOW],
		SpriteLibrary.Species.LARVA: [HabitatLayoutScript.Kind.GROUND],
		SpriteLibrary.Species.CRYSTAL: [HabitatLayoutScript.Kind.GROUND, HabitatLayoutScript.Kind.PERCH_STABLE],
		SpriteLibrary.Species.SPORE: [HabitatLayoutScript.Kind.FUNGAL_GROUND, HabitatLayoutScript.Kind.FUNGAL_PERCH],
	}
	for species in expected_kinds:
		for profile in HabitatLayoutScript.profiles_for_species(species):
			_check(expected_kinds[species].has(profile["kind"]), "%s never receives an incompatible habitat" % SpriteLibrary.species_name(species))
		var placement := HabitatLayoutScript.choose_placement("species-support-%d" % species, species, [])
		var selected_profile: Dictionary = placement["profile"]
		if int(selected_profile["kind"]) == HabitatLayoutScript.Kind.AIR:
			_check(
				selected_profile["area"].has_point(placement["position"]),
				"%s placement stays in its declared air region" % SpriteLibrary.species_name(species)
			)
		else:
			_check(
				is_equal_approx(
					placement["position"].y,
					HabitatLayoutScript.surface_y_at(selected_profile, placement["position"].x)
				),
				"%s placement is attached to its declared support surface" % SpriteLibrary.species_name(species)
			)
	var larva_profiles := HabitatLayoutScript.profiles_for_species(SpriteLibrary.Species.LARVA)
	_check(
		larva_profiles.all(func(profile: Dictionary) -> bool: return profile["kind"] != HabitatLayoutScript.Kind.AIR),
		"Larva is never assigned to an air region"
	)
	var wisp_profiles := HabitatLayoutScript.profiles_for_species(SpriteLibrary.Species.WISP)
	_check(
		wisp_profiles.all(func(profile: Dictionary) -> bool: return profile["kind"] == HabitatLayoutScript.Kind.AIR),
		"Wisp remains in the air habitat"
	)
	var stable_identity := "test-process|create-time:100.0"
	var first := HabitatLayoutScript.choose_placement(stable_identity, SpriteLibrary.Species.LARVA, [])
	var repeated := HabitatLayoutScript.choose_placement(stable_identity, SpriteLibrary.Species.LARVA, [])
	_check(first["profile"]["id"] == repeated["profile"]["id"] and first["position"] == repeated["position"], "same identity receives a deterministic habitat and anchor")
	var other := HabitatLayoutScript.choose_placement("test-process|create-time:101.0", SpriteLibrary.Species.LARVA, [])
	_check(first["position"] != other["position"], "different identities do not automatically share the same empty anchor")
	var obstacle := Vector2(10.0, 20.0)
	var other_obstacle := Vector2(70.0, 90.0)
	var placement_a := HabitatLayoutScript.choose_placement(stable_identity, SpriteLibrary.Species.LARVA, [obstacle, other_obstacle])
	var placement_b := HabitatLayoutScript.choose_placement(stable_identity, SpriteLibrary.Species.LARVA, [other_obstacle, obstacle])
	_check(placement_a["profile"]["id"] == placement_b["profile"]["id"] and placement_a["position"] == placement_b["position"], "occupied-position order does not change layout choice")
	var larva_bounds_small := SpriteLibrary.visual_bounds_at(SpriteLibrary.Species.LARVA, Vector2(300.0, 298.0), true, 0.85)
	var larva_bounds_large := SpriteLibrary.visual_bounds_at(SpriteLibrary.Species.LARVA, Vector2(300.0, 298.0), true, 1.35)
	_check(SpriteLibrary.opaque_bounds(SpriteLibrary.Species.LARVA).has_area(), "species envelope uses measured opaque frame pixels")
	_check(larva_bounds_large.size.x > larva_bounds_small.size.x, "RAM scale expands the visual occupancy envelope")
	var visual_occupant: Array[Dictionary] = [{"identity": "fixture", "habitat_id": "ground_main", "supported": true, "bounds": larva_bounds_large}]
	var aware_a := HabitatLayoutScript.choose_placement_with_envelopes("crowded-larva", SpriteLibrary.Species.LARVA, visual_occupant)
	var aware_b := HabitatLayoutScript.choose_placement_with_envelopes("crowded-larva", SpriteLibrary.Species.LARVA, visual_occupant)
	var aware_bounds: Rect2 = aware_a["bounds"]
	_check(aware_a["position"] == aware_b["position"], "envelope-aware placement is deterministic for an identity")
	_check(not aware_bounds.intersects(larva_bounds_large), "new terrestrial placement avoids an available opaque-body overlap")
	var composition := HabitatLayoutScript.analyze_composition([
		{"habitat_id": "ground_main", "supported": true, "bounds": Rect2(10.0, 10.0, 30.0, 30.0)},
		{"habitat_id": "ground_main", "supported": false, "bounds": Rect2(25.0, 20.0, 30.0, 30.0)},
	], [Rect2(0.0, 0.0, 80.0, 80.0)])
	_check(composition["overlap_pairs"] == 1 and composition["overlap_area"] > 0.0, "composition diagnostics report overlapping visual envelopes")
	_check(composition["unsupported"] == 1 and composition["potential_interface_intersections"] == 2, "composition diagnostics report unsupported and potentially interface-obscured occupants")
	var capacity_estimates: Dictionary = composition["estimated_capacity_by_surface"]
	var capacities_measured := capacity_estimates.size() == HabitatLayoutScript.all_profiles().size()
	for capacity in capacity_estimates.values():
		capacities_measured = capacities_measured and int(capacity) > 0
	_check(capacities_measured, "composition capacity estimates use valid visual envelopes for each habitat")
	_check(is_equal_approx(HabitatLayoutScript.surface_y_at(first["profile"], first["position"].x), first["position"].y), "supported anchor position lies on its declared surface")
	_check(SpriteLibrary.opaque_bottom_extent(SpriteLibrary.Species.LARVA) > 0.0, "Larva support edge is measured from opaque sprite pixels")
	_check(SpriteLibrary.support_offset(SpriteLibrary.Species.LARVA, 1.0) > 0.0, "Larva support offset converts sprite edge to logical pixels")
	var air_profiles := HabitatLayoutScript.profiles_for_species(SpriteLibrary.Species.WISP)
	var air_candidates := HabitatLayoutScript.candidate_positions(air_profiles[0])
	var distinct_air_rows: Dictionary = {}
	var air_candidates_repeat := HabitatLayoutScript.candidate_positions(air_profiles[0])
	for candidate in air_candidates:
		distinct_air_rows[snappedf(candidate.y, 0.01)] = true
	_check(air_candidates.size() == HabitatLayoutScript.AIR_CANDIDATE_COUNT, "air habitat exposes the configured deterministic candidate count")
	_check(distinct_air_rows.size() > 30, "air habitat candidates are dispersed instead of arranged in horizontal rows")
	_check(air_candidates == air_candidates_repeat, "air candidate distribution is deterministic")
	var air_candidates_stay_inside := true
	for air_profile in air_profiles:
		var region: Rect2 = air_profile["area"]
		for candidate in HabitatLayoutScript.candidate_positions(air_profile):
			air_candidates_stay_inside = air_candidates_stay_inside and region.has_point(candidate)
	_check(air_candidates_stay_inside, "air candidates stay inside their habitat regions")
	var support_profiles := HabitatLayoutScript.ledge_profiles()
	var support_ids: Dictionary = {}
	for profile in support_profiles:
		support_ids[profile["id"]] = true
		var structure := HabitatLayoutScript.structure_polygon(profile)
		_check(structure.size() >= 4, "support structure %s has drawable geometry" % profile["id"])
		var visible_surface: PackedVector2Array = profile["points"]
		if profile["structure_style"] == "wall_shelf":
			var shelf_polygon := HabitatLayoutScript.ledge_polygon(profile)
			_check(shelf_polygon[0] == visible_surface[0] and shelf_polygon[1] == visible_surface[1], "wall shelf %s draws its habitat surface as the polygon top" % profile["id"])
		elif profile["structure_style"] == "mineral_shelf":
			_check(structure[1] == visible_surface[0] and structure[2] == visible_surface[1], "mineral shelf draws its habitat surface as the polygon top")
		if profile["id"].begins_with("root_perch_"):
			var foot_points := HabitatLayoutScript.support_foot_points(profile)
			var twigs := HabitatLayoutScript.root_branch_twigs(profile)
			_check(foot_points.size() == 2 and twigs.size() == 2, "root perch %s visibly connects its support to the ground" % profile["id"])
			for foot in foot_points:
				_check(is_equal_approx(foot.y, HabitatLayoutScript.ground_surface_y(foot.x)), "root perch foot meets the shared ground contour")
	_check(support_profiles.size() == 5, "environment includes wall, root and mineral support structures")
	_check(not support_ids.has("stable_perch_west") and not support_ids.has("stable_perch_east"), "legacy stable aliases do not duplicate visible structures")
	var fungal_perches := HabitatLayoutScript.mushroom_profiles()
	_check(fungal_perches.size() == 6, "six fungal platforms are available for Spore placement")
	var ground_banks := HabitatLayoutScript.ground_bank_profiles()
	_check(ground_banks.size() == 4, "four natural ground rises provide additional low support surfaces")
	var ground_bank_geometry_matches := true
	for bank in ground_banks:
		var bank_polygon := HabitatLayoutScript.ground_bank_polygon(bank)
		var bank_surface: PackedVector2Array = bank["points"]
		for point_index in range(bank_surface.size()):
			ground_bank_geometry_matches = ground_bank_geometry_matches and bank_polygon[point_index] == bank_surface[point_index]
		ground_bank_geometry_matches = ground_bank_geometry_matches and is_equal_approx(bank_polygon[bank_polygon.size() - 2].y, HabitatLayoutScript.ground_surface_y(bank_surface[bank_surface.size() - 1].x))
		ground_bank_geometry_matches = ground_bank_geometry_matches and is_equal_approx(bank_polygon[bank_polygon.size() - 1].y, HabitatLayoutScript.ground_surface_y(bank_surface[0].x))
		_check(bank["eligible_species"].has(SpriteLibrary.Species.LARVA), "Larva can use grounded terrain rises without receiving a perch or air habitat")
	_check(ground_bank_geometry_matches, "drawn ground-rise polygons preserve their exact modeled support surfaces")
	for fungal_profile in fungal_perches:
		var mushroom_center: Vector2 = fungal_profile["mushroom_center"]
		_check(is_equal_approx(mushroom_center.y, HabitatLayoutScript.ground_surface_y(mushroom_center.x)), "mushroom %s is rooted at the ground contour" % fungal_profile["id"])
		var cap_polygon := HabitatLayoutScript.mushroom_cap_polygon(fungal_profile)
		var support_points: PackedVector2Array = fungal_profile["points"]
		_check(
			cap_polygon[2] == support_points[0] and cap_polygon[3] == support_points[1],
			"mushroom %s uses its drawn flat crown as the Spore support" % fungal_profile["id"]
		)
		var stem := HabitatLayoutScript.mushroom_stem_rect(fungal_profile)
		_check(is_equal_approx(stem.end.y, mushroom_center.y), "mushroom %s stem reaches the ground contour" % fungal_profile["id"])
	var controller := GardenControllerScript.new() as GardenController
	var creature_layer := Node2D.new()
	creature_layer.name = "Creatures"
	controller.add_child(creature_layer)
	root.add_child(controller)
	await process_frame
	var records: Array[Dictionary] = []
	for pid in range(100, 180):
		records.append(_proc(pid, 2_000.0 + float(pid), float(pid % 10) * 4.0))
	controller.reconcile_processes(records)
	await process_frame
	_check(controller.get_creature_count() <= 30, "habitat placement preserves the 30-creature cap")
	var composition_metrics := controller.get_composition_metrics()
	_check(composition_metrics["count"] <= 30, "composition metrics include represented organisms within the cap")
	_check(composition_metrics["unsupported"] == 0, "composition metrics find no unsupported REAL/DEMO habitat occupants")
	_check(composition_metrics.has("estimated_capacity_by_surface") and composition_metrics.has("saturated_surfaces"), "composition metrics include per-surface estimated capacity and saturation")
	var positions_before: Dictionary = {}
	var all_supported := true
	for identity in controller.get_creature_identities():
		var represented := controller.get_creature(identity)
		positions_before[identity] = represented.position
		var allowed := HabitatLayoutScript.profiles_for_species(represented.species)
		var habitat_allowed := false
		for profile in allowed:
			if profile["id"] == represented.habitat_id:
				habitat_allowed = true
				var placement_is_on_surface := false
				if profile["kind"] == HabitatLayoutScript.Kind.AIR:
					var air_area: Rect2 = profile["area"]
					placement_is_on_surface = air_area.has_point(represented.position)
				else:
					placement_is_on_surface = is_equal_approx(
						represented.position.y,
						HabitatLayoutScript.surface_y_at(profile, represented.position.x)
					)
				all_supported = all_supported and placement_is_on_surface
		all_supported = all_supported and habitat_allowed
	_check(all_supported, "all REAL/DEMO-created creatures use an eligible habitat anchor")
	var identity_order := controller.get_creature_identities()
	var habitats_before: Dictionary = {}
	for identity in identity_order:
		habitats_before[identity] = controller.get_creature(identity).habitat_id
	var reversed_records := records.duplicate()
	reversed_records.reverse()
	controller.reconcile_processes(reversed_records)
	var positions_stable := true
	for identity in identity_order:
		var represented := controller.get_creature(identity)
		positions_stable = positions_stable and represented.position == positions_before[identity] and represented.habitat_id == habitats_before[identity]
	_check(positions_stable, "snapshot order changes do not redistribute persistent creatures")
	var selected_identity := identity_order[0]
	var selected_creature := controller.get_creature(selected_identity)
	controller.select_at(selected_creature.get_visual_center_position())
	_check(controller.get_selected_identity() == selected_identity, "habitat-aware sprite position remains selectable")
	var selected_position := selected_creature.position
	_check(controller.set_visual_renderer(ProcessCreature.RENDERER_COZY_MYSTIC), "habitat garden switches to the Cozy renderer")
	_check(controller.get_creature(selected_identity) == selected_creature and selected_creature.position == selected_position and controller.get_selected_identity() == selected_identity, "renderer switch preserves identity, habitat position, and selection")
	controller.queue_free()
	await process_frame

	var occupied: Array[Vector2] = []
	var anchor_positions: Dictionary = {}
	for index in range(60):
		var identity := "saturated-larva-%03d" % index
		var placement := HabitatLayoutScript.choose_placement(identity, SpriteLibrary.Species.LARVA, occupied)
		_check(placement["profile"]["kind"] == HabitatLayoutScript.Kind.GROUND, "saturated Larva remains supported")
		occupied.append(placement["position"])
		anchor_positions["%.3f|%.3f" % [placement["position"].x, placement["position"].y]] = true
	_check(anchor_positions.size() == 60, "layout saturation stress fixture still resolves 60 distinct ground anchors")

	var creature := CreatureScene.instantiate() as ProcessCreature
	root.add_child(creature)
	await process_frame
	creature.set_process_record(_proc(8811, 100.0, 0.0), "habitat-test|100.0")
	creature.configure_habitat(first["profile"], first["position"])
	creature.state = ProcessCreature.State.IDLE
	creature._pause_remaining = 0.0
	for _step in range(120):
		creature.advance_simulation(1.0 / 60.0)
	var expected_y := HabitatLayoutScript.surface_y_at(creature.habitat_profile, creature.position.x)
	_check(is_equal_approx(creature.position.y, expected_y), "ground movement follows its support surface without flying")
	_check(creature.position.x >= creature.habitat_profile["range_x"].x and creature.position.x <= creature.habitat_profile["range_x"].y, "ground movement stays within its assigned segment")
	_check(is_equal_approx(creature.get_float_offset(), 0.0), "supported creatures do not use free-flight bobbing")
	creature.queue_free()
	await process_frame


func _test_creature_design_preview() -> void:
	var identity := Parser.identity_key(_proc(314, 1700.0, 0.0))
	var species_before := CreatureVisualScript.species_for_identity(identity)
	var wisp := CreatureVisualScript.new() as CreatureVisual
	wisp.set_species(CreatureVisualScript.Species.WISP)
	_check(
		not wisp.is_design_v2() and not wisp.contains_body_point(Vector2(0.0, 15.0)),
		"Wisp current style keeps its existing body geometry and hitbox"
	)
	wisp.configure_design_preview(true)
	_check(
		wisp.is_design_v2() and wisp.contains_body_point(Vector2(0.0, 15.0)),
		"Wisp v2 preview hitbox covers its extended teardrop body"
	)
	wisp.configure_design_preview(true, true)
	_check(
		wisp.is_silhouette_preview() and wisp.contains_body_point(Vector2(0.0, 15.0)),
		"Wisp monochrome preview keeps the v2 silhouette hitbox"
	)
	_check(
		CreatureVisualScript.species_for_identity(identity) == species_before,
		"preview style does not change deterministic process species identity"
	)

	var beetle := CreatureVisualScript.new() as CreatureVisual
	beetle.set_species(CreatureVisualScript.Species.BEETLE)
	_check(
		not beetle.contains_body_point(Vector2(17.0, 0.0)),
		"Beetle current style keeps its existing shell hitbox"
	)
	beetle.configure_design_preview(true)
	_check(
		beetle.is_design_v2() and beetle.contains_body_point(Vector2(17.0, 0.0)),
		"Beetle v2 preview hitbox covers its wider carapace"
	)
	var spore := CreatureVisualScript.new() as CreatureVisual
	spore.set_species(CreatureVisualScript.Species.SPORE)
	spore.configure_design_preview(true)
	_check(
		not spore.is_design_v2() and spore.species == CreatureVisualScript.Species.SPORE,
		"v2 prototype option does not alter Spore or other production species"
	)
	wisp.free()
	beetle.free()
	spore.free()

	var preview_node: Node = CreatureDesignPreviewScene.instantiate()
	if not is_instance_valid(preview_node):
		_check(false, "comparison scene instantiates before its samples are inspected")
		return
	var preview := preview_node as CreatureDesignPreview
	if not is_instance_valid(preview):
		_check(false, "comparison scene exposes the preview controller")
		_release_test_node(preview_node)
		return
	root.add_child(preview)
	await process_frame
	_check(preview.get_preview_sample_count() == 12, "comparison scene renders four designs in three views")
	_check(
		preview.get_animated_sample_count() == 2,
		"only the two game-scale v2 samples animate in the comparison scene"
	)
	var monochrome_count := 0
	var valid_children := true
	for child in preview.get_children():
		var visual := child as CreatureVisual
		valid_children = valid_children and visual != null
		if visual != null and visual.is_silhouette_preview():
			monochrome_count += 1
	_check(valid_children, "preview contains only isolated creature visual samples")
	_check(monochrome_count == 4, "comparison includes monochrome silhouettes for both designs")
	preview.queue_free()
	await process_frame


func _test_environment_ambience() -> void:
	var first_node: Node = EnvironmentScene.instantiate()
	var second_node: Node = EnvironmentScene.instantiate()
	var main_node: Node = MainScene.instantiate()
	if not is_instance_valid(first_node) or not is_instance_valid(second_node):
		_check(false, "environment scene fixtures instantiate before ambience checks")
		_release_test_node(first_node)
		_release_test_node(second_node)
		_release_test_node(main_node)
		return
	var first := first_node as CaveEnvironment
	var second := second_node as CaveEnvironment
	var main_scene := main_node as Control
	if not is_instance_valid(first) or not is_instance_valid(second) or not is_instance_valid(main_scene):
		_check(false, "environment fixtures have the expected node types")
		_release_test_node(first_node)
		_release_test_node(second_node)
		_release_test_node(main_node)
		return
	var scene_environment := main_scene.get_node_or_null("Garden/Environment") as Node2D
	var creature_layer := main_scene.get_node_or_null("Garden/Creatures") as Node2D
	if not is_instance_valid(scene_environment) or not is_instance_valid(creature_layer):
		_check(false, "main scene exposes environment and creature layers")
		_release_test_node(first_node)
		_release_test_node(second_node)
		_release_test_node(main_node)
		return
	root.add_child(first)
	root.add_child(second)
	root.add_child(main_scene)
	await process_frame
	_check(
		scene_environment.get_index() < creature_layer.get_index(),
		"environment remains behind the selectable creature layer"
	)
	_check(first.get_ambient_particle_count() == 18, "environment uses a bounded fixed ambient particle count")
	_check(first.get_habitat_ground_points() == HabitatLayoutScript.ground_surface_points(), "ground art and support model share the same surface points")
	var environment_supports := first.get_habitat_ledge_profiles()
	_check(environment_supports.size() == 5, "environment draws every modeled wall, root and mineral support")
	var all_drawable_supports := true
	for support in environment_supports:
		all_drawable_supports = all_drawable_supports and HabitatLayoutScript.structure_polygon(support).size() >= 4
	_check(all_drawable_supports, "all visible support surfaces expose matching habitat geometry")
	_check(not first.show_habitat_debug, "habitat anchors are hidden in normal rendering")
	first.set_habitat_debug_visible(true)
	_check(first.show_habitat_debug, "habitat debug overlay can be enabled explicitly")
	first.set_habitat_debug_visible(false)
	_check(first.get_ambient_particle_count() <= 24, "ambient decoration remains below its configured cap")
	_check(first.get_child_count() == 0, "ambient particles do not create interactive scene nodes")
	var main_environment := main_scene.get_node("Garden/Environment") as CaveEnvironment
	_check(main_environment._synthetic_theme, "main application selects the Synthetic Life terrarium")
	main_scene.call("_on_renderer_mode_selected", 0)
	_check(not main_environment._synthetic_theme, "legacy renderer restores its original cave environment")
	main_scene.call("_on_renderer_mode_selected", 2)
	_check(main_environment._synthetic_theme, "Synthetic Life renderer restores the terrarium environment")
	var first_positions := first.get_ambient_particle_positions()
	var second_positions := second.get_ambient_particle_positions()
	_check(first_positions == second_positions, "ambient particle placement is deterministic")
	var in_field := true
	for particle_position in first_positions:
		in_field = in_field and Rect2(Vector2.ZERO, Vector2(640, 360)).has_point(particle_position)
	_check(in_field, "ambient particles remain within the logical garden bounds")
	var painter_order := first.get_painter_order()
	_check(
		painter_order.find("distant_rock") < painter_order.find("midground")
		and painter_order.find("midground") < painter_order.find("ground")
		and painter_order.find("ground") < painter_order.find("foreground_edges")
		and painter_order.find("foreground_edges") < painter_order.find("ambient"),
		"environment draws distant, middle, ground, edge, and ambient planes in order"
	)
	first.advance_ambience(0.25)
	second.advance_ambience(0.25)
	_check(
		first.get_ambient_particle_positions() == second.get_ambient_particle_positions(),
		"equal ambience time preserves deterministic particle motion"
	)
	_check(
		first.get_ambient_particle_positions() != first_positions,
		"ambient particles drift independently of process identities"
	)
	_release_test_node(first)
	_release_test_node(second)
	_release_test_node(main_scene)
	await process_frame


func _release_test_node(node: Node) -> void:
	if not is_instance_valid(node):
		return
	if node.is_inside_tree():
		node.queue_free()
	else:
		node.free()


func _test_process_selection() -> void:
	var selector := Selector.new()
	var under_limit: Array[Dictionary] = [_proc(3, 1.0, 0.0), _proc(1, 1.0, 0.0)]
	var under_result: Array[Dictionary] = selector.select_processes(under_limit, [], 60)
	_check(under_result.size() == 2, "selection keeps all candidates under limit")

	var many: Array[Dictionary] = []
	for pid in range(75):
		many.append(_proc(pid + 1, 1000.0 + pid, float(pid % 10), 1024 + pid))
	var selected := selector.select_processes(many, [], 60)
	_check(selected.size() == 30, "selector enforces the hard 30-creature visual cap")
	var reversed_many := many.duplicate()
	reversed_many.reverse()
	var reordered := selector.select_processes(reversed_many, [], 60)
	_check(_identities(selected) == _identities(reordered), "selection is independent of snapshot order")
	var tied := selector.select_processes(
		[_proc(10, 1.0, 0.0), _proc(2, 1.0, 0.0)], [], 2
	)
	_check(int(tied[0]["pid"]) == 2, "identity tie-break uses numeric PID order")

	var idle_heavy := _proc(0, 1.0, 100.0, 8_000_000_000)
	var small_active := _proc(7, 2.0, 1.0, 1024)
	var inactive_large := _proc(8, 3.0, 0.0, 4_000_000_000)
	var active_first := selector.select_processes([idle_heavy, inactive_large, small_active], [], 1)
	_check(int(active_first[0]["pid"]) == 7, "CPU activity outranks RAM and PID 0 activity is ignored")
	var ram_tiebreak := selector.select_processes(
		[_proc(10, 1.0, 0.0, 1024), _proc(11, 1.0, 0.0, 2_048_000)], [], 1
	)
	_check(int(ram_tiebreak[0]["pid"]) == 11, "RAM breaks equal activity ties")

	var incumbent := _proc(21, 1.0, 1.1, 1024)
	var challenger := _proc(22, 1.0, 4.9, 1024)
	var incumbent_key := Parser.identity_key(incumbent)
	var held := selector.select_processes([challenger, incumbent], [incumbent_key], 1)
	_check(int(held[0]["pid"]) == 21, "incumbent persists within the same activity band")
	var displaced := selector.select_processes(
		[_proc(22, 1.0, 10.0, 1024), incumbent], [incumbent_key], 1
	)
	_check(int(displaced[0]["pid"]) == 22, "stronger activity can replace an incumbent")
	var reused_pid := _proc(21, 2.0, 2.0, 1024)
	var reused := selector.select_processes([reused_pid], [incumbent_key], 1)
	_check(Parser.identity_key(reused[0]) != incumbent_key, "reused PID is selected as a new identity")


func _test_visible_population_limit() -> void:
	var selector := Selector.new()
	var populations: Array[int] = [0, 1, 29, 30, 31, 50, 150, 300, 500]
	for population in populations:
		var monitored: Array[Dictionary] = []
		for index in range(population):
			monitored.append(_proc(index + 10, 10_000.0 + float(index), float(index % 7), 1024 + index))
		var selected := selector.select_processes(monitored, [], 500)
		var default_selected := selector.select_processes(monitored, [])
		var reversed_monitored := monitored.duplicate()
		reversed_monitored.reverse()
		var reordered := selector.select_processes(reversed_monitored, [], 500)
		var identities := _identities(selected)
		var unique_identities: Dictionary = {}
		for identity in identities:
			unique_identities[identity] = true
		var expected_visible := mini(population, Selector.MAX_VISIBLE_CREATURES)
		_check(monitored.size() == population, "population %d remains fully monitored in the fixture" % population)
		_check(selected.size() == expected_visible, "population %d represents min(population, 30) creatures" % population)
		_check(default_selected.size() == expected_visible, "population %d respects the selector's 30-creature default" % population)
		_check(identities.size() == unique_identities.size(), "population %d contains no duplicate represented identities" % population)
		_check(identities == _identities(reordered), "population %d selection is deterministic across snapshot order" % population)
		var identities_belong_to_snapshot := true
		for process in selected:
			identities_belong_to_snapshot = identities_belong_to_snapshot and monitored.any(
				func(candidate: Dictionary) -> bool: return Parser.identity_key(candidate) == Parser.identity_key(process)
			)
		_check(identities_belong_to_snapshot, "population %d preserves selected PID/create_time identities" % population)
		var registry := Registry.new()
		var validated_snapshot := _validated(_snapshot(1, 1_700_000_000.0, "ok", monitored))
		registry.accept_snapshot(validated_snapshot, 1_700_000_001.0, 1000)
		_check(registry.get_tracked_count() == population, "population %d remains fully tracked in ProcessRegistry" % population)

	var controller := GardenControllerScript.new() as GardenController
	var creature_layer := Node2D.new()
	creature_layer.name = "Creatures"
	controller.add_child(creature_layer)
	root.add_child(controller)
	await process_frame
	var full_snapshot: Array[Dictionary] = []
	for index in range(31):
		full_snapshot.append(_proc(index + 10, 20_000.0 + float(index), 0.0, 1024))
	_check(controller.creature_limit == Selector.MAX_VISIBLE_CREATURES, "garden default visual limit is centrally set to 30")
	controller.creature_limit = 500
	controller.reconcile_processes(full_snapshot)
	_check(full_snapshot.size() == 31, "controller receives all 31 monitored records without truncating source data")
	_check(controller.get_creature_count() == 30, "controller cannot exceed the 30-creature cap when configured above it")
	var retained: Dictionary = {}
	for identity in controller.get_creature_identities():
		var creature := controller.get_creature(identity)
		retained[identity] = creature.get_instance_id()
	var reduced_snapshot: Array[Dictionary] = []
	for identity in controller.get_creature_identities().slice(0, 29):
		for process in full_snapshot:
			if Parser.identity_key(process) == identity:
				reduced_snapshot.append(process)
				break
	controller.reconcile_processes(reduced_snapshot)
	_check(controller.get_creature_count() <= 30, "31-to-29 population transition remains within cap during despawn")
	for identity in controller.get_creature_identities():
		if not reduced_snapshot.any(func(process: Dictionary) -> bool: return Parser.identity_key(process) == identity):
			continue
		var creature := controller.get_creature(identity)
		_check(creature.get_instance_id() == int(retained[identity]), "surviving identity retains its creature instance when population falls")
	for _frame in range(120):
		if controller.get_creature_count() == 29:
			break
		await process_frame
	_check(controller.get_creature_count() == 29, "completed despawn settles representation at the 29-process population")
	controller.queue_free()
	await process_frame


func _identities(processes: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for process in processes:
		result.append(Parser.identity_key(process))
	return result


func _test_garden_controller_reconciliation() -> void:
	var controller := GardenControllerScript.new() as GardenController
	controller.creature_limit = 3
	var creature_layer := Node2D.new()
	creature_layer.name = "Creatures"
	controller.add_child(creature_layer)
	root.add_child(controller)

	var processes: Array[Dictionary] = []
	for pid in range(1, 6):
		processes.append(_proc(pid, 100.0 + pid, float(pid), 1024))
	controller.reconcile_processes(processes)
	_check(controller.get_creature_count() == 3, "garden creates no more than its configured creature limit")
	_check(creature_layer.get_child_count() == 3, "only selected creature nodes are added")

	var retained_identity := controller.get_creature_identities()[0]
	var retained_creature := controller.get_creature(retained_identity)
	var retained_instance_id := retained_creature.get_instance_id()
	for process in processes:
		if Parser.identity_key(process) == retained_identity:
			process["name"] = "updated-worker"
			process["cpu_percent"] = 42.0
	processes.reverse()
	controller.reconcile_processes(processes)
	_check(controller.get_creature_count() == 3, "reordered snapshot keeps the same represented count")
	_check(
		controller.get_creature(retained_identity).get_instance_id() == retained_instance_id,
		"persistent process reuses its creature node"
	)
	_check(
		retained_creature.process_name == "updated-worker"
		and retained_creature.cpu_percent == 42.0,
		"existing creature receives current process metrics"
	)
	for identity in controller.get_creature_identities():
		var creature := controller.get_creature(identity)
		_check(
			creature.position.x >= 20.0
			and creature.position.x <= 620.0
			and creature.position.y >= 88.0
			and creature.position.y <= 312.0,
			"creature position remains inside garden bounds"
		)

	controller.reconcile_processes([])
	_check(controller.get_creature_count() == 3, "despawning creatures continue to count toward the node cap")
	_check(creature_layer.get_child_count() == 3, "removed identities remain only for their fade-out")
	await create_timer(ProcessCreature.DESPAWN_DURATION_SECONDS + 0.08).timeout
	_check(controller.get_creature_count() == 0, "completed despawn releases represented creatures")
	_check(creature_layer.get_child_count() == 0, "completed despawn removes creature nodes")
	controller.queue_free()
	await process_frame


func _test_creature_behavior_and_lifecycle() -> void:
	var creature := CreatureScene.instantiate() as ProcessCreature
	root.add_child(creature)
	creature.set_movement_bounds(Rect2(Vector2.ZERO, Vector2(120.0, 100.0)))
	creature.position = Vector2(60.0, 50.0)
	var identity := Parser.identity_key(_proc(44, 12.5, null, 0))
	creature.set_process_record(_proc(44, 12.5, null, 0), identity)
	_check(creature.state == ProcessCreature.State.SPAWNING, "new creature enters SPAWNING")
	var speed_before := creature._base_speed
	var pause_before := creature._pause_min
	var wander_before := creature._wander_distance
	var personality_peer := CreatureScene.instantiate() as ProcessCreature
	root.add_child(personality_peer)
	personality_peer.set_movement_bounds(Rect2(Vector2.ZERO, Vector2(120.0, 100.0)))
	personality_peer.position = Vector2(60.0, 50.0)
	personality_peer.set_process_record(_proc(44, 12.5, null, 0), identity)
	_check(
		personality_peer._base_speed == speed_before
		and personality_peer._pause_min == pause_before
		and personality_peer._wander_distance == wander_before,
		"same process identity derives the same movement personality"
	)
	personality_peer.queue_free()
	creature.set_process_record(_proc(44, 12.5, null, 0), identity)
	_check(
		creature._base_speed == speed_before
		and creature._pause_min == pause_before
		and creature._wander_distance == wander_before,
		"persistent identity keeps deterministic personality across snapshots"
	)
	await create_timer(ProcessCreature.SPAWN_DURATION_SECONDS + 0.08).timeout
	_check(creature.state == ProcessCreature.State.IDLE, "spawn transitions to IDLE for null CPU")
	var start_position := creature.position
	creature._target_position = start_position + Vector2(20.0, 0.0)
	creature._base_speed = 10.0
	creature._move_toward_destination(0.2, 1.0)
	_check(
		is_equal_approx(creature.position.x - start_position.x, 2.0),
		"movement distance uses elapsed delta time"
	)
	creature.position = start_position
	creature._pause_remaining = 0.0
	creature.advance_simulation(0.1)
	_check(creature.state == ProcessCreature.State.WANDERING, "IDLE transitions to WANDERING")
	var bounds := creature.get_effective_movement_bounds()
	_check(
		_point_is_within_bounds(creature._target_position, bounds),
		"wander destination respects visual bounds"
	)
	for _step in range(500):
		creature.advance_simulation(0.1)
		_check_position_in_bounds(creature, "movement remains inside bounds")

	creature.set_process_record(_proc(44, 12.5, 0.0, 0), identity)
	for _step in range(80):
		creature.advance_simulation(0.1)
	_check(creature.get_activity_level() == 0.0, "zero CPU remains visually idle")
	_check(creature.get_ram_scale() <= ProcessCreature.MAX_RAM_SCALE, "zero RAM scale remains clamped")
	creature.set_process_record(_proc(44, 12.5, 240.0, 2_147_483_648), identity)
	for _step in range(80):
		creature.advance_simulation(0.1)
	_check(creature.state == ProcessCreature.State.ACTIVE, "elevated CPU activates creature")
	_check(creature.get_activity_level() <= 1.0, "CPU over 100 percent normalizes to a safe level")
	_check(
		creature._base_speed * (1.0 + creature.get_activity_level() * 0.65) <= 22.0,
		"high CPU keeps travel speed within a calm bound"
	)
	_check(
		creature.get_ram_scale() <= ProcessCreature.MAX_RAM_SCALE,
		"high RAM does not exceed visual scale limit"
	)
	_check(
		creature._scale_for_memory(0) == ProcessCreature.MIN_RAM_SCALE,
		"zero RAM maps to minimum visual scale"
	)
	_check(
		creature._activity_from_cpu(1000.0, 0) == 0.0,
		"PID 0 does not create useful visual activity"
	)
	_check(
		creature._activity_from_cpu(null, 44) == 0.0,
		"null CPU maps to resting activity"
	)
	creature.begin_despawn()
	_check(creature.state == ProcessCreature.State.DESPAWNING, "removed creature enters DESPAWNING")
	creature.cancel_despawn()
	_check(creature.state == ProcessCreature.State.SPAWNING, "return during despawn reuses and fades in")
	await create_timer(ProcessCreature.SPAWN_DURATION_SECONDS + 0.08).timeout
	_check(is_instance_valid(creature), "cancelled despawn does not free a returning creature")
	creature.begin_despawn()
	await create_timer(ProcessCreature.DESPAWN_DURATION_SECONDS + 0.08).timeout
	_check(creature.state == ProcessCreature.State.DESPAWNING, "despawn completes in its terminal state")
	creature.queue_free()
	await process_frame


func _test_despawn_reuse_and_capacity() -> void:
	var controller := GardenControllerScript.new() as GardenController
	controller.creature_limit = 1
	var creature_layer := Node2D.new()
	creature_layer.name = "Creatures"
	controller.add_child(creature_layer)
	root.add_child(controller)
	var original := _proc(52, 20.0, 0.0)
	var original_identity := Parser.identity_key(original)
	controller.reconcile_processes([original])
	var original_creature := controller.get_creature(original_identity)
	_check(controller.get_creature_count() == 1, "initial selected identity spawns once")
	controller.select_at(original_creature.get_visual_center_position())
	_check(controller.get_selected_identity() == original_identity, "selection stores process identity")
	# A repeated valid snapshot preserves the same node and doesn't restart its birth animation.
	var generation_before := original_creature._animation_generation
	controller.reconcile_processes([original])
	_check(
		controller.get_creature(original_identity) == original_creature
		and original_creature._animation_generation == generation_before,
		"repeated snapshot preserves the node without restarting its animation"
	)
	controller.reconcile_processes([])
	_check(original_creature.state == ProcessCreature.State.DESPAWNING, "complete removal starts despawn")
	_check(
		controller.get_selected_identity() == original_identity,
		"selection is retained during the short despawn transition"
	)
	controller.reconcile_processes([original])
	_check(
		controller.get_creature(original_identity) == original_creature,
		"identity returning during despawn reuses the existing node"
	)
	_check(controller.get_creature_count() == 1, "return does not duplicate a creature")
	await create_timer(ProcessCreature.SPAWN_DURATION_SECONDS + 0.08).timeout
	var reused_pid := _proc(52, 21.0, 0.0)
	var reused_identity := Parser.identity_key(reused_pid)
	controller.reconcile_processes([reused_pid])
	_check(controller.get_creature_count() == 1, "PID reuse does not exceed the node cap")
	_check(
		controller.get_creature(reused_identity) == null,
		"new PID identity waits for the old identity to despawn"
	)
	await create_timer(ProcessCreature.DESPAWN_DURATION_SECONDS + 0.08).timeout
	_check(
		controller.get_creature(reused_identity) != null,
		"deferred PID replacement is created after the old node is released"
	)
	_check(controller.get_creature_count() == 1, "deferred replacement preserves configured cap")
	_check(controller.get_selected_identity().is_empty(), "PID reuse does not inherit selection")
	controller.queue_free()
	await process_frame


func _test_separation_and_click_selection() -> void:
	var controller := GardenControllerScript.new() as GardenController
	controller.creature_limit = 3
	var creature_layer := Node2D.new()
	creature_layer.name = "Creatures"
	controller.add_child(creature_layer)
	root.add_child(controller)
	var records: Array[Dictionary] = [
		_proc(61, 10.0, null), _proc(62, 11.0, null), _proc(63, 12.0, null)
	]
	controller.reconcile_processes(records)
	var identities := controller.get_creature_identities()
	var first := controller.get_creature(identities[0])
	var second := controller.get_creature(identities[1])
	var third := controller.get_creature(identities[2])
	# Isolate the generic pairwise separation test from habitat constraints.
	# Supported-surface movement is verified in _test_habitat_layout.
	for creature: ProcessCreature in [first, second, third]:
		creature.habitat_profile.clear()
		creature.habitat_id = ""
		creature.habitat_kind = -1
		creature.set_movement_bounds(Rect2(Vector2.ZERO, Vector2(640.0, 360.0)))
	first.position = Vector2(100.0, 140.0)
	second.position = Vector2(100.0, 140.0)
	third.position = Vector2(200.0, 140.0)
	var before_distance := first.position.distance_to(second.position)
	controller.update_separation(0.1)
	var first_force := first.get_separation_force()
	var second_force := second.get_separation_force()
	_check(
		first_force.length() > 0.0 and second_force.length() > 0.0,
		"overlapping creatures receive a soft separation direction"
	)
	_check(
		is_finite(first_force.x) and is_finite(first_force.y)
		and is_finite(second_force.x) and is_finite(second_force.y),
		"separation remains finite for coincident creatures"
	)
	_check(
		third.get_separation_force() == Vector2.ZERO,
		"distant creature receives no separation force"
	)
	first.advance_simulation(0.1)
	second.advance_simulation(0.1)
	var after_distance := first.position.distance_to(second.position)
	_check(after_distance > before_distance, "soft separation increases overlap distance")
	_check(after_distance < 3.0, "separation moves gradually without teleporting")
	var bounds := first.get_effective_movement_bounds()
	_check(_point_is_within_bounds(first.position, bounds), "separation respects garden limits")

	first.position = first.get_territory_center()
	first._choose_destination()
	_check(
		first._target_position.distance_to(first.get_territory_center())
		<= first.get_territory_radius(),
		"wander targets prefer the identity's local territory"
	)
	var float_before := first.get_float_offset()
	var navigation_before := first.position
	first.set_separation_force(Vector2.ZERO)
	first._separation_level = Vector2.ZERO
	first.advance_simulation(0.17)
	_check(first.get_float_offset() != float_before, "visual float phase advances over time")
	_check(
		first.position == navigation_before
		and is_equal_approx(first._visual.position.y, first.get_float_offset()),
		"float offset changes the visual node without moving navigation position"
	)

	first.position = Vector2(100.0, 140.0)
	second.position = Vector2(200.0, 140.0)
	third.position = Vector2(300.0, 140.0)
	_check(controller.select_at(first.get_visual_center_position()) == identities[0], "click hit test selects a creature")
	_check(first.is_selected, "selected creature receives visual highlight state")
	_check(controller.select_at(second.get_visual_center_position()) == identities[1], "clicking another creature changes selection")
	_check(not first.is_selected and second.is_selected, "highlight moves to the new selection")
	_check(controller.select_at(Vector2.ZERO).is_empty(), "empty-space click clears selection")

	first._visual.position = Vector2.ZERO
	first._visual.scale = Vector2.ONE
	var scale_test_point := _scale_test_point(first.species)
	_check(
		not first.contains_local_point(scale_test_point),
		"base-scale click area excludes points beyond the body"
	)
	first._visual.scale = Vector2(1.35, 1.35)
	_check(
		first.contains_local_point(scale_test_point),
		"larger visual scale expands the click area"
	)
	first._visual.scale = Vector2.ONE
	first._visual.position = Vector2.ZERO

	first.position = Vector2(320.0, 210.0)
	second.position = first.position
	third.position = Vector2(500.0, 210.0)
	first._visual.position = Vector2.ZERO
	second._visual.position = Vector2.ZERO
	var visually_upper := first if first.get_index() > second.get_index() else second
	_check(
		controller.select_at(first.get_visual_center_position()) == visually_upper.process_identity,
		"overlap selection follows the top draw-order tie break"
	)
	first.begin_despawn()
	first.set_selected(false)
	_check(
		not first.contains_local_point(Vector2.ZERO),
		"despawning creature cannot be selected again"
	)
	controller.queue_free()
	await process_frame


func _scale_test_point(species: int) -> Vector2:
	match species:
		CreatureVisualScript.Species.WISP:
			return Vector2(12.0, 0.0)
		CreatureVisualScript.Species.BEETLE:
			return Vector2(18.0, 0.0)
		CreatureVisualScript.Species.SPORE:
			return Vector2(17.0, -6.0)
		CreatureVisualScript.Species.CRYSTAL:
			return Vector2(15.0, 0.0)
	return Vector2(1000.0, 1000.0)


func _test_click_routing_and_process_details() -> void:
	var main := MainScene.instantiate() as Control
	# Keep this integration fixture independent from a locally running collector.
	# Main starts SnapshotClient on entry; an API response could otherwise replace
	# these synthetic identities while their spawn tweens are still running.
	var snapshot_client := main.get_node("SnapshotClient") as SnapshotClient
	snapshot_client.endpoint_url = "http://127.0.0.1:0/v1/snapshot"
	root.add_child(main)
	await process_frame
	var garden := main.get_node("Garden") as GardenController
	var first_record := _proc(71, 20.0, 12.5, 3_145_728)
	first_record["name"] = "process-name-that-is-longer-than-the-details-card"
	var records: Array[Dictionary] = [first_record, _proc(72, 21.0, null, 0)]
	garden.reconcile_processes(records)
	var identities := garden.get_creature_identities()
	if identities.size() != records.size():
		_check(false, "synthetic click fixture creates both process identities")
		main.queue_free()
		await process_frame
		return
	var first := garden.get_creature(identities[0])
	var second := garden.get_creature(identities[1])
	if not is_instance_valid(first) or not is_instance_valid(second):
		_check(false, "synthetic click fixture creates both process identities")
		main.queue_free()
		await process_frame
		return
	first.position = Vector2(120.0, 170.0)
	second.position = Vector2(260.0, 170.0)
	var first_spawned := await _wait_for_spawn_completion(first)
	var second_spawned := await _wait_for_spawn_completion(second)
	_check(first_spawned, "synthetic click target completes its spawn animation")
	_check(second_spawned, "second synthetic process completes its spawn animation")
	if not first_spawned or not second_spawned:
		main.queue_free()
		await process_frame
		return
	_check(first.is_inside_tree(), "synthetic click target remains in the scene tree")
	_check(
		first.is_visible_in_tree() and first.state != ProcessCreature.State.DESPAWNING,
		"synthetic click target is visible and eligible after its spawn animation"
	)
	var point_to_viewport := garden.get_global_transform_with_canvas()
	var first_click := point_to_viewport * first.get_visual_center_position()
	await _send_left_click(first_click)
	_check(garden.get_selected_identity() == identities[0], "viewport coordinates select the expected identity")
	_check(main.mouse_filter == Control.MOUSE_FILTER_IGNORE, "full-screen root does not consume pointer input")
	var details_panel := main.get_node("ProcessDetails") as Control
	_check(details_panel.visible, "selecting a creature opens the details panel")
	_check(
		details_panel.mouse_filter == Control.MOUSE_FILTER_STOP,
		"visible details card consumes pointer input instead of clicking through"
	)
	var name_label := main.get("_details_name_label") as Label
	_check(
		name_label.text.length() <= 26 and name_label.tooltip_text == first_record["name"],
		"long process names fit the details card and retain the full name as a tooltip"
	)
	var identity_label := main.get("_details_pid_label") as Label
	_check(
		identity_label.text.contains(first.get_species_name()) and identity_label.text.contains("PID 71"),
		"details identify the visual species and process PID"
	)
	var metrics_label := main.get("_details_metrics_label") as Label
	_check(
		metrics_label.text.contains("CPU 12.5%")
		and metrics_label.text.contains("RAM 3.0 MiB"),
		"panel shows current CPU and RAM values"
	)
	var second_click := point_to_viewport * second.get_visual_center_position()
	await _send_left_click(second_click)
	_check(
		metrics_label.text.contains("CPU —") and metrics_label.text.contains("RAM 0.0 MiB"),
		"null CPU stays unavailable in the observation card"
	)
	await _send_left_click(first_click)
	var panel_click := details_panel.get_global_rect().get_center()
	await _send_left_click(panel_click)
	_check(
		not main.call("route_pointer_click", panel_click),
		"click inside the details panel does not pass through to the garden"
	)
	_check(garden.get_selected_identity() == identities[0], "panel click preserves selection")
	garden.position = Vector2(8.0, 6.0)
	garden.scale = Vector2(1.25, 1.25)
	var resized_click := garden.get_global_transform_with_canvas() * second.get_visual_center_position()
	await _send_left_click(resized_click)
	_check(
		garden.get_selected_identity() == identities[1],
		"click coordinate conversion follows scaled and repositioned garden transforms"
	)
	garden.position = Vector2.ZERO
	garden.scale = Vector2.ONE
	await _send_left_click(first_click)

	var refreshed := _proc(71, 20.0, 54.0, 6_291_456)
	garden.reconcile_processes([refreshed, records[1]])
	main.call("_refresh_details")
	_check(
		metrics_label.text.contains("CPU 54.0%")
		and metrics_label.text.contains("RAM 6.0 MiB"),
		"selected details follow updated process metrics"
	)
	var selected_creature := garden.get_selected_creature()
	var selected_is_valid := is_instance_valid(selected_creature)
	_check(selected_is_valid, "selected identity resolves to a creature after metrics update")
	if selected_is_valid:
		_check(
			selected_creature.species == SpriteLibrary.Species.BEETLE,
			"metrics-update hit-test fixture exercises a supported Beetle habitat"
		)
		var initial_ram_scale := selected_creature.get_ram_scale()
		var ram_scale_responded := false
		for _frame in range(30):
			if not is_instance_valid(selected_creature):
				break
			await process_frame
			if not is_instance_valid(selected_creature):
				break
			if not is_equal_approx(selected_creature.get_ram_scale(), initial_ram_scale):
				ram_scale_responded = true
				break
		_check(ram_scale_responded, "RAM scale responds to the updated process metrics")
		selected_is_valid = is_instance_valid(selected_creature) and selected_creature.is_inside_tree()
		_check(selected_is_valid, "selected creature remains present while RAM scale responds to updated metrics")
		if selected_is_valid:
			var visual_center_in_parent := selected_creature.get_visual_center_position()
			var parent_node := selected_creature.get_parent() as Node2D
			var visual_center_in_global := parent_node.to_global(visual_center_in_parent)
			var visual_center_in_creature := selected_creature.to_local(visual_center_in_global)
			_check(
				selected_creature.contains_local_point(visual_center_in_creature),
				"selected creature remains hit-testable at its rendered body after metrics update"
			)
			var visual_center_in_garden := garden.to_local(visual_center_in_global)
			_check(
				garden.select_at(visual_center_in_garden) == identities[0],
				"updated creature remains selectable through the garden hit-test"
			)
	var registry: ProcessRegistry = main.get("_registry")
	registry.connection_state = ProcessRegistry.STATE_DISCONNECTED
	main.call("_refresh_details")
	var state_label := main.get("_details_state_label") as Label
	_check(
		state_label.text.contains("OFFLINE") and state_label.text.contains("LAST VALID METRICS"),
		"offline panel marks metrics as stale"
	)
	var selected_identity := garden.get_selected_identity()
	registry.connection_state = ProcessRegistry.STATE_CONNECTED
	main.call("_refresh_details")
	_check(
		garden.get_selected_identity() == selected_identity
		and state_label.text.contains("LIVE"),
		"reconnection keeps selection and returns the detail status to live"
	)
	var close_button := details_panel.find_child("CloseDetails", true, false) as Button
	_check(
		close_button.focus_mode == Control.FOCUS_ALL,
		"details close control can receive keyboard focus"
	)
	await _send_left_click(close_button.get_global_rect().get_center())
	_check(garden.get_selected_identity().is_empty(), "details close button receives real GUI input")
	_check(not details_panel.visible, "closing details does not select a creature behind the panel")
	var empty_click := point_to_viewport * Vector2(10.0, 330.0)
	await _send_left_click(empty_click)
	_check(garden.get_selected_identity().is_empty(), "empty garden click clears selection")
	_check(not details_panel.visible, "clearing selection hides the details panel")
	main.call("_on_close_details_pressed")
	main.queue_free()
	await process_frame


func _test_observatory_ui_states_and_demo_controls() -> void:
	var main := MainScene.instantiate() as Control
	var client := main.get_node("SnapshotClient") as SnapshotClient
	client.set_polling_enabled(false)
	root.add_child(main)
	await process_frame
	var registry := main.get("_registry") as ProcessRegistry
	var status_label := main.get("_status_label") as Label
	var counts_label := main.get("_counts_label") as Label
	var message_label := main.get("_error_label") as Label
	var empty_label := main.get("_empty_state_label") as Label
	var demo_controls := main.get("_demo_controls") as HBoxContainer
	_check(
		status_label.text.contains("CONNECTING") and empty_label.visible,
		"REAL startup communicates the connecting and empty-garden states"
	)
	_check(not demo_controls.visible, "DEMO-only scenario controls stay hidden in REAL mode")

	var valid := Parser.validate_data(
		_snapshot(1, Time.get_unix_time_from_system(), "ok", [_proc(91, 10.0, null, 0)])
	)
	main.call("_on_snapshot_received", valid["snapshot"])
	_check(status_label.text.contains("CONNECTED"), "valid REAL snapshot updates the status to connected")
	_check(counts_label.text.contains("1 monitored"), "REAL header reports the monitored process count")
	_check(not empty_label.visible, "a represented process hides the empty-garden message")

	registry._snapshot_age_at_receipt = 6.5
	registry._last_new_snapshot_ticks_msec = Time.get_ticks_msec()
	main.call("_refresh_status")
	_check(
		status_label.text.contains("STALE") and message_label.text.contains("last valid data"),
		"STALE status explains that the last valid snapshot remains visible"
	)
	registry._snapshot_age_at_receipt = 16.0
	registry._last_new_snapshot_ticks_msec = Time.get_ticks_msec()
	main.call("_refresh_status")
	_check(
		status_label.text.contains("DISCONNECTED")
		and message_label.text.contains("retrying automatically"),
		"DISCONNECTED status communicates automatic recovery"
	)

	main.call("set_source_mode", "DEMO")
	_check(demo_controls.visible, "DEMO scenario and seed controls appear only in DEMO mode")
	_check(
		status_label.text.contains("DEMO · SIMULATED") and counts_label.text.contains("simulated"),
		"DEMO mode labels synthetic metrics and process counts explicitly"
	)
	_check(message_label.text.is_empty(), "DEMO mode clears REAL collector availability messages")
	main.call("set_source_mode", "REAL")
	_check(not demo_controls.visible, "returning to REAL hides DEMO-only controls")
	_check(empty_label.visible, "source reset restores the empty-garden message")
	main.queue_free()
	await process_frame


func _test_demo_snapshot_source() -> void:
	var source := DemoSnapshotSourceScript.new() as DemoSnapshotSource
	root.add_child(source)
	var snapshots: Array[Dictionary] = []
	source.snapshot_generated.connect(func(snapshot: Dictionary): snapshots.append(snapshot))
	source.interval_seconds = 3600.0
	source.configure(50, 4242)
	source.start()
	_check(snapshots.size() == 1, "demo source emits an initial snapshot when started")
	if snapshots.is_empty():
		_check(false, "demo source produces a snapshot fixture")
		source.stop()
		source.queue_free()
		await process_frame
		return
	var initial: Dictionary = snapshots[0]
	var parsed := Parser.validate_data(initial)
	_check(parsed["ok"], "demo source snapshot matches the existing JSON contract")
	_check(initial["processes"].size() == 50, "50-process scenario starts with 50 records")
	var original_processes: Array = initial["processes"].duplicate(true)
	source.advance_one_step()
	if snapshots.size() < 2:
		_check(false, "demo source emits the next process sample")
		source.stop()
		source.queue_free()
		await process_frame
		return
	var after_birth: Dictionary = snapshots[1]
	_check(after_birth["sequence"] == 2, "demo sequence increments for the next sample")
	_check(after_birth["processes"].size() == 51, "demo lifecycle creates a process")
	var initial_by_identity := _processes_by_identity(original_processes)
	var after_birth_by_identity := _processes_by_identity(after_birth["processes"])
	var new_identity := ""
	for identity in after_birth_by_identity:
		if not initial_by_identity.has(identity):
			new_identity = str(identity)
	_check(not new_identity.is_empty(), "new demo process receives a new logical identity")
	var stable_identity := str(initial_by_identity.keys()[0])
	var initial_stable: Dictionary = initial_by_identity[stable_identity]
	var updated_stable: Dictionary = after_birth_by_identity[stable_identity]
	_check(
		initial_stable["cpu_percent"] != updated_stable["cpu_percent"]
		or initial_stable["memory_rss_bytes"] != updated_stable["memory_rss_bytes"],
		"demo snapshots change CPU or RAM metrics over time"
	)
	source.advance_one_step()
	source.advance_one_step()
	if snapshots.size() < 4:
		_check(false, "demo source emits the process exit sample")
		source.stop()
		source.queue_free()
		await process_frame
		return
	var after_exit: Dictionary = snapshots[3]
	_check(after_exit["processes"].size() == 50, "demo lifecycle ends a process")
	var after_exit_by_identity := _processes_by_identity(after_exit["processes"])
	_check(
		after_exit_by_identity.has(new_identity),
		"newly spawned identity remains active when an existing process ends"
	)
	var ended_process: Dictionary = {}
	var ended_identity := ""
	for identity in after_birth_by_identity:
		if not after_exit_by_identity.has(identity):
			ended_identity = str(identity)
			ended_process = after_birth_by_identity[identity]
	_check(not ended_process.is_empty(), "demo snapshot identifies the ended process")
	_check(
		not after_exit_by_identity.has(ended_identity),
		"ended identity is absent from the complete snapshot"
	)
	source.advance_one_step()
	source.advance_one_step()
	if snapshots.size() < 6:
		_check(false, "demo source emits the PID reuse sample")
		source.stop()
		source.queue_free()
		await process_frame
		return
	var after_pid_reuse: Dictionary = snapshots[5]
	var reused_pid_found := false
	for process in after_pid_reuse["processes"]:
		if int(process["pid"]) == int(ended_process.get("pid", -1)):
			reused_pid_found = float(process["create_time"]) != float(ended_process["create_time"])
	_check(reused_pid_found, "reused demo PID receives a different create_time")
	_check(_demo_scenarios_have_expected_sizes(), "all supported scenarios have the requested population")
	var duplicate := DemoSnapshotSourceScript.new() as DemoSnapshotSource
	root.add_child(duplicate)
	var duplicate_snapshots: Array[Dictionary] = []
	duplicate.snapshot_generated.connect(func(snapshot: Dictionary): duplicate_snapshots.append(snapshot))
	duplicate.interval_seconds = 3600.0
	duplicate.configure(50, 4242)
	duplicate.start()
	if duplicate_snapshots.is_empty():
		_check(false, "same-seed demo source emits its initial fixture")
		source.stop()
		duplicate.stop()
		source.queue_free()
		duplicate.queue_free()
		await process_frame
		return
	_check(
		JSON.stringify(duplicate_snapshots[0]["processes"])
		== JSON.stringify(initial["processes"]),
		"same demo seed reproduces process identities and initial metrics"
	)
	var alternate_seed := DemoSnapshotSourceScript.new() as DemoSnapshotSource
	root.add_child(alternate_seed)
	var alternate_snapshots: Array[Dictionary] = []
	alternate_seed.snapshot_generated.connect(func(snapshot: Dictionary): alternate_snapshots.append(snapshot))
	alternate_seed.interval_seconds = 3600.0
	alternate_seed.configure(50, 4243)
	alternate_seed.start()
	if alternate_snapshots.is_empty():
		_check(false, "alternate-seed demo source emits its initial fixture")
		source.stop()
		duplicate.stop()
		alternate_seed.stop()
		source.queue_free()
		duplicate.queue_free()
		alternate_seed.queue_free()
		await process_frame
		return
	_check(
		JSON.stringify(alternate_snapshots[0]["processes"])
		!= JSON.stringify(initial["processes"]),
		"changing the demo seed changes the reproducible process data"
	)
	source.stop()
	duplicate.stop()
	alternate_seed.stop()
	source.queue_free()
	duplicate.queue_free()
	alternate_seed.queue_free()
	await process_frame


func _processes_by_identity(processes: Array) -> Dictionary:
	var result := {}
	for process in processes:
		result[Parser.identity_key(process)] = process
	return result


func _demo_scenarios_have_expected_sizes() -> bool:
	for population in [50, 150, 300, 500]:
		var source := DemoSnapshotSourceScript.new() as DemoSnapshotSource
		root.add_child(source)
		var snapshots: Array[Dictionary] = []
		source.snapshot_generated.connect(func(snapshot: Dictionary): snapshots.append(snapshot))
		source.interval_seconds = 3600.0
		source.configure(population, 1)
		source.start()
		var valid_size: bool = (
			snapshots.size() == 1 and snapshots[0]["processes"].size() == population
		)
		source.stop()
		source.queue_free()
		if not valid_size:
			return false
	return true


func _test_demo_mode_switching() -> void:
	var main := MainScene.instantiate() as Control
	var client := main.get_node("SnapshotClient") as SnapshotClient
	client.endpoint_url = "http://127.0.0.1:0/v1/snapshot"
	root.add_child(main)
	await process_frame
	var garden := main.get_node("Garden") as GardenController
	var mode_option := main.find_child("SourceMode", true, false) as OptionButton
	mode_option.select(1)
	mode_option.item_selected.emit(1)
	var demo_source := main.get("_demo_source") as DemoSnapshotSource
	demo_source.stop()
	demo_source.interval_seconds = 3600.0
	demo_source.start()
	var scenario_option := main.find_child("DemoScenario", true, false) as OptionButton
	scenario_option.select(2)
	scenario_option.item_selected.emit(2)
	_check(
		(main.get("_registry") as ProcessRegistry).get_tracked_count() == 300,
		"demo scenario selector restarts with the selected population"
	)
	_check(
		garden.get_creature_count() == 30,
		"300-process demo remains fully tracked while representation stays capped at 30"
	)
	var counts_label := main.get("_counts_label") as Label
	_check(
		counts_label.text == "300 simulated · 30 represented",
		"300-process demo HUD reports monitored and represented counts separately"
	)
	for scenario_index in [0, 3]:
		scenario_option.select(scenario_index)
		scenario_option.item_selected.emit(scenario_index)
		var expected_population := 50 if scenario_index == 0 else 500
		var scenario_registry := main.get("_registry") as ProcessRegistry
		_check(
			scenario_registry.get_tracked_count() == expected_population
			and garden.get_creature_count() == 30,
			"%d-process demo tracks every process and represents 30" % expected_population
		)
		_check(
			counts_label.text == "%d simulated · 30 represented" % expected_population,
			"%d-process demo HUD preserves full monitored count" % expected_population
		)
	scenario_option.select(1)
	scenario_option.item_selected.emit(1)
	var seed_input := main.find_child("DemoSeed", true, false) as SpinBox
	seed_input.value = 4242.0
	var demo_registry: ProcessRegistry = main.get("_registry")
	var demo_records := demo_registry.get_records()
	_check(main.get("_source_mode") == "DEMO", "DEMO can be selected explicitly")
	var status_label := main.get("_status_label") as Label
	_check(status_label.text.contains("DEMO · SIMULATED"), "header clearly marks simulated data")
	_check(demo_registry.get_tracked_count() == 150, "demo feeds its snapshot through ProcessRegistry")
	_check(garden.get_creature_count() == 30, "150-process demo represents exactly the 30-creature cap")
	_check(
		counts_label.text == "150 simulated · 30 represented",
		"demo HUD distinguishes the complete monitored population from the visual limit"
	)
	if demo_records.is_empty():
		_check(false, "demo mode provides synthetic process records")
		main.queue_free()
		await process_frame
		return
	_check(
		str(demo_records[0]["name"]).begins_with("demo-"),
		"demo mode is visibly backed by synthetic process names"
	)
	var demo_identity: String = Parser.identity_key(demo_records[0])
	mode_option.select(0)
	mode_option.item_selected.emit(0)
	var real_registry: ProcessRegistry = main.get("_registry")
	_check(main.get("_source_mode") == "REAL", "REAL can be selected explicitly")
	_check(real_registry.get_tracked_count() == 0, "switching sources clears the previous registry")
	_check(garden.get_creature_count() == 0, "switching sources clears old creature identities immediately")
	var real_process := _proc(int(demo_records[0]["pid"]), float(demo_records[0]["create_time"]), 0.0)
	var accepted := Parser.validate_data(_snapshot(1, Time.get_unix_time_from_system(), "ok", [real_process]))
	main.call("_on_snapshot_received", accepted["snapshot"])
	_check(real_registry.get_tracked_count() == 1, "real snapshot enters the fresh registry")
	var creature_after_source_change := garden.get_creature(demo_identity)
	_check(
		creature_after_source_change == null
		or creature_after_source_change.process_name == real_process["name"],
		"same PID and create_time cannot retain a demo creature across sources"
	)
	main.call("_on_request_failed", "transport", "benchmark_disconnect_fixture")
	var disconnected_registry: ProcessRegistry = main.get("_registry")
	_check(
		disconnected_registry.get_tracked_count() == 1 and garden.get_creature_count() == 1,
		"API loss preserves the last valid registry and creature"
	)
	var recovered := Parser.validate_data(
		_snapshot(2, Time.get_unix_time_from_system(), "ok", [real_process])
	)
	main.call("_on_snapshot_received", recovered["snapshot"])
	_check(
		disconnected_registry.connection_state == ProcessRegistry.STATE_CONNECTED
		and garden.get_creature_count() == 1,
		"a fresh API sample recovers without duplicating the creature"
	)
	mode_option.select(1)
	mode_option.item_selected.emit(1)
	var switched_back_registry: ProcessRegistry = main.get("_registry")
	_check(
		switched_back_registry.get_tracked_count() == 150,
		"switching back to demo starts a fresh deterministic source"
	)
	var maximum_creatures := garden.get_creature_count()
	for cycle in range(20):
		mode_option.select(0)
		mode_option.item_selected.emit(0)
		await process_frame
		var cleared_registry: ProcessRegistry = main.get("_registry")
		_check(
			cleared_registry.get_tracked_count() == 0 and garden.get_creature_count() == 0,
			"source switch %d clears prior process identities" % cycle
		)
		mode_option.select(1)
		mode_option.item_selected.emit(1)
		await process_frame
		var active_registry: ProcessRegistry = main.get("_registry")
		maximum_creatures = maxi(maximum_creatures, garden.get_creature_count())
		_check(
			active_registry.get_tracked_count() == 150 and garden.get_creature_count() <= 30,
			"source switch %d restores demo within the creature limit" % cycle
		)
	_check(maximum_creatures <= 30, "repeated source changes never exceed the 30-creature visual limit")
	mode_option.select(0)
	mode_option.item_selected.emit(0)
	main.queue_free()
	await process_frame


func _wait_for_spawn_completion(creature: ProcessCreature) -> bool:
	# Observe the actual lifecycle state instead of assuming a wall-clock delay.
	# The frame bound turns a broken or stalled tween into a normal test failure.
	for _frame in range(120):
		if not is_instance_valid(creature) or not creature.is_inside_tree():
			return false
		if creature.state != ProcessCreature.State.SPAWNING:
			return (
				creature.state != ProcessCreature.State.DESPAWNING
				and creature.is_visible_in_tree()
			)
		await process_frame
	return false


func _send_left_click(viewport_position: Vector2) -> void:
	# Injected mouse events use window coordinates; callbacks receive viewport coordinates.
	var screen_position := root.get_screen_transform() * viewport_position
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = screen_position
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await process_frame


func _check_position_in_bounds(creature: ProcessCreature, description: String) -> void:
	var bounds := creature.get_effective_movement_bounds()
	_check(_point_is_within_bounds(creature.position, bounds), description)


func _point_is_within_bounds(point: Vector2, bounds: Rect2) -> bool:
	return (
		point.x >= bounds.position.x
		and point.x <= bounds.end.x
		and point.y >= bounds.position.y
		and point.y <= bounds.end.y
	)


func _test_add_persist_remove_and_pid_reuse() -> void:
	var registry := Registry.new()
	var first := _validated(_snapshot(1, 1000.0, "ok", [_proc(22, 5.0, null)]))
	var added: Dictionary = registry.accept_snapshot(first, 1001.0, 1000)
	_check(added["accepted"] and added["events"]["added"].size() == 1, "new process added")
	var persisted_snapshot := _validated(_snapshot(2, 1002.0, "ok", [_proc(22, 5.0, 0.0)]))
	var persisted: Dictionary = registry.accept_snapshot(persisted_snapshot, 1003.0, 3000)
	_check(persisted["events"]["persisted"].size() == 1, "same identity persisted")
	var reused_snapshot := _validated(_snapshot(3, 1004.0, "ok", [_proc(22, 6.0, null)]))
	var reused: Dictionary = registry.accept_snapshot(reused_snapshot, 1005.0, 5000)
	_check(reused["events"]["added"].size() == 1, "reused PID is a new identity")
	_check(reused["events"]["removed"].size() == 1, "old PID identity removed")
	var empty_snapshot := _validated(_snapshot(4, 1006.0, "ok", []))
	var removed: Dictionary = registry.accept_snapshot(empty_snapshot, 1007.0, 7000)
	_check(removed["events"]["removed"].size() == 1, "missing process removed from complete snapshot")


func _test_repeat_and_partial_preserve_processes() -> void:
	var registry := Registry.new()
	var first := _validated(_snapshot(1, 2000.0, "ok", [_proc(9, 4.0, null)]))
	registry.accept_snapshot(first, 2001.0, 1000)
	var repeated := registry.accept_snapshot(first, 2004.0, 4000)
	_check(not repeated["accepted"] and repeated["reason"] == "repeated", "repeated snapshot ignored")
	_check(registry.get_tracked_count() == 1, "repeat does not reconcile twice")
	var partial := _validated(_snapshot(2, 2005.0, "partial", []))
	var partial_result := registry.accept_snapshot(partial, 2006.0, 6000)
	_check(partial_result["events"]["removed"].is_empty(), "partial snapshot does not remove absent process")
	_check(registry.get_tracked_count() == 1, "partial snapshot preserves missing process")
	var older := _validated(_snapshot(1, 2003.0, "ok", []))
	var older_result := registry.accept_snapshot(older, 2007.0, 7000)
	_check(not older_result["accepted"], "older snapshot rejected")
	_check(registry.get_tracked_count() == 1, "older snapshot leaves registry unchanged")


func _test_restart_and_freshness() -> void:
	var registry := Registry.new(6.0, 15.0)
	var first := _validated(_snapshot(8, 3000.0, "ok", [_proc(28, 5.0, 2.0)]))
	registry.accept_snapshot(first, 3001.0, 1000)
	var restarted := _validated(_snapshot(1, 3002.0, "ok", [_proc(28, 5.0, 2.0)]))
	var restart_result := registry.accept_snapshot(restarted, 3003.0, 3000)
	_check(restart_result["accepted"] and restart_result["restarted"], "sequence reset with newer time detects restart")
	registry.update_connection_state(3009.0, 9000)
	_check(registry.connection_state == Registry.STATE_STALE, "freshness becomes stale")
	_check(registry.get_tracked_count() == 1, "stale data remains in the process registry")
	registry.update_connection_state(3018.0, 18000)
	_check(registry.connection_state == Registry.STATE_DISCONNECTED, "freshness becomes disconnected")
	_check(registry.get_tracked_count() == 1, "disconnection does not remove the last process snapshot")


func _snapshot(sequence: int, collected_unix: float, status: String, processes: Array) -> Dictionary:
	var utc := Time.get_datetime_dict_from_unix_time(int(collected_unix))
	return {
		"schema_version": 1,
		"sequence": sequence,
		"collected_at": "%04d-%02d-%02dT%02d:%02d:%02dZ" % [utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second],
		"interval_ms": 2000,
		"status": status,
		"processes": processes,
		"skipped_count": 1 if status == "partial" else 0,
		"_collected_at_unix": collected_unix,
	}


func _proc(pid: int, create_time: float, cpu: Variant, memory: int = 1024) -> Dictionary:
	return {
		"pid": pid,
		"create_time": create_time,
		"name": "worker",
		"cpu_percent": cpu,
		"memory_rss_bytes": memory,
	}


func _validated(snapshot: Dictionary) -> Dictionary:
	var result: Dictionary = Parser.validate_data(snapshot)
	if not result["ok"]:
		push_error("Test fixture must satisfy parser: %s" % result.get("error", ""))
		_failed += 1
	return result["snapshot"]


func _check(condition: bool, description: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		push_error(description)
