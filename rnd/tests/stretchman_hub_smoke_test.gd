extends Node3D

const PlayerScene := preload("res://demo/player.tscn")
const StretchmanScene := preload("res://rnd/stretch/npc/stretchman.tscn")

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	var loot_boxes := StretchGoalSystem.get_loot_box_catalog()
	var funded_stretch := original_stretch.duplicate(true)
	funded_stretch["balance"] = int((loot_boxes[0] as Dictionary).get("price", 0))
	funded_stretch["completed_routes"] = []
	funded_stretch["active_destination"] = {}
	funded_stretch["run_defeated_ids"] = []
	_check(
		StretchGoalSystem.load_save_data(funded_stretch),
		"The hub fixture should fund one live-catalog loot-box purchase."
	)
	var player := PlayerScene.instantiate() as PlayerCharacter
	player.name = "Player"
	add_child(player)
	var stretchman := StretchmanScene.instantiate() as PFRCharacter
	stretchman.name = "Stretchman"
	stretchman.position = Vector3(0.0, 0.0, -2.0)
	add_child(stretchman)
	await get_tree().process_frame

	_check(stretchman.can_interact(player), "Stretchman should advertise interaction to the shared dispatcher.")
	_check(stretchman.get_interaction_prompt(player) == "Talk to Stretchman", "Stretchman's interaction prompt should identify him.")
	_check(stretchman.interact(player), "Stretchman should accept an available interaction.")
	await get_tree().process_frame
	_check(not GameInstance.is_player_movement_enabled(), "The open Stretchman hub should own the movement lock.")

	var hub := _find_hub()
	_check(hub != null, "Talking to Stretchman should open the stretch goal hub UI.")
	if hub != null:
		var hub_panel := hub.find_child("HubPanel", true, false) as PanelContainer
		_check(
			hub_panel != null
			and hub_panel.get_combined_minimum_size().y <= hub_panel.size.y + 1.0,
			"Stretchman's complete hub should fit the project's 960x540 viewport."
		)
		var offers := hub.find_child("Offers", true, false) as ItemList
		var filter := hub.find_child("Filter", true, false) as OptionButton
		var sort := hub.find_child("PokemonSort", true, false) as OptionButton
		var sort_row := hub.find_child("PokemonSortRow", true, false) as HBoxContainer
		var search := hub.find_child("Search", true, false) as LineEdit
		_check(offers != null and offers.item_count == 2223, "The default item tab should render the complete item catalog in one navigable list.")
		_check(filter != null and filter.item_count > 10, "The item shop should expose price and category filters.")
		_check(
			sort != null and sort_row != null and not sort_row.visible,
			"The Pokemon-only sort control should stay out of the item shop."
		)
		search.grab_focus()
		await get_tree().process_frame
		search.text = "p"
		await get_tree().process_frame
		_check(
			search.has_focus(),
			"Typing a search character should not transfer focus to Stretchman's results."
		)
		search.text = "poton"
		await get_tree().process_frame
		_check(
			search.has_focus() and _list_contains(offers, "Potion"),
			"Stretchman search should retain focus across multiple characters and recover a typo."
		)
		search.text = "exp share"
		await get_tree().process_frame
		_check(
			_list_contains(offers, "Exp. Share")
			and _list_contains(offers, "$100,000"),
			"The item shop should visibly list the Exp. Share at $100,000."
		)
		hub._select_category("pokemon")
		_check(offers.item_count == 1025, "The Pokemon tab should render every default species offer.")
		_check(filter.item_count > 10, "The Pokemon shop should expose price, appeal, rarity, and tier filters.")
		_check(
			sort_row.visible and sort.item_count == 5,
			"The Pokemon shop should expose Pokedex, both price, and both coolness sort directions."
		)
		_select_filter(sort, "price_ascending")
		hub._on_sort_selected(sort.selected)
		_check(
			_entries_are_sorted_by_price(hub._visible_entries, true),
			"Price Low to High should order every visible Pokemon by ascending price."
		)
		_select_filter(sort, "price_descending")
		hub._on_sort_selected(sort.selected)
		_check(
			_entries_are_sorted_by_price(hub._visible_entries, false),
			"Price High to Low should order every visible Pokemon by descending price."
		)
		_select_filter(sort, "coolness_descending")
		hub._on_sort_selected(sort.selected)
		_check(
			_entries_are_sorted_by_coolness(hub, false),
			"Coolest to Lamest should order every visible Pokemon by descending coolness."
		)
		_select_filter(sort, "coolness_ascending")
		hub._on_sort_selected(sort.selected)
		_check(
			_entries_are_sorted_by_coolness(hub, true),
			"Lamest to Coolest should provide the reverse coolness direction."
		)
		_select_filter(sort, "pokedex")
		hub._on_sort_selected(sort.selected)
		for _frame in 8:
			await get_tree().process_frame
		var preview := hub.find_child("PokemonAnimatedPreview", true, false) as TextureRect
		_check(offers.get_item_icon(0) != null, "Visible Pokemon offers should use a still GIF frame as their icon.")
		_check(preview != null and preview.texture != null, "Selecting a Pokemon should show its animated GIF atlas in the preview pane.")
		_check(
			hub._preview_frames != null
			and hub._preview_frames.get_frame_count(&"idle") > 1,
			"The selected Pokemon preview should retain the full multi-frame animation."
		)
		search.text = "pikchu"
		await get_tree().process_frame
		_check(_list_contains(offers, "Pikachu"), "Elastic Pokemon search should recover a one-letter Pikachu typo.")
		search.text = ""
		_select_filter(filter, "appeal:legendary")
		hub._on_filter_selected(filter.selected)
		_check(
			offers.item_count > 0 and offers.item_count < 1025,
			"The Legendary filter should narrow the Pokemon catalog."
		)
		hub._select_category("loot_boxes")
		_check(offers.item_count >= 6, "The loot-box tab should expose many escalating tiers.")
		var collection_before_loot := CollectionSystem.get_collection_size()
		hub._activate_selected()
		await get_tree().process_frame
		var roulette := hub.find_child("LootBoxRoulette", true, false) as RNDLootBoxRoulette
		_check(roulette != null, "Buying a loot box should open the blocking spinning reel.")
		if roulette != null:
			var roulette_panel := roulette.find_child("Panel", true, false) as PanelContainer
			_check(
				roulette_panel != null
				and roulette_panel.get_combined_minimum_size().y <= roulette_panel.size.y + 1.0,
				"The loot reel should fit the project's 960x540 viewport."
			)
			roulette.reveal_immediately()
			for _reveal_frame in 2:
				await get_tree().process_frame
			var reel_status := roulette.find_child("LootBoxStatus", true, false) as Label
			var reel_window := roulette.find_child("ReelWindow", true, false) as Control
			var reel_track := roulette.find_child("ReelTrack", true, false) as HBoxContainer
			_check(
				reel_status != null and "You got" in reel_status.text,
				"The middle-knob result should reveal the committed Pokemon."
			)
			if reel_window != null and reel_track != null:
				var winner_card := reel_track.get_child(26) as Control
				var winner_center := winner_card.global_position.x + winner_card.size.x * 0.5
				var knob_center := reel_window.global_position.x + reel_window.size.x * 0.5
				_check(
					absf(winner_center - knob_center) < 1.0,
					"The awarded Pokemon card should stop against the physical middle knob "
					+ "(winner %.2f, knob %.2f)." % [winner_center, knob_center]
				)
			_check(
				CollectionSystem.get_collection_size() == collection_before_loot + 1,
				"The revealed loot-box Pokemon should already be in storage."
			)
			roulette._close()
			await get_tree().process_frame
		hub._select_category("gym")
		_check(offers.item_count == 8, "The gym tab should render Gym 1 through Gym 8.")
		hub._select_category("champion")
		_check(offers.item_count == 1, "The champion tab should render the sequential gauntlet.")
		hub._select_category("route")
		var action := hub.find_child("Action", true, false) as Button
		_check(
			offers.item_count == 40
			and _list_contains(offers, "Route 0")
			and _list_contains(offers, "Route 39"),
			"The route tab should render the complete Route 0–39 destination catalog."
		)
		_check(
			action != null
			and not action.disabled
			and action.text == "Travel to Route 0"
			and "AVAILABLE" in offers.get_item_text(0),
			"Route 0 should be the fresh player's available authored destination."
		)
		offers.select(1)
		hub._on_item_selected(1)
		_check(
			action != null
			and action.disabled
			and "finish Route 0" in action.text
			and "LOCKED" in offers.get_item_text(1),
			"Route 1 should visibly stay locked until the player reaches Route 0's end."
		)
		_check(action != null and action.focus_mode != Control.FOCUS_NONE, "The selected action should be keyboard/gamepad focusable.")
		_check(search != null and search.focus_mode != Control.FOCUS_NONE, "Catalog search should be keyboard/gamepad focusable.")
		_check(filter != null and filter.focus_mode != Control.FOCUS_NONE, "Catalog filters should be keyboard/gamepad focusable.")
		_check(sort != null and sort.focus_mode != Control.FOCUS_NONE, "Pokemon sorting should be keyboard/gamepad focusable.")
		hub.close_hub()
		await get_tree().process_frame
	_check(GameInstance.is_player_movement_enabled(), "Closing Stretchman's hub should restore movement.")
	CollectionSystem.load_save_data(original_collection)
	StretchGoalSystem.load_save_data(original_stretch)

	if _failures.is_empty():
		print(
			"Stretchman hub smoke test passed: NPC dispatch, lock ownership, complete "
			+ "tabs, retained search focus, fuzzy filters, price/coolness sorting, GIF "
			+ "art, loot reel, Route 0–39 lock states, focus navigation, and cleanup verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Stretchman hub smoke test failed: %s" % failure)
	get_tree().quit(1)


func _find_hub() -> RNDStretchGoalUI:
	for child: Node in UIManager.get_children():
		if child is RNDStretchGoalUI:
			return child as RNDStretchGoalUI
	return null


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


func _entries_are_sorted_by_price(entries: Array[Dictionary], ascending: bool) -> bool:
	for index in range(1, entries.size()):
		var previous := int(entries[index - 1].get("price", 0))
		var current := int(entries[index].get("price", 0))
		if (ascending and previous > current) or (not ascending and previous < current):
			return false
	return true


func _entries_are_sorted_by_coolness(hub: RNDStretchGoalUI, ascending: bool) -> bool:
	for index in range(1, hub._visible_entries.size()):
		var previous := hub._pokemon_coolness_score(hub._visible_entries[index - 1])
		var current := hub._pokemon_coolness_score(hub._visible_entries[index])
		if (ascending and previous > current) or (not ascending and previous < current):
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
