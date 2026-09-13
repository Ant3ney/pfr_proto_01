extends Node

const RULES = preload("res://src/loading_battle_rules.gd")
const SESSION = preload("res://src/loading_battle_session.gd")


class FakeTransport:
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


	func complete(value: Variant, response_code := 200, result := HTTPRequest.RESULT_SUCCESS) -> void:
		var completed := active_request_id
		active_request_id = -1
		transport_completed.emit(
			completed,
			result,
			response_code,
			PackedStringArray(["Content-Type: application/json"]),
			JSON.stringify(value).to_utf8_buffer()
		)


var _failures: Array[String] = []
var _transport := FakeTransport.new()
var _session: Node
var _captured_events: Array = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_verify_rules()
	add_child(_transport)
	_session = SESSION.new()
	_session.set_transport_for_testing(_transport)
	_session.presentation_events_ready.connect(
		func(events: Array, revision: int) -> void:
			_captured_events.append({"events": events, "revision": revision})
	)
	add_child(_session)
	await get_tree().process_frame
	await _verify_session_contract()
	if _failures.is_empty():
		print(
			"Loading battle smoke test passed: exact teams and ladder, starter selection, "
			+ "strict response validation, byte-identical retry, event locking, concession, "
			+ "and practice-only memory state verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Loading battle smoke test failed: %s" % failure)
	get_tree().quit(1)


func _verify_rules() -> void:
	_check(RULES.STARTERS == ["charmander", "froakie", "treecko"], "Starter order must remain exact.")
	_check(
		RULES.STANDARD_MOVES.charmander
		== ["Fire Fang", "Scratch", "Smokescreen", "Thunder Punch"],
		"Charmander standard moves must remain exact."
	)
	_check(
		RULES.STANDARD_MOVES.froakie
		== ["Water Pulse", "Quick Attack", "Smokescreen", "Ice Beam"],
		"Froakie standard moves must remain exact."
	)
	_check(
		RULES.STANDARD_MOVES.treecko
		== ["Leaf Blade", "Quick Attack", "Leer", "Rock Tomb"],
		"Treecko standard moves must remain exact."
	)
	for starter_id: String in RULES.STARTERS:
		var medium: Dictionary = RULES.start_payload(starter_id, "medium")
		var ditto := ((medium.opponent as Dictionary).team as Array)[0] as Dictionary
		_check(
			ditto.species == "Ditto" and ditto.level == 22 and ditto.health == 0.85
			and ditto.ability == "Imposter",
			"Medium must be the level-22, 85%-health Imposter mirror."
		)
		var impossible: Dictionary = RULES.start_payload(starter_id, "impossible")
		var player := ((impossible.player as Dictionary).team as Array)[0] as Dictionary
		var wobbuffet := ((impossible.opponent as Dictionary).team as Array)[0] as Dictionary
		_check(
			player.moves == RULES.EXHIBITION_MOVES[starter_id],
			"Impossible player moves must be physical-only for %s." % starter_id
		)
		_check(
			wobbuffet.species == "Wobbuffet" and wobbuffet.level == 50
			and wobbuffet.moves == ["Counter"] and wobbuffet.ivs.spe == 0
			and wobbuffet.evs.spe == 0,
			"Impossible must use minimum-speed Counter Wobbuffet."
		)
	_check(RULES.next_difficulty("medium", "player") == "hard", "A Medium win must raise to Hard.")
	_check(RULES.next_difficulty("hard", "player") == "impossible", "Two wins must reach Impossible.")
	_check(RULES.next_difficulty("impossible", "player") == "impossible", "Impossible is the upper bound.")
	_check(RULES.next_difficulty("medium", "opponent") == "easy", "A Medium loss must lower to Easy.")
	_check(RULES.next_difficulty("easy", "tie") == "easy", "Easy is the lower bound.")
	_check(
		RULES.tier_title("impossible") == "Impossible Exhibition — survive as long as you can",
		"The rigged exhibition must be explicitly labeled."
	)


func _verify_session_contract() -> void:
	_check(_session.practice_only, "The boot session must identify itself as practice-only.")
	_check(_session.get_state() == SESSION.STATE_PICKING, "The session should begin at starter selection.")
	_check(_session.select_starter("charmander"), "Selecting a valid starter should dispatch Medium.")
	_check(_transport.calls.size() == 1, "Starter selection should dispatch one REST request.")
	var first_call: Dictionary = _transport.calls[0]
	_check(first_call.route == "/battles", "The first request must use the battle start route.")
	var first_body := first_call.body as PackedByteArray
	var start_payload := JSON.parse_string(first_body.get_string_from_utf8()) as Dictionary
	_check(
		((start_payload.player as Dictionary).team as Array)[0].moves
		== RULES.STANDARD_MOVES.charmander,
		"The serialized player team should use the selected starter's exact standard moves."
	)
	_transport.complete({}, 0, HTTPRequest.RESULT_CANT_CONNECT)
	await get_tree().process_frame
	_check(_session.difficulty == "medium", "An API failure must not change difficulty.")
	_check(_session.retry_pending_request(), "A failed start should expose Retry Battle.")
	_check(
		(_transport.calls[1].body as PackedByteArray) == first_body,
		"A start retry must reuse byte-identical request bytes."
	)

	_transport.complete(_awaiting_response(start_payload, 0, "token-medium", [
		"|start",
		"|switch|p1a: Charmander|Charmander, L20|44/44",
		"|switch|p2a: Ditto|Ditto, L22|42/49",
	]))
	await get_tree().process_frame
	_check(_session.get_state() == SESSION.STATE_PRESENTING, "A valid response should enter event presentation.")
	_check(not _session.choose_move(4), "Moves must stay locked until every event is acknowledged.")
	_check(not _captured_events.is_empty(), "Translated presentation events should be emitted.")
	if not _captured_events.is_empty():
		var types: Array = (_captured_events.back().events as Array).map(
			func(event: Dictionary) -> String: return String(event.get("type", ""))
		)
		_check(types == ["message", "switch", "switch"], "REST events must be translated in order.")
	_check(
		not JSON.stringify(_session.get_snapshot()).contains("token-medium"),
		"The opaque token must never enter presentation state."
	)
	_check(_session.acknowledge_events_presented(0), "The exact revision should unlock its request.")
	_check(_session.can_choose(), "A move request should unlock only after event acknowledgement.")
	_check(_session.choose_move(4), "The enabled coverage move should submit.")
	var action_body := (_transport.calls.back().body as PackedByteArray).duplicate()
	var action := JSON.parse_string(action_body.get_string_from_utf8()) as Dictionary
	var typed_action := action.action as Dictionary
	_check(
		String(typed_action.get("type", "")) == "move"
		and int(typed_action.get("moveIndex", 0)) == 4,
		"Move submission must stay typed."
	)
	_check(action.stateToken == "token-medium", "The current in-memory token must drive the action.")
	_transport.complete({}, 0, HTTPRequest.RESULT_CONNECTION_ERROR)
	await get_tree().process_frame
	_check(_session.retry_pending_request(), "An interrupted action should remain retryable.")
	_check(
		(_transport.calls.back().body as PackedByteArray) == action_body,
		"An action retry must reuse byte-identical token and action bytes."
	)
	_transport.complete(_ended_response(start_payload, 1, "player"))
	await get_tree().process_frame
	_check(_session.difficulty == "hard" and _session.win_streak == 1, "A Medium win must advance to Hard.")
	_check(not _session.start_next_battle(), "Next Battle must wait for final event acknowledgement.")
	_check(_session.acknowledge_events_presented(1), "Final events should be acknowledgeable.")
	_check(_session.start_next_battle(), "Next Battle should start after the result sequence.")
	var hard_payload := JSON.parse_string(
		(_transport.calls.back().body as PackedByteArray).get_string_from_utf8()
	) as Dictionary
	_check(
		((hard_payload.opponent as Dictionary).team as Array)[0].species == "Froakie",
		"Hard Charmander must face its Froakie counter."
	)
	_transport.complete(_awaiting_response(hard_payload, 0, "token-hard", []))
	await get_tree().process_frame
	_session.acknowledge_events_presented(0)
	_check(_session.concede(), "Concede should submit only from an unlocked choice.")
	var concede := JSON.parse_string(
		(_transport.calls.back().body as PackedByteArray).get_string_from_utf8()
	) as Dictionary
	_check(
		String((concede.action as Dictionary).get("type", "")) == "forfeit"
		and (concede.action as Dictionary).size() == 1,
		"Concede must use the REST forfeit action."
	)
	_transport.complete(_ended_response(hard_payload, 1, "opponent"))
	await get_tree().process_frame
	_check(
		_session.difficulty == "medium" and _session.win_streak == 0,
		"A concession must lower difficulty and clear the streak only after acceptance."
	)


func _awaiting_response(payload: Dictionary, revision: int, token: String, events: Array) -> Dictionary:
	var player_input := ((payload.player as Dictionary).team as Array)[0] as Dictionary
	var opponent_input := ((payload.opponent as Dictionary).team as Array)[0] as Dictionary
	var moves: Array = []
	for index in range((player_input.moves as Array).size()):
		var move_name := String((player_input.moves as Array)[index])
		moves.append({
			"moveIndex": index + 1,
			"id": move_name.to_lower().replace(" ", ""),
			"name": move_name,
			"pp": 20,
			"maxPp": 20,
			"disabled": false,
		})
	return {
		"apiVersion": "v1",
		"engineVersion": "0.11.11",
		"formatVersion": "pfr-gen9-singles-v1",
		"battleId": "practice-battle",
		"revision": revision,
		"phase": "awaiting_player",
		"stateToken": token,
		"events": events,
		"request": {
			"type": "move",
			"activeMemberId": "practice-player",
			"moves": moves,
			"switchOptions": [],
		},
		"parties": _parties(player_input, opponent_input, moves, false),
		"result": null,
	}


func _ended_response(payload: Dictionary, revision: int, winner: String) -> Dictionary:
	var player_input := ((payload.player as Dictionary).team as Array)[0] as Dictionary
	var opponent_input := ((payload.opponent as Dictionary).team as Array)[0] as Dictionary
	var moves: Array = []
	for index in range((player_input.moves as Array).size()):
		var move_name := String((player_input.moves as Array)[index])
		moves.append({
			"moveIndex": index + 1,
			"id": move_name.to_lower().replace(" ", ""),
			"name": move_name,
			"pp": 19,
			"maxPp": 20,
		})
	return {
		"apiVersion": "v1",
		"engineVersion": "0.11.11",
		"formatVersion": "pfr-gen9-singles-v1",
		"battleId": "practice-battle",
		"revision": revision,
		"phase": "ended",
		"events": ["|win|Player" if winner == "player" else "|win|Practice CPU"],
		"request": null,
		"parties": _parties(player_input, opponent_input, moves, true),
		"result": {"winner": winner, "reason": "forfeit" if winner != "player" else "all_pokemon_fainted"},
	}


func _parties(
	player_input: Dictionary,
	opponent_input: Dictionary,
	moves: Array,
	ended: bool
) -> Dictionary:
	return {
		"player": [{
			"memberId": "practice-player",
			"species": String(player_input.species),
			"nickname": String(player_input.species),
			"level": int(player_input.level),
			"hp": 0 if ended else 44,
			"maxHp": 44,
			"normalizedHealth": 0.0 if ended else 1.0,
			"fainted": ended,
			"active": not ended,
			"status": null,
			"moves": moves,
		}],
		"opponent": [{
			"memberId": "practice-opponent",
			"species": String(opponent_input.species),
			"nickname": String(opponent_input.species),
			"level": int(opponent_input.level),
			"hp": 0 if ended else 42,
			"maxHp": 49,
			"normalizedHealth": 0.0 if ended else 42.0 / 49.0,
			"fainted": ended,
			"active": not ended,
			"status": null,
		}],
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
