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


	func emit_duplicate_json(value: Variant, request_id: int) -> void:
		transport_completed.emit(
			request_id,
			HTTPRequest.RESULT_SUCCESS,
			200,
			PackedStringArray(["Content-Type: application/json"]),
			JSON.stringify(value).to_utf8_buffer()
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
	var xp_share_holder := CollectionSystem.add_pokemon(443, 7, 1.0, 639, 0)
	var xp_share_holder_id := String(xp_share_holder.get("pclID", ""))
	_check(
		not xp_share_holder.is_empty()
		and CollectionSystem.move_to_party_slot(xp_share_holder_id, 2)
		and CollectionSystem.set_held_item(
			xp_share_holder_id,
			"exp-share"
		),
		"The XP Share fixture should put a held Lv. 7 Gible one XP award from Lv. 8."
	)
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
	await _verify_second_knockout_does_not_repeat_level_up()
	await _verify_invalid_action_and_forfeit()
	await _verify_fainted_switch_participant_receives_xp()
	await _verify_incompatible_response_ends_locally()
	await _verify_fainted_drag_participant_receives_xp()

	BattleSystem.reset_for_testing()
	BattleSystem.restore_default_transport_after_testing()
	CollectionSystem.load_save_data(_original_collection)
	if _failures.is_empty():
		print(
			"Battle system session test passed: start, validated presentation, exact "
			+ "retry, stale/duplicate callbacks, one Gible Lv. 8 announcement across two knockouts, "
			+ "persistent appeared-participant XP through switches and forced entry, "
			+ "422 recovery, forfeit, "
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
	var uninvolved_id := String((start_request.player.team as Array)[1].memberId)
	var second_participant_id := String((start_request.player.team as Array)[2].memberId)
	var palkia_xp_before := int(CollectionSystem.get_pcl(palkia_id).instanceStats.currentXp)
	var second_xp_before := int(CollectionSystem.get_pcl(second_participant_id).instanceStats.currentXp)
	var xp_share_xp_before := int(CollectionSystem.get_pcl(uninvolved_id).instanceStats.currentXp)
	var action_response := _response_from_start(start_request, 1, false)
	(action_response.parties.player as Array)[0].active = false
	(action_response.parties.player as Array)[2].active = true
	(action_response.parties.opponent as Array)[0].hp = 0
	(action_response.parties.opponent as Array)[0].normalizedHealth = 0.0
	(action_response.parties.opponent as Array)[0].fainted = true
	(action_response.parties.opponent as Array)[0].active = false
	(action_response.parties.opponent as Array)[1].active = true
	action_response.request.activeMemberId = second_participant_id
	action_response.request.moves = []
	for move_value: Variant in (action_response.parties.player as Array)[2].moves:
		var move := (move_value as Dictionary).duplicate(true)
		move["disabled"] = false
		action_response.request.moves.append(move)
	action_response.request.switchOptions = []
	for member_value: Variant in action_response.parties.player:
		var member := member_value as Dictionary
		if String(member.memberId) != second_participant_id:
			action_response.request.switchOptions.append({"memberId": member.memberId})
	action_response.events = [
		"|drag|p1a: Hoothoot|Hoothoot, L3|100/100",
		"|faint|p2a: Wooper",
		"|switch|p2a: Magikarp|Magikarp, L3|100/100",
		"|turn|2",
	]
	var retry_request_id := int(retry_call.request_id)
	_transport.complete_json(action_response)
	await get_tree().process_frame
	_check(int(BattleSystem.get_snapshot().revision) == 1, "Successful retry should accept revision 1.")
	var expected_wooper_award := int(
		preload("res://game/battle/system/battle_experience.gd").calculate_award(3, 3, 194).amount
	)
	var expected_xp_share_award := maxi(roundi(float(
		preload("res://game/battle/system/battle_experience.gd").calculate_award(7, 3, 194).amount
	) * 0.5), 1)
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
		int(CollectionSystem.get_pcl(uninvolved_id).instanceStats.currentXp)
		== xp_share_xp_before + expected_xp_share_award,
		"A benched Party Slot 2 Gible holding Exp. Share should gain half of its own knockout XP."
	)
	_check(
		int(CollectionSystem.get_pcl(uninvolved_id).instanceStats.level) == 8,
		"The first knockout should move the near-threshold Gible from Lv. 7 to Lv. 8."
	)
	_check(
		float(BattleSystem.get_snapshot().parties.player[1].get("experienceProgress", -1.0)) > 0.0,
		"The accepted snapshot should expose copied XP progress for the battle HUD."
	)
	var has_experience_event := false
	var has_xp_share_event := false
	for event_value: Variant in (_captured_events.back().events as Array):
		if typeof(event_value) == TYPE_DICTIONARY and String(event_value.get("type", "")) == "experience":
			has_experience_event = true
			if (
				String(event_value.get("source", "")) == "exp_share"
				and String(event_value.get("memberId", "")) == uninvolved_id
			):
				var xp_share_message := String(event_value.get("message", ""))
				has_xp_share_event = (
					"Gible" in xp_share_message
					and "Exp. Share" in xp_share_message
					and "grew to Lv. 8" in xp_share_message
					and "Lv. 8 progress:" in xp_share_message
				)
	_check(has_experience_event, "A knockout should enqueue a readable XP presentation event.")
	_check(
		has_xp_share_event,
		"Gible's first XP event should identify the Exp. Share and announce Lv. 8 once."
	)
	var captured_event_count := _captured_events.size()
	_transport.emit_duplicate_json(
		_response_from_start(start_request, 2, false),
		retry_request_id
	)
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
	_check(
		int(CollectionSystem.get_pcl(uninvolved_id).instanceStats.currentXp)
		== xp_share_xp_before + expected_xp_share_award,
		"A duplicate response callback must not double-award the Exp. Share holder."
	)
	_check(
		_captured_events.size() == captured_event_count,
		"A duplicate response callback must not enqueue the level-up presentation twice."
	)
	BattleSystem.acknowledge_events_presented(1)


func _verify_second_knockout_does_not_repeat_level_up() -> void:
	_check(BattleSystem.choose_move(1), "The revision-1 move should submit the second knockout.")
	var start_request := JSON.parse_string(
		(_transport.calls[0].body as PackedByteArray).get_string_from_utf8()
	) as Dictionary
	var gible_id := String((start_request.player.team as Array)[1].memberId)
	var gible_xp_before := int(CollectionSystem.get_pcl(gible_id).instanceStats.currentXp)
	var ended := _response_from_start(start_request, 2, true)
	for opponent_value: Variant in ended.parties.opponent:
		var opponent := opponent_value as Dictionary
		opponent.hp = 0
		opponent.normalizedHealth = 0.0
		opponent.fainted = true
		opponent.active = false
	ended.events = ["|faint|p2a: Magikarp", "|win|Kyle"]
	_transport.complete_json(ended)
	await get_tree().process_frame
	_check(
		BattleSystem.get_state() == BattleSystem.State.PRESENTING,
		"The final knockout should present before the battle ends."
	)
	_check(
		int(CollectionSystem.get_pcl(gible_id).instanceStats.currentXp) > gible_xp_before,
		"Gible should receive a second per-knockout Exp. Share award."
	)
	var second_message := ""
	for event_value: Variant in (_captured_events.back().events as Array):
		if (
			typeof(event_value) == TYPE_DICTIONARY
			and String(event_value.get("type", "")) == "experience"
			and String(event_value.get("memberId", "")) == gible_id
		):
			second_message = String(event_value.get("message", ""))
	_check(
		not second_message.is_empty()
		and "grew to Lv. 8" not in second_message
		and "Lv. 8 progress:" in second_message
		and "XP to Lv. 9" in second_message,
		"The next knockout should show Lv. 8 progress without repeating the Lv. 8 announcement."
	)
	_check(
		_count_level_announcements(gible_id, 8) == 1,
		"The complete two-knockout battle should contain exactly one Gible Lv. 8 announcement."
	)
	_check(
		BattleSystem.acknowledge_events_presented(2),
		"The final knockout presentation should acknowledge revision 2."
	)
	_check(BattleSystem.get_state() == BattleSystem.State.ENDED, "Two knockouts should end Kyle's battle.")


func _verify_invalid_action_and_forfeit() -> void:
	BattleSystem.reset_for_testing()
	_transport.calls.clear()
	_check(BattleSystem.begin_current_battle_scene(), "The invalid-action session should start.")
	var start_request := JSON.parse_string(
		(_transport.calls.back().body as PackedByteArray).get_string_from_utf8()
	) as Dictionary
	_transport.complete_json(_response_from_start(start_request, 0, false))
	await get_tree().process_frame
	_check(
		BattleSystem.acknowledge_events_presented(0),
		"The invalid-action session should acknowledge its start revision."
	)
	_check(BattleSystem.choose_move(1), "The restored revision-0 move should submit.")
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
	var ended := _response_from_start(start_request, 1, true)
	ended.events = ["|", "|win|Kyle"]
	ended.result = {"winner": "opponent", "reason": "forfeit"}
	_check(
		String(action_request.action.type) == "forfeit",
		"Forfeit should send only the typed forfeit action."
	)
	_transport.complete_json(ended)
	await get_tree().process_frame
	_check(BattleSystem.get_state() == BattleSystem.State.PRESENTING, "Ended response events should still present first.")
	BattleSystem.acknowledge_events_presented(1)
	_check(BattleSystem.get_state() == BattleSystem.State.ENDED, "Ended events should lead to ENDED.")
	_check(BattleSystem.get_result().winner == "opponent", "The server result should be authoritative.")


func _verify_fainted_switch_participant_receives_xp() -> void:
	BattleSystem.reset_for_testing()
	_transport.calls.clear()
	_check(BattleSystem.begin_current_battle_scene(), "The switch-participation session should start.")
	var start_request := JSON.parse_string(
		(_transport.calls.back().body as PackedByteArray).get_string_from_utf8()
	) as Dictionary
	_transport.complete_json(_response_from_start(start_request, 0, false))
	await get_tree().process_frame
	_check(
		BattleSystem.acknowledge_events_presented(0),
		"The switch-participation session should acknowledge its start revision."
	)

	var player_team := start_request.player.team as Array
	var original_active_id := String((player_team[0] as Dictionary).memberId)
	var switched_id := String((player_team[2] as Dictionary).memberId)
	var untouched_id := String((player_team[3] as Dictionary).memberId)
	var original_active_xp := int(
		CollectionSystem.get_pcl(original_active_id).instanceStats.currentXp
	)
	var switched_xp := int(CollectionSystem.get_pcl(switched_id).instanceStats.currentXp)
	var untouched_xp := int(CollectionSystem.get_pcl(untouched_id).instanceStats.currentXp)
	_check(
		BattleSystem.choose_switch(switched_id),
		"A living bench Pokemon should be selectable for the participation edge case."
	)

	var response := _response_from_start(start_request, 1, false)
	for member_value: Variant in response.parties.player:
		(member_value as Dictionary).active = false
	var switched_snapshot := (response.parties.player as Array)[2] as Dictionary
	switched_snapshot.hp = 0
	switched_snapshot.normalizedHealth = 0.0
	switched_snapshot.fainted = true
	var defeated_snapshot := (response.parties.opponent as Array)[0] as Dictionary
	defeated_snapshot.hp = 0
	defeated_snapshot.normalizedHealth = 0.0
	defeated_snapshot.fainted = true
	defeated_snapshot.active = false
	(response.parties.opponent as Array)[1].active = true
	var switch_options: Array[Dictionary] = []
	for member_value: Variant in response.parties.player:
		var member := member_value as Dictionary
		if not bool(member.fainted):
			switch_options.append({"memberId": member.memberId})
	response.request = {
		"type": "switch",
		"activeMemberId": switched_id,
		"switchOptions": switch_options,
	}
	response.events = [
		"|switch|p1a: Hoothoot|Hoothoot, L4|100/100",
		"|faint|p1a: Hoothoot",
		"|faint|p2a: Wooper",
		"|switch|p2a: Magikarp|Magikarp, L3|100/100",
	]
	_transport.complete_json(response)
	await get_tree().process_frame
	var original_active_award := int(
		preload("res://game/battle/system/battle_experience.gd").calculate_award(
			int((player_team[0] as Dictionary).level),
			3,
			194
		).amount
	)
	var switched_award := int(
		preload("res://game/battle/system/battle_experience.gd").calculate_award(
			int((player_team[2] as Dictionary).level),
			3,
			194
		).amount
	)
	_check(
		int(CollectionSystem.get_pcl(original_active_id).instanceStats.currentXp)
		== original_active_xp + original_active_award,
		"The original stage Pokemon should retain participant XP after switching out."
	)
	_check(
		int(CollectionSystem.get_pcl(switched_id).instanceStats.currentXp)
		== switched_xp + switched_award,
		"A switched-in Pokemon should receive participant XP even if it faints that turn."
	)
	_check(
		int(CollectionSystem.get_pcl(untouched_id).instanceStats.currentXp) == untouched_xp,
		"A bench Pokemon that never appeared and has no Exp. Share should receive no XP."
	)
	var switched_event_found := false
	for event_value: Variant in (_captured_events.back().events as Array):
		if (
			typeof(event_value) == TYPE_DICTIONARY
			and String(event_value.get("type", "")) == "experience"
			and String(event_value.get("memberId", "")) == switched_id
			and String(event_value.get("source", "")) == "participation"
			and int(event_value.get("amount", 0)) == switched_award
		):
			switched_event_found = true
	_check(
		switched_event_found,
		"The fainted switch target should receive a normal participation XP event."
	)
	_check(
		BattleSystem.acknowledge_events_presented(1),
		"The switch-participation response should acknowledge normally."
	)


func _verify_fainted_drag_participant_receives_xp() -> void:
	BattleSystem.reset_for_testing()
	_transport.calls.clear()
	_check(BattleSystem.begin_current_battle_scene(), "The forced-entry session should start.")
	var start_request := JSON.parse_string(
		(_transport.calls.back().body as PackedByteArray).get_string_from_utf8()
	) as Dictionary
	_transport.complete_json(_response_from_start(start_request, 0, false))
	await get_tree().process_frame
	_check(
		BattleSystem.acknowledge_events_presented(0),
		"The forced-entry session should acknowledge its start revision."
	)

	var player_team := start_request.player.team as Array
	var original_active_id := String((player_team[0] as Dictionary).memberId)
	var final_active_id := String((player_team[4] as Dictionary).memberId)
	var dragged_and_fainted_id := String((player_team[3] as Dictionary).memberId)
	var untouched_id := String((player_team[5] as Dictionary).memberId)
	var original_active_xp := int(
		CollectionSystem.get_pcl(original_active_id).instanceStats.currentXp
	)
	var final_active_xp := int(
		CollectionSystem.get_pcl(final_active_id).instanceStats.currentXp
	)
	var dragged_and_fainted_xp := int(
		CollectionSystem.get_pcl(dragged_and_fainted_id).instanceStats.currentXp
	)
	var untouched_xp := int(CollectionSystem.get_pcl(untouched_id).instanceStats.currentXp)
	_check(BattleSystem.choose_move(1), "A move should submit the forced-entry response.")

	var response := _response_from_start(start_request, 1, false)
	for member_value: Variant in response.parties.player:
		(member_value as Dictionary).active = false
	(response.parties.player as Array)[4].active = true
	var transient_snapshot := (response.parties.player as Array)[3] as Dictionary
	transient_snapshot.hp = 0
	transient_snapshot.normalizedHealth = 0.0
	transient_snapshot.fainted = true
	var defeated_snapshot := (response.parties.opponent as Array)[0] as Dictionary
	defeated_snapshot.hp = 0
	defeated_snapshot.normalizedHealth = 0.0
	defeated_snapshot.fainted = true
	defeated_snapshot.active = false
	(response.parties.opponent as Array)[1].active = true
	response.request.activeMemberId = final_active_id
	response.request.moves = []
	for move_value: Variant in (response.parties.player as Array)[4].moves:
		var move := (move_value as Dictionary).duplicate(true)
		move["disabled"] = false
		response.request.moves.append(move)
	response.request.switchOptions = []
	for member_value: Variant in response.parties.player:
		var member := member_value as Dictionary
		if String(member.memberId) != final_active_id and not bool(member.fainted):
			response.request.switchOptions.append({"memberId": member.memberId})
	response.events = [
		"|drag|p1a: Bidoof|Bidoof, L3|100/100",
		"|faint|p1a: Bidoof",
		"|drag|p1a: Hoothoot|Hoothoot, L3|100/100",
		"|faint|p2a: Wooper",
		"|switch|p2a: Magikarp|Magikarp, L3|100/100",
	]
	_transport.complete_json(response)
	await get_tree().process_frame

	for participant_value: Variant in [
		{
			"memberId": original_active_id,
			"previousXp": original_active_xp,
			"teamIndex": 0,
		},
		{
			"memberId": final_active_id,
			"previousXp": final_active_xp,
			"teamIndex": 4,
		},
		{
			"memberId": dragged_and_fainted_id,
			"previousXp": dragged_and_fainted_xp,
			"teamIndex": 3,
		},
	]:
		var participant := participant_value as Dictionary
		var expected_award := int(
			preload("res://game/battle/system/battle_experience.gd").calculate_award(
				int((player_team[int(participant.teamIndex)] as Dictionary).level),
				3,
				194
			).amount
		)
		_check(
			int(CollectionSystem.get_pcl(String(participant.memberId)).instanceStats.currentXp)
			== int(participant.previousXp) + expected_award,
			"Every Pokemon shown on the stage should receive the knockout XP."
		)
	_check(
		int(CollectionSystem.get_pcl(untouched_id).instanceStats.currentXp) == untouched_xp,
		"An untouched bench Pokemon without Exp. Share should still receive no XP."
	)
	_check(
		BattleSystem.acknowledge_events_presented(1),
		"The forced-entry response should acknowledge normally."
	)


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
		if not bool(member.fainted):
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


func _count_level_announcements(member_id: String, level: int) -> int:
	var count := 0
	var phrase := "grew to Lv. %d" % level
	for captured_value: Variant in _captured_events:
		if typeof(captured_value) != TYPE_DICTIONARY:
			continue
		for event_value: Variant in (captured_value as Dictionary).get("events", []):
			if (
				typeof(event_value) == TYPE_DICTIONARY
				and String(event_value.get("memberId", "")) == member_id
				and phrase in String(event_value.get("message", ""))
			):
				count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
