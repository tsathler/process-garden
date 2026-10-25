extends Node
class_name CollectorProcessManager

const STARTUP_TIMEOUT_SECONDS := 10.0
const READY_POLL_SECONDS := 0.1

var _owned_pid := -1
var _ready_file := ""
var _stop_file := ""


func should_manage_bundled_collector() -> bool:
	return OS.get_name() == "Windows" and not OS.has_feature("editor")


func launch_and_configure(client: SnapshotClient) -> Dictionary:
	if not should_manage_bundled_collector():
		return {"ok": false, "error": "bundled_collector_not_applicable"}
	var executable := OS.get_executable_path().get_base_dir().path_join("collector").path_join("ProcessGardenCollector.exe")
	if not FileAccess.file_exists(executable):
		return {"ok": false, "error": "bundled_collector_missing · DEMO remains available"}
	var temp_directory := OS.get_environment("TEMP")
	if temp_directory.is_empty():
		return {"ok": false, "error": "temporary_directory_unavailable · DEMO remains available"}
	if _owned_pid > 0:
		if OS.is_process_running(_owned_pid):
			stop_owned_collector()
			return {"ok": false, "error": "previous_collector_stopping · DEMO remains available"}
		_forget_exited_collector()
	var token := Crypto.new().generate_random_bytes(16).hex_encode()
	_ready_file = temp_directory.path_join("process-garden-%s.json" % token)
	_stop_file = temp_directory.path_join("process-garden-%s.stop" % token)
	var arguments := PackedStringArray(
		[
			"--port",
			"0",
			"--interval",
			"2",
			"--ready-token",
			token,
			"--stop-token",
			token,
			"--owner-pid",
			str(OS.get_process_id()),
		]
	)
	_owned_pid = OS.create_process(executable, arguments, false)
	if _owned_pid <= 0:
		_owned_pid = -1
		_remove_ready_file()
		_remove_stop_file()
		return {"ok": false, "error": "bundled_collector_start_failed · DEMO remains available"}

	var deadline := Time.get_ticks_msec() + int(STARTUP_TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if FileAccess.file_exists(_ready_file):
			var readiness := _readiness_data()
			if readiness.is_empty():
				stop_owned_collector()
				return {"ok": false, "error": "bundled_collector_handshake_invalid · DEMO remains available"}
			var endpoint := "http://127.0.0.1:%d/v1/snapshot" % int(readiness["port"])
			if not client.set_endpoint_url(endpoint):
				stop_owned_collector()
				return {"ok": false, "error": "bundled_collector_endpoint_invalid · DEMO remains available"}
			_remove_ready_file()
			return {"ok": true, "pid": _owned_pid, "port": int(readiness["port"])}
		await get_tree().create_timer(READY_POLL_SECONDS).timeout
	stop_owned_collector()
	return {"ok": false, "error": "bundled_collector_start_timeout · DEMO remains available"}


func stop_owned_collector() -> void:
	if _owned_pid > 0 and not _stop_file.is_empty():
		var stop_signal := FileAccess.open(_stop_file, FileAccess.WRITE)
		if stop_signal != null:
			stop_signal.store_string("stop")
			stop_signal.close()
	_remove_ready_file()


func owned_collector_has_exited() -> bool:
	if _owned_pid <= 0:
		return true
	if OS.is_process_running(_owned_pid):
		return false
	_forget_exited_collector()
	return true


func get_owned_pid() -> int:
	return _owned_pid


func _forget_exited_collector() -> void:
	_owned_pid = -1
	_remove_ready_file()
	_remove_stop_file()


func _exit_tree() -> void:
	stop_owned_collector()


func _readiness_data() -> Dictionary:
	var file := FileAccess.open(_ready_file, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return validate_readiness(parsed)


static func validate_readiness(parsed: Variant) -> Dictionary:
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	if parsed.get("host") != "127.0.0.1":
		return {}
	var port: Variant = parsed.get("port")
	if typeof(port) != TYPE_INT and typeof(port) != TYPE_FLOAT:
		return {}
	var port_number := float(port)
	if not is_finite(port_number) or port_number != floorf(port_number):
		return {}
	if port_number < 1.0 or port_number > 65535.0:
		return {}
	parsed["port"] = int(port_number)
	return parsed


func _remove_ready_file() -> void:
	if not _ready_file.is_empty() and FileAccess.file_exists(_ready_file):
		DirAccess.remove_absolute(_ready_file)
	_ready_file = ""


func _remove_stop_file() -> void:
	if not _stop_file.is_empty() and FileAccess.file_exists(_stop_file):
		DirAccess.remove_absolute(_stop_file)
	_stop_file = ""
