extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	GameInstance.set_player_movement_enabled(true)
	var working_stretch := original_stretch.duplicate(true)
	working_stretch["balance"] = 10_000
	_check(
		StretchGoalSystem.load_save_data(working_stretch),
		"The player-menu fixture should load a funded R&D economy."
	)
	_check(bool(StretchGoalSystem.buy_item("potion").get("ok", false)), "The fixture should buy its first Potion.")
	_check(bool(StretchGoalSystem.buy_item("potion").get("ok", false)), "The fixture should buy its second Potion.")
	var storage_pokemon := CollectionSystem.add_pokemon(10, 50, 1.0, -1, 0)
	var storage_pcl_id := String(storage_pokemon.get("pclID", ""))
	var branching_pokemon := CollectionSystem.add_pokemon(133, 50, 1.0, -1, 0)
	var branching_pcl_id := String(branching_pokemon.get("pclID", ""))
	_check(
		not bool((storage_pokemon.get("party", {}) as Dictionary).get("inParty", true)),
		"A newly bought-style Pokemon fixture should begin in PC storage."
	)

	await get_tree().process_frame
	var hud := $GameUI/PlayerMenuHUD as RNDPlayerMenuHUD
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
		var evolution_prompt := menu.find_child("EvolutionPrompt", true, false) as Control
		var evolution_choice := menu.find_child("EvolutionChoice", true, false) as OptionButton
		_check(
			menu._tab_buttons.size() == 3,
			"The player menu should expose Party & PC, Bag, and Pokedex tabs."
		)
		_check(
			_list_contains(entries, "PC  —  #0010 Caterpie"),
			"The Party & PC screen should show the complete storage collection."
		)
		_check(
			primary != null and primary.focus_mode != Control.FOCUS_NONE
			and party_slot != null and party_slot.focus_mode != Control.FOCUS_NONE
			and evolve_action != null and evolve_action.focus_mode != Control.FOCUS_NONE,
			"Party management controls should be keyboard/gamepad focusable."
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

		menu.select_tab(RNDPlayerMenuUI.TAB_BAG)
		_check(entries.item_count == 1 and _list_contains(entries, "x2  Potion"), "The Bag should show owned item quantities only.")
		search.text = "poton"
		await get_tree().process_frame
		_check(_list_contains(entries, "Potion"), "Bag search should recover a one-letter item typo.")
		var discard_result := StretchGoalSystem.discard_item("potion", 1)
		_check(bool(discard_result.get("ok", false)), "Owned item quantities should be manageable from the R&D inventory API.")
		_check(StretchGoalSystem.get_item_count("potion") == 1, "Discarding one item should leave the remaining stack intact.")

		menu.select_tab(RNDPlayerMenuUI.TAB_POKEDEX)
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
	StretchGoalSystem.load_save_data(original_stretch)
	GameInstance.set_player_movement_enabled(true)
	if _failures.is_empty():
		print(
			"R&D player menu HUD smoke test passed: persistent button, leveled evolution "
			+ "choices, Party/PC swaps, bag management, complete Pokedex, GIF art, focus, and cleanup verified."
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
