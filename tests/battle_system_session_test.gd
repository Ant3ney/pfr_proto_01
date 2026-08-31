extends Node


class FakeBattleTransport:
	extends Node

	signal transport_completed(
		request_id: int,
		result: int,
		response_code: int,
		headers: PackedStringArray,
		body: PackedByteArray
	)

	var calls: Array[Dictionary] = []
	var active_request_id := -1


	func post_json_bytes(route: String, body: PackedByteArray, request_id: int) -> Error:
		active_request_id = request_id
		calls.append({
			"route": route,
			"body": body.duplicate(),
			"request_id": request_id,
		})
		return OK


	func cancel_active_request() -> void:
		active_request_id = -1


	func complete_json(
		value: Variant,
		response_code := 200,
		result := HTTPRequest.RESULT_SUCCESS,
		request_id := -1
	) -> void:
		var completed_id := active_request_id if request_id < 0 else request_id
		if completed_id == active_request_id:
			active_request_id = -1
		transport_completed.emit(
			completed_id,
			result,
			response_code,
			PackedStringArray(["Content-Type: application/json"]),
			JSON.stringify(value).to_utf8_buffer()
		)


	func complete_raw(body: PackedByteArray, response_code := 200) -> void:
		var completed_id := active_request_id
		active_request_id = -1
		transport_completed.emit(
			completed_id,
			HTTPRequest.RESULT_SUCCESS,
			response_code,
			PackedStringArray(),
			body
		)


var _failures: Array[String] = []
var _transport := FakeBattleTransport.new()
var _original_collection: Array[Dictionary] = []
var _captured_snapshots: Array[Dictionary] = []
var _captured_choices: Array[Dictionary] = []
var _captured_events: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_original_collection = CollectionSystem.get_save_data()
	BattleSystem.reset_for_testing()
	_check(
		BattleSystem.set_transport_for_testing(_transport),
		"The fake transport should be injectable while idle."
	)
	BattleSystem.snapshot_changed.connect(
		func(snapshot: Dictionary) -> void:
			_captured_snapshots.append(snapshot)
	)
	BattleSystem.choice_request_changed.connect(
		func(request: Dictionary) -> void:
			_captured_choices.append(request)
	)
	BattleSystem.presentation_events_ready.connect(
		func(events: Array, revision: int) -> void:
			_captured_events.append({"events": events, "revision": revision})
	)

	await _verify_start_and_exact_retry()
	await _verify_invalid_action_and_forfeit()
	await _verify_incompatible_response_ends_locally()

	BattleSystem.reset_for_testing()
	BattleSystem.restore_default_transport_after_testing()
	CollectionSystem.load_save_data(_original_collection)
	if _failures.is_empty():
		print(
			"Battle system session test passed: start, validated presentation, exact "
			+ "retry, stale/duplicate callbacks, knockout XP, 422 recovery, forfeit, "
			+ "atomic collection writeback, "
			+ "and incompatible-response termination verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Battle system session test failed: %s" % failure)
	get_tree().quit(1)


func _verify_start_and_exact_retry() -> void:
	_check(BattleSystem.begin_current_battle_scene(), "Battle start should dispatch.")
	_check(BattleSystem.get_state() == BattleSystem.State.CONNECTING, "Start should enter CONNECTING.")
	_check(_transport.calls.size() == 1, "Start should issue exactly one request.")
	var start_call: Dictionary = _transport.calls.back()
	_check(start_call.route == "/battles", "Start should use the versioned battles route.")
	var start_request := JSON.parse_string((start_call.body as PackedByteArray).get_string_from_utf8()) as Dictionary
	_check(
		start_request.player.name == "Player",
		"The player API name should remain fixed to Player."
	)
	_check(
		(start_request.player.team as Array).size() == 6,
		"BattleSystem should read all six current party members from CollectionSystem."
	)
	_check(
		(start_request.opponent.team as Array).size() == 2,
		"BattleSystem should read Kyle's two-member authored encounter."
	)
	var strict_player_member := (start_request.player.team as Array)[0] as Dictionary
	var strict_player_keys: Array = strict_player_member.keys()
	strict_player_keys.sort()
	_check(
		strict_player_keys == ["health", "level", "memberId", "moves", "species"],
		"Local XP and Pokédex metadata must not leave the strict REST team DTO."
	)

	_transport.complete_json(_response_from_start(start_request, 0, false))
	await get_tree().process_frame
	_check(BattleSystem.get_state() == BattleSystem.State.PRESENTING, "A valid start should enter PRESENTING.")
	_check(not _captured_snapshots.is_empty(), "A valid start should emit a snapshot.")
	if not _captured_snapshots.is_empty():
		var presentation_snapshot: Dictionary = _captured_snapshots.back()
		var player_members: Array = presentation_snapshot.parties.player
		var opponent_members: Array = presentation_snapshot.parties.opponent
		_check(
			int((player_members[0] as Dictionary).get("pokemonId", 0)) == 484,
			"Player presentation metadata should retain Palkia's local Pokédex ID."
		)
		_check(
			int((opponent_members[0] as Dictionary).get("pokemonId", 0)) == 194,
			"Opponent presentation metadata should retain Wooper's authored Pokédex ID."
		)
		_check(
			not _contains_sensitive_key(presentation_snapshot),
			"Presentation snapshots must not expose the state token."
		)
		_captured_snapshots.back()["revision"] = 999
		_check(
			int(BattleSystem.get_snapshot().revision) == 0,
			"Signal snapshots should be isolated by a deep copy."
		)
	_check(
		BattleSystem.acknowledge_events_presented(0),
		"The accepted revision should unlock its choice only after acknowledgement."
	)
	_check(BattleSystem.get_state() == BattleSystem.State.AWAITING_PLAYER, "Acknowledgement should enter AWAITING_PLAYER.")

	_check(BattleSystem.choose_move(1), "A returned enabled move should be accepted.")
	_check(BattleSystem.get_state() == BattleSystem.State.SUBMITTING, "A move should enter SUBMITTING.")
	var first_action_call: Dictionary = _transport.calls.back()
	var original_action_bytes: PackedByteArray = first_action_call.body
	_transport.complete_json(
		{},
		0,
		HTTPRequest.RESULT_CANT_CONNECT
	)
	await get_tree().process_frame
	_check(bool(BattleSystem.get_battle_error().get("retriable", false)), "Transport failure should offer Retry.")
	_check(BattleSystem.retry_pending_request(), "Retry should redispatch the pending action.")
	var retry_call: Dictionary = _transport.calls.back()
	_check(
		(original_action_bytes as PackedByteArray) == (retry_call.body as PackedByteArray),
		"Retry must use the byte-identical action payload."
	)

	var palkia_id := String((start_request.player.team as Array)[0].memberId)
	var second_participant_id := String((start_request.player.team as Array)[1].memberId)
	var uninvolved_id := String((start_request.player.team as Array)[2].memberId)
	var palkia_xp_before := int(CollectionSystem.get_pcl(palkia_id).instanceStats.currentXp)
	var second_xp_before := int(CollectionSystem.get_pcl(second_participant_id).instanceStats.currentXp)
	var uninvolved_xp_before := int(CollectionSystem.get_pcl(uninvolved_id).instanceStats.currentXp)
	var action_response := _response_from_start(start_request, 1, false)
	(action_response.parties.player as Array)[0].active = false
	(action_response.parties.player as Array)[1].active = true
	(action_response.parties.opponent as Array)[0].hp = 0
	(action_response.parties.opponent as Array)[0].normalizedHealth = 0.0
	(action_response.parties.opponent as Array)[0].fainted = true
	(action_response.parties.opponent as Array)[0].active = false
	(action_response.parties.opponent as Array)[1].active = true
	action_response.request.activeMemberId = second_participant_id
	action_response.request.moves = []
	for move_value: Variant in (action_response.parties.player as Array)[1].moves:
		var move := (move_value as Dictionary).duplicate(true)
		move["disabled"] = false
		action_response.request.moves.append(move)
	action_response.request.switchOptions = []
	for member_value: Variant in action_response.parties.player:
		var member := member_value as Dictionary
		if String(member.memberId) != second_participant_id:
			action_response.request.switchOptions.append({"memberId": member.memberId})
	action_response.events = [
		"|drag|p1a: Mothim|Mothim, L3|100/100",
		"|faint|p2a: Wooper",
		"|switch|p2a: Magikarp|Magikarp, L3|100/100",
		"|turn|2",
	]
	var retry_request_id := int(retry_call.request_id)
	_transport.complete_json(action_response)
	await get_tree().process_frame
	_check(int(BattleSystem.get_snapshot().revision) == 1, "Successful retry should accept revision 1.")
	var expected_wooper_award := int(
		preload("res://battle/system/BattleExperience.gd").calculate_award(3, 3, 194).amount
	)
	_check(
		int(CollectionSystem.get_pcl(palkia_id).instanceStats.currentXp)
		== palkia_xp_before + expected_wooper_award,
		"The active participant should gain level-differential, species-multiplied XP on knockout."
	)
	_check(
		int(CollectionSystem.get_pcl(second_participant_id).instanceStats.currentXp)
		== second_xp_before + expected_wooper_award,
		"A switched-in participant should share the knockout XP."
	)
	_check(
		int(CollectionSystem.get_pcl(uninvolved_id).instanceStats.currentXp) == uninvolved_xp_before,
		"A party member that has not entered battle should not gain XP."
	)
	_check(
		float(BattleSystem.get_snapshot().parties.player[1].get("experienceProgress", -1.0)) > 0.0,
		"The accepted snapshot should expose copied XP progress for the battle HUD."
	)
	var has_experience_event := false
	for event_value: Variant in (_captured_events.back().events as Array):
		if typeof(event_value) == TYPE_DICTIONARY and String(event_value.get("type", "")) == "experience":
			has_experience_event = true
	_check(has_experience_event, "A knockout should enqueue a readable XP presentation event.")
	_transport.complete_json(_response_from_start(start_request, 2, false), 200, HTTPRequest.RESULT_SUCCESS, retry_request_id)
	await get_tree().process_frame
	_check(
		int(BattleSystem.get_snapshot().revision) == 1,
		"A duplicate callback should be ignored after the request completes."
	)
	_check(
		int(CollectionSystem.get_pcl(palkia_id).instanceStats.currentXp)
		== palkia_xp_before + expected_wooper_award,
		"A duplicate response callback must not award XP twice."
	)
	_check(
		int(CollectionSystem.get_pcl(second_participant_id).instanceStats.currentXp)
		== second_xp_before + expected_wooper_award,
		"A duplicate response callback must not double-award another participant."
	)
	BattleSystem.acknowledge_events_presented(1)


func _verify_invalid_action_and_forfeit() -> void:
	_check(BattleSystem.choose_move(1), "The restored revision-1 move should submit.")
	_transport.complete_json({
		"error": {"code": "invalid_action", "message": "That move is unavailable."},
	}, 422)
	await get_tree().process_frame
	_check(
		BattleSystem.get_state() == BattleSystem.State.AWAITING_PLAYER,
		"A 422 invalid action should restore AWAITING_PLAYER."
	)
	_check(
		String(BattleSystem.get_choice_request().get("type", "")) == "move",
		"A 422 invalid action should restore the last valid request."
	)

	_check(BattleSystem.forfeit(), "Confirmed forfeit should submit through BattleSystem.")
	var action_call: Dictionary = _transport.calls.back()
	var action_request := JSON.parse_string((action_call.body as PackedByteArray).get_string_from_utf8()) as Dictionary
	var start_request := JSON.parse_string((_transport.calls[0].body as PackedByteArray).get_string_from_utf8()) as Dictionary
	var ended := _response_from_start(start_request, 2, true)
	ended.events = ["|", "|win|Kyle"]
	ended.result = {"winner": "opponent", "reason": "forfeit"}
	_check(
		String(action_request.action.type) == "forfeit",
		"Forfeit should send only the typed forfeit action."
	)
	_transport.complete_json(ended)
	await get_tree().process_frame
	_check(BattleSystem.get_state() == BattleSystem.State.PRESENTING, "Ended response events should still present first.")
	BattleSystem.acknowledge_events_presented(2)
	_check(BattleSystem.get_state() == BattleSystem.State.ENDED, "Ended events should lead to ENDED.")
	_check(BattleSystem.get_result().winner == "opponent", "The server result should be authoritative.")


func _verify_incompatible_response_ends_locally() -> void:
	BattleSystem.reset_for_testing()
	_transport.calls.clear()
	_check(BattleSystem.begin_current_battle_scene(), "A reset session should start again.")
	var start_request := JSON.parse_string((_transport.calls.back().body as PackedByteArray).get_string_from_utf8()) as Dictionary
	var incompatible := _response_from_start(start_request, 0, false)
	incompatible.engineVersion = "future-engine"
	_transport.complete_json(incompatible)
	await get_tree().process_frame
	_check(BattleSystem.get_state() == BattleSystem.State.ENDED, "Version mismatch should end the local session.")
	_check(
		String(BattleSystem.get_battle_error().get("code", "")) == "version_mismatch",
		"Version mismatch should expose a safe local error code."
	)
	_check(not bool(BattleSystem.get_battle_error().get("retriable", true)), "Version mismatch must not offer retry.")


func _response_from_start(start_request: Dictionary, revision: int, ended: bool) -> Dictionary:
	var player_members: Array[Dictionary] = []
	var opponent_members: Array[Dictionary] = []
	for index in range((start_request.player.team as Array).size()):
		var member := (start_request.player.team as Array)[index] as Dictionary
		player_members.append(_snapshot_member(member, index == 0, true))
	for index in range((start_request.opponent.team as Array).size()):
		var member := (start_request.opponent.team as Array)[index] as Dictionary
		opponent_members.append(_snapshot_member(member, index == 0, false))
	var request_moves: Array[Dictionary] = []
	for move_value: Variant in player_members[0].moves as Array:
		var move := move_value as Dictionary
		request_moves.append({
			"moveIndex": move.moveIndex,
			"id": move.id,
			"name": move.name,
			"pp": move.pp,
			"maxPp": move.maxPp,
			"disabled": false,
		})
	var switch_options: Array[Dictionary] = []
	for member_value: Variant in player_members.slice(1):
		var member := member_value as Dictionary
		switch_options.append({"memberId": member.memberId})
	var request := {
		"type": "move",
		"activeMemberId": String(player_members[0].memberId),
		"moves": request_moves,
		"switchOptions": switch_options,
	}
	var response := {
		"apiVersion": "v1",
		"engineVersion": "0.11.11",
		"formatVersion": "pfr-gen9-singles-v1",
		"battleId": "00000000-0000-4000-8000-000000000777",
		"revision": revision,
		"phase": "ended" if ended else "awaiting_player",
		"events": ["|start", "|turn|%d" % (revision + 1)],
		"request": null if ended else request,
		"parties": {
			"player": player_members,
			"opponent": opponent_members,
		},
	}
	if ended:
		response.result = {"winner": "player", "reason": "all_pokemon_fainted"}
	else:
		response.stateToken = "opaque-test-token-%d" % revision
	return response


func _snapshot_member(input: Dictionary, active: bool, include_moves: bool) -> Dictionary:
	var max_hp := 100
	var hp := int(round(float(input.health) * max_hp))
	var result := {
		"memberId": String(input.memberId),
		"species": String(input.species),
		"nickname": String(input.species),
		"level": int(input.level),
		"hp": hp,
		"maxHp": max_hp,
		"normalizedHealth": float(hp) / float(max_hp),
		"fainted": hp == 0,
		"active": active,
		"status": null,
	}
	if include_moves:
		var moves: Array[Dictionary] = []
		for index in range((input.moves as Array).size()):
			var move_id := String((input.moves as Array)[index])
			moves.append({
				"moveIndex": index + 1,
				"id": move_id,
				"name": move_id.capitalize(),
				"pp": 10,
				"maxPp": 10,
			})
		result.moves = moves
	return result


func _contains_sensitive_key(value: Variant) -> bool:
	if typeof(value) == TYPE_DICTIONARY:
		for key: Variant in value as Dictionary:
			if String(key).to_lower().contains("token"):
				return true
			if _contains_sensitive_key((value as Dictionary)[key]):
				return true
	elif typeof(value) == TYPE_ARRAY:
		for child: Variant in value as Array:
			if _contains_sensitive_key(child):
				return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
