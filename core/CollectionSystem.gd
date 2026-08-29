extends Node

## Owns the player's Pokemon collection and six-slot party.
##
## Each Pokemon collection instance (PCL) keeps the TDD's stable field names:
## {
##   "pokemonId": int,
##   "pclID": String,
##   "party": {"inParty": bool, "slot": int or null},
##   "instanceStats": {"health": float, "xp": float, "level": int},
##   "battleProfile": {
##     "species": String, "spriteId": String, "moves": Array[String]
##   }
## }
##
## `battleProfile` is present only when the PokeAPI Pokemon ID has an explicit
## mapping to the pinned battle engine. It is persisted so equipped moves are
## never recalculated when a battle starts.
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
const SpeciesMapping := preload("res://battle/system/BattleSpeciesMapping.gd")

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
	var battle_profile := _create_default_battle_profile(pokemon_id)
	var pcl := _create_pcl(
		pokemon_id,
		pcl_id,
		level,
		health,
		xp,
		party_slot,
		battle_profile
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


## Returns the current party in the exact strict member shape accepted by the
## battle REST API. Fainted members remain in the result. An empty result means
## local preflight failed; inspect `get_last_error()` for the reason.
func get_battle_party_members() -> Array[Dictionary]:
	_last_error = ""
	var members: Array[Dictionary] = []
	var has_living_member := false
	for pcl_id in _party_slots:
		if pcl_id.is_empty():
			continue
		var pcl: Dictionary = _collection_by_id[pcl_id]
		var battle_profile_value: Variant = pcl.get("battleProfile")
		if typeof(battle_profile_value) != TYPE_DICTIONARY:
			_set_error(
				"Pokemon ID %d is not supported for battle" % int(pcl["pokemonId"])
			)
			return []
		var battle_profile: Dictionary = battle_profile_value
		if not _validate_battle_profile(
			int(pcl["pokemonId"]),
			battle_profile,
			"PCL %s" % pcl_id
		):
			return []
		var stats: Dictionary = pcl["instanceStats"]
		var health := float(stats["health"])
		has_living_member = has_living_member or health > 0.0
		members.append({
			"memberId": pcl_id,
			"species": str(battle_profile["species"]),
			"level": int(stats["level"]),
			"health": health,
			"moves": battle_profile["moves"].duplicate(),
		})

	if members.is_empty():
		_set_error("Player party is empty")
		return []
	if not has_living_member:
		_set_error("Player party has no living members")
		return []
	return members


## Returns the persisted presentation/battle identifiers for one PCL.
func get_battle_profile(pcl_id: String) -> Dictionary:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_last_error = "Unknown PCL ID: %s" % pcl_id
		return {}
	var pcl: Dictionary = _collection_by_id[pcl_id]
	var profile_value: Variant = pcl.get("battleProfile")
	if typeof(profile_value) != TYPE_DICTIONARY:
		_last_error = "PCL %s is not supported for battle" % pcl_id
		return {}
	var profile: Dictionary = profile_value
	return profile.duplicate(true)


## Replaces the one-to-four persisted Showdown move IDs used by later battles.
func set_equipped_moves(pcl_id: String, moves: Array) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false
	var pcl: Dictionary = _collection_by_id[pcl_id]
	var battle_profile_value: Variant = pcl.get("battleProfile")
	if typeof(battle_profile_value) != TYPE_DICTIONARY:
		_set_error("PCL %s is not supported for battle" % pcl_id)
		return false
	var validated_moves := _validated_move_ids(moves, "Equipped moves")
	if validated_moves.is_empty():
		return false
	var battle_profile: Dictionary = battle_profile_value
	battle_profile["moves"] = validated_moves
	collection_changed.emit()
	return true


## Atomically applies a complete server `parties.player` health snapshot.
## Every current party member must appear exactly once and no other member may
## appear. Validation completes before any collection state is changed.
func apply_battle_health_snapshot(snapshot: Array) -> bool:
	_last_error = ""
	var party_ids: Array[String] = []
	for pcl_id in _party_slots:
		if not pcl_id.is_empty():
			party_ids.append(pcl_id)
	if party_ids.is_empty():
		_set_error("Cannot apply battle health to an empty party")
		return false
	if snapshot.size() != party_ids.size():
		_set_error("Battle health snapshot does not contain the complete player party")
		return false

	var health_by_id: Dictionary = {}
	for value: Variant in snapshot:
		if typeof(value) != TYPE_DICTIONARY:
			_set_error("Battle health snapshot contains a non-object member")
			return false
		var member: Dictionary = value
		var member_id_value: Variant = member.get("memberId")
		var health_value: Variant = member.get("normalizedHealth")
		if typeof(member_id_value) != TYPE_STRING:
			_set_error("Battle health snapshot has an invalid memberId")
			return false
		var member_id: String = member_id_value
		if member_id not in party_ids:
			_set_error("Battle health snapshot contains unknown memberId: %s" % member_id)
			return false
		if health_by_id.has(member_id):
			_set_error("Battle health snapshot repeats memberId: %s" % member_id)
			return false
		if not _is_numeric(health_value):
			_set_error("Battle health snapshot has non-numeric normalizedHealth")
			return false
		var health := float(health_value)
		if not _validate_percentage(health, "normalizedHealth"):
			return false
		health_by_id[member_id] = health

	for party_id in party_ids:
		if not health_by_id.has(party_id):
			_set_error("Battle health snapshot is missing memberId: %s" % party_id)
			return false

	for party_id in party_ids:
		var pcl: Dictionary = _collection_by_id[party_id]
		var updated_stats: Dictionary = pcl["instanceStats"].duplicate(true)
		updated_stats["health"] = health_by_id[party_id]
		pcl["instanceStats"] = updated_stats
	collection_changed.emit()
	return true


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

		var battle_profile: Dictionary = {}
		var mapped_profile := _create_default_battle_profile(pokemon_id)
		if source_pcl.has("battleProfile"):
			var battle_profile_value: Variant = source_pcl["battleProfile"]
			if typeof(battle_profile_value) != TYPE_DICTIONARY:
				_set_error("PCL %s has invalid battleProfile data" % pcl_id)
				return false
			if mapped_profile.is_empty():
				_set_error(
					"PCL %s has a battleProfile for an unsupported Pokemon ID" % pcl_id
				)
				return false
			battle_profile = battle_profile_value.duplicate(true)
			if not _validate_battle_profile(
				pokemon_id,
				battle_profile,
				"PCL %s" % pcl_id
			):
				return false
			battle_profile = {
				"species": str(battle_profile["species"]),
				"spriteId": str(battle_profile["spriteId"]),
				"moves": battle_profile["moves"].duplicate(),
			}
		elif not mapped_profile.is_empty():
			# One-time migration for saves created before battle profiles existed.
			battle_profile = mapped_profile

		var normalized_pcl := _create_pcl(
			pokemon_id,
			pcl_id,
			level,
			health,
			xp,
			party_slot,
			battle_profile
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
	party_slot: int,
	battle_profile: Dictionary = {}
) -> Dictionary:
	var pcl := {
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
	if not battle_profile.is_empty():
		pcl["battleProfile"] = battle_profile.duplicate(true)
	return pcl


func _create_default_battle_profile(pokemon_id: int) -> Dictionary:
	var mapping: Dictionary = SpeciesMapping.get_entry(pokemon_id)
	if mapping.is_empty():
		return {}
	return {
		"species": str(mapping["species"]),
		"spriteId": str(mapping["spriteId"]),
		"moves": mapping["defaultMoves"].duplicate(),
	}


func _validate_battle_profile(
	pokemon_id: int,
	profile: Dictionary,
	context: String
) -> bool:
	var mapping: Dictionary = SpeciesMapping.get_entry(pokemon_id)
	if mapping.is_empty():
		_set_error("%s uses an unsupported Pokemon ID" % context)
		return false
	if typeof(profile.get("species")) != TYPE_STRING:
		_set_error("%s has an invalid battle species" % context)
		return false
	if str(profile["species"]) != str(mapping["species"]):
		_set_error("%s battle species does not match its Pokemon ID" % context)
		return false
	if typeof(profile.get("spriteId")) != TYPE_STRING:
		_set_error("%s has an invalid battle spriteId" % context)
		return false
	if str(profile["spriteId"]) != str(mapping["spriteId"]):
		_set_error("%s battle spriteId does not match its Pokemon ID" % context)
		return false
	var moves_value: Variant = profile.get("moves")
	if typeof(moves_value) != TYPE_ARRAY:
		_set_error("%s has invalid equipped moves" % context)
		return false
	var moves: Array = moves_value
	return not _validated_move_ids(moves, "%s equipped moves" % context).is_empty()


func _validated_move_ids(moves: Array, context: String) -> Array[String]:
	if moves.is_empty() or moves.size() > 4:
		_set_error("%s must contain between 1 and 4 move IDs" % context)
		return []
	var validated: Array[String] = []
	for move_value: Variant in moves:
		if typeof(move_value) != TYPE_STRING:
			_set_error("%s contains a non-string move ID" % context)
			return []
		var move_id: String = move_value
		if not _is_showdown_id(move_id):
			_set_error("%s contains an invalid Showdown move ID: %s" % [context, move_id])
			return []
		if not SpeciesMapping.has_move_id(move_id):
			_set_error("%s contains an unknown Showdown move ID: %s" % [context, move_id])
			return []
		if move_id in validated:
			_set_error("%s contains duplicate move ID: %s" % [context, move_id])
			return []
		validated.append(move_id)
	return validated


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
