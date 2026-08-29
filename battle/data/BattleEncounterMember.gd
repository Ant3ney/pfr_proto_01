class_name BattleEncounterMember
extends Resource

## One editor-authored opponent roster member. Optional Showdown set fields are
## intentionally absent so the REST service applies its documented defaults.

const SpeciesMapping := preload("res://battle/system/BattleSpeciesMapping.gd")

@export var member_id := ""
@export var pokemon_id := 0
@export var species := ""
@export var sprite_id := ""
@export_range(1, 100, 1) var level := 1
@export_range(0.0, 1.0, 0.001) var health := 1.0
@export var moves: Array[String] = []


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if (
		member_id.strip_edges().is_empty()
		or member_id != member_id.strip_edges()
		or member_id.length() > 128
	):
		errors.append("member_id must contain between 1 and 128 characters")
	if pokemon_id <= 0:
		errors.append("pokemon_id must be positive")
	if level < 1 or level > 100:
		errors.append("level must be between 1 and 100")
	if not is_finite(health) or health < 0.0 or health > 1.0:
		errors.append("health must be between 0.0 and 1.0")
	if moves.is_empty() or moves.size() > 4:
		errors.append("moves must contain between 1 and 4 move IDs")
	else:
		var seen_moves: Dictionary = {}
		for move_id in moves:
			if not _is_showdown_id(move_id):
				errors.append("invalid Showdown move ID: %s" % move_id)
			elif not SpeciesMapping.has_move_id(move_id):
				errors.append("unknown Showdown move ID: %s" % move_id)
			elif seen_moves.has(move_id):
				errors.append("duplicate move ID: %s" % move_id)
			seen_moves[move_id] = true

	var mapping: Dictionary = SpeciesMapping.get_entry(pokemon_id)
	if pokemon_id > 0 and mapping.is_empty():
		errors.append("pokemon_id %d has no battle mapping" % pokemon_id)
	elif not mapping.is_empty():
		if species != str(mapping["species"]):
			errors.append("species does not match pokemon_id %d" % pokemon_id)
		if sprite_id != str(mapping["spriteId"]):
			errors.append("sprite_id does not match pokemon_id %d" % pokemon_id)
	return errors


func to_server_member() -> Dictionary:
	if not validate().is_empty():
		return {}
	return {
		"memberId": member_id,
		"species": species,
		"level": level,
		"health": health,
		"moves": moves.duplicate(),
	}


func to_presentation_member() -> Dictionary:
	if not validate().is_empty():
		return {}
	return {
		"memberId": member_id,
		"pokemonId": pokemon_id,
		"species": species,
		"spriteId": sprite_id,
		"level": level,
		"health": health,
		"moves": moves.duplicate(),
	}


func _is_showdown_id(value: String) -> bool:
	if value.is_empty() or value.length() > 128 or value != value.to_lower():
		return false
	for character_index in value.length():
		var codepoint := value.unicode_at(character_index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 97 and codepoint <= 122)
		):
			return false
	return true
