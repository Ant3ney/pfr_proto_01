extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_check(
		CreatureSystem.get_pokemon_count() == 1351,
		"Expected all 1,351 Pokemon records."
	)
	_check(
		CreatureSystem.get_pokemon_count(false) == 1025,
		"Expected 1,025 default National-Dex Pokemon."
	)
	_check(CreatureSystem.has_pokemon(1), "Bulbasaur ID should exist.")
	_check(CreatureSystem.has_pokemon(10001), "Alternate-form ID should exist.")
	_check(not CreatureSystem.has_pokemon(0), "ID 0 should not exist.")

	var bulbasaur := CreatureSystem.get_creature(1)
	_check(not bulbasaur.is_empty(), "Bulbasaur should load from local data.")
	_check(int(bulbasaur.get("id", -1)) == 1, "Bulbasaur ID should be 1.")
	_check(bulbasaur.get("name") == "bulbasaur", "Bulbasaur name is incorrect.")
	_check(int(bulbasaur.get("height", -1)) == 7, "Bulbasaur height is incorrect.")
	_check(int(bulbasaur.get("weight", -1)) == 69, "Bulbasaur weight is incorrect.")
	_check_stat(bulbasaur, "hp", 45)
	_check_stat(bulbasaur, "attack", 49)
	_check_stat(bulbasaur, "speed", 45)
	_check_named_resource(bulbasaur, "types", "type", "grass")
	_check_named_resource(bulbasaur, "types", "type", "poison")
	_check_named_resource(bulbasaur, "moves", "move", "tackle")
	var encounters_value: Variant = bulbasaur.get("encounters_data")
	_check(
		typeof(encounters_value) == TYPE_ARRAY,
		"A full encounters_data array should be attached."
	)
	if typeof(encounters_value) == TYPE_ARRAY:
		_check(
			not encounters_value.is_empty(),
			"Bulbasaur should have local location-encounter records."
		)

	var species_value: Variant = bulbasaur.get("species_data")
	_check(
		typeof(species_value) == TYPE_DICTIONARY,
		"A full species_data object should be attached."
	)
	if typeof(species_value) == TYPE_DICTIONARY:
		var species: Dictionary = species_value
		_check(int(species.get("id", -1)) == 1, "Species ID should be 1.")
		_check(
			str(species.get("generation", {}).get("name", "")) == "generation-i",
			"Bulbasaur should have its species generation."
		)
		_check(
			not species.get("flavor_text_entries", []).is_empty(),
			"Bulbasaur should have local Pokedex flavor text."
		)

	var evolution_value: Variant = bulbasaur.get("evolution_chain_data")
	_check(
		typeof(evolution_value) == TYPE_DICTIONARY,
		"A full evolution_chain_data object should be attached."
	)
	if typeof(evolution_value) == TYPE_DICTIONARY:
		var evolution_chain: Dictionary = evolution_value
		_check(
			int(evolution_chain.get("id", -1)) == 1,
			"Bulbasaur evolution-chain ID should be 1."
		)
		_check(
			str(
				evolution_chain.get("chain", {}).get("species", {}).get("name", "")
			) == "bulbasaur",
			"Bulbasaur should be the root of its evolution chain."
		)

	var deoxys_attack := CreatureSystem.get_creature(10001)
	_check(
		deoxys_attack.get("name") == "deoxys-attack",
		"Alternate-form data should load by numeric ID."
	)
	_check(
		deoxys_attack.get("species_data", {}).get("name") == "deoxys",
		"Alternate forms should resolve their shared species record."
	)
	_check(
		CreatureSystem.get_pokemon_id("Deoxys Attack") == 10001,
		"Normalized name lookup should resolve an alternate form."
	)

	bulbasaur["name"] = "mutated"
	bulbasaur["species_data"]["name"] = "mutated-species"
	var fresh_bulbasaur := CreatureSystem.get_pokemon(1)
	_check(
		fresh_bulbasaur.get("name") == "bulbasaur",
		"Caller mutation should not alter cached Pokemon data."
	)
	_check(
		fresh_bulbasaur.get("species_data", {}).get("name") == "bulbasaur",
		"Caller mutation should not alter cached species data."
	)

	_check(
		CreatureSystem.get_creature(999999).is_empty(),
		"An unknown ID should return an empty dictionary."
	)
	_check(
		CreatureSystem.get_last_error().contains("999999"),
		"An unknown ID should expose a useful lookup error."
	)

	if _failures.is_empty():
		print(
			"Creature System smoke test passed: 1,351 local Pokemon records, "
			+ "encounters/species/evolution enrichment, forms, and cache "
			+ "isolation verified."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Creature System smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _check_stat(creature: Dictionary, stat_name: String, expected: int) -> void:
	var stats_value: Variant = creature.get("stats")
	if typeof(stats_value) != TYPE_ARRAY:
		_check(false, "Creature stats should be an array.")
		return
	for stat_value: Variant in stats_value:
		if typeof(stat_value) != TYPE_DICTIONARY:
			continue
		var stat: Dictionary = stat_value
		if stat.get("stat", {}).get("name") != stat_name:
			continue
		_check(
			int(stat.get("base_stat", -1)) == expected,
			"%s should be %d." % [stat_name, expected]
		)
		return
	_check(false, "Missing stat: %s" % stat_name)


func _check_named_resource(
	creature: Dictionary,
	list_field: String,
	resource_field: String,
	expected_name: String
) -> void:
	var values: Variant = creature.get(list_field)
	if typeof(values) != TYPE_ARRAY:
		_check(false, "%s should be an array." % list_field)
		return
	for value: Variant in values:
		if (
			typeof(value) == TYPE_DICTIONARY
			and value.get(resource_field, {}).get("name") == expected_name
		):
			return
	_check(false, "Missing %s entry: %s" % [list_field, expected_name])
