class_name PlayerController
extends NPCController

## Creates camera-relative move targets from keyboard, gamepad, and touch input.

static var _floating_joystick_input := Vector2.ZERO


static func set_floating_joystick_input(input_vector: Vector2) -> void:
	_floating_joystick_input = input_vector.limit_length(1.0)


func get_move_target(character: CharacterBody3D) -> Vector3:
	var input_vector := _get_movement_input()
	if input_vector.is_zero_approx():
		return character.global_position

	var move_direction := _screen_input_to_world(character, input_vector)
	return character.global_position + move_direction * input_vector.length()


func _get_movement_input() -> Vector2:
	var keyboard := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)

	var gamepad := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	)
	if gamepad.length() < 0.18:
		gamepad = Vector2.ZERO

	var strongest_input := keyboard
	if gamepad.length() > strongest_input.length():
		strongest_input = gamepad
	if _floating_joystick_input.length() > strongest_input.length():
		strongest_input = _floating_joystick_input
	return strongest_input.limit_length(1.0)


func _screen_input_to_world(
	character: CharacterBody3D,
	input_vector: Vector2
) -> Vector3:
	var camera := character.get_viewport().get_camera_3d()
	if not camera:
		return Vector3(input_vector.x, 0.0, input_vector.y).normalized()

	var camera_right := camera.global_basis.x
	var camera_forward := -camera.global_basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()

	return (camera_right * input_vector.x - camera_forward * input_vector.y).normalized()
