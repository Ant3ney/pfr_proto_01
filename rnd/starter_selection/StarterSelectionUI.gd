class_name RNDStarterSelectionUI
extends CanvasLayer

## Mandatory fresh-profile starter picker. Each card retains one exact
## front-facing battle GIF atlas and advances it with the source frame timing.

signal starter_chosen(pokemon_id: int)

const ANIMATION_NAME := &"idle"

var _root: Control
var _cards: HBoxContainer
var _status: Label
var _confirmation: Control
var _confirmation_title: Label
var _confirmation_message: Label
var _confirm_button: Button
var _choice_buttons: Dictionary = {}
var _choices_by_id: Dictionary = {}
var _animations: Array[Dictionary] = []
var _pending_pokemon_id := 0
var _input_locked := false


func _ready() -> void:
	_build_interface()
	set_process(false)
	set_process_unhandled_input(true)


func _exit_tree() -> void:
	_release_animation_assets()


func _process(delta: float) -> void:
	for animation_index in _animations.size():
		var state := _animations[animation_index]
		var frames := state.get("frames") as SpriteFrames
		var preview := state.get("preview") as TextureRect
		if frames == null or not is_instance_valid(preview):
			continue
		var frame_count := frames.get_frame_count(ANIMATION_NAME)
		if frame_count <= 1:
			continue
		var frame := int(state.get("frame", 0))
		var elapsed := float(state.get("elapsed", 0.0)) + delta
		var duration := _frame_duration(frames, frame)
		while elapsed >= duration:
			elapsed -= duration
			frame = (frame + 1) % frame_count
			preview.texture = frames.get_frame_texture(ANIMATION_NAME, frame)
			duration = _frame_duration(frames, frame)
		state["frame"] = frame
		state["elapsed"] = elapsed


func show_choices(choices: Array[Dictionary]) -> void:
	_clear_cards()
	_input_locked = false
	_pending_pokemon_id = 0
	_confirmation.visible = false
	_choices_by_id.clear()
	for choice in choices:
		var pokemon_id := int(choice.get("pokemonId", 0))
		if pokemon_id <= 0 or _choices_by_id.has(pokemon_id):
			continue
		var copied := choice.duplicate(true)
		_choices_by_id[pokemon_id] = copied
		_build_starter_card(copied)
	_status.text = "Choose carefully. This Pokémon will be the first member of your party."
	_root.visible = true
	set_process(not _animations.is_empty())
	var buttons := get_starter_buttons()
	if not buttons.is_empty():
		buttons[0].grab_focus()


func hide_ui() -> void:
	_root.visible = false
	_confirmation.visible = false
	_pending_pokemon_id = 0
	_input_locked = false
	set_process(false)


func show_error(message: String) -> void:
	_input_locked = false
	_status.text = message
	_confirmation.visible = false
	for button_value: Variant in _choice_buttons.values():
		(button_value as Button).disabled = false


func request_choice(pokemon_id: int) -> bool:
	if _input_locked or not _choices_by_id.has(pokemon_id):
		return false
	_pending_pokemon_id = pokemon_id
	var choice := _choices_by_id[pokemon_id] as Dictionary
	var pokemon_name := String(choice.get("name", "this Pokémon"))
	_confirmation_title.text = "CHOOSE %s?" % pokemon_name.to_upper()
	_confirmation_message.text = (
		"%s will become your only starting Pokémon at Lv. %d. "
		+ "You cannot choose a different starter after confirming."
	) % [pokemon_name, int(choice.get("level", 5))]
	_confirm_button.text = "YES — START WITH %s" % pokemon_name.to_upper()
	_confirmation.visible = true
	_confirm_button.grab_focus()
	return true


func confirm_choice() -> bool:
	if _input_locked or not _choices_by_id.has(_pending_pokemon_id):
		return false
	_input_locked = true
	_confirmation.visible = false
	for button_value: Variant in _choice_buttons.values():
		(button_value as Button).disabled = true
	_status.text = "Preparing your new partner…"
	starter_chosen.emit(_pending_pokemon_id)
	return true


func get_starter_buttons() -> Array[Button]:
	var result: Array[Button] = []
	for child: Node in _cards.get_children():
		var button := child.find_child("ChooseStarter", true, false) as Button
		if button != null:
			result.append(button)
	return result


func get_choice_button(pokemon_id: int) -> Button:
	return _choice_buttons.get(pokemon_id) as Button


func get_animation_frame_count(pokemon_id: int) -> int:
	for state in _animations:
		if int(state.get("pokemonId", 0)) != pokemon_id:
			continue
		var frames := state.get("frames") as SpriteFrames
		return frames.get_frame_count(ANIMATION_NAME) if frames != null else 0
	return 0


func is_confirmation_visible() -> bool:
	return is_instance_valid(_confirmation) and _confirmation.visible


func get_confirm_button() -> Button:
	return _confirm_button


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _confirmation.visible and not _input_locked:
		_close_confirmation()
	else:
		_status.text = "A starter is required before the adventure can begin."


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "Root"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.006, 0.015, 0.025, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(dim)

	var panel := PanelContainer.new()
	panel.name = "StarterPanel"
	panel.anchor_left = 0.025
	panel.anchor_top = 0.025
	panel.anchor_right = 0.975
	panel.anchor_bottom = 0.975
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override(
		"panel",
		_style_box(Color("10243a"), Color("79c9ff"), 3, 18)
	)
	_root.add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 18)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var kicker := Label.new()
	kicker.text = "A NEW JOURNEY BEGINS"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override("font_color", Color("79c9ff"))
	kicker.add_theme_font_size_override("font_size", 13)
	column.add_child(kicker)
	var title := Label.new()
	title.text = "CHOOSE YOUR STARTER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color("f4fbff"))
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Three regions. Three partners. One permanent first choice."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color("b8cbd9"))
	subtitle.add_theme_font_size_override("font_size", 15)
	column.add_child(subtitle)

	_cards = HBoxContainer.new()
	_cards.name = "StarterCards"
	_cards.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_cards.add_theme_constant_override("separation", 14)
	_cards.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(_cards)

	_status = Label.new()
	_status.name = "Status"
	_status.custom_minimum_size = Vector2(0.0, 26.0)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("d9e8ef"))
	_status.add_theme_font_size_override("font_size", 14)
	column.add_child(_status)

	_build_confirmation()


func _build_starter_card(choice: Dictionary) -> void:
	var pokemon_id := int(choice.get("pokemonId", 0))
	var accent := Color(String(choice.get("color", "6b9dbb")))
	var card := PanelContainer.new()
	card.name = "%sCard" % String(choice.get("name", "Starter"))
	card.custom_minimum_size = Vector2(265.0, 315.0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override(
		"panel",
		_style_box(Color("0b1825"), accent, 3, 14)
	)
	_cards.add_child(card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 12)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var type_label := Label.new()
	type_label.text = "%s TYPE  ·  %s" % [
		String(choice.get("type", "Unknown")).to_upper(),
		String(choice.get("generation", "Unknown region")).to_upper(),
	]
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	type_label.add_theme_color_override("font_color", accent.lightened(0.22))
	type_label.add_theme_font_size_override("font_size", 12)
	column.add_child(type_label)

	var preview_panel := PanelContainer.new()
	preview_panel.custom_minimum_size = Vector2(0.0, 180.0)
	preview_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview_panel.add_theme_stylebox_override(
		"panel",
		_style_box(Color("07111b"), accent.darkened(0.2), 1, 10)
	)
	column.add_child(preview_panel)
	var center := CenterContainer.new()
	preview_panel.add_child(center)
	var preview := TextureRect.new()
	preview.name = "AnimatedGif"
	preview.custom_minimum_size = Vector2(200.0, 170.0)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	center.add_child(preview)
	_load_animation(choice, preview)

	var name_label := Label.new()
	name_label.text = String(choice.get("name", "Pokémon")).to_upper()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color("f4fbff"))
	name_label.add_theme_font_size_override("font_size", 24)
	column.add_child(name_label)
	var region_label := Label.new()
	region_label.text = "%s REGION  ·  Lv. %d" % [
		String(choice.get("region", "Unknown")).to_upper(),
		int(choice.get("level", 5)),
	]
	region_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	region_label.add_theme_color_override("font_color", Color("a9bac7"))
	region_label.add_theme_font_size_override("font_size", 12)
	column.add_child(region_label)
	var choose := Button.new()
	choose.name = "ChooseStarter"
	choose.text = "CHOOSE %s" % String(choice.get("name", "Starter")).to_upper()
	choose.custom_minimum_size = Vector2(0.0, 46.0)
	choose.add_theme_color_override("font_color", Color.WHITE)
	choose.add_theme_color_override("font_hover_color", Color.WHITE)
	choose.add_theme_stylebox_override(
		"normal",
		_style_box(accent.darkened(0.32), accent, 2, 9)
	)
	choose.add_theme_stylebox_override(
		"hover",
		_style_box(accent.darkened(0.15), accent.lightened(0.2), 2, 9)
	)
	choose.pressed.connect(request_choice.bind(pokemon_id))
	column.add_child(choose)
	_choice_buttons[pokemon_id] = choose


func _load_animation(choice: Dictionary, preview: TextureRect) -> void:
	var catalog := BattleSpriteCatalog.new()
	if not catalog.initialize():
		return
	var asset := catalog.load_active(String(choice.get("spriteId", "")), false)
	var frames := asset.get("sprite_frames") as SpriteFrames
	if frames == null or frames.get_frame_count(ANIMATION_NAME) <= 0:
		catalog.release_all()
		return
	preview.texture = frames.get_frame_texture(ANIMATION_NAME, 0)
	_animations.append({
		"pokemonId": int(choice.get("pokemonId", 0)),
		"catalog": catalog,
		"frames": frames,
		"preview": preview,
		"frame": 0,
		"elapsed": 0.0,
	})


func _build_confirmation() -> void:
	_confirmation = ColorRect.new()
	_confirmation.name = "StarterConfirmation"
	_confirmation.color = Color(0.005, 0.008, 0.012, 0.9)
	_confirmation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirmation.visible = false
	_confirmation.z_index = 50
	_root.add_child(_confirmation)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirmation.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560.0, 250.0)
	panel.add_theme_stylebox_override(
		"panel",
		_style_box(Color("111b25"), Color("ffd166"), 3, 16)
	)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	_confirmation_title = Label.new()
	_confirmation_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirmation_title.add_theme_color_override("font_color", Color("ffd166"))
	_confirmation_title.add_theme_font_size_override("font_size", 26)
	column.add_child(_confirmation_title)
	_confirmation_message = Label.new()
	_confirmation_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_confirmation_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirmation_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_confirmation_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirmation_message.add_theme_font_size_override("font_size", 16)
	column.add_child(_confirmation_message)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	column.add_child(buttons)
	var back := Button.new()
	back.name = "Back"
	back.text = "GO BACK"
	back.custom_minimum_size = Vector2(150.0, 48.0)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_close_confirmation)
	buttons.add_child(back)
	_confirm_button = Button.new()
	_confirm_button.name = "ConfirmStarter"
	_confirm_button.custom_minimum_size = Vector2(260.0, 48.0)
	_confirm_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_button.pressed.connect(confirm_choice)
	buttons.add_child(_confirm_button)


func _close_confirmation() -> void:
	if _input_locked:
		return
	_confirmation.visible = false
	var button := get_choice_button(_pending_pokemon_id)
	_pending_pokemon_id = 0
	if button != null:
		button.grab_focus()


func _clear_cards() -> void:
	_release_animation_assets()
	_choice_buttons.clear()
	if not is_instance_valid(_cards):
		return
	for child: Node in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()


func _release_animation_assets() -> void:
	for state in _animations:
		var catalog := state.get("catalog") as BattleSpriteCatalog
		if catalog != null:
			catalog.release_all()
	_animations.clear()


func _frame_duration(frames: SpriteFrames, frame: int) -> float:
	var speed := maxf(frames.get_animation_speed(ANIMATION_NAME), 0.001)
	return maxf(
		frames.get_frame_duration(ANIMATION_NAME, frame) / speed,
		0.001
	)


func _style_box(
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
