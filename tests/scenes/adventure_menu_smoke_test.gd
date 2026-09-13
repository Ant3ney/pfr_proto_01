extends Node3D

const PLAYER_SCENE := preload("res://game/actors/player/player.tscn")
const STRETCHMAN_SCENE := preload("res://game/actors/npcs/residents/stretchman/stretchman.tscn")
const MENU_PATH := "res://game/ui/adventure_menu/adventure_menu.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_economy := EconomySystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	EconomySystem.load_save_data({
		"version": EconomyService.CURRENT_ECONOMY_VERSION,
		"balance": 1_000,
		"last_battle_reward": {},
	})
	InventorySystem.reset_progress()

	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	var stretchman := STRETCHMAN_SCENE.instantiate() as PFRCharacter
	add_child(player)
	add_child(stretchman)
	stretchman.position = Vector3(0, 0, -2)
	await get_tree().process_frame

	_check(stretchman is PFRCharacter, "Stretchman should remain an ordinary PFRCharacter NPC.")
	var behavior := stretchman.controller.npc_behavior as MenuNpcBehavior
	_check(behavior != null, "Stretchman should use the reusable MenuNpcBehavior resource.")
	if behavior != null:
		_check(behavior.menu_scene != null and behavior.menu_scene.resource_path == MENU_PATH, "The scene should assign Adventure Menu through the Inspector.")
		_check(behavior.interaction_prompt == "Talk to Stretchman", "The generic behavior should expose its Inspector-authored prompt.")
	_check(stretchman.can_interact(player), "Stretchman should advertise interaction through the shared NPC contract.")
	_check(stretchman.interact(player), "Stretchman should open his assigned generic menu.")
	await get_tree().process_frame

	var menu := _find_menu()
	_check(menu != null, "Interaction should add AdventureMenu beneath UIManager.")
	_check(not GameInstance.is_player_movement_enabled(), "MenuNpcBehavior should lock player movement while the menu is open.")
	if menu != null:
		_check(not menu.has_signal(&"travel_requested"), "The menu should launch areas directly without a Stretchman relay signal.")
		var panel := menu.find_child("HubPanel", true, false) as PanelContainer
		var offers := menu.find_child("Offers", true, false) as ItemList
		var search := menu.find_child("Search", true, false) as LineEdit
		var filter := menu.find_child("Filter", true, false) as OptionButton
		var action := menu.find_child("Action", true, false) as Button
		_check(panel != null and panel.get_combined_minimum_size().y <= panel.size.y + 1.0, "The complete menu should fit the 960x540 viewport.")
		_check(offers != null and offers.item_count == 2223, "The default tab should render the complete item catalog.")
		_check(search != null and filter != null and action != null, "Search, filters, and the selected action should remain native editable controls.")
		if offers != null:
			_verify_touch_scroll(menu, offers)
		if search != null and offers != null:
			search.text = "exp share"
			await get_tree().process_frame
			_check(_list_contains(offers, "Exp. Share") and _list_contains(offers, "$100,000"), "Item search should expose the persistent Exp. Share offer.")
		menu._select_category(AdventureMenu.CATEGORY_POKEMON)
		_check(offers != null and offers.item_count == 1025, "The Pokemon tab should render every catalog species.")
		menu._select_category(AdventureMenu.CATEGORY_ROUTES)
		_check(offers != null and offers.item_count == StandaloneAreaCatalog.ROUTE_COUNT, "The Routes tab should contain Route 0 through Route 40.")
		if offers != null and offers.item_count >= 2:
			_check("AVAILABLE" in offers.get_item_text(0) and "LOCKED" in offers.get_item_text(1), "Fresh route availability should be visible in the menu.")
		menu._select_category(AdventureMenu.CATEGORY_GYMS)
		_check(offers != null and offers.item_count == 8, "The Gyms tab should contain eight destinations.")
		menu._select_category(AdventureMenu.CATEGORY_CHAMPION)
		_check(offers != null and offers.item_count == 1, "The Champion tab should contain one editable challenge scene.")
		var source := FileAccess.get_file_as_string("res://game/ui/adventure_menu/adventure_menu.gd")
		_check("ChallengeProgressionSystem.launch_area(area_id)" in source, "AdventureMenu should call the progression launch API directly.")
		menu.close_hub()
		await get_tree().process_frame

	_check(GameInstance.is_player_movement_enabled(), "Closing the menu should restore player movement.")
	EconomySystem.load_save_data(original_economy)
	InventorySystem.load_save_data(original_inventory)
	player.queue_free()
	stretchman.queue_free()
	_finish()


func _find_menu() -> AdventureMenu:
	for child in UIManager.get_children():
		if child is AdventureMenu:
			return child as AdventureMenu
	return null


func _list_contains(list: ItemList, fragment: String) -> bool:
	for item_index in list.item_count:
		if fragment in list.get_item_text(item_index):
			return true
	return false


func _verify_touch_scroll(menu: AdventureMenu, offers: ItemList) -> void:
	var selected_before := offers.get_selected_items()
	var scroll_bar := offers.get_v_scroll_bar()
	var scroll_before := scroll_bar.value
	var start_local := Vector2(32.0, offers.size.y * 0.72)
	var end_local := start_local + Vector2(0.0, -80.0)
	var transform := offers.get_global_transform_with_canvas()
	var start := transform * start_local
	var finish := transform * end_local

	var press := InputEventScreenTouch.new()
	press.index = 17
	press.position = start
	press.pressed = true
	menu._input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 17
	drag.position = finish
	drag.relative = finish - start
	menu._input(drag)
	var release := InputEventScreenTouch.new()
	release.index = 17
	release.position = finish
	release.pressed = false
	menu._input(release)

	_check(scroll_bar.value > scroll_before + 40.0, "A mobile drag over an offer should scroll the ItemList.")
	_check(offers.get_selected_items() == selected_before, "A mobile drag should not select or activate the touched offer.")

	var tap_local := Vector2(32.0, offers.size.y * 0.55)
	var tapped_item := offers.get_item_at_position(tap_local, true)
	_check(tapped_item >= 0, "The touch-scroll test should find a visible offer to tap.")
	if tapped_item < 0:
		return
	var tap_position := transform * tap_local
	var tap_press := InputEventScreenTouch.new()
	tap_press.index = 18
	tap_press.position = tap_position
	tap_press.pressed = true
	menu._input(tap_press)
	_check(offers.get_selected_items() == selected_before, "A touch press should wait for release before changing selection.")
	var tap_release := InputEventScreenTouch.new()
	tap_release.index = 18
	tap_release.position = tap_position
	tap_release.pressed = false
	menu._input(tap_release)
	var tapped_selection := offers.get_selected_items()
	_check(
		not tapped_selection.is_empty() and tapped_selection[0] == tapped_item,
		"A stationary mobile tap should still select its offer on release."
	)


func _finish() -> void:
	if _failures.is_empty():
		print("Adventure Menu smoke test passed: ordinary NPC inheritance, Inspector-assigned generic behavior, movement lock, touch-safe scrolling, complete catalogs, 50 destinations, and direct launch contract verified.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Adventure Menu smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
