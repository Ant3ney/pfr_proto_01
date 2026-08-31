extends Node

## Offline Creature System backed by the vendored PokeAPI snapshot.
##
## `get_creature()` preserves every field from PokeAPI's Pokemon record and
## adds `encounters_data`, `species_data`, and `evolution_chain_data` containing
## the complete associated records, plus project `evolution_options` and local
## experience metadata. Returned dictionaries are deep copies, so a caller
## cannot mutate the cached source data.

const DATA_ROOT := "res://data/creatures"
const INDEX_PATH := DATA_ROOT + "/index.json"
const MAX_DECOMPRESSED_RECORD_BYTES := 8 * 1024 * 1024
const CACHE_CAPACITY := 16
const MIN_POKEMON_LEVEL := 1
const MAX_POKEMON_LEVEL := 100
const DEFAULT_FIRST_EVOLUTION_LEVEL := 20
const DEFAULT_SECOND_EVOLUTION_LEVEL := 36
const Experience := preload("res://core/CreatureExperience.gd")

var _entries_by_id: Dictionary = {}
var _ids_by_name: Dictionary = {}
var _default_id_by_species_id: Dictionary = {}
var _all_ids: Array[int] = []
var _default_ids: Array[int] = []
var _creature_cache: Dictionary = {}
var _cache_order: Array[int] = []
var _evolution_options_cache: Dictionary = {}
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

	var encounters_data := _read_compressed_json_array(
		DATA_ROOT + "/encounters/%d.json.gz" % pokemon_id
	)
	if not _last_error.is_empty():
		return {}

	var complete_data := pokemon_data.duplicate(true)
	complete_data["encounters_data"] = encounters_data
	complete_data["species_data"] = species_data
	complete_data["evolution_chain_data"] = evolution_chain_data
	var evolution_options := get_evolution_options(pokemon_id)
	if not _last_error.is_empty():
		return {}
	complete_data["evolution_options"] = evolution_options
	var experience_profile := Experience.get_profile(pokemon_id)
	if experience_profile.is_empty():
		_fail(Experience.get_last_error())
		return {}
	complete_data["xp_multiplier"] = experience_profile["xpMultiplier"]
	complete_data["experience_data"] = {
		"growth_rate": experience_profile["growthRate"],
		"growth_rate_index": experience_profile["growthRateIndex"],
		"community_tier": experience_profile["communityTier"],
		"xp_multiplier": experience_profile["xpMultiplier"],
		"experience_by_level": Experience.get_experience_curve(pokemon_id),
	}
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


## Returns every direct evolution for a default-form Pokemon. Each option has
## one project level requirement regardless of the source game's item, trade,
## friendship, location, time, or stat rule. PokeAPI minimum levels are kept;
## branches without one inherit an authored sibling level when possible, then
## use the stage defaults (20 for the first evolution and 36 for the second).
func get_evolution_options(pokemon_id: int) -> Array[Dictionary]:
	_last_error = ""
	if not _ensure_index_loaded():
		return []
	if not _entries_by_id.has(pokemon_id):
		_last_error = "Unknown Pokemon ID: %d" % pokemon_id
		return []
	if _evolution_options_cache.has(pokemon_id):
		var cached: Array = _evolution_options_cache[pokemon_id]
		return cached.duplicate(true)

	var entry: Dictionary = _entries_by_id[pokemon_id]
	# Evolution chains identify species rather than individual battle/forms.
	# Offering a default-species evolution for an alternate form would silently
	# discard that form, so forms remain ineligible until explicitly mapped.
	if not bool(entry.get("is_default", false)):
		_evolution_options_cache[pokemon_id] = []
		return []

	var evolution_chain_id := int(entry.get("evolution_chain_id", 0))
	var chain_data := _read_compressed_json(
		DATA_ROOT + "/evolution_chains/%d.json.gz" % evolution_chain_id
	)
	if chain_data.is_empty():
		return []
	var found := _find_evolution_node(
		chain_data.get("chain"),
		int(entry.get("species_id", 0)),
		0
	)
	if found.is_empty():
		_fail("Pokemon ID %d is missing from evolution chain %d" % [pokemon_id, evolution_chain_id])
		return []

	var node := found.get("node", {}) as Dictionary
	var children_value: Variant = node.get("evolves_to", [])
	if typeof(children_value) != TYPE_ARRAY:
		_fail("Evolution chain %d has invalid child data" % evolution_chain_id)
		return []
	var children := children_value as Array
	var target_stage := int(found.get("depth", 0)) + 1
	var sibling_level := _minimum_authored_evolution_level(children)
	var options: Array[Dictionary] = []
	for child_value: Variant in children:
		if typeof(child_value) != TYPE_DICTIONARY:
			_fail("Evolution chain %d contains a non-object stage" % evolution_chain_id)
			return []
		var child := child_value as Dictionary
		var species_value: Variant = child.get("species")
		if typeof(species_value) != TYPE_DICTIONARY:
			_fail("Evolution chain %d contains an invalid target species" % evolution_chain_id)
			return []
		var species := species_value as Dictionary
		var target_species_id := _resource_id(species)
		if target_species_id <= 0 or not _default_id_by_species_id.has(target_species_id):
			_fail("Evolution chain %d targets an unknown species" % evolution_chain_id)
			return []
		var required_level := _minimum_authored_evolution_level([child])
		var level_source := "pokeapi"
		if required_level <= 0 and sibling_level > 0:
			required_level = sibling_level
			level_source = "branch"
		elif required_level <= 0:
			required_level = _default_level_for_evolution_stage(target_stage)
			level_source = "stage-default"
		options.append({
			"pokemonId": int(_default_id_by_species_id[target_species_id]),
			"name": String(species.get("name", "")),
			"requiredLevel": required_level,
			"stage": target_stage,
			"levelSource": level_source,
		})

	_evolution_options_cache[pokemon_id] = options.duplicate(true)
	return options.duplicate(true)


## Filters direct evolution options to those whose level has been reached.
func get_available_evolutions(pokemon_id: int, level: int) -> Array[Dictionary]:
	_last_error = ""
	if level < MIN_POKEMON_LEVEL or level > MAX_POKEMON_LEVEL:
		_last_error = "Pokemon level must be between %d and %d" % [
			MIN_POKEMON_LEVEL,
			MAX_POKEMON_LEVEL,
		]
		return []
	var available: Array[Dictionary] = []
	for option in get_evolution_options(pokemon_id):
		if level >= int(option.get("requiredLevel", MAX_POKEMON_LEVEL + 1)):
			available.append(option.duplicate(true))
	return available


func can_evolve(pokemon_id: int, level: int) -> bool:
	return not get_available_evolutions(pokemon_id, level).is_empty()


## Returns cumulative XP required to reach `level` for this Pokemon's growth
## curve. Level 1 is zero and level 100 is the final threshold.
func get_experience_for_level(pokemon_id: int, level: int) -> int:
	_last_error = ""
	var result := Experience.get_experience_for_level(pokemon_id, level)
	if result < 0:
		_last_error = Experience.get_last_error()
	return result


func get_experience_to_next_level(pokemon_id: int, level: int) -> int:
	_last_error = ""
	var result := Experience.get_experience_to_next_level(pokemon_id, level)
	if result < 0:
		_last_error = Experience.get_last_error()
	return result


func get_level_for_experience(pokemon_id: int, current_xp: int) -> int:
	_last_error = ""
	var result := Experience.get_level_for_experience(pokemon_id, current_xp)
	if result < 0:
		_last_error = Experience.get_last_error()
	return result


func get_experience_progress(pokemon_id: int, current_xp: int) -> Dictionary:
	_last_error = ""
	var result := Experience.get_progress(pokemon_id, current_xp)
	if result.is_empty():
		_last_error = Experience.get_last_error()
	return result


func get_xp_multiplier(pokemon_id: int) -> float:
	return float(get_experience_profile(pokemon_id).get("xpMultiplier", 0.0))


func get_experience_profile(pokemon_id: int) -> Dictionary:
	_last_error = ""
	var result := Experience.get_profile(pokemon_id)
	if result.is_empty():
		_last_error = Experience.get_last_error()
	return result


func get_experience_growth_table() -> Array[PackedInt32Array]:
	return Experience.get_growth_table()


func get_experience_growth_rate_names() -> Array[String]:
	return Experience.get_growth_rate_names()


func get_last_error() -> String:
	return _last_error


func clear_cache() -> void:
	_creature_cache.clear()
	_cache_order.clear()
	_evolution_options_cache.clear()


## Reloads the on-disk index and clears all cached creature objects.
func reload_data() -> bool:
	_entries_by_id.clear()
	_ids_by_name.clear()
	_default_id_by_species_id.clear()
	_all_ids.clear()
	_default_ids.clear()
	clear_cache()
	_index_load_attempted = false
	_index_loaded = false
	_last_error = ""
	return Experience.reload_data() and _ensure_index_loaded()


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
			if _default_id_by_species_id.has(species_id):
				_fail("Creature index repeats a default species ID")
				_reset_failed_index()
				return false
			_default_id_by_species_id[species_id] = pokemon_id
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
	var parsed: Variant = _read_compressed_json_value(path)
	if parsed == null:
		return {}
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("Creature data record is not a JSON object: %s" % path)
		return {}
	return parsed


func _read_compressed_json_array(path: String) -> Array:
	var parsed: Variant = _read_compressed_json_value(path)
	if parsed == null:
		return []
	if typeof(parsed) != TYPE_ARRAY:
		_fail("Creature data record is not a JSON array: %s" % path)
		return []
	return parsed


func _read_compressed_json_value(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("Creature data record is missing: %s" % path)
		return null
	var compressed := FileAccess.get_file_as_bytes(path)
	if compressed.is_empty():
		_fail("Creature data record is empty or unreadable: %s" % path)
		return null
	var decompressed := compressed.decompress_dynamic(
		MAX_DECOMPRESSED_RECORD_BYTES,
		FileAccess.COMPRESSION_GZIP
	)
	if decompressed.is_empty():
		_fail("Creature data record could not be decompressed: %s" % path)
		return null

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
		return null
	return parser.data


func _store_cache_entry(pokemon_id: int, creature_data: Dictionary) -> void:
	if _creature_cache.has(pokemon_id):
		_cache_order.erase(pokemon_id)
	_creature_cache[pokemon_id] = creature_data
	_cache_order.append(pokemon_id)
	while _cache_order.size() > CACHE_CAPACITY:
		var evicted_id: int = _cache_order.pop_front()
		_creature_cache.erase(evicted_id)


func _touch_cache_entry(pokemon_id: int) -> void:
	_cache_order.erase(pokemon_id)
	_cache_order.append(pokemon_id)


func _find_evolution_node(value: Variant, species_id: int, depth: int) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var node := value as Dictionary
	var species_value: Variant = node.get("species")
	if typeof(species_value) == TYPE_DICTIONARY:
		if _resource_id(species_value as Dictionary) == species_id:
			return {"node": node, "depth": depth}
	var children_value: Variant = node.get("evolves_to", [])
	if typeof(children_value) != TYPE_ARRAY:
		return {}
	for child_value: Variant in children_value as Array:
		var found := _find_evolution_node(child_value, species_id, depth + 1)
		if not found.is_empty():
			return found
	return {}


func _minimum_authored_evolution_level(children: Array) -> int:
	var minimum_level := MAX_POKEMON_LEVEL + 1
	for child_value: Variant in children:
		if typeof(child_value) != TYPE_DICTIONARY:
			continue
		var details_value: Variant = (child_value as Dictionary).get("evolution_details", [])
		if typeof(details_value) != TYPE_ARRAY:
			continue
		for detail_value: Variant in details_value as Array:
			if typeof(detail_value) != TYPE_DICTIONARY:
				continue
			var level_value: Variant = (detail_value as Dictionary).get("min_level")
			if typeof(level_value) not in [TYPE_INT, TYPE_FLOAT]:
				continue
			var level := int(level_value)
			if level >= MIN_POKEMON_LEVEL and level <= MAX_POKEMON_LEVEL:
				minimum_level = mini(minimum_level, level)
	return -1 if minimum_level > MAX_POKEMON_LEVEL else minimum_level


func _default_level_for_evolution_stage(stage: int) -> int:
	return DEFAULT_FIRST_EVOLUTION_LEVEL if stage <= 1 else DEFAULT_SECOND_EVOLUTION_LEVEL


func _resource_id(resource: Dictionary) -> int:
	var url := String(resource.get("url", "")).trim_suffix("/")
	var separator := url.rfind("/")
	if separator < 0:
		return -1
	var id_text := url.substr(separator + 1)
	return int(id_text) if id_text.is_valid_int() else -1


func _reset_failed_index() -> void:
	_entries_by_id.clear()
	_ids_by_name.clear()
	_default_id_by_species_id.clear()
	_all_ids.clear()
	_default_ids.clear()
	_evolution_options_cache.clear()
	_index_loaded = false


func _fail(message: String) -> void:
	_last_error = message
	push_error(message)
