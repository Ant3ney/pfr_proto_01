extends Node3D

const SOURCE_SCENE_PATH := "res://tests/integration/battle_return_position_smoke_test.tscn"


class BattleReturnWatcher:
	extends Node

	var failures: Array[String] = []
	var expected_transform := Transform3D.IDENTITY
	var expected_visual_rotation := Vector3.ZERO


	func run() -> void:
		var source_scene := get_tree().current_scene
		var player := source_scene.get_node(^"Player") as PlayerCharacter
		player.global_position = Vector3(4.5, 0.0, -3.75)
		player.global_rotation = Vector3(0.0, 0.31, 0.0)
		var visual := player.get_node(^"Visual") as Node3D
		visual.rotation = Vector3(0.0, -0.84, 0.0)
		expected_transform = player.global_transform
		expected_visual_rotation = visual.rotation

		var accepted := GameInstance.startBattle({
			"encounter_type": "wild",
			"battle_scene_path": "res://game/battle/scenes/battle_scene.tscn",
		})
		_check(accepted, "The source scene should launch the shared battle scene.")
		await _wait_for_scene_path("res://game/battle/scenes/battle_scene.tscn")
		_check(
			get_tree().current_scene is BattleScene,
			"The battle transition should reach the shared battle scene."
		)
		for _frame in range(120):
			if not GameInstance.get_active_battle_data().is_empty():
				break
			await get_tree().process_frame
		_check(
			GameInstance.get_active_battle_data().get("return_scene_path")
			== SOURCE_SCENE_PATH,
			"Battle launch should retain the implicit source return scene."
		)
		_check(
			GameInstance.return_from_battle("", "rnd-return-position-test"),
			"A battle return without an override should use the captured source."
		)

		await _wait_for_scene_path(SOURCE_SCENE_PATH)
		var returned_scene := get_tree().current_scene
		var returned_player := returned_scene.get_node(^"Player") as PlayerCharacter
		var returned_visual := returned_player.get_node(^"Visual") as Node3D
		_check(
			returned_player.global_transform.is_equal_approx(expected_transform),
			"The returned player should keep the exact pre-battle transform."
		)
		_check(
			returned_visual.rotation.is_equal_approx(expected_visual_rotation),
			"The returned player should keep the pre-battle facing direction."
		)
		_check(
			GameInstance.is_player_movement_enabled(),
			"Movement should be restored only after the source scene is ready."
		)

		if failures.is_empty():
			print(
				"RND battle return smoke test passed: implicit source scene, exact player "
				+ "transform/facing, and movement restoration verified."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("RND battle return smoke test failed: %s" % failure)
		get_tree().quit(1)


	func _wait_for_scene_path(path: String) -> void:
		for _frame in range(600):
			var scene := get_tree().current_scene
			if scene != null and scene.scene_file_path == path:
				return
			await get_tree().process_frame


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


func _ready() -> void:
	if get_tree().root.has_node(^"BattleReturnPositionWatcher"):
		return
	var watcher := BattleReturnWatcher.new()
	watcher.name = "BattleReturnPositionWatcher"
	get_tree().root.add_child.call_deferred(watcher)
	watcher.run.call_deferred()
