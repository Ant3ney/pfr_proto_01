extends Node

## Owns the player's Pokemon collection and six-slot party.
##
## Each Pokemon collection instance (PCL) keeps the TDD's stable field names:
## {
##   "pokemonId": int,
##   "pclID": String,
##   "party": {"inParty": bool, "slot": int or null},
##   "instanceStats": {"health": float, "currentXp": int, "level": int},
##   "heldItem": String (optional),
##   "battleProfile": {
##     "species": String, "spriteId": String, "moves": Array[String]
##   }
## }
##
## `battleProfile` is present only when the PokeAPI Pokemon ID has an explicit
## mapping to the pinned battle engine. It is persisted so equipped moves are
## never recalculated when a battle starts.
##
## Health is normalized from 0.0 through 1.0. XP is a cumulative integer and
## level is derived from the Pokemon's growth curve. Returned dictionaries are
## deep copies so callers cannot bypass collection invariants.

signal collection_changed
signal party_changed
signal pokemon_evolved(pcl_id: String, previous_pokemon_id: int, pokemon_id: int)

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
			-1,
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
	current_xp := -1,
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
	if not _is_integer_value(current_xp):
		_set_error("currentXp must be a whole number")
		return {}
	var resolved_xp := int(current_xp)
	if resolved_xp < 0:
		resolved_xp = CreatureSystem.get_experience_for_level(pokemon_id, level)
	if not _validate_current_xp(pokemon_id, level, resolved_xp):
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
		resolved_xp,
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


## Restores every current party member to full health in one collection update.
## Stored Pokemon are intentionally untouched. Returns the number of party
## members whose health changed.
func heal_party() -> int:
	_last_error = ""
	var healed_stats_by_id: Dictionary = {}
	for pcl_id in _party_slots:
		if pcl_id.is_empty():
			continue
		var pcl: Dictionary = _collection_by_id[pcl_id]
		var stats: Dictionary = pcl["instanceStats"]
		if float(stats["health"]) >= 1.0:
			continue
		var healed_stats := stats.duplicate(true)
		healed_stats["health"] = 1.0
		healed_stats_by_id[pcl_id] = healed_stats

	for pcl_id: String in healed_stats_by_id:
		var pcl: Dictionary = _collection_by_id[pcl_id]
		pcl["instanceStats"] = healed_stats_by_id[pcl_id]

	if not healed_stats_by_id.is_empty():
		collection_changed.emit()
	return healed_stats_by_id.size()


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


## Returns the item slug held by one captured Pokemon, or an empty string when
## it is not holding an item. Held items stay local and never enter REST DTOs.
func get_held_item(pcl_id: String) -> String:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return ""
	return String((_collection_by_id[pcl_id] as Dictionary).get("heldItem", ""))


## Replaces one captured Pokemon's held item. Pass an empty string to take the
## current item. Bag ownership transfers are coordinated by StretchGoalSystem.
func set_held_item(pcl_id: String, item_key: String) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false
	var normalized_key := item_key.strip_edges()
	if not normalized_key.is_empty() and not _validate_item_key(normalized_key):
		return false
	var pcl := _collection_by_id[pcl_id] as Dictionary
	var current_key := String(pcl.get("heldItem", ""))
	if current_key == normalized_key:
		return true
	if normalized_key.is_empty():
		pcl.erase("heldItem")
	else:
		pcl["heldItem"] = normalized_key
	collection_changed.emit()
	return true


## Atomically applies a complete server `parties.player` health snapshot.
## Every current party member must appear exactly once and no other member may
## appear. Validation completes before any collection state is changed.
func apply_battle_health_snapshot(snapshot: Array) -> bool:
	return bool(apply_battle_health_and_experience(snapshot, []).get("ok", false))


## Atomically applies the complete player health snapshot and zero or more
## cumulative XP awards. All health and award records are validated before one
## collection_changed signal is emitted. Repeated award member IDs are summed.
func apply_battle_health_and_experience(snapshot: Array, awards: Array) -> Dictionary:
	_last_error = ""
	var party_ids: Array[String] = []
	for pcl_id in _party_slots:
		if not pcl_id.is_empty():
			party_ids.append(pcl_id)
	if party_ids.is_empty():
		_set_error("Cannot apply battle health to an empty party")
		return {"ok": false, "awards": []}
	if snapshot.size() != party_ids.size():
		_set_error("Battle health snapshot does not contain the complete player party")
		return {"ok": false, "awards": []}

	var health_by_id: Dictionary = {}
	for value: Variant in snapshot:
		if typeof(value) != TYPE_DICTIONARY:
			_set_error("Battle health snapshot contains a non-object member")
			return {"ok": false, "awards": []}
		var member: Dictionary = value
		var member_id_value: Variant = member.get("memberId")
		var health_value: Variant = member.get("normalizedHealth")
		if typeof(member_id_value) != TYPE_STRING:
			_set_error("Battle health snapshot has an invalid memberId")
			return {"ok": false, "awards": []}
		var member_id: String = member_id_value
		if member_id not in party_ids:
			_set_error("Battle health snapshot contains unknown memberId: %s" % member_id)
			return {"ok": false, "awards": []}
		if health_by_id.has(member_id):
			_set_error("Battle health snapshot repeats memberId: %s" % member_id)
			return {"ok": false, "awards": []}
		if not _is_numeric(health_value):
			_set_error("Battle health snapshot has non-numeric normalizedHealth")
			return {"ok": false, "awards": []}
		var health := float(health_value)
		if not _validate_percentage(health, "normalizedHealth"):
			return {"ok": false, "awards": []}
		health_by_id[member_id] = health

	for party_id in party_ids:
		if not health_by_id.has(party_id):
			_set_error("Battle health snapshot is missing memberId: %s" % party_id)
			return {"ok": false, "awards": []}

	var award_by_id: Dictionary = {}
	for value: Variant in awards:
		if typeof(value) != TYPE_DICTIONARY:
			_set_error("Battle experience awards contain a non-object entry")
			return {"ok": false, "awards": []}
		var award := value as Dictionary
		var member_id_value: Variant = award.get("memberId")
		var amount_value: Variant = award.get("amount")
		if typeof(member_id_value) != TYPE_STRING or not _is_integer_value(amount_value):
			_set_error("Battle experience award has invalid memberId or amount")
			return {"ok": false, "awards": []}
		var member_id := String(member_id_value)
		var amount := int(amount_value)
		if member_id not in party_ids:
			_set_error("Battle experience award contains unknown memberId: %s" % member_id)
			return {"ok": false, "awards": []}
		if amount < 0:
			_set_error("Battle experience award cannot be negative")
			return {"ok": false, "awards": []}
		award_by_id[member_id] = int(award_by_id.get(member_id, 0)) + amount

	var updated_stats_by_id: Dictionary = {}
	var applied_awards: Array[Dictionary] = []
	for party_id in party_ids:
		var pcl: Dictionary = _collection_by_id[party_id]
		var updated_stats: Dictionary = pcl["instanceStats"].duplicate(true)
		updated_stats["health"] = health_by_id[party_id]
		var requested_amount := int(award_by_id.get(party_id, 0))
		if requested_amount > 0:
			var pokemon_id := int(pcl["pokemonId"])
			var previous_xp := int(updated_stats["currentXp"])
			var previous_level := int(updated_stats["level"])
			var maximum_xp := CreatureSystem.get_experience_for_level(pokemon_id, MAX_LEVEL)
			var current_xp := mini(previous_xp + requested_amount, maximum_xp)
			var level := CreatureSystem.get_level_for_experience(pokemon_id, current_xp)
			if maximum_xp < 0 or level < MIN_LEVEL:
				_set_error("Could not resolve experience for PCL %s" % party_id)
				return {"ok": false, "awards": []}
			updated_stats["currentXp"] = current_xp
			updated_stats["level"] = level
			var progress := CreatureSystem.get_experience_progress(pokemon_id, current_xp)
			var evolution_options := CreatureSystem.get_available_evolutions(
				pokemon_id,
				level
			)
			if not CreatureSystem.get_last_error().is_empty():
				_set_error("Could not resolve evolution options for PCL %s" % party_id)
				return {"ok": false, "awards": []}
			applied_awards.append({
				"memberId": party_id,
				"pokemonId": pokemon_id,
				"amount": requested_amount,
				"appliedAmount": current_xp - previous_xp,
				"previousLevel": previous_level,
				"level": level,
				"currentXp": current_xp,
				"leveledUp": level > previous_level,
				"xpIntoLevel": int(progress.get("xpIntoLevel", 0)),
				"xpForNextLevel": int(progress.get("xpForNextLevel", 0)),
				"normalizedProgress": float(progress.get("normalizedProgress", 1.0)),
				"evolutionAvailable": not evolution_options.is_empty(),
				"evolutionOptions": evolution_options,
			})
		updated_stats_by_id[party_id] = updated_stats

	for party_id in party_ids:
		var pcl: Dictionary = _collection_by_id[party_id]
		pcl["instanceStats"] = updated_stats_by_id[party_id]
	collection_changed.emit()
	return {"ok": true, "awards": applied_awards}


## Grants cumulative XP to one collection instance outside battle. Level-ups
## are applied in the same atomic update and the result is presentation-ready.
func grant_experience(pcl_id: String, amount: int) -> Dictionary:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return {}
	if amount < 0:
		_set_error("Experience amount cannot be negative")
		return {}
	var pcl: Dictionary = _collection_by_id[pcl_id]
	var pokemon_id := int(pcl["pokemonId"])
	var stats: Dictionary = pcl["instanceStats"].duplicate(true)
	var previous_xp := int(stats["currentXp"])
	var previous_level := int(stats["level"])
	var maximum_xp := CreatureSystem.get_experience_for_level(pokemon_id, MAX_LEVEL)
	var current_xp := mini(previous_xp + amount, maximum_xp)
	var level := CreatureSystem.get_level_for_experience(pokemon_id, current_xp)
	if maximum_xp < 0 or level < MIN_LEVEL:
		_set_error("Could not resolve experience for PCL %s" % pcl_id)
		return {}
	stats["currentXp"] = current_xp
	stats["level"] = level
	var progress := CreatureSystem.get_experience_progress(pokemon_id, current_xp)
	var evolution_options := CreatureSystem.get_available_evolutions(pokemon_id, level)
	if not CreatureSystem.get_last_error().is_empty():
		_set_error("Could not resolve evolution options for PCL %s" % pcl_id)
		return {}
	pcl["instanceStats"] = stats
	collection_changed.emit()
	return {
		"memberId": pcl_id,
		"pokemonId": pokemon_id,
		"amount": amount,
		"appliedAmount": current_xp - previous_xp,
		"previousLevel": previous_level,
		"level": level,
		"currentXp": current_xp,
		"leveledUp": level > previous_level,
		"xpIntoLevel": int(progress.get("xpIntoLevel", 0)),
		"xpForNextLevel": int(progress.get("xpForNextLevel", 0)),
		"normalizedProgress": float(progress.get("normalizedProgress", 1.0)),
		"evolutionAvailable": not evolution_options.is_empty(),
		"evolutionOptions": evolution_options,
	}


func get_experience_progress(pcl_id: String) -> Dictionary:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return {}
	var pcl: Dictionary = _collection_by_id[pcl_id]
	return CreatureSystem.get_experience_progress(
		int(pcl["pokemonId"]),
		int((pcl["instanceStats"] as Dictionary)["currentXp"])
	)


## Returns the direct evolutions whose level requirements this captured
## Pokemon currently meets. Eligibility is derived, so Pokemon acquired above
## a threshold retain the same evolution action as Pokemon that just leveled.
func get_evolution_options(pcl_id: String) -> Array[Dictionary]:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return []
	var pcl: Dictionary = _collection_by_id[pcl_id]
	var stats := pcl.get("instanceStats", {}) as Dictionary
	var options := CreatureSystem.get_available_evolutions(
		int(pcl.get("pokemonId", 0)),
		int(stats.get("level", 0))
	)
	if not CreatureSystem.get_last_error().is_empty():
		_set_error(CreatureSystem.get_last_error())
		return []
	return options


func can_evolve(pcl_id: String) -> bool:
	return not get_evolution_options(pcl_id).is_empty()


## Evolves one captured instance into a currently eligible direct target.
## Identity, party position, health, level, and in-level XP progress survive;
## the target growth curve and battle species/sprite metadata are reconciled.
func evolve_pokemon(pcl_id: String, target_pokemon_id: int) -> Dictionary:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return {}
	var available_options := get_evolution_options(pcl_id)
	if not _last_error.is_empty():
		return {}
	if available_options.is_empty():
		_set_error("PCL %s does not currently meet an evolution level" % pcl_id)
		return {}
	var selected_option: Dictionary = {}
	for option in available_options:
		if int(option.get("pokemonId", 0)) == target_pokemon_id:
			selected_option = option
			break
	if selected_option.is_empty():
		_set_error(
			"Pokemon ID %d is not an available evolution for PCL %s"
			% [target_pokemon_id, pcl_id]
		)
		return {}

	var pcl: Dictionary = _collection_by_id[pcl_id]
	var previous_pokemon_id := int(pcl.get("pokemonId", 0))
	var stats := (pcl.get("instanceStats", {}) as Dictionary).duplicate(true)
	var level := int(stats.get("level", 0))
	var previous_xp := int(stats.get("currentXp", 0))
	var previous_progress := CreatureSystem.get_experience_progress(
		previous_pokemon_id,
		previous_xp
	)
	if previous_progress.is_empty():
		_set_error("Could not preserve experience progress while evolving PCL %s" % pcl_id)
		return {}
	var target_level_start := CreatureSystem.get_experience_for_level(
		target_pokemon_id,
		level
	)
	if target_level_start < 0:
		_set_error("Could not resolve the evolved Pokemon's experience curve")
		return {}
	var target_xp := target_level_start
	if level < MAX_LEVEL:
		var target_level_span := CreatureSystem.get_experience_to_next_level(
			target_pokemon_id,
			level
		)
		if target_level_span <= 0:
			_set_error("Could not resolve the evolved Pokemon's next level")
			return {}
		var normalized_progress := clampf(
			float(previous_progress.get("normalizedProgress", 0.0)),
			0.0,
			1.0
		)
		target_xp += mini(
			roundi(normalized_progress * float(target_level_span)),
			target_level_span - 1
		)
	if CreatureSystem.get_level_for_experience(target_pokemon_id, target_xp) != level:
		_set_error("The evolved Pokemon's experience no longer matches its level")
		return {}

	var target_profile := _create_default_battle_profile(target_pokemon_id)
	var previous_profile_value: Variant = pcl.get("battleProfile")
	if not target_profile.is_empty() and typeof(previous_profile_value) == TYPE_DICTIONARY:
		var previous_profile := previous_profile_value as Dictionary
		target_profile["moves"] = (previous_profile.get("moves", []) as Array).duplicate()

	pcl["pokemonId"] = target_pokemon_id
	stats["currentXp"] = target_xp
	pcl["instanceStats"] = stats
	if target_profile.is_empty():
		pcl.erase("battleProfile")
	else:
		pcl["battleProfile"] = target_profile

	collection_changed.emit()
	pokemon_evolved.emit(pcl_id, previous_pokemon_id, target_pokemon_id)
	return {
		"pclID": pcl_id,
		"previousPokemonId": previous_pokemon_id,
		"pokemonId": target_pokemon_id,
		"level": level,
		"currentXp": target_xp,
		"requiredLevel": int(selected_option.get("requiredLevel", level)),
	}


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


## Moves a captured Pokemon into a party slot in one atomic collection update.
## If the target is occupied, a stored Pokemon replaces that member and sends
## it to storage; a current party member swaps slots with the occupant.
func move_to_party_slot(pcl_id: String, party_slot: int) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false
	if not _validate_party_slot(party_slot):
		return false

	var pcl: Dictionary = _collection_by_id[pcl_id]
	var party: Dictionary = pcl["party"]
	var current_slot := int(party.get("slot", 0)) if bool(party["inParty"]) else 0
	if current_slot == party_slot:
		return true

	var displaced_id := _party_slots[party_slot - 1]
	if current_slot > 0:
		_party_slots[current_slot - 1] = ""

	if not displaced_id.is_empty() and displaced_id != pcl_id:
		var displaced: Dictionary = _collection_by_id[displaced_id]
		var displaced_party: Dictionary = displaced["party"]
		if current_slot > 0:
			displaced_party["inParty"] = true
			displaced_party["slot"] = current_slot
			_party_slots[current_slot - 1] = displaced_id
		else:
			displaced_party["inParty"] = false
			displaced_party["slot"] = null

	party["inParty"] = true
	party["slot"] = party_slot
	_party_slots[party_slot - 1] = pcl_id
	party_changed.emit()
	collection_changed.emit()
	return true


## Applies health and/or progression atomically. Setting only `level` moves XP
## to that level's exact threshold. Setting currentXp derives the level.
func update_instance_stats(pcl_id: String, changes: Dictionary) -> bool:
	_last_error = ""
	if not _collection_by_id.has(pcl_id):
		_set_error("Unknown PCL ID: %s" % pcl_id)
		return false
	for field: Variant in changes.keys():
		if field not in ["health", "currentXp", "level"]:
			_set_error("Unknown instanceStats field: %s" % str(field))
			return false

	var pcl: Dictionary = _collection_by_id[pcl_id]
	var current_stats: Dictionary = pcl["instanceStats"]
	var updated_stats := current_stats.duplicate(true)
	var requested_level := -1
	if changes.has("level"):
		if not _is_integer_value(changes["level"]):
			_set_error("level must be a whole number")
			return false
		requested_level = int(changes["level"])
		if not _validate_level(requested_level):
			return false
	if changes.has("health"):
		if not _is_numeric(changes["health"]):
			_set_error("health must be numeric")
			return false
		var health: float = float(changes["health"])
		if not _validate_percentage(health, "health"):
			return false
		updated_stats["health"] = health
	var pokemon_id := int(pcl["pokemonId"])
	if changes.has("currentXp"):
		if not _is_integer_value(changes["currentXp"]):
			_set_error("currentXp must be a whole number")
			return false
		var current_xp := int(changes["currentXp"])
		var maximum_xp := CreatureSystem.get_experience_for_level(pokemon_id, MAX_LEVEL)
		if current_xp < 0 or current_xp > maximum_xp:
			_set_error("currentXp must be within this Pokemon's growth curve")
			return false
		var derived_level := CreatureSystem.get_level_for_experience(pokemon_id, current_xp)
		if derived_level < MIN_LEVEL:
			_set_error("currentXp could not be resolved for this Pokemon")
			return false
		if requested_level >= MIN_LEVEL and requested_level != derived_level:
			_set_error("level does not match currentXp")
			return false
		updated_stats["currentXp"] = current_xp
		updated_stats["level"] = derived_level
	if requested_level >= MIN_LEVEL:
		if not changes.has("currentXp"):
			updated_stats["level"] = requested_level
			updated_stats["currentXp"] = CreatureSystem.get_experience_for_level(
				pokemon_id,
				requested_level
			)

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
		if not _is_integer_value(level_value):
			_set_error("PCL %s has an invalid level" % pcl_id)
			return false
		if not _is_numeric(health_value):
			_set_error("PCL %s has non-numeric health data" % pcl_id)
			return false
		var level := int(level_value)
		var health := float(health_value)
		if not _validate_level(level):
			return false
		if not _validate_percentage(health, "health"):
			return false

		var current_xp := -1
		if stats.has("currentXp"):
			var current_xp_value: Variant = stats["currentXp"]
			if not _is_integer_value(current_xp_value):
				_set_error("PCL %s has invalid currentXp data" % pcl_id)
				return false
			current_xp = int(current_xp_value)
			if not _validate_current_xp(pokemon_id, level, current_xp):
				return false
		elif stats.has("xp"):
			# One-time migration from the legacy normalized in-level XP field.
			var legacy_xp_value: Variant = stats["xp"]
			if not _is_numeric(legacy_xp_value):
				_set_error("PCL %s has non-numeric legacy xp data" % pcl_id)
				return false
			var legacy_progress := float(legacy_xp_value)
			if not _validate_percentage(legacy_progress, "xp"):
				return false
			var level_start := CreatureSystem.get_experience_for_level(pokemon_id, level)
			var level_span := CreatureSystem.get_experience_to_next_level(pokemon_id, level)
			current_xp = level_start
			if level < MAX_LEVEL:
				current_xp += int(round(legacy_progress * float(level_span)))
			level = CreatureSystem.get_level_for_experience(pokemon_id, current_xp)
		else:
			_set_error("PCL %s has no currentXp data" % pcl_id)
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

		var held_item := ""
		if source_pcl.has("heldItem"):
			var held_item_value: Variant = source_pcl["heldItem"]
			if typeof(held_item_value) != TYPE_STRING:
				_set_error("PCL %s has invalid heldItem data" % pcl_id)
				return false
			held_item = String(held_item_value).strip_edges()
			if not held_item.is_empty() and not _validate_item_key(held_item):
				return false

		var normalized_pcl := _create_pcl(
			pokemon_id,
			pcl_id,
			level,
			health,
			current_xp,
			party_slot,
			battle_profile,
			held_item
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
	current_xp: int,
	party_slot: int,
	battle_profile: Dictionary = {},
	held_item := ""
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
			"currentXp": current_xp,
			"level": level,
		},
	}
	if not held_item.is_empty():
		pcl["heldItem"] = held_item
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


func _validate_item_key(value: String) -> bool:
	if value.is_empty() or value.length() > 128 or value != value.to_lower():
		_set_error("Held item must use a lowercase catalog slug")
		return false
	for character_index in value.length():
		var codepoint := value.unicode_at(character_index)
		if not (
			(codepoint >= 48 and codepoint <= 57)
			or (codepoint >= 97 and codepoint <= 122)
			or codepoint == 45
		):
			_set_error("Held item contains an invalid character: %s" % value)
			return false
	return true


func _validate_level(level: int) -> bool:
	if level < MIN_LEVEL or level > MAX_LEVEL:
		_set_error("Pokemon level must be between %d and %d" % [MIN_LEVEL, MAX_LEVEL])
		return false
	return true


func _validate_current_xp(pokemon_id: int, level: int, current_xp: int) -> bool:
	if current_xp < 0:
		_set_error("currentXp cannot be negative")
		return false
	var maximum_xp := CreatureSystem.get_experience_for_level(pokemon_id, MAX_LEVEL)
	if maximum_xp < 0 or current_xp > maximum_xp:
		_set_error("currentXp exceeds this Pokemon's level-100 threshold")
		return false
	var derived_level := CreatureSystem.get_level_for_experience(pokemon_id, current_xp)
	if derived_level < MIN_LEVEL:
		_set_error("currentXp could not be resolved for Pokemon ID %d" % pokemon_id)
		return false
	if derived_level != level:
		_set_error("currentXp does not match Pokemon level %d" % level)
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
