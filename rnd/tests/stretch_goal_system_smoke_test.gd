extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	var working_stretch := original_stretch.duplicate(true)
	working_stretch["balance"] = 8_000_000_000
	working_stretch["item_inventory"] = {}
	working_stretch["claimed_gifts"] = []
	working_stretch["completed_routes"] = []
	working_stretch["active_destination"] = {}
	working_stretch["run_defeated_ids"] = []
	_check(
		StretchGoalSystem.load_save_data(working_stretch),
		"The smoke fixture should be able to load a high R&D balance."
	)

	var items := StretchGoalSystem.get_item_catalog()
	var pokemon := StretchGoalSystem.get_pokemon_catalog()
	_check(StretchGoalSystem.STARTING_BALANCE == 50, "A fresh Stretchman economy should start with exactly $50.")
	_check(items.size() == 2223, "The item shop should expose all 2,223 pinned PokeAPI items.")
	_check(pokemon.size() == 1025, "The Pokemon shop should expose all 1,025 default species forms.")
	_check(_find_entry(items, "slug", "potion").get("name") == "Potion", "The full item catalog should include Potion.")
	_check(int(_find_entry(items, "slug", "potion").get("price", 0)) == 20, "A basic Potion should fit the low-cash economy.")
	_check(_find_entry(items, "slug", "master-ball").get("price", 0) >= 1_000_000, "Master Ball pricing should retain a collector premium.")
	_check(
		_find_entry(items, "slug", "exp-share").get("name", "") == "Exp. Share"
		and int(_find_entry(items, "slug", "exp-share").get("price", 0)) == 100_000,
		"The functional Exp. Share should have its exact $100,000 premium."
	)

	var caterpie := _find_entry(pokemon, "id", 10)
	var lucario := _find_entry(pokemon, "id", 448)
	var mewtwo := _find_entry(pokemon, "id", 150)
	_check(not caterpie.is_empty() and not mewtwo.is_empty(), "Known Pokemon should be present in the generated catalog.")
	_check(int(caterpie.get("price", 0)) >= 500, "Even an ordinary Pokemon should respect the $500 shop floor.")
	_check(int(lucario.get("price", 0)) > int(caterpie.get("price", 0)), "A curated cool-looking Pokemon should receive a larger markup.")
	_check(int(mewtwo.get("price", 0)) >= 2_000_000_000, "Legendary Pokemon should retain their extreme price premium.")
	_check(
		StretchGoalSystem.get_pokemon_purchase_level(10)
		== StretchGoalSystem.PURCHASED_POKEMON_MIN_LEVEL,
		"A floor-price Pokemon should be delivered at Lv. 5."
	)
	_check(
		StretchGoalSystem.get_pokemon_purchase_level(150)
		== StretchGoalSystem.PURCHASED_POKEMON_MAX_LEVEL,
		"A premium-price Pokemon should be delivered at Lv. 20."
	)
	_check(
		StretchGoalSystem.get_pokemon_purchase_level(-1) == 0,
		"Unknown Pokemon should not advertise a delivery level."
	)
	var pokemon_by_id: Dictionary = {}
	for offer in pokemon:
		pokemon_by_id[int(offer.get("id", 0))] = offer
		_check(
			int(offer.get("price", 0)) >= 500,
			"Every Pokemon offer should respect the $500 minimum."
		)
	for offer in pokemon:
		var parent_value: Variant = offer.get("evolvesFromId")
		if parent_value == null:
			continue
		var parent_id := int(parent_value)
		_check(pokemon_by_id.has(parent_id), "Every evolution parent should exist in the shop catalog.")
		if pokemon_by_id.has(parent_id):
			_check(
				int(offer.get("price", 0))
				> int((pokemon_by_id[parent_id] as Dictionary).get("price", 0)),
				"Every evolved Pokemon should cost more than its direct pre-evolution."
			)
	var pokemon_by_price := pokemon.duplicate(true)
	pokemon_by_price.sort_custom(
		func(left: Dictionary, right: Dictionary) -> bool:
			return int(left.get("price", 0)) < int(right.get("price", 0))
	)
	var previous_price := -1
	var previous_delivery_level := StretchGoalSystem.PURCHASED_POKEMON_MIN_LEVEL
	for offer in pokemon_by_price:
		var price := int(offer.get("price", 0))
		var delivery_level := StretchGoalSystem.get_pokemon_purchase_level(
			int(offer.get("id", 0))
		)
		_check(
			delivery_level >= StretchGoalSystem.PURCHASED_POKEMON_MIN_LEVEL
			and delivery_level <= StretchGoalSystem.PURCHASED_POKEMON_MAX_LEVEL,
			"Every direct Pokemon purchase should deliver within Lv. 5-20."
		)
		_check(
			delivery_level >= previous_delivery_level,
			"A higher shop price should never produce a lower delivery level."
		)
		if price == previous_price:
			_check(
				delivery_level == previous_delivery_level,
				"Equal prices should produce equal delivery levels."
			)
		previous_price = price
		previous_delivery_level = delivery_level
	var loot_boxes := StretchGoalSystem.get_loot_box_catalog()
	_check(loot_boxes.size() >= 6, "Stretchman should offer many increasingly expensive loot-box tiers.")
	var former_loot_box_prices: Array[int] = [100, 500, 2_500, 10_000, 100_000, 1_000_000]
	for loot_box_index in range(loot_boxes.size()):
		var loot_box := loot_boxes[loot_box_index]
		_check(
			int(loot_box.get("price", 0)) >= 400,
			"Every loot box should respect the $400 minimum."
		)
		if loot_box_index < former_loot_box_prices.size():
			_check(
				int(loot_box.get("price", 0)) > former_loot_box_prices[loot_box_index],
				"Every loot-box tier should cost more than its former price."
			)
	for box_index in range(1, loot_boxes.size()):
		_check(
			int(loot_boxes[box_index].get("price", 0))
			> int(loot_boxes[box_index - 1].get("price", 0)),
			"Every loot-box tier should cost more than the prior tier."
		)
	var top_box := loot_boxes.back() as Dictionary
	for pokemon_id in top_box.get("high_quality_pool", []) as Array:
		_check(
			bool(_find_entry(pokemon, "id", int(pokemon_id)).get("isLegendary", false)),
			"The top loot box's high-quality slot should contain legendary Pokemon."
		)

	var potion_before := StretchGoalSystem.get_item_count("potion")
	var item_purchase := StretchGoalSystem.buy_item("potion")
	_check(bool(item_purchase.get("ok", false)), "A funded player should be able to buy an item.")
	_check(StretchGoalSystem.get_item_count("potion") == potion_before + 1, "Item purchases should enter the R&D inventory.")
	var exp_share_balance_before := StretchGoalSystem.get_balance()
	var exp_share_purchase := StretchGoalSystem.buy_item(
		StretchGoalSystem.XP_SHARE_ITEM_KEY
	)
	_check(
		bool(exp_share_purchase.get("ok", false))
		and int((exp_share_purchase.get("summary", {}) as Dictionary).get("price", 0))
		== 100_000
		and StretchGoalSystem.get_balance() == exp_share_balance_before - 100_000
		and StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 1,
		"Buying an Exp. Share should deduct exactly $100,000 and add one to the bag."
	)
	_check(
		bool(StretchGoalSystem.discard_item(
			StretchGoalSystem.XP_SHARE_ITEM_KEY
		).get("ok", false)),
		"The premium purchase fixture should clear its Exp. Share before the gift checks."
	)

	var gift_result := StretchGoalSystem.claim_unique_item(
		"stretch-smoke-exp-share",
		StretchGoalSystem.XP_SHARE_ITEM_KEY
	)
	_check(
		bool(gift_result.get("ok", false))
		and bool((gift_result.get("summary", {}) as Dictionary).get("newly_claimed", false))
		and StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 1,
		"A stable world gift should place one Exp. Share in the bag."
	)
	var repeated_gift := StretchGoalSystem.claim_unique_item(
		"stretch-smoke-exp-share",
		StretchGoalSystem.XP_SHARE_ITEM_KEY
	)
	_check(
		bool(repeated_gift.get("ok", false))
		and not bool((repeated_gift.get("summary", {}) as Dictionary).get("newly_claimed", true))
		and StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 1,
		"A claimed world gift should not duplicate its item."
	)
	var held_item_pcl_id := String(CollectionSystem.get_party()[0].get("pclID", ""))
	var equip_result := StretchGoalSystem.give_item_to_pokemon(
		StretchGoalSystem.XP_SHARE_ITEM_KEY,
		held_item_pcl_id
	)
	_check(
		bool(equip_result.get("ok", false))
		and CollectionSystem.get_held_item(held_item_pcl_id) == StretchGoalSystem.XP_SHARE_ITEM_KEY
		and StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 0,
		"Giving an item should atomically move it from the bag onto the selected Pokemon."
	)
	var take_result := StretchGoalSystem.take_held_item_from_pokemon(held_item_pcl_id)
	_check(
		bool(take_result.get("ok", false))
		and CollectionSystem.get_held_item(held_item_pcl_id).is_empty()
		and StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 1,
		"Taking a held item should return the same item to the persistent bag."
	)
	var gift_save := StretchGoalSystem.get_save_data()
	_check(
		StretchGoalSystem.load_save_data(gift_save)
		and StretchGoalSystem.has_claimed_gift("stretch-smoke-exp-share"),
		"Claimed one-time gifts should survive Stretch progression save validation."
	)

	var collection_size_before := CollectionSystem.get_collection_size()
	var pokemon_purchase := StretchGoalSystem.buy_pokemon(10)
	_check(bool(pokemon_purchase.get("ok", false)), "A funded player should be able to buy a Pokemon.")
	_check(CollectionSystem.get_collection_size() == collection_size_before + 1, "Pokemon purchases should enter CollectionSystem storage.")
	if bool(pokemon_purchase.get("ok", false)):
		var summary := pokemon_purchase.get("summary", {}) as Dictionary
		var purchased := CollectionSystem.get_pcl(String(summary.get("pcl_id", "")))
		var advertised_level := StretchGoalSystem.get_pokemon_purchase_level(10)
		_check(
			int((purchased.get("instanceStats", {}) as Dictionary).get("level", 0))
			== advertised_level
			and int(summary.get("level", 0)) == advertised_level,
			"Purchased Pokemon and their receipt should use the price-derived level."
		)
		_check(
			int(summary.get("price", 0)) == int(caterpie.get("price", 0)),
			"Deriving delivery level must not rewrite the catalog price."
		)
		_check(
			not bool((purchased.get("party", {}) as Dictionary).get("inParty", true))
			and purchased.get("party", {}).get("slot") == null,
			"Pokemon bought from Stretchman should arrive in PC storage, not the party."
		)

	var premium_purchase := StretchGoalSystem.buy_pokemon(150)
	_check(bool(premium_purchase.get("ok", false)), "A funded player should be able to buy a premium Pokemon.")
	if bool(premium_purchase.get("ok", false)):
		var premium_summary := premium_purchase.get("summary", {}) as Dictionary
		var premium_pokemon := CollectionSystem.get_pcl(
			String(premium_summary.get("pcl_id", ""))
		)
		_check(
			int((premium_pokemon.get("instanceStats", {}) as Dictionary).get("level", 0))
			== StretchGoalSystem.PURCHASED_POKEMON_MAX_LEVEL,
			"A premium direct purchase should actually arrive at the Lv. 20 cap."
		)

	var loot_collection_before := CollectionSystem.get_collection_size()
	var loot_balance_before := StretchGoalSystem.get_balance()
	var loot_purchase := StretchGoalSystem.buy_loot_box("scuffed-parcel")
	_check(bool(loot_purchase.get("ok", false)), "A funded player should be able to buy a loot box.")
	_check(
		StretchGoalSystem.get_balance() == loot_balance_before - 400,
		"Buying the first loot-box tier should deduct its $400 price."
	)
	_check(
		CollectionSystem.get_collection_size() == loot_collection_before + 1,
		"A loot-box result should be committed to Pokemon storage before presentation."
	)
	if bool(loot_purchase.get("ok", false)):
		var loot_summary := loot_purchase.get("summary", {}) as Dictionary
		var loot_pokemon := CollectionSystem.get_pcl(String(loot_summary.get("pcl_id", "")))
		_check(
			not bool((loot_pokemon.get("party", {}) as Dictionary).get("inParty", true))
			and loot_pokemon.get("party", {}).get("slot") == null,
			"Loot-box Pokemon should arrive in PC storage, not the party."
		)
		var reel := StretchGoalSystem.build_loot_box_reel(
			"scuffed-parcel",
			int(loot_summary.get("pokemon_id", 0))
		)
		_check(reel.size() == 31, "A loot-box result should build a full spinning reel.")
		_check(
			reel.size() > 26 and reel[26] == int(loot_summary.get("pokemon_id", 0)),
			"The committed prize should occupy the reel's middle-knob stop."
		)
	_check(
		is_equal_approx(StretchGoalSystem.LOOT_BOX_HIGH_QUALITY_CHANCE, 0.10),
		"Every loot-box tier should share the same 10% high-quality hit rate."
	)

	_check(StretchGoalSystem.get_destinations("gym").size() == 8, "Stretchman should offer Gyms 1 through 8.")
	var routes := StretchGoalSystem.get_destinations("route")
	_check(routes.size() == 40, "Stretchman should offer Route 0 through Route 39.")
	_check(StretchGoalSystem.get_destinations("champion").size() == 1, "Stretchman should offer one champion gauntlet.")
	var biome_ids: Dictionary = {}
	var previous_length := 0
	for route_index in routes.size():
		var route := routes[route_index]
		_check(
			int(route.get("index", -1)) == route_index,
			"The route catalog should stay in uninterrupted Route 0–39 order."
		)
		biome_ids[String(route.get("biome_id", ""))] = true
		var route_length := int(route.get("world_length", 0))
		_check(
			route_length >= previous_length,
			"Route dungeon size should never shrink as difficulty rises."
		)
		previous_length = route_length
	_check(biome_ids.size() == 20, "The 40 routes should span 20 distinct biome families.")
	for level_band in 10:
		var first_route := routes[level_band * 4]
		for route_offset in range(1, 4):
			var companion_route := routes[level_band * 4 + route_offset]
			_check(
				int(companion_route.get("level_min", -1))
				== int(first_route.get("level_min", -2))
				and int(companion_route.get("level_max", -1))
				== int(first_route.get("level_max", -2)),
				"Every difficulty band should contain four routes with the same level range."
			)
	_check(
		String(routes[0].get("scene_path", ""))
		== "res://overworld/route_0/route_0.tscn"
		and not bool(routes[0].get("generated", true)),
		"Route 0 should be the renamed authored modular meadow."
	)
	_check(
		int(routes[39].get("world_length", 0)) > int(routes[1].get("world_length", 0))
		and int(routes[39].get("trainer_count", 0))
		> int(routes[1].get("trainer_count", 0)),
		"Late routes should be longer and contain more mandatory trainers."
	)
	_check(
		StretchGoalSystem.is_route_unlocked(0)
		and not StretchGoalSystem.is_route_unlocked(1),
		"Only Route 0 should be available in a fresh route progression."
	)
	_check(
		StretchGoalSystem.begin_destination("route", 1).is_empty(),
		"A player should not be able to start Route 1 before reaching Route 0's end."
	)
	var route_zero_clear := StretchGoalSystem.complete_route_at_end(0)
	_check(
		bool(route_zero_clear.get("ok", false))
		and StretchGoalSystem.is_route_completed(0)
		and StretchGoalSystem.is_route_unlocked(1),
		"Touching Route 0's far-end goal should complete it and unlock Route 1."
	)

	StretchGoalSystem.begin_destination("champion", 1)
	var champion_encounters := StretchGoalSystem.get_active_encounters()
	_check(champion_encounters.size() == 5, "The champion run should contain Elite Four 1–4 plus the Champion.")
	var minimum_level := 100
	var maximum_level := 0
	for encounter in champion_encounters:
		for member_value: Variant in encounter.get("members", []) as Array:
			var member := member_value as Dictionary
			minimum_level = mini(minimum_level, int(member.get("level", 0)))
			maximum_level = maxi(maximum_level, int(member.get("level", 0)))
	_check(minimum_level >= 60 and maximum_level >= 80 and maximum_level <= 89, "Elite Four and Champion Pokemon should span the requested 60s through 80s.")

	var prepared := champion_encounters[0]
	var provider := RNDStretchBattleEncounterProvider.new()
	_check(
		provider.configure_from_launch_data({"encounter_id": prepared["encounter_id"]}),
		"The dynamic battle provider should resolve the standard GameInstance launch ID."
	)
	_check(provider.encounter != null, "The dynamic battle provider should build an encounter resource.")
	if provider.encounter != null:
		_check(provider.encounter.validate().is_empty(), "The generated Elite Four encounter should pass battle validation.")
	provider.free()

	_check(
		not StretchGoalSystem.begin_destination("route", 1).is_empty(),
		"Route 1 should start after Route 0 is complete."
	)
	_check(
		not bool(StretchGoalSystem.complete_route_at_end(1).get("ok", false)),
		"A generated route's far-end goal should stay sealed until every trainer is defeated."
	)
	var early_route_encounter := StretchGoalSystem.get_active_encounters()[0]
	var balance_before_reward := StretchGoalSystem.get_balance()
	StretchGoalSystem._apply_battle_result(
		early_route_encounter,
		{"winner": "player", "reason": "all_pokemon_fainted"}
	)
	_check(
		StretchGoalSystem.get_balance() - balance_before_reward == 80,
		"The first generated-route trainer should use the beginning of the scaled reward curve."
	)
	var route_one_encounters := StretchGoalSystem.get_active_encounters()
	for encounter_index in range(1, route_one_encounters.size()):
		StretchGoalSystem._apply_battle_result(
			route_one_encounters[encounter_index],
			{"winner": "player", "reason": "all_pokemon_fainted"}
		)
	var route_one_clear := StretchGoalSystem.complete_route_at_end(1)
	_check(
		bool(route_one_clear.get("ok", false))
		and StretchGoalSystem.get_completed_routes() == [0, 1]
		and StretchGoalSystem.is_route_unlocked(2),
		"Clearing every Route 1 checkpoint and touching its end should unlock Route 2."
	)
	var route_progress_save := StretchGoalSystem.get_save_data()
	_check(
		StretchGoalSystem.load_save_data(route_progress_save)
		and StretchGoalSystem.get_completed_routes() == [0, 1]
		and StretchGoalSystem.is_route_unlocked(2),
		"Sequential route completion should survive save validation and reload."
	)
	var skipped_route_save := route_progress_save.duplicate(true)
	skipped_route_save["completed_routes"] = [0, 2]
	_check(
		not StretchGoalSystem.load_save_data(skipped_route_save),
		"Save validation should reject route progression that skips a required dungeon."
	)
	_check(
		StretchGoalSystem.load_save_data(route_progress_save),
		"The valid route fixture should reload after the rejected skip check."
	)

	var route_eight_fixture := StretchGoalSystem.get_save_data()
	route_eight_fixture["completed_routes"] = range(8)
	route_eight_fixture["active_destination"] = {}
	route_eight_fixture["run_defeated_ids"] = []
	_check(
		StretchGoalSystem.load_save_data(route_eight_fixture)
		and not StretchGoalSystem.begin_destination("route", 8).is_empty(),
		"A contiguous Route 0–7 clear should make Route 8 available."
	)
	var late_route_encounter := StretchGoalSystem.get_active_encounters()[0]
	balance_before_reward = StretchGoalSystem.get_balance()
	StretchGoalSystem._apply_battle_result(
		late_route_encounter,
		{"winner": "player", "reason": "all_pokemon_fainted"}
	)
	_check(
		StretchGoalSystem.get_balance() - balance_before_reward == 4_000,
		"A high-level route victory should pay about $4,000."
	)
	balance_before_reward = StretchGoalSystem.get_balance()
	StretchGoalSystem._apply_generic_battle_result(
		{"encounter_id": "existing-trainer", "trainer_name": "Existing Trainer"},
		{"winner": "player", "reason": "all_pokemon_fainted"}
	)
	_check(
		StretchGoalSystem.get_balance() - balance_before_reward == 20,
		"A completed battle outside a Stretchman destination should still award money."
	)

	StretchGoalSystem.begin_destination("gym", 1)
	var gym_encounter := StretchGoalSystem.get_active_encounters()[0]
	balance_before_reward = StretchGoalSystem.get_balance()
	StretchGoalSystem._apply_battle_result(
		gym_encounter,
		{"winner": "player", "reason": "all_pokemon_fainted"}
	)
	_check(StretchGoalSystem.get_balance() > balance_before_reward, "Winning a battle should grant money.")
	_check(StretchGoalSystem.has_badge(1), "Winning Gym 1 should mark its R&D badge earned.")

	var untouched_legacy := StretchGoalSystem.get_save_data()
	untouched_legacy.erase("economy_version")
	untouched_legacy["balance"] = StretchGoalSystem.LEGACY_STARTING_BALANCE
	untouched_legacy["item_inventory"] = {}
	untouched_legacy["claimed_gifts"] = []
	untouched_legacy["earned_badges"] = []
	untouched_legacy["champion_cleared"] = false
	untouched_legacy["completed_routes"] = []
	untouched_legacy["active_destination"] = {}
	untouched_legacy["run_defeated_ids"] = []
	untouched_legacy["last_battle_reward"] = {}
	_check(StretchGoalSystem.load_save_data(untouched_legacy), "An untouched legacy economy save should migrate safely.")
	_check(StretchGoalSystem.get_balance() == 50, "Untouched legacy starting cash should migrate down to $50.")

	CollectionSystem.load_save_data(original_collection)
	StretchGoalSystem.load_save_data(original_stretch)

	if _failures.is_empty():
		print(
			"Stretch goal system smoke test passed: complete catalogs, revised pricing, "
			+ "price-derived Lv. 5-20 direct purchases, loot boxes, generated encounters, "
			+ "40-route biome bands, sequential end-gate unlocks, scaled rewards, held-item "
			+ "transfers, unique gifts, and badges verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Stretch goal system smoke test failed: %s" % failure)
	get_tree().quit(1)


func _find_entry(entries: Array[Dictionary], field: String, expected: Variant) -> Dictionary:
	for entry in entries:
		if entry.get(field) == expected:
			return entry
	return {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
