class_name RNDStretchGoalSystem
extends Node

## Experimental economy, shop ownership, destination selection, and battle
## rewards for Stretchman's deliberately oversized R&D feature hub.

signal progression_changed
signal balance_changed(balance: int)
signal inventory_changed
signal purchase_completed(summary: Dictionary)
signal purchase_failed(message: String)
signal destination_started(destination: Dictionary)
signal battle_reward_granted(summary: Dictionary)
signal loot_box_opened(summary: Dictionary)

const Content := preload("res://rnd/stretch/StretchContent.gd")
const ITEM_CATALOG_PATH := "res://rnd/stretch/data/items.json"
const POKEMON_CATALOG_PATH := "res://rnd/stretch/data/pokemon.json"
const CURRENT_ECONOMY_VERSION := 2
const LEGACY_STARTING_BALANCE := 5_000_000
const STARTING_BALANCE := 500
const PURCHASED_POKEMON_LEVEL := 50
const LOOT_BOX_HIGH_QUALITY_CHANCE := 0.10
const MAX_BALANCE := 9_000_000_000_000_000
const MAX_ITEM_QUANTITY := 999_999

var _balance := STARTING_BALANCE
var _item_inventory: Dictionary = {}
var _earned_badges: Array[int] = []
var _champion_cleared := false
var _active_destination: Dictionary = {}
var _run_defeated_ids: Dictionary = {}
var _run_id := 0
var _last_battle_reward: Dictionary = {}

var _item_catalog: Array[Dictionary] = []
var _pokemon_catalog: Array[Dictionary] = []
var _items_by_slug: Dictionary = {}
var _pokemon_by_id: Dictionary = {}
var _last_error := ""
var _loot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_catalogs()
	_loot_rng.randomize()
	if not BattleSystem.battle_ended.is_connected(_on_battle_ended):
		BattleSystem.battle_ended.connect(_on_battle_ended)


func get_balance() -> int:
	return _balance


func get_item_catalog() -> Array[Dictionary]:
	return _item_catalog.duplicate(true)


func get_pokemon_catalog() -> Array[Dictionary]:
	return _pokemon_catalog.duplicate(true)


func get_pokemon_offer(pokemon_id: int) -> Dictionary:
	if not _pokemon_by_id.has(pokemon_id):
		return {}
	return (_pokemon_by_id[pokemon_id] as Dictionary).duplicate(true)


func get_loot_box_catalog() -> Array[Dictionary]:
	return Content.get_loot_boxes()


func get_item_count(item_key: String) -> int:
	return int(_item_inventory.get(item_key, 0))


func get_item_inventory() -> Dictionary:
	return _item_inventory.duplicate(true)


func get_earned_badges() -> Array[int]:
	return _earned_badges.duplicate()


func has_badge(gym_index: int) -> bool:
	return gym_index in _earned_badges


func is_champion_cleared() -> bool:
	return _champion_cleared


func get_last_battle_reward() -> Dictionary:
	return _last_battle_reward.duplicate(true)


func get_last_error() -> String:
	return _last_error


func buy_item(item_key: String) -> Dictionary:
	_last_error = ""
	var normalized_key := item_key.strip_edges()
	if not _items_by_slug.has(normalized_key):
		return _purchase_failure("Unknown shop item: %s" % normalized_key)
	var item := _items_by_slug[normalized_key] as Dictionary
	var price := int(item.get("price", 0))
	if not _can_afford(price):
		return _purchase_failure(
			"Stretchman wants %s, but you only have %s."
			% [format_money(price), format_money(_balance)]
		)
	var current_quantity := int(_item_inventory.get(normalized_key, 0))
	if current_quantity >= MAX_ITEM_QUANTITY:
		return _purchase_failure("The R&D inventory cap has been reached for this item.")

	_balance -= price
	_item_inventory[normalized_key] = current_quantity + 1
	var summary := {
		"kind": "item",
		"id": normalized_key,
		"name": String(item.get("name", normalized_key)),
		"price": price,
		"quantity": current_quantity + 1,
	}
	_emit_progression_change(true)
	inventory_changed.emit()
	purchase_completed.emit(summary.duplicate(true))
	return {"ok": true, "summary": summary}


func discard_item(item_key: String, quantity := 1) -> Dictionary:
	_last_error = ""
	var normalized_key := item_key.strip_edges()
	if not _items_by_slug.has(normalized_key):
		return _inventory_failure("Unknown inventory item: %s" % normalized_key)
	if quantity <= 0:
		return _inventory_failure("Discard quantity must be at least one.")
	var current_quantity := int(_item_inventory.get(normalized_key, 0))
	if current_quantity < quantity:
		return _inventory_failure(
			"You only have %d of that item in the bag." % current_quantity
		)

	var remaining := current_quantity - quantity
	if remaining > 0:
		_item_inventory[normalized_key] = remaining
	else:
		_item_inventory.erase(normalized_key)
	var item := _items_by_slug[normalized_key] as Dictionary
	var summary := {
		"kind": "discarded_item",
		"id": normalized_key,
		"name": String(item.get("name", normalized_key)),
		"quantity": quantity,
		"remaining": remaining,
	}
	_emit_progression_change()
	inventory_changed.emit()
	return {"ok": true, "summary": summary}


func buy_pokemon(pokemon_id: int) -> Dictionary:
	_last_error = ""
	if not _pokemon_by_id.has(pokemon_id):
		return _purchase_failure("That Pokemon is not in Stretchman's catalog.")
	var offer := _pokemon_by_id[pokemon_id] as Dictionary
	var price := int(offer.get("price", 0))
	if not _can_afford(price):
		return _purchase_failure(
			"Stretchman wants %s, but you only have %s."
			% [format_money(price), format_money(_balance)]
		)

	var purchased := CollectionSystem.add_pokemon(
		pokemon_id,
		PURCHASED_POKEMON_LEVEL,
		1.0,
		-1,
		0
	)
	if purchased.is_empty():
		return _purchase_failure(
			"The Pokemon could not be added to storage: %s"
			% CollectionSystem.get_last_error()
		)

	_balance -= price
	var summary := {
		"kind": "pokemon",
		"id": pokemon_id,
		"pcl_id": String(purchased.get("pclID", "")),
		"name": String(offer.get("name", "Pokemon")),
		"price": price,
		"level": PURCHASED_POKEMON_LEVEL,
	}
	_emit_progression_change(true)
	purchase_completed.emit(summary.duplicate(true))
	return {"ok": true, "summary": summary}


func buy_loot_box(box_id: String) -> Dictionary:
	_last_error = ""
	var offer := Content.get_loot_box(box_id.strip_edges())
	if offer.is_empty():
		return _purchase_failure("Stretchman does not recognize that loot box.")
	var price := int(offer.get("price", 0))
	if not _can_afford(price):
		return _purchase_failure(
			"Stretchman wants %s, but you only have %s."
			% [format_money(price), format_money(_balance)]
		)

	var high_quality := _loot_rng.randf() < LOOT_BOX_HIGH_QUALITY_CHANCE
	var pool: Array = (
		offer.get("high_quality_pool", []) as Array
		if high_quality
		else Content.BORING_LOOT_POKEMON_IDS
	)
	if pool.is_empty():
		return _purchase_failure("That loot box has no configured prize pool.")
	var pokemon_id := int(pool[_loot_rng.randi_range(0, pool.size() - 1)])
	var pokemon_offer := get_pokemon_offer(pokemon_id)
	if pokemon_offer.is_empty():
		return _purchase_failure("The selected loot-box Pokemon is unavailable.")

	var delivered_level := int(offer.get("level", 1))
	var awarded := CollectionSystem.add_pokemon(
		pokemon_id,
		delivered_level,
		1.0,
		-1,
		0
	)
	if awarded.is_empty():
		return _purchase_failure(
			"The loot-box prize could not enter storage: %s"
			% CollectionSystem.get_last_error()
		)

	_balance -= price
	var summary := {
		"kind": "loot_box",
		"id": String(offer.get("id", "")),
		"name": String(offer.get("name", "Loot Box")),
		"price": price,
		"pokemon_id": pokemon_id,
		"pokemon_name": String(pokemon_offer.get("name", "Pokemon")),
		"pokemon": pokemon_offer,
		"pcl_id": String(awarded.get("pclID", "")),
		"level": delivered_level,
		"high_quality": high_quality,
		"quality": "HIGH QUALITY" if high_quality else "BORING POOL",
		"offer": offer,
	}
	_emit_progression_change(true)
	purchase_completed.emit(summary.duplicate(true))
	loot_box_opened.emit(summary.duplicate(true))
	return {"ok": true, "summary": summary}


func build_loot_box_reel(
	box_id: String,
	winner_pokemon_id: int,
	reel_size := 31,
	winner_index := 26
) -> Array[int]:
	var offer := Content.get_loot_box(box_id)
	if offer.is_empty():
		return []
	var safe_size := clampi(reel_size, 9, 101)
	var safe_winner_index := clampi(winner_index, 4, safe_size - 3)
	var high_pool := offer.get("high_quality_pool", []) as Array
	if high_pool.is_empty():
		return []
	var reel: Array[int] = []
	for reel_index in safe_size:
		if reel_index == safe_winner_index:
			reel.append(winner_pokemon_id)
			continue
		var use_high_pool := _loot_rng.randf() < LOOT_BOX_HIGH_QUALITY_CHANCE
		var pool: Array = high_pool if use_high_pool else Content.BORING_LOOT_POKEMON_IDS
		reel.append(int(pool[_loot_rng.randi_range(0, pool.size() - 1)]))
	# Always show at least one tempting near miss without changing the already
	# committed result or the actual fixed 10% prize roll.
	var near_miss_index := maxi(0, safe_winner_index - 2)
	if near_miss_index != safe_winner_index:
		reel[near_miss_index] = int(high_pool[_loot_rng.randi_range(0, high_pool.size() - 1)])
	return reel


func get_destinations(kind: String) -> Array[Dictionary]:
	return Content.get_destinations(kind)


func begin_destination(kind: String, destination_index: int) -> Dictionary:
	_last_error = ""
	var destination := Content.get_destination(kind, destination_index)
	if destination.is_empty():
		_last_error = "Unknown Stretchman destination: %s %d" % [kind, destination_index]
		return {}
	_run_id += 1
	_active_destination = destination.duplicate(true)
	_active_destination["kind"] = kind
	_active_destination["scene_path"] = Content.DESTINATION_SCENE_PATH
	_active_destination["run_id"] = _run_id
	_run_defeated_ids.clear()
	progression_changed.emit()
	destination_started.emit(_active_destination.duplicate(true))
	return _active_destination.duplicate(true)


func get_active_destination() -> Dictionary:
	return _active_destination.duplicate(true)


func get_active_encounters() -> Array[Dictionary]:
	if _active_destination.is_empty():
		return []
	return Content.get_encounters(
		String(_active_destination.get("kind", "")),
		int(_active_destination.get("index", 0))
	)


func get_encounter_by_id(encounter_id: String) -> Dictionary:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id.is_empty():
		return {}
	for encounter in get_active_encounters():
		if String(encounter.get("encounter_id", "")) == normalized_id:
			return encounter.duplicate(true)
	return {}


func is_encounter_defeated(encounter_id: String) -> bool:
	return _run_defeated_ids.has(encounter_id)


func get_run_defeated_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _run_defeated_ids.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func format_money(amount: int) -> String:
	var digits := str(maxi(amount, 0))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return "$" + ",".join(groups)


func get_save_data() -> Dictionary:
	return {
		"economy_version": CURRENT_ECONOMY_VERSION,
		"balance": _balance,
		"item_inventory": _item_inventory.duplicate(true),
		"earned_badges": _earned_badges.duplicate(),
		"champion_cleared": _champion_cleared,
		"active_destination": _active_destination.duplicate(true),
		"run_defeated_ids": get_run_defeated_ids(),
		"run_id": _run_id,
		"last_battle_reward": _last_battle_reward.duplicate(true),
	}


func validate_save_data(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Stretch progression is not an object."
	var data := value as Dictionary
	var economy_version_value: Variant = data.get("economy_version", 1)
	if (
		not _is_integer_value(economy_version_value)
		or int(economy_version_value) < 1
		or int(economy_version_value) > CURRENT_ECONOMY_VERSION
	):
		return "Stretch progression has an invalid economy version."
	var balance_value: Variant = data.get("balance")
	if not _is_integer_value(balance_value) or int(balance_value) < 0 or int(balance_value) > MAX_BALANCE:
		return "Stretch progression has an invalid balance."

	var inventory_value: Variant = data.get("item_inventory", {})
	if typeof(inventory_value) != TYPE_DICTIONARY:
		return "Stretch progression has an invalid item inventory."
	for key: Variant in (inventory_value as Dictionary).keys():
		if typeof(key) != TYPE_STRING or not _items_by_slug.has(String(key)):
			return "Stretch progression contains an unknown item."
		var quantity: Variant = (inventory_value as Dictionary)[key]
		if not _is_integer_value(quantity) or int(quantity) < 1 or int(quantity) > MAX_ITEM_QUANTITY:
			return "Stretch progression contains an invalid item quantity."

	var badges_value: Variant = data.get("earned_badges", [])
	if typeof(badges_value) != TYPE_ARRAY:
		return "Stretch progression has an invalid badge list."
	var seen_badges: Dictionary = {}
	for badge_value: Variant in badges_value as Array:
		if not _is_integer_value(badge_value) or int(badge_value) < 1 or int(badge_value) > 8:
			return "Stretch progression contains an invalid badge."
		if seen_badges.has(int(badge_value)):
			return "Stretch progression repeats a badge."
		seen_badges[int(badge_value)] = true

	if typeof(data.get("champion_cleared", false)) != TYPE_BOOL:
		return "Stretch progression has an invalid champion flag."
	if not _is_integer_value(data.get("run_id", 0)) or int(data.get("run_id", 0)) < 0:
		return "Stretch progression has an invalid run ID."

	var active_value: Variant = data.get("active_destination", {})
	if typeof(active_value) != TYPE_DICTIONARY:
		return "Stretch progression has an invalid active destination."
	var active := active_value as Dictionary
	if not active.is_empty():
		var kind := String(active.get("kind", ""))
		var destination_index := int(active.get("index", 0))
		if Content.get_destination(kind, destination_index).is_empty():
			return "Stretch progression references an unknown destination."

	var defeated_value: Variant = data.get("run_defeated_ids", [])
	if typeof(defeated_value) != TYPE_ARRAY:
		return "Stretch progression has an invalid defeated encounter list."
	for defeated_id: Variant in defeated_value as Array:
		if typeof(defeated_id) != TYPE_STRING or String(defeated_id).strip_edges().is_empty():
			return "Stretch progression contains an invalid defeated encounter ID."
	return ""


func load_save_data(value: Variant) -> bool:
	_last_error = validate_save_data(value)
	if not _last_error.is_empty():
		return false
	var data := value as Dictionary
	_balance = int(data["balance"])
	if (
		int(data.get("economy_version", 1)) < CURRENT_ECONOMY_VERSION
		and _is_untouched_legacy_economy(data)
	):
		_balance = STARTING_BALANCE
	_item_inventory = (data.get("item_inventory", {}) as Dictionary).duplicate(true)
	_earned_badges.clear()
	for badge_value: Variant in data.get("earned_badges", []) as Array:
		_earned_badges.append(int(badge_value))
	_earned_badges.sort()
	_champion_cleared = bool(data.get("champion_cleared", false))
	_active_destination = (data.get("active_destination", {}) as Dictionary).duplicate(true)
	_run_defeated_ids.clear()
	for defeated_id: Variant in data.get("run_defeated_ids", []) as Array:
		_run_defeated_ids[String(defeated_id)] = true
	_run_id = int(data.get("run_id", 0))
	_last_battle_reward = (
		(data.get("last_battle_reward", {}) as Dictionary).duplicate(true)
		if typeof(data.get("last_battle_reward", {})) == TYPE_DICTIONARY
		else {}
	)
	balance_changed.emit(_balance)
	inventory_changed.emit()
	progression_changed.emit()
	return true


func _load_catalogs() -> void:
	_item_catalog.clear()
	_pokemon_catalog.clear()
	_items_by_slug.clear()
	_pokemon_by_id.clear()

	var item_document := _read_json_dictionary(ITEM_CATALOG_PATH)
	var item_rows: Variant = item_document.get("items", [])
	if typeof(item_rows) == TYPE_ARRAY:
		for row_value: Variant in item_rows as Array:
			if typeof(row_value) != TYPE_DICTIONARY:
				continue
			var row := (row_value as Dictionary).duplicate(true)
			var slug := String(row.get("slug", ""))
			if slug.is_empty():
				continue
			var catalog_key := slug
			if _items_by_slug.has(catalog_key):
				catalog_key = "%s#%d" % [slug, int(row.get("id", 0))]
			row["key"] = catalog_key
			_item_catalog.append(row)
			_items_by_slug[catalog_key] = row

	var pokemon_document := _read_json_dictionary(POKEMON_CATALOG_PATH)
	var pokemon_rows: Variant = pokemon_document.get("pokemon", [])
	if typeof(pokemon_rows) == TYPE_ARRAY:
		for row_value: Variant in pokemon_rows as Array:
			if typeof(row_value) != TYPE_DICTIONARY:
				continue
			var row := (row_value as Dictionary).duplicate(true)
			var pokemon_id := int(row.get("id", 0))
			if pokemon_id <= 0 or _pokemon_by_id.has(pokemon_id):
				continue
			_pokemon_catalog.append(row)
			_pokemon_by_id[pokemon_id] = row

	if _item_catalog.is_empty() or _pokemon_catalog.is_empty():
		push_error("Stretchman's generated shop catalogs could not be loaded.")


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _can_afford(price: int) -> bool:
	return price > 0 and _balance >= price


func _is_integer_value(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	return (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floorf(float(value)) == float(value)
	)


func _purchase_failure(message: String) -> Dictionary:
	_last_error = message
	purchase_failed.emit(message)
	return {"ok": false, "error": message}


func _inventory_failure(message: String) -> Dictionary:
	_last_error = message
	return {"ok": false, "error": message}


func _emit_progression_change(emit_balance := false) -> void:
	if emit_balance:
		balance_changed.emit(_balance)
	progression_changed.emit()


func _on_battle_ended(result: Dictionary) -> void:
	var launch_data := GameInstance.get_active_battle_data()
	var encounter_id := String(launch_data.get("encounter_id", "")).strip_edges()
	if encounter_id.is_empty():
		return
	var encounter := get_encounter_by_id(encounter_id)
	if encounter.is_empty():
		_apply_generic_battle_result(launch_data, result)
		return
	_apply_battle_result(encounter, result)


func _apply_battle_result(encounter: Dictionary, result: Dictionary) -> void:
	var winner := String(result.get("winner", "tie"))
	var reason := String(result.get("reason", ""))
	var reward := _calculate_battle_reward(encounter, winner, reason)
	if winner == "player":
		_record_encounter_victory(encounter)
	if reward > 0:
		_balance = mini(_balance + reward, MAX_BALANCE)

	_last_battle_reward = {
		"amount": reward,
		"winner": winner,
		"reason": reason,
		"encounter_id": String(encounter.get("encounter_id", "")),
		"opponent": String(encounter.get("display_name", "Trainer")),
	}
	_emit_progression_change(reward > 0)
	battle_reward_granted.emit(_last_battle_reward.duplicate(true))


func _apply_generic_battle_result(
	launch_data: Dictionary,
	result: Dictionary
) -> void:
	var reason := String(result.get("reason", ""))
	var winner := String(result.get("winner", "tie"))
	var reward := 0
	if reason != "forfeit":
		match winner:
			"player":
				reward = 20
			"tie":
				reward = 5
			"opponent":
				reward = 2
	if reward > 0:
		_balance = mini(_balance + reward, MAX_BALANCE)
	var opponent_name := "Opponent"
	for field in ["trainer_name", "opponent_name", "encounter_name"]:
		var candidate := String(launch_data.get(field, "")).strip_edges()
		if not candidate.is_empty():
			opponent_name = candidate
			break
	_last_battle_reward = {
		"amount": reward,
		"winner": winner,
		"reason": reason,
		"encounter_id": String(launch_data.get("encounter_id", "")),
		"opponent": opponent_name,
	}
	_emit_progression_change(reward > 0)
	battle_reward_granted.emit(_last_battle_reward.duplicate(true))


func _record_encounter_victory(encounter: Dictionary) -> void:
	var encounter_id := String(encounter.get("encounter_id", ""))
	if not encounter_id.is_empty():
		_run_defeated_ids[encounter_id] = true
	var kind := String(_active_destination.get("kind", ""))
	if kind == "gym":
		var gym_index := int(_active_destination.get("index", 0))
		if gym_index >= 1 and gym_index <= 8 and gym_index not in _earned_badges:
			_earned_badges.append(gym_index)
			_earned_badges.sort()
	elif kind == "champion" and encounter_id == "stretch-champion":
		_champion_cleared = true


func _calculate_battle_reward(encounter: Dictionary, winner: String, reason: String) -> int:
	if reason == "forfeit":
		return 0
	var base_reward := _destination_win_reward(encounter)
	match winner:
		"player":
			return base_reward
		"tie":
			return maxi(roundi(base_reward * 0.25), 1)
		"opponent":
			return maxi(roundi(base_reward * 0.1), 1)
	return 0


func _destination_win_reward(encounter: Dictionary) -> int:
	var destination_index := int(_active_destination.get("index", 1))
	match String(_active_destination.get("kind", "")):
		"route":
			var route_rewards: Array[int] = [20, 100, 250, 500, 1_000, 1_800, 2_800, 4_000]
			return route_rewards[clampi(destination_index, 1, route_rewards.size()) - 1]
		"gym":
			var gym_rewards: Array[int] = [200, 400, 750, 1_200, 2_000, 3_000, 4_500, 6_000]
			return gym_rewards[clampi(destination_index, 1, gym_rewards.size()) - 1]
		"champion":
			var encounter_id := String(encounter.get("encounter_id", ""))
			var champion_ids: Array[String] = [
				"stretch-elite-four-1",
				"stretch-elite-four-2",
				"stretch-elite-four-3",
				"stretch-elite-four-4",
				"stretch-champion",
			]
			var challenge_index := champion_ids.find(encounter_id)
			return 8_000 + maxi(challenge_index, 0) * 1_000
	return 20


func _is_untouched_legacy_economy(data: Dictionary) -> bool:
	var inventory_value: Variant = data.get("item_inventory", {})
	var badges_value: Variant = data.get("earned_badges", [])
	var reward_value: Variant = data.get("last_battle_reward", {})
	return (
		int(data.get("balance", 0)) == LEGACY_STARTING_BALANCE
		and typeof(inventory_value) == TYPE_DICTIONARY
		and (inventory_value as Dictionary).is_empty()
		and typeof(badges_value) == TYPE_ARRAY
		and (badges_value as Array).is_empty()
		and not bool(data.get("champion_cleared", false))
		and typeof(reward_value) == TYPE_DICTIONARY
		and (reward_value as Dictionary).is_empty()
	)
