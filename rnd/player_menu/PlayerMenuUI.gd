class_name RNDPlayerMenuUI
extends Control

## R&D player menu backed by the real collection and Stretchman inventory.

signal closed
signal reset_progress_confirmed

const TAB_POKEMON := "pokemon"
const TAB_BAG := "bag"
const TAB_POKEDEX := "pokedex"
const SpriteMapping := preload("res://battle/system/BattleSpeciesMapping.gd")
const SPRITE_ANIMATION := &"idle"
const POKEMON_ICON_SIZE := Vector2i(48, 48)
const RESET_CONFIRMATION_PHRASE := "RESET FOREVER"

var _tab := TAB_POKEMON
var _visible_entries: Array[Dictionary] = []
var _selected_entry: Dictionary = {}
var _closing := false
var _tab_buttons: Dictionary = {}
var _icon_generation := 0
var _icon_loader_running := false
var _icon_reload_requested := false
var _preview_frame := 0
var _preview_elapsed := 0.0
var _pending_discard_key := ""
var _pending_discard_quantity := 0
var _pending_evolution_pcl_id := ""
var _pending_evolution_options: Array[Dictionary] = []
var _reset_warning_step := 0

var _summary: Label
var _balance: Label
var _search: LineEdit
var _filter: OptionButton
var _result_count: Label
var _list: ItemList
var _preview_panel: PanelContainer
var _preview: TextureRect
var _detail: RichTextLabel
var _party_slot_row: HBoxContainer
var _party_slot_picker: OptionButton
var _item_amount_row: HBoxContainer
var _item_amount: SpinBox
var _held_item_action: Button
var _evolve_action: Button
var _primary_action: Button
var _secondary_action: Button
var _status: Label
var _discard_dialog: ConfirmationDialog
var _evolution_prompt: Control
var _evolution_message: Label
var _evolution_choice: OptionButton
var _evolution_confirm: Button
var _reset_button: Button
var _reset_prompt: Control
var _reset_step_label: Label
var _reset_title: Label
var _reset_message: Label
var _reset_ack_pokemon: CheckButton
var _reset_ack_irreversible: CheckButton
var _reset_phrase: LineEdit
var _reset_continue: Button
var _reset_final: Button
var _cloud_button: Button
var _cloud_prompt: Control
var _cloud_save_id: LineEdit
var _cloud_show_id: CheckButton
var _cloud_status: Label
var _cloud_apply: Button
var _cloud_sync_now: Button
var _cloud_opt_out: Button
var _sprite_catalog: BattleSpriteCatalog
var _preview_frames: SpriteFrames


func _ready() -> void:
	set_process_unhandled_input(true)
	set_process(false)
	_sprite_catalog = BattleSpriteCatalog.new()
	if not _sprite_catalog.initialize():
		push_error("Player menu Pokemon art could not initialize: %s" % _sprite_catalog.get_last_error())
	_build_interface()
	CollectionSystem.collection_changed.connect(_on_collection_changed)
	StretchGoalSystem.inventory_changed.connect(_on_inventory_changed)
	StretchGoalSystem.balance_changed.connect(_on_balance_changed)
	CloudSaveSync.status_changed.connect(_on_cloud_status_changed)
	CloudSaveSync.configuration_changed.connect(_on_cloud_configuration_changed)
	select_tab(TAB_POKEMON)
	_refresh_cloud_controls()


func _exit_tree() -> void:
	if _sprite_catalog != null:
		_sprite_catalog.release_all()


func _process(delta: float) -> void:
	if _preview_frames == null or not _preview_panel.visible:
		return
	var frame_count := _preview_frames.get_frame_count(SPRITE_ANIMATION)
	if frame_count <= 1:
		return
	_preview_elapsed += delta
	var animation_speed := maxf(_preview_frames.get_animation_speed(SPRITE_ANIMATION), 0.001)
	var frame_duration := (
		_preview_frames.get_frame_duration(SPRITE_ANIMATION, _preview_frame)
		/ animation_speed
	)
	while _preview_elapsed >= frame_duration:
		_preview_elapsed -= frame_duration
		_preview_frame = (_preview_frame + 1) % frame_count
		_preview.texture = _preview_frames.get_frame_texture(
			SPRITE_ANIMATION,
			_preview_frame
		)
		frame_duration = (
			_preview_frames.get_frame_duration(SPRITE_ANIMATION, _preview_frame)
			/ animation_speed
		)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var close_requested := false
	if event is InputEventKey:
		close_requested = (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_M]
	elif event is InputEventJoypadButton:
		close_requested = (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
	if not close_requested:
		return
	if _cloud_prompt.visible:
		get_viewport().set_input_as_handled()
		close_cloud_save()
		return
	if _reset_prompt.visible:
		get_viewport().set_input_as_handled()
		cancel_reset_warnings()
		return
	if _evolution_prompt.visible:
		get_viewport().set_input_as_handled()
		_close_evolution_prompt()
		return
	if _discard_dialog.visible:
		return
	get_viewport().set_input_as_handled()
	close_menu()


func close_menu() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


func open_cloud_save() -> void:
	if _closing:
		return
	_cloud_save_id.text = CloudSaveSync.get_save_id()
	_cloud_save_id.secret = true
	_cloud_show_id.button_pressed = false
	_cloud_prompt.visible = true
	_refresh_cloud_controls()
	_cloud_save_id.grab_focus()


func close_cloud_save() -> void:
	_cloud_prompt.visible = false
	_cloud_save_id.release_focus()
	if is_instance_valid(_cloud_button):
		_cloud_button.grab_focus()


func apply_cloud_save_id() -> bool:
	if not CloudSaveSync.enable_with_save_id(_cloud_save_id.text):
		_refresh_cloud_controls()
		return false
	_cloud_save_id.text = CloudSaveSync.get_save_id()
	_refresh_cloud_controls()
	return true


func sync_cloud_save_now() -> bool:
	if not CloudSaveSync.is_enabled():
		_cloud_status.text = "Enter a private Save ID, then choose Use ID & Sync."
		_cloud_save_id.grab_focus()
		return false
	var requested := CloudSaveSync.request_sync(true)
	_refresh_cloud_controls()
	return requested


func opt_out_of_cloud_save() -> void:
	CloudSaveSync.disable_cloud_sync()
	_cloud_save_id.text = ""
	_cloud_show_id.button_pressed = false
	_refresh_cloud_controls()


func open_reset_warnings() -> void:
	if _closing:
		return
	_reset_warning_step = 1
	_reset_prompt.visible = true
	_show_reset_warning_step()


func advance_reset_warning() -> bool:
	if _reset_warning_step == 1:
		_reset_warning_step = 2
		_show_reset_warning_step()
		return true
	if (
		_reset_warning_step == 2
		and _reset_ack_pokemon.button_pressed
		and _reset_ack_irreversible.button_pressed
	):
		_reset_warning_step = 3
		_show_reset_warning_step()
		return true
	return false


func cancel_reset_warnings() -> void:
	_reset_warning_step = 0
	_reset_prompt.visible = false
	_reset_phrase.text = ""
	_reset_ack_pokemon.button_pressed = false
	_reset_ack_irreversible.button_pressed = false
	if is_instance_valid(_reset_button):
		_reset_button.grab_focus()


func confirm_progress_reset() -> bool:
	if (
		_reset_warning_step != 3
		or _reset_phrase.text.strip_edges().to_upper()
		!= RESET_CONFIRMATION_PHRASE
	):
		return false
	_reset_final.disabled = true
	_reset_phrase.editable = false
	_reset_title.text = "ERASING ALL PROGRESS…"
	_reset_message.text = "The confirmed reset request is being applied."
	reset_progress_confirmed.emit()
	return true


func get_reset_warning_step() -> int:
	return _reset_warning_step


func select_tab(tab: String) -> void:
	if tab not in [TAB_POKEMON, TAB_BAG, TAB_POKEDEX]:
		return
	_tab = tab
	_selected_entry.clear()
	for key: Variant in _tab_buttons.keys():
		(_tab_buttons[key] as Button).button_pressed = String(key) == tab
	_search.text = ""
	_list.fixed_icon_size = POKEMON_ICON_SIZE if tab in [TAB_POKEMON, TAB_POKEDEX] else Vector2i.ZERO
	_configure_filter()
	match tab:
		TAB_POKEMON:
			_search.placeholder_text = "Search your party and PC…"
			_status.text = "Move Pokémon between the party and PC, evolve them, or manage their held item."
		TAB_BAG:
			_search.placeholder_text = "Search the items you own…"
			_status.text = "The bag uses the same persistent item inventory as Stretchman's shop."
		TAB_POKEDEX:
			_search.placeholder_text = "Search all 1,025 Pokemon…"
			_status.text = "Owned entries are derived from your complete collection, including PC storage."
	_refresh_entries()


func move_pokemon_to_party_slot(pcl_id: String, party_slot: int) -> bool:
	var pcl := CollectionSystem.get_pcl(pcl_id)
	if pcl.is_empty():
		_status.text = CollectionSystem.get_last_error()
		return false
	var pokemon_name := _pokemon_name(int(pcl.get("pokemonId", 0)))
	var displaced := CollectionSystem.get_pcl_by_party_slot(party_slot)
	var displaced_name := (
		_pokemon_name(int(displaced.get("pokemonId", 0)))
		if not displaced.is_empty() and String(displaced.get("pclID", "")) != pcl_id
		else ""
	)
	if not CollectionSystem.move_to_party_slot(pcl_id, party_slot):
		_status.text = CollectionSystem.get_last_error()
		return false
	_status.text = "%s moved to Party Slot %d." % [pokemon_name, party_slot]
	if not displaced_name.is_empty():
		var was_in_party := bool((pcl.get("party", {}) as Dictionary).get("inParty", false))
		_status.text += (
			" %s moved to the previous slot." % displaced_name
			if was_in_party
			else " %s was sent to the PC." % displaced_name
		)
	_refresh_entries(pcl_id)
	return true


func send_pokemon_to_pc(pcl_id: String) -> bool:
	var pcl := CollectionSystem.get_pcl(pcl_id)
	if pcl.is_empty():
		_status.text = CollectionSystem.get_last_error()
		return false
	var party := pcl.get("party", {}) as Dictionary
	if not bool(party.get("inParty", false)):
		_status.text = "%s is already in PC storage." % _pokemon_name(int(pcl.get("pokemonId", 0)))
		return true
	if CollectionSystem.get_party_size() <= 1:
		_status.text = "At least one Pokemon must remain in the party."
		return false
	if not CollectionSystem.remove_from_party(pcl_id):
		_status.text = CollectionSystem.get_last_error()
		return false
	_status.text = "%s was sent to PC storage." % _pokemon_name(int(pcl.get("pokemonId", 0)))
	_refresh_entries(pcl_id)
	return true


func give_xp_share_to_pokemon(pcl_id: String) -> bool:
	var result := StretchGoalSystem.give_item_to_pokemon(
		StretchGoalSystem.XP_SHARE_ITEM_KEY,
		pcl_id
	)
	if not bool(result.get("ok", false)):
		_status.text = String(result.get("error", "The Exp. Share could not be given."))
		return false
	var pcl := CollectionSystem.get_pcl(pcl_id)
	_status.text = "%s is now holding the Exp. Share." % _pokemon_name(
		int(pcl.get("pokemonId", 0))
	)
	_refresh_entries(pcl_id)
	return true


func take_held_item_from_pokemon(pcl_id: String) -> bool:
	var pcl := CollectionSystem.get_pcl(pcl_id)
	var pokemon_name := _pokemon_name(int(pcl.get("pokemonId", 0)))
	var result := StretchGoalSystem.take_held_item_from_pokemon(pcl_id)
	if not bool(result.get("ok", false)):
		_status.text = String(result.get("error", "The held item could not be taken."))
		return false
	var summary := result.get("summary", {}) as Dictionary
	_status.text = "Took %s from %s and returned it to the bag." % [
		String(summary.get("item_name", "the held item")),
		pokemon_name,
	]
	_refresh_entries(pcl_id)
	return true


## Opens the evolution prompt for any currently eligible captured Pokemon.
## Branching evolutions populate an explicit keyboard/gamepad choice control.
func request_pokemon_evolution(pcl_id: String) -> bool:
	var pcl := CollectionSystem.get_pcl(pcl_id)
	if pcl.is_empty():
		_status.text = CollectionSystem.get_last_error()
		return false
	var options := CollectionSystem.get_evolution_options(pcl_id)
	if options.is_empty():
		_status.text = (
			CollectionSystem.get_last_error()
			if not CollectionSystem.get_last_error().is_empty()
			else "%s does not currently meet an evolution level."
			% _pokemon_name(int(pcl.get("pokemonId", 0)))
		)
		return false

	_pending_evolution_pcl_id = pcl_id
	_pending_evolution_options = options.duplicate(true)
	_evolution_choice.clear()
	for option in options:
		var target_id := int(option.get("pokemonId", 0))
		_evolution_choice.add_item("%s — Lv. %d" % [
			_pokemon_name(target_id),
			int(option.get("requiredLevel", 1)),
		])
		_evolution_choice.set_item_metadata(
			_evolution_choice.item_count - 1,
			target_id
		)
	_evolution_choice.select(0)
	var source_name := _pokemon_name(int(pcl.get("pokemonId", 0)))
	if options.size() > 1:
		_evolution_message.text = (
			"%s can evolve in several ways. Choose the Pokémon you want it to become."
			% source_name
		)
		_evolution_choice.visible = true
	else:
		var target_name := _pokemon_name(int(options[0].get("pokemonId", 0)))
		_evolution_message.text = "Evolve %s into %s?" % [source_name, target_name]
		_evolution_choice.visible = false
	_evolution_prompt.visible = true
	if _evolution_choice.visible:
		_evolution_choice.grab_focus()
	else:
		_evolution_confirm.grab_focus()
	return true


func confirm_evolution_choice() -> bool:
	if (
		_pending_evolution_pcl_id.is_empty()
		or _pending_evolution_options.is_empty()
		or _evolution_choice.item_count <= 0
	):
		return false
	var target_id := int(
		_evolution_choice.get_item_metadata(_evolution_choice.selected)
	)
	var before := CollectionSystem.get_pcl(_pending_evolution_pcl_id)
	var source_name := _pokemon_name(int(before.get("pokemonId", 0)))
	var pcl_id := _pending_evolution_pcl_id
	var result := CollectionSystem.evolve_pokemon(pcl_id, target_id)
	if result.is_empty():
		_status.text = CollectionSystem.get_last_error()
		_evolution_message.text = _status.text
		return false
	_close_evolution_prompt()
	_status.text = "%s evolved into %s!" % [source_name, _pokemon_name(target_id)]
	_refresh_entries(pcl_id)
	return true


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.012, 0.018, 0.032, 0.94)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "MenuPanel"
	panel.anchor_left = 0.015
	panel.anchor_top = 0.01
	panel.anchor_right = 0.985
	panel.anchor_bottom = 0.99
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	column.add_child(header)
	var title := Label.new()
	title.text = "PLAYER MENU"
	title.add_theme_font_size_override("font_size", 22)
	header.add_child(title)
	_summary = Label.new()
	_summary.name = "CollectionSummary"
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary.add_theme_font_size_override("font_size", 14)
	header.add_child(_summary)
	_balance = Label.new()
	_balance.name = "Balance"
	_balance.text = StretchGoalSystem.format_money(StretchGoalSystem.get_balance())
	_balance.custom_minimum_size = Vector2(135.0, 0.0)
	_balance.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance.add_theme_font_size_override("font_size", 18)
	header.add_child(_balance)
	var close_button := Button.new()
	close_button.name = "Close"
	close_button.text = "Close  Esc / B"
	close_button.custom_minimum_size = Vector2(140.0, 38.0)
	close_button.pressed.connect(close_menu)
	header.add_child(close_button)
	_reset_button = Button.new()
	_reset_button.name = "ResetProgress"
	_reset_button.text = "RESET PROGRESS"
	_reset_button.custom_minimum_size = Vector2(155.0, 38.0)
	_reset_button.add_theme_color_override("font_color", Color("fff1f1"))
	_reset_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_reset_button.add_theme_stylebox_override(
		"normal",
		_danger_style(Color("501218"), Color("d83343"), 2, 8)
	)
	_reset_button.add_theme_stylebox_override(
		"hover",
		_danger_style(Color("741822"), Color("ff5262"), 2, 8)
	)
	_reset_button.pressed.connect(open_reset_warnings)
	header.add_child(_reset_button)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	_add_tab(tabs, TAB_POKEMON, "Pokemon Party & PC")
	_add_tab(tabs, TAB_BAG, "Bag & Items")
	_add_tab(tabs, TAB_POKEDEX, "Pokedex")
	_cloud_button = Button.new()
	_cloud_button.name = "CloudSave"
	_cloud_button.text = "Cloud Save"
	_cloud_button.custom_minimum_size = Vector2(142.0, 38.0)
	_cloud_button.pressed.connect(open_cloud_save)
	tabs.add_child(_cloud_button)

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 10)
	column.add_child(search_row)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(330.0, 36.0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	search_row.add_child(_search)
	_filter = OptionButton.new()
	_filter.name = "Filter"
	_filter.custom_minimum_size = Vector2(235.0, 36.0)
	_filter.item_selected.connect(_on_filter_selected)
	search_row.add_child(_filter)
	_result_count = Label.new()
	_result_count.name = "ResultCount"
	_result_count.custom_minimum_size = Vector2(110.0, 0.0)
	_result_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	search_row.add_child(_result_count)

	var content := HSplitContainer.new()
	content.name = "Content"
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.split_offset = 500
	column.add_child(content)
	_list = ItemList.new()
	_list.name = "Entries"
	_list.custom_minimum_size = Vector2(440.0, 235.0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.allow_reselect = true
	_list.max_columns = 1
	_list.same_column_width = true
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	_list.get_v_scroll_bar().value_changed.connect(_on_list_scrolled)
	content.add_child(_list)

	var detail_column := VBoxContainer.new()
	detail_column.custom_minimum_size = Vector2(330.0, 0.0)
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 7)
	content.add_child(detail_column)
	_preview_panel = PanelContainer.new()
	_preview_panel.name = "PokemonPreviewPanel"
	_preview_panel.custom_minimum_size = Vector2(0.0, 132.0)
	_preview_panel.visible = false
	detail_column.add_child(_preview_panel)
	var preview_center := CenterContainer.new()
	_preview_panel.add_child(preview_center)
	_preview = TextureRect.new()
	_preview.name = "PokemonAnimatedPreview"
	_preview.custom_minimum_size = Vector2(190.0, 124.0)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_center.add_child(_preview)
	_detail = RichTextLabel.new()
	_detail.name = "Details"
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(0.0, 86.0)
	detail_column.add_child(_detail)

	_party_slot_row = HBoxContainer.new()
	_party_slot_row.name = "PartySlotControls"
	_party_slot_row.add_theme_constant_override("separation", 8)
	_party_slot_row.visible = false
	detail_column.add_child(_party_slot_row)
	var slot_label := Label.new()
	slot_label.text = "Target slot"
	_party_slot_row.add_child(slot_label)
	_party_slot_picker = OptionButton.new()
	_party_slot_picker.name = "PartySlot"
	_party_slot_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_slot_picker.item_selected.connect(_on_party_slot_selected)
	_party_slot_row.add_child(_party_slot_picker)

	_item_amount_row = HBoxContainer.new()
	_item_amount_row.name = "ItemAmountControls"
	_item_amount_row.add_theme_constant_override("separation", 8)
	_item_amount_row.visible = false
	detail_column.add_child(_item_amount_row)
	var amount_label := Label.new()
	amount_label.text = "Discard amount"
	_item_amount_row.add_child(amount_label)
	_item_amount = SpinBox.new()
	_item_amount.name = "DiscardAmount"
	_item_amount.min_value = 1.0
	_item_amount.max_value = 1.0
	_item_amount.step = 1.0
	_item_amount.value = 1.0
	_item_amount.allow_greater = false
	_item_amount.allow_lesser = false
	_item_amount.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_item_amount_row.add_child(_item_amount)

	_held_item_action = Button.new()
	_held_item_action.name = "HeldItemAction"
	_held_item_action.custom_minimum_size = Vector2(0.0, 42.0)
	_held_item_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_held_item_action.visible = false
	_held_item_action.pressed.connect(_activate_held_item)
	detail_column.add_child(_held_item_action)

	_evolve_action = Button.new()
	_evolve_action.name = "EvolutionAction"
	_evolve_action.custom_minimum_size = Vector2(0.0, 42.0)
	_evolve_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_evolve_action.visible = false
	_evolve_action.pressed.connect(_activate_evolution)
	detail_column.add_child(_evolve_action)

	var action_row := HBoxContainer.new()
	action_row.name = "Actions"
	action_row.add_theme_constant_override("separation", 8)
	detail_column.add_child(action_row)
	_primary_action = Button.new()
	_primary_action.name = "PrimaryAction"
	_primary_action.custom_minimum_size = Vector2(0.0, 42.0)
	_primary_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_primary_action.visible = false
	_primary_action.pressed.connect(_activate_primary)
	action_row.add_child(_primary_action)
	_secondary_action = Button.new()
	_secondary_action.name = "SecondaryAction"
	_secondary_action.custom_minimum_size = Vector2(120.0, 42.0)
	_secondary_action.visible = false
	_secondary_action.pressed.connect(_activate_secondary)
	action_row.add_child(_secondary_action)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.76, 0.84, 0.94)
	column.add_child(_status)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.name = "DiscardConfirmation"
	_discard_dialog.title = "Discard items?"
	_discard_dialog.ok_button_text = "Discard"
	_discard_dialog.cancel_button_text = "Keep"
	_discard_dialog.confirmed.connect(_confirm_discard)
	add_child(_discard_dialog)
	_build_evolution_prompt()
	_build_cloud_prompt()
	_build_reset_prompt()


func _build_evolution_prompt() -> void:
	_evolution_prompt = ColorRect.new()
	_evolution_prompt.name = "EvolutionPrompt"
	_evolution_prompt.color = Color(0.005, 0.009, 0.018, 0.9)
	_evolution_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_evolution_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_evolution_prompt.z_index = 50
	_evolution_prompt.visible = false
	add_child(_evolution_prompt)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_evolution_prompt.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(470.0, 220.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	var title := Label.new()
	title.text = "EVOLUTION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 23)
	column.add_child(title)
	_evolution_message = Label.new()
	_evolution_message.name = "EvolutionMessage"
	_evolution_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_evolution_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_evolution_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_evolution_message)
	_evolution_choice = OptionButton.new()
	_evolution_choice.name = "EvolutionChoice"
	_evolution_choice.custom_minimum_size = Vector2(0.0, 42.0)
	column.add_child(_evolution_choice)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var cancel := Button.new()
	cancel.name = "CancelEvolution"
	cancel.text = "Not now"
	cancel.custom_minimum_size = Vector2(130.0, 42.0)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(_close_evolution_prompt)
	buttons.add_child(cancel)
	_evolution_confirm = Button.new()
	_evolution_confirm.name = "ConfirmEvolution"
	_evolution_confirm.text = "Evolve"
	_evolution_confirm.custom_minimum_size = Vector2(130.0, 42.0)
	_evolution_confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_evolution_confirm.pressed.connect(confirm_evolution_choice)
	buttons.add_child(_evolution_confirm)


func _build_cloud_prompt() -> void:
	_cloud_prompt = ColorRect.new()
	_cloud_prompt.name = "CloudSavePrompt"
	_cloud_prompt.color = Color(0.004, 0.012, 0.025, 0.96)
	_cloud_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cloud_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_cloud_prompt.z_index = 55
	_cloud_prompt.visible = false
	add_child(_cloud_prompt)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cloud_prompt.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "CloudSavePanel"
	panel.custom_minimum_size = Vector2(680.0, 360.0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var title := Label.new()
	title.text = "OPTIONAL CLOUD SAVE"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 25)
	column.add_child(title)
	var explanation := Label.new()
	explanation.text = (
		"Choose a private Save ID to synchronize this profile across devices. "
		+ "The Save ID acts like a password: anyone who knows it can load this save. "
		+ "Local saving continues while offline and also works when cloud sync is off."
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(explanation)

	var id_row := HBoxContainer.new()
	id_row.add_theme_constant_override("separation", 10)
	column.add_child(id_row)
	_cloud_save_id = LineEdit.new()
	_cloud_save_id.name = "CloudSaveId"
	_cloud_save_id.placeholder_text = "Private Save ID — 12 to 128 characters"
	_cloud_save_id.secret = true
	_cloud_save_id.secret_character = "●"
	_cloud_save_id.max_length = RNDCloudSaveSync.SAVE_ID_MAX_LENGTH
	_cloud_save_id.custom_minimum_size = Vector2(420.0, 44.0)
	_cloud_save_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cloud_save_id.text_submitted.connect(_on_cloud_save_id_submitted)
	id_row.add_child(_cloud_save_id)
	_cloud_show_id = CheckButton.new()
	_cloud_show_id.name = "ShowCloudSaveId"
	_cloud_show_id.text = "Show ID"
	_cloud_show_id.toggled.connect(_on_cloud_show_id_toggled)
	id_row.add_child(_cloud_show_id)

	_cloud_status = Label.new()
	_cloud_status.name = "CloudSaveStatus"
	_cloud_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_cloud_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cloud_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cloud_status.add_theme_color_override("font_color", Color("b9ddff"))
	column.add_child(_cloud_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	var close := Button.new()
	close.name = "CloseCloudSave"
	close.text = "Close"
	close.custom_minimum_size = Vector2(100.0, 46.0)
	close.pressed.connect(close_cloud_save)
	buttons.add_child(close)
	_cloud_opt_out = Button.new()
	_cloud_opt_out.name = "DisableCloudSave"
	_cloud_opt_out.text = "Opt Out"
	_cloud_opt_out.custom_minimum_size = Vector2(120.0, 46.0)
	_cloud_opt_out.pressed.connect(opt_out_of_cloud_save)
	buttons.add_child(_cloud_opt_out)
	_cloud_sync_now = Button.new()
	_cloud_sync_now.name = "SyncCloudSaveNow"
	_cloud_sync_now.text = "Sync Now"
	_cloud_sync_now.custom_minimum_size = Vector2(125.0, 46.0)
	_cloud_sync_now.pressed.connect(sync_cloud_save_now)
	buttons.add_child(_cloud_sync_now)
	_cloud_apply = Button.new()
	_cloud_apply.name = "ApplyCloudSaveId"
	_cloud_apply.text = "Use ID & Sync"
	_cloud_apply.custom_minimum_size = Vector2(175.0, 46.0)
	_cloud_apply.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cloud_apply.pressed.connect(apply_cloud_save_id)
	buttons.add_child(_cloud_apply)


func _build_reset_prompt() -> void:
	_reset_prompt = ColorRect.new()
	_reset_prompt.name = "ResetWarningPrompt"
	_reset_prompt.color = Color(0.04, 0.0, 0.005, 0.96)
	_reset_prompt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_prompt.mouse_filter = Control.MOUSE_FILTER_STOP
	_reset_prompt.z_index = 60
	_reset_prompt.visible = false
	add_child(_reset_prompt)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_reset_prompt.add_child(center)
	var panel := PanelContainer.new()
	panel.name = "ResetDangerPanel"
	panel.custom_minimum_size = Vector2(650.0, 410.0)
	panel.add_theme_stylebox_override(
		"panel",
		_danger_style(Color("21070a"), Color("ff263d"), 5, 14)
	)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	_reset_step_label = Label.new()
	_reset_step_label.name = "ResetWarningStep"
	_reset_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_step_label.add_theme_color_override("font_color", Color("ff7785"))
	_reset_step_label.add_theme_font_size_override("font_size", 13)
	column.add_child(_reset_step_label)
	_reset_title = Label.new()
	_reset_title.name = "ResetWarningTitle"
	_reset_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reset_title.add_theme_color_override("font_color", Color("ff263d"))
	_reset_title.add_theme_color_override("font_shadow_color", Color.BLACK)
	_reset_title.add_theme_constant_override("shadow_offset_x", 2)
	_reset_title.add_theme_constant_override("shadow_offset_y", 2)
	_reset_title.add_theme_font_size_override("font_size", 29)
	column.add_child(_reset_title)
	_reset_message = Label.new()
	_reset_message.name = "ResetWarningMessage"
	_reset_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_reset_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reset_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reset_message.add_theme_color_override("font_color", Color("ffe7e9"))
	_reset_message.add_theme_font_size_override("font_size", 16)
	column.add_child(_reset_message)

	_reset_ack_pokemon = CheckButton.new()
	_reset_ack_pokemon.name = "AcknowledgePokemonDeletion"
	_reset_ack_pokemon.text = "I understand every party and PC Pokémon will be deleted."
	_reset_ack_pokemon.toggled.connect(_on_reset_acknowledgement_changed)
	column.add_child(_reset_ack_pokemon)
	_reset_ack_irreversible = CheckButton.new()
	_reset_ack_irreversible.name = "AcknowledgeNoRecovery"
	_reset_ack_irreversible.text = "I understand there is no undo, backup, or recovery button."
	_reset_ack_irreversible.toggled.connect(_on_reset_acknowledgement_changed)
	column.add_child(_reset_ack_irreversible)

	_reset_phrase = LineEdit.new()
	_reset_phrase.name = "ResetConfirmationPhrase"
	_reset_phrase.placeholder_text = "Type %s exactly" % RESET_CONFIRMATION_PHRASE
	_reset_phrase.custom_minimum_size = Vector2(0.0, 48.0)
	_reset_phrase.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reset_phrase.add_theme_color_override("font_color", Color("ffb8bf"))
	_reset_phrase.add_theme_font_size_override("font_size", 19)
	_reset_phrase.text_changed.connect(_on_reset_phrase_changed)
	column.add_child(_reset_phrase)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var cancel := Button.new()
	cancel.name = "CancelReset"
	cancel.text = "CANCEL — KEEP MY SAVE"
	cancel.custom_minimum_size = Vector2(210.0, 50.0)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(cancel_reset_warnings)
	buttons.add_child(cancel)
	_reset_continue = Button.new()
	_reset_continue.name = "ContinueResetWarning"
	_reset_continue.custom_minimum_size = Vector2(250.0, 50.0)
	_reset_continue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reset_continue.pressed.connect(advance_reset_warning)
	buttons.add_child(_reset_continue)
	_reset_final = Button.new()
	_reset_final.name = "ConfirmProgressReset"
	_reset_final.text = "ERASE EVERYTHING NOW"
	_reset_final.custom_minimum_size = Vector2(250.0, 50.0)
	_reset_final.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_reset_final.add_theme_color_override("font_color", Color.WHITE)
	_reset_final.add_theme_color_override("font_hover_color", Color.WHITE)
	_reset_final.add_theme_stylebox_override(
		"normal",
		_danger_style(Color("7e0d19"), Color("ff263d"), 3, 9)
	)
	_reset_final.add_theme_stylebox_override(
		"hover",
		_danger_style(Color("b31020"), Color("ff8290"), 3, 9)
	)
	_reset_final.pressed.connect(confirm_progress_reset)
	buttons.add_child(_reset_final)


func _show_reset_warning_step() -> void:
	_reset_ack_pokemon.visible = false
	_reset_ack_irreversible.visible = false
	_reset_phrase.visible = false
	_reset_continue.visible = false
	_reset_final.visible = false
	match _reset_warning_step:
		1:
			_reset_step_label.text = "DESTRUCTIVE ACTION  ·  WARNING 1 OF 3"
			_reset_title.text = "⚠ DANGER: FULL PROGRESS RESET ⚠"
			_reset_message.text = (
				"This is not a logout, restart, or temporary reset. Continuing begins "
				+ "a permanent deletion sequence for this local save and any linked cloud copy."
			)
			_reset_continue.text = "I UNDERSTAND — SHOW THE NEXT WARNING"
			_reset_continue.disabled = false
			_reset_continue.visible = true
			_reset_continue.grab_focus()
		2:
			_reset_step_label.text = "DESTRUCTIVE ACTION  ·  WARNING 2 OF 3"
			_reset_title.text = "EVERYTHING YOU EARNED WILL BE DESTROYED"
			_reset_message.text = (
				"All Pokémon, levels, XP, equipped moves, pending move choices, items, "
				+ "money, badges, Champion progress, route progress, and saved world "
				+ "position will be erased. This cannot be reversed."
			)
			_reset_ack_pokemon.button_pressed = false
			_reset_ack_irreversible.button_pressed = false
			_reset_ack_irreversible.text = (
				"I understand no local or linked cloud copy can undo this reset."
			)
			_reset_ack_pokemon.visible = true
			_reset_ack_irreversible.visible = true
			_reset_continue.text = "I ACCEPT BOTH WARNINGS"
			_reset_continue.disabled = true
			_reset_continue.visible = true
			_reset_ack_pokemon.grab_focus()
		3:
			_reset_step_label.text = "DESTRUCTIVE ACTION  ·  FINAL WARNING 3 OF 3"
			_reset_title.text = "POINT OF NO RETURN"
			_reset_message.text = (
				"Type %s exactly. The red button will erase local progress, mark any linked "
				+ "cloud profile as reset, "
				+ "return to the main development environment, and force a new starter choice."
			) % RESET_CONFIRMATION_PHRASE
			_reset_phrase.text = ""
			_reset_phrase.editable = true
			_reset_phrase.visible = true
			_reset_final.disabled = true
			_reset_final.visible = true
			_reset_phrase.grab_focus()


func _on_reset_acknowledgement_changed(_pressed: bool) -> void:
	_reset_continue.disabled = not (
		_reset_ack_pokemon.button_pressed
		and _reset_ack_irreversible.button_pressed
	)


func _on_reset_phrase_changed(value: String) -> void:
	_reset_final.disabled = (
		value.strip_edges().to_upper() != RESET_CONFIRMATION_PHRASE
	)


func _danger_style(
	background: Color,
	border: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style


func _add_tab(parent: HBoxContainer, tab: String, label: String) -> void:
	var button := Button.new()
	button.name = tab.capitalize().replace(" ", "")
	button.text = label
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.pressed.connect(select_tab.bind(tab))
	parent.add_child(button)
	_tab_buttons[tab] = button


func _configure_filter() -> void:
	_filter.clear()
	_add_filter("All", "all")
	match _tab:
		TAB_POKEMON:
			_add_filter("Party only", "location:party")
			_add_filter("PC storage only", "location:pc")
		TAB_BAG:
			var owned_categories: Array[String] = []
			var inventory := StretchGoalSystem.get_item_inventory()
			for item in StretchGoalSystem.get_item_catalog():
				var item_key := String(item.get("key", item.get("slug", "")))
				if int(inventory.get(item_key, 0)) <= 0:
					continue
				var category := String(item.get("category", "miscellaneous"))
				if category not in owned_categories:
					owned_categories.append(category)
			owned_categories.sort()
			for category in owned_categories:
				_add_filter(
					category.replace("-", " ").capitalize(),
					"category:%s" % category
				)
		TAB_POKEDEX:
			_add_filter("Owned", "dex:owned")
			_add_filter("Missing", "dex:missing")
			_add_filter("Legendary", "dex:legendary")
			_add_filter("Mythical", "dex:mythical")
	_filter.select(0)


func _add_filter(label: String, value: String) -> void:
	_filter.add_item(label)
	_filter.set_item_metadata(_filter.item_count - 1, value)


func _refresh_entries(preserve_key := "", focus_results := true) -> void:
	if preserve_key.is_empty() and not _selected_entry.is_empty():
		preserve_key = _entry_key(_selected_entry)
	_icon_generation += 1
	_visible_entries.clear()
	_list.clear()
	var source: Array[Dictionary]
	match _tab:
		TAB_POKEMON:
			source = _build_collection_entries()
		TAB_BAG:
			source = _build_bag_entries()
		TAB_POKEDEX:
			source = _build_pokedex_entries()
		_:
			source = []
	var filter_value := _selected_filter_value()
	for entry in source:
		if not _passes_filter(entry, filter_value) or not _matches_search(entry, _search.text):
			continue
		_visible_entries.append(entry)
		_list.add_item(_entry_text(entry))
	_result_count.text = "%s result%s" % [
		_format_count(_visible_entries.size()),
		"" if _visible_entries.size() == 1 else "s",
	]
	_update_summary()
	if _visible_entries.is_empty():
		_selected_entry.clear()
		_detail.text = "[center]No entries match this view.[/center]"
		_hide_actions()
		_clear_preview()
		return
	var selected_index := 0
	if not preserve_key.is_empty():
		for index in _visible_entries.size():
			if _entry_key(_visible_entries[index]) == preserve_key:
				selected_index = index
				break
	_list.select(selected_index)
	_on_item_selected(selected_index)
	if focus_results:
		_list.grab_focus()
	if _tab in [TAB_POKEMON, TAB_POKEDEX]:
		_queue_visible_icons.call_deferred()


func _build_collection_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for party_slot in range(1, CollectionSystem.PARTY_SIZE + 1):
		var pcl := CollectionSystem.get_pcl_by_party_slot(party_slot)
		if pcl.is_empty():
			entries.append({
				"kind": "empty_party",
				"location": "party",
				"party_slot": party_slot,
				"name": "Empty Party Slot",
			})
		else:
			entries.append(_pcl_entry(pcl, "party"))
	for pcl in CollectionSystem.get_collection():
		var party := pcl.get("party", {}) as Dictionary
		if bool(party.get("inParty", false)):
			continue
		entries.append(_pcl_entry(pcl, "pc"))
	return entries


func _pcl_entry(pcl: Dictionary, location: String) -> Dictionary:
	var pokemon_id := int(pcl.get("pokemonId", 0))
	var party := pcl.get("party", {}) as Dictionary
	return {
		"kind": "pcl",
		"pcl_id": String(pcl.get("pclID", "")),
		"pokemon_id": pokemon_id,
		"id": pokemon_id,
		"name": _pokemon_name(pokemon_id),
		"slug": _pokemon_slug(pokemon_id),
		"location": location,
		"party_slot": int(party.get("slot", 0)) if bool(party.get("inParty", false)) else 0,
		"pcl": pcl,
	}


func _build_bag_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var inventory := StretchGoalSystem.get_item_inventory()
	for item in StretchGoalSystem.get_item_catalog():
		var item_key := String(item.get("key", item.get("slug", "")))
		var quantity := int(inventory.get(item_key, 0))
		if quantity <= 0:
			continue
		var entry := item.duplicate(true)
		entry["kind"] = "item"
		entry["item_key"] = item_key
		entry["quantity"] = quantity
		entries.append(entry)
	return entries


func _build_pokedex_entries() -> Array[Dictionary]:
	var owned_counts: Dictionary = {}
	for pcl in CollectionSystem.get_collection():
		var pokemon_id := int(pcl.get("pokemonId", 0))
		owned_counts[pokemon_id] = int(owned_counts.get(pokemon_id, 0)) + 1
	var entries: Array[Dictionary] = []
	for offer in StretchGoalSystem.get_pokemon_catalog():
		var entry := offer.duplicate(true)
		var pokemon_id := int(entry.get("id", 0))
		entry["kind"] = "dex"
		entry["pokemon_id"] = pokemon_id
		entry["owned_count"] = int(owned_counts.get(pokemon_id, 0))
		entries.append(entry)
	return entries


func _selected_filter_value() -> String:
	if _filter.item_count <= 0:
		return "all"
	return String(_filter.get_item_metadata(_filter.selected))


func _passes_filter(entry: Dictionary, filter_value: String) -> bool:
	if filter_value == "all" or filter_value.is_empty():
		return true
	var separator := filter_value.find(":")
	if separator < 0:
		return true
	var kind := filter_value.left(separator)
	var value := filter_value.substr(separator + 1)
	match kind:
		"location":
			return String(entry.get("location", "")) == value
		"category":
			return String(entry.get("category", "")) == value
		"dex":
			match value:
				"owned":
					return int(entry.get("owned_count", 0)) > 0
				"missing":
					return int(entry.get("owned_count", 0)) == 0
				"legendary":
					return bool(entry.get("isLegendary", false))
				"mythical":
					return bool(entry.get("isMythical", false))
	return true


func _matches_search(entry: Dictionary, query: String) -> bool:
	var normalized_query := _normalize_search_text(query)
	if normalized_query.is_empty():
		return true
	var haystack := _normalize_search_text(" ".join([
		str(entry.get("id", entry.get("pokemon_id", ""))),
		String(entry.get("name", "")),
		String(entry.get("slug", "")),
		String(entry.get("category", "")),
		String(entry.get("location", "")),
		String(entry.get("description", "")),
	]))
	var candidates := haystack.split(" ", false)
	for query_term_value in normalized_query.split(" ", false):
		var query_term := String(query_term_value)
		if query_term in haystack:
			continue
		var matched := false
		for candidate_value in candidates:
			if _elastic_token_matches(query_term, String(candidate_value)):
				matched = true
				break
		if not matched:
			return false
	return true


func _normalize_search_text(value: String) -> String:
	var normalized := value.to_lower()
	var replacements := {
		"é": "e", "è": "e", "ê": "e", "ë": "e",
		"á": "a", "à": "a", "â": "a", "ä": "a",
		"í": "i", "ì": "i", "î": "i", "ï": "i",
		"ó": "o", "ò": "o", "ô": "o", "ö": "o",
		"ú": "u", "ù": "u", "û": "u", "ü": "u",
		"♀": " f ", "♂": " m ",
	}
	for source: Variant in replacements.keys():
		normalized = normalized.replace(String(source), String(replacements[source]))
	for separator in ["-", "_", "/", "\\", "'", "’", ".", ",", ":", "(", ")", "[", "]"]:
		normalized = normalized.replace(separator, " ")
	return " ".join(normalized.split(" ", false)).strip_edges()


func _elastic_token_matches(query: String, candidate: String) -> bool:
	if query.is_empty() or candidate.is_empty():
		return false
	if candidate.begins_with(query) or query.begins_with(candidate):
		return true
	if query.length() < 3:
		return false
	var max_distance := 2 if query.length() >= 7 else 1
	if absi(query.length() - candidate.length()) > max_distance:
		return false
	return _edit_distance_at_most(query, candidate, max_distance)


func _edit_distance_at_most(left: String, right: String, limit: int) -> bool:
	var previous: Array[int] = []
	for column in range(right.length() + 1):
		previous.append(column)
	for row in range(1, left.length() + 1):
		var current: Array[int] = [row]
		var row_minimum := row
		for column in range(1, right.length() + 1):
			var substitution_cost := 0 if left[row - 1] == right[column - 1] else 1
			var distance := mini(
				mini(current[column - 1] + 1, previous[column] + 1),
				previous[column - 1] + substitution_cost
			)
			current.append(distance)
			row_minimum = mini(row_minimum, distance)
		if row_minimum > limit:
			return false
		previous = current
	return previous[right.length()] <= limit


func _entry_text(entry: Dictionary) -> String:
	match String(entry.get("kind", "")):
		"empty_party":
			return "PARTY %d  —  [Empty slot]" % int(entry.get("party_slot", 0))
		"pcl":
			var pcl := entry.get("pcl", {}) as Dictionary
			var stats := pcl.get("instanceStats", {}) as Dictionary
			var level_xp := _level_xp_text(String(entry.get("pcl_id", "")))
			var prefix := (
				"PARTY %d" % int(entry.get("party_slot", 0))
				if String(entry.get("location", "")) == "party"
				else "PC"
			)
			var held_item := String(pcl.get("heldItem", ""))
			var held_suffix := "" if held_item.is_empty() else "  —  Holding %s" % _item_name(held_item)
			return ("%s  —  #%04d %s  —  Lv.%d  —  XP %s  —  HP %d%%" % [
				prefix,
				int(entry.get("pokemon_id", 0)),
				String(entry.get("name", "Pokemon")),
				int(stats.get("level", 1)),
				level_xp,
				roundi(float(stats.get("health", 0.0)) * 100.0),
			]) + held_suffix
		"item":
			return "x%d  %s  —  %s" % [
				int(entry.get("quantity", 0)),
				String(entry.get("name", "Item")),
				String(entry.get("category", "miscellaneous")).replace("-", " ").capitalize(),
			]
		"dex":
			var owned := int(entry.get("owned_count", 0))
			return "#%04d  %s  —  %s" % [
				int(entry.get("id", 0)),
				String(entry.get("name", "Pokemon")),
				"OWNED x%d" % owned if owned > 0 else "MISSING",
			]
	return String(entry.get("name", "Entry"))


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _visible_entries.size():
		_selected_entry.clear()
		_hide_actions()
		return
	_selected_entry = _visible_entries[index].duplicate(true)
	_hide_actions()
	match String(_selected_entry.get("kind", "")):
		"empty_party":
			_clear_preview()
			_detail.text = (
				"[font_size=24][b]Party Slot %d[/b][/font_size]\n\n"
				+ "This slot is empty. Select a Pokemon in PC storage, choose this slot, "
				+ "and press Move to Party."
			) % int(_selected_entry.get("party_slot", 0))
		"pcl":
			_show_preview(_selected_entry)
			_detail.text = _collection_details(_selected_entry)
			_configure_party_actions()
		"item":
			_clear_preview()
			_detail.text = _item_details(_selected_entry)
			_configure_item_actions()
		"dex":
			_show_preview(_selected_entry)
			_detail.text = _pokedex_details(_selected_entry)


func _on_item_activated(index: int) -> void:
	_on_item_selected(index)
	if _tab == TAB_POKEMON and String(_selected_entry.get("kind", "")) == "pcl":
		_activate_primary()


func _hide_actions() -> void:
	_party_slot_row.visible = false
	_item_amount_row.visible = false
	_held_item_action.visible = false
	_evolve_action.visible = false
	_primary_action.visible = false
	_secondary_action.visible = false


func _configure_party_actions() -> void:
	_party_slot_row.visible = true
	_primary_action.visible = true
	_secondary_action.visible = true
	_party_slot_picker.clear()
	var current_slot := int(_selected_entry.get("party_slot", 0))
	var first_empty_index := -1
	for slot in range(1, CollectionSystem.PARTY_SIZE + 1):
		var occupant := CollectionSystem.get_pcl_by_party_slot(slot)
		var occupant_name := "Empty" if occupant.is_empty() else _pokemon_name(int(occupant.get("pokemonId", 0)))
		_party_slot_picker.add_item("Slot %d — %s" % [slot, occupant_name])
		_party_slot_picker.set_item_metadata(_party_slot_picker.item_count - 1, slot)
		if occupant.is_empty() and first_empty_index < 0:
			first_empty_index = _party_slot_picker.item_count - 1
	if current_slot > 0:
		_party_slot_picker.select(current_slot - 1)
	elif first_empty_index >= 0:
		_party_slot_picker.select(first_empty_index)
	else:
		_party_slot_picker.select(0)
	_secondary_action.text = "Send to PC"
	_secondary_action.disabled = (
		String(_selected_entry.get("location", "")) != "party"
		or CollectionSystem.get_party_size() <= 1
	)
	var pcl_id := String(_selected_entry.get("pcl_id", ""))
	var pcl := CollectionSystem.get_pcl(pcl_id)
	var held_item := String(pcl.get("heldItem", ""))
	_held_item_action.visible = (
		not held_item.is_empty()
		or StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) > 0
	)
	if not held_item.is_empty():
		_held_item_action.text = "Take %s" % _item_name(held_item)
		_held_item_action.disabled = false
	else:
		_held_item_action.text = "Give Exp. Share"
		_held_item_action.disabled = (
			StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) <= 0
		)
	var evolution_options := CollectionSystem.get_evolution_options(pcl_id)
	_evolve_action.visible = not evolution_options.is_empty()
	if evolution_options.size() > 1:
		_evolve_action.text = "Choose Evolution…"
	elif evolution_options.size() == 1:
		_evolve_action.text = "Evolve into %s" % _pokemon_name(
			int(evolution_options[0].get("pokemonId", 0))
		)
	_update_party_action_label()


func _configure_item_actions() -> void:
	_item_amount_row.visible = true
	_primary_action.visible = true
	_primary_action.text = "Discard from Bag"
	_primary_action.disabled = false
	var quantity := maxi(1, int(_selected_entry.get("quantity", 1)))
	_item_amount.max_value = quantity
	_item_amount.value = 1.0


func _on_party_slot_selected(_index: int) -> void:
	_update_party_action_label()


func _update_party_action_label() -> void:
	if _party_slot_picker.item_count <= 0 or _selected_entry.is_empty():
		_primary_action.disabled = true
		return
	var target_slot := int(_party_slot_picker.get_item_metadata(_party_slot_picker.selected))
	var current_slot := int(_selected_entry.get("party_slot", 0))
	if current_slot == target_slot:
		_primary_action.text = "Already in Party Slot %d" % target_slot
		_primary_action.disabled = true
		return
	var occupant := CollectionSystem.get_pcl_by_party_slot(target_slot)
	if occupant.is_empty():
		_primary_action.text = "Move to Party Slot %d" % target_slot
	elif current_slot > 0:
		_primary_action.text = "Swap with Party Slot %d" % target_slot
	else:
		_primary_action.text = "Replace Slot %d (old member to PC)" % target_slot
	_primary_action.disabled = false


func _activate_primary() -> void:
	match String(_selected_entry.get("kind", "")):
		"pcl":
			if _party_slot_picker.item_count <= 0:
				return
			var party_slot := int(
				_party_slot_picker.get_item_metadata(_party_slot_picker.selected)
			)
			move_pokemon_to_party_slot(
				String(_selected_entry.get("pcl_id", "")),
				party_slot
			)
		"item":
			_request_discard()


func _activate_secondary() -> void:
	if String(_selected_entry.get("kind", "")) != "pcl":
		return
	send_pokemon_to_pc(String(_selected_entry.get("pcl_id", "")))


func _activate_evolution() -> void:
	if String(_selected_entry.get("kind", "")) != "pcl":
		return
	request_pokemon_evolution(String(_selected_entry.get("pcl_id", "")))


func _activate_held_item() -> void:
	if String(_selected_entry.get("kind", "")) != "pcl":
		return
	var pcl_id := String(_selected_entry.get("pcl_id", ""))
	var held_item := CollectionSystem.get_held_item(pcl_id)
	if held_item.is_empty():
		give_xp_share_to_pokemon(pcl_id)
	else:
		take_held_item_from_pokemon(pcl_id)


func _close_evolution_prompt() -> void:
	_evolution_prompt.visible = false
	_pending_evolution_pcl_id = ""
	_pending_evolution_options.clear()
	_evolution_choice.clear()
	if is_instance_valid(_list):
		_list.grab_focus()


func _request_discard() -> void:
	var item_key := String(_selected_entry.get("item_key", ""))
	var quantity := int(_item_amount.value)
	if item_key.is_empty() or quantity <= 0:
		return
	_pending_discard_key = item_key
	_pending_discard_quantity = quantity
	_discard_dialog.dialog_text = "Discard %d × %s? This cannot be undone." % [
		quantity,
		String(_selected_entry.get("name", "item")),
	]
	_discard_dialog.popup_centered(Vector2i(420, 180))


func _confirm_discard() -> void:
	if _pending_discard_key.is_empty() or _pending_discard_quantity <= 0:
		return
	var result := StretchGoalSystem.discard_item(
		_pending_discard_key,
		_pending_discard_quantity
	)
	_pending_discard_key = ""
	_pending_discard_quantity = 0
	if bool(result.get("ok", false)):
		var summary := result.get("summary", {}) as Dictionary
		_status.text = "Discarded %d × %s. %d remain." % [
			int(summary.get("quantity", 0)),
			String(summary.get("name", "item")),
			int(summary.get("remaining", 0)),
		]
	else:
		_status.text = String(result.get("error", "The item could not be discarded."))
	_refresh_entries()


func _collection_details(entry: Dictionary) -> String:
	var pcl := entry.get("pcl", {}) as Dictionary
	var stats := pcl.get("instanceStats", {}) as Dictionary
	var profile := pcl.get("battleProfile", {}) as Dictionary
	var location := (
		"Party Slot %d" % int(entry.get("party_slot", 0))
		if String(entry.get("location", "")) == "party"
		else "PC Storage"
	)
	var moves: Array[String] = []
	for move_value: Variant in profile.get("moves", []) as Array:
		moves.append(String(move_value).replace("-", " ").capitalize())
	var move_text := ", ".join(moves) if not moves.is_empty() else "No battle profile"
	var evolution_text := _evolution_level_summary(
		int(entry.get("pokemon_id", 0)),
		int(stats.get("level", 1))
	)
	var held_item_key := String(pcl.get("heldItem", ""))
	var held_item_text := "None" if held_item_key.is_empty() else _item_name(held_item_key)
	var held_effect_text := (
		" A party holder receives half of its normal knockout XP without entering battle; "
		+ "a holder that enters battle receives the normal full award instead."
		if held_item_key == StretchGoalSystem.XP_SHARE_ITEM_KEY
		else ""
	)
	var level_xp_text := _level_xp_text(String(entry.get("pcl_id", "")), true)
	return (
		"[font_size=23][b]#%04d %s[/b][/font_size]\n\n"
		+ "[b]Location:[/b] %s\n[b]Level:[/b] %d\n[b]Health:[/b] %d%%\n"
		+ "[b]Current XP:[/b] %s\n[b]Level XP:[/b] %s\n[b]Held item:[/b] %s%s\n"
		+ "[b]Moves:[/b] %s\n[b]Evolution:[/b] %s\n\n"
		+ "Use the slot selector to move or atomically swap this individual Pokemon."
	) % [
		int(entry.get("pokemon_id", 0)),
		String(entry.get("name", "Pokemon")),
		location,
		int(stats.get("level", 1)),
		roundi(float(stats.get("health", 0.0)) * 100.0),
		_format_count(int(stats.get("currentXp", 0))),
		level_xp_text,
		held_item_text,
		held_effect_text,
		move_text,
		evolution_text,
	]


func _level_xp_text(pcl_id: String, include_remaining := false) -> String:
	var progress := CollectionSystem.get_experience_progress(pcl_id)
	if progress.is_empty():
		return "Unavailable"
	var required := int(progress.get("xpForNextLevel", 0))
	if required <= 0:
		return "MAX"
	var earned := int(progress.get("xpIntoLevel", 0))
	var text := "%s/%s" % [_format_count(earned), _format_count(required)]
	if include_remaining:
		text += " (%s remaining to Lv. %d)" % [
			_format_count(maxi(0, required - earned)),
			int(progress.get("level", 1)) + 1,
		]
	return text


func _evolution_level_summary(pokemon_id: int, level: int) -> String:
	var options := CreatureSystem.get_evolution_options(pokemon_id)
	if options.is_empty():
		return "Final stage"
	var summaries: Array[String] = []
	for option in options:
		var required_level := int(option.get("requiredLevel", 1))
		var summary := "%s at Lv. %d" % [
			_pokemon_name(int(option.get("pokemonId", 0))),
			required_level,
		]
		if level >= required_level:
			summary += " (ready)"
		summaries.append(summary)
	return "; ".join(summaries)


func _item_details(entry: Dictionary) -> String:
	var item_key := String(entry.get("item_key", ""))
	var effect_note := (
		"Give this to a Pokémon from the Pokémon Party & PC tab. A party holder that "
		+ "does not enter battle receives half of its normal knockout XP."
		if item_key == StretchGoalSystem.XP_SHARE_ITEM_KEY
		else "This item's battle effect is not wired yet; it can still be stored or discarded."
	)
	return (
		"[font_size=23][b]%s[/b][/font_size]\n\n"
		+ "[b]Quantity:[/b] %d\n[b]Category:[/b] %s\n[b]Shop value:[/b] %s\n\n%s\n\n"
		+ "[color=#e4b663]%s[/color]"
	) % [
		String(entry.get("name", "Item")),
		int(entry.get("quantity", 0)),
		String(entry.get("category", "miscellaneous")).replace("-", " ").capitalize(),
		StretchGoalSystem.format_money(int(entry.get("price", 0))),
		String(entry.get("description", "No description available.")),
		effect_note,
	]


func _pokedex_details(entry: Dictionary) -> String:
	var pokemon_id := int(entry.get("id", 0))
	var mapping := SpriteMapping.get_entry(pokemon_id)
	var dimensions := SpriteMapping.get_pokedex_dimensions(pokemon_id)
	var pokemon_data := CreatureSystem.get_pokemon(pokemon_id)
	var types: Array[String] = []
	for type_value: Variant in pokemon_data.get("types", []) as Array:
		if typeof(type_value) != TYPE_DICTIONARY:
			continue
		var type_row := type_value as Dictionary
		var type_data := type_row.get("type", {}) as Dictionary
		var type_name := String(type_data.get("name", "")).capitalize()
		if not type_name.is_empty():
			types.append(type_name)
	var flavor_text := _english_flavor_text(pokemon_data)
	var rarity := "Mythical" if bool(entry.get("isMythical", false)) else (
		"Legendary" if bool(entry.get("isLegendary", false)) else "Standard"
	)
	var height_text := "Unknown"
	var weight_text := "Unknown"
	if not dimensions.is_empty():
		height_text = "%.1f m" % (float(dimensions.get("height_dm", 0)) / 10.0)
		weight_text = "%.1f kg" % (float(dimensions.get("weight_hg", 0)) / 10.0)
	return (
		"[font_size=23][b]#%04d %s[/b][/font_size]\n\n"
		+ "[b]Status:[/b] %s\n[b]Type:[/b] %s\n[b]Height:[/b] %s\n"
		+ "[b]Weight:[/b] %s\n[b]Rarity:[/b] %s\n[b]Community tier:[/b] %s\n\n%s"
	) % [
		pokemon_id,
		String(entry.get("name", mapping.get("species", "Pokemon"))),
		"Owned ×%d" % int(entry.get("owned_count", 0)) if int(entry.get("owned_count", 0)) > 0 else "Not owned",
		", ".join(types) if not types.is_empty() else "Unknown",
		height_text,
		weight_text,
		rarity,
		String(entry.get("tier", "Unranked")),
		flavor_text,
	]


func _english_flavor_text(pokemon_data: Dictionary) -> String:
	var species := pokemon_data.get("species_data", {}) as Dictionary
	for value: Variant in species.get("flavor_text_entries", []) as Array:
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var entry := value as Dictionary
		var language := entry.get("language", {}) as Dictionary
		if String(language.get("name", "")) != "en":
			continue
		return " ".join(
			String(entry.get("flavor_text", "")).replace("\n", " ").replace("\f", " ").split(" ", false)
		)
	return "No Pokédex description is available."


func _pokemon_name(pokemon_id: int) -> String:
	var offer := StretchGoalSystem.get_pokemon_offer(pokemon_id)
	if not offer.is_empty():
		return String(offer.get("name", "Pokemon"))
	var mapping := SpriteMapping.get_entry(pokemon_id)
	return String(mapping.get("species", "Pokemon #%d" % pokemon_id))


func _pokemon_slug(pokemon_id: int) -> String:
	var offer := StretchGoalSystem.get_pokemon_offer(pokemon_id)
	if not offer.is_empty():
		return String(offer.get("slug", ""))
	return String(SpriteMapping.get_entry(pokemon_id).get("spriteId", "missing-pokemon"))


func _item_name(item_key: String) -> String:
	for item in StretchGoalSystem.get_item_catalog():
		if String(item.get("key", item.get("slug", ""))) == item_key:
			return String(item.get("name", item_key.replace("-", " ").capitalize()))
	return item_key.replace("-", " ").capitalize()


func _pokemon_sprite_id(entry: Dictionary) -> String:
	var pokemon_id := int(entry.get("pokemon_id", entry.get("id", 0)))
	var mapping := SpriteMapping.get_entry(pokemon_id)
	var sprite_id := String(mapping.get("spriteId", "")).strip_edges()
	if sprite_id.is_empty():
		sprite_id = String(entry.get("slug", _pokemon_slug(pokemon_id))).strip_edges()
	return sprite_id if not sprite_id.is_empty() else "missing-pokemon"


func _show_preview(entry: Dictionary) -> void:
	var asset := _sprite_catalog.load_active(_pokemon_sprite_id(entry), false)
	_preview_frames = asset.get("sprite_frames") as SpriteFrames
	if _preview_frames == null or _preview_frames.get_frame_count(SPRITE_ANIMATION) <= 0:
		_clear_preview()
		return
	_preview_frame = 0
	_preview_elapsed = 0.0
	_preview.texture = _preview_frames.get_frame_texture(SPRITE_ANIMATION, 0)
	_preview_panel.visible = true
	set_process(true)


func _clear_preview() -> void:
	_preview_frames = null
	_preview_frame = 0
	_preview_elapsed = 0.0
	if is_instance_valid(_preview):
		_preview.texture = null
	if is_instance_valid(_preview_panel):
		_preview_panel.visible = false
	if _sprite_catalog != null:
		_sprite_catalog.release_active(false)
	set_process(false)


func _on_list_scrolled(_value: float) -> void:
	if _tab in [TAB_POKEMON, TAB_POKEDEX]:
		_queue_visible_icons()


func _queue_visible_icons() -> void:
	if _tab not in [TAB_POKEMON, TAB_POKEDEX] or _visible_entries.is_empty():
		return
	if _icon_loader_running:
		_icon_reload_requested = true
		return
	_load_visible_icons(_icon_generation)


func _load_visible_icons(generation: int) -> void:
	_icon_loader_running = true
	_icon_reload_requested = false
	await get_tree().process_frame
	if generation != _icon_generation or _tab not in [TAB_POKEMON, TAB_POKEDEX]:
		_finish_icon_load()
		return
	var scroll_bar := _list.get_v_scroll_bar()
	var row_height := float(POKEMON_ICON_SIZE.y + 8)
	var first_visible := maxi(0, floori(scroll_bar.value / row_height) - 4)
	var visible_count := maxi(16, ceili(scroll_bar.page / row_height) + 10)
	var last_visible := mini(_visible_entries.size(), first_visible + visible_count)
	var loaded_since_yield := 0
	for index in range(first_visible, last_visible):
		if generation != _icon_generation or _tab not in [TAB_POKEMON, TAB_POKEDEX]:
			_finish_icon_load()
			return
		if _list.get_item_icon(index) != null:
			continue
		var entry := _visible_entries[index]
		if String(entry.get("kind", "")) == "empty_party":
			continue
		var thumbnail := _sprite_catalog.load_front_thumbnail(
			_pokemon_sprite_id(entry),
			false,
			"",
			POKEMON_ICON_SIZE
		)
		var texture := thumbnail.get("texture") as Texture2D
		if texture != null and index < _list.item_count:
			_list.set_item_icon(index, texture)
		loaded_since_yield += 1
		if loaded_since_yield >= 3:
			loaded_since_yield = 0
			await get_tree().process_frame
	_finish_icon_load()


func _finish_icon_load() -> void:
	_icon_loader_running = false
	if _icon_reload_requested:
		_icon_reload_requested = false
		_queue_visible_icons.call_deferred()


func _entry_key(entry: Dictionary) -> String:
	match String(entry.get("kind", "")):
		"empty_party":
			return "party:%d" % int(entry.get("party_slot", 0))
		"pcl":
			return String(entry.get("pcl_id", ""))
		"item":
			return String(entry.get("item_key", ""))
		"dex":
			return "dex:%d" % int(entry.get("id", 0))
	return ""


func _format_count(value: int) -> String:
	var digits := str(maxi(value, 0))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return ",".join(groups)


func _update_summary() -> void:
	var collection := CollectionSystem.get_collection()
	var owned_species: Dictionary = {}
	for pcl in collection:
		owned_species[int(pcl.get("pokemonId", 0))] = true
	var party_size := CollectionSystem.get_party_size()
	var pc_size := maxi(0, collection.size() - party_size)
	var item_stacks := StretchGoalSystem.get_item_inventory().size()
	_summary.text = "Party %d/6  •  PC %s  •  Dex %s/1,025  •  Bag %s stacks" % [
		party_size,
		_format_count(pc_size),
		_format_count(owned_species.size()),
		_format_count(item_stacks),
	]


func _on_search_changed(_value: String) -> void:
	_refresh_entries("", false)


func _on_filter_selected(_index: int) -> void:
	_refresh_entries()


func _on_cloud_save_id_submitted(_value: String) -> void:
	apply_cloud_save_id()


func _on_cloud_show_id_toggled(show_id: bool) -> void:
	_cloud_save_id.secret = not show_id
	_cloud_save_id.grab_focus()
	_cloud_save_id.caret_column = _cloud_save_id.text.length()


func _on_cloud_status_changed(_state: String, _message: String) -> void:
	_refresh_cloud_controls()


func _on_cloud_configuration_changed(_enabled: bool) -> void:
	_refresh_cloud_controls()


func _refresh_cloud_controls() -> void:
	if not is_instance_valid(_cloud_button):
		return
	var cloud_enabled := CloudSaveSync.is_enabled()
	var cloud_state := CloudSaveSync.get_state()
	match cloud_state:
		"synced":
			_cloud_button.text = "Cloud ✓"
		"syncing", "pending":
			_cloud_button.text = "Cloud …"
		"offline", "error":
			_cloud_button.text = "Cloud !"
		_:
			_cloud_button.text = "Cloud Save"
	_cloud_status.text = CloudSaveSync.get_status_message()
	var last_sync_ms := CloudSaveSync.get_last_sync_at_ms()
	if last_sync_ms > 0:
		_cloud_status.text += "\nLast successful sync: %s UTC · revision %d" % [
			Time.get_datetime_string_from_unix_time(last_sync_ms / 1000, true),
			CloudSaveSync.get_base_revision(),
		]
	_cloud_opt_out.disabled = not cloud_enabled
	_cloud_sync_now.disabled = not cloud_enabled or cloud_state == "syncing"


func _on_collection_changed() -> void:
	if _tab in [TAB_POKEMON, TAB_POKEDEX]:
		_refresh_entries()
	else:
		_update_summary()


func _on_inventory_changed() -> void:
	if _tab == TAB_BAG:
		_configure_filter()
		_refresh_entries()
	elif _tab == TAB_POKEMON:
		_refresh_entries()
	else:
		_update_summary()


func _on_balance_changed(balance: int) -> void:
	_balance.text = StretchGoalSystem.format_money(balance)
