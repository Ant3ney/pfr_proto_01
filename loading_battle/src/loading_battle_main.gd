extends Control

## Silent, practice-only UI shown while the production PCK fills its cache.

const SESSION_SCRIPT = preload("res://src/loading_battle_session.gd")
const RULES = preload("res://src/loading_battle_rules.gd")
const SPRITE_SCRIPT = preload("res://src/loading_battle_sprite.gd")

const INK := Color("#0e1728")
const PANEL := Color("#182943e8")
const PANEL_LIGHT := Color("#233958f2")
const CREAM := Color("#fff3d2")
const MUTED := Color("#aebdd2")
const BLUE := Color("#65bce9")
const RED := Color("#ef795e")
const GOLD := Color("#f1c878")

var _session: LoadingBattleSession
var _starter_screen: Control
var _starter_grid: GridContainer
var _starter_cards: Array[Control] = []
var _starter_buttons: Array[Button] = []
var _battle_screen: Control
var _tier_label: Label
var _streak_label: Label
var _message_label: Label
var _error_label: Label
var _retry_button: Button
var _next_button: Button
var _concede_button: Button
var _move_buttons: Array[Button] = []
var _allowed_move_indices: Dictionary = {}
var _player_name: Label
var _player_hp_text: Label
var _player_hp: ProgressBar
var _opponent_name: Label
var _opponent_hp_text: Label
var _opponent_hp: ProgressBar
var _player_sprite: LoadingBattleSprite
var _opponent_sprite: LoadingBattleSprite
var _battle_tier := "medium"
var _event_sequence := 0
var _online_poll_elapsed := 0.0
var _was_online := true


func _ready() -> void:
	_build_ui()
	_session = SESSION_SCRIPT.new()
	_session.name = "PracticeBattleSession"
	add_child(_session)
	_session.state_changed.connect(_on_state_changed)
	_session.snapshot_changed.connect(_on_snapshot_changed)
	_session.presentation_events_ready.connect(_on_events_ready)
	_session.choice_request_changed.connect(_on_choice_request_changed)
	_session.practice_error_changed.connect(_on_practice_error_changed)
	_session.battle_finished.connect(_on_battle_finished)
	_was_online = _browser_online()
	set_process(OS.get_name() == "Web")
	get_viewport().size_changed.connect(_update_responsive_layout)
	_update_responsive_layout()


func _process(delta: float) -> void:
	_online_poll_elapsed += delta
	if _online_poll_elapsed < 0.5:
		return
	_online_poll_elapsed = 0.0
	var online := _browser_online()
	if online and not _was_online:
		_session.resume_after_reconnect()
	_was_online = online


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = INK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var glow_left := ColorRect.new()
	glow_left.color = Color("#173d66")
	glow_left.anchor_right = 0.52
	glow_left.anchor_bottom = 1.0
	glow_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow_left)
	var glow_right := ColorRect.new()
	glow_right.color = Color("#4c252e")
	glow_right.anchor_left = 0.52
	glow_right.anchor_right = 1.0
	glow_right.anchor_bottom = 1.0
	glow_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow_right)

	var header := PanelContainer.new()
	header.anchor_right = 1.0
	header.offset_left = 14.0
	header.offset_top = 10.0
	header.offset_right = -14.0
	header.offset_bottom = 58.0
	header.add_theme_stylebox_override("panel", _style(PANEL, 14, GOLD, 1))
	add_child(header)
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 14)
	header.add_child(header_row)
	var title := _label("LOADING BATTLE", 20, CREAM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)
	_tier_label = _label("Choose a partner", 15, GOLD)
	header_row.add_child(_tier_label)
	_streak_label = _label("Practice only • nothing is saved", 13, MUTED)
	header_row.add_child(_streak_label)

	_starter_screen = _build_starter_screen()
	add_child(_starter_screen)
	_battle_screen = _build_battle_screen()
	_battle_screen.visible = false
	add_child(_battle_screen)


func _build_starter_screen() -> Control:
	var screen := Control.new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	screen.offset_top = 62.0
	var content := VBoxContainer.new()
	content.anchor_left = 0.08
	content.anchor_top = 0.05
	content.anchor_right = 0.92
	content.anchor_bottom = 0.94
	content.add_theme_constant_override("separation", 12)
	screen.add_child(content)
	var prompt := _label("Choose a partner for a few practice rounds", 28, CREAM)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(prompt)
	var explanation := _label(
		"Your choice, results, and HP vanish when you enter the adventure.",
		15,
		MUTED
	)
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(explanation)
	_starter_grid = GridContainer.new()
	_starter_grid.columns = 3
	_starter_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_starter_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_starter_grid.add_theme_constant_override("h_separation", 16)
	_starter_grid.add_theme_constant_override("v_separation", 10)
	content.add_child(_starter_grid)
	for starter_id: String in RULES.STARTERS:
		var card := _starter_card(starter_id)
		_starter_cards.append(card)
		_starter_grid.add_child(card)
	return screen


func _starter_card(starter_id: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 280)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(PANEL, 18, Color("#4f6f94"), 1))
	var column := VBoxContainer.new()
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var sprite: LoadingBattleSprite = SPRITE_SCRIPT.new()
	sprite.custom_minimum_size = Vector2(150, 160)
	column.add_child(sprite)
	sprite.call_deferred("configure", "ani", starter_id)
	var name_label := _label(_display_name(starter_id), 23, CREAM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)
	var type_label := _label(_starter_type(starter_id), 14, _starter_color(starter_id))
	type_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(type_label)
	var choose := _button("Choose %s" % _display_name(starter_id), BLUE)
	choose.custom_minimum_size.y = 76
	choose.pressed.connect(_on_starter_chosen.bind(starter_id))
	column.add_child(choose)
	_starter_buttons.append(choose)
	return panel


func _build_battle_screen() -> Control:
	var screen := Control.new()
	screen.anchor_right = 1.0
	screen.anchor_bottom = 1.0
	screen.offset_top = 62.0

	var opponent_card := _status_card(true)
	opponent_card.anchor_left = 0.61
	opponent_card.anchor_top = 0.02
	opponent_card.anchor_right = 0.965
	opponent_card.anchor_bottom = 0.16
	screen.add_child(opponent_card)
	_opponent_name = opponent_card.get_node("Margin/Column/Row/Name")
	_opponent_hp_text = opponent_card.get_node("Margin/Column/Row/HPText")
	_opponent_hp = opponent_card.get_node("Margin/Column/HP")

	_opponent_sprite = SPRITE_SCRIPT.new()
	_opponent_sprite.anchor_left = 0.52
	_opponent_sprite.anchor_top = 0.12
	_opponent_sprite.anchor_right = 0.91
	_opponent_sprite.anchor_bottom = 0.46
	screen.add_child(_opponent_sprite)

	_player_sprite = SPRITE_SCRIPT.new()
	_player_sprite.anchor_left = 0.05
	_player_sprite.anchor_top = 0.12
	_player_sprite.anchor_right = 0.43
	_player_sprite.anchor_bottom = 0.46
	screen.add_child(_player_sprite)

	var player_card := _status_card(false)
	player_card.anchor_left = 0.035
	player_card.anchor_top = 0.36
	player_card.anchor_right = 0.39
	player_card.anchor_bottom = 0.48
	screen.add_child(player_card)
	_player_name = player_card.get_node("Margin/Column/Row/Name")
	_player_hp_text = player_card.get_node("Margin/Column/Row/HPText")
	_player_hp = player_card.get_node("Margin/Column/HP")

	var hud := HBoxContainer.new()
	hud.anchor_left = 0.025
	hud.anchor_top = 0.50
	hud.anchor_right = 0.975
	hud.anchor_bottom = 0.99
	hud.add_theme_constant_override("separation", 10)
	screen.add_child(hud)

	var message_panel := PanelContainer.new()
	message_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	message_panel.size_flags_stretch_ratio = 1.08
	message_panel.add_theme_stylebox_override("panel", _style(PANEL, 14, Color("#4f6f94"), 1))
	hud.add_child(message_panel)
	var message_column := VBoxContainer.new()
	message_column.add_theme_constant_override("separation", 5)
	message_panel.add_child(message_column)
	_message_label = _label("The practice arena is ready.", 18, CREAM)
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	message_column.add_child(_message_label)
	_error_label = _label("", 13, Color("#ffb7a3"))
	_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error_label.visible = false
	message_column.add_child(_error_label)
	_retry_button = _button("Retry Battle", RED)
	_retry_button.visible = false
	_retry_button.pressed.connect(_on_retry_pressed)
	message_column.add_child(_retry_button)

	var commands := VBoxContainer.new()
	commands.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commands.size_flags_stretch_ratio = 1.0
	commands.add_theme_constant_override("separation", 6)
	hud.add_child(commands)
	var move_grid := GridContainer.new()
	move_grid.columns = 2
	move_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	move_grid.add_theme_constant_override("h_separation", 6)
	move_grid.add_theme_constant_override("v_separation", 6)
	commands.add_child(move_grid)
	for index in range(4):
		var move_button := _button("Move %d" % (index + 1), BLUE if index < 2 else RED)
		move_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		move_button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		move_button.pressed.connect(_on_move_pressed.bind(index + 1))
		move_grid.add_child(move_button)
		_move_buttons.append(move_button)
	var command_row := HBoxContainer.new()
	command_row.custom_minimum_size.y = 64
	command_row.add_theme_constant_override("separation", 6)
	commands.add_child(command_row)
	_concede_button = _button("Concede", Color("#8f5362"))
	_concede_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_concede_button.pressed.connect(_on_concede_pressed)
	command_row.add_child(_concede_button)
	_next_button = _button("Next Battle", GOLD)
	_next_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_next_button.visible = false
	_next_button.pressed.connect(_on_next_pressed)
	command_row.add_child(_next_button)
	_set_choices_enabled(false)
	return screen


func _update_responsive_layout() -> void:
	if not is_instance_valid(_starter_grid):
		return
	var viewport_size := get_viewport_rect().size
	var portrait := viewport_size.y > viewport_size.x
	_starter_grid.columns = 1 if portrait else 3
	for card in _starter_cards:
		card.custom_minimum_size = Vector2(210, 350 if portrait else 280)
	for button in _starter_buttons:
		button.custom_minimum_size.y = 108 if portrait else 76


func _status_card(opponent: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(PANEL_LIGHT, 13, RED if opponent else BLUE, 1))
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 9)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var row := HBoxContainer.new()
	row.name = "Row"
	column.add_child(row)
	var name_label := _label("Opponent" if opponent else "Partner", 15, CREAM)
	name_label.name = "Name"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var hp_text := _label("HP", 12, MUTED)
	hp_text.name = "HPText"
	row.add_child(hp_text)
	var hp := ProgressBar.new()
	hp.name = "HP"
	hp.show_percentage = false
	hp.max_value = 1.0
	hp.value = 1.0
	hp.custom_minimum_size.y = 10
	hp.add_theme_stylebox_override("background", _style(Color("#0b1422"), 5))
	hp.add_theme_stylebox_override("fill", _style(Color("#55d28a"), 5))
	column.add_child(hp)
	return card


func _on_starter_chosen(starter_id: String) -> void:
	_battle_tier = "medium"
	_starter_screen.visible = false
	_battle_screen.visible = true
	_player_sprite.configure("ani-back", starter_id)
	_opponent_sprite.configure("ani", "ditto")
	_tier_label.text = RULES.tier_title(_battle_tier)
	_message_label.text = "Contacting the practice arena…"
	_session.select_starter(starter_id)


func _on_move_pressed(move_index: int) -> void:
	if _session.choose_move(move_index):
		_message_label.text = "Sending your move…"


func _on_concede_pressed() -> void:
	if _session.concede():
		_message_label.text = "Conceding this practice round…"


func _on_retry_pressed() -> void:
	_retry_button.disabled = true
	_message_label.text = "Retrying the exact practice request…"
	_session.retry_pending_request()


func _on_next_pressed() -> void:
	_battle_tier = _session.difficulty
	_tier_label.text = RULES.tier_title(_battle_tier)
	_next_button.visible = false
	_concede_button.visible = true
	_error_label.visible = false
	_retry_button.visible = false
	_opponent_sprite.configure("ani", RULES.opponent_sprite_id(_session.selected_starter, _battle_tier))
	_message_label.text = "Preparing the next practice round…"
	_session.start_next_battle()


func _on_state_changed(state: String) -> void:
	_set_choices_enabled(state == LoadingBattleSession.STATE_AWAITING_PLAYER)
	if state == LoadingBattleSession.STATE_SUBMITTING:
		_concede_button.disabled = true


func _on_snapshot_changed(snapshot: Dictionary) -> void:
	var parties_value: Variant = snapshot.get("parties")
	if typeof(parties_value) != TYPE_DICTIONARY:
		return
	var parties := parties_value as Dictionary
	_update_member_status((parties.get("player", []) as Array), true)
	_update_member_status((parties.get("opponent", []) as Array), false)


func _update_member_status(members: Array, player: bool) -> void:
	if members.is_empty() or typeof(members[0]) != TYPE_DICTIONARY:
		return
	var member := members[0] as Dictionary
	var hp := int(member.get("hp", 0))
	var max_hp := maxi(int(member.get("maxHp", 1)), 1)
	var name_label := _player_name if player else _opponent_name
	var hp_text := _player_hp_text if player else _opponent_hp_text
	var hp_bar := _player_hp if player else _opponent_hp
	name_label.text = "%s  Lv.%d" % [String(member.get("nickname", "Partner")), int(member.get("level", 1))]
	hp_text.text = "%d / %d" % [hp, max_hp]
	hp_bar.value = float(hp) / float(max_hp)
	var fill_color := Color("#55d28a")
	if hp_bar.value <= 0.25:
		fill_color = RED
	elif hp_bar.value <= 0.5:
		fill_color = GOLD
	hp_bar.add_theme_stylebox_override("fill", _style(fill_color, 5))


func _on_events_ready(events: Array, revision: int) -> void:
	_event_sequence += 1
	_play_event_sequence(events.duplicate(true), revision, _event_sequence)


func _play_event_sequence(events: Array, revision: int, sequence: int) -> void:
	_set_choices_enabled(false)
	if events.is_empty():
		await get_tree().process_frame
	for value: Variant in events:
		if sequence != _event_sequence:
			return
		if typeof(value) == TYPE_DICTIONARY:
			var message := String((value as Dictionary).get("message", "")).strip_edges()
			if not message.is_empty():
				_message_label.text = message
		await get_tree().create_timer(0.58).timeout
	if sequence == _event_sequence:
		_session.acknowledge_events_presented(revision)


func _on_choice_request_changed(request: Dictionary) -> void:
	_allowed_move_indices.clear()
	for index in range(_move_buttons.size()):
		_move_buttons[index].text = "—"
		_move_buttons[index].disabled = true
	if String(request.get("type", "")) != "move":
		return
	for value: Variant in request.get("moves", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var move := value as Dictionary
		var button_index := int(move.get("moveIndex", 0)) - 1
		if button_index < 0 or button_index >= _move_buttons.size():
			continue
		_move_buttons[button_index].text = "%s\nPP %d/%d" % [
			String(move.get("name", "Move")),
			int(move.get("pp", 0)),
			int(move.get("maxPp", 0)),
		]
		if not bool(move.get("disabled", true)):
			_allowed_move_indices[button_index] = true
		_move_buttons[button_index].disabled = not _allowed_move_indices.has(button_index)
	_set_choices_enabled(_session.can_choose())
	if _session.can_choose():
		_message_label.text = "Choose a move."


func _on_practice_error_changed(error: Dictionary) -> void:
	var has_error := not error.is_empty()
	_error_label.visible = has_error
	_retry_button.visible = has_error
	_retry_button.disabled = not has_error
	if not has_error:
		return
	var offline := String(error.get("code", "")) == "offline"
	_error_label.text = (
		"Offline — this exact action will resume after reconnection."
		if offline
		else String(error.get("message", "Practice battle unavailable."))
	)
	_message_label.text = "The adventure download continues separately."
	_set_choices_enabled(false)


func _on_battle_finished(result: Dictionary, next_tier: String) -> void:
	var winner := String(result.get("winner", "tie"))
	_message_label.text = (
		"Practice victory!"
		if winner == "player"
		else ("Practice draw." if winner == "tie" else "The opponent won this round.")
	)
	_streak_label.text = "Win streak %d • Next: %s" % [
		_session.win_streak,
		RULES.tier_title(next_tier),
	]
	_concede_button.visible = false
	_next_button.visible = true
	_next_button.disabled = false
	_set_choices_enabled(false)


func _set_choices_enabled(enabled: bool) -> void:
	for index in range(_move_buttons.size()):
		_move_buttons[index].disabled = not (enabled and _allowed_move_indices.has(index))
	if is_instance_valid(_concede_button):
		_concede_button.disabled = not enabled


func _button(text_value: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text_value
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", CREAM)
	button.add_theme_color_override("font_disabled_color", Color("#74839a"))
	button.add_theme_stylebox_override("normal", _style(accent.darkened(0.55), 10, accent, 1))
	button.add_theme_stylebox_override("hover", _style(accent.darkened(0.38), 10, CREAM, 1))
	button.add_theme_stylebox_override("pressed", _style(accent.darkened(0.66), 10, GOLD, 2))
	button.add_theme_stylebox_override("disabled", _style(Color("#182337"), 10, Color("#34445c"), 1))
	return button


func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _style(color: Color, radius: int, border := Color.TRANSPARENT, width := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.border_color = border
	style.border_width_left = width
	style.border_width_top = width
	style.border_width_right = width
	style.border_width_bottom = width
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	return style


func _display_name(starter_id: String) -> String:
	return starter_id.left(1).to_upper() + starter_id.substr(1)


func _starter_type(starter_id: String) -> String:
	return {"charmander": "FIRE", "froakie": "WATER", "treecko": "GRASS"}[starter_id]


func _starter_color(starter_id: String) -> Color:
	return {
		"charmander": RED,
		"froakie": BLUE,
		"treecko": Color("#74d59a"),
	}[starter_id]


func _browser_online() -> bool:
	if OS.get_name() != "Web":
		return true
	var online: Variant = JavaScriptBridge.eval("navigator.onLine", true)
	return bool(online) if typeof(online) == TYPE_BOOL else true
