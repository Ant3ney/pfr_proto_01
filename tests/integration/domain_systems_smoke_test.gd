extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_economy := EconomySystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	var original_challenge := ChallengeProgressionSystem.get_save_data()

	_check(EconomyService.STARTING_BALANCE == 50, "A fresh economy should start at $50.")
	_check(
		EconomySystem.load_save_data({
			"version": EconomyService.CURRENT_ECONOMY_VERSION,
			"balance": 8_000_000_000,
			"last_battle_reward": {},
		}),
		"The economy fixture should accept a funded balance."
	)
	InventorySystem.reset_progress()
	ChallengeProgressionSystem.reset_progress()

	var items := ShopSystem.get_item_catalog()
	var pokemon := ShopSystem.get_pokemon_catalog()
	var boxes := ShopSystem.get_loot_box_catalog()
	_check(items.size() == 2223, "The shop should expose all 2,223 pinned items.")
	_check(pokemon.size() == 1025, "The shop should expose all 1,025 default species forms.")
	_check(boxes.size() == 6, "The loot-box catalog should contain six tiers.")
	_check(int(_find_entry(items, "slug", "potion").get("price", 0)) == 20, "Potion should retain its low-cash $20 price.")
	_check(int(_find_entry(items, "slug", "exp-share").get("price", 0)) == 100_000, "Exp. Share should retain its $100,000 price.")
	_check(ShopSystem.get_pokemon_purchase_level(10) == ShopService.PURCHASED_POKEMON_MIN_LEVEL, "A floor-price Pokemon should arrive at Lv. 5.")
	_check(ShopSystem.get_pokemon_purchase_level(150) == ShopService.PURCHASED_POKEMON_MAX_LEVEL, "A premium Pokemon should arrive at Lv. 20.")

	var balance_before := EconomySystem.get_balance()
	var item_purchase := ShopSystem.buy_item("potion")
	_check(bool(item_purchase.get("ok", false)), "A funded item purchase should succeed.")
	_check(InventorySystem.get_item_count("potion") == 1, "Purchased items should enter InventorySystem.")
	_check(EconomySystem.get_balance() == balance_before - 20, "ShopSystem should spend through EconomySystem.")

	var gift := InventorySystem.claim_unique_item("domain-smoke-exp-share", InventoryService.XP_SHARE_ITEM_KEY)
	var repeated_gift := InventorySystem.claim_unique_item("domain-smoke-exp-share", InventoryService.XP_SHARE_ITEM_KEY)
	_check(bool(gift.get("ok", false)) and bool((gift.get("summary", {}) as Dictionary).get("newly_claimed", false)), "A stable world gift should be claimable once.")
	_check(bool(repeated_gift.get("ok", false)) and not bool((repeated_gift.get("summary", {}) as Dictionary).get("newly_claimed", true)), "Repeating a claimed gift should not duplicate it.")
	_check(InventorySystem.get_item_count(InventoryService.XP_SHARE_ITEM_KEY) == 1, "A repeated gift should leave one item in the bag.")

	var party := CollectionSystem.get_party()
	if party.is_empty():
		_check(false, "The held-item fixture requires the existing test party.")
	else:
		var pcl_id := String(party[0].get("pclID", ""))
		var equipped := InventorySystem.give_item_to_pokemon(InventoryService.XP_SHARE_ITEM_KEY, pcl_id)
		_check(bool(equipped.get("ok", false)) and CollectionSystem.get_held_item(pcl_id) == InventoryService.XP_SHARE_ITEM_KEY, "Equipping should atomically transfer an item from the bag.")
		var taken := InventorySystem.take_held_item_from_pokemon(pcl_id)
		_check(bool(taken.get("ok", false)) and CollectionSystem.get_held_item(pcl_id).is_empty(), "Taking a held item should return it to the bag.")

	var collection_size := CollectionSystem.get_collection_size()
	var pokemon_purchase := ShopSystem.buy_pokemon(10)
	_check(bool(pokemon_purchase.get("ok", false)), "A funded Pokemon purchase should succeed.")
	_check(CollectionSystem.get_collection_size() == collection_size + 1, "Purchased Pokemon should enter CollectionSystem storage.")
	var loot_size := CollectionSystem.get_collection_size()
	var loot_purchase := ShopSystem.buy_loot_box("scuffed-parcel")
	_check(bool(loot_purchase.get("ok", false)), "A funded loot-box purchase should succeed.")
	_check(CollectionSystem.get_collection_size() == loot_size + 1, "Loot-box prizes should be committed before presentation.")
	if bool(loot_purchase.get("ok", false)):
		var summary := loot_purchase.get("summary", {}) as Dictionary
		_check(ShopSystem.build_loot_box_reel("scuffed-parcel", int(summary.get("pokemon_id", 0))).size() == 31, "The roulette presentation should build a fixed reel from an immutable prize.")

	var catalog := ChallengeProgressionSystem.get_catalog()
	_check(catalog != null, "Challenge progression should load the standalone-area catalog.")
	if catalog != null:
		_check(catalog.areas.size() == StandaloneAreaCatalog.TOTAL_AREA_COUNT, "The catalog should contain exactly 50 areas.")
		_check(catalog.validate().is_empty(), "Every area and encounter resource should validate.")
		_check(ChallengeProgressionSystem.get_destinations("route").size() == StandaloneAreaCatalog.ROUTE_COUNT, "The Adventure Menu should receive 41 routes.")
		_check(ChallengeProgressionSystem.get_destinations("gym").size() == 8, "The Adventure Menu should receive eight gyms.")
		_check(ChallengeProgressionSystem.get_destinations("champion").size() == 1, "The Adventure Menu should receive one champion challenge.")

	_check(ChallengeProgressionSystem.is_route_unlocked(0) and not ChallengeProgressionSystem.is_route_unlocked(1), "Only Route 0 should begin unlocked.")
	var route_zero_result := ChallengeProgressionSystem.complete_route_at_end(0)
	_check(bool(route_zero_result.get("ok", false)) and ChallengeProgressionSystem.is_route_unlocked(1), "Completing Route 0 should unlock Route 1.")
	var route_one_state := ChallengeProgressionSystem.get_save_data()
	route_one_state["active_area_id"] = "route_01"
	route_one_state["run_id"] = 1
	_check(ChallengeProgressionSystem.load_save_data(route_one_state), "A Route 1 active-run fixture should validate.")
	var route_one := ChallengeProgressionSystem.get_area("route_01")
	if route_one != null:
		for encounter in route_one.battle_encounters:
			ChallengeProgressionSystem.record_encounter_victory(encounter.encounter_id)
	_check(bool(ChallengeProgressionSystem.complete_route_at_end(1).get("ok", false)), "Defeating each authored Route 1 trainer should permit end-gate completion.")
	_check(ChallengeProgressionSystem.get_completed_routes() == [0, 1], "Sequential route completion should persist as an ordered prefix.")

	ChallengeProgressionSystem.record_encounter_victory("gym-01-leader")
	ChallengeProgressionSystem.record_encounter_victory("champion")
	_check(ChallengeProgressionSystem.has_badge(1), "A gym-leader victory should award Badge 1.")
	_check(ChallengeProgressionSystem.is_champion_completed(), "The champion victory should complete the challenge.")
	var route_one_reward := int(BattleRewardSystem.call("_calculate_reward", route_one, "route-01-trainer-01", "player", "all_pokemon_fainted"))
	_check(route_one_reward == 80, "Route 1's battle reward should preserve the scaled $80 payout.")

	CollectionSystem.load_save_data(original_collection)
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	ChallengeProgressionSystem.load_save_data(original_challenge)

	if _failures.is_empty():
		print("Domain systems smoke test passed: economy, shop, inventory, loot boxes, rewards, 50-area catalog, route locks, badges, and champion progression verified.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Domain systems smoke test failed: %s" % failure)
	get_tree().quit(1)


func _find_entry(entries: Array[Dictionary], field: String, expected: Variant) -> Dictionary:
	for entry in entries:
		if entry.get(field) == expected:
			return entry
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
