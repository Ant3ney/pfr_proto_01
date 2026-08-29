extends Node

const SpeciesMapping := preload("res://battle/system/BattleSpeciesMapping.gd")
const EncounterDefinition := preload("res://battle/data/BattleEncounterDefinition.gd")
const EncounterMember := preload("res://battle/data/BattleEncounterMember.gd")
const KYLE_ENCOUNTER_PATH := "res://battle/encounters/trainer_kyle_lake_v1.tres"
const KYLE_SCENE_PATH := "res://battle/kyle_battle_scene.tscn"

var _failures: Array[String] = []
var _collection_change_count := 0


func _ready() -> void:
	_test_generated_species_mapping()
	_test_starting_profiles_and_server_party()
	_test_profile_migration_and_move_persistence()
	_test_unsupported_forms_and_all_fainted_preflight()
	_test_atomic_health_snapshot()
	_test_kyle_encounter_resource_and_provider_scene()

	CollectionSystem.clear_collection()
	if _failures.is_empty():
		print(
			"Battle data smoke test passed: generated mapping, collection battle "
			+ "profiles, atomic HP writeback, and Kyle encounter verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Battle data smoke test failed: %s" % failure)
	get_tree().quit(1)


func _test_generated_species_mapping() -> void:
	_check(SpeciesMapping.get_source_pokemon_count() == 1351, "Mapping should cover the PokeAPI index.")
	_check(SpeciesMapping.get_supported_count() == 1335, "Generated supported mapping count should remain stable.")
	var missing_default_ids: Array[int] = []
	for pokemon_id in range(1, 1026):
		if not SpeciesMapping.has_mapping(pokemon_id):
			missing_default_ids.append(pokemon_id)
	_check(
		missing_default_ids.is_empty(),
		"Every default National-Dex Pokemon should be mapped; missing %s."
		% str(missing_default_ids)
	)
	var palkia_mapping: Dictionary = SpeciesMapping.get_entry(484)
	_check(palkia_mapping.get("species") == "Palkia", "Palkia should use its canonical Showdown species.")
	_check(palkia_mapping.get("spriteId") == "palkia", "Palkia should use its exact Showdown sprite ID.")
	_check(
		palkia_mapping.get("defaultMoves")
		== ["scaryface", "waterpulse", "dragonbreath", "ancientpower"],
		"Palkia's seeded moves should remain exact."
	)
	_check(
		SpeciesMapping.get_pokedex_dimensions(484)
		== {"height_dm": 42, "weight_hg": 3360},
		"Palkia should retain its exact form-specific Pokédex dimensions."
	)
	_check(
		SpeciesMapping.get_pokedex_dimensions(194)
		== {"height_dm": 4, "weight_hg": 85},
		"Wooper should retain its exact form-specific Pokédex dimensions."
	)
	_check(
		SpeciesMapping.get_pokedex_dimensions(321)
		== {"height_dm": 145, "weight_hg": 3980},
		"Wailord should retain the large-species Pokédex extreme."
	)
	_check(
		SpeciesMapping.get_pokedex_dimensions(595)
		== {"height_dm": 1, "weight_hg": 6},
		"Joltik should retain the tiny-species Pokédex extreme."
	)
	_check(
		SpeciesMapping.get_pokedex_dimensions(10190)
		== {"height_dm": 1000, "weight_hg": 0},
		"An unknown Pokédex weight should remain explicit instead of being invented."
	)
	_check(
		SpeciesMapping.get_pokedex_dimensions(10118).is_empty(),
		"Unsupported forms should not acquire guessed Pokédex dimensions."
	)
	_check(SpeciesMapping.get_move_type("tackle") == "Normal", "Tackle should expose its Showdown type.")
	_check(SpeciesMapping.get_move_type("watergun") == "Water", "Water Gun should expose its Showdown type.")
	_check(
		SpeciesMapping.get_move_type("thundershock") == "Electric",
		"Thunder Shock should expose its Showdown type."
	)
	_check(SpeciesMapping.get_move_type("notamove").is_empty(), "Unknown moves should have no type.")
	_check(SpeciesMapping.get_move_type("Tackle").is_empty(), "Move type lookup should require canonical IDs.")
	_check(not SpeciesMapping.has_mapping(10118), "An unapproved PokeAPI form should remain unsupported.")
	_check(10118 in SpeciesMapping.get_unsupported_pokemon_ids(), "Unsupported form IDs should be explicit.")


func _test_starting_profiles_and_server_party() -> void:
	var expected_moves := [
		["scaryface", "waterpulse", "dragonbreath", "ancientpower"],
		["tackle", "gust", "confusion", "bugbite"],
		["tackle", "growl", "peck", "hypnosis"],
		["gust", "poisonsting", "confuseray", "bugbite"],
		["tackle", "leer", "thundershock", "charge"],
		["watergun", "growl", "supersonic", "wingattack"],
	]
	var party := CollectionSystem.get_party()
	_check(party.size() == 6, "Fresh collection should retain its six-member party.")
	for member_index in min(party.size(), expected_moves.size()):
		var profile: Dictionary = party[member_index].get("battleProfile", {})
		_check(not profile.is_empty(), "Every supported starter should have a battleProfile.")
		_check(profile.get("moves") == expected_moves[member_index], "Starter move defaults should be exact.")

	var server_party := CollectionSystem.get_battle_party_members()
	_check(server_party.size() == 6, "Supported living party should pass battle preflight.")
	if not server_party.is_empty():
		var member := server_party[0]
		_check(member.size() == 5, "Server party members should contain no presentation-only fields.")
		for key in ["memberId", "species", "level", "health", "moves"]:
			_check(member.has(key), "Server party member should contain %s." % key)
		member["moves"][0] = "tackle"
		_check(
			CollectionSystem.get_party()[0]["battleProfile"]["moves"][0] == "scaryface",
			"Battle party results should be defensive deep copies."
		)


func _test_profile_migration_and_move_persistence() -> void:
	var party := CollectionSystem.get_party()
	var palkia_id := str(party[0]["pclID"])
	_check(
		CollectionSystem.set_equipped_moves(palkia_id, ["spacialrend", "surf"]),
		"Valid equipped move IDs should be accepted."
	)
	_check(
		not CollectionSystem.set_equipped_moves(palkia_id, ["Spacial Rend"]),
		"Move display names should not be accepted where canonical IDs are required."
	)
	_check(
		not CollectionSystem.set_equipped_moves(palkia_id, ["notamove"]),
		"Unknown but syntactically valid move IDs should be rejected locally."
	)
	var save_data := CollectionSystem.get_save_data()
	CollectionSystem.clear_collection()
	_check(CollectionSystem.load_save_data(save_data), "Battle profiles should reload from save data.")
	_check(
		CollectionSystem.get_battle_profile(palkia_id).get("moves") == ["spacialrend", "surf"],
		"Equipped moves should persist without being recomputed."
	)

	var legacy_save := save_data.duplicate(true)
	for pcl in legacy_save:
		pcl.erase("battleProfile")
	CollectionSystem.clear_collection()
	_check(CollectionSystem.load_save_data(legacy_save), "Legacy PCLs should migrate atomically.")
	_check(
		CollectionSystem.get_battle_profile(palkia_id).get("moves")
		== ["scaryface", "waterpulse", "dragonbreath", "ancientpower"],
		"Legacy supported PCLs should receive generated defaults once."
	)


func _test_unsupported_forms_and_all_fainted_preflight() -> void:
	CollectionSystem.clear_collection()
	var unsupported := CollectionSystem.add_pokemon(10118, 3, 1.0, 0.0, 1)
	_check(not unsupported.is_empty(), "Unsupported forms should remain collectible.")
	_check(not unsupported.has("battleProfile"), "Unsupported forms should not receive an invented battle mapping.")
	_check(CollectionSystem.get_battle_party_members().is_empty(), "Unsupported party members should fail local preflight.")
	_check(CollectionSystem.get_last_error().contains("not supported"), "Unsupported preflight should be actionable.")

	CollectionSystem.clear_collection()
	var pikachu := CollectionSystem.add_pokemon(25, 3, 0.0, 0.0, 1)
	var bulbasaur := CollectionSystem.add_pokemon(1, 3, 0.0, 0.0, 2)
	_check(not pikachu.is_empty() and not bulbasaur.is_empty(), "Fainted members should remain valid PCLs.")
	_check(CollectionSystem.get_battle_party_members().is_empty(), "An all-fainted party should fail local preflight.")
	_check(CollectionSystem.get_last_error().contains("no living"), "All-fainted preflight should explain the failure.")
	_check(
		is_equal_approx(CollectionSystem.get_pcl(str(pikachu["pclID"]))["instanceStats"]["health"], 0.0),
		"Zero health should be preserved."
	)
	_check(
		CollectionSystem.update_instance_stats(str(bulbasaur["pclID"]), {"health": 1.0}),
		"One party member should be healable for mixed-health preflight."
	)
	var mixed_health_party := CollectionSystem.get_battle_party_members()
	_check(mixed_health_party.size() == 2, "A party with one living member should pass preflight.")
	if mixed_health_party.size() == 2:
		_check(
			is_equal_approx(float(mixed_health_party[0].get("health", -1.0)), 0.0),
			"Zero-health members should remain in the server request roster."
		)


func _test_atomic_health_snapshot() -> void:
	var party := CollectionSystem.get_party()
	var first_id := str(party[0]["pclID"])
	var second_id := str(party[1]["pclID"])
	CollectionSystem.collection_changed.connect(_on_collection_changed)
	_collection_change_count = 0
	var invalid_snapshot := [
		{"memberId": first_id, "normalizedHealth": 0.25},
		{"memberId": "not-in-the-party", "normalizedHealth": 0.5},
	]
	_check(not CollectionSystem.apply_battle_health_snapshot(invalid_snapshot), "Unknown snapshot members should be rejected.")
	_check(_collection_change_count == 0, "Rejected snapshots should emit no collection update.")
	_check(
		is_equal_approx(CollectionSystem.get_pcl(first_id)["instanceStats"]["health"], 0.0),
		"Rejected snapshots should not partially mutate earlier members."
	)

	var valid_snapshot := [
		{"memberId": second_id, "normalizedHealth": 0.75, "active": true},
		{"memberId": first_id, "normalizedHealth": 0.25, "fainted": false},
	]
	_check(CollectionSystem.apply_battle_health_snapshot(valid_snapshot), "Complete health snapshot should apply.")
	_check(_collection_change_count == 1, "Accepted snapshots should emit exactly one collection update.")
	_check(
		is_equal_approx(CollectionSystem.get_pcl(first_id)["instanceStats"]["health"], 0.25)
		and is_equal_approx(CollectionSystem.get_pcl(second_id)["instanceStats"]["health"], 0.75),
		"Accepted snapshot should update every member atomically."
	)
	CollectionSystem.collection_changed.disconnect(_on_collection_changed)


func _test_kyle_encounter_resource_and_provider_scene() -> void:
	var encounter: Resource = load(KYLE_ENCOUNTER_PATH)
	_check(encounter != null, "Kyle encounter resource should load.")
	if encounter == null:
		return
	_check(encounter.validate().is_empty(), "Kyle encounter resource should validate.")
	_check(encounter.encounter_id == "trainer-kyle-lake-v1", "Kyle encounter ID should remain stable.")
	_check(encounter.display_name == "Trainer Kyle", "Kyle display name should be authored.")
	_check(encounter.api_name == "Kyle", "Kyle API name should be protocol-safe.")
	var team: Array[Dictionary] = encounter.to_server_team()
	_check(team.size() == 2, "Kyle should have exactly two team members.")
	if team.size() == 2:
		_check(
			team[0].get("species") == "Wooper"
			and team[0].get("level") == 3
			and team[0].get("moves") == ["watergun", "tailwhip"],
			"Kyle's first member should be the exact level-3 Wooper."
		)
		_check(
			team[1].get("species") == "Magikarp"
			and team[1].get("level") == 3
			and team[1].get("moves") == ["splash"],
			"Kyle's second member should be the exact level-3 Magikarp."
		)

	var invalid := EncounterDefinition.new()
	invalid.encounter_id = "Not Stable"
	invalid.display_name = "Invalid"
	invalid.api_name = "Bad|Name"
	invalid.members = [EncounterMember.new()]
	_check(not invalid.validate().is_empty(), "Invalid encounter authoring should be rejected.")

	var packed_scene: PackedScene = load(KYLE_SCENE_PATH)
	_check(packed_scene != null, "Concrete Kyle battle scene should load.")
	if packed_scene == null:
		return
	var scene := packed_scene.instantiate()
	add_child(scene)
	var providers := get_tree().get_nodes_in_group("battle_encounter_provider")
	var scene_providers := providers.filter(func(node: Node) -> bool: return scene.is_ancestor_of(node))
	_check(scene_providers.size() == 1, "Kyle scene should expose exactly one encounter provider.")
	if scene_providers.size() == 1:
		_check(scene_providers[0].encounter == encounter, "Kyle provider should export the authored encounter resource.")
	scene.queue_free()


func _on_collection_changed() -> void:
	_collection_change_count += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
