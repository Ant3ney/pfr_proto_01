class_name ProgressResetConfirmation
extends Control

## Shared, input-agnostic destructive-reset gate. Each warning requires its
## own explicit Yes press; only the third press emits confirmed.

signal confirmed
signal cancelled

const WARNING_TITLES: Array[String] = [
	"RESET ALL PROGRESS?",
	"ARE YOU SURE?",
	"ARE YOU ABSOLUTELY SURE?",
]
const WARNING_MESSAGES: Array[String] = [
	(
		"All saved progression will be erased: every Pokémon, level, move choice, "
		+ "item, dollar, badge, route result, and saved position."
	),
	(
		"The deletion is irreversible unless you exported a JSON backup before "
		+ "resetting. Separately exported backup files are not deleted."
	),
	(
		"This is the final confirmation. Press YES — ERASE EVERYTHING to permanently "
		+ "remove this progress. If cloud saving is linked, the new profile will "
		+ "replace the linked cloud save after you choose a starter."
	),
]

var _warning_step := 0
var _confirmed_once := false
var _step_label: Label
var _title_label: Label
var _message_label: Label
var _yes_button: Button
var _cancel_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 80
	_build_interface()
	visible = false
	set_process_unhandled_input(true)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not event.is_pressed():
		return
	var cancel_requested := false
	if event is InputEventKey:
		cancel_requested = (event as InputEventKey).keycode == KEY_ESCAPE
	elif event is InputEventJoypadButton:
		cancel_requested = (event as InputEventJoypadButton).button_index == JOY_BUTTON_B
	if cancel_requested:
		get_viewport().set_input_as_handled()
		cancel()


func open() -> void:
	_warning_step = 1
	_confirmed_once = false
	visible = true
	_show_current_warning()


func press_yes() -> bool:
	if not visible or _warning_step < 1 or _warning_step > WARNING_MESSAGES.size():
		return false
	if _warning_step < WARNING_MESSAGES.size():
		_warning_step += 1
		_show_current_warning()
		return true
	if _confirmed_once:
		return false
	_confirmed_once = true
	_yes_button.disabled = true
	_cancel_button.disabled = true
	_title_label.text = "RESETTING PROGRESS…"
	_message_label.text = "The confirmed reset is being applied."
	confirmed.emit()
	return true


func cancel() -> void:
	if not visible or _confirmed_once:
		return
	_warning_step = 0
	visible = false
	cancelled.emit()


func get_warning_step() -> int:
	return _warning_step


func get_yes_button() -> Button:
	return _yes_button


func get_cancel_button() -> Button:
	return _cancel_button


func _show_current_warning() -> void:
	var index := _warning_step - 1
	_step_label.text = "DESTRUCTIVE ACTION  ·  WARNING %d OF %d" % [
		_warning_step,
		WARNING_MESSAGES.size(),
	]
	_title_label.text = WARNING_TITLES[index]
	_message_label.text = WARNING_MESSAGES[index]
	_yes_button.text = "YES — CONTINUE" if _warning_step < 3 else "YES — ERASE EVERYTHING"
	_yes_button.disabled = false
	_cancel_button.disabled = false
	_yes_button.grab_focus()


func _build_interface() -> void:
	var dim := ColorRect.new()
	dim.name = "ResetWarningPrompt"
	dim.color = Color(0.035, 0.0, 0.008, 0.97)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var safe_margin := MarginContainer.new()
	safe_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		safe_margin.add_theme_constant_override(side, 18)
	dim.add_child(safe_margin)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	safe_margin.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ResetDangerPanel"
	panel.custom_minimum_size = Vector2(620.0, 330.0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override(
		"panel",
		_danger_style(Color("21070a"), Color("ff263d"), 5, 14)
	)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 16)
	margin.add_child(column)

	_step_label = Label.new()
	_step_label.name = "ResetWarningStep"
	_step_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_step_label.add_theme_color_override("font_color", Color("ff8995"))
	_step_label.add_theme_font_size_override("font_size", 14)
	column.add_child(_step_label)

	_title_label = Label.new()
	_title_label.name = "ResetWarningTitle"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.add_theme_color_override("font_color", Color("ff4054"))
	_title_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 2)
	_title_label.add_theme_font_size_override("font_size", 27)
	column.add_child(_title_label)

	_message_label = Label.new()
	_message_label.name = "ResetWarningMessage"
	_message_label.custom_minimum_size = Vector2(0.0, 112.0)
	_message_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message_label.add_theme_color_override("font_color", Color("ffe7e9"))
	_message_label.add_theme_font_size_override("font_size", 17)
	column.add_child(_message_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 14)
	column.add_child(buttons)

	_cancel_button = Button.new()
	_cancel_button.name = "CancelReset"
	_cancel_button.text = "CANCEL — KEEP MY SAVE"
	_cancel_button.custom_minimum_size = Vector2(235.0, 52.0)
	_cancel_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cancel_button.pressed.connect(cancel)
	buttons.add_child(_cancel_button)

	_yes_button = Button.new()
	_yes_button.name = "ConfirmProgressReset"
	_yes_button.custom_minimum_size = Vector2(255.0, 52.0)
	_yes_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_yes_button.add_theme_color_override("font_color", Color.WHITE)
	_yes_button.add_theme_color_override("font_hover_color", Color.WHITE)
	_yes_button.add_theme_stylebox_override(
		"normal",
		_danger_style(Color("7e0d19"), Color("ff263d"), 3, 9)
	)
	_yes_button.add_theme_stylebox_override(
		"hover",
		_danger_style(Color("b31020"), Color("ff8290"), 3, 9)
	)
	_yes_button.add_theme_stylebox_override(
		"focus",
		_danger_style(Color("b31020"), Color("ffffff"), 3, 9)
	)
	_yes_button.pressed.connect(press_yes)
	buttons.add_child(_yes_button)


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
