class_name CreatureExperience
extends RefCounted

## Validated, read-only access to the generated two-dimensional experience
## tables and compact per-Pokemon progression rows.

const DATA_PATH := "res://data/creatures/experience.json"
const SCHEMA_VERSION := 1
const SHOWDOWN_VERSION := "0.11.11"
const MIN_LEVEL := 1
const MAX_LEVEL := 100

static var _load_attempted := false
static var _growth_rate_names: Array[String] = []
static var _curves: Array[PackedInt32Array] = []
static var _community_tiers: Array[String] = []
static var _rows_by_pokemon_id: Dictionary = {}
static var _source_pokemon_count := 0
static var _last_error := ""


static func get_profile(pokemon_id: int) -> Dictionary:
	if not _ensure_loaded() or not _rows_by_pokemon_id.has(pokemon_id):
		_last_error = "Pokemon ID %d has no experience profile" % pokemon_id
		return {}
	_last_error = ""
	var row: PackedInt32Array = _rows_by_pokemon_id[pokemon_id]
	return {
		"growthRate": _growth_rate_names[row[0]],
		"growthRateIndex": row[0],
		"xpMultiplier": float(row[1]) / 10000.0,
		"xpMultiplierBasisPoints": row[1],
		"communityTier": _community_tiers[row[2]],
	}


static func get_experience_curve(pokemon_id: int) -> PackedInt32Array:
	var row := _pokemon_row(pokemon_id)
	if row.is_empty():
		return PackedInt32Array()
	return _curves[row[0]].duplicate()


static func get_experience_for_level(pokemon_id: int, level: int) -> int:
	var row := _pokemon_row(pokemon_id)
	if row.is_empty() or level < MIN_LEVEL or level > MAX_LEVEL:
		if level < MIN_LEVEL or level > MAX_LEVEL:
			_last_error = "Pokemon level must be between %d and %d" % [MIN_LEVEL, MAX_LEVEL]
		return -1
	_last_error = ""
	return _curves[row[0]][level]


static func get_experience_to_next_level(pokemon_id: int, level: int) -> int:
	if level == MAX_LEVEL:
		return 0 if not _pokemon_row(pokemon_id).is_empty() else -1
	var current := get_experience_for_level(pokemon_id, level)
	var following := get_experience_for_level(pokemon_id, level + 1)
	return following - current if current >= 0 and following >= 0 else -1


static func get_level_for_experience(pokemon_id: int, current_xp: int) -> int:
	var row := _pokemon_row(pokemon_id)
	if row.is_empty():
		return -1
	if current_xp < 0:
		_last_error = "Current XP cannot be negative"
		return -1
	var curve: PackedInt32Array = _curves[row[0]]
	var low := MIN_LEVEL
	var high := MAX_LEVEL
	while low < high:
		var middle := (low + high + 1) / 2
		if curve[middle] <= current_xp:
			low = middle
		else:
			high = middle - 1
	_last_error = ""
	return low


static func get_progress(pokemon_id: int, current_xp: int) -> Dictionary:
	var level := get_level_for_experience(pokemon_id, current_xp)
	if level < MIN_LEVEL:
		return {}
	var level_start := get_experience_for_level(pokemon_id, level)
	if level >= MAX_LEVEL:
		return {
			"level": MAX_LEVEL,
			"currentXp": current_xp,
			"levelStartXp": level_start,
			"nextLevelXp": level_start,
			"xpIntoLevel": 0,
			"xpForNextLevel": 0,
			"normalizedProgress": 1.0,
		}
	var next_level := get_experience_for_level(pokemon_id, level + 1)
	var required := next_level - level_start
	var into_level := clampi(current_xp - level_start, 0, required)
	return {
		"level": level,
		"currentXp": current_xp,
		"levelStartXp": level_start,
		"nextLevelXp": next_level,
		"xpIntoLevel": into_level,
		"xpForNextLevel": required,
		"normalizedProgress": float(into_level) / float(required),
	}


static func get_growth_table() -> Array[PackedInt32Array]:
	if not _ensure_loaded():
		return []
	var copy: Array[PackedInt32Array] = []
	for curve in _curves:
		copy.append(curve.duplicate())
	return copy


static func get_growth_rate_names() -> Array[String]:
	return _growth_rate_names.duplicate() if _ensure_loaded() else []


static func get_source_pokemon_count() -> int:
	return _source_pokemon_count if _ensure_loaded() else 0


static func get_last_error() -> String:
	return _last_error


static func reload_data() -> bool:
	_load_attempted = false
	_growth_rate_names.clear()
	_curves.clear()
	_community_tiers.clear()
	_rows_by_pokemon_id.clear()
	_source_pokemon_count = 0
	_last_error = ""
	return _ensure_loaded()


static func _pokemon_row(pokemon_id: int) -> PackedInt32Array:
	if not _ensure_loaded() or not _rows_by_pokemon_id.has(pokemon_id):
		_last_error = "Pokemon ID %d has no experience profile" % pokemon_id
		return PackedInt32Array()
	_last_error = ""
	return _rows_by_pokemon_id[pokemon_id]


static func _ensure_loaded() -> bool:
	if _load_attempted:
		return not _rows_by_pokemon_id.is_empty()
	_load_attempted = true
	if not FileAccess.file_exists(DATA_PATH):
		_last_error = "Creature experience data is missing: %s" % DATA_PATH
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_last_error = "Creature experience data is not a JSON object"
		return false
	var document := parsed as Dictionary
	if int(document.get("schemaVersion", -1)) != SCHEMA_VERSION:
		_last_error = "Creature experience schema version is incompatible"
		return false
	if String(document.get("pokemonShowdownVersion", "")) != SHOWDOWN_VERSION:
		_last_error = "Creature experience Pokemon Showdown version is incompatible"
		return false
	for hash_key in ["pokeapiIndexSha256", "pokeapiDatasetSha256", "battleMappingSha256"]:
		var hash_value := String(document.get(hash_key, ""))
		if hash_value.length() != 64 or not hash_value.is_valid_hex_number(false):
			_last_error = "Creature experience provenance is invalid"
			return false

	var names_value: Variant = document.get("growthRateNames")
	var curves_value: Variant = document.get("experienceByGrowthRate")
	var tiers_value: Variant = document.get("communityTiers")
	var rows_value: Variant = document.get("pokemonRows")
	if (
		typeof(names_value) != TYPE_ARRAY
		or typeof(curves_value) != TYPE_ARRAY
		or typeof(tiers_value) != TYPE_ARRAY
		or typeof(rows_value) != TYPE_ARRAY
	):
		_last_error = "Creature experience data has invalid tables"
		return false

	var names: Array[String] = []
	for name_value: Variant in names_value:
		if typeof(name_value) != TYPE_STRING or String(name_value).is_empty():
			_last_error = "Creature experience data has an invalid growth-rate name"
			return false
		names.append(String(name_value))
	if names.is_empty() or curves_value.size() != names.size():
		_last_error = "Creature experience curve count is inconsistent"
		return false

	var curves: Array[PackedInt32Array] = []
	for curve_value: Variant in curves_value:
		if typeof(curve_value) != TYPE_ARRAY or (curve_value as Array).size() != MAX_LEVEL + 1:
			_last_error = "Creature experience curve has an invalid length"
			return false
		var curve := PackedInt32Array()
		for level in range(MAX_LEVEL + 1):
			var xp_value: Variant = (curve_value as Array)[level]
			if not _is_integer_value(xp_value) or int(xp_value) < 0:
				_last_error = "Creature experience curve contains invalid XP"
				return false
			if level >= 2 and int(xp_value) <= curve[level - 1]:
				_last_error = "Creature experience curve is not increasing"
				return false
			curve.append(int(xp_value))
		curves.append(curve)

	var tiers: Array[String] = []
	for tier_value: Variant in tiers_value:
		if typeof(tier_value) != TYPE_STRING or String(tier_value).is_empty():
			_last_error = "Creature experience data has an invalid community tier"
			return false
		tiers.append(String(tier_value))

	var rows: Dictionary = {}
	for row_value: Variant in rows_value:
		if typeof(row_value) != TYPE_ARRAY or (row_value as Array).size() != 4:
			_last_error = "Creature experience data has an invalid Pokemon row"
			return false
		var source_row := row_value as Array
		for cell: Variant in source_row:
			if not _is_integer_value(cell):
				_last_error = "Creature experience Pokemon row is not integral"
				return false
		var pokemon_id := int(source_row[0])
		var growth_index := int(source_row[1])
		var multiplier_basis_points := int(source_row[2])
		var tier_index := int(source_row[3])
		if (
			pokemon_id <= 0
			or rows.has(pokemon_id)
			or growth_index < 0
			or growth_index >= curves.size()
			or multiplier_basis_points < 1000
			or multiplier_basis_points > 30000
			or tier_index < 0
			or tier_index >= tiers.size()
		):
			_last_error = "Creature experience data has an out-of-range Pokemon row"
			return false
		rows[pokemon_id] = PackedInt32Array([
			growth_index,
			multiplier_basis_points,
			tier_index,
		])

	var source_count := int(document.get("sourcePokemonCount", -1))
	if source_count != rows.size():
		_last_error = "Creature experience Pokemon count is inconsistent"
		return false
	_growth_rate_names = names
	_curves = curves
	_community_tiers = tiers
	_rows_by_pokemon_id = rows
	_source_pokemon_count = source_count
	_last_error = ""
	return true


static func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), float(int(value)))
