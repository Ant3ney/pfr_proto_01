class_name BattleEventTranslator
extends RefCounted

## Converts p1-filtered Showdown protocol deltas into presentation-only events.
## Snapshots, never these messages, remain authoritative for gameplay state.


static func translate(events_value: Variant) -> Array[Dictionary]:
	var translated: Array[Dictionary] = []
	if typeof(events_value) != TYPE_ARRAY:
		return translated
	for value: Variant in events_value as Array:
		if typeof(value) != TYPE_STRING:
			continue
		var event := _translate_line(value as String)
		if not event.is_empty():
			translated.append(event)
	return translated


static func _translate_line(line: String) -> Dictionary:
	if line.is_empty() or line == "|":
		return {}
	var fields := line.split("|", true)
	if fields.size() < 2:
		return _message(line)
	var event_type := fields[1]
	match event_type:
		"switch", "drag", "replace":
			if fields.size() < 5:
				return {}
			var actor := _actor(fields[2])
			var name := _display_name(fields[3])
			return {
				"type": "switch",
				"side": actor.side,
				"actor": actor.name,
				"name": name,
				"message": "%s sent out %s!" % [_side_label(actor.side), name],
			}
		"move":
			if fields.size() < 4:
				return {}
			var actor := _actor(fields[2])
			var move_name := fields[3].strip_edges()
			return {
				"type": "attack",
				"side": actor.side,
				"actor": actor.name,
				"move": move_name,
				"message": "%s used %s!" % [actor.name, move_name],
			}
		"-damage":
			return _health_event(fields, "damage")
		"-heal":
			return _health_event(fields, "heal")
		"-status":
			if fields.size() < 4:
				return {}
			var actor := _actor(fields[2])
			return {
				"type": "status",
				"side": actor.side,
				"actor": actor.name,
				"status": fields[3],
				"message": "%s was afflicted with %s." % [actor.name, fields[3]],
			}
		"-curestatus":
			if fields.size() < 3:
				return {}
			var actor := _actor(fields[2])
			return {
				"type": "status_cleared",
				"side": actor.side,
				"actor": actor.name,
				"message": "%s recovered from its status condition." % actor.name,
			}
		"faint":
			if fields.size() < 3:
				return {}
			var actor := _actor(fields[2])
			return {
				"type": "knockout",
				"side": actor.side,
				"actor": actor.name,
				"message": "%s fainted!" % actor.name,
			}
		"win":
			var winner := fields[2].strip_edges() if fields.size() > 2 else ""
			return {"type": "result", "winner": winner, "message": "%s won the battle!" % winner}
		"tie":
			return {"type": "result", "winner": "tie", "message": "The battle ended in a tie."}
		"turn":
			if fields.size() > 2:
				return {"type": "turn", "turn": int(fields[2]), "message": "Turn %s" % fields[2]}
		"cant":
			if fields.size() > 3:
				var actor := _actor(fields[2])
				return {
					"type": "message",
					"side": actor.side,
					"message": "%s could not move (%s)." % [actor.name, fields[3]],
				}
		"-supereffective":
			return _message("It's super effective!")
		"-resisted":
			return _message("It's not very effective.")
		"-immune":
			return _message("It had no effect.")
		"-crit":
			return _message("A critical hit!")
		"message", "-message":
			if fields.size() > 2:
				return _message(fields[2])
		"start":
			return _message("The battle began!")
	return {}


static func _health_event(fields: PackedStringArray, event_type: String) -> Dictionary:
	if fields.size() < 4:
		return {}
	var actor := _actor(fields[2])
	return {
		"type": event_type,
		"side": actor.side,
		"actor": actor.name,
		"message": "%s%s" % [
			actor.name,
			" recovered health." if event_type == "heal" else " was hurt.",
		],
	}


static func _actor(protocol_name: String) -> Dictionary:
	var side := "player" if protocol_name.begins_with("p1") else "opponent"
	var separator := protocol_name.find(":")
	var name := protocol_name.substr(separator + 1).strip_edges() if separator >= 0 else protocol_name
	return {"side": side, "name": name}


static func _display_name(details: String) -> String:
	return details.get_slice(",", 0).strip_edges()


static func _side_label(side: String) -> String:
	return "You" if side == "player" else "The opponent"


static func _message(text: String) -> Dictionary:
	var cleaned := text.strip_edges()
	return {"type": "message", "message": cleaned} if not cleaned.is_empty() else {}
