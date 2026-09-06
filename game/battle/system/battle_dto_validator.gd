class_name BattleDtoValidator
extends RefCounted

## Strict validation for the public battle API response. It deliberately never
## returns or embeds the opaque state token in an error or presentation value.

const API_VERSION := "v1"
const ENGINE_VERSION := "0.11.11"
const FORMAT_VERSION := "pfr-gen9-singles-v1"
const MAX_STATE_TOKEN_BYTES := 128 * 1024
const MAX_EVENT_COUNT := 4096
const MAX_EVENT_BYTES := 32 * 1024
const MAX_TEXT_BYTES := 512


static func validate_response(value: Variant, expected: Dictionary) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("malformed_response", "Battle response must be a JSON object.")
	var response := value as Dictionary

	if String(response.get("apiVersion", "")) != API_VERSION:
		return _failure("version_mismatch", "The battle API version is incompatible.")
	if String(response.get("engineVersion", "")) != ENGINE_VERSION:
		return _failure("version_mismatch", "The battle engine version is incompatible.")
	if String(response.get("formatVersion", "")) != FORMAT_VERSION:
		return _failure("version_mismatch", "The battle format version is incompatible.")

	var battle_id := String(response.get("battleId", ""))
	if not _valid_text(battle_id, 1, 128):
		return _failure("malformed_response", "Battle response has an invalid battle ID.")
	var expected_battle_id := String(expected.get("battle_id", ""))
	if not expected_battle_id.is_empty() and battle_id != expected_battle_id:
		return _failure("battle_id_mismatch", "Battle response belongs to a different battle.")

	var revision_value: Variant = response.get("revision")
	if not _is_integer(revision_value) or int(revision_value) < 0:
		return _failure("malformed_response", "Battle response has an invalid revision.")
	var revision := int(revision_value)
	if expected.has("revision") and revision != int(expected["revision"]):
		return _failure("revision_mismatch", "Battle response revision did not advance as expected.")

	var phase := String(response.get("phase", ""))
	if phase not in ["awaiting_player", "ended"]:
		return _failure("malformed_response", "Battle response has an invalid phase.")

	var events_result := _validate_events(response.get("events"))
	if not events_result.ok:
		return events_result

	var parties_result := _validate_parties(
		response.get("parties"),
		expected.get("player_member_ids", []),
		expected.get("opponent_member_ids", [])
	)
	if not parties_result.ok:
		return parties_result

	var request_value: Variant = response.get("request")
	var result_value: Variant = response.get("result")
	if phase == "awaiting_player":
		var token_value: Variant = response.get("stateToken")
		if typeof(token_value) != TYPE_STRING:
			return _failure("malformed_response", "Awaiting battle response is missing its state token.")
		var token := token_value as String
		if token.is_empty() or token.to_utf8_buffer().size() > MAX_STATE_TOKEN_BYTES:
			return _failure("response_too_large", "Battle state token exceeds the client limit.")
		if result_value != null:
			return _failure("malformed_response", "Awaiting battle response contains a result.")
		var request_result := _validate_choice_request(
			request_value,
			parties_result.player_members
		)
		if not request_result.ok:
			return request_result
	else:
		if response.has("stateToken"):
			return _failure("malformed_response", "Ended battle response contains a state token.")
		if request_value != null:
			return _failure("malformed_response", "Ended battle response contains a choice request.")
		var battle_result := _validate_result(result_value)
		if not battle_result.ok:
			return battle_result

	return {
		"ok": true,
		"response": response.duplicate(true),
	}


static func _validate_events(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("malformed_response", "Battle events must be an array.")
	var events := value as Array
	if events.size() > MAX_EVENT_COUNT:
		return _failure("response_too_large", "Battle event count exceeds the client limit.")
	for event_value: Variant in events:
		if typeof(event_value) != TYPE_STRING:
			return _failure("malformed_response", "Battle event entries must be strings.")
		if (event_value as String).to_utf8_buffer().size() > MAX_EVENT_BYTES:
			return _failure("response_too_large", "A battle event exceeds the client limit.")
	return {"ok": true}


static func _validate_parties(
	value: Variant,
	expected_player_ids: Variant,
	expected_opponent_ids: Variant
) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("malformed_response", "Battle parties must be an object.")
	var parties := value as Dictionary
	var player_result := _validate_party(
		parties.get("player"),
		expected_player_ids,
		true,
		"player"
	)
	if not player_result.ok:
		return player_result
	var opponent_result := _validate_party(
		parties.get("opponent"),
		expected_opponent_ids,
		false,
		"opponent"
	)
	if not opponent_result.ok:
		return opponent_result
	return {
		"ok": true,
		"player_members": player_result.members,
		"opponent_members": opponent_result.members,
	}


static func _validate_party(
	value: Variant,
	expected_ids_value: Variant,
	include_moves: bool,
	label: String
) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("malformed_response", "Battle %s party must be an array." % label)
	var members := value as Array
	if members.is_empty() or members.size() > 6:
		return _failure("malformed_response", "Battle %s party size is invalid." % label)

	var expected_ids: Array = expected_ids_value if typeof(expected_ids_value) == TYPE_ARRAY else []
	if not expected_ids.is_empty() and members.size() != expected_ids.size():
		return _failure("malformed_response", "Battle %s party is incomplete." % label)

	var seen_ids := {}
	var active_count := 0
	for index in range(members.size()):
		var member_value: Variant = members[index]
		if typeof(member_value) != TYPE_DICTIONARY:
			return _failure("malformed_response", "Battle %s party member is invalid." % label)
		var member := member_value as Dictionary
		var member_id := String(member.get("memberId", ""))
		if not _valid_text(member_id, 1, 128) or seen_ids.has(member_id):
			return _failure("malformed_response", "Battle %s member ID is invalid." % label)
		seen_ids[member_id] = true
		if not expected_ids.is_empty() and member_id != String(expected_ids[index]):
			return _failure("malformed_response", "Battle %s party order changed." % label)

		for text_key in ["species", "nickname"]:
			if not _valid_text(String(member.get(text_key, "")), 1, MAX_TEXT_BYTES):
				return _failure("malformed_response", "Battle %s member text is invalid." % label)
		var level_value: Variant = member.get("level")
		var hp_value: Variant = member.get("hp")
		var max_hp_value: Variant = member.get("maxHp")
		var health_value: Variant = member.get("normalizedHealth")
		if not _is_integer(level_value) or int(level_value) < 1 or int(level_value) > 100:
			return _failure("malformed_response", "Battle %s member level is invalid." % label)
		if not _is_integer(hp_value) or not _is_integer(max_hp_value):
			return _failure("malformed_response", "Battle %s member HP is invalid." % label)
		var hp := int(hp_value)
		var max_hp := int(max_hp_value)
		if max_hp <= 0 or hp < 0 or hp > max_hp or not _valid_fraction(health_value):
			return _failure("malformed_response", "Battle %s member HP is invalid." % label)
		var normalized_health := float(health_value)
		if absf(normalized_health - float(hp) / float(max_hp)) > 0.00001:
			return _failure("malformed_response", "Battle %s member health is inconsistent." % label)
		if typeof(member.get("fainted")) != TYPE_BOOL or bool(member.fainted) != (hp == 0):
			return _failure("malformed_response", "Battle %s fainted state is inconsistent." % label)
		if typeof(member.get("active")) != TYPE_BOOL:
			return _failure("malformed_response", "Battle %s active state is invalid." % label)
		if bool(member.active):
			active_count += 1
		var status_value: Variant = member.get("status")
		if status_value != null and (
			typeof(status_value) != TYPE_STRING
			or (status_value as String).to_utf8_buffer().size() > MAX_TEXT_BYTES
		):
			return _failure("malformed_response", "Battle %s status is invalid." % label)
		if include_moves:
			var moves_result := _validate_snapshot_moves(member.get("moves"))
			if not moves_result.ok:
				return moves_result
		elif member.has("moves"):
			return _failure("malformed_response", "Opponent party leaked private move data.")
	if active_count > 1:
		return _failure("malformed_response", "Battle %s party has multiple active members." % label)
	return {"ok": true, "members": members}


static func _validate_snapshot_moves(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("malformed_response", "Player move snapshot must be an array.")
	var moves := value as Array
	if moves.is_empty() or moves.size() > 4:
		return _failure("malformed_response", "Player move snapshot size is invalid.")
	var seen_indices := {}
	for move_value: Variant in moves:
		if typeof(move_value) != TYPE_DICTIONARY:
			return _failure("malformed_response", "Player move snapshot entry is invalid.")
		var move := move_value as Dictionary
		if not _valid_move_identity(move, seen_indices):
			return _failure("malformed_response", "Player move snapshot identity is invalid.")
		if not _valid_pp(move.get("pp"), move.get("maxPp")):
			return _failure("malformed_response", "Player move snapshot PP is invalid.")
	return {"ok": true}


static func _validate_choice_request(value: Variant, player_members: Array) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("malformed_response", "Awaiting battle response is missing its choice request.")
	var request := value as Dictionary
	var request_type := String(request.get("type", ""))
	if request_type not in ["move", "switch"]:
		return _failure("malformed_response", "Battle choice request type is invalid.")

	var member_by_id := {}
	var active_member_id := ""
	for member_value: Variant in player_members:
		var member := member_value as Dictionary
		var member_id := String(member.memberId)
		member_by_id[member_id] = member
		if bool(member.active):
			active_member_id = member_id

	var request_active_id := String(request.get("activeMemberId", ""))
	if request_type == "move":
		if request_active_id.is_empty() or request_active_id != active_member_id:
			return _failure("malformed_response", "Move request active member is invalid.")
		var moves_value: Variant = request.get("moves")
		if typeof(moves_value) != TYPE_ARRAY:
			return _failure("malformed_response", "Move request options must be an array.")
		var moves := moves_value as Array
		if moves.is_empty() or moves.size() > 4:
			return _failure("malformed_response", "Move request option count is invalid.")
		var seen_indices := {}
		for move_value: Variant in moves:
			if typeof(move_value) != TYPE_DICTIONARY:
				return _failure("malformed_response", "Move request option is invalid.")
			var move := move_value as Dictionary
			if not _valid_move_identity(move, seen_indices):
				return _failure("malformed_response", "Move request identity is invalid.")
			if not _valid_pp(move.get("pp"), move.get("maxPp")):
				return _failure("malformed_response", "Move request PP is invalid.")
			if typeof(move.get("disabled")) != TYPE_BOOL:
				return _failure("malformed_response", "Move request disabled state is invalid.")
	elif request.has("moves"):
		return _failure("malformed_response", "Forced switch request contains moves.")

	var switches_value: Variant = request.get("switchOptions")
	if typeof(switches_value) != TYPE_ARRAY:
		return _failure("malformed_response", "Switch options must be an array.")
	var seen_switches := {}
	for switch_value: Variant in switches_value as Array:
		if typeof(switch_value) != TYPE_DICTIONARY:
			return _failure("malformed_response", "Switch option is invalid.")
		var member_id := String((switch_value as Dictionary).get("memberId", ""))
		if member_id.is_empty() or seen_switches.has(member_id) or not member_by_id.has(member_id):
			return _failure("malformed_response", "Switch option member is invalid.")
		var target := member_by_id[member_id] as Dictionary
		if bool(target.fainted) or bool(target.active):
			return _failure("malformed_response", "Switch option is not an available party member.")
		seen_switches[member_id] = true
	if request_type == "switch" and seen_switches.is_empty():
		return _failure("malformed_response", "Forced switch request has no options.")
	return {"ok": true}


static func _validate_result(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("malformed_response", "Ended battle response is missing its result.")
	var result := value as Dictionary
	if String(result.get("winner", "")) not in ["player", "opponent", "tie"]:
		return _failure("malformed_response", "Battle result winner is invalid.")
	if not _valid_text(String(result.get("reason", "")), 1, MAX_TEXT_BYTES):
		return _failure("malformed_response", "Battle result reason is invalid.")
	return {"ok": true}


static func _valid_move_identity(move: Dictionary, seen_indices: Dictionary) -> bool:
	var index_value: Variant = move.get("moveIndex")
	if not _is_integer(index_value):
		return false
	var move_index := int(index_value)
	if move_index < 1 or move_index > 4 or seen_indices.has(move_index):
		return false
	seen_indices[move_index] = true
	return (
		_valid_text(String(move.get("id", "")), 1, 128)
		and _valid_text(String(move.get("name", "")), 1, MAX_TEXT_BYTES)
	)


static func _valid_pp(pp_value: Variant, max_pp_value: Variant) -> bool:
	return (
		_is_integer(pp_value)
		and _is_integer(max_pp_value)
		and int(max_pp_value) > 0
		and int(pp_value) >= 0
		and int(pp_value) <= int(max_pp_value)
	)


static func _valid_fraction(value: Variant) -> bool:
	return (
		typeof(value) in [TYPE_INT, TYPE_FLOAT]
		and is_finite(float(value))
		and float(value) >= 0.0
		and float(value) <= 1.0
	)


static func _valid_text(value: String, minimum_bytes: int, maximum_bytes: int) -> bool:
	var byte_count := value.to_utf8_buffer().size()
	return byte_count >= minimum_bytes and byte_count <= maximum_bytes


static func _is_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return typeof(value) == TYPE_FLOAT and is_finite(value) and floorf(value) == value


static func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"message": message,
	}
