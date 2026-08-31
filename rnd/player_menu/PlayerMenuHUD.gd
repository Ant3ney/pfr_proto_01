class_name RNDPlayerMenuHUD
extends CanvasLayer

## Persistent overworld entry point for the R&D player menu.

signal menu_opened(menu: RNDPlayerMenuUI)
signal menu_closed

const PlayerMenuScene := preload("res://rnd/player_menu/player_menu_ui.tscn")

@onready var menu_button: Button = $MenuButton

var _menu: RNDPlayerMenuUI
var _movement_was_enabled := false


func _ready() -> void:
	menu_button.pressed.connect(open_menu)
	set_process_unhandled_input(true)


func _exit_tree() -> void:
	_restore_movement()


func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_menu) or not event.is_pressed():
		return
	var open_requested := false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		open_requested = not key_event.echo and key_event.keycode == KEY_M
	elif event is InputEventJoypadButton:
		open_requested = (event as InputEventJoypadButton).button_index == JOY_BUTTON_Y
	if not open_requested:
		return
	get_viewport().set_input_as_handled()
	open_menu()


func open_menu() -> void:
	if is_instance_valid(_menu):
		return
	_menu = PlayerMenuScene.instantiate() as RNDPlayerMenuUI
	if _menu == null:
		push_error("The R&D player menu scene could not be instantiated.")
		return
	_movement_was_enabled = GameInstance.is_player_movement_enabled()
	GameInstance.set_player_movement_enabled(false)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	menu_button.disabled = true
	_menu.closed.connect(_on_menu_closed)
	add_child(_menu)
	menu_opened.emit(_menu)


func get_open_menu() -> RNDPlayerMenuUI:
	return _menu if is_instance_valid(_menu) else null


func _on_menu_closed() -> void:
	_menu = null
	menu_button.disabled = false
	_restore_movement()
	menu_closed.emit()


func _restore_movement() -> void:
	if not _movement_was_enabled:
		return
	_movement_was_enabled = false
	if (
		GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
		or GameInstance.is_scene_transfer_in_progress()
	):
		return
	GameInstance.set_player_movement_enabled(true)
