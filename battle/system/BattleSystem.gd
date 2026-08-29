extends Node

## The single owner of PvE battle state, REST sessions, validation, retries,
## collection HP writeback, event ordering, and completion.

signal state_changed(state: int)
signal snapshot_changed(snapshot: Dictionary)
signal presentation_events_ready(events: Array, revision: int)
signal choice_request_changed(choice_request: Dictionary)
signal battle_ended(result: Dictionary)
signal battle_error_changed(error: Dictionary)

enum State {
	IDLE,
	CONNECTING,
	PRESENTING,
	AWAITING_PLAYER,
	SUBMITTING,
	ENDED,
	RETURNING,
}

const START_ROUTE := "/battles"
const ACTION_ROUTE := "/battles/actions"
const RETURN_SCENE_PATH := "res://demo/modular_ground_scene.tscn"
const MAX_RESPONSE_BYTES := 512 * 1024

var _state := State.IDLE
var _transport: Node
var _default_transport: BattleRestClient
var _owns_injected_transport := false

var _encounter: Resource
var _encounter_id := ""
var _forfeit_allowed := true
var _player_member_ids: Array[String] = []
var _opponent_member_ids: Array[String] = []
var _presentation_metadata_by_id: Dictionary = {}

# Sensitive session state. These values never enter a signal or public getter.
var _state_token := ""
var _pending_request_body := PackedByteArray()
var _pending_route := ""
var _pending_kind := ""
var _pending_action: Dictionary = {}

var _battle_id := ""
var _revision := -1
var _snapshot: Dictionary = {}
var _choice_request: Dictionary = {}
var _last_valid_choice_request: Dictionary = {}
var _result: Dictionary = {}
var _battle_error: Dictionary = {}

var _next_request_id := 1
var _inflight_request_id := -1
var _awaiting_retry := false


func _ready() -> void:
	_default_transport = BattleRestClient.new()
	_default_transport.name = "BattleRestClient"
	add_child(_default_transport)
	_set_transport(_default_transport)
	if GameInstance.has_signal("battle_return_finished"):
		GameInstance.battle_return_finished.connect(_on_battle_return_finished)


func get_state() -> int:
	return _state


func get_state_name() -> StringName:
	return State.keys()[_state].to_lower()


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func get_choice_request() -> Dictionary:
	return _choice_request.duplicate(true)


func get_battle_error() -> Dictionary:
	return _battle_error.duplicate(true)


func get_result() -> Dictionary:
	return _result.duplicate(true)


func is_forfeit_allowed() -> bool:
	return _forfeit_allowed


func begin_current_battle_scene() -> bool:
	if _state != State.IDLE:
		return false
	_clear_session_data()

	var providers := _providers_in_current_scene()
	if providers.size() != 1:
		_end_with_error(
			"invalid_encounter_provider",
			"The battle scene must contain exactly one encounter provider.",
			true
		)
		return false

	var encounter_value: Variant = providers[0].get("encounter")
	if not encounter_value is Resource:
		_end_with_error(
			"invalid_encounter",
			"The battle scene does not provide an encounter definition.",
			true
		)
		return false
	_encounter = encounter_value as Resource

	var encounter_errors := _validate_encounter(_encounter)
	if not encounter_errors.is_empty():
		_end_with_error(
			"invalid_encounter",
			String(encounter_errors[0]),
			true
		)
		return false

	_encounter_id = String(_encounter.get("encounter_id")).strip_edges()
	var launch_data := GameInstance.get_active_battle_data()
	var expected_encounter_id := String(
		launch_data.get("encounter_id", "")
	).strip_edges()
	if not expected_encounter_id.is_empty() and expected_encounter_id != _encounter_id:
		_end_with_error(
			"encounter_id_mismatch",
			"The loaded battle scene does not match the requested encounter.",
			true
		)
		return false
	_forfeit_allowed = (
		bool(_encounter.call("allows_forfeit"))
		if _encounter.has_method("allows_forfeit")
		else true
	)

	var player_team_value: Variant = CollectionSystem.get_battle_party_members()
	if typeof(player_team_value) != TYPE_ARRAY:
		_end_with_error(
			"invalid_player_party",
			_collection_error("The player party is not ready for battle."),
			true
		)
		return false
	var player_team := player_team_value as Array
	if player_team.is_empty() or not _has_living_member(player_team):
		_end_with_error(
			"all_player_members_fainted",
			"All party members have fainted. Return and heal before battling.",
			true
		)
		return false

	var opponent_team := _encounter_server_team(_encounter)
	if opponent_team.is_empty() or not _has_living_member(opponent_team):
		_end_with_error(
			"invalid_encounter",
			"The encounter has no battle-ready opponent party.",
			true
		)
		return false

	_player_member_ids = _member_ids(player_team)
	_opponent_member_ids = _member_ids(opponent_team)
	if _player_member_ids.size() != player_team.size() or _opponent_member_ids.size() != opponent_team.size():
		_end_with_error(
			"invalid_team_member_id",
			"A battle party contains an invalid or duplicate member ID.",
			true
		)
		return false
	_capture_presentation_metadata(player_team, _encounter)

	var opponent_api_name := String(_encounter.get("api_name")).strip_edges()
	var request := {
		"player": {
			"name": "Player",
			"team": player_team.duplicate(true),
		},
		"opponent": {
			"name": opponent_api_name,
			"team": opponent_team.duplicate(true),
		},
	}
	_prepare_pending_request(START_ROUTE, request, "start", {})
	_set_state(State.CONNECTING)
	return _dispatch_pending_request()


func choose_move(move_index: int) -> bool:
	if _state != State.AWAITING_PLAYER or String(_choice_request.get("type")) != "move":
		return false
	for move_value: Variant in _choice_request.get("moves", []):
		if typeof(move_value) != TYPE_DICTIONARY:
			continue
		var move := move_value as Dictionary
		if int(move.get("moveIndex", 0)) == move_index and not bool(move.get("disabled", true)):
			return _submit_action({"type": "move", "moveIndex": move_index})
	return false


func choose_switch(member_id: String) -> bool:
	if _state != State.AWAITING_PLAYER or member_id.is_empty():
		return false
	for option_value: Variant in _choice_request.get("switchOptions", []):
		if (
			typeof(option_value) == TYPE_DICTIONARY
			and String((option_value as Dictionary).get("memberId", "")) == member_id
		):
			return _submit_action({"type": "switch", "memberId": member_id})
	return false


func forfeit() -> bool:
	if _state != State.AWAITING_PLAYER or not _forfeit_allowed:
		return false
	return _submit_action({"type": "forfeit"})


func retry_pending_request() -> bool:
	if not _awaiting_retry or _inflight_request_id >= 0 or _pending_request_body.is_empty():
		return false
	_clear_battle_error()
	return _dispatch_pending_request()


func acknowledge_events_presented(presented_revision: int) -> bool:
	if _state != State.PRESENTING or presented_revision != _revision:
		return false
	if not _result.is_empty():
		_choice_request.clear()
		choice_request_changed.emit({})
		_set_state(State.ENDED)
		battle_ended.emit(_result.duplicate(true))
		return true

	_choice_request = _last_valid_choice_request.duplicate(true)
	_set_state(State.AWAITING_PLAYER)
	choice_request_changed.emit(_choice_request.duplicate(true))
	return true


func continue_after_result() -> bool:
	if (
		_state != State.ENDED
		and not bool(_battle_error.get("can_return", false))
	):
		return false
	_set_state(State.RETURNING)
	_cancel_inflight()
	var suppression_id := _encounter_id
	_clear_sensitive_session_state()
	if not GameInstance.return_from_battle(RETURN_SCENE_PATH, suppression_id):
		_end_with_error(
			"return_failed",
			"The overworld could not be loaded.",
			false
		)
		return false
	# The authored return transition is now committed. Remove all remaining
	# session identity and presentation data before the overworld can reveal.
	_clear_session_data()
	snapshot_changed.emit({})
	choice_request_changed.emit({})
	battle_error_changed.emit({})
	return true


## Test-only dependency injection. Production always uses BattleRestClient.
func set_transport_for_testing(transport: Node) -> bool:
	if _state != State.IDLE or transport == null:
		return false
	_cancel_inflight()
	if _owns_injected_transport and is_instance_valid(_transport):
		_transport.queue_free()
	_owns_injected_transport = transport.get_parent() == null
	if _owns_injected_transport:
		add_child(transport)
	_set_transport(transport)
	return true


func restore_default_transport_after_testing() -> bool:
	if _state != State.IDLE:
		return false
	if _owns_injected_transport and is_instance_valid(_transport):
		_transport.queue_free()
	_owns_injected_transport = false
	_set_transport(_default_transport)
	return true


func reset_for_testing() -> void:
	_cancel_inflight()
	_clear_session_data()
	_set_state(State.IDLE)


func _submit_action(action: Dictionary) -> bool:
	if _state_token.is_empty() or _inflight_request_id >= 0:
		return false
	_last_valid_choice_request = _choice_request.duplicate(true)
	_choice_request.clear()
	choice_request_changed.emit({})
	_clear_battle_error()
	var request := {
		"stateToken": _state_token,
		"action": action.duplicate(true),
	}
	_prepare_pending_request(ACTION_ROUTE, request, "action", action)
	_set_state(State.SUBMITTING)
	return _dispatch_pending_request()


func _prepare_pending_request(
	route: String,
	payload: Dictionary,
	kind: String,
	action: Dictionary
) -> void:
	_pending_route = route
	_pending_request_body = JSON.stringify(payload).to_utf8_buffer()
	_pending_kind = kind
	_pending_action = action.duplicate(true)
	_awaiting_retry = false


func _dispatch_pending_request() -> bool:
	if not is_instance_valid(_transport) or not _transport.has_method("post_json_bytes"):
		_end_with_error("transport_unavailable", "The battle service is unavailable.", _pending_kind == "start")
		return false
	var request_id := _next_request_id
	_next_request_id += 1
	_inflight_request_id = request_id
	var error: Error = _transport.call(
		"post_json_bytes",
		_pending_route,
		_pending_request_body,
		request_id
	)
	if error != OK:
		_inflight_request_id = -1
		_set_retryable_error("network_error", "The battle service could not be reached.")
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
		_end_with_error("response_too_large", "The battle service response is too large.", _pending_kind == "start")
		return
	if result != HTTPRequest.RESULT_SUCCESS:
		_set_retryable_error("network_error", "The battle service request was interrupted.")
		return
	if response_code < 200 or response_code >= 300:
		_handle_http_error(response_code, body)
		return

	var parsed := _parse_json(body)
	if not parsed.ok:
		_end_with_error("malformed_response", "The battle service returned malformed JSON.", _pending_kind == "start")
		return
	var expected_revision := 0 if _pending_kind == "start" else _revision + 1
	var validation := BattleDtoValidator.validate_response(parsed.value, {
		"battle_id": "" if _pending_kind == "start" else _battle_id,
		"revision": expected_revision,
		"player_member_ids": _player_member_ids,
		"opponent_member_ids": _opponent_member_ids,
	})
	if not validation.ok:
		_end_with_error(
			String(validation.code),
			String(validation.message),
			_pending_kind == "start"
		)
		return
	_accept_response(validation.response)


func _accept_response(response: Dictionary) -> void:
	var player_snapshot := (response.parties as Dictionary).player as Array
	if not CollectionSystem.apply_battle_health_snapshot(player_snapshot):
		_end_with_error(
			"collection_writeback_failed",
			_collection_error("The updated party health could not be saved."),
			_pending_kind == "start"
		)
		return

	_battle_id = String(response.battleId)
	_revision = int(response.revision)
	_state_token = String(response.get("stateToken", ""))
	_last_valid_choice_request = (
		(response.request as Dictionary).duplicate(true)
		if typeof(response.request) == TYPE_DICTIONARY
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
	_enrich_snapshot_presentation(_snapshot)
	if not _result.is_empty():
		_snapshot["result"] = _result.duplicate(true)

	var translated_events := BattleEventTranslator.translate(response.events)
	_clear_pending_request()
	_clear_battle_error()
	_set_state(State.PRESENTING)
	snapshot_changed.emit(_snapshot.duplicate(true))
	choice_request_changed.emit({})
	presentation_events_ready.emit(translated_events.duplicate(true), _revision)


func _handle_http_error(response_code: int, body: PackedByteArray) -> void:
	if response_code >= 500:
		_set_retryable_error("server_error", "The battle service is temporarily unavailable.")
		return
	var code := "http_error"
	var message := "The battle service rejected the request."
	var parsed := _parse_json(body)
	if parsed.ok and typeof(parsed.value) == TYPE_DICTIONARY:
		var error_value: Variant = (parsed.value as Dictionary).get("error")
		if typeof(error_value) == TYPE_DICTIONARY:
			var error_body := error_value as Dictionary
			code = String(error_body.get("code", code)).strip_edges()
			message = String(error_body.get("message", message)).strip_edges()
	if code.is_empty():
		code = "http_error"
	if message.is_empty():
		message = "The battle service rejected the request."

	if response_code == 422 and code == "invalid_action" and _pending_kind == "action":
		_clear_pending_request()
		_choice_request = _last_valid_choice_request.duplicate(true)
		_set_state(State.AWAITING_PLAYER)
		_set_battle_error({
			"code": code,
			"message": message,
			"retriable": false,
			"can_return": false,
			"during_start": false,
		})
		choice_request_changed.emit(_choice_request.duplicate(true))
		return

	_end_with_error(code, message, _pending_kind == "start")


func _set_retryable_error(code: String, message: String) -> void:
	_awaiting_retry = true
	_set_battle_error({
		"code": code,
		"message": message,
		"retriable": true,
		"can_return": true,
		"during_start": _pending_kind == "start",
	})


func _end_with_error(code: String, message: String, during_start: bool) -> void:
	_cancel_inflight()
	_clear_sensitive_session_state()
	_choice_request.clear()
	_last_valid_choice_request.clear()
	_result.clear()
	_awaiting_retry = false
	_set_state(State.ENDED)
	choice_request_changed.emit({})
	_set_battle_error({
		"code": code,
		"message": message,
		"retriable": false,
		"can_return": true,
		"during_start": during_start,
	})


func _set_battle_error(error: Dictionary) -> void:
	_battle_error = error.duplicate(true)
	battle_error_changed.emit(_battle_error.duplicate(true))


func _clear_battle_error() -> void:
	if _battle_error.is_empty():
		return
	_battle_error.clear()
	battle_error_changed.emit({})


func _set_state(next_state: int) -> void:
	if _state == next_state:
		return
	_state = next_state
	state_changed.emit(_state)


func _set_transport(transport: Node) -> void:
	if is_instance_valid(_transport) and _transport.has_signal("transport_completed"):
		var callback := Callable(self, "_on_transport_completed")
		if _transport.is_connected("transport_completed", callback):
			_transport.disconnect("transport_completed", callback)
	_transport = transport
	if is_instance_valid(_transport) and _transport.has_signal("transport_completed"):
		_transport.connect("transport_completed", Callable(self, "_on_transport_completed"))


func _providers_in_current_scene() -> Array[Node]:
	var providers: Array[Node] = []
	var current_scene := get_tree().current_scene
	if current_scene == null:
		return providers
	for candidate: Node in get_tree().get_nodes_in_group("battle_encounter_provider"):
		if candidate == current_scene or current_scene.is_ancestor_of(candidate):
			providers.append(candidate)
	return providers


func _validate_encounter(encounter: Resource) -> PackedStringArray:
	if encounter.has_method("validate"):
		var result: Variant = encounter.call("validate")
		if typeof(result) == TYPE_PACKED_STRING_ARRAY:
			return result as PackedStringArray
		if typeof(result) == TYPE_ARRAY:
			var errors := PackedStringArray()
			for value: Variant in result as Array:
				errors.append(String(value))
			return errors
	return PackedStringArray(["Encounter resource does not provide validation."])


func _encounter_server_team(encounter: Resource) -> Array:
	if encounter.has_method("to_server_team"):
		var result: Variant = encounter.call("to_server_team")
		return (result as Array).duplicate(true) if typeof(result) == TYPE_ARRAY else []
	if encounter.has_method("get_server_team"):
		var result: Variant = encounter.call("get_server_team")
		return (result as Array).duplicate(true) if typeof(result) == TYPE_ARRAY else []
	return []


func _has_living_member(team: Array) -> bool:
	for value: Variant in team:
		if typeof(value) == TYPE_DICTIONARY and float((value as Dictionary).get("health", 0.0)) > 0.0:
			return true
	return false


func _member_ids(team: Array) -> Array[String]:
	var ids: Array[String] = []
	var seen := {}
	for value: Variant in team:
		if typeof(value) != TYPE_DICTIONARY:
			return []
		var member_id := String((value as Dictionary).get("memberId", "")).strip_edges()
		if member_id.is_empty() or seen.has(member_id):
			return []
		seen[member_id] = true
		ids.append(member_id)
	return ids


func _capture_presentation_metadata(
	player_team: Array,
	encounter: Resource
) -> void:
	_presentation_metadata_by_id.clear()
	for value: Variant in player_team:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var member := value as Dictionary
		var member_id := String(member.get("memberId", ""))
		var profile: Dictionary = CollectionSystem.get_battle_profile(member_id)
		if not profile.is_empty():
			var pcl: Dictionary = CollectionSystem.get_pcl(member_id)
			_presentation_metadata_by_id[member_id] = {
				"pokemonId": int(pcl.get("pokemonId", 0)),
				"spriteId": String(profile.get("spriteId", "")),
			}
	if encounter.has_method("to_presentation_data"):
		var presentation_value: Variant = encounter.call("to_presentation_data")
		if typeof(presentation_value) == TYPE_DICTIONARY:
			for value: Variant in (presentation_value as Dictionary).get("members", []):
				if typeof(value) != TYPE_DICTIONARY:
					continue
				var member := value as Dictionary
				var member_id := String(member.get("memberId", ""))
				_presentation_metadata_by_id[member_id] = {
					"pokemonId": int(member.get("pokemonId", 0)),
					"spriteId": String(member.get("spriteId", "")),
					"spriteOverride": String(member.get("spriteOverride", "")),
				}


func _enrich_snapshot_presentation(snapshot: Dictionary) -> void:
	var parties_value: Variant = snapshot.get("parties")
	if typeof(parties_value) != TYPE_DICTIONARY:
		return
	var parties := parties_value as Dictionary
	for side in ["player", "opponent"]:
		var members_value: Variant = parties.get(side)
		if typeof(members_value) != TYPE_ARRAY:
			continue
		for value: Variant in members_value as Array:
			if typeof(value) != TYPE_DICTIONARY:
				continue
			var member := value as Dictionary
			var metadata_value: Variant = _presentation_metadata_by_id.get(
				String(member.get("memberId", ""))
			)
			if typeof(metadata_value) != TYPE_DICTIONARY:
				continue
			for key: Variant in (metadata_value as Dictionary):
				var metadata: Variant = (metadata_value as Dictionary)[key]
				if typeof(metadata) == TYPE_STRING and (metadata as String).is_empty():
					continue
				if typeof(metadata) in [TYPE_INT, TYPE_FLOAT] and float(metadata) == 0.0:
					continue
				member[key] = metadata


func _collection_error(fallback: String) -> String:
	if CollectionSystem.has_method("get_last_error"):
		var message := String(CollectionSystem.get_last_error()).strip_edges()
		if not message.is_empty():
			return message
	return fallback


func _parse_json(body: PackedByteArray) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(body.get_string_from_utf8()) != OK:
		return {"ok": false}
	return {"ok": true, "value": parser.data}


func _cancel_inflight() -> void:
	_inflight_request_id = -1
	if is_instance_valid(_transport) and _transport.has_method("cancel_active_request"):
		_transport.call("cancel_active_request")


func _clear_pending_request() -> void:
	_pending_request_body = PackedByteArray()
	_pending_route = ""
	_pending_kind = ""
	_pending_action.clear()
	_awaiting_retry = false


func _clear_sensitive_session_state() -> void:
	_state_token = ""
	_clear_pending_request()


func _clear_session_data() -> void:
	_clear_sensitive_session_state()
	_encounter = null
	_encounter_id = ""
	_forfeit_allowed = true
	_player_member_ids.clear()
	_opponent_member_ids.clear()
	_presentation_metadata_by_id.clear()
	_battle_id = ""
	_revision = -1
	_snapshot.clear()
	_choice_request.clear()
	_last_valid_choice_request.clear()
	_result.clear()
	_battle_error.clear()
	_inflight_request_id = -1
	_awaiting_retry = false


func _on_battle_return_finished() -> void:
	_clear_session_data()
	_set_state(State.IDLE)
