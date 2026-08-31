extends Node

var _failures: Array[String] = []


func _ready() -> void:
	var expected_starting_party: Array[int] = [484, 414, 163, 416, 405, 279]
	var starting_party := CollectionSystem.get_party()
	_check(
		CollectionSystem.get_collection_size() == expected_starting_party.size(),
		"A fresh collection should contain all six starting Pokemon."
	)
	_check(
		starting_party.size() == expected_starting_party.size(),
		"All six starting Pokemon should be in the party."
	)
	for party_index in min(starting_party.size(), expected_starting_party.size()):
		var starter := starting_party[party_index]
		_check(
			starter.get("pokemonId") == expected_starting_party[party_index],
			"Starting party slot %d should contain Pokemon ID %d."
			% [party_index + 1, expected_starting_party[party_index]]
		)
		_check(
			starter.get("party", {}).get("slot") == party_index + 1,
			"A starting Pokemon should report its assigned party slot."
		)
		_check(
			starter.get("instanceStats", {}).get("level") == 3,
			"Each starting Pokemon should be level 3."
		)
		_check(
			int(starter.get("instanceStats", {}).get("currentXp", -1))
			== CreatureSystem.get_experience_for_level(expected_starting_party[party_index], 3),
			"Each starter should begin at its exact level-3 cumulative XP threshold."
		)

	CollectionSystem.clear_collection()

	var pikachu_start_xp := CreatureSystem.get_experience_for_level(25, 5) + 27
	var pikachu := CollectionSystem.add_pokemon(25, 5, 0.4, pikachu_start_xp, 3)
	_check(not pikachu.is_empty(), "Pikachu PCL should be created.")
	_check(pikachu.get("pokemonId") == 25, "PCL should store its Pokemon ID.")
	_check(not str(pikachu.get("pclID", "")).is_empty(), "PCL ID should be generated.")
	_check(pikachu.get("party", {}).get("inParty"), "Pikachu should be in the party.")
	_check(pikachu.get("party", {}).get("slot") == 3, "Pikachu should occupy slot 3.")
	_check(
		is_equal_approx(pikachu.get("instanceStats", {}).get("health", -1.0), 0.4),
		"Pikachu health percentage should be stored."
	)
	_check(
		int(pikachu.get("instanceStats", {}).get("currentXp", -1)) == pikachu_start_xp,
		"Pikachu cumulative current XP should be stored."
	)
	_check(
		pikachu.get("instanceStats", {}).get("level") == 5,
		"Pikachu level should be stored."
	)

	var pikachu_pcl_id := str(pikachu["pclID"])
	var slot_three := CollectionSystem.get_pcl_by_party_slot(3)
	_check(
		slot_three.get("pclID") == pikachu_pcl_id,
		"Party slot lookup should return the expected PCL."
	)

	var bulbasaur := CollectionSystem.add_pokemon(1, 7)
	var bulbasaur_pcl_id := str(bulbasaur.get("pclID", ""))
	_check(not bulbasaur_pcl_id.is_empty(), "Bulbasaur PCL should be created.")
	_check(
		bulbasaur.get("party", {}).get("inParty") == false,
		"A zero party slot should leave a PCL in storage."
	)
	_check(
		bulbasaur.get("party", {}).get("slot") == null,
		"A stored PCL should have a null party slot."
	)
	_check(
		pikachu_pcl_id != bulbasaur_pcl_id,
		"Every captured Pokemon should receive a unique PCL ID."
	)
	_check(
		CollectionSystem.get_evolution_options(bulbasaur_pcl_id).is_empty()
		and CollectionSystem.evolve_pokemon(bulbasaur_pcl_id, 2).is_empty()
		and int(CollectionSystem.get_pcl(bulbasaur_pcl_id).get("pokemonId", 0)) == 1,
		"A Pokemon below its evolution level should remain unchanged."
	)

	_check(
		not CollectionSystem.set_party_slot(bulbasaur_pcl_id, 3),
		"An occupied party slot should be rejected."
	)
	_check(
		CollectionSystem.get_last_error().contains("occupied"),
		"Occupied-slot rejection should explain the failure."
	)
	_check(
		CollectionSystem.set_party_slot(bulbasaur_pcl_id, 1),
		"Bulbasaur should move into a free party slot."
	)
	var squirtle := CollectionSystem.add_pokemon(7, 7)
	var squirtle_pcl_id := String(squirtle.get("pclID", ""))
	_check(
		CollectionSystem.move_to_party_slot(squirtle_pcl_id, 1),
		"A stored Pokemon should atomically replace an occupied party member."
	)
	_check(
		CollectionSystem.get_pcl_by_party_slot(1).get("pclID") == squirtle_pcl_id
		and not bool(CollectionSystem.get_pcl(bulbasaur_pcl_id).get("party", {}).get("inParty", true)),
		"Replacing a full slot should send its former member to storage."
	)
	_check(
		CollectionSystem.move_to_party_slot(bulbasaur_pcl_id, 1),
		"A stored Pokemon should be able to restore the occupied slot."
	)
	_check(
		CollectionSystem.move_to_party_slot(bulbasaur_pcl_id, 3),
		"Moving a party member onto another occupied slot should swap them."
	)
	_check(
		CollectionSystem.get_pcl_by_party_slot(1).get("pclID") == pikachu_pcl_id
		and CollectionSystem.get_pcl_by_party_slot(3).get("pclID") == bulbasaur_pcl_id,
		"An occupied party-to-party move should preserve both members by swapping slots."
	)
	_check(
		CollectionSystem.move_to_party_slot(bulbasaur_pcl_id, 1),
		"The party swap should be reversible."
	)
	_check(CollectionSystem.remove_pcl(squirtle_pcl_id), "The storage swap fixture should clean up.")

	var party := CollectionSystem.get_party()
	_check(party.size() == 2, "Party should contain two PCLs.")
	if party.size() == 2:
		_check(
			party[0].get("pclID") == bulbasaur_pcl_id,
			"Party results should be ordered by slot."
		)
		_check(
			party[1].get("pclID") == pikachu_pcl_id,
			"Party slot ordering should preserve gaps."
		)

	_check(
		CollectionSystem.update_instance_stats(
			pikachu_pcl_id,
			{"health": 0.2, "currentXp": 300, "level": 6}
		),
		"Valid instance-stat changes should apply."
	)
	var updated_pikachu := CollectionSystem.get_pcl(pikachu_pcl_id)
	_check(
		is_equal_approx(updated_pikachu["instanceStats"]["health"], 0.2),
		"Updated health should be returned."
	)
	_check(
		updated_pikachu["instanceStats"]["level"] == 6,
		"Updated level should be returned."
	)
	_check(
		updated_pikachu["instanceStats"]["currentXp"] == 300,
		"Updated cumulative XP should be returned."
	)
	_check(
		not CollectionSystem.update_instance_stats(
			pikachu_pcl_id,
			{"health": 1.5}
		),
		"Out-of-range percentages should be rejected."
	)
	_check(
		not CollectionSystem.update_instance_stats(
			pikachu_pcl_id,
			{"currentXp": "half"}
		),
		"Non-numeric instance stats should be rejected."
	)
	_check(
		not CollectionSystem.update_instance_stats(
			pikachu_pcl_id,
			{"currentXp": 300, "level": 7}
		),
		"A level that disagrees with cumulative XP should be rejected."
	)

	var xp_before_award := int(CollectionSystem.get_pcl(pikachu_pcl_id)["instanceStats"]["currentXp"])
	var award_result := CollectionSystem.grant_experience(pikachu_pcl_id, 1000)
	_check(not award_result.is_empty(), "Direct cumulative XP awards should apply.")
	_check(
		int(CollectionSystem.get_pcl(pikachu_pcl_id)["instanceStats"]["currentXp"])
		== xp_before_award + 1000,
		"An XP award should persist its exact applied amount."
	)
	_check(
		int(award_result.get("level", 0)) > 6 and bool(award_result.get("leveledUp", false)),
		"A large XP award should cross multiple level thresholds atomically."
	)

	var high_level_bulbasaur := CollectionSystem.add_pokemon(1, 32, 0.65)
	var high_level_bulbasaur_id := String(high_level_bulbasaur.get("pclID", ""))
	var high_level_options := CollectionSystem.get_evolution_options(high_level_bulbasaur_id)
	_check(
		high_level_options.size() == 1
		and int(high_level_options[0].get("pokemonId", 0)) == 2,
		"A Pokemon obtained above its threshold should immediately expose its direct evolution."
	)
	_check(
		CollectionSystem.evolve_pokemon(high_level_bulbasaur_id, 3).is_empty()
		and int(CollectionSystem.get_pcl(high_level_bulbasaur_id).get("pokemonId", 0)) == 1,
		"Evolution should reject a non-direct target without changing the PCL."
	)
	var original_high_level_moves: Array = (
		(high_level_bulbasaur.get("battleProfile", {}) as Dictionary).get("moves", []) as Array
	).duplicate()
	var ivysaur_result := CollectionSystem.evolve_pokemon(high_level_bulbasaur_id, 2)
	var evolved_ivysaur := CollectionSystem.get_pcl(high_level_bulbasaur_id)
	_check(
		int(ivysaur_result.get("previousPokemonId", 0)) == 1
		and int(ivysaur_result.get("pokemonId", 0)) == 2
		and String(evolved_ivysaur.get("pclID", "")) == high_level_bulbasaur_id
		and int((evolved_ivysaur.get("instanceStats", {}) as Dictionary).get("level", 0)) == 32
		and is_equal_approx(
			float((evolved_ivysaur.get("instanceStats", {}) as Dictionary).get("health", 0.0)),
			0.65
		),
		"Evolution should preserve instance identity, level, health, and report both species IDs."
	)
	var ivysaur_profile := evolved_ivysaur.get("battleProfile", {}) as Dictionary
	_check(
		String(ivysaur_profile.get("species", "")) == "Ivysaur"
		and (ivysaur_profile.get("moves", []) as Array) == original_high_level_moves,
		"Evolution should update battle presentation metadata without replacing equipped moves."
	)
	_check(
		CollectionSystem.get_evolution_options(high_level_bulbasaur_id).size() == 1
		and not CollectionSystem.evolve_pokemon(high_level_bulbasaur_id, 3).is_empty()
		and int(CollectionSystem.get_pcl(high_level_bulbasaur_id).get("pokemonId", 0)) == 3,
		"A high-level PCL should be able to evolve through each direct stage in order."
	)
	_check(
		CollectionSystem.get_evolution_options(high_level_bulbasaur_id).is_empty(),
		"A final evolution should no longer expose an evolution action."
	)

	var eevee := CollectionSystem.add_pokemon(133, 20)
	var eevee_pcl_id := String(eevee.get("pclID", ""))
	_check(
		CollectionSystem.get_evolution_options(eevee_pcl_id).size() == 8,
		"A branching Pokemon should return every eligible choice."
	)
	_check(
		not CollectionSystem.evolve_pokemon(eevee_pcl_id, 134).is_empty()
		and int(CollectionSystem.get_pcl(eevee_pcl_id).get("pokemonId", 0)) == 134,
		"Selecting one branch should evolve the same captured instance into that target."
	)
	var caterpie := CollectionSystem.add_pokemon(10, 6)
	var caterpie_pcl_id := String(caterpie.get("pclID", ""))
	var caterpie_level_award := CollectionSystem.grant_experience(
		caterpie_pcl_id,
		CreatureSystem.get_experience_for_level(10, 7)
		- CreatureSystem.get_experience_for_level(10, 6)
	)
	var caterpie_evolution_options := caterpie_level_award.get("evolutionOptions", []) as Array
	_check(
		bool(caterpie_level_award.get("leveledUp", false))
		and bool(caterpie_level_award.get("evolutionAvailable", false))
		and caterpie_evolution_options.size() == 1
		and int(caterpie_evolution_options[0].get("pokemonId", 0)) == 11,
		"A threshold-crossing XP result should report the newly available evolution."
	)
	_check(CollectionSystem.remove_pcl(caterpie_pcl_id), "The XP evolution-notice fixture should clean up.")
	var evolved_save := CollectionSystem.get_save_data()
	_check(
		CollectionSystem.load_save_data(evolved_save)
		and int(CollectionSystem.get_pcl(high_level_bulbasaur_id).get("pokemonId", 0)) == 3
		and int(CollectionSystem.get_pcl(eevee_pcl_id).get("pokemonId", 0)) == 134,
		"Evolved species and their reconciled profiles should survive save validation."
	)
	_check(CollectionSystem.remove_pcl(high_level_bulbasaur_id), "The staged evolution fixture should clean up.")
	_check(CollectionSystem.remove_pcl(eevee_pcl_id), "The branching evolution fixture should clean up.")

	updated_pikachu["pokemonId"] = 999
	updated_pikachu["instanceStats"]["health"] = 0.0
	var protected_pikachu := CollectionSystem.get_pcl(pikachu_pcl_id)
	_check(
		protected_pikachu["pokemonId"] == 25,
		"Caller mutation should not change the stored Pokemon ID."
	)
	_check(
		is_equal_approx(protected_pikachu["instanceStats"]["health"], 0.2),
		"Caller mutation should not change stored instance stats."
	)

	_check(
		CollectionSystem.add_pokemon(999999).is_empty(),
		"Unknown Pokemon IDs should be rejected."
	)
	_check(CollectionSystem.get_collection_size() == 2, "Collection size should remain 2.")

	var save_data := CollectionSystem.get_save_data()
	var serialized_save := JSON.stringify(save_data)
	var parsed_save: Variant = JSON.parse_string(serialized_save)
	_check(
		typeof(parsed_save) == TYPE_ARRAY,
		"Collection save data should survive JSON serialization."
	)
	CollectionSystem.clear_collection()
	_check(CollectionSystem.get_collection_size() == 0, "Clear should empty the collection.")
	if typeof(parsed_save) == TYPE_ARRAY:
		_check(CollectionSystem.load_save_data(parsed_save), "Valid save data should reload.")
	_check(
		CollectionSystem.get_pcl_by_party_slot(3).get("pclID") == pikachu_pcl_id,
		"Save loading should restore party slot 3."
	)

	var legacy_save: Array = save_data.duplicate(true)
	legacy_save[0]["instanceStats"].erase("currentXp")
	legacy_save[0]["instanceStats"]["xp"] = 0.5
	var legacy_level := int(legacy_save[0]["instanceStats"]["level"])
	var legacy_pokemon_id := int(legacy_save[0]["pokemonId"])
	var expected_legacy_xp := CreatureSystem.get_experience_for_level(
		legacy_pokemon_id,
		legacy_level
	) + int(round(
		0.5 * float(CreatureSystem.get_experience_to_next_level(legacy_pokemon_id, legacy_level))
	))
	_check(CollectionSystem.load_save_data(legacy_save), "Legacy normalized XP should migrate once.")
	var migrated := CollectionSystem.get_pcl(String(legacy_save[0]["pclID"]))
	_check(
		int(migrated["instanceStats"].get("currentXp", -1)) == expected_legacy_xp
		and not migrated["instanceStats"].has("xp"),
		"Legacy XP migration should persist only canonical currentXp."
	)
	_check(CollectionSystem.load_save_data(save_data), "Canonical save data should restore after migration test.")

	var invalid_save: Array = save_data.duplicate(true)
	invalid_save[1]["party"]["inParty"] = true
	invalid_save[1]["party"]["slot"] = 3
	_check(
		not CollectionSystem.load_save_data(invalid_save),
		"Save data with duplicate party slots should be rejected."
	)
	_check(
		CollectionSystem.get_collection_size() == 2,
		"Rejected save data should leave the collection untouched."
	)
	_check(
		CollectionSystem.get_pcl_by_party_slot(1).get("pclID") == bulbasaur_pcl_id,
		"Rejected save data should leave existing party assignments untouched."
	)

	_check(CollectionSystem.remove_pcl(pikachu_pcl_id), "PCL removal should succeed.")
	_check(
		CollectionSystem.get_pcl_by_party_slot(3).is_empty(),
		"Removing a PCL should free its party slot."
	)
	CollectionSystem.clear_collection()

	if _failures.is_empty():
		print(
			"Collection System smoke test passed: cumulative XP migration, leveled and "
			+ "branching evolutions, party lookups, safe copies, and atomic save loading verified."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Collection System smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
