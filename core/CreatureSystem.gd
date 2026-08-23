extends Node

## Offline Creature System backed by the vendored PokeAPI snapshot.
##
## `get_creature()` preserves every field from PokeAPI's Pokemon record and
## adds `species_data` and `evolution_chain_data` dictionaries containing the
## complete associated records. Returned dictionaries are deep copies, so a
## caller cannot mutate the cached source data.

const DATA_ROOT := "res://data/creatures"
const INDEX_PATH := DATA_ROOT + "/index.json"
const MAX_DECOMPRESSED_RECORD_BYTES := 8 * 1024 * 1024
const CACHE_CAPACITY := 16

var _entries_by_id: Dictionary = {}
var _ids_by_name: Dictionary = {}
var _all_ids: Array[int] = []
var _default_ids: Array[int] = []
var _creature_cache: Dictionary = {}
var _cache_order: Array[int] = []
var _index_load_attempted := false
var _index_loaded := false
var _last_error := ""


func _ready() -> void:
	_ensure_index_loaded()


## Returns a complete local PokeAPI object for a numeric Pokemon ID.
## Invalid IDs or unavailable data return an empty dictionary; inspect
## `get_last_error()` for the reason.
func get_creature(pokemon_id: int) -> Dictionary:
	_last_error = ""
	if not _ensure_index_loaded():
		return {}
	if not _entries_by_id.has(pokemon_id):
		_last_error = "Unknown Pokemon ID: %d" % pokemon_id
		return {}

	if _creature_cache.has(pokemon_id):
		_touch_cache_entry(pokemon_id)
		var cached: Dictionary = _creature_cache[pokemon_id]
		return cached.duplicate(true)

	var entry: Dictionary = _entries_by_id[pokemon_id]
	var pokemon_data := _read_compressed_json(
		DATA_ROOT + "/pokemon/%d.json.gz" % pokemon_id
	)
	if pokemon_data.is_empty():
		return {}

	var species_id := int(entry["species_id"])
	var species_data := _read_compressed_json(
		DATA_ROOT + "/species/%d.json.gz" % species_id
	)
	if species_data.is_empty():
		return {}

	var evolution_chain_id := int(entry["evolution_chain_id"])
	var evolution_chain_data := _read_compressed_json(
		DATA_ROOT + "/evolution_chains/%d.json.gz" % evolution_chain_id
	)
	if evolution_chain_data.is_empty():
		return {}

	var complete_data := pokemon_data.duplicate(true)
	complete_data["species_data"] = species_data
	complete_data["evolution_chain_data"] = evolution_chain_data
	_store_cache_entry(pokemon_id, complete_data)
	return complete_data.duplicate(true)


## Natural alias for systems that still call the records Pokemon.
func get_pokemon(pokemon_id: int) -> Dictionary:
	return get_creature(pokemon_id)


## Optional name lookup using PokeAPI slugs such as `mr-mime` or
## `deoxys-attack`. The numeric-ID API remains the canonical interface.
func get_creature_by_name(pokemon_name: String) -> Dictionary:
	var pokemon_id := get_pokemon_id(pokemon_name)
	if pokemon_id < 0:
		return {}
	return get_creature(pokemon_id)


## Returns the numeric ID for a PokeAPI name, or -1 when it is unknown.
func get_pokemon_id(pokemon_name: String) -> int:
	_last_error = ""
	if not _ensure_index_loaded():
		return -1
	var normalized_name := pokemon_name.strip_edges().to_lower()
	normalized_name = normalized_name.replace("_", "-").replace(" ", "-")
	if not _ids_by_name.has(normalized_name):
		_last_error = "Unknown Pokemon name: %s" % pokemon_name
		return -1
	return int(_ids_by_name[normalized_name])


func has_pokemon(pokemon_id: int) -> bool:
	return _ensure_index_loaded() and _entries_by_id.has(pokemon_id)


## Includes alternate and battle forms by default.
func get_pokemon_count(include_alternate_forms := true) -> int:
	if not _ensure_index_loaded():
		return 0
	return _all_ids.size() if include_alternate_forms else _default_ids.size()


## Includes alternate and battle forms by default.
func get_pokemon_ids(include_alternate_forms := true) -> Array[int]:
	if not _ensure_index_loaded():
		return []
	if include_alternate_forms:
		return _all_ids.duplicate()
	return _default_ids.duplicate()


func get_last_error() -> String:
	return _last_error


func clear_cache() -> void:
	_creature_cache.clear()
	_cache_order.clear()


## Reloads the on-disk index and clears all cached creature objects.
func reload_data() -> bool:
	_entries_by_id.clear()
	_ids_by_name.clear()
	_all_ids.clear()
	_default_ids.clear()
	clear_cache()
	_index_load_attempted = false
	_index_loaded = false
	_last_error = ""
	return _ensure_index_loaded()


func _ensure_index_loaded() -> bool:
	if _index_loaded:
		return true
	if _index_load_attempted:
		return false
	_index_load_attempted = true

	if not FileAccess.file_exists(INDEX_PATH):
		_fail("Creature index is missing: %s" % INDEX_PATH)
		return false
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(INDEX_PATH)
	)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Creature index is not a JSON object: %s" % INDEX_PATH)
		return false

	var index_data: Dictionary = parsed
	var pokemon_entries: Variant = index_data.get("pokemon")
	if typeof(pokemon_entries) != TYPE_ARRAY:
		_fail("Creature index has no Pokemon entry list")
		return false

	for entry_value: Variant in pokemon_entries:
		if typeof(entry_value) != TYPE_DICTIONARY:
			_fail("Creature index contains a non-object entry")
			_reset_failed_index()
			return false
		var entry: Dictionary = entry_value
		var pokemon_id := int(entry.get("id", 0))
		var pokemon_name := str(entry.get("name", ""))
		var species_id := int(entry.get("species_id", 0))
		var evolution_chain_id := int(entry.get("evolution_chain_id", 0))
		if (
			pokemon_id <= 0
			or pokemon_name.is_empty()
			or species_id <= 0
			or evolution_chain_id <= 0
			or _entries_by_id.has(pokemon_id)
			or _ids_by_name.has(pokemon_name)
		):
			_fail("Creature index contains an invalid or duplicate entry")
			_reset_failed_index()
			return false
		_entries_by_id[pokemon_id] = entry
		_ids_by_name[pokemon_name] = pokemon_id
		_all_ids.append(pokemon_id)
		if bool(entry.get("is_default", false)):
			_default_ids.append(pokemon_id)

	if int(index_data.get("pokemon_count", -1)) != _all_ids.size():
		_fail("Creature index Pokemon count is inconsistent")
		_reset_failed_index()
		return false
	if (
		int(index_data.get("default_pokemon_count", -1))
		!= _default_ids.size()
	):
		_fail("Creature index default-Pokemon count is inconsistent")
		_reset_failed_index()
		return false

	_index_loaded = true
	return true


func _read_compressed_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		_fail("Creature data record is missing: %s" % path)
		return {}
	var compressed := FileAccess.get_file_as_bytes(path)
	if compressed.is_empty():
		_fail("Creature data record is empty or unreadable: %s" % path)
		return {}
	var decompressed := compressed.decompress_dynamic(
		MAX_DECOMPRESSED_RECORD_BYTES,
		FileAccess.COMPRESSION_GZIP
	)
	if decompressed.is_empty():
		_fail("Creature data record could not be decompressed: %s" % path)
		return {}

	var parser := JSON.new()
	var parse_error := parser.parse(decompressed.get_string_from_utf8())
	if parse_error != OK:
		_fail(
			"Creature data JSON failed at line %d in %s: %s" % [
				parser.get_error_line(),
				path,
				parser.get_error_message(),
			]
		)
		return {}
	if typeof(parser.data) != TYPE_DICTIONARY:
		_fail("Creature data record is not a JSON object: %s" % path)
		return {}
	return parser.data


func _store_cache_entry(pokemon_id: int, creature_data: Dictionary) -> void:
	if _creature_cache.has(pokemon_id):
		_cache_order.erase(pokemon_id)
	_creature_cache[pokemon_id] = creature_data
	_cache_order.append(pokemon_id)
	while _cache_order.size() > CACHE_CAPACITY:
		var evicted_id := _cache_order.pop_front()
		_creature_cache.erase(evicted_id)


func _touch_cache_entry(pokemon_id: int) -> void:
	_cache_order.erase(pokemon_id)
	_cache_order.append(pokemon_id)


func _reset_failed_index() -> void:
	_entries_by_id.clear()
	_ids_by_name.clear()
	_all_ids.clear()
	_default_ids.clear()
	_index_loaded = false


func _fail(message: String) -> void:
	_last_error = message
	push_error(message)
