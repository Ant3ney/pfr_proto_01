extends Node

## Owns the player's Pokemon collection and six-slot party.
##
## Each Pokemon collection instance (PCL) keeps the TDD's stable field names:
## {
##   "pokemonId": int,
##   "pclID": String,
##   "party": {"inParty": bool, "slot": int or null},
##   "instanceStats": {"health": float, "xp": float, "level": int}
## }
##
## Health and XP are normalized percentages from 0.0 through 1.0. Returned
## dictionaries are deep copies so callers cannot bypass collection invariants.

signal collection_changed
signal party_changed

const PARTY_SIZE := 6
const MIN_LEVEL := 1
const MAX_LEVEL := 100
const STARTING_LEVEL := 3
const STARTING_PARTY_POKEMON_IDS: Array[int] = [484, 414, 163, 416, 405, 279]

var _collection_by_id: Dictionary = {}
var _collection_order: Array[String] = []
var _party_slots: Array[String] = ["", "", "", "", "", ""]
var _crypto := Crypto.new()
var _fallback_id_counter := 0
var _last_error := ""


func _ready() -> void:
	for party_index in STARTING_PARTY_POKEMON_IDS.size():
		var pokemon_id := STARTING_PARTY_POKEMON_IDS[party_index]
		var pcl := add_pokemon(
			pokemon_id,
			STARTING_LEVEL,
			1.0,
			0.0,
			party_index + 1
		)
		if pcl.is_empty():
			push_error(
				"Could not add starting Pokemon ID %d: %s"
				% [pokemon_id, get_last_error()]
			)


## Creates a PCL and returns a safe copy. Pass party_slot 0 to leave it in
## storage, or a slot from 1 through 6 to add it directly to the party.
func add_pokemon(
	pokemon_id: int,
	level := 1,
	health := 1.0,
	xp := 0.0,
	party_slot := 0
) -> Dictionary:
	_last_error = ""
	if not CreatureSystem.has_pokemon(pokemon_id):
		_set_error("Unknown Pokemon ID: %d" % pokemon_id)
		return {}
	if not _validate_level(level):
		return {}
	if not _validate_percentage(health, "health"):
		return {}
	if not _validate_percentage(xp, "xp"):
		return {}
	if not _validate_optional_party_slot(party_slot):
		return {}
	if party_slot > 0 and not _party_slots[party_slot - 1].is_empty():
		_set_error("Party slot %d is already occupied" % party_slot)
		return {}

	var pcl_id := _generate_pcl_id()
	var pcl := _create_pcl(
		pokemon_id,
		pcl_id,
		level,
		health,
		xp,
		party_slot
	)
	_collection_by_id[pcl_id] = pcl
	_collection_order.append(pcl_id)
	if party_slot > 0:
		_party_slots[party_slot - 1] = pcl_id
		party_changed.emit()
	collection_changed.emit()
	return pcl.duplicate(true)


## Returns a PCL by its unique instance ID, or an empty dictionary when absent.
func get_pcl(pcl_id: String) -> Dictionary:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_last_error = "Unknown PCL ID: %s" % pcl_id
		return {}
	var pcl: Dictionary = _collection_by_id[pcl_id]
	return pcl.duplicate(true)


## Implements the TDD's battle lookup path: party slot -> PCL object.
func get_pcl_by_party_slot(party_slot: int) -> Dictionary:
	_last_error = ""
	if not _validate_party_slot(party_slot):
		return {}
	var pcl_id := _party_slots[party_slot - 1]
	if pcl_id.is_empty():
		return {}
	var pcl: Dictionary = _collection_by_id[pcl_id]
	return pcl.duplicate(true)


## Returns every PCL in capture/import order.
func get_collection() -> Array[Dictionary]:
	var collection: Array[Dictionary] = []
	for pcl_id in _collection_order:
		var pcl: Dictionary = _collection_by_id[pcl_id]
		collection.append(pcl.duplicate(true))
	return collection


## Returns party PCLs in slot order, omitting empty slots.
func get_party() -> Array[Dictionary]:
	var party: Array[Dictionary] = []
	for pcl_id in _party_slots:
		if pcl_id.is_empty():
			continue
		var pcl: Dictionary = _collection_by_id[pcl_id]
		party.append(pcl.duplicate(true))
	return party


func get_collection_size() -> int:
	return _collection_order.size()


func get_party_size() -> int:
	var party_count := 0
	for pcl_id in _party_slots:
		if not pcl_id.is_empty():
			party_count += 1
	return party_count


func has_pcl(pcl_id: String) -> bool:
	return _collection_by_id.has(pcl_id)


## Assigns an existing PCL to a free party slot. Pass 0 to remove it from the
## party. Occupied target slots are rejected rather than silently replacing a
## different Pokemon.
func set_party_slot(pcl_id: String, party_slot: int) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false
	if not _validate_optional_party_slot(party_slot):
		return false
	if (
		party_slot > 0
		and not _party_slots[party_slot - 1].is_empty()
		and _party_slots[party_slot - 1] != pcl_id
	):
		_set_error("Party slot %d is already occupied" % party_slot)
		return false

	var pcl: Dictionary = _collection_by_id[pcl_id]
	var party: Dictionary = pcl["party"]
	var current_slot := int(party.get("slot", 0)) if party["inParty"] else 0
	if current_slot == party_slot:
		return true
	if current_slot > 0:
		_party_slots[current_slot - 1] = ""

	party["inParty"] = party_slot > 0
	party["slot"] = party_slot if party_slot > 0 else null
	if party_slot > 0:
		_party_slots[party_slot - 1] = pcl_id
	party_changed.emit()
	collection_changed.emit()
	return true


func remove_from_party(pcl_id: String) -> bool:
	return set_party_slot(pcl_id, 0)


## Applies any subset of `health`, `xp`, and `level` atomically.
func update_instance_stats(pcl_id: String, changes: Dictionary) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false
	for field: Variant in changes.keys():
		if field not in ["health", "xp", "level"]:
			_set_error("Unknown instanceStats field: %s" % str(field))
			return false

	var pcl: Dictionary = _collection_by_id[pcl_id]
	var current_stats: Dictionary = pcl["instanceStats"]
	var updated_stats := current_stats.duplicate(true)
	if changes.has("health"):
		if not _is_numeric(changes["health"]):
			_set_error("health must be numeric")
			return false
		var health: float = float(changes["health"])
		if not _validate_percentage(health, "health"):
			return false
		updated_stats["health"] = health
	if changes.has("xp"):
		if not _is_numeric(changes["xp"]):
			_set_error("xp must be numeric")
			return false
		var xp: float = float(changes["xp"])
		if not _validate_percentage(xp, "xp"):
			return false
		updated_stats["xp"] = xp
	if changes.has("level"):
		if not _is_integer_value(changes["level"]):
			_set_error("level must be a whole number")
			return false
		var level: int = int(changes["level"])
		if not _validate_level(level):
			return false
		updated_stats["level"] = level

	pcl["instanceStats"] = updated_stats
	collection_changed.emit()
	return true


func remove_pcl(pcl_id: String) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false

	var pcl: Dictionary = _collection_by_id[pcl_id]
	var party: Dictionary = pcl["party"]
	var was_in_party := bool(party["inParty"])
	if was_in_party:
		var party_slot := int(party["slot"])
		_party_slots[party_slot - 1] = ""
	_collection_by_id.erase(pcl_id)
	_collection_order.erase(pcl_id)
	if was_in_party:
		party_changed.emit()
	collection_changed.emit()
	return true


## Returns save-ready collection data. This is intentionally the same shape as
## `get_collection()` so the future Save System can store it directly.
func get_save_data() -> Array[Dictionary]:
	return get_collection()


## Replaces the collection atomically from save data. Invalid records leave the
## current collection untouched.
func load_save_data(collection_data: Array) -> bool:
	_last_error = ""
	var loaded_by_id: Dictionary = {}
	var loaded_order: Array[String] = []
	var loaded_party: Array[String] = ["", "", "", "", "", ""]

	for value: Variant in collection_data:
		if typeof(value) != TYPE_DICTIONARY:
			_set_error("Collection save data contains a non-object PCL")
			return false
		var source_pcl: Dictionary = value
		var pokemon_id_value: Variant = source_pcl.get("pokemonId")
		var pcl_id_value: Variant = source_pcl.get("pclID")
		if not _is_integer_value(pokemon_id_value):
			_set_error("Collection save data has an invalid Pokemon ID")
			return false
		if typeof(pcl_id_value) != TYPE_STRING:
			_set_error("Collection save data has an invalid PCL ID")
			return false
		var pokemon_id := int(pokemon_id_value)
		var pcl_id: String = pcl_id_value
		if not CreatureSystem.has_pokemon(pokemon_id):
			_set_error("Collection save data has unknown Pokemon ID: %d" % pokemon_id)
			return false
		if pcl_id.strip_edges().is_empty() or loaded_by_id.has(pcl_id):
			_set_error("Collection save data has an empty or duplicate PCL ID")
			return false

		var party_value: Variant = source_pcl.get("party")
		var stats_value: Variant = source_pcl.get("instanceStats")
		if typeof(party_value) != TYPE_DICTIONARY:
			_set_error("PCL %s has invalid party data" % pcl_id)
			return false
		if typeof(stats_value) != TYPE_DICTIONARY:
			_set_error("PCL %s has invalid instanceStats data" % pcl_id)
			return false

		var party: Dictionary = party_value
		var stats: Dictionary = stats_value
		var in_party_value: Variant = party.get("inParty")
		if typeof(in_party_value) != TYPE_BOOL:
			_set_error("PCL %s has invalid inParty data" % pcl_id)
			return false
		var in_party: bool = in_party_value
		var party_slot := 0
		if in_party:
			var party_slot_value: Variant = party.get("slot")
			if not _is_integer_value(party_slot_value):
				_set_error("PCL %s has an invalid party slot" % pcl_id)
				return false
			party_slot = int(party_slot_value)
			if not _validate_party_slot(party_slot):
				return false
		if party_slot > 0 and not loaded_party[party_slot - 1].is_empty():
			_set_error("Collection save data repeats party slot %d" % party_slot)
			return false

		var level_value: Variant = stats.get("level")
		var health_value: Variant = stats.get("health")
		var xp_value: Variant = stats.get("xp")
		if not _is_integer_value(level_value):
			_set_error("PCL %s has an invalid level" % pcl_id)
			return false
		if not _is_numeric(health_value) or not _is_numeric(xp_value):
			_set_error("PCL %s has non-numeric health or xp data" % pcl_id)
			return false
		var level := int(level_value)
		var health := float(health_value)
		var xp := float(xp_value)
		if not _validate_level(level):
			return false
		if not _validate_percentage(health, "health"):
			return false
		if not _validate_percentage(xp, "xp"):
			return false

		var normalized_pcl := _create_pcl(
			pokemon_id,
			pcl_id,
			level,
			health,
			xp,
			party_slot
		)
		loaded_by_id[pcl_id] = normalized_pcl
		loaded_order.append(pcl_id)
		if party_slot > 0:
			loaded_party[party_slot - 1] = pcl_id

	_collection_by_id = loaded_by_id
	_collection_order = loaded_order
	_party_slots = loaded_party
	party_changed.emit()
	collection_changed.emit()
	return true


func clear_collection() -> void:
	var had_collection := not _collection_order.is_empty()
	var had_party := get_party_size() > 0
	_collection_by_id.clear()
	_collection_order.clear()
	_party_slots = ["", "", "", "", "", ""]
	_last_error = ""
	if had_party:
		party_changed.emit()
	if had_collection:
		collection_changed.emit()


func get_last_error() -> String:
	return _last_error


func _create_pcl(
	pokemon_id: int,
	pcl_id: String,
	level: int,
	health: float,
	xp: float,
	party_slot: int
) -> Dictionary:
	return {
		"pokemonId": pokemon_id,
		"pclID": pcl_id,
		"party": {
			"inParty": party_slot > 0,
			"slot": party_slot if party_slot > 0 else null,
		},
		"instanceStats": {
			"health": health,
			"xp": xp,
			"level": level,
		},
	}


func _generate_pcl_id() -> String:
	for attempt in range(8):
		var random_bytes: PackedByteArray = _crypto.generate_random_bytes(16)
		var candidate := random_bytes.hex_encode()
		if not candidate.is_empty() and not _collection_by_id.has(candidate):
			return candidate

	_fallback_id_counter += 1
	var fallback_id := "%d-%d" % [Time.get_ticks_usec(), _fallback_id_counter]
	while _collection_by_id.has(fallback_id):
		_fallback_id_counter += 1
		fallback_id = "%d-%d" % [Time.get_ticks_usec(), _fallback_id_counter]
	return fallback_id


func _is_numeric(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT or not is_finite(float(value)):
		return false
	return is_equal_approx(float(value), float(int(value)))


func _validate_level(level: int) -> bool:
	if level < MIN_LEVEL or level > MAX_LEVEL:
		_set_error("Pokemon level must be between %d and %d" % [MIN_LEVEL, MAX_LEVEL])
		return false
	return true


func _validate_percentage(value: float, field_name: String) -> bool:
	if not is_finite(value) or value < 0.0 or value > 1.0:
		_set_error("%s must be between 0.0 and 1.0" % field_name)
		return false
	return true


func _validate_optional_party_slot(party_slot: int) -> bool:
	if party_slot == 0:
		return true
	return _validate_party_slot(party_slot)


func _validate_party_slot(party_slot: int) -> bool:
	if party_slot < 1 or party_slot > PARTY_SIZE:
		_set_error("Party slot must be between 1 and %d" % PARTY_SIZE)
		return false
	return true


func _set_error(message: String) -> void:
	_last_error = message
