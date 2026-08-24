extends Node


class BattleStartWatcher:
	extends Node

	var failures: Array[String] = []


	func run() -> void:
		var ordinary_template := UIManager.show_ui("Template baseline")
		_check(
			ordinary_template != null,
			"The ordinary UI template should still instantiate."
		)
		if ordinary_template:
			ordinary_template.set_speaker_name("System")
			ordinary_template.set_action_text("Continue")
			_check(
				ordinary_template.message_label.text == "Template baseline",
				"Battle transition support should not change ordinary template text."
			)
			_check(
				ordinary_template.dialog_panel.visible
				and ordinary_template.action_frame.visible,
				"Ordinary template panels should remain visible by default."
			)
			ordinary_template.close()
			await get_tree().process_frame
			_check(
				_ui_template_count() == 0,
				"The ordinary template should retain its close lifecycle."
			)

		var launch_data := {
			"encounter_type": "trainer",
			"trainer_name": "Ranger Mira",
			"player_party": [{"pcl_id": "player-001"}],
			"opponent_party": [{"pokemon_id": 25, "level": 7}],
			"nested": {"seed": 7},
		}
		var accepted := GameInstance.startBattle(launch_data)
		_check(accepted, "startBattle should accept the first launch request.")
		_check(
			not GameInstance.is_player_movement_enabled(),
			"Battle start should lock overworld movement immediately."
		)
		_check(
			GameInstance.is_battle_start_in_progress(),
			"Battle start should report an active transition."
		)
		_check(
			not GameInstance.startBattle({"encounter_type": "wild"}),
			"A second battle start should be rejected while the first is active."
		)

		launch_data["nested"]["seed"] = 99
		var pending := GameInstance.get_pending_battle_data()
		_check(
			pending.get("source_scene_path")
				== "res://tests/battle_start_smoke_test.tscn",
			"GameInstance should capture the implicit source scene path."
		)
		_check(
			pending.get("return_scene_path")
				== "res://tests/battle_start_smoke_test.tscn",
			"The source scene should be the implicit return scene."
		)
		_check(
			pending.get("transition_title") == "TRAINER BATTLE",
			"Trainer encounters should receive the trainer transition title."
		)
		_check(
			pending.get("transition_subtitle") == "Ranger Mira",
			"The trainer name should become the implicit transition subtitle."
		)
		_check(
			pending.get("nested", {}).get("seed") == 7,
			"Battle launch data should be isolated by a deep copy."
		)
		_check(
			_ui_template_count() == 1,
			"GameInstance should own exactly one transition UITemplate."
		)

		var battle_scene := await _wait_for_battle_scene()
		_check(battle_scene != null, "The transition should open the battle scene.")
		if battle_scene:
			var scene_data := battle_scene.get_battle_data()
			_check(
				scene_data.get("trainer_name") == "Ranger Mira",
				"The battle scene should receive the pending launch data."
			)
			_check(
				scene_data.get("nested", {}).get("seed") == 7,
				"The battle scene should receive the protected data copy."
			)
			var camera := battle_scene.get_node_or_null(^"BattleCamera") as Camera3D
			_check(camera != null, "The battle camera should remain available.")
			if camera:
				_check(
					is_equal_approx(camera.fov, 42.0) or camera.fov < 42.0,
					"The intro should animate toward the preserved 42-degree FOV."
				)
			var player_spawn := battle_scene.get_node_or_null(
				^"SpawnPoints/PlayerSpawn"
			) as Marker3D
			var opponent_spawn := battle_scene.get_node_or_null(
				^"SpawnPoints/OpponentSpawn"
			) as Marker3D
			_check(
				player_spawn != null
				and player_spawn.position.is_equal_approx(Vector3(-2.35, 0.0, 1.45)),
				"The player spawn transform should survive the presentation update."
			)
			_check(
				opponent_spawn != null
				and opponent_spawn.position.is_equal_approx(Vector3(2.25, 0.0, -1.85)),
				"The opponent spawn transform should survive the presentation update."
			)

		await _wait_for_transition_completion()
		_check(
			not GameInstance.is_battle_start_in_progress(),
			"The transition should release its start-in-progress guard."
		)
		_check(
			_ui_template_count() == 0,
			"The transition UITemplate should close after revealing battle."
		)
		_check(
			GameInstance.get_pending_battle_data().is_empty(),
			"Pending data should be consumed when the battle scene enters."
		)
		_check(
			GameInstance.get_active_battle_data().get("trainer_name") == "Ranger Mira",
			"Consumed launch data should remain available as active battle data."
		)
		_check(
			not GameInstance.is_player_movement_enabled(),
			"Overworld movement should remain locked while battle is active."
		)

		if battle_scene:
			await _wait_for_local_intro(battle_scene)
			var overlay := battle_scene.get_node_or_null(
				^"BattleIntroUI/IntroOverlay"
			) as Control
			_check(
				overlay != null and not overlay.visible,
				"The battle-local intro overlay should retire after its animation."
			)
			var camera := battle_scene.get_node_or_null(^"BattleCamera") as Camera3D
			if camera:
				_check(
					camera.position.is_equal_approx(Vector3(0.0, 4.7, 8.7)),
					"The intro should restore the exact battle camera position."
				)
				_check(
					is_equal_approx(camera.fov, 42.0),
					"The intro should restore the exact battle camera FOV."
				)

		GameInstance.set_player_movement_enabled(true)
		if failures.is_empty():
			print(
				"Battle start smoke test passed: data handoff, template transition, "
				+ "scene swap, intro effects, camera, spawns, and cleanup verified."
			)
			get_tree().quit(0)
			return

		for failure in failures:
			push_error("Battle start smoke test failed: %s" % failure)
		get_tree().quit(1)


	func _wait_for_battle_scene() -> BattleScene:
		for _frame in range(180):
			await get_tree().process_frame
			var current_scene := get_tree().current_scene
			if current_scene is BattleScene:
				return current_scene as BattleScene
		return null


	func _wait_for_transition_completion() -> void:
		for _frame in range(180):
			await get_tree().process_frame
			if (
				not GameInstance.is_battle_start_in_progress()
				and _ui_template_count() == 0
			):
				return


	func _wait_for_local_intro(battle_scene: BattleScene) -> void:
		for _frame in range(120):
			await get_tree().process_frame
			var overlay := battle_scene.get_node_or_null(
				^"BattleIntroUI/IntroOverlay"
			) as Control
			if overlay and not overlay.visible:
				return


	func _ui_template_count() -> int:
		var count := 0
		for child in UIManager.get_children():
			if child is UITemplate:
				count += 1
		return count


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


func _ready() -> void:
	_start_watcher.call_deferred()


func _start_watcher() -> void:
	var watcher := BattleStartWatcher.new()
	watcher.name = "BattleStartWatcher"
	get_tree().root.add_child(watcher)
	watcher.run.call_deferred()
