class_name PlayerMenuHUD
extends CanvasLayer

## Persistent overworld entry point for the R&D player menu.

signal menu_opened(menu: PlayerMenuUI)
signal menu_closed

const PlayerMenuScene := preload("res://game/ui/player_menu/player_menu_ui.tscn")

@onready var menu_button: Button = $MenuButton

var _menu: PlayerMenuUI
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
	_menu = PlayerMenuScene.instantiate() as PlayerMenuUI
	if _menu == null:
		push_error("The R&D player menu scene could not be instantiated.")
		return
	_movement_was_enabled = GameInstance.is_player_movement_enabled()
	GameInstance.set_player_movement_enabled(false)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	menu_button.disabled = true
	_menu.closed.connect(_on_menu_closed)
	_menu.reset_progress_confirmed.connect(_on_reset_progress_confirmed)
	add_child(_menu)
	menu_opened.emit(_menu)


func get_open_menu() -> PlayerMenuUI:
	return _menu if is_instance_valid(_menu) else null


func _on_menu_closed() -> void:
	_menu = null
	menu_button.disabled = false
	_restore_movement()
	menu_closed.emit()


func _on_reset_progress_confirmed() -> void:
	if not is_instance_valid(_menu):
		return
	# Closing first releases this menu's movement lock. The starter picker then
	# acquires its own lock after the reset returns to the main scene.
	_menu.close_menu()
	if not ProgressionAutosave.reset_all_progress():
		push_error("The confirmed progress reset could not be started.")


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
