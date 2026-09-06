class_name ShopService
extends Node

## Owns immutable item, Pokemon, and loot-box catalogs plus purchase
## transactions. Money and bag state remain in their dedicated systems.

signal purchase_completed(summary: Dictionary)
signal purchase_failed(message: String)
signal loot_box_opened(summary: Dictionary)

const ITEM_CATALOG_PATH := "res://game/economy/shop/catalogs/items.json"
const POKEMON_CATALOG_PATH := "res://game/economy/shop/catalogs/pokemon.json"
const PURCHASED_POKEMON_MIN_LEVEL := 5
const PURCHASED_POKEMON_MAX_LEVEL := 20
const PURCHASED_POKEMON_LEVEL_PRICE_FLOOR := 500
const PURCHASED_POKEMON_LEVEL_PRICE_CAP := 2_000_000_000

var _item_catalog: Array[Dictionary] = []
var _pokemon_catalog: Array[Dictionary] = []
var _items_by_key: Dictionary = {}
var _pokemon_by_id: Dictionary = {}
var _last_error := ""
var _loot_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_load_catalogs()
	_loot_rng.randomize()


func get_item_catalog() -> Array[Dictionary]:
	return _item_catalog.duplicate(true)


func get_pokemon_catalog() -> Array[Dictionary]:
	return _pokemon_catalog.duplicate(true)


func get_loot_box_catalog() -> Array[Dictionary]:
	return LootBoxCatalog.get_offers()


func has_item(item_key: String) -> bool:
	return _items_by_key.has(item_key.strip_edges())


func get_item_offer(item_key: String) -> Dictionary:
	var normalized_key := item_key.strip_edges()
	if not _items_by_key.has(normalized_key):
		return {}
	return (_items_by_key[normalized_key] as Dictionary).duplicate(true)


func get_pokemon_offer(pokemon_id: int) -> Dictionary:
	if not _pokemon_by_id.has(pokemon_id):
		return {}
	return (_pokemon_by_id[pokemon_id] as Dictionary).duplicate(true)


func get_pokemon_purchase_level(pokemon_id: int) -> int:
	var offer := get_pokemon_offer(pokemon_id)
	if offer.is_empty():
		return 0
	return _pokemon_purchase_level_for_price(int(offer.get("price", 0)))


func buy_item(item_key: String) -> Dictionary:
	_last_error = ""
	var normalized_key := item_key.strip_edges()
	var item := get_item_offer(normalized_key)
	if item.is_empty():
		return _purchase_failure("Unknown shop item: %s" % normalized_key)
	var price := int(item.get("price", 0))
	if not EconomySystem.can_afford(price):
		return _purchase_failure(EconomySystem.get_last_error() if not EconomySystem.get_last_error().is_empty() else (
			"That item costs %s, but you only have %s."
			% [EconomySystem.format_money(price), EconomySystem.format_money(EconomySystem.get_balance())]
		))
	if not InventorySystem.can_add_item(normalized_key):
		return _purchase_failure("There is no room for that item in the bag.")
	if not EconomySystem.spend_money(price):
		return _purchase_failure(EconomySystem.get_last_error())
	var inventory_result := InventorySystem.add_item(normalized_key)
	if not bool(inventory_result.get("ok", false)):
		EconomySystem.grant_money(price)
		return _purchase_failure(String(inventory_result.get("error", "The item could not enter the bag.")))
	var summary := {
		"kind": "item",
		"id": normalized_key,
		"name": String(item.get("name", normalized_key)),
		"price": price,
		"quantity": InventorySystem.get_item_count(normalized_key),
	}
	purchase_completed.emit(summary.duplicate(true))
	return {"ok": true, "summary": summary}


func buy_pokemon(pokemon_id: int) -> Dictionary:
	_last_error = ""
	var offer := get_pokemon_offer(pokemon_id)
	if offer.is_empty():
		return _purchase_failure("That Pokemon is not in the shop catalog.")
	var price := int(offer.get("price", 0))
	if not EconomySystem.can_afford(price):
		return _purchase_failure(
			"That Pokemon costs %s, but you only have %s."
			% [EconomySystem.format_money(price), EconomySystem.format_money(EconomySystem.get_balance())]
		)
	if not EconomySystem.spend_money(price):
		return _purchase_failure(EconomySystem.get_last_error())
	var delivered_level := _pokemon_purchase_level_for_price(price)
	var purchased := CollectionSystem.add_pokemon(pokemon_id, delivered_level, 1.0, -1, 0)
	if purchased.is_empty():
		EconomySystem.grant_money(price)
		return _purchase_failure(
			"The Pokemon could not be added to storage: %s"
			% CollectionSystem.get_last_error()
		)
	var summary := {
		"kind": "pokemon",
		"id": pokemon_id,
		"pcl_id": String(purchased.get("pclID", "")),
		"name": String(offer.get("name", "Pokemon")),
		"price": price,
		"level": delivered_level,
	}
	purchase_completed.emit(summary.duplicate(true))
	return {"ok": true, "summary": summary}


func buy_loot_box(box_id: String) -> Dictionary:
	_last_error = ""
	var offer := LootBoxCatalog.get_offer(box_id)
	if offer.is_empty():
		return _purchase_failure("Unknown loot box.")
	var price := int(offer.get("price", 0))
	if not EconomySystem.can_afford(price):
		return _purchase_failure(
			"That loot box costs %s, but you only have %s."
			% [EconomySystem.format_money(price), EconomySystem.format_money(EconomySystem.get_balance())]
		)
	var high_quality := _loot_rng.randf() < LootBoxCatalog.HIGH_QUALITY_CHANCE
	var pool: Array = (
		offer.get("high_quality_pool", []) as Array
		if high_quality
		else LootBoxCatalog.COMMON_POKEMON_IDS
	)
	if pool.is_empty():
		return _purchase_failure("That loot box has no configured prize pool.")
	var pokemon_id := int(pool[_loot_rng.randi_range(0, pool.size() - 1)])
	var pokemon_offer := get_pokemon_offer(pokemon_id)
	if pokemon_offer.is_empty():
		return _purchase_failure("The selected loot-box Pokemon is unavailable.")
	if not EconomySystem.spend_money(price):
		return _purchase_failure(EconomySystem.get_last_error())
	var delivered_level := int(offer.get("level", 1))
	var awarded := CollectionSystem.add_pokemon(pokemon_id, delivered_level, 1.0, -1, 0)
	if awarded.is_empty():
		EconomySystem.grant_money(price)
		return _purchase_failure(
			"The loot-box prize could not enter storage: %s"
			% CollectionSystem.get_last_error()
		)
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
		"quality": "HIGH QUALITY" if high_quality else "COMMON POOL",
		"offer": offer,
	}
	purchase_completed.emit(summary.duplicate(true))
	loot_box_opened.emit(summary.duplicate(true))
	return {"ok": true, "summary": summary}


func build_loot_box_reel(
	box_id: String,
	winner_pokemon_id: int,
	reel_size := 31,
	winner_index := 26
) -> Array[int]:
	var offer := LootBoxCatalog.get_offer(box_id)
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
		var use_high_pool := _loot_rng.randf() < LootBoxCatalog.HIGH_QUALITY_CHANCE
		var pool: Array = high_pool if use_high_pool else LootBoxCatalog.COMMON_POKEMON_IDS
		reel.append(int(pool[_loot_rng.randi_range(0, pool.size() - 1)]))
	var near_miss_index := maxi(0, safe_winner_index - 2)
	if near_miss_index != safe_winner_index:
		reel[near_miss_index] = int(high_pool[_loot_rng.randi_range(0, high_pool.size() - 1)])
	return reel


func get_last_error() -> String:
	return _last_error


func _load_catalogs() -> void:
	_item_catalog.clear()
	_pokemon_catalog.clear()
	_items_by_key.clear()
	_pokemon_by_id.clear()
	var item_rows: Variant = _read_json_dictionary(ITEM_CATALOG_PATH).get("items", [])
	if typeof(item_rows) == TYPE_ARRAY:
		for row_value: Variant in item_rows as Array:
			if typeof(row_value) != TYPE_DICTIONARY:
				continue
			var row := (row_value as Dictionary).duplicate(true)
			var slug := String(row.get("slug", ""))
			if slug.is_empty():
				continue
			var catalog_key := slug
			if _items_by_key.has(catalog_key):
				catalog_key = "%s#%d" % [slug, int(row.get("id", 0))]
			row["key"] = catalog_key
			_item_catalog.append(row)
			_items_by_key[catalog_key] = row
	var pokemon_rows: Variant = _read_json_dictionary(POKEMON_CATALOG_PATH).get("pokemon", [])
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
		push_error("Shop catalogs could not be loaded.")


func _read_json_dictionary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _pokemon_purchase_level_for_price(price: int) -> int:
	var clamped_price := clampi(
		price,
		PURCHASED_POKEMON_LEVEL_PRICE_FLOOR,
		PURCHASED_POKEMON_LEVEL_PRICE_CAP
	)
	var minimum_log := log(float(PURCHASED_POKEMON_LEVEL_PRICE_FLOOR))
	var maximum_log := log(float(PURCHASED_POKEMON_LEVEL_PRICE_CAP))
	var price_progress := (
		(log(float(clamped_price)) - minimum_log) / (maximum_log - minimum_log)
	)
	return clampi(
		PURCHASED_POKEMON_MIN_LEVEL
		+ roundi(price_progress * (PURCHASED_POKEMON_MAX_LEVEL - PURCHASED_POKEMON_MIN_LEVEL)),
		PURCHASED_POKEMON_MIN_LEVEL,
		PURCHASED_POKEMON_MAX_LEVEL
	)


func _purchase_failure(message: String) -> Dictionary:
	_last_error = message
	purchase_failed.emit(message)
	return {"ok": false, "error": message}
