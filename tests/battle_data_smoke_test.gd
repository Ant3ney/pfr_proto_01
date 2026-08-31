extends Node

const SpeciesMapping := preload("res://battle/system/BattleSpeciesMapping.gd")
const ExperiencePolicy := preload("res://battle/system/BattleExperience.gd")
const EncounterDefinition := preload("res://battle/data/BattleEncounterDefinition.gd")
const EncounterMember := preload("res://battle/data/BattleEncounterMember.gd")
const KYLE_ENCOUNTER_PATH := "res://battle/encounters/trainer_kyle_lake_v1.tres"
const KYLE_SCENE_PATH := "res://battle/kyle_battle_scene.tscn"
const KYLE_TRAINER_SCENE_PATH := "res://overworld/trainer_lake/TrainerKyle.tscn"
const DELIVERY_WORKER_ENCOUNTER_PATH := (
	"res://battle/encounters/trainer_delivery_worker_city_v1.tres"
)
const DELIVERY_WORKER_BATTLE_SCENE_PATH := (
	"res://battle/delivery_worker_battle_scene.tscn"
)
const DELIVERY_WORKER_TRAINER_SCENE_PATH := (
	"res://overworld/trainer_lake/TrainerDeliveryWorker.tscn"
)
const CITY_LINEUP_TRAINER_SPECS := [
	{
		"label": "Police Officer",
		"encounter_id": "trainer-police-officer-city-v1",
		"encounter_path": "res://battle/encounters/trainer_police_officer_city_v1.tres",
		"battle_scene_path": "res://battle/police_officer_battle_scene.tscn",
		"trainer_scene_path": "res://overworld/trainer_lake/TrainerPoliceOfficer.tscn",
		"team_size": 2,
	},
	{
		"label": "Businessman",
		"encounter_id": "trainer-businessman-city-v1",
		"encounter_path": "res://battle/encounters/trainer_businessman_city_v1.tres",
		"battle_scene_path": "res://battle/businessman_battle_scene.tscn",
		"trainer_scene_path": "res://overworld/trainer_lake/TrainerBusinessman.tscn",
		"team_size": 2,
	},
	{
		"label": "Backpacker",
		"encounter_id": "trainer-backpacker-city-v1",
		"encounter_path": "res://battle/encounters/trainer_backpacker_city_v1.tres",
		"battle_scene_path": "res://battle/backpacker_battle_scene.tscn",
		"trainer_scene_path": "res://overworld/trainer_lake/TrainerBackpacker.tscn",
		"team_size": 2,
	},
	{
		"label": "Jogger",
		"encounter_id": "trainer-jogger-city-v1",
		"encounter_path": "res://battle/encounters/trainer_jogger_city_v1.tres",
		"battle_scene_path": "res://battle/jogger_battle_scene.tscn",
		"trainer_scene_path": "res://overworld/trainer_lake/TrainerJogger.tscn",
		"team_size": 1,
	},
	{
		"label": "Tourist",
		"encounter_id": "trainer-tourist-city-v1",
		"encounter_path": "res://battle/encounters/trainer_tourist_city_v1.tres",
		"battle_scene_path": "res://battle/tourist_battle_scene.tscn",
		"trainer_scene_path": "res://overworld/trainer_lake/TrainerTourist.tscn",
		"team_size": 2,
	},
]

var _failures: Array[String] = []
var _collection_change_count := 0


func _ready() -> void:
	_test_generated_species_mapping()
	_test_starting_profiles_and_server_party()
	_test_profile_migration_and_move_persistence()
	_test_unsupported_forms_and_all_fainted_preflight()
	_test_atomic_health_snapshot()
	_test_experience_policy()
	_test_kyle_encounter_resource_and_provider_scene()
	_test_delivery_worker_encounter_mapping()
	_test_city_lineup_trainer_mappings()

	CollectionSystem.clear_collection()
	if _failures.is_empty():
		print(
			"Battle data smoke test passed: generated mapping, collection battle "
			+ "profiles, atomic HP/XP writeback, and trainer encounters verified."
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
	var unsupported := CollectionSystem.add_pokemon(10118, 3, 1.0, -1, 1)
	_check(not unsupported.is_empty(), "Unsupported forms should remain collectible.")
	_check(not unsupported.has("battleProfile"), "Unsupported forms should not receive an invented battle mapping.")
	_check(CollectionSystem.get_battle_party_members().is_empty(), "Unsupported party members should fail local preflight.")
	_check(CollectionSystem.get_last_error().contains("not supported"), "Unsupported preflight should be actionable.")

	CollectionSystem.clear_collection()
	var pikachu := CollectionSystem.add_pokemon(25, 3, 0.0, -1, 1)
	var bulbasaur := CollectionSystem.add_pokemon(1, 3, 0.0, -1, 2)
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

	var first_xp_before := int(CollectionSystem.get_pcl(first_id)["instanceStats"]["currentXp"])
	_collection_change_count = 0
	var rejected_progression := CollectionSystem.apply_battle_health_and_experience(
		[
			{"memberId": first_id, "normalizedHealth": 0.1},
			{"memberId": second_id, "normalizedHealth": 0.2},
		],
		[{"memberId": "not-in-the-party", "amount": 99}]
	)
	_check(not bool(rejected_progression.get("ok", true)), "Unknown XP recipients should reject the transaction.")
	_check(_collection_change_count == 0, "Rejected XP should emit no collection update.")
	_check(
		is_equal_approx(CollectionSystem.get_pcl(first_id)["instanceStats"]["health"], 0.25)
		and int(CollectionSystem.get_pcl(first_id)["instanceStats"]["currentXp"]) == first_xp_before,
		"Rejected XP should not partially apply health or progression."
	)

	var accepted_progression := CollectionSystem.apply_battle_health_and_experience(
		valid_snapshot,
		[
			{"memberId": first_id, "amount": 12},
			{"memberId": first_id, "amount": 8},
		]
	)
	_check(bool(accepted_progression.get("ok", false)), "Valid health and XP should apply together.")
	_check(_collection_change_count == 1, "Combined health and XP should emit one collection update.")
	_check(
		int(CollectionSystem.get_pcl(first_id)["instanceStats"]["currentXp"]) == first_xp_before + 20,
		"Repeated participant awards should be summed exactly once."
	)
	CollectionSystem.collection_changed.disconnect(_on_collection_changed)


func _test_experience_policy() -> void:
	var same_level_wooper := ExperiencePolicy.calculate_award(3, 3, 194)
	var same_level_palkia := ExperiencePolicy.calculate_award(3, 3, 484)
	var higher_level_wooper := ExperiencePolicy.calculate_award(3, 8, 194)
	_check(
		int(same_level_wooper.get("baseXp", 0)) == 30
		and int(same_level_wooper.get("amount", 0)) == 23,
		"A same-level level-3 Wooper should use the exact base and LC multiplier."
	)
	_check(
		int(same_level_palkia.get("amount", 0)) == 45,
		"A same-level Uber species should apply its stronger community multiplier."
	)
	_check(
		int(higher_level_wooper.get("amount", 0)) > int(same_level_wooper.get("amount", 0)),
		"A higher-level defeated Pokemon should yield more from the level differential."
	)


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

	var trainer_scene := load(KYLE_TRAINER_SCENE_PATH) as PackedScene
	_check(trainer_scene != null, "Kyle's overworld trainer scene should load.")
	if trainer_scene != null:
		var trainer := trainer_scene.instantiate() as PFRCharacter
		add_child(trainer)
		var controller := trainer.controller as TrainerKyle if trainer != null else null
		var behavior := (
			controller.npc_behavior as TrainerBehavior
			if controller != null
			else null
		)
		_check(
			controller != null
			and controller.encounter_id == encounter.encounter_id
			and controller.battle_scene_path == KYLE_SCENE_PATH,
			"Kyle's scene-local controller should retain its concrete encounter launch."
		)
		_check(
			behavior != null
			and behavior.encounter_id == encounter.encounter_id
			and behavior.battle_scene_path == KYLE_SCENE_PATH,
			"Kyle's scene-local behavior should receive the same concrete encounter launch."
		)
		trainer.queue_free()


func _test_delivery_worker_encounter_mapping() -> void:
	var encounter: Resource = load(DELIVERY_WORKER_ENCOUNTER_PATH)
	_check(encounter != null, "Delivery Worker encounter resource should load.")
	if encounter == null:
		return
	_check(
		encounter.validate().is_empty(),
		"Delivery Worker encounter resource should validate."
	)
	_check(
		encounter.encounter_id == "trainer-delivery-worker-city-v1",
		"Delivery Worker encounter ID should remain stable."
	)
	_check(
		encounter.display_name == "Delivery Worker",
		"Delivery Worker display name should be authored."
	)
	_check(
		encounter.api_name == "DeliveryWorker",
		"Delivery Worker API name should be protocol-safe."
	)
	_check(
		encounter.to_server_team().size() == 2,
		"Delivery Worker should have the cloned two-member starter roster."
	)

	var battle_scene: PackedScene = load(DELIVERY_WORKER_BATTLE_SCENE_PATH)
	_check(battle_scene != null, "Delivery Worker battle scene should load.")
	if battle_scene != null:
		var battle_instance := battle_scene.instantiate()
		add_child(battle_instance)
		var providers := get_tree().get_nodes_in_group("battle_encounter_provider")
		var scene_providers := providers.filter(
			func(node: Node) -> bool: return battle_instance.is_ancestor_of(node)
		)
		_check(
			scene_providers.size() == 1,
			"Delivery Worker battle scene should expose one encounter provider."
		)
		if scene_providers.size() == 1:
			_check(
				scene_providers[0].encounter == encounter,
				"Delivery Worker provider should export its authored encounter."
			)
		battle_instance.queue_free()

	var trainer_scene: PackedScene = load(DELIVERY_WORKER_TRAINER_SCENE_PATH)
	_check(trainer_scene != null, "Delivery Worker trainer scene should load.")
	if trainer_scene == null:
		return
	var trainer_instance := trainer_scene.instantiate()
	var controller: Resource = trainer_instance.get("controller") as Resource
	_check(controller != null, "Delivery Worker trainer should expose a controller.")
	if controller != null:
		_check(
			controller.get("encounter_id") == encounter.encounter_id,
			"Delivery Worker trainer and encounter IDs should match."
		)
		_check(
			controller.get("battle_scene_path")
			== DELIVERY_WORKER_BATTLE_SCENE_PATH,
			"Delivery Worker trainer should launch its concrete battle scene."
		)
	trainer_instance.free()


func _test_city_lineup_trainer_mappings() -> void:
	for spec: Dictionary in CITY_LINEUP_TRAINER_SPECS:
		var label := str(spec["label"])
		var encounter: Resource = load(str(spec["encounter_path"]))
		_check(encounter != null, "%s encounter resource should load." % label)
		if encounter == null:
			continue
		_check(
			encounter.validate().is_empty(),
			"%s encounter resource should validate." % label
		)
		_check(
			encounter.get("encounter_id") == spec["encounter_id"],
			"%s encounter ID should match its lineup specification." % label
		)
		_check(
			encounter.get("display_name") == label,
			"%s encounter should expose its authored display name." % label
		)
		_check(
			encounter.call("to_server_team").size() == int(spec["team_size"]),
			"%s encounter should expose its authored team." % label
		)

		var battle_scene: PackedScene = load(str(spec["battle_scene_path"]))
		_check(battle_scene != null, "%s battle scene should load." % label)
		if battle_scene != null:
			var battle_instance := battle_scene.instantiate()
			add_child(battle_instance)
			var providers := get_tree().get_nodes_in_group(
				"battle_encounter_provider"
			)
			var scene_providers := providers.filter(
				func(node: Node) -> bool:
					return battle_instance.is_ancestor_of(node)
			)
			_check(
				scene_providers.size() == 1,
				"%s battle scene should expose one encounter provider." % label
			)
			if scene_providers.size() == 1:
				_check(
					scene_providers[0].encounter == encounter,
					"%s battle scene should provide its matching encounter." % label
				)
			battle_instance.queue_free()

		var trainer_scene: PackedScene = load(str(spec["trainer_scene_path"]))
		_check(trainer_scene != null, "%s trainer scene should load." % label)
		if trainer_scene == null:
			continue
		var trainer_instance := trainer_scene.instantiate()
		var controller: Resource = trainer_instance.get("controller") as Resource
		_check(controller != null, "%s should expose a trainer controller." % label)
		if controller != null:
			_check(
				controller.get("encounter_id") == spec["encounter_id"],
				"%s trainer and encounter IDs should match." % label
			)
			_check(
				controller.get("battle_scene_path") == spec["battle_scene_path"],
				"%s trainer should launch its matching battle scene." % label
			)

		var art_pack: Resource = (
			trainer_instance.get("character_art_asset_pack") as Resource
		)
		var character_art := trainer_instance.get_node_or_null(
			^"Visual/CharacterArt"
		) as Node3D
		_check(art_pack != null, "%s should expose a character art pack." % label)
		_check(character_art != null, "%s should expose character art." % label)
		if art_pack != null and character_art != null:
			var expected_scene := art_pack.get("character_scene") as PackedScene
			_check(
				expected_scene != null
				and character_art.scene_file_path == expected_scene.resource_path,
				"%s art pack and preview model should match." % label
			)
			var animation_player := character_art.get_node_or_null(
				art_pack.get("animation_player_path")
			) as AnimationPlayer
			_check(
				animation_player != null,
				"%s character art should expose its AnimationPlayer." % label
			)
			if animation_player != null:
				_check(
					animation_player.has_animation(art_pack.get("idle_animation")),
					"%s character art should contain its idle animation." % label
				)
				_check(
					animation_player.has_animation(art_pack.get("run_animation")),
					"%s character art should contain its run animation." % label
				)
		trainer_instance.free()


func _on_collection_changed() -> void:
	_collection_change_count += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
