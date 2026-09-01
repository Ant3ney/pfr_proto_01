extends Node3D

const TEST_SAVE_PATH := "user://pfr_rnd_progression_smoke_test.json"
const TEST_EXPORT_PATH := "user://pfr_rnd_progression_export_smoke_test.json"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_files()
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
	saved_stretch["claimed_gifts"] = ["autosave-exp-share-fixture"]
	saved_stretch["completed_routes"] = [0]
	saved_stretch["active_destination"] = {}
	saved_stretch["run_defeated_ids"] = []
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
		CollectionSystem.set_held_item(pcl_id, StretchGoalSystem.XP_SHARE_ITEM_KEY),
		"The save fixture should be able to equip a held Exp. Share."
	)
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
	var timestamped_payload := ProgressionAutosave.get_save_payload()
	var save_meta := timestamped_payload.get("save_meta", {}) as Dictionary
	var section_timestamps := (
		save_meta.get("section_updated_at_ms", {}) as Dictionary
	)
	_check(
		int(timestamped_payload.get("schema_version", 0)) == 5
		and int(save_meta.get("saved_at_ms", 0)) > 0
		and int(section_timestamps.get("profile", 0)) > 0
		and int(section_timestamps.get("collection", 0)) > 0
		and int(section_timestamps.get("move_learning", 0)) > 0
		and int(section_timestamps.get("stretch", 0)) > 0
		and int(section_timestamps.get("world", 0)) > 0,
		"Schema 5 should retain offline-safe timestamps for every mergeable save section."
	)

	player.global_position = Vector3(-8.0, 0.0, 6.0)
	(player.get_node(^"Visual") as Node3D).rotation = Vector3.ZERO
	CollectionSystem.update_instance_stats(pcl_id, {"health": 0.87})
	CollectionSystem.set_held_item(pcl_id, "")
	RNDMoveLearningSystem.resolve_next_pending(-1)
	var changed_stretch := saved_stretch.duplicate(true)
	changed_stretch["balance"] = 123
	changed_stretch["item_inventory"] = {}
	changed_stretch["claimed_gifts"] = []
	changed_stretch["completed_routes"] = []
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
	_check(
		CollectionSystem.get_held_item(pcl_id) == StretchGoalSystem.XP_SHARE_ITEM_KEY,
		"Loading should restore the Pokemon's held item from its PCL."
	)
	_check(
		StretchGoalSystem.has_claimed_gift("autosave-exp-share-fixture"),
		"Loading should restore one-time world gift claims."
	)
	_check(
		StretchGoalSystem.get_completed_routes() == [0]
		and StretchGoalSystem.is_route_unlocked(1),
		"Loading should restore the far-end Route 0 clear and its Route 1 unlock."
	)
	var cloud_payload := ProgressionAutosave.get_save_payload()
	cloud_payload["stretch"]["balance"] = 888
	var cloud_meta := cloud_payload.get("save_meta", {}) as Dictionary
	var cloud_timestamps := (
		cloud_meta.get("section_updated_at_ms", {}) as Dictionary
	)
	cloud_timestamps["stretch"] = int(cloud_timestamps.get("stretch", 0)) + 100
	cloud_meta["section_updated_at_ms"] = cloud_timestamps
	cloud_meta["saved_at_ms"] = int(cloud_meta.get("saved_at_ms", 0)) + 100
	cloud_payload["save_meta"] = cloud_meta
	_check(
		ProgressionAutosave.apply_cloud_payload(cloud_payload)
		and StretchGoalSystem.get_balance() == 888,
		"A resolved cloud payload should use the normal validators and checkpoint locally."
	)
	var exported_json := ProgressionAutosave.get_export_json()
	var exported_value: Variant = JSON.parse_string(exported_json)
	var exported_payload := (
		exported_value as Dictionary
		if typeof(exported_value) == TYPE_DICTIONARY
		else {}
	)
	_check(
		int(exported_payload.get("schema_version", 0))
		== RNDProgressionAutosave.SAVE_SCHEMA_VERSION
		and exported_payload.has("profile")
		and exported_payload.has("collection")
		and exported_payload.has("move_learning")
		and exported_payload.has("stretch")
		and exported_payload.has("world")
		and exported_payload.has("save_meta")
		and not exported_payload.has("save_id")
		and not exported_payload.has("device_id"),
		"JSON export should use the credential-free schema-5 cloud progression payload."
	)
	_check(
		ProgressionAutosave.write_export_json(TEST_EXPORT_PATH)
		and FileAccess.file_exists(TEST_EXPORT_PATH),
		"JSON export should write the portable payload to a selected path."
	)
	var before_import_stretch := StretchGoalSystem.get_save_data()
	before_import_stretch["balance"] = 321
	_check(
		StretchGoalSystem.load_save_data(before_import_stretch),
		"The JSON-import fixture should be able to diverge from its exported backup."
	)
	var before_import_payload := ProgressionAutosave.get_save_payload()
	var before_import_meta := before_import_payload.get("save_meta", {}) as Dictionary
	_check(
		ProgressionAutosave.import_json_save(exported_json, "smoke-test JSON import")
		and StretchGoalSystem.get_balance() == 888,
		"JSON import should validate, replace, and checkpoint the exported progression."
	)
	var imported_payload := ProgressionAutosave.get_save_payload()
	var imported_meta := imported_payload.get("save_meta", {}) as Dictionary
	var imported_timestamps := (
		imported_meta.get("section_updated_at_ms", {}) as Dictionary
	)
	_check(
		int(imported_meta.get("saved_at_ms", 0))
		> int(before_import_meta.get("saved_at_ms", 0))
		and int(imported_timestamps.get("stretch", 0))
		== int(imported_meta.get("saved_at_ms", 0)),
		"A manual import should become a fresh local edit for cloud conflict resolution."
	)
	var checkpoint_value: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TEST_SAVE_PATH)
	)
	_check(
		typeof(checkpoint_value) == TYPE_DICTIONARY
		and int(
			((checkpoint_value as Dictionary).get("stretch", {}) as Dictionary).get(
				"balance",
				-1
			)
		) == 888,
		"A successful JSON import should immediately replace the ordinary local checkpoint."
	)

	RNDMoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	RNDMoveLearningSystem.load_save_data(original_move_learning)
	RNDMoveLearningSystem.finish_save_restore()
	RNDMoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	StretchGoalSystem.load_save_data(original_stretch)
	ProgressionAutosave.save_path = original_save_path
	_remove_test_files()

	if _failures.is_empty():
		print(
			"RND progression autosave smoke test passed: disk checkpoint, validated "
			+ "collection/economy/held-item/gift/route/move-choice reload, and current-scene "
			+ "player pose restoration plus cloud-compatible JSON transfer verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("RND progression autosave smoke test failed: %s" % failure)
	get_tree().quit(1)


func _remove_test_files() -> void:
	for path in [TEST_SAVE_PATH, TEST_EXPORT_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
