extends Node3D

const TEST_SAVE_PATH := "user://pfr_rnd_progression_smoke_test.json"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_save()
	var original_collection := CollectionSystem.get_save_data()
	var original_move_learning := RNDMoveLearningSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	var original_save_path := ProgressionAutosave.save_path
	RNDMoveLearningSystem.set_automatic_presentation_enabled_for_testing(false)
	RNDMoveLearningSystem.reset_for_testing()
	ProgressionAutosave.save_path = TEST_SAVE_PATH
	var saved_stretch := original_stretch.duplicate(true)
	saved_stretch["balance"] = 777
	saved_stretch["item_inventory"] = {"potion": 2}
	_check(
		StretchGoalSystem.load_save_data(saved_stretch),
		"The save fixture should be able to set Stretchman's economy state."
	)

	var player := $Player as PlayerCharacter
	var expected_position := Vector3(3.25, 0.0, -4.75)
	var expected_visual_rotation := Vector3(0.0, 0.72, 0.0)
	player.global_position = expected_position
	(player.get_node(^"Visual") as Node3D).rotation = expected_visual_rotation

	var first_party_member := CollectionSystem.get_party()[0] as Dictionary
	var pcl_id := String(first_party_member["pclID"])
	_check(
		CollectionSystem.update_instance_stats(pcl_id, {"health": 0.41}),
		"The save fixture should be able to change party health."
	)
	_check(
		CollectionSystem.update_instance_stats(pcl_id, {"level": 23})
		and CollectionSystem.update_instance_stats(pcl_id, {"level": 24}),
		"The save fixture should cross Palkia's level-24 move threshold."
	)
	_check(
		RNDMoveLearningSystem.get_pending_requests().size() == 1,
		"The save fixture should own one unresolved move-learning choice."
	)
	_check(
		ProgressionAutosave.save_now(true),
		"The RND autosave owner should write a checkpoint immediately."
	)

	player.global_position = Vector3(-8.0, 0.0, 6.0)
	(player.get_node(^"Visual") as Node3D).rotation = Vector3.ZERO
	CollectionSystem.update_instance_stats(pcl_id, {"health": 0.87})
	RNDMoveLearningSystem.resolve_next_pending(-1)
	var changed_stretch := saved_stretch.duplicate(true)
	changed_stretch["balance"] = 123
	changed_stretch["item_inventory"] = {}
	StretchGoalSystem.load_save_data(changed_stretch)
	_check(
		ProgressionAutosave.load_now(),
		"The RND autosave owner should reload its saved checkpoint."
	)

	var restored_member := CollectionSystem.get_pcl(pcl_id)
	var restored_stats := restored_member.get("instanceStats", {}) as Dictionary
	_check(
		is_equal_approx(float(restored_stats.get("health", -1.0)), 0.41),
		"Loading should restore player-owned collection progression."
	)
	_check(
		int(restored_stats.get("level", 0)) == 24
		and RNDMoveLearningSystem.get_pending_requests().size() == 1
		and String(
			RNDMoveLearningSystem.get_pending_requests()[0].get("moveId", "")
		) == "slash",
		"Loading should restore the level and its unresolved move choice together."
	)
	_check(
		player.global_position.is_equal_approx(expected_position),
		"Loading in the saved scene should restore the overworld player location."
	)
	_check(
		(player.get_node(^"Visual") as Node3D).rotation.is_equal_approx(
			expected_visual_rotation
		),
		"Loading should restore the player's facing direction."
	)
	_check(
		StretchGoalSystem.get_balance() == 777,
		"Loading should restore Stretchman's balance alongside collection progression."
	)
	_check(
		StretchGoalSystem.get_item_count("potion") == 2,
		"Loading should restore the player-menu Bag from the persistent item inventory."
	)

	RNDMoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	RNDMoveLearningSystem.load_save_data(original_move_learning)
	RNDMoveLearningSystem.finish_save_restore()
	RNDMoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	StretchGoalSystem.load_save_data(original_stretch)
	ProgressionAutosave.save_path = original_save_path
	_remove_test_save()

	if _failures.is_empty():
		print(
			"RND progression autosave smoke test passed: disk checkpoint, validated "
			+ "collection/economy/move-choice reload, and current-scene player pose "
			+ "restoration verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("RND progression autosave smoke test failed: %s" % failure)
	get_tree().quit(1)


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
