extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_economy := EconomySystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	GameInstance.set_player_movement_enabled(true)
	InventorySystem.reset_progress()
	_check(
		EconomySystem.load_save_data({
			"version": EconomyService.CURRENT_ECONOMY_VERSION,
			"balance": 10_000,
			"last_battle_reward": {},
		}),
		"The player-menu fixture should load a funded economy."
	)
	_check(bool(ShopSystem.buy_item("potion").get("ok", false)), "The fixture should buy its first Potion.")
	_check(bool(ShopSystem.buy_item("potion").get("ok", false)), "The fixture should buy its second Potion.")
	_check(
		bool(InventorySystem.claim_unique_item(
			"player-menu-xp-share",
			InventoryService.XP_SHARE_ITEM_KEY
		).get("ok", false)),
		"The player-menu fixture should receive one Exp. Share."
	)
	var storage_pokemon := CollectionSystem.add_pokemon(10, 50, 1.0, -1, 0)
	var storage_pcl_id := String(storage_pokemon.get("pclID", ""))
	var branching_pokemon := CollectionSystem.add_pokemon(133, 50, 1.0, -1, 0)
	var branching_pcl_id := String(branching_pokemon.get("pclID", ""))
	_check(
		not bool((storage_pokemon.get("party", {}) as Dictionary).get("inParty", true)),
		"A newly bought-style Pokemon fixture should begin in PC storage."
	)

	await get_tree().process_frame
	var hud := $GameUI/PlayerMenuHUD as PlayerMenuHUD
	var menu_button := $GameUI/PlayerMenuHUD/MenuButton as Button
	_check(hud != null, "The shared overworld GameUI should instance the R&D player-menu HUD.")
	_check(
		menu_button != null and menu_button.visible and not menu_button.disabled,
		"The player-menu HUD button should always be visible and pressable."
	)
	menu_button.pressed.emit()
	await get_tree().process_frame
	var menu := hud.get_open_menu()
	_check(menu != null, "Pressing the permanent HUD button should open the player menu.")
	_check(
		not GameInstance.is_player_movement_enabled(),
		"The open player menu should pause overworld movement."
	)
	if menu != null:
		var menu_panel := menu.find_child("MenuPanel", true, false) as PanelContainer
		_check(
			menu_panel != null
			and menu_panel.get_combined_minimum_size().y <= menu_panel.size.y + 1.0,
			"The complete player menu should fit the project's 960x540 viewport."
		)
		var entries := menu.find_child("Entries", true, false) as ItemList
		var search := menu.find_child("Search", true, false) as LineEdit
		var filter := menu.find_child("Filter", true, false) as OptionButton
		var primary := menu.find_child("PrimaryAction", true, false) as Button
		var party_slot := menu.find_child("PartySlot", true, false) as OptionButton
		var evolve_action := menu.find_child("EvolutionAction", true, false) as Button
		var held_item_action := menu.find_child("HeldItemAction", true, false) as Button
		var evolution_prompt := menu.find_child("EvolutionPrompt", true, false) as Control
		var evolution_choice := menu.find_child("EvolutionChoice", true, false) as OptionButton
		var save_data_button := menu.find_child("SaveData", true, false) as Button
		var save_data_prompt := menu.find_child("SaveDataPrompt", true, false) as Control
		var save_data_status := menu.find_child("SaveDataStatus", true, false) as Label
		var export_save := menu.find_child("ExportSaveJson", true, false) as Button
		var import_save := menu.find_child("ImportSaveJson", true, false) as Button
		var import_confirmation := menu.find_child(
			"ImportSaveConfirmation", true, false
		) as Control
		var import_confirmation_message := menu.find_child(
			"ImportSaveConfirmationMessage", true, false
		) as Label
		var confirm_save_import := menu.find_child(
			"ConfirmSaveImport", true, false
		) as Button
		var cloud_button := menu.find_child("CloudSave", true, false) as Button
		var cloud_prompt := menu.find_child("CloudSavePrompt", true, false) as Control
		var cloud_save_id := menu.find_child("CloudSaveId", true, false) as LineEdit
		var cloud_status := menu.find_child("CloudSaveStatus", true, false) as Label
		_check(
			menu._tab_buttons.size() == 3,
			"The player menu should expose Party & PC, Bag, and Pokedex tabs."
		)
		_check(
			cloud_button != null and cloud_button.focus_mode != Control.FOCUS_NONE,
			"The player menu should expose keyboard/gamepad cloud-save settings."
		)
		_check(
			save_data_button != null
			and save_data_button.focus_mode != Control.FOCUS_NONE
			and export_save != null
			and import_save != null,
			"The player menu should expose keyboard/gamepad JSON export and import controls."
		)
		menu.open_save_data()
		_check(
			save_data_prompt.visible
			and "Save ID is never included" in save_data_status.text,
			"Portable-save settings should explain that cloud credentials are excluded."
		)
		_check(
			menu.stage_json_import(
				ProgressionAutosave.get_export_json(),
				"player-menu-backup.json"
			)
			and import_confirmation.visible
			and confirm_save_import.has_focus()
			and "cloud Save ID is not changed" in import_confirmation_message.text,
			"A valid JSON file should require confirmation before replacing local progress."
		)
		import_confirmation.hide()
		menu.cancel_json_import()
		_check(
			"not changed" in save_data_status.text,
			"Canceling JSON import should clearly retain the current save."
		)
		menu.close_save_data()
		menu.open_cloud_save()
		_check(
			cloud_prompt.visible and cloud_save_id.secret,
			"Cloud-save settings should open with the private Save ID masked."
		)
		_check(
			search.virtual_keyboard_enabled and cloud_save_id.virtual_keyboard_enabled,
			"Player-menu text fields should request the touchscreen virtual keyboard."
		)
		cloud_save_id.release_focus()
		cloud_save_id.unedit()
		var cloud_touch := InputEventScreenTouch.new()
		cloud_touch.pressed = true
		cloud_save_id.gui_input.emit(cloud_touch)
		_check(
			cloud_save_id.has_focus() and cloud_save_id.is_editing(),
			"Tapping the cloud Save ID should explicitly enter focused edit mode."
		)
		cloud_save_id.text = "short"
		_check(
			not menu.apply_cloud_save_id()
			and "12" in cloud_status.text,
			"A guessable short Save ID should be rejected with an inline explanation."
		)
		cloud_save_id.text = "menu-smoke-private-save-id"
		_check(
			menu.apply_cloud_save_id()
			and CloudSaveSync.is_enabled()
			and menu.sync_cloud_save_now(),
			"A valid Save ID should opt in and allow an immediate background sync request."
		)
		menu.opt_out_of_cloud_save()
		_check(
			not CloudSaveSync.is_enabled()
			and cloud_save_id.text.is_empty(),
			"Opting out should forget the Save ID without disabling local progress saves."
		)
		menu.close_cloud_save()
		_check(
			_list_contains(entries, "PC  —  #0010 Caterpie"),
			"The Party & PC screen should show the complete storage collection."
		)
		_check(
			_list_contains(entries, " —  XP "),
			"Every captured-Pokemon row should expose its in-level XP progress."
		)
		_check(
			primary != null and primary.focus_mode != Control.FOCUS_NONE
			and party_slot != null and party_slot.focus_mode != Control.FOCUS_NONE
			and evolve_action != null and evolve_action.focus_mode != Control.FOCUS_NONE,
			"Party management controls should be keyboard/gamepad focusable."
		)
		_check(
			held_item_action != null and held_item_action.focus_mode != Control.FOCUS_NONE,
			"The held-item action should be keyboard/gamepad focusable."
		)
		menu._refresh_entries(storage_pcl_id)
		_check(
			evolve_action.visible and "Metapod" in evolve_action.text,
			"A Pokemon obtained above its evolution level should expose an Evolve action."
		)
		_check(
			menu.request_pokemon_evolution(storage_pcl_id)
			and evolution_prompt.visible
			and not evolution_choice.visible
			and evolution_choice.item_count == 1,
			"A single eligible evolution should open a focused confirmation prompt."
		)
		_check(
			menu.confirm_evolution_choice()
			and int(CollectionSystem.get_pcl(storage_pcl_id).get("pokemonId", 0)) == 11
			and not evolution_prompt.visible,
			"Confirming the menu action should evolve the same captured Pokemon."
		)
		_check(
			menu.request_pokemon_evolution(branching_pcl_id)
			and evolution_prompt.visible
			and evolution_choice.visible
			and evolution_choice.item_count == 8,
			"A branching evolution should prompt the player to choose its target Pokemon."
		)
		var selected_branch_id := int(evolution_choice.get_item_metadata(1))
		evolution_choice.select(1)
		_check(
			menu.confirm_evolution_choice()
			and int(CollectionSystem.get_pcl(branching_pcl_id).get("pokemonId", 0))
			== selected_branch_id,
			"The branching prompt should apply the player's selected evolution."
		)

		menu._refresh_entries(storage_pcl_id)
		_check(
			held_item_action.visible and "Give Exp. Share" in held_item_action.text,
			"An owned Exp. Share should expose a Give action on the selected Pokemon."
		)
		_check(
			menu.give_xp_share_to_pokemon(storage_pcl_id)
			and CollectionSystem.get_held_item(storage_pcl_id)
			== InventoryService.XP_SHARE_ITEM_KEY
			and InventorySystem.get_item_count(InventoryService.XP_SHARE_ITEM_KEY) == 0,
			"The menu should move the Exp. Share from the bag to the selected Pokemon."
		)
		var details := menu.find_child("Details", true, false) as RichTextLabel
		_check(
			details != null
			and "Level XP:" in details.text
			and "remaining to Lv." in details.text
			and "normal full award" in details.text,
			"A holder's detail panel should show level progress and explain benched versus active XP."
		)
		_check(
			menu.take_held_item_from_pokemon(storage_pcl_id)
			and CollectionSystem.get_held_item(storage_pcl_id).is_empty()
			and InventorySystem.get_item_count(InventoryService.XP_SHARE_ITEM_KEY) == 1,
			"The menu should return a held Exp. Share to the bag."
		)
		_check(
			menu.give_xp_share_to_pokemon(storage_pcl_id),
			"The Exp. Share should be equippable again after it is taken."
		)

		var original_slot_one := CollectionSystem.get_pcl_by_party_slot(1)
		var original_slot_one_id := String(original_slot_one.get("pclID", ""))
		_check(
			menu.move_pokemon_to_party_slot(storage_pcl_id, 1),
			"The menu should move a PC Pokemon into a full party slot."
		)
		_check(
			CollectionSystem.get_pcl_by_party_slot(1).get("pclID") == storage_pcl_id,
			"The selected PC Pokemon should occupy the requested party slot."
		)
		_check(
			not bool(CollectionSystem.get_pcl(original_slot_one_id).get("party", {}).get("inParty", true)),
			"The replaced party member should move safely into PC storage."
		)
		_check(
			menu.send_pokemon_to_pc(storage_pcl_id),
			"The menu should send a current party member back to PC storage."
		)
		_check(
			not bool(CollectionSystem.get_pcl(storage_pcl_id).get("party", {}).get("inParty", true)),
			"Sending a Pokemon to the PC should clear its party assignment."
		)
		_check(
			CollectionSystem.get_held_item(storage_pcl_id) == InventoryService.XP_SHARE_ITEM_KEY,
			"Moving a Pokemon between party and PC should preserve its held item."
		)

		menu.select_tab(PlayerMenuUI.TAB_BAG)
		_check(entries.item_count == 1 and _list_contains(entries, "x2  Potion"), "The Bag should show owned item quantities only.")
		search.grab_focus()
		await get_tree().process_frame
		search.text = "p"
		await get_tree().process_frame
		_check(
			search.has_focus(),
			"Typing a search character should not transfer focus to the player-menu results."
		)
		search.text = "poton"
		await get_tree().process_frame
		_check(
			search.has_focus() and _list_contains(entries, "Potion"),
			"Player-menu search should retain focus across multiple characters and recover a typo."
		)
		var discard_result := InventorySystem.discard_item("potion", 1)
		_check(bool(discard_result.get("ok", false)), "Owned item quantities should be manageable from the R&D inventory API.")
		_check(InventorySystem.get_item_count("potion") == 1, "Discarding one item should leave the remaining stack intact.")

		menu.select_tab(PlayerMenuUI.TAB_POKEDEX)
		_check(entries.item_count == 1025, "The Pokedex should expose all 1,025 default Pokemon.")
		search.text = "pikchu"
		await get_tree().process_frame
		_check(_list_contains(entries, "Pikachu"), "Pokedex search should recover a one-letter Pokemon typo.")
		search.text = ""
		await get_tree().process_frame
		for _frame in 8:
			await get_tree().process_frame
		var preview := menu.find_child("PokemonAnimatedPreview", true, false) as TextureRect
		_check(entries.get_item_icon(0) != null, "Visible Pokedex rows should reuse a still GIF frame as their icon.")
		_check(
			preview != null and preview.texture != null
			and menu._preview_frames != null
			and menu._preview_frames.get_frame_count(&"idle") > 1,
			"A selected Pokedex entry should show the existing animated GIF atlas."
		)
		_select_filter(filter, "dex:owned")
		menu._on_filter_selected(filter.selected)
		_check(
			entries.item_count > 0 and entries.item_count < 1025,
			"The Pokedex should filter the complete catalog down to owned species."
		)
		_check(
			search.focus_mode != Control.FOCUS_NONE and filter.focus_mode != Control.FOCUS_NONE,
			"Player-menu search and filters should remain keyboard/gamepad focusable."
		)
		menu.close_menu()
		await get_tree().process_frame
	_check(hud.get_open_menu() == null, "Closing should release the active player-menu instance.")
	_check(GameInstance.is_player_movement_enabled(), "Closing the player menu should restore its movement lock.")
	_check(not menu_button.disabled, "The permanent menu button should become pressable again after closing.")

	CollectionSystem.load_save_data(original_collection)
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	GameInstance.set_player_movement_enabled(true)
	if _failures.is_empty():
		print(
			"R&D player menu HUD smoke test passed: persistent button, retained search "
			+ "focus, leveled evolution choices, held-item transfers, Party/PC swaps, bag "
			+ "management, JSON transfer, cloud opt-in/out, complete Pokedex, GIF art, "
			+ "focus, and cleanup verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("R&D player menu HUD smoke test failed: %s" % failure)
	get_tree().quit(1)


func _list_contains(list: ItemList, fragment: String) -> bool:
	if list == null:
		return false
	for item_index in list.item_count:
		if fragment in list.get_item_text(item_index):
			return true
	return false


func _select_filter(filter: OptionButton, metadata: String) -> void:
	for item_index in filter.item_count:
		if String(filter.get_item_metadata(item_index)) == metadata:
			filter.select(item_index)
			return


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
