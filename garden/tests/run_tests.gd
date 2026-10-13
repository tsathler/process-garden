extends SceneTree

const Parser = preload("res://scripts/snapshot_parser.gd")
const Registry = preload("res://scripts/process_registry.gd")
const Selector = preload("res://scripts/process_selector.gd")
const GardenControllerScript = preload("res://scripts/garden_controller.gd")
const DemoSnapshotSourceScript = preload("res://scripts/demo_snapshot_source.gd")
const CreatureScene: PackedScene = preload("res://scenes/creature.tscn")
const MainScene: PackedScene = preload("res://scenes/main.tscn")

var _passed := 0
var _failed := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_valid_snapshot_and_null_cpu()
	_test_invalid_json_and_contract()
	_test_timestamp_calendar_validation()
	_test_duplicate_identity_and_negative_metric()
	_test_pid_zero_regression()
	_test_process_selection()
	await _test_garden_controller_reconciliation()
	await _test_creature_behavior_and_lifecycle()
	await _test_despawn_reuse_and_capacity()
	_test_separation_and_click_selection()
	await _test_click_routing_and_process_details()
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


func _test_process_selection() -> void:
	var selector := Selector.new()
	var under_limit: Array[Dictionary] = [_proc(3, 1.0, 0.0), _proc(1, 1.0, 0.0)]
	var under_result: Array[Dictionary] = selector.select_processes(under_limit, [], 60)
	_check(under_result.size() == 2, "selection keeps all candidates under limit")

	var many: Array[Dictionary] = []
	for pid in range(75):
		many.append(_proc(pid + 1, 1000.0 + pid, float(pid % 10), 1024 + pid))
	var selected := selector.select_processes(many, [], 60)
	_check(selected.size() == 60, "selection enforces configured limit")
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
	controller.select_at(original_creature.position)
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
	_check(controller.select_at(first.position) == identities[0], "click hit test selects a creature")
	_check(first.is_selected, "selected creature receives visual highlight state")
	_check(controller.select_at(second.position) == identities[1], "clicking another creature changes selection")
	_check(not first.is_selected and second.is_selected, "highlight moves to the new selection")
	_check(controller.select_at(Vector2.ZERO).is_empty(), "empty-space click clears selection")

	first._visual.position = Vector2(0.0, 2.0)
	first._visual.scale = Vector2.ONE
	_check(
		not first.contains_local_point(Vector2(14.0, 2.0)),
		"base-scale click area excludes points beyond the body"
	)
	first._visual.scale = Vector2(1.35, 1.35)
	_check(
		first.contains_local_point(Vector2(14.0, 2.0)),
		"larger visual scale expands the click area"
	)
	first._visual.scale = Vector2.ONE
	first._visual.position = Vector2.ZERO

	first.position = Vector2(320.0, 210.0)
	second.position = first.position
	third.position = Vector2(500.0, 210.0)
	var visually_upper := first if first.get_index() > second.get_index() else second
	_check(
		controller.select_at(first.position) == visually_upper.process_identity,
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
	var records: Array[Dictionary] = [
		_proc(71, 20.0, 12.5, 3_145_728), _proc(72, 21.0, null, 0)
	]
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
	var first_click := point_to_viewport * first.position
	await _send_left_click(first_click)
	_check(garden.get_selected_identity() == identities[0], "viewport coordinates select the expected identity")
	_check(main.mouse_filter == Control.MOUSE_FILTER_IGNORE, "full-screen root does not consume pointer input")
	var details_panel := main.get_node("ProcessDetails") as Control
	_check(details_panel.visible, "selecting a creature opens the details panel")
	var metrics_label := main.get("_details_metrics_label") as Label
	_check(
		metrics_label.text.contains("CPU 12.5%")
		and metrics_label.text.contains("RAM 3.0 MiB"),
		"panel shows current CPU and RAM values"
	)
	var panel_click := details_panel.get_global_rect().get_center()
	await _send_left_click(panel_click)
	_check(
		not main.call("route_pointer_click", panel_click),
		"click inside the details panel does not pass through to the garden"
	)
	_check(garden.get_selected_identity() == identities[0], "panel click preserves selection")
	garden.position = Vector2(8.0, 6.0)
	garden.scale = Vector2(1.25, 1.25)
	var resized_click := garden.get_global_transform_with_canvas() * second.position
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
		_check(selected_creature.contains_local_point(Vector2.ZERO), "selected creature remains hit-testable after metrics update")
	var registry: ProcessRegistry = main.get("_registry")
	registry.connection_state = ProcessRegistry.STATE_DISCONNECTED
	main.call("_refresh_details")
	var state_label := main.get("_details_state_label") as Label
	_check(state_label.text.contains("OFFLINE") and state_label.text.contains("last valid"), "offline panel marks metrics as stale")
	var selected_identity := garden.get_selected_identity()
	registry.connection_state = ProcessRegistry.STATE_CONNECTED
	main.call("_refresh_details")
	_check(
		garden.get_selected_identity() == selected_identity
		and state_label.text.contains("LIVE"),
		"reconnection keeps selection and returns the detail status to live"
	)
	var close_button := details_panel.find_child("CloseDetails", true, false) as Button
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
	_check(garden.get_creature_count() <= 60, "demo preserves the garden creature limit")
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
	mode_option.select(1)
	mode_option.item_selected.emit(1)
	var switched_back_registry: ProcessRegistry = main.get("_registry")
	_check(
		switched_back_registry.get_tracked_count() == 150,
		"switching back to demo starts a fresh deterministic source"
	)
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
	var first := _validated(_snapshot(8, 3000.0, "ok", []))
	registry.accept_snapshot(first, 3001.0, 1000)
	var restarted := _validated(_snapshot(1, 3002.0, "ok", []))
	var restart_result := registry.accept_snapshot(restarted, 3003.0, 3000)
	_check(restart_result["accepted"] and restart_result["restarted"], "sequence reset with newer time detects restart")
	registry.update_connection_state(3009.0, 9000)
	_check(registry.connection_state == Registry.STATE_STALE, "freshness becomes stale")
	registry.update_connection_state(3018.0, 18000)
	_check(registry.connection_state == Registry.STATE_DISCONNECTED, "freshness becomes disconnected")


func _snapshot(sequence: int, collected_unix: float, status: String, processes: Array) -> Dictionary:
	var utc := Time.get_datetime_dict_from_unix_time(int(collected_unix))
	return {
		"schema_version": 1,
		"sequence": sequence,
		"collected_at": "%04d-%02d-%02dT%02d:%02d:%02dZ" % [utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second],
		"interval_ms": 2000,
		"status": status,
		"processes": processes,
		"skipped_count": 0,
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
