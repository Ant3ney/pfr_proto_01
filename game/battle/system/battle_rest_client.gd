class_name BattleRestClient
extends Node

## Small, single-flight JSON transport used only by BattleSystem.

signal transport_completed(
	request_id: int,
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
)

const BASE_URL := "https://pfr-locomotion-prototype.vercel.app/api/v1"
const REQUEST_TIMEOUT_SECONDS := 20.0
const MAX_RESPONSE_BYTES := 512 * 1024

var _http_request: HTTPRequest
var _active_request_id := -1


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.name = "HTTPRequest"
	_http_request.timeout = REQUEST_TIMEOUT_SECONDS
	_http_request.body_size_limit = MAX_RESPONSE_BYTES
	_http_request.accept_gzip = true
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


func is_busy() -> bool:
	return _active_request_id >= 0


func post_json_bytes(
	route: String,
	body: PackedByteArray,
	request_id: int
) -> Error:
	if not is_instance_valid(_http_request):
		return ERR_UNCONFIGURED
	if is_busy():
		return ERR_BUSY
	if request_id < 0 or not route.begins_with("/"):
		return ERR_INVALID_PARAMETER

	_active_request_id = request_id
	var error := _http_request.request_raw(
		BASE_URL + route,
		PackedStringArray([
			"Accept: application/json",
			"Content-Type: application/json",
		]),
		HTTPClient.METHOD_POST,
		body
	)
	if error != OK:
		_active_request_id = -1
	return error


func cancel_active_request() -> void:
	if is_instance_valid(_http_request) and is_busy():
		_http_request.cancel_request()
	_active_request_id = -1


func _on_request_completed(
	result: int,
	response_code: int,
	headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	var completed_request_id := _active_request_id
	_active_request_id = -1
	if completed_request_id < 0:
		return
	transport_completed.emit(
		completed_request_id,
		result,
		response_code,
		headers,
		body
	)
