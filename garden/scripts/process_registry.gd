extends RefCounted
class_name ProcessRegistry

signal processes_changed(events: Dictionary)
signal connection_state_changed(state: String)

const STATE_CONNECTING := "Connecting"
const STATE_CONNECTED := "Connected"
const STATE_STALE := "Stale"
const STATE_DISCONNECTED := "Disconnected"
const MAX_FUTURE_SKEW_SECONDS := 5.0

var stale_after_seconds: float
var disconnected_after_seconds: float
var _processes: Dictionary = {}
var _has_snapshot := false
var _started_ticks_msec := 0
var _last_new_snapshot_ticks_msec := 0
var _snapshot_age_at_receipt := 0.0
var _last_sequence := 0
var _last_collected_at_unix := 0.0
var _latest_snapshot: Dictionary = {}
var _last_problem := ""
var connection_state := STATE_CONNECTING


func _init(stale_after: float = 6.0, disconnected_after: float = 15.0) -> void:
	stale_after_seconds = stale_after
	disconnected_after_seconds = disconnected_after
	_started_ticks_msec = Time.get_ticks_msec()


func accept_snapshot(snapshot: Dictionary, received_utc: float, received_ticks_msec: int) -> Dictionary:
	var sequence := int(snapshot["sequence"])
	var collected_at := float(snapshot["_collected_at_unix"])
	var age_at_receipt := received_utc - collected_at
	if age_at_receipt < -MAX_FUTURE_SKEW_SECONDS:
		return _reject("timestamp_in_future", received_utc, received_ticks_msec)
	age_at_receipt = maxf(age_at_receipt, 0.0)
	if age_at_receipt > disconnected_after_seconds:
		return _reject("snapshot_too_old", received_utc, received_ticks_msec)

	var restarted := false
	if _has_snapshot:
		if collected_at == _last_collected_at_unix and sequence == _last_sequence:
			_last_problem = ""
			update_connection_state(received_utc, received_ticks_msec)
			return {"accepted": false, "reason": "repeated", "events": _empty_events()}
		if collected_at <= _last_collected_at_unix:
			return _reject("older_snapshot", received_utc, received_ticks_msec)
		if sequence <= _last_sequence:
			restarted = true

	var events := _reconcile(snapshot, sequence, restarted)
	_has_snapshot = true
	_last_sequence = sequence
	_last_collected_at_unix = collected_at
	_last_new_snapshot_ticks_msec = received_ticks_msec
	_snapshot_age_at_receipt = age_at_receipt
	_latest_snapshot = snapshot
	_last_problem = ""
	update_connection_state(received_utc, received_ticks_msec)
	processes_changed.emit(events)
	return {"accepted": true, "reason": "", "events": events, "restarted": restarted}


func update_connection_state(_now_utc: float, now_ticks_msec: int) -> Dictionary:
	var age_seconds: float
	if _has_snapshot:
		age_seconds = _snapshot_age_at_receipt + maxf(
			float(now_ticks_msec - _last_new_snapshot_ticks_msec) / 1000.0,
			0.0
		)
	else:
		age_seconds = maxf(float(now_ticks_msec - _started_ticks_msec) / 1000.0, 0.0)

	var next_state := STATE_CONNECTING
	if age_seconds >= disconnected_after_seconds:
		next_state = STATE_DISCONNECTED
	elif age_seconds >= stale_after_seconds:
		next_state = STATE_STALE
	elif _has_snapshot:
		next_state = STATE_CONNECTED
	if next_state != connection_state:
		connection_state = next_state
		connection_state_changed.emit(connection_state)
	return {
		"state": connection_state,
		"age_seconds": age_seconds,
		"has_snapshot": _has_snapshot,
		"last_problem": _last_problem,
	}


func note_request_problem(problem: String) -> void:
	_last_problem = problem


func get_process_count_in_snapshot() -> int:
	return int(_latest_snapshot.get("processes", []).size())


func get_sequence() -> int:
	return _last_sequence


func get_collected_at() -> String:
	return str(_latest_snapshot.get("collected_at", "—"))


func get_snapshot_status() -> String:
	return str(_latest_snapshot.get("status", "—"))


func get_last_problem() -> String:
	return _last_problem


func get_records() -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for identity in _processes:
		records.append(_processes[identity])
	return records


func get_tracked_count() -> int:
	return _processes.size()


func _reconcile(snapshot: Dictionary, sequence: int, restarted: bool) -> Dictionary:
	var added: Array[Dictionary] = []
	var persisted: Array[Dictionary] = []
	var removed: Array[Dictionary] = []
	var present_identities: Dictionary = {}
	for process in snapshot["processes"]:
		var identity: String = SnapshotParser.identity_key(process)
		present_identities[identity] = true
		if _processes.has(identity):
			persisted.append(process)
		else:
			added.append(process)
		_processes[identity] = process

	if snapshot["status"] == "ok":
		for identity in _processes.keys():
			if not present_identities.has(identity):
				removed.append(_processes[identity])
				_processes.erase(identity)

	return {
		"sequence": sequence,
		"added": added,
		"persisted": persisted,
		"removed": removed,
		"session_restarted": restarted,
		"snapshot_status": snapshot["status"],
	}


func _reject(reason: String, now_utc: float, now_ticks_msec: int) -> Dictionary:
	_last_problem = reason
	update_connection_state(now_utc, now_ticks_msec)
	return {"accepted": false, "reason": reason, "events": _empty_events()}


func _empty_events() -> Dictionary:
	return {
		"sequence": _last_sequence,
		"added": [],
		"persisted": [],
		"removed": [],
		"session_restarted": false,
		"snapshot_status": get_snapshot_status(),
	}
