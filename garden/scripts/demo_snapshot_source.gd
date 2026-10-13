extends Node
class_name DemoSnapshotSource

signal snapshot_generated(snapshot: Dictionary)

const SnapshotParserScript = preload("res://scripts/snapshot_parser.gd")
const SCENARIOS := [50, 150, 300, 500]
const PROCESS_NAMES := ["wisp", "spore", "mote", "moth", "ember"]
const BASE_PID := 1_500_000_000
const MAX_MEMORY_BYTES := 2_147_483_648

@export_range(0.25, 10.0, 0.25) var interval_seconds := 2.0

var population_size := 150
var seed_value := 2025
var _timer: Timer
var _random := RandomNumberGenerator.new()
var _processes: Array[Dictionary] = []
var _available_pids: Array[int] = []
var _pid_generations: Dictionary = {}
var _next_pid := BASE_PID
var _birth_serial := 0
var _sequence := 0
var _tick := 0
var _last_collected_unix := 0.0
var _is_running := false


func _ready() -> void:
	_ensure_timer()


func configure(new_population_size: int, new_seed: int) -> void:
	stop()
	population_size = _supported_population(new_population_size)
	seed_value = maxi(new_seed, 0)
	_reset_simulation()


func start() -> void:
	_ensure_timer()
	if _is_running:
		return
	_is_running = true
	_timer.wait_time = interval_seconds
	_timer.start()
	_emit_snapshot()


func stop() -> void:
	_is_running = false
	if _timer != null:
		_timer.stop()


func advance_one_step() -> void:
	if not _is_running:
		return
	_tick += 1
	_update_metrics()
	if _tick % 4 == 1:
		_spawn_process()
	elif _tick % 4 == 3:
		_end_process()
	_emit_snapshot()


func get_population_size() -> int:
	return _processes.size()


func _ensure_timer() -> void:
	if _timer != null:
		return
	_timer = Timer.new()
	_timer.name = "DemoSnapshotTimer"
	_timer.one_shot = false
	_timer.timeout.connect(advance_one_step)
	add_child(_timer)


func _reset_simulation() -> void:
	_random.seed = seed_value
	_processes.clear()
	_available_pids.clear()
	_pid_generations.clear()
	_next_pid = BASE_PID
	_birth_serial = 0
	_sequence = 0
	_tick = 0
	_last_collected_unix = 0.0
	var create_time_base := 1_700_000_000.0 + float(posmod(seed_value, 100_000))
	for index in range(population_size):
		var pid := _next_pid
		_next_pid += 1
		_pid_generations[pid] = 0
		_processes.append(_make_process(pid, create_time_base + float(index) * 0.25))


func _make_process(pid: int, create_time: float) -> Dictionary:
	_birth_serial += 1
	var process_index := _birth_serial - 1
	var cpu_value: Variant = null if _random.randf() < 0.08 else _random.randf_range(0.0, 85.0)
	var memory_mib := _random.randf_range(6.0, 640.0)
	return {
		"pid": pid,
		"create_time": create_time,
		"name": "demo-%s-%03d" % [PROCESS_NAMES[process_index % PROCESS_NAMES.size()], process_index],
		"cpu_percent": cpu_value,
		"memory_rss_bytes": int(memory_mib * 1_048_576.0),
	}


func _update_metrics() -> void:
	for process in _processes:
		process["cpu_percent"] = _random.randf_range(0.0, 180.0)
		var memory_delta := _random.randf_range(-28.0, 35.0) * 1_048_576.0
		process["memory_rss_bytes"] = clampi(
			int(float(process["memory_rss_bytes"]) + memory_delta),
			1_048_576,
			MAX_MEMORY_BYTES
		)


func _spawn_process() -> void:
	var pid := _next_pid
	if not _available_pids.is_empty():
		pid = _available_pids.pop_front()
	else:
		_next_pid += 1
	var generation := int(_pid_generations.get(pid, 0)) + 1
	_pid_generations[pid] = generation
	var create_time := (
		1_700_000_000.0
		+ float(posmod(seed_value, 100_000))
		+ float(_birth_serial + generation) * 0.25
	)
	_processes.append(_make_process(pid, create_time))


func _end_process() -> void:
	if _processes.is_empty():
		return
	var removed_index := 0
	if _processes.size() > 1:
		removed_index = _random.randi_range(0, _processes.size() - 2)
	var removed: Dictionary = _processes.pop_at(removed_index)
	_available_pids.append(int(removed["pid"]))


func _emit_snapshot() -> void:
	_sequence += 1
	var now := Time.get_unix_time_from_system()
	_last_collected_unix = maxf(now, _last_collected_unix + 0.000001)
	var snapshot := {
		"schema_version": 1,
		"sequence": _sequence,
		"collected_at": _utc_timestamp(_last_collected_unix),
		"interval_ms": int(round(interval_seconds * 1000.0)),
		"status": "ok",
		"processes": _processes.duplicate(true),
		"skipped_count": 0,
	}
	var validated: Dictionary = SnapshotParserScript.validate_data(snapshot)
	if validated["ok"]:
		snapshot_generated.emit(validated["snapshot"])


func _utc_timestamp(unix_time: float) -> String:
	var whole_seconds := int(floor(unix_time))
	var microseconds := int((unix_time - float(whole_seconds)) * 1_000_000.0)
	var date_time := Time.get_datetime_dict_from_unix_time(whole_seconds)
	return "%04d-%02d-%02dT%02d:%02d:%02d.%06dZ" % [
		date_time["year"],
		date_time["month"],
		date_time["day"],
		date_time["hour"],
		date_time["minute"],
		date_time["second"],
		microseconds,
	]


func _supported_population(value: int) -> int:
	return value if SCENARIOS.has(value) else SCENARIOS[1]
