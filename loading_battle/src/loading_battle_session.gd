class_name LoadingBattleSession
extends Node

## Memory-only coordinator for REST-backed loading-screen practice battles.

signal state_changed(state: String)
signal snapshot_changed(snapshot: Dictionary)
signal presentation_events_ready(events: Array, revision: int)
signal choice_request_changed(request: Dictionary)
signal practice_error_changed(error: Dictionary)
signal battle_finished(result: Dictionary, next_tier: String)

const REST_CLIENT_SCRIPT = preload("res://shared/battle_rest_client.gd")
const DTO_VALIDATOR = preload("res://shared/battle_dto_validator.gd")
const EVENT_TRANSLATOR = preload("res://shared/battle_event_translator.gd")
const RULES = preload("res://src/loading_battle_rules.gd")

const START_ROUTE := "/battles"
const ACTION_ROUTE := "/battles/actions"
const MAX_RESPONSE_BYTES := 512 * 1024

const STATE_PICKING := "picking"
const STATE_SUBMITTING := "submitting"
const STATE_PRESENTING := "presenting"
const STATE_AWAITING_PLAYER := "awaiting_player"
const STATE_ENDED := "ended"

var practice_only := true
var difficulty := "medium"
var selected_starter := ""
var win_streak := 0
var battles_played := 0

var _state := STATE_PICKING
var _transport: Node
var _owns_transport := false
var _next_request_id := 1
var _inflight_request_id := -1
var _pending_route := ""
var _pending_body := PackedByteArray()
var _pending_kind := ""
var _awaiting_retry := false
var _battle_id := ""
var _revision := -1
var _state_token := ""
var _player_member_ids: Array[String] = []
var _opponent_member_ids: Array[String] = []
var _snapshot: Dictionary = {}
var _choice_request: Dictionary = {}
var _queued_choice_request: Dictionary = {}
var _result: Dictionary = {}
var _practice_error: Dictionary = {}
var _result_applied_revision := -1


func _ready() -> void:
	if not is_instance_valid(_transport):
		_transport = REST_CLIENT_SCRIPT.new()
		_transport.name = "BattleRestClient"
		_owns_transport = true
		add_child(_transport)
	_connect_transport()
	state_changed.emit(_state)


func _exit_tree() -> void:
	# The opaque token and exact pending body intentionally die with this page.
	_state_token = ""
	_pending_body = PackedByteArray()
	if _owns_transport and is_instance_valid(_transport):
		_transport.cancel_active_request()


func set_transport_for_testing(transport: Node) -> void:
	if is_inside_tree():
		_disconnect_transport()
	_transport = transport
	_owns_transport = false
	if is_inside_tree():
		_connect_transport()


func select_starter(starter_id: String) -> bool:
	if _state != STATE_PICKING or not RULES.is_valid_starter(starter_id):
		return false
	selected_starter = starter_id
	difficulty = "medium"
	win_streak = 0
	battles_played = 0
	return _start_current_tier()


func start_next_battle() -> bool:
	if _state != STATE_ENDED or selected_starter.is_empty():
		return false
	return _start_current_tier()


func choose_move(move_index: int) -> bool:
	if not can_choose() or String(_choice_request.get("type", "")) != "move":
		return false
	var allowed := false
	for value: Variant in _choice_request.get("moves", []):
		if typeof(value) == TYPE_DICTIONARY:
			var move := value as Dictionary
			if int(move.get("moveIndex", 0)) == move_index and not bool(move.get("disabled", true)):
				allowed = true
				break
	return _submit_action({"type": "move", "moveIndex": move_index}) if allowed else false


func concede() -> bool:
	if not can_choose():
		return false
	return _submit_action({"type": "forfeit"})


func retry_pending_request() -> bool:
	if not _awaiting_retry or _inflight_request_id >= 0 or _pending_body.is_empty():
		return false
	_clear_error()
	_set_state(STATE_SUBMITTING)
	return _dispatch_pending_request()


func resume_after_reconnect() -> bool:
	if not _awaiting_retry or String(_practice_error.get("code", "")) != "offline":
		return false
	return retry_pending_request()


func acknowledge_events_presented(revision: int) -> bool:
	if _state != STATE_PRESENTING or revision != _revision:
		return false
	if not _result.is_empty():
		_set_state(STATE_ENDED)
		battle_finished.emit(_result.duplicate(true), difficulty)
		return true
	_choice_request = _queued_choice_request.duplicate(true)
	_queued_choice_request.clear()
	_set_state(STATE_AWAITING_PLAYER)
	choice_request_changed.emit(_choice_request.duplicate(true))
	return true


func can_choose() -> bool:
	return _state == STATE_AWAITING_PLAYER and not _choice_request.is_empty()


func get_state() -> String:
	return _state


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_choice_request() -> Dictionary:
	return _choice_request.duplicate(true)


func get_practice_error() -> Dictionary:
	return _practice_error.duplicate(true)


func get_pending_body_for_testing() -> PackedByteArray:
	return _pending_body.duplicate()


func _start_current_tier() -> bool:
	var payload: Dictionary = RULES.start_payload(selected_starter, difficulty)
	if payload.is_empty():
		return false
	_reset_battle_state()
	_player_member_ids = _member_ids((payload.player as Dictionary).team as Array)
	_opponent_member_ids = _member_ids((payload.opponent as Dictionary).team as Array)
	_prepare_pending_request(START_ROUTE, payload, "start")
	_set_state(STATE_SUBMITTING)
	return _dispatch_pending_request()


func _submit_action(action: Dictionary) -> bool:
	if _state_token.is_empty() or _inflight_request_id >= 0:
		return false
	_choice_request.clear()
	choice_request_changed.emit({})
	_prepare_pending_request(ACTION_ROUTE, {
		"stateToken": _state_token,
		"action": action.duplicate(true),
	}, "action")
	_set_state(STATE_SUBMITTING)
	return _dispatch_pending_request()


func _prepare_pending_request(route: String, payload: Dictionary, kind: String) -> void:
	_pending_route = route
	_pending_body = JSON.stringify(payload).to_utf8_buffer()
	_pending_kind = kind
	_awaiting_retry = false


func _dispatch_pending_request() -> bool:
	if not is_instance_valid(_transport) or not _transport.has_method("post_json_bytes"):
		_set_retryable_error("network_error", "The practice server is unavailable.")
		return false
	var request_id := _next_request_id
	_next_request_id += 1
	_inflight_request_id = request_id
	var error: Error = _transport.call(
		"post_json_bytes",
		_pending_route,
		_pending_body,
		request_id
	)
	if error != OK:
		_inflight_request_id = -1
		_set_retryable_error(_network_error_code(), "The practice server could not be reached.")
		return false
	return true


func _on_transport_completed(
	request_id: int,
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray
) -> void:
	if request_id != _inflight_request_id:
		return
	_inflight_request_id = -1
	if body.size() > MAX_RESPONSE_BYTES:
		_set_retryable_error("response_too_large", "The practice response was too large.")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_retryable_error(_network_error_code(), "The practice request was interrupted.")
		return
	if response_code < 200 or response_code >= 300:
		_set_retryable_error(
			"server_error" if response_code >= 500 else "request_rejected",
			"The practice server could not accept that request."
		)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_set_retryable_error("malformed_response", "The practice server returned malformed data.")
		return
	var expected_revision := 0 if _pending_kind == "start" else _revision + 1
	var validation: Dictionary = DTO_VALIDATOR.validate_response(json.data, {
		"battle_id": "" if _pending_kind == "start" else _battle_id,
		"revision": expected_revision,
		"player_member_ids": _player_member_ids,
		"opponent_member_ids": _opponent_member_ids,
	})
	if not bool(validation.get("ok", false)):
		_set_retryable_error(
			String(validation.get("code", "malformed_response")),
			String(validation.get("message", "The practice response was invalid."))
		)
		return
	_accept_response(validation.response as Dictionary)


func _accept_response(response: Dictionary) -> void:
	_battle_id = String(response.battleId)
	_revision = int(response.revision)
	_state_token = String(response.get("stateToken", ""))
	_queued_choice_request = (
		(response.request as Dictionary).duplicate(true)
		if typeof(response.get("request")) == TYPE_DICTIONARY
		else {}
	)
	_choice_request.clear()
	_result = (
		(response.result as Dictionary).duplicate(true)
		if typeof(response.get("result")) == TYPE_DICTIONARY
		else {}
	)
	_snapshot = {
		"battleId": _battle_id,
		"revision": _revision,
		"phase": String(response.phase),
		"parties": (response.parties as Dictionary).duplicate(true),
	}
	if not _result.is_empty():
		_snapshot["result"] = _result.duplicate(true)
		_apply_result_once()
	var events: Array = EVENT_TRANSLATOR.translate(response.events)
	_pending_body = PackedByteArray()
	_pending_route = ""
	_pending_kind = ""
	_awaiting_retry = false
	_clear_error()
	_set_state(STATE_PRESENTING)
	snapshot_changed.emit(_snapshot.duplicate(true))
	choice_request_changed.emit({})
	presentation_events_ready.emit(events.duplicate(true), _revision)


func _apply_result_once() -> void:
	if _revision == _result_applied_revision:
		return
	_result_applied_revision = _revision
	var winner := String(_result.get("winner", "tie"))
	battles_played += 1
	if winner == "player":
		win_streak += 1
	else:
		win_streak = 0
	difficulty = RULES.next_difficulty(difficulty, winner)


func _set_retryable_error(code: String, message: String) -> void:
	_awaiting_retry = true
	_practice_error = {
		"code": code,
		"message": message,
		"retriable": true,
	}
	practice_error_changed.emit(_practice_error.duplicate(true))


func _clear_error() -> void:
	if _practice_error.is_empty():
		return
	_practice_error.clear()
	practice_error_changed.emit({})


func _reset_battle_state() -> void:
	_battle_id = ""
	_revision = -1
	_state_token = ""
	_snapshot.clear()
	_choice_request.clear()
	_queued_choice_request.clear()
	_result.clear()
	_result_applied_revision = -1
	_clear_error()


func _set_state(next_state: String) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(_state)


func _connect_transport() -> void:
	if is_instance_valid(_transport) and _transport.has_signal("transport_completed"):
		_transport.connect("transport_completed", Callable(self, "_on_transport_completed"))


func _disconnect_transport() -> void:
	if is_instance_valid(_transport) and _transport.has_signal("transport_completed"):
		var callback := Callable(self, "_on_transport_completed")
		if _transport.is_connected("transport_completed", callback):
			_transport.disconnect("transport_completed", callback)


func _member_ids(team: Array) -> Array[String]:
	var ids: Array[String] = []
	for value: Variant in team:
		if typeof(value) == TYPE_DICTIONARY:
			ids.append(String((value as Dictionary).get("memberId", "")))
	return ids


func _network_error_code() -> String:
	if OS.get_name() == "Web":
		var online: Variant = JavaScriptBridge.eval("navigator.onLine", true)
		if typeof(online) == TYPE_BOOL and not bool(online):
			return "offline"
	return "network_error"
