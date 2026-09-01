extends Node


class FakeBattleTransport:
	extends Node

	signal transport_completed(
		request_id: int,
		result: int,
		response_code: int,
		headers: PackedStringArray,
		body: PackedByteArray
	)

	var calls: Array[Dictionary] = []
	var active_request_id := -1


	func post_json_bytes(route: String, body: PackedByteArray, request_id: int) -> Error:
		active_request_id = request_id
		calls.append({"route": route, "body": body.duplicate(), "request_id": request_id})
		return OK


	func cancel_active_request() -> void:
		active_request_id = -1


	func complete(value: Dictionary, status := 200) -> void:
		var request_id := active_request_id
		active_request_id = -1
		transport_completed.emit(
			request_id,
			HTTPRequest.RESULT_SUCCESS,
			status,
			PackedStringArray(),
			JSON.stringify(value).to_utf8_buffer()
		)


class LifecycleWatcher:
	extends Node

	const ROUTE_0_PATH := "res://overworld/route_0/route_0.tscn"

	var failures: Array[String] = []
	var transport := FakeBattleTransport.new()
	var original_collection: Array[Dictionary] = []


	func run() -> void:
		original_collection = CollectionSystem.get_save_data()
		BattleSystem.reset_for_testing()
		_check(BattleSystem.set_transport_for_testing(transport), "Fake transport injection should succeed.")
		var accepted := GameInstance.startBattle({
			"encounter_type": "trainer",
			"trainer_name": "Trainer Kyle",
			"battle_scene_path": "res://battle/kyle_battle_scene.tscn",
			"encounter_id": "trainer-kyle-lake-v1",
			# This lifecycle fixture has no overworld player. Explicitly exercise
			# Kyle's authored Route 0 home while production calls return to the
			# implicitly captured source scene and pose.
			"return_scene_path": ROUTE_0_PATH,
		})
		_check(accepted, "Kyle's concrete battle scene should be accepted.")
		_check(not GameInstance.is_player_movement_enabled(), "Battle launch should lock movement.")

		var battle_scene := await _wait_for_battle_scene()
		_check(battle_scene != null, "The covered transition should load Kyle's battle scene.")
		if not battle_scene:
			await _finish()
			return
		_check(BattleSystem.get_state() == BattleSystem.State.CONNECTING, "The loaded scene should remain CONNECTING.")
		_check(GameInstance.is_battle_start_in_progress(), "The transition should remain active while connecting.")
		_check(battle_scene.get_battle_ui() == null, "The HUD should stay hidden before the initial response.")
		_check(transport.calls.size() == 1, "Battle entry should issue one start request.")

		var start_request := _request_at(0)
		transport.complete(_response(start_request, 0, false))
		await get_tree().process_frame
		_check(BattleSystem.get_state() == BattleSystem.State.PRESENTING, "Initial events should enter PRESENTING.")
		var covered_player_sprite := battle_scene.get_node_or_null(
			^"SpawnPoints/PlayerSpawn/PlayerBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		var covered_player_height := (
			float(covered_player_sprite.get_meta("battle_sprite_visible_height_m", 0.0))
			if covered_player_sprite != null
			else 0.0
		)

		await _wait_for_hud(battle_scene)
		var battle_ui := battle_scene.get_battle_ui()
		_check(battle_ui != null, "A valid initial response should reveal the battlefield and HUD.")
		var player_sprite := battle_scene.get_node_or_null(
			^"SpawnPoints/PlayerSpawn/PlayerBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		var opponent_sprite := battle_scene.get_node_or_null(
			^"SpawnPoints/OpponentSpawn/OpponentBattleSpriteActor/MotionRoot/AnimatedPokemon"
		) as AnimatedSprite3D
		_check(
			player_sprite != null
			and opponent_sprite != null
			and int(player_sprite.get_meta("battle_pokemon_id", 0)) == 484
			and int(opponent_sprite.get_meta("battle_pokemon_id", 0)) == 194
			and player_sprite.get_meta("battle_sprite_scale_source", "") == "pokedex"
			and opponent_sprite.get_meta("battle_sprite_scale_source", "") == "pokedex",
			"The revealed scene should present exact Pokédex-driven Palkia and Wooper proportions."
		)
		_check(
			player_sprite != null
			and float(player_sprite.get_meta("battle_sprite_visible_height_m", 0.0))
			>= covered_player_height - 0.0001,
			"Settling the intro camera should refresh rather than further shrink the covered battler."
		)
		if battle_ui:
			var fight_button := _battle_button(battle_ui, "FightButton")
			_check(fight_button != null and fight_button.disabled, "Choices should remain locked during event presentation.")

		await _wait_for_state(BattleSystem.State.AWAITING_PLAYER)
		_check(BattleSystem.get_state() == BattleSystem.State.AWAITING_PLAYER, "Events should finish before choices unlock.")
		if battle_ui:
			var fight_button := _battle_button(battle_ui, "FightButton")
			var bag_button := _battle_button(battle_ui, "BagButton")
			var party_button := _battle_button(battle_ui, "PartyButton")
			var run_button := _battle_button(battle_ui, "RunButton")
			_check(fight_button != null and not fight_button.disabled, "Move request should enable Fight.")
			_check(bag_button != null and bag_button.disabled, "Bag should remain visibly unavailable.")
			_check(party_button != null and not party_button.disabled, "Returned switch options should enable Pokémon.")
			_check(run_button != null and not run_button.disabled, "Allowed forfeit policy should enable Run.")

			fight_button.pressed.emit()
			await get_tree().process_frame
			_check(battle_scene.choice_overlay.visible, "Fight should open the server-provided move list.")
			_check(
				battle_scene.choice_overlay.options.get_child_count() == 4,
				"Palkia's four returned moves should be shown without local recomputation."
			)
			battle_scene.choice_overlay.cancel_button.pressed.emit()
			run_button.pressed.emit()
			await get_tree().process_frame
			_check(battle_scene.choice_overlay.confirm_button.visible, "Run should require confirmation.")
			battle_scene.choice_overlay.confirm_button.pressed.emit()

		await _wait_for_call_count(2)
		_check(transport.calls.size() == 2, "Confirmed Run should submit one action.")
		if transport.calls.size() >= 2:
			var action_request := _request_at(1)
			_check(String(action_request.action.type) == "forfeit", "Run confirmation should send typed forfeit.")
			transport.complete(_response(start_request, 1, true))

		await _wait_for_result_overlay(battle_scene)
		_check(
			battle_scene.choice_overlay.continue_button.visible,
			"The result should wait for Continue."
		)
		battle_scene.choice_overlay.continue_button.pressed.emit()
		_check(not GameInstance.is_player_movement_enabled(), "Movement should remain locked when return begins.")

		await _wait_for_scene_path(ROUTE_0_PATH)
		_check(
			get_tree().current_scene != null
			and get_tree().current_scene.scene_file_path == ROUTE_0_PATH,
			"Every result should return to Kyle's authored Route 0 home."
		)
		_check(GameInstance.is_player_movement_enabled(), "Movement should unlock only after the overworld is ready.")
		_check(
			GameInstance.is_encounter_suppressed("trainer-kyle-lake-v1"),
			"The just-finished Kyle encounter should be suppressed for this scene."
		)
		await get_tree().physics_frame
		var trainer := get_tree().current_scene.get_node_or_null(
			^"RouteTrainers/TrainerKyle"
		)
		if trainer:
			var behavior: Variant = trainer.get("npc_behavior")
			_check(
				behavior != null
				and int(behavior.get("_approach_state")) == TrainerBehavior.ApproachState.WAITING,
				"Kyle should return waiting for an optional manual rematch."
			)
			_check(
				GameInstance.has_consumed_standard_trainer_sight_encounter(
					"trainer-kyle-lake-v1"
				),
				"Kyle's standard sight challenge should be consumed after one battle."
			)
		else:
			_check(false, "Route 0 should contain Trainer Kyle in its ordered trainer group.")

		await _wait_for_state(BattleSystem.State.IDLE)
		if trainer:
			var player := get_tree().current_scene.get_node_or_null(^"Player") as PlayerCharacter
			_check(
				player != null and trainer.can_interact(player),
				"Kyle should remain interactable for a manual rematch."
			)
		await _finish()


	func _finish() -> void:
		BattleSystem.reset_for_testing()
		BattleSystem.restore_default_transport_after_testing()
		CollectionSystem.load_save_data(original_collection)
		if failures.is_empty():
			print(
				"Battle scene lifecycle test passed: covered connect, request-driven locked UI, "
				+ "event sequencing, confirmed forfeit, result Continue, ordered return, and "
					+ "one-time Kyle sight and manual rematch verified."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("Battle scene lifecycle test failed: %s" % failure)
		get_tree().quit(1)


	func _request_at(index: int) -> Dictionary:
		var call: Dictionary = transport.calls[index]
		return JSON.parse_string((call.body as PackedByteArray).get_string_from_utf8()) as Dictionary


	func _response(start_request: Dictionary, revision: int, ended: bool) -> Dictionary:
		var player := _party_snapshot(start_request.player.team as Array, true)
		var opponent := _party_snapshot(start_request.opponent.team as Array, false)
		var active_player := player[0] as Dictionary
		var moves: Array[Dictionary] = []
		for move_value: Variant in active_player.moves as Array:
			var move := move_value as Dictionary
			var choice := move.duplicate(true)
			choice.disabled = false
			moves.append(choice)
		var switches: Array[Dictionary] = []
		for member_value: Variant in player.slice(1):
			switches.append({"memberId": String((member_value as Dictionary).memberId)})
		var response := {
			"apiVersion": "v1",
			"engineVersion": "0.11.11",
			"formatVersion": "pfr-gen9-singles-v1",
			"battleId": "00000000-0000-4000-8000-000000000888",
			"revision": revision,
			"phase": "ended" if ended else "awaiting_player",
			"events": ["|win|Kyle"] if ended else ["|start", "|turn|1"],
			"request": null if ended else {
				"type": "move",
				"activeMemberId": active_player.memberId,
				"moves": moves,
				"switchOptions": switches,
			},
			"parties": {"player": player, "opponent": opponent},
		}
		if ended:
			response.result = {"winner": "opponent", "reason": "forfeit"}
		else:
			response.stateToken = "opaque-lifecycle-token-%d" % revision
		return response


	func _party_snapshot(team: Array, include_moves: bool) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for index in range(team.size()):
			var input := team[index] as Dictionary
			var member := {
				"memberId": String(input.memberId),
				"species": String(input.species),
				"nickname": String(input.species),
				"level": int(input.level),
				"hp": 100,
				"maxHp": 100,
				"normalizedHealth": 1.0,
				"fainted": false,
				"active": index == 0,
				"status": null,
			}
			if include_moves:
				var moves: Array[Dictionary] = []
				for move_index in range((input.moves as Array).size()):
					var move_id := String((input.moves as Array)[move_index])
					moves.append({
						"moveIndex": move_index + 1,
						"id": move_id,
						"name": move_id.capitalize(),
						"pp": 10,
						"maxPp": 10,
					})
				member.moves = moves
			result.append(member)
		return result


	func _battle_button(template: UITemplate, name: String) -> Button:
		return template.get_node_or_null(
			"BattleUIOverlay/ActionTray/Margin/Actions/%s" % name
		) as Button


	func _wait_for_battle_scene() -> BattleScene:
		for _frame in range(300):
			await get_tree().process_frame
			if get_tree().current_scene is BattleScene and transport.calls.size() >= 1:
				return get_tree().current_scene as BattleScene
		return null


	func _wait_for_hud(scene: BattleScene) -> void:
		for _frame in range(360):
			await get_tree().process_frame
			if scene != null and scene.get_battle_ui() != null:
				return


	func _wait_for_state(expected: int) -> void:
		for _frame in range(900):
			if BattleSystem.get_state() == expected:
				return
			await get_tree().process_frame


	func _wait_for_call_count(expected: int) -> void:
		for _frame in range(120):
			if transport.calls.size() >= expected:
				return
			await get_tree().process_frame


	func _wait_for_result_overlay(scene: BattleScene) -> void:
		for _frame in range(900):
			await get_tree().process_frame
			if scene != null and scene.choice_overlay.continue_button.visible:
				return


	func _wait_for_scene_path(path: String) -> void:
		for _frame in range(600):
			await get_tree().process_frame
			var scene := get_tree().current_scene
			if scene != null and scene.scene_file_path == path:
				return


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


func _ready() -> void:
	var watcher := LifecycleWatcher.new()
	watcher.name = "BattleSceneLifecycleWatcher"
	get_tree().root.add_child.call_deferred(watcher)
	watcher.run.call_deferred()
