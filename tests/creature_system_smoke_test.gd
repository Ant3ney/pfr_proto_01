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
	var experience_data := bulbasaur.get("experience_data", {}) as Dictionary
	_check(
		String(experience_data.get("growth_rate", "")) == "medium-slow",
		"Bulbasaur should expose its PokeAPI growth rate."
	)
	_check(
		is_equal_approx(float(bulbasaur.get("xp_multiplier", 0.0)), 0.75),
		"Bulbasaur should expose its pinned community-tier XP multiplier."
	)
	var bulbasaur_curve: PackedInt32Array = experience_data.get(
		"experience_by_level",
		PackedInt32Array()
	)
	_check(bulbasaur_curve.size() == 101, "A growth curve should be indexed from 0 through 100.")
	if bulbasaur_curve.size() == 101:
		_check(bulbasaur_curve[1] == 0, "Level 1 should require zero cumulative XP.")
		_check(bulbasaur_curve[100] == 1059860, "Medium-slow level 100 XP should match PokeAPI.")
	_check(
		CreatureSystem.get_experience_for_level(1, 50) == 117360,
		"The Pokédex API should return exact cumulative XP by Pokemon and level."
	)
	_check(
		CreatureSystem.get_experience_to_next_level(1, 50)
		== CreatureSystem.get_experience_for_level(1, 51) - 117360,
		"The Pokédex API should return exact next-level XP deltas."
	)
	var growth_table := CreatureSystem.get_experience_growth_table()
	var growth_names := CreatureSystem.get_experience_growth_rate_names()
	var expected_level_100 := [1250000, 1000000, 800000, 1059860, 600000, 1640000]
	_check(growth_table.size() == 6, "The compact experience table should contain six growth rows.")
	for row_index in mini(growth_table.size(), expected_level_100.size()):
		_check(
			growth_table[row_index].size() == 101
			and growth_table[row_index][100] == expected_level_100[row_index],
			"Growth row %d should match its canonical level-100 threshold." % row_index
		)
	_check(growth_names.size() == 6, "Every growth row should have a stable name.")
	var palkia_profile := CreatureSystem.get_experience_profile(484)
	var wooper_profile := CreatureSystem.get_experience_profile(194)
	_check(
		String(palkia_profile.get("communityTier", "")) == "Uber"
		and String(wooper_profile.get("communityTier", "")) == "LC"
		and float(palkia_profile.get("xpMultiplier", 0.0))
		> float(wooper_profile.get("xpMultiplier", 0.0)),
		"A community-ranked legendary should yield more XP than an LC species."
	)
	for pokemon_id in CreatureSystem.get_pokemon_ids():
		var profile := CreatureSystem.get_experience_profile(pokemon_id)
		_check(
			not profile.is_empty() and float(profile.get("xpMultiplier", 0.0)) > 0.0,
			"Every local Pokemon ID should have a growth row and XP multiplier."
		)
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
	var bulbasaur_evolutions := CreatureSystem.get_evolution_options(1)
	_check(
		bulbasaur_evolutions.size() == 1
		and int(bulbasaur_evolutions[0].get("pokemonId", 0)) == 2
		and int(bulbasaur_evolutions[0].get("requiredLevel", 0)) == 16
		and int(bulbasaur_evolutions[0].get("stage", 0)) == 1,
		"Bulbasaur should expose Ivysaur as its level-16 first evolution."
	)
	_check(
		CreatureSystem.get_available_evolutions(1, 15).is_empty()
		and CreatureSystem.get_available_evolutions(1, 16).size() == 1,
		"An evolution should become available at, but not below, its level requirement."
	)
	var ivysaur_evolutions := CreatureSystem.get_evolution_options(2)
	_check(
		ivysaur_evolutions.size() == 1
		and int(ivysaur_evolutions[0].get("pokemonId", 0)) == 3
		and int(ivysaur_evolutions[0].get("requiredLevel", 0)) == 32
		and int(ivysaur_evolutions[0].get("stage", 0)) == 2,
		"Ivysaur should expose Venusaur as its level-32 second evolution."
	)
	var eevee_evolutions := CreatureSystem.get_evolution_options(133)
	_check(
		eevee_evolutions.size() == 8
		and CreatureSystem.get_available_evolutions(133, 19).is_empty()
		and CreatureSystem.get_available_evolutions(133, 20).size() == 8,
		"Every Eevee branch should use the first-stage fallback level and become a choice."
	)
	var kirlia_evolutions := CreatureSystem.get_evolution_options(281)
	var kirlia_requirements: Dictionary = {}
	for option in kirlia_evolutions:
		kirlia_requirements[int(option.get("pokemonId", 0))] = int(
			option.get("requiredLevel", 0)
		)
	_check(
		int(kirlia_requirements.get(282, 0)) == 30
		and int(kirlia_requirements.get(475, 0)) == 30,
		"A branch without an official level should inherit its sibling's authored level."
	)
	var evolution_edge_count := 0
	for pokemon_id in CreatureSystem.get_pokemon_ids(false):
		for option in CreatureSystem.get_evolution_options(pokemon_id):
			evolution_edge_count += 1
			_check(
				int(option.get("pokemonId", 0)) > 0
				and int(option.get("requiredLevel", 0)) in range(1, 101)
				and int(option.get("stage", 0)) in [1, 2],
				"Every direct evolution should have a valid target, stage, and level."
			)
	_check(
		evolution_edge_count == 484,
		"All 484 direct evolution edges in the local snapshot should receive levels."
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
			+ "leveled evolution stages, canonical growth tables, community XP multipliers, forms, and "
			+ "cache isolation verified."
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
