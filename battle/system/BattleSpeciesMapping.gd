class_name BattleSpeciesMapping
extends RefCounted

## Read-only bridge from local PokeAPI Pokemon IDs to the identifiers pinned by
## the battle server's Pokemon Showdown runtime.

const MAPPING_PATH := "res://battle/data/pokeapi_showdown_mapping.json"
const SCHEMA_VERSION := 2
const SHOWDOWN_VERSION := "0.11.11"
const CANONICAL_MOVE_TYPES := {
	"Bug": true,
	"Dark": true,
	"Dragon": true,
	"Electric": true,
	"Fairy": true,
	"Fighting": true,
	"Fire": true,
	"Flying": true,
	"Ghost": true,
	"Grass": true,
	"Ground": true,
	"Ice": true,
	"Normal": true,
	"Poison": true,
	"Psychic": true,
	"Rock": true,
	"Steel": true,
	"Water": true,
}

static var _load_attempted := false
static var _mappings: Dictionary = {}
static var _move_ids: Dictionary = {}
static var _move_types: Dictionary = {}
static var _unsupported_ids: Array[int] = []
static var _source_pokemon_count := 0
static var _last_error := ""


static func has_mapping(pokemon_id: int) -> bool:
	return _ensure_loaded() and _mappings.has(str(pokemon_id))


static func get_entry(pokemon_id: int) -> Dictionary:
	if not _ensure_loaded():
		return {}
	var key := str(pokemon_id)
	if not _mappings.has(key):
		_last_error = "Pokemon ID %d has no battle mapping" % pokemon_id
		return {}
	_last_error = ""
	var entry: Dictionary = _mappings[key]
	return entry.duplicate(true)


static func has_move_id(move_id: String) -> bool:
	return _ensure_loaded() and _move_ids.has(move_id)


static func get_move_type(move_id: String) -> String:
	if not _ensure_loaded():
		return ""
	return str(_move_types.get(move_id, ""))


static func get_pokedex_dimensions(pokemon_id: int) -> Dictionary:
	if not _ensure_loaded():
		return {}
	var key := str(pokemon_id)
	if not _mappings.has(key):
		return {}
	var entry: Dictionary = _mappings[key]
	return {
		"height_dm": int(entry["pokedexHeightDm"]),
		"weight_hg": int(entry["pokedexWeightHg"]),
	}


static func get_supported_count() -> int:
	return _mappings.size() if _ensure_loaded() else 0


static func get_source_pokemon_count() -> int:
	return _source_pokemon_count if _ensure_loaded() else 0


static func get_unsupported_pokemon_ids() -> Array[int]:
	if not _ensure_loaded():
		return []
	return _unsupported_ids.duplicate()


static func get_last_error() -> String:
	return _last_error


static func _ensure_loaded() -> bool:
	if _load_attempted:
		return not _mappings.is_empty()
	_load_attempted = true
	_last_error = ""

	if not FileAccess.file_exists(MAPPING_PATH):
		_last_error = "Battle mapping is missing: %s" % MAPPING_PATH
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAPPING_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "Battle mapping is not a JSON object"
		return false
	var document: Dictionary = parsed
	if int(document.get("schemaVersion", -1)) != SCHEMA_VERSION:
		_last_error = "Battle mapping schema version is incompatible"
		return false
	if str(document.get("pokemonShowdownVersion", "")) != SHOWDOWN_VERSION:
		_last_error = "Battle mapping Pokemon Showdown version is incompatible"
		return false
	var dataset_sha256 := str(document.get("pokeapiDatasetSha256", ""))
	if dataset_sha256.length() != 64 or not dataset_sha256.is_valid_hex_number(false):
		_last_error = "Battle mapping PokeAPI dataset provenance is invalid"
		return false
	var mappings_value: Variant = document.get("mappings")
	var unsupported_value: Variant = document.get("unsupportedPokemonIds")
	var move_ids_value: Variant = document.get("validMoveIds")
	var move_types_value: Variant = document.get("moveTypes")
	if (
		typeof(mappings_value) != TYPE_DICTIONARY
		or typeof(unsupported_value) != TYPE_ARRAY
		or typeof(move_ids_value) != TYPE_ARRAY
		or typeof(move_types_value) != TYPE_DICTIONARY
	):
		_last_error = "Battle mapping has invalid entry collections"
		return false
	var validated_move_ids: Dictionary = {}
	for move_id_value: Variant in move_ids_value:
		if typeof(move_id_value) != TYPE_STRING:
			_last_error = "Battle mapping contains a non-string move ID"
			return false
		var move_id: String = move_id_value
		if not _is_identifier(move_id) or validated_move_ids.has(move_id):
			_last_error = "Battle mapping contains an invalid or duplicate move ID"
			return false
		validated_move_ids[move_id] = true
	if validated_move_ids.is_empty():
		_last_error = "Battle mapping contains no move IDs"
		return false

	var validated_move_types: Dictionary = {}
	if move_types_value.size() != validated_move_ids.size():
		_last_error = "Battle mapping move type count is inconsistent"
		return false
	for move_id_value: Variant in move_types_value.keys():
		if typeof(move_id_value) != TYPE_STRING:
			_last_error = "Battle mapping contains a non-string move type key"
			return false
		var move_id: String = move_id_value
		var move_type_value: Variant = move_types_value[move_id_value]
		if not validated_move_ids.has(move_id):
			_last_error = "Battle mapping contains a move type for an unknown move ID"
			return false
		if typeof(move_type_value) != TYPE_STRING or not CANONICAL_MOVE_TYPES.has(move_type_value):
			_last_error = "Battle mapping contains an invalid type for move %s" % move_id
			return false
		validated_move_types[move_id] = move_type_value
	for move_id: String in validated_move_ids.keys():
		if not validated_move_types.has(move_id):
			_last_error = "Battle mapping has no type for move %s" % move_id
			return false

	var validated_mappings: Dictionary = {}
	for pokemon_id_value: Variant in mappings_value.keys():
		var pokemon_id_text := str(pokemon_id_value)
		if not pokemon_id_text.is_valid_int() or int(pokemon_id_text) <= 0:
			_last_error = "Battle mapping contains an invalid Pokemon ID"
			return false
		var entry_value: Variant = mappings_value[pokemon_id_value]
		if typeof(entry_value) != TYPE_DICTIONARY:
			_last_error = "Battle mapping entry %s is not an object" % pokemon_id_text
			return false
		var entry: Dictionary = entry_value
		if not _valid_entry(entry, validated_move_ids):
			_last_error = "Battle mapping entry %s is invalid" % pokemon_id_text
			return false
		validated_mappings[pokemon_id_text] = entry.duplicate(true)

	var validated_unsupported: Array[int] = []
	for pokemon_id_value: Variant in unsupported_value:
		if not _is_integer_value(pokemon_id_value) or int(pokemon_id_value) <= 0:
			_last_error = "Battle mapping has an invalid unsupported Pokemon ID"
			return false
		var pokemon_id := int(pokemon_id_value)
		if validated_mappings.has(str(pokemon_id)) or pokemon_id in validated_unsupported:
			_last_error = "Battle mapping repeats Pokemon ID %d" % pokemon_id
			return false
		validated_unsupported.append(pokemon_id)

	var source_count_value: Variant = document.get("sourcePokemonCount")
	var supported_count_value: Variant = document.get("supportedPokemonCount")
	if (
		not _is_integer_value(source_count_value)
		or not _is_integer_value(supported_count_value)
		or int(supported_count_value) != validated_mappings.size()
		or int(source_count_value) != validated_mappings.size() + validated_unsupported.size()
	):
		_last_error = "Battle mapping counts are inconsistent"
		return false

	_mappings = validated_mappings
	_move_ids = validated_move_ids
	_move_types = validated_move_types
	_unsupported_ids = validated_unsupported
	_source_pokemon_count = int(source_count_value)
	return true


static func _valid_entry(entry: Dictionary, valid_move_ids: Dictionary) -> bool:
	if typeof(entry.get("species")) != TYPE_STRING:
		return false
	if str(entry["species"]).strip_edges().is_empty():
		return false
	if typeof(entry.get("spriteId")) != TYPE_STRING:
		return false
	if not _is_identifier(str(entry["spriteId"])):
		return false
	if (
		not _is_integer_value(entry.get("pokedexHeightDm"))
		or int(entry["pokedexHeightDm"]) <= 0
		or not _is_integer_value(entry.get("pokedexWeightHg"))
		or int(entry["pokedexWeightHg"]) < 0
	):
		return false
	var moves_value: Variant = entry.get("defaultMoves")
	if typeof(moves_value) != TYPE_ARRAY or moves_value.is_empty() or moves_value.size() > 4:
		return false
	var seen_moves: Dictionary = {}
	for move_value: Variant in moves_value:
		if typeof(move_value) != TYPE_STRING or not _is_identifier(str(move_value)):
			return false
		if not valid_move_ids.has(move_value):
			return false
		if seen_moves.has(move_value):
			return false
		seen_moves[move_value] = true
	return true


static func _is_identifier(value: String) -> bool:
	if value.is_empty() or value.length() > 128:
		return false
	for character_index in value.length():
		var codepoint := value.unicode_at(character_index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 65 and codepoint <= 90)
			or (codepoint >= 97 and codepoint <= 122)
			or codepoint == 45
		):
			return false
	return true


static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), float(int(value)))
