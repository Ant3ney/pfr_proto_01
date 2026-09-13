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
	_check(
		ShopSystem.get_known_item_catalog().size() == 2223,
		"The runtime should retain metadata for all 2,223 pinned items."
	)
	_check(
		items.size() == 2
		and String(items[0].get("slug", "")) == InventoryService.RARE_CANDY_ITEM_KEY
		and String(items[1].get("slug", "")) == InventoryService.XP_SHARE_ITEM_KEY,
		"The store should expose only the implemented Rare Candy and Exp. Share."
	)
	_check(pokemon.size() == 1025, "The shop should expose all 1,025 default species forms.")
	_check(boxes.size() == 6, "The loot-box catalog should contain six tiers.")
	_check(int(_find_entry(items, "slug", "rare-candy").get("price", 0)) == 1_000, "Rare Candy should retain its $1,000 price.")
	_check(int(_find_entry(items, "slug", "exp-share").get("price", 0)) == 100_000, "Exp. Share should retain its $100,000 price.")
	_check(ShopSystem.get_pokemon_purchase_level(10) == ShopService.PURCHASED_POKEMON_MIN_LEVEL, "A floor-price Pokemon should arrive at Lv. 5.")
	_check(ShopSystem.get_pokemon_purchase_level(150) == ShopService.PURCHASED_POKEMON_MAX_LEVEL, "A premium Pokemon should arrive at Lv. 20.")

	var balance_before := EconomySystem.get_balance()
	var hidden_item_purchase := ShopSystem.buy_item("potion")
	_check(
		not bool(hidden_item_purchase.get("ok", true))
		and EconomySystem.get_balance() == balance_before
		and InventorySystem.get_item_count("potion") == 0,
		"A known but unimplemented item should stay hidden and reject direct purchase."
	)
	var item_purchase := ShopSystem.buy_item(InventoryService.RARE_CANDY_ITEM_KEY)
	_check(bool(item_purchase.get("ok", false)), "A funded Rare Candy purchase should succeed.")
	_check(
		InventorySystem.get_item_count(InventoryService.RARE_CANDY_ITEM_KEY) == 1,
		"A purchased Rare Candy should enter InventorySystem."
	)
	_check(EconomySystem.get_balance() == balance_before - 1_000, "ShopSystem should spend through EconomySystem.")

	var gift := InventorySystem.claim_unique_item("domain-smoke-exp-share", InventoryService.XP_SHARE_ITEM_KEY)
	var repeated_gift := InventorySystem.claim_unique_item("domain-smoke-exp-share", InventoryService.XP_SHARE_ITEM_KEY)
	_check(bool(gift.get("ok", false)) and bool((gift.get("summary", {}) as Dictionary).get("newly_claimed", false)), "A stable world gift should be claimable once.")
	_check(bool(repeated_gift.get("ok", false)) and not bool((repeated_gift.get("summary", {}) as Dictionary).get("newly_claimed", true)), "Repeating a claimed gift should not duplicate it.")
	_check(InventorySystem.get_item_count(InventoryService.XP_SHARE_ITEM_KEY) == 1, "A repeated gift should leave one item in the bag.")
	var candy_pokemon := CollectionSystem.add_pokemon(10, 5, 0.55, -1, 0)
	var candy_pcl_id := String(candy_pokemon.get("pclID", ""))
	var previous_stats := candy_pokemon.get("instanceStats", {}) as Dictionary
	var previous_level := int(previous_stats.get("level", 0))
	var expected_next_xp := CreatureSystem.get_experience_for_level(10, previous_level + 1)
	var candy_result := InventorySystem.use_rare_candy_on_pokemon(candy_pcl_id)
	var leveled_pcl := CollectionSystem.get_pcl(candy_pcl_id)
	var leveled_stats := leveled_pcl.get("instanceStats", {}) as Dictionary
	_check(
		bool(candy_result.get("ok", false))
		and int(leveled_stats.get("level", 0)) == previous_level + 1
		and int(leveled_stats.get("currentXp", -1)) == expected_next_xp
		and is_equal_approx(float(leveled_stats.get("health", -1.0)), 0.55)
		and InventorySystem.get_item_count(InventoryService.RARE_CANDY_ITEM_KEY) == 0,
		"Rare Candy should consume once, reach the exact next-level XP threshold, and preserve health."
	)

	var party := CollectionSystem.get_party()
	if party.is_empty():
		_check(false, "The item-effect fixture requires the existing test party.")
	else:
		var pcl_id := String(party[0].get("pclID", ""))
		var equipped := InventorySystem.give_item_to_pokemon(InventoryService.XP_SHARE_ITEM_KEY, pcl_id)
		_check(bool(equipped.get("ok", false)) and CollectionSystem.get_held_item(pcl_id) == InventoryService.XP_SHARE_ITEM_KEY, "Equipping should atomically transfer an item from the bag.")
		var taken := InventorySystem.take_held_item_from_pokemon(pcl_id)
		_check(bool(taken.get("ok", false)) and CollectionSystem.get_held_item(pcl_id).is_empty(), "Taking a held item should return it to the bag.")
	var max_level_pokemon := CollectionSystem.add_pokemon(10, 100, 1.0, -1, 0)
	_check(not max_level_pokemon.is_empty(), "The Rare Candy cap fixture should be created.")
	_check(
		bool(InventorySystem.add_item(InventoryService.RARE_CANDY_ITEM_KEY).get("ok", false)),
		"The Rare Candy cap fixture should receive one candy."
	)
	var capped_candy_result := InventorySystem.use_rare_candy_on_pokemon(
		String(max_level_pokemon.get("pclID", ""))
	)
	_check(
		not bool(capped_candy_result.get("ok", true))
		and InventorySystem.get_item_count(InventoryService.RARE_CANDY_ITEM_KEY) == 1,
		"Rare Candy should not be consumed by a Lv. 100 Pokemon."
	)
	InventorySystem.discard_item(InventoryService.RARE_CANDY_ITEM_KEY)

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
	var jackpot_payout := BattleRewardSystem.call(
		"_apply_trainer_jackpot", route_one_reward, "trainer", 0.099999
	) as Dictionary
	_check(
		int(jackpot_payout.get("amount", 0)) == route_one_reward * 20
		and bool(jackpot_payout.get("jackpot", false))
		and int(jackpot_payout.get("multiplier", 0)) == 20,
		"A trainer jackpot roll below 10% should pay exactly 20 times the normal reward."
	)
	var ordinary_payout := BattleRewardSystem.call(
		"_apply_trainer_jackpot", route_one_reward, "trainer", 0.1
	) as Dictionary
	_check(
		int(ordinary_payout.get("amount", 0)) == route_one_reward
		and not bool(ordinary_payout.get("jackpot", true)),
		"The 10% boundary should begin the ordinary trainer-payout range."
	)
	var wild_payout := BattleRewardSystem.call(
		"_apply_trainer_jackpot", route_one_reward, "wild", 0.0
	) as Dictionary
	_check(
		int(wild_payout.get("amount", 0)) == route_one_reward
		and not bool(wild_payout.get("jackpot", true)),
		"Wild battles should never receive the trainer jackpot."
	)
	var forfeit_payout := BattleRewardSystem.call(
		"_apply_trainer_jackpot", 0, "trainer", 0.0
	) as Dictionary
	_check(
		int(forfeit_payout.get("amount", -1)) == 0
		and not bool(forfeit_payout.get("jackpot", true)),
		"A zero-payout trainer battle should remain ineligible for a jackpot."
	)

	CollectionSystem.load_save_data(original_collection)
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	ChallengeProgressionSystem.load_save_data(original_challenge)

	if _failures.is_empty():
		print("Domain systems smoke test passed: implemented-item storefront, Rare Candy, inventory, loot boxes, trainer jackpots, 50-area catalog, route locks, badges, and champion progression verified.")
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
