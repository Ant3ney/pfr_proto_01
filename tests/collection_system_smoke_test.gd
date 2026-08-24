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

	CollectionSystem.clear_collection()

	var pikachu := CollectionSystem.add_pokemon(25, 5, 0.4, 0.3, 3)
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
		is_equal_approx(pikachu.get("instanceStats", {}).get("xp", -1.0), 0.3),
		"Pikachu XP percentage should be stored."
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
			{"health": 0.2, "xp": 0.75, "level": 6}
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
		not CollectionSystem.update_instance_stats(
			pikachu_pcl_id,
			{"health": 1.5}
		),
		"Out-of-range percentages should be rejected."
	)
	_check(
		not CollectionSystem.update_instance_stats(
			pikachu_pcl_id,
			{"xp": "half"}
		),
		"Non-numeric instance stats should be rejected."
	)

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
			"Collection System smoke test passed: PCL shape, unique IDs, "
			+ "party lookups, stats, safe copies, and atomic JSON save loading verified."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Collection System smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
