extends Node

const Catalog := preload("res://game/progression/move_learning/move_learnset_catalog.gd")
const MoveLearningUI := preload("res://game/progression/move_learning/move_learning_ui.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_move_learning := MoveLearningSystem.get_save_data()
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(false)
	MoveLearningSystem.reset_for_testing()

	_test_generated_catalog()
	await _test_replacement_ui()
	await _test_level_change_queue_and_choices()

	MoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	MoveLearningSystem.load_save_data(original_move_learning)
	MoveLearningSystem.finish_save_restore()
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)

	if _failures.is_empty():
		print(
			"Move-learning smoke test passed: generated PokeAPI learnsets, "
			+ "form fallback, touch replacement UI, open-slot learning, four-move "
			+ "replacement/decline, multi-move levels, and pending persistence verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Move-learning smoke test failed: %s" % failure)
	get_tree().quit(1)


func _test_generated_catalog() -> void:
	var palkia_level_24 := Catalog.get_moves_learned_between(484, 23, 24)
	_check(
		palkia_level_24.size() == 1
		and String(palkia_level_24[0].get("moveId", "")) == "slash"
		and String(palkia_level_24[0].get("type", "")) == "Normal",
		"Palkia should learn the validated Scarlet/Violet Slash at level 24."
	)
	var caterpie_source := Catalog.get_learnset_source(10)
	_check(
		String(caterpie_source.get("versionGroup", ""))
		== "brilliant-diamond-shining-pearl",
		"Caterpie should deterministically fall back to its newest available conventional learnset."
	)
	var gmax_source := Catalog.get_learnset_source(10195)
	_check(
		int(gmax_source.get("sourcePokemonId", 0)) == 3,
		"A form with no independent PokeAPI moves should inherit its default species-form learnset."
	)
	var wooper_level_12 := Catalog.get_moves_learned_between(194, 11, 12)
	_check(
		wooper_level_12.size() == 2
		and String(wooper_level_12[0].get("moveId", "")) == "haze"
		and String(wooper_level_12[1].get("moveId", "")) == "mist",
		"All moves learned at the same crossed level should be returned in stable order."
	)


func _test_replacement_ui() -> void:
	var ui := MoveLearningUI.instantiate() as MoveLearningUI
	add_child(ui)
	var ui_state := {"selected_index": -99, "continued": false}
	ui.replacement_selected.connect(
		func(index: int) -> void: ui_state["selected_index"] = index
	)
	ui.continued.connect(func() -> void: ui_state["continued"] = true)
	var request := {
		"pokemonName": "Palkia",
		"currentLevel": 24,
		"learnedLevel": 24,
		"moveName": "Slash",
		"moveType": "Normal",
		"currentMoves": [
			{"moveId": "scaryface", "name": "Scary Face", "type": "Normal"},
			{"moveId": "waterpulse", "name": "Water Pulse", "type": "Water"},
			{"moveId": "dragonbreath", "name": "Dragon Breath", "type": "Dragon"},
			{"moveId": "ancientpower", "name": "Ancient Power", "type": "Rock"},
		],
	}
	ui.show_replacement(request)
	await get_tree().process_frame
	var move_buttons := ui.get_move_buttons()
	_check(move_buttons.size() == 4, "The replacement prompt should expose all four equipped moves.")
	_check(
		ui.keep_button.visible and not ui.continue_button.visible,
		"The replacement prompt should offer an explicit keep-current-moves choice."
	)
	if move_buttons.size() == 4:
		move_buttons[1].pressed.emit()
	await get_tree().process_frame
	_check(
		int(ui_state["selected_index"]) == 1,
		"A move button should return its exact replacement slot."
	)

	ui.show_result(request, {
		"status": "replaced",
		"forgottenMoveName": "Water Pulse",
	})
	ui.continue_button.pressed.emit()
	await get_tree().process_frame
	_check(
		bool(ui_state["continued"]),
		"The learned-move result should expose a keyboard/touch Continue path."
	)
	ui.queue_free()
	await get_tree().process_frame


func _test_level_change_queue_and_choices() -> void:
	CollectionSystem.clear_collection()
	MoveLearningSystem.reset_for_testing()

	var bulbasaur := CollectionSystem.add_pokemon(1, 8, 1.0, -1, 1)
	var bulbasaur_id := String(bulbasaur.get("pclID", ""))
	_check(
		CollectionSystem.set_equipped_moves(bulbasaur_id, ["tackle", "growl"]),
		"The open-slot fixture should equip two valid moves."
	)
	_grant_to_level(bulbasaur_id, 9)
	var pending := MoveLearningSystem.get_pending_requests()
	_check(
		pending.size() == 1
		and String(pending[0].get("moveId", "")) == "leechseed",
		"Crossing Bulbasaur's level 9 threshold should queue Leech Seed once."
	)
	var auto_result := MoveLearningSystem.resolve_next_pending()
	_check(
		String(auto_result.get("status", "")) == "learned"
		and CollectionSystem.get_battle_profile(bulbasaur_id).get("moves", []).size() == 3
		and "leechseed" in CollectionSystem.get_battle_profile(bulbasaur_id).get("moves", []),
		"A Pokémon with fewer than four moves should learn into its open slot."
	)

	var palkia := CollectionSystem.add_pokemon(484, 23, 1.0, -1, 2)
	var palkia_id := String(palkia.get("pclID", ""))
	var palkia_before: Array = (
		CollectionSystem.get_battle_profile(palkia_id).get("moves", []) as Array
	).duplicate()
	_grant_to_level(palkia_id, 24)
	var saved_pending := MoveLearningSystem.get_save_data()
	_check(
		(saved_pending.get("pending", []) as Array).size() == 1,
		"A full moveset should leave its new move pending for player choice."
	)
	MoveLearningSystem.reset_for_testing()
	_check(
		MoveLearningSystem.load_save_data(saved_pending),
		"A valid pending move choice should survive a progression reload."
	)
	var presentation_state := {
		"movement_was_locked": false,
		"result": {},
	}
	MoveLearningSystem.move_learning_resolved.connect(
		func(result: Dictionary) -> void:
			presentation_state["result"] = result.duplicate(true),
		CONNECT_ONE_SHOT
	)
	get_tree().process_frame.connect(
		_drive_system_replacement_ui.bind(1, presentation_state),
		CONNECT_ONE_SHOT
	)
	var presentation_ok := await MoveLearningSystem.present_pending_for_member(
		palkia_id
	)
	var replace_result := presentation_state["result"] as Dictionary
	var palkia_after := CollectionSystem.get_battle_profile(palkia_id).get("moves", []) as Array
	_check(
		presentation_ok
		and bool(presentation_state["movement_was_locked"])
		and GameInstance.is_player_movement_enabled()
		and String(replace_result.get("status", "")) == "replaced"
		and String(replace_result.get("forgottenMoveId", "")) == String(palkia_before[1])
		and String(palkia_after[1]) == "slash"
		and palkia_after.size() == 4,
		"The blocking prompt should lock movement, replace exactly slot two, persist Slash, and restore movement."
	)

	_check(
		CollectionSystem.update_instance_stats(palkia_id, {"level": 31}),
		"The decline fixture should advance Palkia to the level before Aqua Ring."
	)
	_grant_to_level(palkia_id, 32)
	var moves_before_decline := (
		CollectionSystem.get_battle_profile(palkia_id).get("moves", []) as Array
	).duplicate()
	var skip_result := MoveLearningSystem.resolve_next_pending(-1)
	_check(
		String(skip_result.get("status", "")) == "skipped"
		and CollectionSystem.get_battle_profile(palkia_id).get("moves", [])
		== moves_before_decline,
		"Keeping current moves should consume the prompt without changing the profile."
	)

	var wooper := CollectionSystem.add_pokemon(194, 11, 1.0, -1, 0)
	var wooper_id := String(wooper.get("pclID", ""))
	_grant_to_level(wooper_id, 12)
	pending = MoveLearningSystem.get_pending_requests()
	_check(
		pending.size() == 2
		and String(pending[0].get("moveId", "")) == "haze"
		and String(pending[1].get("moveId", "")) == "mist",
		"Two moves learned at level 12 should queue as two sequential decisions."
	)
	MoveLearningSystem.resolve_next_pending(0)
	MoveLearningSystem.resolve_next_pending(-1)
	_check(
		MoveLearningSystem.get_pending_requests().is_empty(),
		"Resolving both same-level moves should empty the queue exactly once."
	)

	var invalid_save := {"pending": [{
		"pcl_id": palkia_id,
		"pokemon_id": 484,
		"learned_level": 99,
		"move_id": "tackle",
	}]}
	_check(
		not MoveLearningSystem.validate_save_data(
			invalid_save,
			CollectionSystem.get_save_data()
		).is_empty(),
		"Impossible or tampered pending move choices should be rejected."
	)


func _drive_system_replacement_ui(
	replacement_index: int,
	presentation_state: Dictionary
) -> void:
	var ui := MoveLearningSystem.get_node_or_null(^"MoveLearningUI") as MoveLearningUI
	presentation_state["movement_was_locked"] = (
		not GameInstance.is_player_movement_enabled()
	)
	if ui == null:
		_failures.append("The move-learning system should instance its blocking UI.")
		return
	var buttons := ui.get_move_buttons()
	if replacement_index < 0 or replacement_index >= buttons.size():
		_failures.append("The system replacement UI should expose the requested move slot.")
		return
	buttons[replacement_index].pressed.emit()
	get_tree().process_frame.connect(
		_continue_system_move_learning_ui,
		CONNECT_ONE_SHOT
	)


func _continue_system_move_learning_ui() -> void:
	var ui := MoveLearningSystem.get_node_or_null(^"MoveLearningUI") as MoveLearningUI
	if ui == null or not ui.continue_button.visible:
		_failures.append("The applied move choice should show its result confirmation.")
		return
	ui.continue_button.pressed.emit()


func _grant_to_level(pcl_id: String, target_level: int) -> void:
	var pcl := CollectionSystem.get_pcl(pcl_id)
	var pokemon_id := int(pcl.get("pokemonId", 0))
	var current_xp := int((pcl.get("instanceStats", {}) as Dictionary).get("currentXp", 0))
	var target_xp := CreatureSystem.get_experience_for_level(pokemon_id, target_level)
	var result := CollectionSystem.grant_experience(pcl_id, target_xp - current_xp)
	_check(
		int(result.get("level", 0)) == target_level,
		"The fixture should reach level %d exactly." % target_level
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
