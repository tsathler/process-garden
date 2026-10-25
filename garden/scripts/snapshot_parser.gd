extends RefCounted
class_name SnapshotParser

const MAX_SAFE_JSON_INTEGER := 9007199254740991
const MONTH_LENGTHS := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
const REQUIRED_SNAPSHOT_FIELDS := [
	"schema_version",
	"sequence",
	"collected_at",
	"interval_ms",
	"status",
	"processes",
	"skipped_count",
]
const REQUIRED_PROCESS_FIELDS := [
	"pid",
	"create_time",
	"name",
	"cpu_percent",
	"memory_rss_bytes",
]


static func parse_text(text: String) -> Dictionary:
	if text.is_empty():
		return _failure("empty", "The response body is empty.")

	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return _failure(
			"json",
			"JSON parse error at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		)
	return validate_data(json.get_data())


static func parse_body(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return _failure("empty", "The response body is empty.")
	return parse_text(body.get_string_from_utf8())


static func validate_data(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("snapshot", "Snapshot must be a JSON object.")

	var data: Dictionary = value
	for field in REQUIRED_SNAPSHOT_FIELDS:
		if not data.has(field):
			return _failure("snapshot", "Snapshot is missing '%s'." % field)

	if not _is_integer(data["schema_version"], 0) or int(data["schema_version"]) != 1:
		return _failure("snapshot", "Unsupported schema_version; expected 1.")
	if not _is_integer(data["sequence"], 1):
		return _failure("snapshot", "sequence must be a positive integer.")
	if not _is_integer(data["interval_ms"], 1):
		return _failure("snapshot", "interval_ms must be a positive integer.")
	if not _is_integer(data["skipped_count"], 0):
		return _failure("snapshot", "skipped_count must be a non-negative integer.")
	if typeof(data["status"]) != TYPE_STRING or not ["ok", "partial"].has(data["status"]):
		return _failure("snapshot", "status must be 'ok' or 'partial'.")
	if typeof(data["processes"]) != TYPE_ARRAY:
		return _failure("snapshot", "processes must be an array.")
	if data["status"] == "ok" and int(data["skipped_count"]) > 0:
		return _failure("snapshot", "an 'ok' snapshot cannot have skipped processes.")
	if data["status"] == "partial" and int(data["skipped_count"]) == 0:
		return _failure("snapshot", "a 'partial' snapshot must report skipped processes.")

	var timestamp_result := _parse_utc_timestamp(data["collected_at"])
	if not timestamp_result["ok"]:
		return timestamp_result

	var processes: Array[Dictionary] = []
	var identities: Dictionary = {}
	for index in range(data["processes"].size()):
		var process_value: Variant = data["processes"][index]
		if typeof(process_value) != TYPE_DICTIONARY:
			return _failure("snapshot", "processes[%d] must be an object." % index)
		var process: Dictionary = process_value
		for field in REQUIRED_PROCESS_FIELDS:
			if not process.has(field):
				return _failure(
					"snapshot", "processes[%d] is missing '%s'." % [index, field]
				)

		if not _is_integer(process["pid"], 0):
			return _failure(
				"snapshot", "processes[%d].pid must be a non-negative integer." % index
			)
		if not _is_number(process["create_time"]) or not is_finite(float(process["create_time"])):
			return _failure("snapshot", "processes[%d].create_time must be finite." % index)
		if typeof(process["name"]) != TYPE_STRING:
			return _failure("snapshot", "processes[%d].name must be text." % index)
		var cpu: Variant = process["cpu_percent"]
		if cpu != null and (
			not _is_number(cpu) or not is_finite(float(cpu)) or float(cpu) < 0.0
		):
			return _failure(
				"snapshot", "processes[%d].cpu_percent must be null or finite and non-negative." % index
			)
		if not _is_integer(process["memory_rss_bytes"], 0):
			return _failure(
				"snapshot", "processes[%d].memory_rss_bytes must be a non-negative integer." % index
			)

		var normalized_process: Dictionary = process.duplicate()
		normalized_process["pid"] = int(process["pid"])
		normalized_process["create_time"] = float(process["create_time"])
		normalized_process["memory_rss_bytes"] = int(process["memory_rss_bytes"])
		if cpu != null:
			normalized_process["cpu_percent"] = float(cpu)
		var identity := identity_key(normalized_process)
		if identities.has(identity):
			return _failure("snapshot", "Duplicate process identity at index %d." % index)
		identities[identity] = true
		processes.append(normalized_process)

	var normalized_snapshot: Dictionary = data.duplicate()
	normalized_snapshot["schema_version"] = 1
	normalized_snapshot["sequence"] = int(data["sequence"])
	normalized_snapshot["interval_ms"] = int(data["interval_ms"])
	normalized_snapshot["skipped_count"] = int(data["skipped_count"])
	normalized_snapshot["processes"] = processes
	normalized_snapshot["_collected_at_unix"] = timestamp_result["unix_time"]
	return {"ok": true, "snapshot": normalized_snapshot, "error": "", "category": ""}


static func identity_key(process: Dictionary) -> String:
	# 17 fractional digits keep distinct IEEE-754 process start times distinct.
	return "%d|%.17f" % [int(process["pid"]), float(process["create_time"])]


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _is_integer(value: Variant, minimum: int) -> bool:
	if not _is_number(value):
		return false
	var number := float(value)
	return (
		is_finite(number)
		and number >= float(minimum)
		and number <= float(MAX_SAFE_JSON_INTEGER)
		and floor(number) == number
	)


static func _parse_utc_timestamp(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_STRING:
		return _failure("snapshot", "collected_at must be a UTC timestamp string.")
	var timestamp: String = value
	var date_time := timestamp
	if timestamp.ends_with("+00:00"):
		date_time = timestamp.trim_suffix("+00:00")
	elif timestamp.ends_with("Z"):
		date_time = timestamp.trim_suffix("Z")
	else:
		return _failure("snapshot", "collected_at must explicitly use UTC (+00:00 or Z).")

	var fraction := ""
	var decimal_index := date_time.find(".")
	if decimal_index >= 0:
		fraction = date_time.substr(decimal_index + 1)
		date_time = date_time.substr(0, decimal_index)
		if fraction.is_empty() or fraction.length() > 6 or not _is_digits(fraction):
			return _failure("snapshot", "collected_at has an invalid fractional second.")

	if (
		date_time.length() != 19
		or date_time[4] != "-"
		or date_time[7] != "-"
		or date_time[10] != "T"
		or date_time[13] != ":"
		or date_time[16] != ":"
		or not _is_digits(date_time.substr(0, 4))
		or not _is_digits(date_time.substr(5, 2))
		or not _is_digits(date_time.substr(8, 2))
		or not _is_digits(date_time.substr(11, 2))
		or not _is_digits(date_time.substr(14, 2))
		or not _is_digits(date_time.substr(17, 2))
	):
		return _failure("snapshot", "collected_at must be an ISO 8601 UTC timestamp.")

	var year := int(date_time.substr(0, 4))
	var month := int(date_time.substr(5, 2))
	var day := int(date_time.substr(8, 2))
	var hour := int(date_time.substr(11, 2))
	var minute := int(date_time.substr(14, 2))
	var second := int(date_time.substr(17, 2))
	if year < 1 or month < 1 or month > 12:
		return _failure("snapshot", "collected_at contains an invalid date or time.")
	if day < 1 or day > _days_in_month(year, month):
		return _failure("snapshot", "collected_at contains an invalid date or time.")
	if hour > 23 or minute > 59 or second > 59:
		return _failure("snapshot", "collected_at contains an invalid date or time.")

	var parts := Time.get_datetime_dict_from_datetime_string(date_time, false)
	if parts.is_empty() or int(parts.get("year", 0)) < 1:
		return _failure("snapshot", "collected_at contains an invalid date.")
	var unix_seconds := Time.get_unix_time_from_datetime_dict(parts)
	var round_trip := Time.get_datetime_dict_from_unix_time(unix_seconds)
	for field in ["year", "month", "day", "hour", "minute", "second"]:
		if int(parts.get(field, -1)) != int(round_trip.get(field, -2)):
			return _failure("snapshot", "collected_at contains an invalid date or time.")
	var fractional_seconds := 0.0 if fraction.is_empty() else float("0." + fraction)
	return {"ok": true, "unix_time": float(unix_seconds) + fractional_seconds}


static func _days_in_month(year: int, month: int) -> int:
	if month < 1 or month > 12:
		return 0
	if month == 2 and (year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)):
		return 29
	return MONTH_LENGTHS[month - 1]


static func _is_digits(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		var character := value[index]
		if character < "0" or character > "9":
			return false
	return true


static func _failure(category: String, message: String) -> Dictionary:
	return {"ok": false, "category": category, "error": message}
