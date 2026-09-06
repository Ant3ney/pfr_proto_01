class_name MoveLearnsetCatalog
extends RefCounted

## Read-only access to the generated PokeAPI level-up learnset catalog.

const DATA_PATH := "res://game/progression/move_learning/data/level_up_learnsets.json"
const SCHEMA_VERSION := 1
const SpeciesMapping := preload("res://game/battle/system/battle_species_mapping.gd")

static var _load_attempted := false
static var _rows_by_pokemon_id: Dictionary = {}
static var _move_names: Dictionary = {}
static var _version_groups: Array[String] = []
static var _last_error := ""


static func get_level_up_moves(pokemon_id: int) -> Array[Dictionary]:
	if not _ensure_loaded():
		return []
	var row_value: Variant = _rows_by_pokemon_id.get(pokemon_id)
	if typeof(row_value) != TYPE_DICTIONARY:
		_last_error = "Pokemon ID %d has no level-up learnset" % pokemon_id
		return []
	var row := row_value as Dictionary
	var result: Array[Dictionary] = []
	for move_value: Variant in row.get("moves", []):
		var move_row := move_value as Array
		var move_id := String(move_row[1])
		result.append({
			"level": int(move_row[0]),
			"moveId": move_id,
			"name": get_move_name(move_id),
			"type": SpeciesMapping.get_move_type(move_id),
		})
	_last_error = ""
	return result


static func get_moves_learned_between(
	pokemon_id: int,
	previous_level: int,
	current_level: int
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if current_level <= previous_level:
		return result
	for move in get_level_up_moves(pokemon_id):
		var learned_level := int(move.get("level", 0))
		if learned_level > previous_level and learned_level <= current_level:
			result.append(move.duplicate(true))
	return result


static func get_learnset_source(pokemon_id: int) -> Dictionary:
	if not _ensure_loaded():
		return {}
	var row_value: Variant = _rows_by_pokemon_id.get(pokemon_id)
	if typeof(row_value) != TYPE_DICTIONARY:
		return {}
	var row := row_value as Dictionary
	return {
		"pokemonId": pokemon_id,
		"sourcePokemonId": int(row.get("sourcePokemonId", 0)),
		"versionGroup": String(row.get("versionGroup", "")),
	}


static func get_move_name(move_id: String) -> String:
	if _ensure_loaded() and _move_names.has(move_id):
		return String(_move_names[move_id])
	return _humanize_identifier(move_id)


static func get_last_error() -> String:
	return _last_error


static func reload_data() -> bool:
	_load_attempted = false
	_rows_by_pokemon_id.clear()
	_move_names.clear()
	_version_groups.clear()
	_last_error = ""
	return _ensure_loaded()


static func _ensure_loaded() -> bool:
	if _load_attempted:
		return not _rows_by_pokemon_id.is_empty()
	_load_attempted = true
	if not FileAccess.file_exists(DATA_PATH):
		return _fail("Move learnset catalog is missing: %s" % DATA_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("Move learnset catalog is not a JSON object")
	var document := parsed as Dictionary
	if int(document.get("schemaVersion", -1)) != SCHEMA_VERSION:
		return _fail("Move learnset catalog schema is incompatible")
	var version_value: Variant = document.get("versionGroups")
	var names_value: Variant = document.get("moveNames")
	var rows_value: Variant = document.get("pokemonRows")
	if (
		typeof(version_value) != TYPE_ARRAY
		or typeof(names_value) != TYPE_DICTIONARY
		or typeof(rows_value) != TYPE_ARRAY
	):
		return _fail("Move learnset catalog collections are invalid")
	for value: Variant in version_value as Array:
		if typeof(value) != TYPE_STRING or String(value).is_empty():
			return _fail("Move learnset catalog has an invalid version group")
		_version_groups.append(String(value))
	if _version_groups.is_empty():
		return _fail("Move learnset catalog has no version groups")
	_move_names = (names_value as Dictionary).duplicate(true)

	var rows: Array = rows_value
	for row_value: Variant in rows:
		if typeof(row_value) != TYPE_ARRAY or (row_value as Array).size() != 4:
			return _fail("Move learnset catalog contains an invalid Pokemon row")
		var row := row_value as Array
		var pokemon_id := int(row[0])
		var source_pokemon_id := int(row[1])
		var version_group_index := int(row[2])
		var moves_value: Variant = row[3]
		if (
			pokemon_id <= 0
			or source_pokemon_id <= 0
			or _rows_by_pokemon_id.has(pokemon_id)
			or version_group_index < 0
			or version_group_index >= _version_groups.size()
			or typeof(moves_value) != TYPE_ARRAY
			or (moves_value as Array).is_empty()
		):
			return _fail("Move learnset catalog contains invalid Pokemon metadata")
		var validated_moves: Array = []
		for move_value: Variant in moves_value as Array:
			if typeof(move_value) != TYPE_ARRAY or (move_value as Array).size() != 2:
				return _fail("Move learnset catalog contains an invalid move row")
			var move_row := move_value as Array
			var level := int(move_row[0])
			var move_id := String(move_row[1])
			if (
				level < 1
				or level > 100
				or move_id.is_empty()
				or not SpeciesMapping.has_move_id(move_id)
				or not _move_names.has(move_id)
			):
				return _fail("Move learnset catalog contains an invalid level-up move")
			validated_moves.append([level, move_id])
		_rows_by_pokemon_id[pokemon_id] = {
			"sourcePokemonId": source_pokemon_id,
			"versionGroup": _version_groups[version_group_index],
			"moves": validated_moves,
		}
	if _rows_by_pokemon_id.size() != int(document.get("sourcePokemonCount", -1)):
		return _fail("Move learnset catalog Pokemon count is inconsistent")
	_last_error = ""
	return true


static func _humanize_identifier(value: String) -> String:
	if value.is_empty():
		return "Unknown Move"
	var words := value.replace("-", " ").split(" ", false)
	for index in words.size():
		words[index] = words[index].capitalize()
	return " ".join(words)


static func _fail(message: String) -> bool:
	_last_error = message
	push_error(message)
	return false
