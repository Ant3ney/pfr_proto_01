class_name BattleChoiceOverlay
extends Control

## Compact presentation surface for server-provided moves, switches, errors,
## and results. It emits typed intents and contains no battle rules.

signal move_chosen(move_index: int)
signal switch_chosen(member_id: String)
signal forfeit_confirmed
signal retry_requested
signal return_requested
signal continue_requested

const MINIMUM_GUTTER := 16.0
const GUTTER_RATIO := 0.015
const TRAY_TOP_OFFSET := -60.0
const TRAY_BOTTOM_OFFSET := -4.0
const TRAY_BUTTON_HEIGHT := 40.0
const MODAL_HALF_WIDTH := 270.0
const MODAL_HALF_HEIGHT := 88.0
const MAX_MOVE_OPTIONS := 4
const SWITCH_THUMBNAIL_SIZE := Vector2i(32, 32)

const GOLD := Color(0.91, 0.73, 0.38, 1.0)
const GOLD_BRIGHT := Color(1.0, 0.91, 0.52, 1.0)
const FOREST_DARK := Color(0.025, 0.075, 0.056, 0.99)
const CHARCOAL := Color(0.035, 0.055, 0.052, 0.99)
const MOVE_TYPE_COLORS := {
	"Bug": Color(0.55, 0.68, 0.12, 1.0),
	"Dark": Color(0.28, 0.24, 0.22, 1.0),
	"Dragon": Color(0.42, 0.28, 0.78, 1.0),
	"Electric": Color(0.88, 0.7, 0.1, 1.0),
	"Fairy": Color(0.82, 0.42, 0.66, 1.0),
	"Fighting": Color(0.64, 0.17, 0.12, 1.0),
	"Fire": Color(0.82, 0.24, 0.08, 1.0),
	"Flying": Color(0.46, 0.62, 0.82, 1.0),
	"Ghost": Color(0.38, 0.3, 0.62, 1.0),
	"Grass": Color(0.25, 0.6, 0.2, 1.0),
	"Ground": Color(0.68, 0.5, 0.2, 1.0),
	"Ice": Color(0.35, 0.72, 0.76, 1.0),
	"Normal": Color(0.56, 0.55, 0.48, 1.0),
	"Poison": Color(0.55, 0.22, 0.61, 1.0),
	"Psychic": Color(0.8, 0.25, 0.48, 1.0),
	"Rock": Color(0.58, 0.49, 0.2, 1.0),
	"Steel": Color(0.48, 0.55, 0.58, 1.0),
	"Water": Color(0.2, 0.44, 0.77, 1.0),
}

@onready var dim: ColorRect = $Dim
@onready var panel: PanelContainer = $Panel
@onready var inner_frame: Panel = $Panel/InnerFrame
@onready var margin: MarginContainer = $Panel/Margin
@onready var content: VBoxContainer = $Panel/Margin/Content
@onready var title_label: Label = %Title
@onready var message_label: Label = %Message
@onready var choice_row: HBoxContainer = $Panel/Margin/Content/ChoiceRow
@onready var options: HBoxContainer = %Options
@onready var footer: HBoxContainer = $Panel/Margin/Content/ChoiceRow/Footer
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton
@onready var retry_button: Button = %RetryButton
@onready var return_button: Button = %ReturnButton
@onready var continue_button: Button = %ContinueButton

var _forced_switch := false
var _surface_mode := &"hidden"
var _sprite_catalog := BattleSpriteCatalog.new()


func _ready() -> void:
	cancel_button.pressed.connect(hide_overlay)
	confirm_button.pressed.connect(_on_forfeit_confirmed)
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	return_button.pressed.connect(func() -> void: return_requested.emit())
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	resized.connect(_layout_current_surface)
	_style_static_button(cancel_button, Color(0.32, 0.39, 0.37, 1.0))
	_style_static_button(confirm_button, Color(0.58, 0.16, 0.11, 1.0))
	_style_static_button(retry_button, Color(0.62, 0.42, 0.08, 1.0))
	_style_static_button(return_button, Color(0.18, 0.35, 0.38, 1.0))
	_style_static_button(continue_button, Color(0.18, 0.48, 0.2, 1.0))
	force_hide()


func hide_overlay() -> void:
	if _forced_switch:
		return
	force_hide()


func force_hide() -> void:
	_forced_switch = false
	_surface_mode = &"hidden"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	_clear_options()
	_hide_static_buttons()


func show_moves(request: Dictionary) -> void:
	_forced_switch = false
	_prepare_tray("CHOOSE A MOVE", "Choose a move, or go back.")
	cancel_button.text = "‹  BACK"
	cancel_button.tooltip_text = "Return to battle actions"
	cancel_button.visible = true
	_set_static_buttons_expand(true)

	var rendered := 0
	for value: Variant in request.get("moves", []):
		if rendered >= MAX_MOVE_OPTIONS:
			break
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var move := value as Dictionary
		var move_id := String(move.get("id", ""))
		var move_type := BattleSpeciesMapping.get_move_type(move_id)
		var disabled := bool(move.get("disabled", true))
		var move_name := String(move.get("name", "Move"))
		var button := _new_option_button(
			_move_button_text(move_name, move_type, move, disabled),
			move_type
		)
		var move_index := int(move.get("moveIndex", 0))
		button.disabled = disabled
		button.tooltip_text = "%s — %s — PP %d/%d%s" % [
			move_name,
			move_type if not move_type.is_empty() else "Unknown type",
			int(move.get("pp", 0)),
			int(move.get("maxPp", 0)),
			" — unavailable" if disabled else "",
		]
		button.set_meta("battle_move_index", move_index)
		button.set_meta("battle_move_id", move_id)
		button.set_meta("battle_move_type", move_type)
		if not disabled:
			button.pressed.connect(_on_move_chosen.bind(move_index))
		rendered += 1
	_update_row_stretch()
	_grab_first_option_focus()


func show_switches(
	request: Dictionary,
	snapshot: Dictionary,
	forced: bool
) -> void:
	_forced_switch = forced
	_prepare_tray(
		"CHOOSE A POKÉMON",
		"Choose a replacement." if forced else "Choose a party member, or go back."
	)
	cancel_button.text = "‹  BACK"
	cancel_button.tooltip_text = "A forced switch cannot be cancelled" if forced else "Return to battle actions"
	cancel_button.visible = not forced
	_set_static_buttons_expand(true)

	var member_by_id := _player_member_map(snapshot)
	for value: Variant in request.get("switchOptions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var member_id := String((value as Dictionary).get("memberId", ""))
		if member_id.is_empty() or not member_by_id.has(member_id):
			continue
		var member: Dictionary = member_by_id[member_id]
		var display_name := _format_member_name(String(
			member.get("nickname", member.get("species", "Pokémon"))
		))
		var button := _new_option_button(
			"%s\nHP %d/%d" % [
				display_name,
				int(member.get("hp", 0)),
				int(member.get("maxHp", 0)),
			],
			"Switch"
		)
		button.tooltip_text = "%s — HP %d/%d" % [
			display_name,
			int(member.get("hp", 0)),
			int(member.get("maxHp", 0)),
		]
		button.set_meta("battle_switch_member_id", member_id)
		_apply_switch_thumbnail(button, member)
		button.pressed.connect(_on_switch_chosen.bind(member_id))
	_update_row_stretch()
	_grab_first_option_focus()


func show_forfeit_confirmation() -> void:
	_forced_switch = false
	_prepare("FORFEIT BATTLE?", "End this battle and return to the overworld?")
	cancel_button.text = "KEEP BATTLING"
	cancel_button.visible = true
	confirm_button.visible = true
	_update_row_stretch()
	confirm_button.grab_focus()


func show_error(error: Dictionary) -> void:
	_forced_switch = true
	_prepare(
		"BATTLE CONNECTION ERROR",
		String(error.get("message", "The battle could not continue."))
	)
	retry_button.visible = bool(error.get("retriable", false))
	return_button.visible = bool(error.get("can_return", true))
	_update_row_stretch()
	if retry_button.visible:
		retry_button.grab_focus()
	elif return_button.visible:
		return_button.grab_focus()


func show_result(result: Dictionary) -> void:
	var winner := String(result.get("winner", "tie"))
	var title := "DRAW"
	var message := "The battle ended in a tie."
	if winner == "player":
		title = "VICTORY"
		message = "You won the battle!"
	elif winner == "opponent":
		title = "BATTLE OVER"
		message = "Your party was defeated."
	_forced_switch = true
	_prepare(title, message)
	continue_button.visible = true
	_update_row_stretch()
	continue_button.grab_focus()


func _prepare(title: String, message: String) -> void:
	_clear_options()
	_hide_static_buttons()
	_surface_mode = &"modal"
	title_label.text = title
	message_label.text = message
	title_label.visible = true
	message_label.visible = true
	options.visible = false
	dim.visible = true
	_set_static_buttons_expand(false)
	_apply_surface_style(true)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_current_surface()


func _prepare_tray(title: String, message: String) -> void:
	_clear_options()
	_hide_static_buttons()
	_surface_mode = &"tray"
	title_label.text = title
	message_label.text = message
	title_label.visible = false
	message_label.visible = false
	options.visible = true
	dim.visible = false
	_apply_surface_style(false)
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_current_surface()


func _layout_current_surface() -> void:
	if not is_instance_valid(panel):
		return
	if _surface_mode == &"tray":
		var gutter := maxf(MINIMUM_GUTTER, size.x * GUTTER_RATIO)
		panel.anchor_left = 0.0
		panel.anchor_top = 1.0
		panel.anchor_right = 1.0
		panel.anchor_bottom = 1.0
		panel.offset_left = gutter
		panel.offset_top = TRAY_TOP_OFFSET
		panel.offset_right = -gutter
		panel.offset_bottom = TRAY_BOTTOM_OFFSET
	elif _surface_mode == &"modal":
		var half_width := minf(MODAL_HALF_WIDTH, maxf(160.0, size.x * 0.46))
		panel.anchor_left = 0.5
		panel.anchor_top = 0.5
		panel.anchor_right = 0.5
		panel.anchor_bottom = 0.5
		panel.offset_left = -half_width
		panel.offset_top = -MODAL_HALF_HEIGHT
		panel.offset_right = half_width
		panel.offset_bottom = MODAL_HALF_HEIGHT


func _apply_surface_style(modal: bool) -> void:
	if modal:
		panel.add_theme_stylebox_override(
			"panel",
			_style_box(CHARCOAL, GOLD, 3, 14, 12, Color(0.0, 0.0, 0.0, 0.62))
		)
		inner_frame.add_theme_stylebox_override(
			"panel",
			_style_box(Color(0.0, 0.0, 0.0, 0.0), Color(0.5, 0.39, 0.19, 0.9), 1, 10)
		)
		_set_margin(20, 13, 20, 13)
		content.add_theme_constant_override("separation", 8)
	else:
		panel.add_theme_stylebox_override(
			"panel",
			_style_box(CHARCOAL, GOLD, 2, 10, 5, Color(0.0, 0.0, 0.0, 0.64))
		)
		inner_frame.add_theme_stylebox_override(
			"panel",
			_style_box(Color(0.0, 0.0, 0.0, 0.0), Color(0.5, 0.39, 0.19, 0.82), 1, 7)
		)
		_set_margin(7, 6, 7, 6)
		content.add_theme_constant_override("separation", 0)


func _set_margin(left: int, top: int, right: int, bottom: int) -> void:
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)


func _new_option_button(text: String, option_kind := "") -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(92.0, TRAY_BUTTON_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.theme_type_variation = &"BattleChoiceButton"
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_constant_override("outline_size", 1)
	button.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.66))
	button.set_meta("battle_option_dynamic", true)
	_style_option_button(button, option_kind)
	options.add_child(button)
	return button


func _move_button_text(
	move_name: String,
	move_type: String,
	move: Dictionary,
	disabled: bool
) -> String:
	var availability := "  [LOCKED]" if disabled else ""
	var type_label := move_type.to_upper() if not move_type.is_empty() else "TYPE —"
	return "%s%s\n%s  •  PP %d/%d" % [
		move_name,
		availability,
		type_label,
		int(move.get("pp", 0)),
		int(move.get("maxPp", 0)),
	]


func _apply_switch_thumbnail(button: Button, member: Dictionary) -> void:
	var sprite_id := String(member.get("spriteId", ""))
	var thumbnail := _sprite_catalog.load_front_thumbnail(
		sprite_id,
		bool(member.get("shiny", false)),
		String(member.get("spriteOverride", "")),
		SWITCH_THUMBNAIL_SIZE
	)
	button.set_meta("battle_switch_sprite_id", sprite_id)
	button.set_meta("battle_switch_thumbnail_style", String(thumbnail.get("style", "")))
	button.set_meta(
		"battle_switch_thumbnail_placeholder",
		bool(thumbnail.get("is_placeholder", true))
	)
	button.set_meta(
		"battle_switch_thumbnail_placeholder_reason",
		String(thumbnail.get("placeholder_reason", ""))
	)
	button.set_meta(
		"battle_switch_thumbnail_atlas_path",
		String(thumbnail.get("atlas_path", ""))
	)
	var texture := thumbnail.get("texture") as Texture2D
	if texture == null:
		return
	button.icon = texture
	button.expand_icon = false
	button.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_constant_override("h_separation", 4)


func _style_option_button(button: Button, option_kind: String) -> void:
	var accent: Color = MOVE_TYPE_COLORS.get(option_kind, Color(0.28, 0.62, 0.39, 1.0))
	var base := FOREST_DARK.lerp(accent, 0.24)
	var border := GOLD.lerp(accent, 0.2)
	button.add_theme_stylebox_override("normal", _style_box(base, border, 2, 7, 2))
	button.add_theme_stylebox_override(
		"hover",
		_style_box(base.lightened(0.12), GOLD_BRIGHT.lerp(accent, 0.16), 2, 7, 4, Color(accent, 0.34))
	)
	button.add_theme_stylebox_override("pressed", _style_box(base.darkened(0.2), GOLD, 2, 7, 1))
	button.add_theme_stylebox_override(
		"focus",
		_style_box(base.lightened(0.08), GOLD_BRIGHT, 3, 8, 5, Color(GOLD_BRIGHT, 0.38))
	)
	button.add_theme_stylebox_override(
		"disabled",
		_style_box(Color(0.075, 0.095, 0.09, 0.97), Color(0.3, 0.32, 0.29, 1.0), 1, 7, 0)
	)
	button.add_theme_color_override("font_color", Color(1.0, 0.985, 0.94, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.94, 0.74, 1.0))
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.57, 0.61, 0.58, 1.0))


func _style_static_button(button: Button, accent: Color) -> void:
	button.custom_minimum_size = Vector2(104.0, TRAY_BUTTON_HEIGHT)
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 12)
	var base := CHARCOAL.lerp(accent, 0.3)
	button.add_theme_stylebox_override("normal", _style_box(base, GOLD.lerp(accent, 0.18), 2, 7, 2))
	button.add_theme_stylebox_override(
		"hover",
		_style_box(base.lightened(0.13), GOLD_BRIGHT, 2, 7, 4, Color(GOLD, 0.3))
	)
	button.add_theme_stylebox_override("pressed", _style_box(base.darkened(0.22), GOLD, 2, 7, 1))
	button.add_theme_stylebox_override(
		"focus",
		_style_box(base.lightened(0.1), GOLD_BRIGHT, 3, 8, 5, Color(GOLD_BRIGHT, 0.36))
	)
	button.add_theme_stylebox_override(
		"disabled",
		_style_box(Color(0.07, 0.085, 0.08, 0.96), Color(0.28, 0.3, 0.28, 1.0), 1, 7)
	)
	button.add_theme_color_override("font_color", Color(1.0, 0.98, 0.91, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.93, 0.7, 1.0))
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", Color(0.56, 0.6, 0.57, 1.0))


func _style_box(
	background: Color,
	border: Color,
	border_width: int,
	radius: int,
	shadow_size := 0,
	shadow_color := Color(0.0, 0.0, 0.0, 0.36)
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_color = shadow_color
	style.shadow_size = shadow_size
	style.shadow_offset = Vector2(0.0, 2.0)
	style.set_content_margin(SIDE_LEFT, 5.0)
	style.set_content_margin(SIDE_RIGHT, 5.0)
	style.set_content_margin(SIDE_TOP, 1.0)
	style.set_content_margin(SIDE_BOTTOM, 1.0)
	return style


func _hide_static_buttons() -> void:
	for button in _static_buttons():
		button.visible = false
	if is_instance_valid(footer):
		footer.visible = false


func _set_static_buttons_expand(expand: bool) -> void:
	var flags := Control.SIZE_EXPAND_FILL if expand else Control.SIZE_SHRINK_CENTER
	footer.alignment = BoxContainer.ALIGNMENT_BEGIN if expand else BoxContainer.ALIGNMENT_CENTER
	for button in _static_buttons():
		button.size_flags_horizontal = flags


func _update_row_stretch() -> void:
	var visible_static_count := 0
	for button in _static_buttons():
		if button.visible:
			visible_static_count += 1
	footer.visible = visible_static_count > 0
	footer.size_flags_stretch_ratio = float(maxi(visible_static_count, 1))
	options.size_flags_stretch_ratio = float(maxi(_dynamic_option_count(), 1))


func _static_buttons() -> Array[Button]:
	return [
		cancel_button,
		confirm_button,
		retry_button,
		return_button,
		continue_button,
	]


func _dynamic_option_count() -> int:
	var count := 0
	for child in options.get_children():
		if bool(child.get_meta("battle_option_dynamic", false)):
			count += 1
	return count


func _clear_options() -> void:
	if not is_instance_valid(options):
		return
	for child in options.get_children():
		if bool(child.get_meta("battle_option_dynamic", false)):
			var button := child as Button
			if button != null:
				# Drop small preview textures as soon as their switch tray closes.
				button.icon = null
			options.remove_child(child)
			child.queue_free()


func _grab_first_option_focus() -> void:
	for child in options.get_children():
		var button := child as Button
		if button and button.visible and not button.disabled:
			button.grab_focus()
			return
	if cancel_button.visible and not cancel_button.disabled:
		cancel_button.grab_focus()


func _player_member_map(snapshot: Dictionary) -> Dictionary:
	var result := {}
	var parties_value: Variant = snapshot.get("parties")
	if typeof(parties_value) != TYPE_DICTIONARY:
		return result
	for value: Variant in (parties_value as Dictionary).get("player", []):
		if typeof(value) == TYPE_DICTIONARY:
			var member := value as Dictionary
			result[String(member.get("memberId", ""))] = member
	return result


func _format_member_name(value: String) -> String:
	var formatted := value.replace("-", " ").strip_edges()
	if formatted.is_empty():
		return "Pokémon"
	if formatted == formatted.to_lower():
		formatted = formatted.capitalize()
	return formatted


func _on_move_chosen(move_index: int) -> void:
	force_hide()
	move_chosen.emit(move_index)


func _on_switch_chosen(member_id: String) -> void:
	force_hide()
	switch_chosen.emit(member_id)


func _on_forfeit_confirmed() -> void:
	force_hide()
	forfeit_confirmed.emit()
