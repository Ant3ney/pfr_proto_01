class_name BattleEncounterDefinition
extends Resource

## Editor-authored opponent definition discovered from the active battle scene.

enum ForfeitPolicy {
	ALLOWED,
	DISALLOWED,
}

@export var encounter_id := ""
@export var display_name := ""
@export var api_name := ""
@export var members: Array[BattleEncounterMember] = []
@export var sprite_override := ""
@export_enum("Allowed", "Disallowed") var forfeit_policy: int = ForfeitPolicy.ALLOWED


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _is_slug(encounter_id):
		errors.append("encounter_id must be a lowercase hyphenated stable ID")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is required")
	if not _is_safe_api_name(api_name):
		errors.append("api_name is not safe for the Showdown protocol")
	if members.is_empty() or members.size() > 6:
		errors.append("members must contain between 1 and 6 entries")
	if forfeit_policy not in [ForfeitPolicy.ALLOWED, ForfeitPolicy.DISALLOWED]:
		errors.append("forfeit_policy is invalid")
	if not sprite_override.is_empty():
		if not sprite_override.begins_with("res://"):
			errors.append("sprite_override must be an explicit res:// resource path")
		elif not ResourceLoader.exists(sprite_override):
			errors.append("sprite_override resource does not exist")

	var seen_member_ids: Dictionary = {}
	for member_index in members.size():
		var member := members[member_index]
		if member == null:
			errors.append("member %d is missing" % (member_index + 1))
			continue
		if seen_member_ids.has(member.member_id):
			errors.append("member_id is repeated: %s" % member.member_id)
		else:
			seen_member_ids[member.member_id] = true
		for member_error in member.validate():
			errors.append("member %d: %s" % [member_index + 1, member_error])
	return errors


func to_server_team() -> Array[Dictionary]:
	if not validate().is_empty():
		return []
	var team: Array[Dictionary] = []
	for member in members:
		team.append(member.to_server_member())
	return team


func to_server_side() -> Dictionary:
	var team := to_server_team()
	if team.is_empty():
		return {}
	return {"name": api_name, "team": team}


func to_presentation_data() -> Dictionary:
	if not validate().is_empty():
		return {}
	var presentation_members: Array[Dictionary] = []
	for member in members:
		var presentation_member := member.to_presentation_member()
		if not sprite_override.is_empty():
			presentation_member["spriteOverride"] = sprite_override
		presentation_members.append(presentation_member)
	return {
		"encounterId": encounter_id,
		"displayName": display_name,
		"apiName": api_name,
		"members": presentation_members,
		"spriteOverride": sprite_override,
		"forfeitAllowed": forfeit_policy == ForfeitPolicy.ALLOWED,
	}


func allows_forfeit() -> bool:
	return forfeit_policy == ForfeitPolicy.ALLOWED


func _is_slug(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value != value.to_lower():
		return false
	if value.begins_with("-") or value.ends_with("-") or value.contains("--"):
		return false
	for character_index in value.length():
		var codepoint := value.unicode_at(character_index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 97 and codepoint <= 122)
			or codepoint == 45
		):
			return false
	return true


func _is_safe_api_name(value: String) -> bool:
	if value.is_empty() or value != value.strip_edges() or value.length() > 18:
		return false
	if value.contains("|") or value.contains(","):
		return false
	if value.contains("[") or value.contains("]") or value.contains("  "):
		return false
	if value.contains("\u202e"):
		return false
	for character in value:
		if character == "\n" or character == "\r" or character == "\t":
			return false
	return true
