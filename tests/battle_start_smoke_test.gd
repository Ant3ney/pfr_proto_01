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
			_check(
				battle_scene.get_battle_ui() == null,
				"The battle HUD should stay hidden while the local intro is active."
			)
			_verify_battle_scene_entry(battle_scene)

		await _wait_for_transition_completion(battle_scene)
		_check(
			not GameInstance.is_battle_start_in_progress(),
			"The transition should release its start-in-progress guard."
		)
		_check(
			_ui_template_count() == 1,
			"The transition template should be replaced by one battle-HUD template."
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
			await _verify_battle_scene_after_intro(battle_scene)

		GameInstance.set_player_movement_enabled(true)
		if failures.is_empty():
			print(
				"Battle start smoke test passed: data handoff, template transition, "
				+ "scene swap, intro effects, HUD timing, commands, camera, and spawns verified."
			)
			get_tree().quit(0)
			return

		for failure in failures:
			push_error("Battle start smoke test failed: %s" % failure)
		get_tree().quit(1)


	func _verify_battle_scene_entry(battle_scene: BattleScene) -> void:
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


	func _verify_battle_scene_after_intro(battle_scene: BattleScene) -> void:
		await _wait_for_local_intro(battle_scene)
		await _wait_for_battle_ui(battle_scene)
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

		var battle_ui := battle_scene.get_battle_ui()
		_check(
			battle_ui != null and battle_ui.is_battle_ui_visible(),
			"The battle scene should own a visible template-driven HUD after intro."
		)
		if not battle_ui:
			return

		_check(
			not battle_ui.dialog_panel.visible,
			"The battle HUD should use its template presentation, not dialog panels."
		)
		var player_name := battle_ui.get_node_or_null(
			^"BattleUIOverlay/PlayerStatus/Margin/Content/Identity/PlayerName"
		) as Label
		var player_level := battle_ui.get_node_or_null(
			^"BattleUIOverlay/PlayerStatus/Margin/Content/Identity/PlayerLevel"
		) as Label
		var opponent_name := battle_ui.get_node_or_null(
			^"BattleUIOverlay/OpponentStatus/Margin/Content/Identity/OpponentName"
		) as Label
		var opponent_level := battle_ui.get_node_or_null(
			^"BattleUIOverlay/OpponentStatus/Margin/Content/Identity/OpponentLevel"
		) as Label
		_check(
			player_name != null and player_name.text == "PALKIA",
			"The HUD should use party slot one as implicit player display data."
		)
		_check(
			player_level != null and player_level.text == "LV. 3",
			"The HUD should display the player PCL level."
		)
		_check(
			opponent_name != null and opponent_name.text == "PIKACHU",
			"The HUD should display explicit opponent-party data."
		)
		_check(
			opponent_level != null and opponent_level.text == "LV. 7",
			"The HUD should display the explicit opponent level."
		)

		var selected_actions: Array[StringName] = []
		battle_scene.battle_action_selected.connect(
			func(action: StringName) -> void:
				selected_actions.append(action)
		)
		var fight_button := battle_ui.get_node_or_null(
			^"BattleUIOverlay/ActionTray/Margin/Actions/FightButton"
		) as Button
		_check(fight_button != null, "The battle HUD should expose its Fight command.")
		if fight_button:
			fight_button.pressed.emit()
		_check(
			selected_actions == [&"fight"],
			"Battle commands should flow through the template to BattleScene."
		)


	func _wait_for_battle_scene() -> BattleScene:
		for _frame in range(180):
			await get_tree().process_frame
			var current_scene := get_tree().current_scene
			if current_scene is BattleScene:
				return current_scene as BattleScene
		return null


	func _wait_for_transition_completion(battle_scene: BattleScene) -> void:
		for _frame in range(180):
			await get_tree().process_frame
			if (
				not GameInstance.is_battle_start_in_progress()
				and battle_scene != null
				and battle_scene.get_battle_ui() != null
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


	func _wait_for_battle_ui(battle_scene: BattleScene) -> void:
		for _frame in range(120):
			await get_tree().process_frame
			var battle_ui := battle_scene.get_battle_ui()
			if not battle_ui:
				continue
			var action_tray := battle_ui.get_node_or_null(
				^"BattleUIOverlay/ActionTray"
			) as Control
			if action_tray and action_tray.modulate.a >= 0.99:
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
