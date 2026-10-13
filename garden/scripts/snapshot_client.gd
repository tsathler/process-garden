extends Node
class_name SnapshotClient

signal snapshot_received(snapshot: Dictionary)
signal request_failed(category: String, detail: String)

const SnapshotParserScript = preload("res://scripts/snapshot_parser.gd")
const RESPONSE_LIMIT_BYTES := 1_048_576
const LOOPBACK_PREFIX := "http://127.0.0.1:"

@export var endpoint_url := "http://127.0.0.1:8765/v1/snapshot"
@export_range(0.25, 10.0, 0.25) var poll_interval_seconds := 2.0
@export_range(0.5, 10.0, 0.5) var request_timeout_seconds := 3.0

var _http_request: HTTPRequest
var _poll_timer: Timer
var _request_active := false
var _endpoint_is_valid := true


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.body_size_limit = RESPONSE_LIMIT_BYTES
	_http_request.timeout = request_timeout_seconds
	_http_request.max_redirects = 0
	_http_request.download_file = ""
	_http_request.accept_gzip = false
	_http_request.use_threads = true
	_http_request.request_completed.connect(_on_request_completed)
	add_child(_http_request)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = poll_interval_seconds
	_poll_timer.timeout.connect(_request_snapshot)
	add_child(_poll_timer)
	_poll_timer.start()
	_endpoint_is_valid = _is_allowed_endpoint(endpoint_url)
	if not _endpoint_is_valid:
		call_deferred("_report_invalid_endpoint")
	else:
		call_deferred("_request_snapshot")


func _exit_tree() -> void:
	if _poll_timer != null:
		_poll_timer.stop()
	if _request_active and _http_request != null:
		_http_request.cancel_request()
		_request_active = false


func _request_snapshot() -> void:
	if _request_active or not _endpoint_is_valid:
		return
	_request_active = true
	var request_error := _http_request.request(
		endpoint_url,
		PackedStringArray(["Accept: application/json"]),
		HTTPClient.METHOD_GET
	)
	if request_error != OK:
		_request_active = false
		request_failed.emit("transport", "request_start_error:%d" % request_error)


func _on_request_completed(
	result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_request_active = false
	if result == HTTPRequest.RESULT_TIMEOUT:
		request_failed.emit("timeout", "request_timeout")
		return
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		request_failed.emit("response_too_large", "response_exceeded_1_mib")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("transport", "http_request_result:%d" % result)
		return
	if response_code != 200:
		request_failed.emit("http_status", "http_status:%d" % response_code)
		return
	if body.is_empty():
		request_failed.emit("empty_response", "empty_response_body")
		return

	var parsed: Dictionary = SnapshotParserScript.parse_body(body)
	if not parsed["ok"]:
		request_failed.emit(str(parsed["category"]), str(parsed["error"]))
		return
	snapshot_received.emit(parsed["snapshot"])


func _is_allowed_endpoint(url: String) -> bool:
	if not url.begins_with(LOOPBACK_PREFIX):
		return false
	var remainder := url.substr(LOOPBACK_PREFIX.length())
	var path_index := remainder.find("/")
	if path_index <= 0 or remainder.substr(path_index) != "/v1/snapshot":
		return false
	var port_text := remainder.substr(0, path_index)
	if not _is_digits(port_text):
		return false
	var port := int(port_text)
	return port > 0 and port <= 65535


func _is_digits(value: String) -> bool:
	if value.is_empty():
		return false
	for index in range(value.length()):
		if value[index] < "0" or value[index] > "9":
			return false
	return true


func _report_invalid_endpoint() -> void:
	request_failed.emit("configuration", "endpoint_must_be_loopback_snapshot_url")
