extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	var working_stretch := original_stretch.duplicate(true)
	working_stretch["balance"] = 8_000_000_000
	_check(
		StretchGoalSystem.load_save_data(working_stretch),
		"The smoke fixture should be able to load a high R&D balance."
	)

	var items := StretchGoalSystem.get_item_catalog()
	var pokemon := StretchGoalSystem.get_pokemon_catalog()
	_check(StretchGoalSystem.STARTING_BALANCE == 500, "A fresh Stretchman economy should start with exactly $500.")
	_check(items.size() == 2223, "The item shop should expose all 2,223 pinned PokeAPI items.")
	_check(pokemon.size() == 1025, "The Pokemon shop should expose all 1,025 default species forms.")
	_check(_find_entry(items, "slug", "potion").get("name") == "Potion", "The full item catalog should include Potion.")
	_check(int(_find_entry(items, "slug", "potion").get("price", 0)) == 20, "A basic Potion should fit the low-cash economy.")
	_check(_find_entry(items, "slug", "master-ball").get("price", 0) >= 1_000_000, "Master Ball pricing should retain a collector premium.")

	var caterpie := _find_entry(pokemon, "id", 10)
	var lucario := _find_entry(pokemon, "id", 448)
	var mewtwo := _find_entry(pokemon, "id", 150)
	_check(not caterpie.is_empty() and not mewtwo.is_empty(), "Known Pokemon should be present in the generated catalog.")
	_check(int(caterpie.get("price", 0)) == 200, "A deliberately ordinary Pokemon should cost about $200.")
	_check(int(lucario.get("price", 0)) > int(caterpie.get("price", 0)), "A curated cool-looking Pokemon should receive a larger markup.")
	_check(int(mewtwo.get("price", 0)) >= 2_000_000_000, "Legendary Pokemon should retain their extreme price premium.")
	var loot_boxes := StretchGoalSystem.get_loot_box_catalog()
	_check(loot_boxes.size() >= 6, "Stretchman should offer many increasingly expensive loot-box tiers.")
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

	var collection_size_before := CollectionSystem.get_collection_size()
	var pokemon_purchase := StretchGoalSystem.buy_pokemon(10)
	_check(bool(pokemon_purchase.get("ok", false)), "A funded player should be able to buy a Pokemon.")
	_check(CollectionSystem.get_collection_size() == collection_size_before + 1, "Pokemon purchases should enter CollectionSystem storage.")
	if bool(pokemon_purchase.get("ok", false)):
		var summary := pokemon_purchase.get("summary", {}) as Dictionary
		var purchased := CollectionSystem.get_pcl(String(summary.get("pcl_id", "")))
		_check(
			int((purchased.get("instanceStats", {}) as Dictionary).get("level", 0))
			== StretchGoalSystem.PURCHASED_POKEMON_LEVEL,
			"Purchased Pokemon should use the advertised delivery level."
		)
		_check(
			not bool((purchased.get("party", {}) as Dictionary).get("inParty", true))
			and purchased.get("party", {}).get("slot") == null,
			"Pokemon bought from Stretchman should arrive in PC storage, not the party."
		)

	var loot_collection_before := CollectionSystem.get_collection_size()
	var loot_balance_before := StretchGoalSystem.get_balance()
	var loot_purchase := StretchGoalSystem.buy_loot_box("scuffed-parcel")
	_check(bool(loot_purchase.get("ok", false)), "A funded player should be able to buy a loot box.")
	_check(
		StretchGoalSystem.get_balance() == loot_balance_before - 100,
		"Buying the first loot-box tier should deduct its $100 price."
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
	_check(StretchGoalSystem.get_destinations("route").size() == 8, "Stretchman should offer eight outdoor route runs.")
	_check(StretchGoalSystem.get_destinations("champion").size() == 1, "Stretchman should offer one champion gauntlet.")

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

	StretchGoalSystem.begin_destination("route", 1)
	var early_route_encounter := StretchGoalSystem.get_active_encounters()[0]
	var balance_before_reward := StretchGoalSystem.get_balance()
	StretchGoalSystem._apply_battle_result(
		early_route_encounter,
		{"winner": "player", "reason": "all_pokemon_fainted"}
	)
	_check(
		StretchGoalSystem.get_balance() - balance_before_reward == 20,
		"A beginner-route victory should pay about $20."
	)

	StretchGoalSystem.begin_destination("route", 8)
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
	untouched_legacy["earned_badges"] = []
	untouched_legacy["champion_cleared"] = false
	untouched_legacy["last_battle_reward"] = {}
	_check(StretchGoalSystem.load_save_data(untouched_legacy), "An untouched legacy economy save should migrate safely.")
	_check(StretchGoalSystem.get_balance() == 500, "Untouched legacy starting cash should migrate down to $500.")

	CollectionSystem.load_save_data(original_collection)
	StretchGoalSystem.load_save_data(original_stretch)

	if _failures.is_empty():
		print(
			"Stretch goal system smoke test passed: complete catalogs, revised pricing, "
			+ "purchases, loot boxes, generated encounters, scaled rewards, and badges verified."
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
