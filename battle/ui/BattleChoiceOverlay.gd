class_name BattleChoiceOverlay
extends Control

## Modal presentation surface for server-provided moves, switches, errors, and
## results. It emits typed intents and contains no battle rules.

signal move_chosen(move_index: int)
signal switch_chosen(member_id: String)
signal forfeit_confirmed
signal retry_requested
signal return_requested
signal continue_requested

@onready var title_label: Label = %Title
@onready var message_label: Label = %Message
@onready var options: VBoxContainer = %Options
@onready var cancel_button: Button = %CancelButton
@onready var confirm_button: Button = %ConfirmButton
@onready var retry_button: Button = %RetryButton
@onready var return_button: Button = %ReturnButton
@onready var continue_button: Button = %ContinueButton

var _forced_switch := false


func _ready() -> void:
	cancel_button.pressed.connect(hide_overlay)
	confirm_button.pressed.connect(_on_forfeit_confirmed)
	retry_button.pressed.connect(func() -> void: retry_requested.emit())
	return_button.pressed.connect(func() -> void: return_requested.emit())
	continue_button.pressed.connect(func() -> void: continue_requested.emit())
	hide_overlay()


func hide_overlay() -> void:
	if _forced_switch:
		return
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_options()


func force_hide() -> void:
	_forced_switch = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_options()


func show_moves(request: Dictionary) -> void:
	_forced_switch = false
	_prepare("CHOOSE A MOVE", "Select one of the moves returned by the battle server.")
	cancel_button.visible = true
	for value: Variant in request.get("moves", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var move := value as Dictionary
		var button := _new_option_button(
			"%s    PP %d/%d" % [
				String(move.get("name", "Move")),
				int(move.get("pp", 0)),
				int(move.get("maxPp", 0)),
			]
		)
		button.disabled = bool(move.get("disabled", true))
		button.pressed.connect(
			_on_move_chosen.bind(int(move.get("moveIndex", 0)))
		)
	_grab_first_option_focus()


func show_switches(
	request: Dictionary,
	snapshot: Dictionary,
	forced: bool
) -> void:
	_prepare(
		"CHOOSE A POKÉMON",
		"Choose a replacement." if forced else "Choose an available party member."
	)
	_forced_switch = forced
	cancel_button.visible = not forced
	var member_by_id := _player_member_map(snapshot)
	for value: Variant in request.get("switchOptions", []):
		if typeof(value) != TYPE_DICTIONARY:
			continue
		var member_id := String((value as Dictionary).get("memberId", ""))
		var member: Dictionary = member_by_id.get(member_id, {})
		var display_name := String(
			member.get("nickname", member.get("species", "Pokémon"))
		).replace("-", " ").capitalize()
		var button := _new_option_button(
			"%s    HP %d/%d" % [
				display_name,
				int(member.get("hp", 0)),
				int(member.get("maxHp", 0)),
			]
		)
		button.pressed.connect(_on_switch_chosen.bind(member_id))
	_grab_first_option_focus()


func show_forfeit_confirmation() -> void:
	_forced_switch = false
	_prepare("FORFEIT BATTLE?", "This will end the battle and return to the overworld.")
	cancel_button.visible = true
	confirm_button.visible = true
	confirm_button.grab_focus()


func show_error(error: Dictionary) -> void:
	_prepare("BATTLE CONNECTION ERROR", String(error.get("message", "The battle could not continue.")))
	_forced_switch = true
	cancel_button.visible = false
	retry_button.visible = bool(error.get("retriable", false))
	return_button.visible = bool(error.get("can_return", true))
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
	_prepare(title, message)
	_forced_switch = true
	cancel_button.visible = false
	continue_button.visible = true
	continue_button.grab_focus()


func _prepare(title: String, message: String) -> void:
	_clear_options()
	title_label.text = title
	message_label.text = message
	cancel_button.visible = false
	confirm_button.visible = false
	retry_button.visible = false
	return_button.visible = false
	continue_button.visible = false
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func _new_option_button(text: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0.0, 48.0)
	button.text = text
	button.theme_type_variation = &"BattleChoiceButton"
	options.add_child(button)
	return button


func _clear_options() -> void:
	if not is_instance_valid(options):
		return
	for child in options.get_children():
		child.queue_free()


func _grab_first_option_focus() -> void:
	for child in options.get_children():
		var button := child as Button
		if button and not button.disabled:
			button.grab_focus()
			return


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


func _on_move_chosen(move_index: int) -> void:
	force_hide()
	move_chosen.emit(move_index)


func _on_switch_chosen(member_id: String) -> void:
	force_hide()
	switch_chosen.emit(member_id)


func _on_forfeit_confirmed() -> void:
	force_hide()
	forfeit_confirmed.emit()
