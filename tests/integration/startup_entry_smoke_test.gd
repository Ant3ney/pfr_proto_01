extends Node

const TEST_SAVE_PATH := "user://pfr_startup_entry_smoke_test.json"
const STARTERS: Array[int] = [4, 656, 252]

var _failures: Array[String] = []
var _entry_finished := false
var _entry_result: Array = []
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
	ProgressionAutosave.save_path = TEST_SAVE_PATH
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(false)
	ProgressionAutosave.startup_entry_completed.connect(_on_entry_completed)
	ProgressionAutosave.startup_entry_failed.connect(_on_entry_failed)
	# Automatic save hooks are intentionally disabled under res://tests/. Attach
	# only the two startup transfer callbacks exercised by this focused test.
	GameInstance.scene_transfer_finished.connect(
		ProgressionAutosave._on_scene_transfer_finished
	)
	GameInstance.scene_transfer_failed.connect(
		ProgressionAutosave._on_scene_transfer_failed
	)

	# Keep this coordinator outside SceneTree.current_scene so it survives each
	# real GameInstance transfer into the station.
	var scene_anchor := Node.new()
	scene_anchor.name = "StartupEntrySceneAnchor"
	get_tree().root.add_child(scene_anchor)
	get_tree().current_scene = scene_anchor

	for starter_id in STARTERS:
		_entry_finished = false
		_entry_result.clear()
		_entry_failure = ""
		_remove_test_save()
		ProgressionAutosave._startup_in_progress = true
		ProgressionAutosave._startup_intro_pending = false
		ProgressionAutosave._startup_entry_error = ""
		ProgressionAutosave._startup_entry_mode = (
			ProgressionAutosaveService.StartupEntryMode.NONE
		)
		ProgressionAutosave._explicit_reset_pending = false
		ProgressionAutosave._reset_in_progress = false
		ProgressionAutosave._prepare_fresh_profile_state()
		GameInstance.set_player_movement_enabled(false)
		_check(
			StarterSelectionSystem.choose_starter(starter_id),
			"Starter %d should be accepted during first launch." % starter_id
		)
		for frame in 600:
			if _entry_finished:
				break
			await get_tree().process_frame
		_check(
			_entry_finished and _entry_failure.is_empty(),
			(
				"Starter %d station entry should complete: %s "
				+ "[pending=%s mode=%s retry=%s transfer=%s scene=%s]"
			) % [
				starter_id,
				_entry_failure,
				ProgressionAutosave._profile_initialization_pending,
				ProgressionAutosave._startup_entry_mode,
				ProgressionAutosave._startup_retry_scene_path,
				GameInstance.is_scene_transfer_in_progress(),
				get_tree().current_scene.scene_file_path,
			]
		)
		if not _entry_finished or not _entry_failure.is_empty():
			continue
		_check(
			String(_entry_result[0]) == ProgressionAutosaveService.FIRST_GAMEPLAY_SCENE_PATH
			and not bool(_entry_result[1]),
			"Starter %d should enter Stretchman’s station without a Continue fallback."
			% starter_id
		)
		_validate_station_entry(starter_id)

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
			"Startup-entry smoke test passed: Charmander, Froakie, and Treecko each "
			+ "created one Lv. 5 party member, faced Stretchman, and checkpointed "
			+ "the exact station arrival."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Startup-entry smoke test failed: %s" % failure)
	get_tree().quit(1)


func _on_entry_completed(destination_scene_path: String, used_fallback: bool) -> void:
	_entry_result = [destination_scene_path, used_fallback]
	_entry_finished = true


func _on_entry_failed(message: String) -> void:
	_entry_failure = message
	_entry_finished = true


func _validate_station_entry(starter_id: int) -> void:
	var scene := get_tree().current_scene
	var player := scene.find_child("Player", true, false) as PlayerCharacter
	var marker := scene.find_child(
		String(ProgressionAutosaveService.FIRST_GAMEPLAY_SPAWN), true, false
	) as Marker3D
	var stretchman := scene.find_child("Stretchman", true, false) as Node3D
	var exit_to_city := scene.find_child("ExitToCity", true, false)
	var party := CollectionSystem.get_party()
	var member := party[0] as Dictionary if party.size() == 1 else {}
	var stats := member.get("instanceStats", {}) as Dictionary
	_check(
		scene.scene_file_path == ProgressionAutosaveService.FIRST_GAMEPLAY_SCENE_PATH
		and player != null
		and marker != null
		and player.global_transform.is_equal_approx(marker.global_transform),
		"Starter %d should be placed exactly at StretchmanReturnSpawn." % starter_id
	)
	_check(
		party.size() == 1
		and int(member.get("pokemonId", 0)) == starter_id
		and int(stats.get("level", 0)) == StarterSelectionSystem.STARTER_LEVEL,
		"Starter %d should be the only Lv. 5 party member." % starter_id
	)
	var player_forward := -player.global_basis.z.normalized()
	var to_stretchman := stretchman.global_position - player.global_position
	to_stretchman.y = 0.0
	_check(
		stretchman != null
		and not to_stretchman.is_zero_approx()
		and player_forward.dot(to_stretchman.normalized()) > 0.995,
		"The station marker should face starter %d directly toward Stretchman."
		% starter_id
	)
	var stretchman_controller: Variant = stretchman.get("controller")
	var stretchman_behavior: Variant = (
		stretchman_controller.get("npc_behavior")
		if stretchman_controller != null
		else null
	)
	_check(
		stretchman_behavior != null
		and stretchman_behavior.get("menu_scene") != null
		and String(stretchman_behavior.get("interaction_prompt"))
		== "Talk to Stretchman",
		"Stretchman’s Adventure Menu interaction should remain configured."
	)
	_check(
		exit_to_city != null
		and String(exit_to_city.get("destination_scene_path"))
		== ProgressionAutosaveService.MAIN_SCENE_PATH
		and StringName(exit_to_city.get("destination_spawn_marker"))
		== &"MiareStationReturn",
		"The station exit should remain connected to New Bouffalant City."
	)
	_check(
		GameInstance.is_player_movement_enabled(),
		"Player control should be enabled only after station placement succeeds."
	)
	_check(
		FileAccess.file_exists(TEST_SAVE_PATH),
		"The first checkpoint should be created after station placement."
	)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE_PATH))
	var payload := parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
	var world := payload.get("world", {}) as Dictionary
	_check(
		String(world.get("scene_path", ""))
		== ProgressionAutosaveService.FIRST_GAMEPLAY_SCENE_PATH
		and _array_to_vector(world.get("player_position", []))
		.is_equal_approx(marker.global_position)
		and int((payload.get("collection", []) as Array).size()) == 1,
		"The first schema-6 checkpoint should contain the marker pose and one starter."
	)


func _array_to_vector(value: Variant) -> Vector3:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return Vector3.INF
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
