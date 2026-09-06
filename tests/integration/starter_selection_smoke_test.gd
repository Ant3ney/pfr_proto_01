extends Node

const TEST_SAVE_PATH := "user://pfr_rnd_starter_selection_smoke_test.json"
const PlayerMenuScene := preload("res://game/ui/player_menu/player_menu_ui.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_remove_test_save()
	var original_collection := CollectionSystem.get_save_data()
	var original_move_learning := MoveLearningSystem.get_save_data()
	var original_economy := EconomySystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	var original_challenge := ChallengeProgressionSystem.get_save_data()
	var original_save_path := ProgressionAutosave.save_path
	var original_starter_id := ProgressionAutosave.get_starter_pokemon_id()
	var original_movement := GameInstance.is_player_movement_enabled()
	ProgressionAutosave.save_path = TEST_SAVE_PATH
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(false)

	_prepare_progressed_fixture()
	_check(
		ProgressionAutosave.save_now(true) and FileAccess.file_exists(TEST_SAVE_PATH),
		"The reset fixture should begin with a real progression save on disk."
	)
	GameInstance.mark_standard_trainer_sight_encounter_consumed(
		"starter-reset-smoke-trainer"
	)
	_check(
		ProgressionAutosave.reset_all_progress(false),
		"The confirmed reset API should accept an idle overworld profile."
	)
	await get_tree().process_frame
	await get_tree().process_frame

	_check(
		not FileAccess.file_exists(TEST_SAVE_PATH),
		"Reset should erase the old disk checkpoint before a new starter is chosen."
	)
	_check(
		CollectionSystem.get_collection().is_empty()
		and MoveLearningSystem.get_pending_requests().is_empty(),
		"Reset should erase every captured Pokémon and pending move choice."
	)
	_check(
		EconomySystem.get_balance() == EconomyService.STARTING_BALANCE
		and InventorySystem.get_item_inventory().is_empty()
		and ChallengeProgressionSystem.get_earned_badges().is_empty()
		and not ChallengeProgressionSystem.is_champion_completed(),
		"Reset should restore money, inventory, badges, and Champion progression."
	)
	_check(
		not GameInstance.has_consumed_standard_trainer_sight_encounter(
			"starter-reset-smoke-trainer"
		),
		"Reset should clear process-only standard-trainer encounter history."
	)
	_check(
		ProgressionAutosave.is_profile_initialization_pending()
		and StarterSelectionSystem.is_selection_required()
		and not GameInstance.is_player_movement_enabled(),
		"A reset profile should remain unsaved and movement-locked until starter selection."
	)

	var choices := StarterSelectionSystem.get_starter_choices()
	_check(
		choices.size() == 3
		and int(choices[0].get("pokemonId", 0)) == 4
		and int(choices[1].get("pokemonId", 0)) == 656
		and int(choices[2].get("pokemonId", 0)) == 252,
		"The choices should be Gen-I Charmander, Gen-VI Froakie, and Gen-III Treecko."
	)
	var starter_ui := StarterSelectionSystem.get_active_ui()
	_check(starter_ui != null, "A fresh profile should show the mandatory starter picker.")
	if starter_ui != null:
		var starter_panel := starter_ui.get_node_or_null(^"Root/StarterPanel") as PanelContainer
		_check(
			starter_panel != null
			and starter_panel.get_combined_minimum_size().x <= starter_panel.size.x + 1.0
			and starter_panel.get_combined_minimum_size().y <= starter_panel.size.y + 1.0,
			"The three-card starter picker should fit the 960x540 design viewport."
		)
		_check(
			starter_ui.get_starter_buttons().size() == 3
			and starter_ui.get_animation_frame_count(4) > 1
			and starter_ui.get_animation_frame_count(656) > 1
			and starter_ui.get_animation_frame_count(252) > 1
			and starter_ui.is_processing(),
			"Every starter card should retain and play its exact multi-frame front GIF."
		)
		_check(
			starter_ui.request_choice(656)
			and starter_ui.is_confirmation_visible(),
			"Selecting Froakie should open a final starter confirmation."
		)
		starter_ui.confirm_choice()
	await get_tree().process_frame

	var fresh_collection := CollectionSystem.get_collection()
	var starter := fresh_collection[0] if fresh_collection.size() == 1 else {}
	var starter_stats := starter.get("instanceStats", {}) as Dictionary
	var starter_party := starter.get("party", {}) as Dictionary
	_check(
		fresh_collection.size() == 1
		and int(starter.get("pokemonId", 0)) == 656
		and int(starter_stats.get("level", 0)) == 5
		and bool(starter_party.get("inParty", false))
		and int(starter_party.get("slot", 0)) == 1
		and typeof(starter.get("battleProfile")) == TYPE_DICTIONARY,
		"Confirming Froakie should create one battle-ready Lv. 5 starter in party slot 1."
	)
	_check(
		FileAccess.file_exists(TEST_SAVE_PATH)
		and not ProgressionAutosave.is_profile_initialization_pending()
		and ProgressionAutosave.get_starter_pokemon_id() == 656
		and GameInstance.is_player_movement_enabled(),
		"Starter confirmation should initialize, save, and unlock the new profile."
	)
	_check_saved_profile()
	_test_schema_three_migration()
	await _test_scary_reset_warnings()

	StarterSelectionSystem.reset_for_testing()
	MoveLearningSystem.begin_save_restore()
	CollectionSystem.load_save_data(original_collection)
	MoveLearningSystem.load_save_data(original_move_learning)
	MoveLearningSystem.finish_save_restore()
	MoveLearningSystem.set_automatic_presentation_enabled_for_testing(true)
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	ChallengeProgressionSystem.load_save_data(original_challenge)
	StarterSelectionSystem.mark_profile_loaded(original_starter_id)
	ProgressionAutosave.save_path = original_save_path
	GameInstance.set_player_movement_enabled(original_movement)
	_remove_test_save()

	if _failures.is_empty():
		print(
			"Starter-selection smoke test passed: exact animated Charmander/Froakie/"
			+ "Treecko choices, Lv. 5 profile creation, complete reset, schema-6 save, "
			+ "and three-stage destructive warnings verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Starter-selection smoke test failed: %s" % failure)
	get_tree().quit(1)


func _prepare_progressed_fixture() -> void:
	MoveLearningSystem.reset_for_testing()
	CollectionSystem.clear_collection()
	var palkia := CollectionSystem.add_pokemon(484, 23, 1.0, -1, 1)
	var palkia_id := String(palkia.get("pclID", ""))
	MoveLearningSystem.reset_for_testing()
	CollectionSystem.update_instance_stats(palkia_id, {"level": 24})
	EconomySystem.load_save_data({
		"version": EconomyService.CURRENT_ECONOMY_VERSION,
		"balance": 9_999,
		"last_battle_reward": {},
	})
	InventorySystem.load_save_data({
		"item_quantities": {"potion": 3},
		"claimed_gifts": [],
	})
	ChallengeProgressionSystem.load_save_data({
		"earned_badges": [1, 2],
		"champion_completed": false,
		"completed_routes": [],
		"active_area_id": "",
		"run_defeated_ids": [],
		"run_id": 0,
	})
	_check(
		MoveLearningSystem.get_pending_requests().size() == 1,
		"The reset fixture should include an unresolved level-up move."
	)


func _check_saved_profile() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TEST_SAVE_PATH)
	)
	var payload := parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}
	var profile := payload.get("profile", {}) as Dictionary
	var collection := payload.get("collection", []) as Array
	_check(
		int(payload.get("schema_version", 0)) == 6
		and int(profile.get("starter_pokemon_id", 0)) == 656
		and collection.size() == 1
		and int((collection[0] as Dictionary).get("pokemonId", 0)) == 656,
		"The first post-choice checkpoint should persist schema 6 and the selected starter."
	)


func _test_schema_three_migration() -> void:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(TEST_SAVE_PATH)
	)
	if typeof(parsed) != TYPE_DICTIONARY:
		_failures.append("The schema-migration fixture should parse the saved profile.")
		return
	var legacy := (parsed as Dictionary).duplicate(true)
	legacy["schema_version"] = 3
	legacy.erase("profile")
	var economy := legacy.get("economy", {}) as Dictionary
	var inventory := legacy.get("inventory", {}) as Dictionary
	var challenge := legacy.get("challenge_progression", {}) as Dictionary
	legacy["stretch"] = {
		"economy_version": int(economy.get("version", 2)),
		"balance": int(economy.get("balance", 50)),
		"item_inventory": inventory.get("item_quantities", {}),
		"claimed_gifts": inventory.get("claimed_gifts", []),
		"earned_badges": challenge.get("earned_badges", []),
		"champion_cleared": bool(challenge.get("champion_completed", false)),
		"completed_routes": challenge.get("completed_routes", []),
		"active_destination": {},
		"run_defeated_ids": [],
		"run_id": int(challenge.get("run_id", 0)),
		"last_battle_reward": economy.get("last_battle_reward", {}),
	}
	legacy.erase("economy")
	legacy.erase("inventory")
	legacy.erase("challenge_progression")
	legacy.erase("save_meta")
	var file := FileAccess.open(TEST_SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_failures.append("The schema-migration fixture should reopen its temporary save.")
		return
	file.store_string(JSON.stringify(legacy, "\t"))
	file.flush()
	_check(
		ProgressionAutosave.load_now()
		and ProgressionAutosave.get_starter_pokemon_id() == 0
		and not StarterSelectionSystem.is_selection_required()
		and CollectionSystem.get_collection().size() == 1
		and int(CollectionSystem.get_collection()[0].get("pokemonId", 0)) == 656,
		"A schema-3 save should keep its collection and migrate without replaying onboarding."
	)


func _test_scary_reset_warnings() -> void:
	var menu := PlayerMenuScene.instantiate() as PlayerMenuUI
	add_child(menu)
	await get_tree().process_frame
	var reset_button := menu.find_child("ResetProgress", true, false) as Button
	var prompt := menu.find_child("ResetWarningPrompt", true, false) as Control
	var acknowledge_pokemon := menu.find_child(
		"AcknowledgePokemonDeletion", true, false
	) as CheckButton
	var acknowledge_backup := menu.find_child(
		"AcknowledgeBackupRequirement", true, false
	) as CheckButton
	var phrase := menu.find_child("ResetConfirmationPhrase", true, false) as LineEdit
	var final_button := menu.find_child("ConfirmProgressReset", true, false) as Button
	_check(
		reset_button != null and reset_button.visible and reset_button.focus_mode != Control.FOCUS_NONE,
		"The permanent player menu should expose a keyboard/gamepad-focusable reset button."
	)
	menu.open_reset_warnings()
	_check(
		prompt.visible and menu.get_reset_warning_step() == 1,
		"Reset should begin with the first full-screen danger warning."
	)
	_check(
		menu.advance_reset_warning() and menu.get_reset_warning_step() == 2,
		"Accepting warning one should reveal the detailed deletion disclaimer."
	)
	_check(
		not menu.advance_reset_warning(),
		"Warning two should block progress until both deletion acknowledgements are checked."
	)
	acknowledge_pokemon.button_pressed = true
	acknowledge_backup.button_pressed = true
	_check(
		"JSON backup" in acknowledge_backup.text
		and menu.advance_reset_warning()
		and menu.get_reset_warning_step() == 3,
		"Both acknowledgements should unlock the truthful final deletion warning."
	)
	phrase.release_focus()
	phrase.unedit()
	var reset_touch := InputEventScreenTouch.new()
	reset_touch.pressed = true
	phrase.gui_input.emit(reset_touch)
	_check(
		phrase.virtual_keyboard_enabled and phrase.has_focus() and phrase.is_editing(),
		"Tapping the reset phrase should explicitly enter touchscreen edit mode."
	)
	_check(final_button.disabled, "The final destructive button should begin disabled.")
	phrase.text = "reset"
	phrase.text_changed.emit(phrase.text)
	_check(final_button.disabled, "An incomplete confirmation phrase should remain rejected.")
	phrase.text = PlayerMenuUI.RESET_CONFIRMATION_PHRASE
	phrase.text_changed.emit(phrase.text)
	_check(not final_button.disabled, "Typing RESET FOREVER should unlock the last red button.")
	var signal_state := {"confirmed": false}
	menu.reset_progress_confirmed.connect(
		func() -> void: signal_state["confirmed"] = true
	)
	_check(
		menu.confirm_progress_reset() and bool(signal_state["confirmed"]),
		"Only the third warning and exact phrase should emit the reset confirmation."
	)
	menu.queue_free()
	await get_tree().process_frame


func _remove_test_save() -> void:
	if FileAccess.file_exists(TEST_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE_PATH))


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
