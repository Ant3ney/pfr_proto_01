extends Node

const TEST_SAVE_PATH := "user://pfr_startup_continue_smoke_test.json"
const EXACT_CASES: Array[Dictionary] = [
	{
		"scene_path": ProgressionAutosaveService.FIRST_GAMEPLAY_SCENE_PATH,
		"position": Vector3(0.8, 0.0, 1.2),
		"rotation": Vector3(0.0, 0.35, 0.0),
		"visual_rotation": Vector3(0.0, -0.55, 0.0),
	},
	{
		"scene_path": ProgressionAutosaveService.MAIN_SCENE_PATH,
		"position": Vector3(0.0, 0.0, -8.0),
		"rotation": Vector3(0.0, 0.9, 0.0),
		"visual_rotation": Vector3(0.0, 0.4, 0.0),
	},
	{
		"scene_path": "res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn",
		"position": Vector3(12.0, 0.0, -56.0),
		"rotation": Vector3(0.0, -1.1, 0.0),
		"visual_rotation": Vector3(0.0, 0.72, 0.0),
	},
]

var _failures: Array[String] = []
var _entry_finished := false
var _entry_destination := ""
var _entry_used_fallback := false
var _entry_failure := ""


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_save()
	var original_save_path := ProgressionAutosave.save_path
	var original_collection := CollectionSystem.get_save_data()
	var original_move_learning := MoveLearningSystem.get_save_data()
	var original_economy := EconomySystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	var original_challenges := ChallengeProgressionSystem.get_save_data()
	var original_starter_id := ProgressionAutosave.get_starter_pokemon_id()
	var original_movement := GameInstance.is_player_movement_enabled()
	var original_test_process := MoveLearningSystem._test_process
	ProgressionAutosave.save_path = TEST_SAVE_PATH
	MoveLearningSystem._test_process = false
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	ProgressionAutosave.startup_entry_completed.connect(_on_entry_completed)
	ProgressionAutosave.startup_entry_failed.connect(_on_entry_failed)
	GameInstance.scene_transfer_finished.connect(
		ProgressionAutosave._on_scene_transfer_finished
	)
	GameInstance.scene_transfer_failed.connect(
		ProgressionAutosave._on_scene_transfer_failed
	)

	await _install_empty_scene_anchor()
	for test_case in EXACT_CASES:
		await _prepare_continue_fixture(test_case)
		var pending_before := MoveLearningSystem.get_pending_requests().size()
		var inspection := ProgressionAutosave.begin_startup_session()
		_check(
			bool(inspection.get("valid", false))
			and bool(inspection.get("has_usable_location", false)),
			"The station, city, and Route 0 fixtures should have usable saved locations."
		)
		_check(
			ProgressionAutosave.continue_from_startup(),
			"Continue should accept %s." % String(test_case["scene_path"])
		)
		_check(
			pending_before == 1
			and MoveLearningSystem._active_ui == null
			and not MoveLearningSystem._automatic_presentation_scheduled,
			"Pending move learning should remain hidden while startup is entering gameplay."
		)
		await _wait_for_entry()
		_check(
			_entry_failure.is_empty()
			and _entry_destination == String(test_case["scene_path"])
			and not _entry_used_fallback,
			"Continue should enter the exact saved scene: %s" % _entry_failure
		)
		_validate_exact_pose(test_case)
		await get_tree().process_frame
		await get_tree().process_frame
		_check(
			MoveLearningSystem._active_ui != null
			and MoveLearningSystem._presenting,
			"The pending move-learning prompt should appear only after gameplay entry."
		)
		MoveLearningSystem.reset_for_testing()
		await _install_empty_scene_anchor()

	# A schema-3 profile without a location retains its progression and uses the
	# station marker rather than replaying the intro or creating another starter.
	var fallback_case := {
		"scene_path": "",
		"position": Vector3.ZERO,
		"rotation": Vector3.ZERO,
		"visual_rotation": Vector3.ZERO,
	}
	await _prepare_continue_fixture(fallback_case, true)
	var fallback_party_id := int(CollectionSystem.get_party()[0].get("pokemonId", 0))
	var fallback_inspection := ProgressionAutosave.begin_startup_session()
	_check(
		bool(fallback_inspection.get("valid", false))
		and not bool(fallback_inspection.get("has_usable_location", true)),
		"A compatible old save with no world record should remain valid."
	)
	_check(
		ProgressionAutosave.continue_from_startup(),
		"Continue should accept a compatible save without a location."
	)
	await _wait_for_entry()
	var fallback_scene := get_tree().current_scene
	var fallback_player := fallback_scene.find_child("Player", true, false) as PlayerCharacter
	var fallback_marker := fallback_scene.find_child(
		String(ProgressionAutosaveService.FIRST_GAMEPLAY_SPAWN), true, false
	) as Marker3D
	_check(
		_entry_failure.is_empty()
		and _entry_used_fallback
		and _entry_destination == ProgressionAutosaveService.FIRST_GAMEPLAY_SCENE_PATH
		and fallback_player.global_transform.is_equal_approx(fallback_marker.global_transform)
		and int(CollectionSystem.get_party()[0].get("pokemonId", 0)) == fallback_party_id
		and ProgressionAutosave.get_starter_pokemon_id() == 0
		and not StarterSelectionSystem.is_selection_required(),
		"Old progression should resume at StretchmanReturnSpawn without another starter."
	)

	MoveLearningSystem.reset_for_testing()
	MoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	MoveLearningSystem.load_save_data(original_move_learning)
	MoveLearningSystem.finish_save_restore()
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	ChallengeProgressionSystem.load_save_data(original_challenges)
	StarterSelectionSystem.mark_profile_loaded(original_starter_id)
	ProgressionAutosave._starter_pokemon_id = original_starter_id
	ProgressionAutosave._startup_in_progress = false
	ProgressionAutosave._profile_initialization_pending = false
	ProgressionAutosave.save_path = original_save_path
	GameInstance.set_player_movement_enabled(original_movement)
	MoveLearningSystem._test_process = original_test_process
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	GameInstance.scene_transfer_finished.disconnect(
		ProgressionAutosave._on_scene_transfer_finished
	)
	GameInstance.scene_transfer_failed.disconnect(
		ProgressionAutosave._on_scene_transfer_failed
	)
	_remove_test_save()

	if _failures.is_empty():
		print(
			"Startup-Continue smoke test passed: station, city, and Route 0 poses "
			+ "restored exactly; old-save fallback and post-entry prompts verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Startup-Continue smoke test failed: %s" % failure)
	get_tree().quit(1)


func _prepare_continue_fixture(test_case: Dictionary, as_schema_three := false) -> void:
	_remove_test_save()
	ProgressionAutosave._startup_in_progress = true
	ProgressionAutosave._profile_initialization_pending = false
	ProgressionAutosave._reset_in_progress = false
	ProgressionAutosave._starter_pokemon_id = 0
	StarterSelectionSystem.mark_profile_loaded(0)
	MoveLearningSystem.reset_for_testing()
	CollectionSystem.clear_collection()
	var palkia := CollectionSystem.add_pokemon(484, 23, 1.0, -1, 1)
	var pcl_id := String(palkia.get("pclID", ""))
	MoveLearningSystem.reset_for_testing()
	MoveLearningSystem._test_process = false
	CollectionSystem.update_instance_stats(pcl_id, {"level": 24})
	ProgressionAutosave._saved_world_state = (
		{}
		if String(test_case.get("scene_path", "")).is_empty()
		else {
			"scene_path": String(test_case["scene_path"]),
			"player_position": _vector_to_array(test_case["position"] as Vector3),
			"player_rotation": _vector_to_array(test_case["rotation"] as Vector3),
			"visual_rotation": _vector_to_array(test_case["visual_rotation"] as Vector3),
		}
	)
	ProgressionAutosave._last_payload_fingerprint = ""
	ProgressionAutosave._startup_in_progress = false
	_check(
		MoveLearningSystem.get_pending_requests().size() == 1
		and ProgressionAutosave.save_now(true),
		"Each Continue fixture should save one pending move choice."
	)
	if as_schema_three:
		_convert_checkpoint_to_schema_three()
	await get_tree().process_frame


func _convert_checkpoint_to_schema_three() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("The schema-3 fallback fixture should parse.")
		return
	var payload := (parsed as Dictionary).duplicate(true)
	var economy := payload.get("economy", {}) as Dictionary
	var inventory := payload.get("inventory", {}) as Dictionary
	var challenge := payload.get("challenge_progression", {}) as Dictionary
	payload["schema_version"] = 3
	payload.erase("profile")
	payload.erase("economy")
	payload.erase("inventory")
	payload.erase("challenge_progression")
	payload.erase("save_meta")
	payload["world"] = {}
	payload["stretch"] = {
		"economy_version": int(economy.get("version", 2)),
		"balance": int(economy.get("balance", 50)),
		"item_inventory": inventory.get("item_quantities", {}),
		"claimed_gifts": inventory.get("claimed_gifts", []),
		"earned_badges": challenge.get("earned_badges", []),
		"champion_cleared": bool(challenge.get("champion_completed", false)),
		"completed_routes": challenge.get("completed_routes", []),
		"active_destination": {},
		"run_defeated_ids": challenge.get("run_defeated_ids", []),
		"run_id": int(challenge.get("run_id", 0)),
		"last_battle_reward": economy.get("last_battle_reward", {}),
	}
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(payload, "\t"))
		file.flush()


func _validate_exact_pose(test_case: Dictionary) -> void:
	var scene := get_tree().current_scene
	var player := scene.find_child("Player", true, false) as PlayerCharacter
	var visual := player.get_node_or_null(^"Visual") as Node3D
	_check(
		player.global_position.is_equal_approx(test_case["position"] as Vector3)
		and player.global_rotation.is_equal_approx(test_case["rotation"] as Vector3)
		and visual.rotation.is_equal_approx(test_case["visual_rotation"] as Vector3),
		"Continue should restore exact position and both saved facing rotations in %s."
		% String(test_case["scene_path"])
	)


func _wait_for_entry() -> void:
	_entry_finished = false
	_entry_destination = ""
	_entry_used_fallback = false
	_entry_failure = ""
	for frame in 600:
		if _entry_finished:
			return
		await get_tree().process_frame
	_failures.append("Timed out while waiting for startup Continue to enter gameplay.")


func _on_entry_completed(destination_scene_path: String, used_fallback: bool) -> void:
	_entry_destination = destination_scene_path
	_entry_used_fallback = used_fallback
	_entry_finished = true


func _on_entry_failed(message: String) -> void:
	_entry_failure = message
	_entry_finished = true


func _install_empty_scene_anchor() -> void:
	var previous := get_tree().current_scene
	var scene_anchor := Node.new()
	scene_anchor.name = "ContinueSceneAnchor"
	get_tree().root.add_child(scene_anchor)
	get_tree().current_scene = scene_anchor
	if previous != null and previous != self and is_instance_valid(previous):
		previous.queue_free()
	await get_tree().process_frame


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
