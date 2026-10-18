extends SceneTree

const DemoSnapshotSourceScript = preload("res://scripts/demo_snapshot_source.gd")
const EnvironmentScene: PackedScene = preload("res://scenes/environment.tscn")
const GardenControllerScript = preload("res://scripts/garden_controller.gd")
const RegistryScript = preload("res://scripts/process_registry.gd")
const SnapshotParserScript = preload("res://scripts/snapshot_parser.gd")

const DEFAULT_SCENARIOS: Array[int] = [50, 150, 300, 500]
const DEFAULT_DURATION_SECONDS := 30.0
const DEFAULT_WARMUP_SECONDS := 5.0
const DEFAULT_SEED := 2025
const DEMO_SAMPLE_INTERVAL_SECONDS := 2.0

var _duration_seconds := DEFAULT_DURATION_SECONDS
var _warmup_seconds := DEFAULT_WARMUP_SECONDS
var _seed_value := DEFAULT_SEED
var _renderer_mode := ProcessCreature.RENDERER_LEGACY
var _scenarios: Array[int] = []
var _benchmark_root: Node2D
var _garden: GardenController
var _source: DemoSnapshotSource
var _registry: ProcessRegistry
var _measuring := false
var _next_source_tick_usec := 0
var _frame_deltas_ms: Array[float] = []
var _engine_frame_ms: Array[float] = []
var _rolling_fps: Array[float] = []
var _static_memory_bytes: Array[float] = []
var _node_counts: Array[float] = []
var _orphan_counts: Array[float] = []
var _creature_counts: Array[float] = []
var _tracked_counts: Array[float] = []
var _snapshot_pipeline_ms: Array[float] = []
var _callback_total_ms: Array[float] = []
var _json_encode_ms: Array[float] = []
var _json_parse_ms: Array[float] = []
var _demo_tick_ms: Array[float] = []
var _metric_update_ms: Array[float] = []
var _lifecycle_update_ms: Array[float] = []
var _source_copy_ms: Array[float] = []
var _contract_validation_ms: Array[float] = []
var _registry_ms: Array[float] = []
var _registry_records_ms: Array[float] = []
var _garden_copy_ms: Array[float] = []
var _selector_ms: Array[float] = []
var _creature_reconcile_ms: Array[float] = []
var _frame_with_tick_ms: Array[float] = []
var _frame_without_tick_ms: Array[float] = []
var _engine_frame_with_tick_ms: Array[float] = []
var _engine_frame_without_tick_ms: Array[float] = []
var _snapshot_count := 0
var _invalid_snapshot_count := 0
var _csv_path := ""


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if not _read_arguments():
		quit(2)
		return
	Engine.max_fps = 60
	if _scenarios.is_empty():
		for population in DEFAULT_SCENARIOS:
			_scenarios.append(population)
	if not _create_harness():
		quit(1)
		return
	var run_stamp := Time.get_datetime_string_from_system(true).replace(":", "-")
	_csv_path = "user://process_garden_e03_2_%s_%d.csv" % [run_stamp, Time.get_ticks_usec()]
	var output := FileAccess.open(_csv_path, FileAccess.WRITE)
	if output == null:
		push_error("Could not open benchmark output: %s" % error_string(FileAccess.get_open_error()))
		quit(1)
		return
	output.store_line(_csv_header())
	print("Process Garden benchmark · Godot %s · %s · %s" % [
		str(Engine.get_version_info().get("string", "unknown")), OS.get_name(), _renderer_mode
	])
	print(_csv_header())
	for population in _scenarios:
		await _run_scenario(population, output)
	_source.stop()
	_garden.clear_for_source_change()
	await process_frame
	output.close()
	print("CSV saved at: %s" % ProjectSettings.globalize_path(_csv_path))
	quit(0)


func _read_arguments() -> bool:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--duration-seconds="):
			_duration_seconds = argument.trim_prefix("--duration-seconds=").to_float()
		elif argument.begins_with("--warmup-seconds="):
			_warmup_seconds = argument.trim_prefix("--warmup-seconds=").to_float()
		elif argument.begins_with("--seed="):
			_seed_value = int(argument.trim_prefix("--seed="))
		elif argument.begins_with("--renderer="):
			_renderer_mode = argument.trim_prefix("--renderer=").to_lower()
			if (
				_renderer_mode != ProcessCreature.RENDERER_LEGACY
				and _renderer_mode != ProcessCreature.RENDERER_COZY_MYSTIC
				and _renderer_mode != ProcessCreature.RENDERER_SYNTHETIC_LIFE
			):
				push_error("Unsupported visual renderer: %s" % _renderer_mode)
				return false
		elif argument.begins_with("--scenario="):
			var requested := int(argument.trim_prefix("--scenario="))
			if not DEFAULT_SCENARIOS.has(requested):
				push_error("Unsupported scenario: %d" % requested)
				return false
			_scenarios.append(requested)
		else:
			push_error("Unknown benchmark argument: %s" % argument)
			return false
	if _duration_seconds < 1.0 or _warmup_seconds < 0.0:
		push_error("Duration must be at least 1 second and warmup cannot be negative.")
		return false
	return true


func _create_harness() -> bool:
	_benchmark_root = Node2D.new()
	_benchmark_root.name = "ProcessGardenBenchmark"
	root.add_child(_benchmark_root)
	_benchmark_root.add_child(EnvironmentScene.instantiate())
	_garden = GardenControllerScript.new() as GardenController
	if _garden == null:
		push_error("Could not instantiate GardenController.")
		return false
	var creature_layer := Node2D.new()
	creature_layer.name = "Creatures"
	_garden.add_child(creature_layer)
	_garden.profiling_enabled = true
	if not _garden.set_visual_renderer(_renderer_mode):
		push_error("Could not enable benchmark visual renderer: %s" % _renderer_mode)
		return false
	_benchmark_root.add_child(_garden)
	_source = DemoSnapshotSourceScript.new() as DemoSnapshotSource
	if _source == null:
		push_error("Could not instantiate DemoSnapshotSource.")
		return false
	_source.name = "BenchmarkDemoSource"
	_source.interval_seconds = 3600.0
	_source.profiling_enabled = true
	_source.snapshot_generated.connect(_on_snapshot_generated)
	_benchmark_root.add_child(_source)
	return true


func _run_scenario(population: int, output: FileAccess) -> void:
	print("Preparing scenario %d (seed %d)..." % [population, _seed_value])
	_source.stop()
	_garden.clear_for_source_change()
	await process_frame
	_registry = RegistryScript.new() as ProcessRegistry
	_source.configure(population, _seed_value)
	_source.start()
	await _observe_for(_warmup_seconds, false)
	_clear_samples()
	_measuring = true
	_next_source_tick_usec = Time.get_ticks_usec() + int(DEMO_SAMPLE_INTERVAL_SECONDS * 1_000_000.0)
	await _observe_for(_duration_seconds, true)
	_measuring = false
	var row := _result_row(population)
	output.store_line(row)
	output.flush()
	print(row)


func _observe_for(duration_seconds: float, collect: bool) -> void:
	var start_usec := Time.get_ticks_usec()
	var end_usec := start_usec + int(duration_seconds * 1_000_000.0)
	var previous_frame_usec := start_usec
	var previous_frame_had_tick := false
	while Time.get_ticks_usec() < end_usec:
		await process_frame
		var now_usec := Time.get_ticks_usec()
		if collect:
			_collect_frame(now_usec - previous_frame_usec, previous_frame_had_tick)
			previous_frame_had_tick = false
			if now_usec >= _next_source_tick_usec:
				var pipeline_start_usec := Time.get_ticks_usec()
				_source.advance_one_step()
				_demo_tick_ms.append(
					float(Time.get_ticks_usec() - pipeline_start_usec) / 1000.0
				)
				_record_demo_source_stages(_source.get_last_profile_usec())
				previous_frame_had_tick = true
				_next_source_tick_usec = now_usec + int(
					DEMO_SAMPLE_INTERVAL_SECONDS * 1_000_000.0
				)
		previous_frame_usec = now_usec


func _collect_frame(frame_elapsed_usec: int, included_source_tick: bool) -> void:
	if frame_elapsed_usec <= 0:
		return
	var frame_elapsed_ms := float(frame_elapsed_usec) / 1000.0
	_frame_deltas_ms.append(frame_elapsed_ms)
	if included_source_tick:
		_frame_with_tick_ms.append(frame_elapsed_ms)
	else:
		_frame_without_tick_ms.append(frame_elapsed_ms)
	var engine_frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_engine_frame_ms.append(engine_frame_ms)
	if included_source_tick:
		_engine_frame_with_tick_ms.append(engine_frame_ms)
	else:
		_engine_frame_without_tick_ms.append(engine_frame_ms)
	_rolling_fps.append(Performance.get_monitor(Performance.TIME_FPS))
	_static_memory_bytes.append(Performance.get_monitor(Performance.MEMORY_STATIC))
	_node_counts.append(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	_orphan_counts.append(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	_creature_counts.append(float(_garden.get_creature_count()))
	_tracked_counts.append(float(_registry.get_tracked_count()))


func _on_snapshot_generated(snapshot: Dictionary) -> void:
	var callback_start_usec := Time.get_ticks_usec()
	var encode_start_usec := Time.get_ticks_usec()
	var wire_snapshot := snapshot.duplicate()
	wire_snapshot.erase("_collected_at_unix")
	var body := JSON.stringify(wire_snapshot).to_utf8_buffer()
	var encode_elapsed_usec := Time.get_ticks_usec() - encode_start_usec
	var parse_start_usec := Time.get_ticks_usec()
	var parsed: Dictionary = SnapshotParserScript.parse_body(body)
	var parse_elapsed_usec := Time.get_ticks_usec() - parse_start_usec
	if _measuring:
		_json_encode_ms.append(float(encode_elapsed_usec) / 1000.0)
		_json_parse_ms.append(float(parse_elapsed_usec) / 1000.0)
	if not parsed["ok"]:
		if _measuring:
			_invalid_snapshot_count += 1
		return
	var received_utc := Time.get_unix_time_from_system()
	var received_ticks := Time.get_ticks_msec()
	var registry_start_usec := Time.get_ticks_usec()
	var result: Dictionary = _registry.accept_snapshot(
		parsed["snapshot"], received_utc, received_ticks
	)
	var registry_elapsed_usec := Time.get_ticks_usec() - registry_start_usec
	if result["accepted"]:
		var records_start_usec := Time.get_ticks_usec()
		var records := _registry.get_records()
		var records_elapsed_usec := Time.get_ticks_usec() - records_start_usec
		var garden_start_usec := Time.get_ticks_usec()
		_garden.reconcile_processes(records)
		var garden_elapsed_usec := Time.get_ticks_usec() - garden_start_usec
		var callback_elapsed_usec := Time.get_ticks_usec() - callback_start_usec
		if _measuring:
			_registry_ms.append(float(registry_elapsed_usec) / 1000.0)
			_registry_records_ms.append(float(records_elapsed_usec) / 1000.0)
			var garden_profile := _garden.get_last_profile_usec()
			_garden_copy_ms.append(
				float(garden_profile.get("process_copy_usec", 0)) / 1000.0
			)
			_selector_ms.append(
				float(garden_profile.get("selector_usec", 0)) / 1000.0
			)
			_creature_reconcile_ms.append(
				float(garden_profile.get("creature_reconcile_usec", 0)) / 1000.0
			)
			_snapshot_pipeline_ms.append(float(garden_elapsed_usec) / 1000.0)
			_callback_total_ms.append(float(callback_elapsed_usec) / 1000.0)
		_snapshot_count += 1


func _record_demo_source_stages(profile: Dictionary) -> void:
	if not _measuring:
		return
	if not bool(profile.get("contract_valid", false)):
		_invalid_snapshot_count += 1
	_metric_update_ms.append(float(profile.get("metric_update_usec", 0)) / 1000.0)
	_lifecycle_update_ms.append(float(profile.get("lifecycle_update_usec", 0)) / 1000.0)
	_source_copy_ms.append(float(profile.get("snapshot_copy_usec", 0)) / 1000.0)
	_contract_validation_ms.append(
		float(profile.get("contract_validation_usec", 0)) / 1000.0
	)


func _clear_samples() -> void:
	_frame_deltas_ms.clear()
	_engine_frame_ms.clear()
	_rolling_fps.clear()
	_static_memory_bytes.clear()
	_node_counts.clear()
	_orphan_counts.clear()
	_creature_counts.clear()
	_tracked_counts.clear()
	_snapshot_pipeline_ms.clear()
	_callback_total_ms.clear()
	_json_encode_ms.clear()
	_json_parse_ms.clear()
	_demo_tick_ms.clear()
	_metric_update_ms.clear()
	_lifecycle_update_ms.clear()
	_source_copy_ms.clear()
	_contract_validation_ms.clear()
	_registry_ms.clear()
	_registry_records_ms.clear()
	_garden_copy_ms.clear()
	_selector_ms.clear()
	_creature_reconcile_ms.clear()
	_frame_with_tick_ms.clear()
	_frame_without_tick_ms.clear()
	_engine_frame_with_tick_ms.clear()
	_engine_frame_without_tick_ms.clear()
	_snapshot_count = 0
	_invalid_snapshot_count = 0


func _result_row(population: int) -> String:
	var average_fps := 0.0
	if not _frame_deltas_ms.is_empty():
		average_fps = float(_frame_deltas_ms.size()) / (_duration_seconds)
	var composition: Dictionary = _garden.get_composition_metrics()
	var max_surface_occupancy := 0
	var surface_counts: Dictionary = composition["by_surface"]
	for count_value in surface_counts.values():
		max_surface_occupancy = maxi(max_surface_occupancy, int(count_value))
	var columns := PackedStringArray([
		_renderer_mode,
		str(Engine.get_version_info().get("string", "unknown")),
		OS.get_name(),
		str(population),
		str(_seed_value),
		"%.2f" % _duration_seconds,
		str(_frame_deltas_ms.size()),
		"%.2f" % average_fps,
		"%.2f" % _minimum_positive(_rolling_fps),
		"%.3f" % _average(_frame_deltas_ms),
		"%.3f" % _percentile(_frame_deltas_ms, 0.95),
		"%.3f" % _maximum(_frame_deltas_ms),
		"%.3f" % _average(_engine_frame_ms),
		"%.3f" % _percentile(_engine_frame_ms, 0.95),
		"%.3f" % _maximum(_engine_frame_ms),
		"%.2f" % _first_mib(_static_memory_bytes),
		"%.2f" % _last_mib(_static_memory_bytes),
		"%.2f" % _maximum_mib(_static_memory_bytes),
		str(int(_maximum(_node_counts))),
		str(int(_maximum(_orphan_counts))),
		str(int(_maximum(_creature_counts))),
		str(int(_maximum(_tracked_counts))),
		str(_snapshot_count),
		str(_invalid_snapshot_count),
		"%.3f" % _average(_snapshot_pipeline_ms),
		"%.3f" % _percentile(_snapshot_pipeline_ms, 0.95),
		"%.3f" % _maximum(_snapshot_pipeline_ms),
		"%.3f" % _average(_demo_tick_ms),
		"%.3f" % _percentile(_demo_tick_ms, 0.95),
		"%.3f" % _maximum(_demo_tick_ms),
		"%.3f" % _average(_frame_with_tick_ms),
		"%.3f" % _average(_engine_frame_with_tick_ms),
		"%.3f" % _maximum(_frame_with_tick_ms),
		"%.3f" % _maximum(_frame_without_tick_ms),
		"%.3f" % _maximum(_engine_frame_with_tick_ms),
		"%.3f" % _maximum(_engine_frame_without_tick_ms),
		"%.3f" % _average(_metric_update_ms),
		"%.3f" % _maximum(_metric_update_ms),
		"%.3f" % _average(_lifecycle_update_ms),
		"%.3f" % _maximum(_lifecycle_update_ms),
		"%.3f" % _average(_source_copy_ms),
		"%.3f" % _maximum(_source_copy_ms),
		"%.3f" % _average(_contract_validation_ms),
		"%.3f" % _maximum(_contract_validation_ms),
		"%.3f" % _average(_json_encode_ms),
		"%.3f" % _maximum(_json_encode_ms),
		"%.3f" % _average(_json_parse_ms),
		"%.3f" % _maximum(_json_parse_ms),
		"%.3f" % _average(_registry_ms),
		"%.3f" % _maximum(_registry_ms),
		"%.3f" % _average(_registry_records_ms),
		"%.3f" % _maximum(_registry_records_ms),
		"%.3f" % _average(_garden_copy_ms),
		"%.3f" % _maximum(_garden_copy_ms),
		"%.3f" % _average(_selector_ms),
		"%.3f" % _maximum(_selector_ms),
		"%.3f" % _average(_creature_reconcile_ms),
		"%.3f" % _maximum(_creature_reconcile_ms),
		"%.3f" % _average(_callback_total_ms),
		"%.3f" % _maximum(_callback_total_ms),
		str(int(composition["overlap_pairs"])),
		"%.2f" % float(composition["overlap_area"]),
		str(int(composition["unsupported"])),
		str(int(composition["potential_interface_intersections"])),
		str(int(composition["saturated_surfaces"])),
		str(max_surface_occupancy),
	])
	return ",".join(columns)


func _csv_header() -> String:
	return "visual_renderer,godot_version,os,scenario,seed,duration_s,frames,avg_fps,min_rolling_fps,avg_frame_ms,p95_frame_ms,max_frame_ms,avg_engine_frame_ms,p95_engine_frame_ms,max_engine_frame_ms,static_memory_start_mib,static_memory_end_mib,sampled_static_memory_peak_mib,max_nodes,max_orphans,max_creatures,max_tracked_processes,snapshots,invalid_snapshots,avg_garden_reconcile_ms,p95_garden_reconcile_ms,max_garden_reconcile_ms,avg_demo_tick_ms,p95_demo_tick_ms,max_demo_tick_ms,avg_frame_after_tick_ms,avg_engine_frame_after_tick_ms,max_frame_after_tick_ms,max_frame_without_tick_ms,max_engine_frame_after_tick_ms,max_engine_frame_without_tick_ms,avg_demo_metrics_ms,max_demo_metrics_ms,avg_demo_lifecycle_ms,max_demo_lifecycle_ms,avg_snapshot_copy_ms,max_snapshot_copy_ms,avg_demo_contract_validation_ms,max_demo_contract_validation_ms,avg_json_encode_ms,max_json_encode_ms,avg_json_parse_validation_ms,max_json_parse_validation_ms,avg_registry_ms,max_registry_ms,avg_registry_get_records_ms,max_registry_get_records_ms,avg_garden_process_copy_ms,max_garden_process_copy_ms,avg_selector_ms,max_selector_ms,avg_creature_reconcile_ms,max_creature_reconcile_ms,avg_snapshot_callback_ms,max_snapshot_callback_ms,composition_overlap_pairs,composition_overlap_area_px2,composition_unsupported,potential_interface_intersections,saturated_surfaces,max_surface_occupancy"


func _average(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var total := 0.0
	for value in values:
		total += value
	return total / float(values.size())


func _maximum(values: Array[float]) -> float:
	var result := 0.0
	for value in values:
		result = maxf(result, value)
	return result


func _minimum_positive(values: Array[float]) -> float:
	var result := INF
	for value in values:
		if value > 0.0:
			result = minf(result, value)
	return 0.0 if is_inf(result) else result


func _percentile(values: Array[float], quantile: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted_values: Array[float] = values.duplicate()
	sorted_values.sort()
	var index := clampi(
		int(ceil(float(sorted_values.size()) * quantile)) - 1, 0, sorted_values.size() - 1
	)
	return sorted_values[index]


func _first_mib(values: Array[float]) -> float:
	return values[0] / 1_048_576.0 if not values.is_empty() else 0.0


func _last_mib(values: Array[float]) -> float:
	return values[-1] / 1_048_576.0 if not values.is_empty() else 0.0


func _maximum_mib(values: Array[float]) -> float:
	return _maximum(values) / 1_048_576.0
