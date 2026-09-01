class_name RNDStretchGoalUI
extends Control

## Keyboard/gamepad/touch navigable R&D hub for shops and destination launch.

signal closed
signal travel_requested(kind: String, destination_index: int)

const CATEGORY_ITEMS := "items"
const CATEGORY_POKEMON := "pokemon"
const CATEGORY_LOOT_BOXES := "loot_boxes"
const CATEGORY_GYMS := "gym"
const CATEGORY_CHAMPION := "champion"
const CATEGORY_ROUTES := "route"
const SpriteMapping := preload("res://battle/system/BattleSpeciesMapping.gd")
const LootBoxScene := preload("res://rnd/stretch/ui/loot_box_roulette.tscn")
const SPRITE_ANIMATION := &"idle"
const POKEMON_ICON_SIZE := Vector2i(48, 48)
const POKEMON_SORT_POKEDEX := "pokedex"
const POKEMON_SORT_PRICE_ASCENDING := "price_ascending"
const POKEMON_SORT_PRICE_DESCENDING := "price_descending"
const POKEMON_SORT_COOLNESS_DESCENDING := "coolness_descending"
const POKEMON_SORT_COOLNESS_ASCENDING := "coolness_ascending"
const POKEMON_COOLNESS_APPEAL := {
	"standard": 25,
	"rare": 55,
	"iconic": 70,
	"legendary": 80,
	"mythical": 84,
}
const POKEMON_COOLNESS_TIER := {
	"LC": 0,
	"NFE": 1,
	"ZU": 2,
	"ZUBL": 3,
	"PU": 4,
	"PUBL": 5,
	"NU": 6,
	"NUBL": 7,
	"RU": 8,
	"RUBL": 9,
	"UU": 10,
	"UUBL": 11,
	"OU": 12,
	"Uber": 13,
	"AG": 14,
}

var _category := CATEGORY_ITEMS
var _visible_entries: Array[Dictionary] = []
var _selected_entry: Dictionary = {}
var _closing := false
var _loot_box_roulette: RNDLootBoxRoulette
var _icon_generation := 0
var _icon_loader_running := false
var _icon_reload_requested := false
var _preview_frame := 0
var _preview_elapsed := 0.0

var _balance_label: Label
var _search: LineEdit
var _filter_row: HBoxContainer
var _filter: OptionButton
var _sort_row: HBoxContainer
var _sort: OptionButton
var _result_count: Label
var _list: ItemList
var _detail: RichTextLabel
var _pokemon_preview_panel: PanelContainer
var _pokemon_preview: TextureRect
var _status: Label
var _action: Button
var _tab_buttons: Dictionary = {}
var _sprite_catalog: BattleSpriteCatalog
var _preview_frames: SpriteFrames


func _ready() -> void:
	set_process_unhandled_input(true)
	set_process(false)
	_sprite_catalog = BattleSpriteCatalog.new()
	if not _sprite_catalog.initialize():
		push_error("Stretchman Pokemon art could not initialize: %s" % _sprite_catalog.get_last_error())
	_build_interface()
	StretchGoalSystem.balance_changed.connect(_on_balance_changed)
	_select_category(CATEGORY_ITEMS)


func _exit_tree() -> void:
	if _sprite_catalog != null:
		_sprite_catalog.release_all()


func _process(delta: float) -> void:
	if _preview_frames == null or not _pokemon_preview_panel.visible:
		return
	var frame_count := _preview_frames.get_frame_count(SPRITE_ANIMATION)
	if frame_count <= 1:
		return
	_preview_elapsed += delta
	var animation_speed := maxf(
		_preview_frames.get_animation_speed(SPRITE_ANIMATION),
		0.001
	)
	var frame_duration := (
		_preview_frames.get_frame_duration(SPRITE_ANIMATION, _preview_frame)
		/ animation_speed
	)
	while _preview_elapsed >= frame_duration:
		_preview_elapsed -= frame_duration
		_preview_frame = (_preview_frame + 1) % frame_count
		_pokemon_preview.texture = _preview_frames.get_frame_texture(
			SPRITE_ANIMATION,
			_preview_frame
		)
		frame_duration = (
			_preview_frames.get_frame_duration(SPRITE_ANIMATION, _preview_frame)
			/ animation_speed
		)


func close_hub() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()
	queue_free()


func dismiss_for_travel() -> void:
	if _closing:
		return
	_closing = true
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_loot_box_roulette):
		return
	if not event.is_pressed():
		return
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_hub()
	elif (
		event is InputEventJoypadButton
		and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
	):
		get_viewport().set_input_as_handled()
		close_hub()


func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.015, 0.02, 0.035, 0.90)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "HubPanel"
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
	header.add_theme_constant_override("separation", 14)
	column.add_child(header)
	var title := Label.new()
	title.text = "STRETCHMAN'S IMPOSSIBLY LARGE R&D MENU"
	title.add_theme_font_size_override("font_size", 21)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_balance_label = Label.new()
	_balance_label.text = StretchGoalSystem.format_money(StretchGoalSystem.get_balance())
	_balance_label.add_theme_font_size_override("font_size", 20)
	_balance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_balance_label.custom_minimum_size = Vector2(180.0, 0.0)
	header.add_child(_balance_label)
	var close_button := Button.new()
	close_button.text = "Close  Esc / B"
	close_button.custom_minimum_size = Vector2(145.0, 40.0)
	close_button.pressed.connect(close_hub)
	header.add_child(close_button)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	column.add_child(tabs)
	_add_tab(tabs, CATEGORY_ITEMS, "Buy Items")
	_add_tab(tabs, CATEGORY_POKEMON, "Buy Pokemon")
	_add_tab(tabs, CATEGORY_LOOT_BOXES, "Loot Boxes")
	_add_tab(tabs, CATEGORY_GYMS, "Gyms 1–8")
	_add_tab(tabs, CATEGORY_CHAMPION, "Champion")
	_add_tab(tabs, CATEGORY_ROUTES, "Routes")

	var search_row := HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 10)
	column.add_child(search_row)
	_search = LineEdit.new()
	_search.name = "Search"
	_search.placeholder_text = "Search the current menu…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(235.0, 38.0)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(_on_search_changed)
	search_row.add_child(_search)

	_filter_row = HBoxContainer.new()
	_filter_row.name = "FilterRow"
	_filter_row.add_theme_constant_override("separation", 8)
	search_row.add_child(_filter_row)
	var filter_label := Label.new()
	filter_label.text = "Filter"
	_filter_row.add_child(filter_label)
	_filter = OptionButton.new()
	_filter.name = "Filter"
	_filter.custom_minimum_size = Vector2(195.0, 38.0)
	_filter.item_selected.connect(_on_filter_selected)
	_filter_row.add_child(_filter)
	_sort_row = HBoxContainer.new()
	_sort_row.name = "PokemonSortRow"
	_sort_row.add_theme_constant_override("separation", 8)
	search_row.add_child(_sort_row)
	var sort_label := Label.new()
	sort_label.text = "Sort"
	_sort_row.add_child(sort_label)
	_sort = OptionButton.new()
	_sort.name = "PokemonSort"
	_sort.custom_minimum_size = Vector2(190.0, 38.0)
	_sort.item_selected.connect(_on_sort_selected)
	_sort_row.add_child(_sort)
	_result_count = Label.new()
	_result_count.name = "ResultCount"
	_result_count.custom_minimum_size = Vector2(105.0, 0.0)
	_result_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	search_row.add_child(_result_count)

	var content := HSplitContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.split_offset = 470
	column.add_child(content)
	_list = ItemList.new()
	_list.name = "Offers"
	_list.custom_minimum_size = Vector2(410.0, 240.0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.select_mode = ItemList.SELECT_SINGLE
	_list.allow_reselect = true
	_list.max_columns = 1
	_list.same_column_width = true
	_list.item_selected.connect(_on_item_selected)
	_list.item_activated.connect(_on_item_activated)
	_list.get_v_scroll_bar().value_changed.connect(_on_offer_scroll)
	content.add_child(_list)

	var detail_column := VBoxContainer.new()
	detail_column.custom_minimum_size = Vector2(310.0, 0.0)
	detail_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_column.add_theme_constant_override("separation", 10)
	content.add_child(detail_column)
	_pokemon_preview_panel = PanelContainer.new()
	_pokemon_preview_panel.name = "PokemonPreviewPanel"
	_pokemon_preview_panel.custom_minimum_size = Vector2(0.0, 140.0)
	_pokemon_preview_panel.visible = false
	detail_column.add_child(_pokemon_preview_panel)
	var preview_center := CenterContainer.new()
	_pokemon_preview_panel.add_child(preview_center)
	_pokemon_preview = TextureRect.new()
	_pokemon_preview.name = "PokemonAnimatedPreview"
	_pokemon_preview.custom_minimum_size = Vector2(190.0, 130.0)
	_pokemon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pokemon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pokemon_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview_center.add_child(_pokemon_preview)
	_detail = RichTextLabel.new()
	_detail.name = "Details"
	_detail.bbcode_enabled = true
	_detail.fit_content = false
	_detail.scroll_active = true
	_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_detail.custom_minimum_size = Vector2(0.0, 100.0)
	detail_column.add_child(_detail)
	_action = Button.new()
	_action.name = "Action"
	_action.text = "Buy"
	_action.custom_minimum_size = Vector2(0.0, 48.0)
	_action.disabled = true
	_action.pressed.connect(_activate_selected)
	detail_column.add_child(_action)

	_status = Label.new()
	_status.name = "Status"
	_status.text = (
		"R&D note: item effects and production balance are intentionally unfinished; "
		+ "ownership, travel, battles, rewards, and Pokemon storage are live."
	)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(0.76, 0.84, 0.94)
	column.add_child(_status)


func _add_tab(parent: HBoxContainer, category: String, label: String) -> void:
	var button := Button.new()
	button.text = label
	button.toggle_mode = true
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size = Vector2(0.0, 38.0)
	button.pressed.connect(_select_category.bind(category))
	parent.add_child(button)
	_tab_buttons[category] = button


func _select_category(category: String) -> void:
	_category = category
	_selected_entry.clear()
	_icon_generation += 1
	_list.fixed_icon_size = POKEMON_ICON_SIZE if category == CATEGORY_POKEMON else Vector2i.ZERO
	if category != CATEGORY_POKEMON:
		_clear_pokemon_preview()
	for key: Variant in _tab_buttons.keys():
		(_tab_buttons[key] as Button).button_pressed = String(key) == category
	_search.text = ""
	_configure_filters()
	_configure_sort()
	match category:
		CATEGORY_ITEMS:
			_search.placeholder_text = "Search all 2,223 PokeAPI items…"
		CATEGORY_POKEMON:
			_search.placeholder_text = "Search all 1,025 default Pokemon…"
		CATEGORY_LOOT_BOXES:
			_search.placeholder_text = "Search loot-box tiers…"
		CATEGORY_GYMS:
			_search.placeholder_text = "Filter Gym 1–8…"
		CATEGORY_CHAMPION:
			_search.placeholder_text = "Champion challenge"
		CATEGORY_ROUTES:
			_search.placeholder_text = "Filter outdoor routes…"
	_refresh_entries()


func _on_search_changed(_new_text: String) -> void:
	_refresh_entries(false)


func _on_filter_selected(_index: int) -> void:
	_refresh_entries()


func _on_sort_selected(_index: int) -> void:
	_refresh_entries()


func _configure_filters() -> void:
	_filter.clear()
	_filter_row.visible = _category in [CATEGORY_ITEMS, CATEGORY_POKEMON]
	if not _filter_row.visible:
		return
	_add_filter_option("All", "all")
	if _category == CATEGORY_ITEMS:
		_add_filter_option("Price: $0–$100", "price:budget")
		_add_filter_option("Price: $101–$1,000", "price:standard")
		_add_filter_option("Price: $1,001–$10,000", "price:premium")
		_add_filter_option("Price: over $10,000", "price:collector")
		var categories: Array[String] = []
		for entry in StretchGoalSystem.get_item_catalog():
			var category := String(entry.get("category", "miscellaneous"))
			if category not in categories:
				categories.append(category)
		categories.sort()
		for category in categories:
			_add_filter_option(
				"Category: %s" % category.replace("-", " ").capitalize(),
				"category:%s" % category
			)
	else:
		_add_filter_option("Affordable: up to $1,000", "price:affordable")
		_add_filter_option("Midrange: $1,001–$10,000", "price:midrange")
		_add_filter_option("Premium: $10,001–$1,000,000", "price:premium")
		_add_filter_option("Collector: over $1,000,000", "price:collector")
		_add_filter_option("Cool / iconic", "appeal:iconic")
		_add_filter_option("Rare", "appeal:rare")
		_add_filter_option("Legendary", "appeal:legendary")
		_add_filter_option("Mythical", "appeal:mythical")
		var tiers: Array[String] = []
		for entry in StretchGoalSystem.get_pokemon_catalog():
			var tier := String(entry.get("tier", "Unranked"))
			if tier not in tiers:
				tiers.append(tier)
		tiers.sort()
		for tier in tiers:
			_add_filter_option("Tier: %s" % tier, "tier:%s" % tier)
	_filter.select(0)


func _configure_sort() -> void:
	_sort.clear()
	_sort_row.visible = _category == CATEGORY_POKEMON
	if not _sort_row.visible:
		return
	_add_sort_option("Pokedex Number", POKEMON_SORT_POKEDEX)
	_add_sort_option("$ Low to High", POKEMON_SORT_PRICE_ASCENDING)
	_add_sort_option("$ High to Low", POKEMON_SORT_PRICE_DESCENDING)
	_add_sort_option("Coolest to Lamest", POKEMON_SORT_COOLNESS_DESCENDING)
	_add_sort_option("Lamest to Coolest", POKEMON_SORT_COOLNESS_ASCENDING)
	_sort.select(0)


func _add_filter_option(label: String, value: String) -> void:
	_filter.add_item(label)
	_filter.set_item_metadata(_filter.item_count - 1, value)


func _add_sort_option(label: String, value: String) -> void:
	_sort.add_item(label)
	_sort.set_item_metadata(_sort.item_count - 1, value)


func _refresh_entries(focus_results := true) -> void:
	_icon_generation += 1
	var source: Array[Dictionary]
	match _category:
		CATEGORY_ITEMS:
			source = StretchGoalSystem.get_item_catalog()
		CATEGORY_POKEMON:
			source = StretchGoalSystem.get_pokemon_catalog()
		CATEGORY_LOOT_BOXES:
			source = StretchGoalSystem.get_loot_box_catalog()
		CATEGORY_GYMS:
			source = StretchGoalSystem.get_destinations("gym")
		CATEGORY_CHAMPION:
			source = StretchGoalSystem.get_destinations("champion")
		CATEGORY_ROUTES:
			source = StretchGoalSystem.get_destinations("route")
		_:
			source = []
	var query := _search.text
	var filter_value := _selected_filter_value()
	_visible_entries.clear()
	_list.clear()
	for entry in source:
		if not _entry_passes_filter(entry, filter_value) or not _entry_matches(entry, query):
			continue
		_visible_entries.append(entry)
	if _category == CATEGORY_POKEMON:
		_visible_entries.sort_custom(_pokemon_entry_precedes)
	for entry in _visible_entries:
		_list.add_item(_entry_text(entry))
	_result_count.text = "%s result%s" % [
		_format_count(_visible_entries.size()),
		"" if _visible_entries.size() == 1 else "s",
	]
	if _visible_entries.is_empty():
		_selected_entry.clear()
		_detail.text = "[center]No entries match this search.[/center]"
		_action.disabled = true
		return
	_list.select(0)
	_on_item_selected(0)
	if focus_results:
		_list.grab_focus()
	if _category == CATEGORY_POKEMON:
		_queue_visible_pokemon_icons.call_deferred()


func _entry_matches(entry: Dictionary, query: String) -> bool:
	var normalized_query := _normalize_search_text(query)
	if normalized_query.is_empty():
		return true
	var haystack := _normalize_search_text(" ".join([
		str(entry.get("id", "")),
		String(entry.get("name", "")),
		String(entry.get("slug", "")),
		String(entry.get("category", "")),
		String(entry.get("tier", "")),
		String(entry.get("appeal", "")),
		String(entry.get("quality_label", "")),
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


func _selected_filter_value() -> String:
	if not is_instance_valid(_filter) or _filter.item_count == 0:
		return "all"
	return String(_filter.get_item_metadata(_filter.selected))


func _selected_sort_value() -> String:
	if not is_instance_valid(_sort) or _sort.item_count == 0:
		return POKEMON_SORT_POKEDEX
	return String(_sort.get_item_metadata(_sort.selected))


func _pokemon_entry_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_id := int(left.get("id", 0))
	var right_id := int(right.get("id", 0))
	match _selected_sort_value():
		POKEMON_SORT_PRICE_ASCENDING:
			var left_price := int(left.get("price", 0))
			var right_price := int(right.get("price", 0))
			return left_price < right_price if left_price != right_price else left_id < right_id
		POKEMON_SORT_PRICE_DESCENDING:
			var left_price := int(left.get("price", 0))
			var right_price := int(right.get("price", 0))
			return left_price > right_price if left_price != right_price else left_id < right_id
		POKEMON_SORT_COOLNESS_DESCENDING:
			var left_coolness := _pokemon_coolness_score(left)
			var right_coolness := _pokemon_coolness_score(right)
			if left_coolness != right_coolness:
				return left_coolness > right_coolness
			var left_price := int(left.get("price", 0))
			var right_price := int(right.get("price", 0))
			return left_price > right_price if left_price != right_price else left_id < right_id
		POKEMON_SORT_COOLNESS_ASCENDING:
			var left_coolness := _pokemon_coolness_score(left)
			var right_coolness := _pokemon_coolness_score(right)
			if left_coolness != right_coolness:
				return left_coolness < right_coolness
			var left_price := int(left.get("price", 0))
			var right_price := int(right.get("price", 0))
			return left_price < right_price if left_price != right_price else left_id < right_id
	return left_id < right_id


func _pokemon_coolness_score(entry: Dictionary) -> int:
	var appeal_points := int(
		POKEMON_COOLNESS_APPEAL.get(String(entry.get("appeal", "standard")), 25)
	)
	var tier_points := int(
		POKEMON_COOLNESS_TIER.get(String(entry.get("tier", "LC")), 0)
	)
	var capture_rate := clampi(int(entry.get("captureRate", 255)), 1, 255)
	var rarity_points := roundi(float(255 - capture_rate) / 254.0 * 8.0)
	var evolution_points := clampi(int(entry.get("evolutionStage", 1)) - 1, 0, 2) * 3
	return clampi(appeal_points + tier_points + rarity_points + evolution_points, 0, 100)


func _entry_passes_filter(entry: Dictionary, filter_value: String) -> bool:
	if filter_value.is_empty() or filter_value == "all":
		return true
	var separator := filter_value.find(":")
	if separator < 0:
		return true
	var filter_kind := filter_value.left(separator)
	var requested := filter_value.substr(separator + 1)
	var price := int(entry.get("price", 0))
	match filter_kind:
		"category":
			return String(entry.get("category", "")) == requested
		"tier":
			return String(entry.get("tier", "")) == requested
		"appeal":
			return String(entry.get("appeal", "")) == requested
		"price":
			if _category == CATEGORY_ITEMS:
				match requested:
					"budget":
						return price <= 100
					"standard":
						return price > 100 and price <= 1_000
					"premium":
						return price > 1_000 and price <= 10_000
					"collector":
						return price > 10_000
			else:
				match requested:
					"affordable":
						return price <= 1_000
					"midrange":
						return price > 1_000 and price <= 10_000
					"premium":
						return price > 10_000 and price <= 1_000_000
					"collector":
						return price > 1_000_000
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


func _format_count(value: int) -> String:
	var digits := str(value)
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return ",".join(groups)


func _on_offer_scroll(_value: float) -> void:
	if _category == CATEGORY_POKEMON:
		_queue_visible_pokemon_icons()


func _queue_visible_pokemon_icons() -> void:
	if _category != CATEGORY_POKEMON or _visible_entries.is_empty():
		return
	if _icon_loader_running:
		_icon_reload_requested = true
		return
	_load_visible_pokemon_icons(_icon_generation)


func _load_visible_pokemon_icons(generation: int) -> void:
	_icon_loader_running = true
	_icon_reload_requested = false
	await get_tree().process_frame
	if generation != _icon_generation or _category != CATEGORY_POKEMON:
		_finish_icon_load()
		return

	var scroll_bar := _list.get_v_scroll_bar()
	var row_height := float(POKEMON_ICON_SIZE.y + 8)
	var first_visible := maxi(0, floori(scroll_bar.value / row_height) - 4)
	var visible_count := maxi(16, ceili(scroll_bar.page / row_height) + 10)
	var last_visible := mini(_visible_entries.size(), first_visible + visible_count)
	var loaded_since_yield := 0
	for index in range(first_visible, last_visible):
		if generation != _icon_generation or _category != CATEGORY_POKEMON:
			_finish_icon_load()
			return
		if _list.get_item_icon(index) != null:
			continue
		var sprite_id := _pokemon_sprite_id(_visible_entries[index])
		var thumbnail := _sprite_catalog.load_front_thumbnail(
			sprite_id,
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
		_queue_visible_pokemon_icons.call_deferred()


func _pokemon_sprite_id(entry: Dictionary) -> String:
	var mapping := SpriteMapping.get_entry(int(entry.get("id", 0)))
	var sprite_id := String(mapping.get("spriteId", "")).strip_edges()
	if sprite_id.is_empty():
		sprite_id = String(entry.get("slug", "missing-pokemon")).strip_edges()
	return sprite_id


func _show_pokemon_preview(entry: Dictionary) -> void:
	var asset := _sprite_catalog.load_active(_pokemon_sprite_id(entry), false)
	_preview_frames = asset.get("sprite_frames") as SpriteFrames
	if (
		_preview_frames == null
		or _preview_frames.get_frame_count(SPRITE_ANIMATION) <= 0
	):
		_clear_pokemon_preview()
		return
	_preview_frame = 0
	_preview_elapsed = 0.0
	_pokemon_preview.texture = _preview_frames.get_frame_texture(SPRITE_ANIMATION, 0)
	_pokemon_preview_panel.visible = true
	set_process(true)


func _clear_pokemon_preview() -> void:
	_preview_frames = null
	_preview_frame = 0
	_preview_elapsed = 0.0
	if is_instance_valid(_pokemon_preview):
		_pokemon_preview.texture = null
	if is_instance_valid(_pokemon_preview_panel):
		_pokemon_preview_panel.visible = false
	if _sprite_catalog != null:
		_sprite_catalog.release_active(false)
	set_process(false)


func _entry_text(entry: Dictionary) -> String:
	match _category:
		CATEGORY_ITEMS:
			var owned := StretchGoalSystem.get_item_count(String(entry.get("key", entry.get("slug", ""))))
			return "%s  —  %s  —  owned %d" % [
				String(entry.get("name", "Item")),
				StretchGoalSystem.format_money(int(entry.get("price", 0))),
				owned,
			]
		CATEGORY_POKEMON:
			return "#%04d  %s  [Lv. %d · %s]  —  %s" % [
				int(entry.get("id", 0)),
				String(entry.get("name", "Pokemon")),
				StretchGoalSystem.get_pokemon_purchase_level(
					int(entry.get("id", 0))
				),
				String(entry.get("tier", "Unranked")),
				StretchGoalSystem.format_money(int(entry.get("price", 0))),
			]
		CATEGORY_LOOT_BOXES:
			return "%s  —  %s  —  %s" % [
				String(entry.get("tier", "Tier")),
				String(entry.get("name", "Loot Box")),
				StretchGoalSystem.format_money(int(entry.get("price", 0))),
			]
		CATEGORY_GYMS:
			var badge := "  ✓ BADGE EARNED" if StretchGoalSystem.has_badge(int(entry.get("index", 0))) else ""
			return "%s%s" % [String(entry.get("name", "Gym")), badge]
		CATEGORY_CHAMPION:
			var clear := "  ✓ CLEARED" if StretchGoalSystem.is_champion_cleared() else ""
			return "%s%s" % [String(entry.get("name", "Champion Challenge")), clear]
		CATEGORY_ROUTES:
			var route_status := (
				"  ✓ COMPLETE"
				if bool(entry.get("completed", false))
				else ("  🔒 LOCKED" if not bool(entry.get("unlocked", false)) else "  • AVAILABLE")
			)
			return "%s  [Lv. %d–%d · %s]%s" % [
				String(entry.get("name", "Route")),
				int(entry.get("level_min", 1)),
				int(entry.get("level_max", 1)),
				String(entry.get("biome", "route")).capitalize(),
				route_status,
			]
	return String(entry.get("name", "Entry"))


func _on_item_selected(index: int) -> void:
	if index < 0 or index >= _visible_entries.size():
		_selected_entry.clear()
		_action.disabled = true
		return
	_selected_entry = _visible_entries[index].duplicate(true)
	_action.disabled = false
	match _category:
		CATEGORY_ITEMS:
			_clear_pokemon_preview()
			_action.text = "Buy Item"
			_detail.text = _item_details(_selected_entry)
		CATEGORY_POKEMON:
			_action.text = "Buy Lv. %d Pokemon" % (
				StretchGoalSystem.get_pokemon_purchase_level(
					int(_selected_entry.get("id", 0))
				)
			)
			_detail.text = _pokemon_details(_selected_entry)
			_show_pokemon_preview(_selected_entry)
		CATEGORY_LOOT_BOXES:
			_clear_pokemon_preview()
			_action.text = "Buy & Open %s" % String(_selected_entry.get("name", "Loot Box"))
			_detail.text = _loot_box_details(_selected_entry)
		CATEGORY_GYMS:
			_clear_pokemon_preview()
			_action.text = "Travel to Gym %d" % int(_selected_entry.get("index", 0))
			_detail.text = _destination_details(_selected_entry, "GYM CHALLENGE")
		CATEGORY_CHAMPION:
			_clear_pokemon_preview()
			_action.text = "Begin Champion Run"
			_detail.text = _destination_details(_selected_entry, "CHAMPION RUN")
		CATEGORY_ROUTES:
			_clear_pokemon_preview()
			var route_unlocked := bool(_selected_entry.get("unlocked", false))
			_action.disabled = not route_unlocked
			_action.text = (
				"Travel to Route %d" % int(_selected_entry.get("index", 0))
				if route_unlocked
				else "Locked — finish Route %d" % (
					int(_selected_entry.get("index", 0)) - 1
				)
			)
			_detail.text = _destination_details(_selected_entry, "OUTDOOR ROUTE")


func _on_item_activated(index: int) -> void:
	_on_item_selected(index)
	_activate_selected()


func _activate_selected() -> void:
	if _selected_entry.is_empty():
		return
	match _category:
		CATEGORY_ITEMS:
			var result := StretchGoalSystem.buy_item(
				String(_selected_entry.get("key", _selected_entry.get("slug", "")))
			)
			_show_purchase_result(result)
		CATEGORY_POKEMON:
			var result := StretchGoalSystem.buy_pokemon(int(_selected_entry.get("id", 0)))
			_show_purchase_result(result)
		CATEGORY_LOOT_BOXES:
			var result := StretchGoalSystem.buy_loot_box(String(_selected_entry.get("id", "")))
			if bool(result.get("ok", false)):
				_open_loot_box_result(result.get("summary", {}) as Dictionary)
			else:
				_status.text = String(result.get("error", "Loot-box purchase failed."))
		CATEGORY_ROUTES:
			if not bool(_selected_entry.get("unlocked", false)):
				_status.text = String(_selected_entry.get(
					"unlock_requirement",
					"Reach the end of the previous route first."
				))
				return
			travel_requested.emit(_category, int(_selected_entry.get("index", 0)))
		CATEGORY_GYMS, CATEGORY_CHAMPION:
			travel_requested.emit(_category, int(_selected_entry.get("index", 0)))


func _show_purchase_result(result: Dictionary) -> void:
	if bool(result.get("ok", false)):
		var summary := result.get("summary", {}) as Dictionary
		_status.text = "Purchased %s for %s." % [
			String(summary.get("name", "offer")),
			StretchGoalSystem.format_money(int(summary.get("price", 0))),
		]
	else:
		_status.text = String(result.get("error", "Purchase failed."))
	var selected_indices := _list.get_selected_items()
	if not selected_indices.is_empty():
		var selected_index := int(selected_indices[0])
		_list.set_item_text(selected_index, _entry_text(_selected_entry))
		_on_item_selected(selected_index)


func _item_details(entry: Dictionary) -> String:
	var owned := StretchGoalSystem.get_item_count(
		String(entry.get("key", entry.get("slug", "")))
	)
	return (
		"[font_size=26][b]%s[/b][/font_size]\n\n"
		+ "[b]Price:[/b] %s\n[b]Category:[/b] %s\n[b]Owned:[/b] %d\n\n%s\n\n"
		+ "[color=#e4b663]R&D inventory only: buying is persistent, but using item "
		+ "effects is intentionally deferred.[/color]"
	) % [
		String(entry.get("name", "Item")),
		StretchGoalSystem.format_money(int(entry.get("price", 0))),
		String(entry.get("category", "miscellaneous")).replace("-", " ").capitalize(),
		owned,
		String(entry.get("description", "No description available.")),
	]


func _pokemon_details(entry: Dictionary) -> String:
	var rarity := "Mythical" if bool(entry.get("isMythical", false)) else (
		"Legendary" if bool(entry.get("isLegendary", false)) else "Standard"
	)
	return (
		"[font_size=26][b]#%04d %s[/b][/font_size]\n\n"
		+ "[color=#88d8ff]Animated GIF sprite preview[/color]\n\n"
		+ "[b]Price:[/b] %s\n[b]Community tier:[/b] %s\n[b]Rarity:[/b] %s\n"
		+ "[b]Appeal markup:[/b] %s\n[b]Stretchman coolness:[/b] %d / 100\n"
		+ "[b]Delivered level:[/b] %d\n\nPurchased Pokemon are added safely to "
		+ "CollectionSystem storage. Ordinary species are affordable; rarity, tier, "
		+ "and Stretchman's subjective cool-factor markup drive premium prices."
	) % [
		int(entry.get("id", 0)),
		String(entry.get("name", "Pokemon")),
		StretchGoalSystem.format_money(int(entry.get("price", 0))),
		String(entry.get("tier", "Unranked")),
		rarity,
		String(entry.get("appeal", "standard")).capitalize(),
		_pokemon_coolness_score(entry),
		StretchGoalSystem.get_pokemon_purchase_level(int(entry.get("id", 0))),
	]


func _loot_box_details(entry: Dictionary) -> String:
	return (
		"[font_size=18][color=#ffb84d]%s[/color][/font_size]\n"
		+ "[font_size=26][b]%s[/b][/font_size]\n\n"
		+ "[b]Price:[/b] %s\n[b]Prize level:[/b] %d\n"
		+ "[b]High-quality chance:[/b] 10%% for every tier\n"
		+ "[b]This tier's high-quality table:[/b] %s\n\n"
		+ "The other 90%% is always Voltorb, Electrode, Igglybuff, Cleffa, Plusle, "
		+ "Minun, Budew, Mantyke, or Bidoof. Higher prices improve only the "
		+ "high-quality table—not the 10%% hit rate. The awarded Pokemon goes to storage."
	) % [
		String(entry.get("tier", "Tier")),
		String(entry.get("name", "Loot Box")),
		StretchGoalSystem.format_money(int(entry.get("price", 0))),
		int(entry.get("level", 1)),
		String(entry.get("quality_label", "Premium Pokemon")),
	]


func _open_loot_box_result(summary: Dictionary) -> void:
	_loot_box_roulette = LootBoxScene.instantiate() as RNDLootBoxRoulette
	if _loot_box_roulette == null:
		_status.text = (
			"Prize awarded: %s. The reveal UI could not open."
			% String(summary.get("pokemon_name", "Pokemon"))
		)
		return
	_loot_box_roulette.closed.connect(_on_loot_box_roulette_closed)
	add_child(_loot_box_roulette)
	_loot_box_roulette.present(summary)


func _on_loot_box_roulette_closed() -> void:
	var prize_name := (
		String(_loot_box_roulette._summary.get("pokemon_name", "Pokemon"))
		if is_instance_valid(_loot_box_roulette)
		else "Pokemon"
	)
	_loot_box_roulette = null
	_status.text = "%s was added to Pokemon storage." % prize_name
	_refresh_entries()


func _destination_details(entry: Dictionary, heading: String) -> String:
	var last_reward := StretchGoalSystem.get_last_battle_reward()
	var reward_text := ""
	if not last_reward.is_empty():
		reward_text = "\n\n[b]Last battle payout:[/b] %s against %s" % [
			StretchGoalSystem.format_money(int(last_reward.get("amount", 0))),
			String(last_reward.get("opponent", "an opponent")),
		]
	var route_progress_text := ""
	if _category == CATEGORY_ROUTES:
		route_progress_text = "\n\n[b]Progress:[/b] %s\n[b]Unlock rule:[/b] %s" % [
			"Complete" if bool(entry.get("completed", false)) else (
				"Available" if bool(entry.get("unlocked", false)) else "Locked"
			),
			String(entry.get("unlock_requirement", "Reach the previous route's end.")),
		]
	return (
		"[font_size=18][color=#88d8ff]%s[/color][/font_size]\n"
		+ "[font_size=26][b]%s[/b][/font_size]\n\n%s%s%s\n\n"
		+ "Selecting this starts a fresh run. Trainers challenge automatically when "
		+ "you move into their sight line."
	) % [
		heading,
		String(entry.get("name", "Destination")),
		String(entry.get("description", "")),
		route_progress_text,
		reward_text,
	]


func _on_balance_changed(balance: int) -> void:
	if is_instance_valid(_balance_label):
		_balance_label.text = StretchGoalSystem.format_money(balance)
