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
				== "res://tests/scenes/battle_start_smoke_test.tscn",
			"GameInstance should capture the implicit source scene path."
		)
		_check(
			pending.get("return_scene_path")
				== "res://tests/scenes/battle_start_smoke_test.tscn",
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
		_verify_authored_sprite_framing(battle_scene)
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
			player_name != null and player_name.text == "Palkia",
			"The HUD should use party slot one as implicit player display data."
		)
		_check(
			player_level != null and player_level.text == "Lv. 3",
			"The HUD should display the player PCL level."
		)
		_check(
			opponent_name != null and opponent_name.text == "Pikachu",
			"The HUD should display explicit opponent-party data."
		)
		_check(
			opponent_level != null and opponent_level.text == "Lv. 7",
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


	func _verify_authored_sprite_framing(battle_scene: BattleScene) -> void:
		var presenter := battle_scene.get_node_or_null(
			^"BattleActors/BattleSpritePresenter"
		)
		var camera := battle_scene.get_node_or_null(^"BattleCamera") as Camera3D
		var player_spawn := battle_scene.get_node_or_null(
			^"SpawnPoints/PlayerSpawn"
		) as Marker3D
		var opponent_spawn := battle_scene.get_node_or_null(
			^"SpawnPoints/OpponentSpawn"
		) as Marker3D
		var player_shadow := battle_scene.get_node_or_null(
			^"ActorShadows/PlayerShadow"
		) as MeshInstance3D
		var opponent_shadow := battle_scene.get_node_or_null(
			^"ActorShadows/OpponentShadow"
		) as MeshInstance3D
		_check(
			presenter != null
			and camera != null
			and player_spawn != null
			and opponent_spawn != null,
			"The authored battle scene should expose its sprite framing dependencies."
		)
		if presenter == null or camera == null or player_spawn == null or opponent_spawn == null:
			return

		var contrast_value: Variant = presenter.call("present_battlers", {
			"memberId": "player-palkia",
			"pokemonId": 484,
			"spriteId": "palkia",
		}, {
			"memberId": "kyle-wooper",
			"pokemonId": 194,
			"spriteId": "wooper",
		})
		var contrast := contrast_value as Dictionary
		var palkia_scale := contrast.get("player", {}) as Dictionary
		var wooper_scale := contrast.get("opponent", {}) as Dictionary
		palkia_scale = palkia_scale.get("scale", {}) as Dictionary
		wooper_scale = wooper_scale.get("scale", {}) as Dictionary
		_check(
			palkia_scale.get("source") == "pokedex"
			and wooper_scale.get("source") == "pokedex",
			"The authored camera should receive Pokédex-driven battler proportions."
		)
		_check(
			player_shadow != null
			and opponent_shadow != null
			and player_shadow.visible
			and opponent_shadow.visible
			and float(player_shadow.get_meta("battle_shadow_width_m", 0.0)) > 0.0
			and float(opponent_shadow.get_meta("battle_shadow_width_m", 0.0)) > 0.0,
			"The authored ground shadows should match each battler's visible width."
		)

		var extremes_value: Variant = presenter.call("present_battlers", {
			"memberId": "player-joltik",
			"pokemonId": 595,
			"spriteId": "joltik",
		}, {
			"memberId": "opponent-wailord",
			"pokemonId": 321,
			"spriteId": "wailord",
		})
		var extremes := extremes_value as Dictionary
		var joltik_result := extremes.get("player", {}) as Dictionary
		var wailord_result := extremes.get("opponent", {}) as Dictionary
		var joltik_scale := joltik_result.get("scale", {}) as Dictionary
		var wailord_scale := wailord_result.get("scale", {}) as Dictionary
		var joltik_sprite := player_spawn.get_node(
			^"PlayerBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		var wailord_sprite := opponent_spawn.get_node(
			^"OpponentBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		var camera_right := camera.global_transform.basis.x.normalized()
		var camera_up := camera.global_transform.basis.y.normalized()
		var joltik_half_height := float(joltik_scale.get("visible_height_m", 0.0)) * 0.5
		var joltik_top := camera.unproject_position(
			joltik_sprite.global_position + camera_up * joltik_half_height
		)
		var joltik_bottom := camera.unproject_position(
			joltik_sprite.global_position - camera_up * joltik_half_height
		)
		var wailord_half_height := float(wailord_scale.get("visible_height_m", 0.0)) * 0.5
		var wailord_left_extent := float(wailord_scale.get("visible_left_extent_m", 0.0))
		var wailord_right_extent := float(wailord_scale.get("visible_right_extent_m", 0.0))
		var wailord_top := camera.unproject_position(
			wailord_sprite.global_position + camera_up * wailord_half_height
		)
		var wailord_bottom := camera.unproject_position(
			wailord_sprite.global_position - camera_up * wailord_half_height
		)
		var wailord_left := camera.unproject_position(
			wailord_sprite.global_position - camera_right * wailord_left_extent
		)
		var wailord_right := camera.unproject_position(
			wailord_sprite.global_position + camera_right * wailord_right_extent
		)
		var viewport_rect := camera.get_viewport().get_visible_rect()
		_check(
			joltik_bottom.y - joltik_top.y >= 56.0,
			"The smallest supported battlers should remain readable on a phone."
		)
		_check(
			wailord_top.y >= viewport_rect.position.y + 16.0
			and wailord_bottom.y > wailord_top.y
			and wailord_left.x >= viewport_rect.position.x
			and wailord_right.x <= viewport_rect.end.x,
			"The exaggerated largest billboard should fit the current authored camera frame."
		)
		var battle_ui := battle_scene.get_battle_ui()
		var opponent_status := (
			battle_ui.get_node_or_null(^"BattleUIOverlay/OpponentStatus") as Control
			if battle_ui != null
			else null
		)
		var wailord_ground := camera.unproject_position(opponent_spawn.global_position)
		var wailord_envelope_top := camera.unproject_position(
			opponent_spawn.global_position
			+ camera_up * float(wailord_scale.get("visible_height_m", 0.0))
		)
		var wailord_rect := Rect2(
			Vector2(
				minf(wailord_left.x, wailord_right.x),
				minf(wailord_envelope_top.y, wailord_ground.y)
			),
			Vector2(
				absf(wailord_right.x - wailord_left.x),
				absf(wailord_ground.y - wailord_envelope_top.y)
			)
		)
		_check(
			opponent_status != null
			and not wailord_rect.intersects(opponent_status.get_global_rect().grow(3.0)),
			"Huge opponents should keep a visible gap from the compact status card."
		)

		var wide_value: Variant = presenter.call("present_battlers", {
			"memberId": "player-dondozo",
			"pokemonId": 977,
			"spriteId": "dondozo",
		}, {
			"memberId": "opponent-wailord",
			"pokemonId": 321,
			"spriteId": "wailord",
		})
		var wide := wide_value as Dictionary
		var dondozo_result := wide.get("player", {}) as Dictionary
		var dondozo_scale := dondozo_result.get("scale", {}) as Dictionary
		var dondozo_sprite := player_spawn.get_node(
			^"PlayerBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		var dondozo_left_extent := float(dondozo_scale.get("visible_left_extent_m", 0.0))
		var dondozo_right_extent := float(dondozo_scale.get("visible_right_extent_m", 0.0))
		var dondozo_left := camera.unproject_position(
			dondozo_sprite.global_position - camera_right * dondozo_left_extent
		)
		var dondozo_right := camera.unproject_position(
			dondozo_sprite.global_position + camera_right * dondozo_right_extent
		)
		_check(
			dondozo_left.x >= viewport_rect.position.x
			and dondozo_right.x <= viewport_rect.end.x,
			"Aspect-aware fitting should keep the widest player billboard on-screen."
		)

		var offset_value: Variant = presenter.call("present_battlers", {
			"memberId": "player-unown",
			"pokemonId": 201,
			"spriteId": "unown",
		}, {
			"memberId": "kyle-wooper",
			"pokemonId": 194,
			"spriteId": "wooper",
		})
		var offset_result := offset_value as Dictionary
		var unown_result := offset_result.get("player", {}) as Dictionary
		var unown_scale := unown_result.get("scale", {}) as Dictionary
		var unown_sprite := player_spawn.get_node(
			^"PlayerBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		var unown_left := camera.unproject_position(
			unown_sprite.global_position
			- camera_right * float(unown_scale.get("visible_left_extent_m", 0.0))
		)
		var unown_right := camera.unproject_position(
			unown_sprite.global_position
			+ camera_right * float(unown_scale.get("visible_right_extent_m", 0.0))
		)
		_check(
			unown_left.x >= viewport_rect.position.x
			and unown_right.x <= viewport_rect.end.x,
			"Camera fitting should include asymmetric all-frame alpha offsets."
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
