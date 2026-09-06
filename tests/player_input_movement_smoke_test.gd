extends Node3D

@onready var player: PlayerCharacter = $Player

var _failures: Array[String] = []


func _ready() -> void:
	GameInstance.set_player_movement_enabled(true)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	await get_tree().physics_frame

	_check(
		player.controller is PlayerController,
		"The inherited player scene should own a PlayerController."
	)
	_check(
		player.is_physics_processing(),
		"The inherited player should run shared character physics at runtime."
	)
	if not player.controller is PlayerController:
		_finish()
		return

	var keyboard_start := player.global_position
	_set_key_pressed(KEY_W, true)
	for _frame in 8:
		await get_tree().physics_frame
	_set_key_pressed(KEY_W, false)
	await get_tree().physics_frame
	_check(
		player.global_position.distance_to(keyboard_start) > 0.05,
		"A held W key should move the inherited player."
	)

	player.global_position = Vector3.ZERO
	player.velocity = Vector3.ZERO
	player.visual.rotation = Vector3.ZERO
	var joystick_start := player.global_position
	PlayerController.set_floating_joystick_input(Vector2.RIGHT)
	for _frame in 8:
		await get_tree().physics_frame
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	await get_tree().physics_frame
	_check(
		player.global_position.distance_to(joystick_start) > 0.05,
		"Floating-joystick input should move the inherited player."
	)

	_finish()


func _set_key_pressed(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _finish() -> void:
	_set_key_pressed(KEY_W, false)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	if _failures.is_empty():
		print(
			"Player input movement smoke test passed: the inherited player responds "
			+ "to keyboard and floating-joystick input."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Player input movement smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
