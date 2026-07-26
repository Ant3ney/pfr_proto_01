class_name PlayerController
extends PFRCharacter

## The player is a PFRCharacter that supplies keyboard and gamepad input.


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

	var strongest_input := gamepad if gamepad.length() > keyboard.length() else keyboard
	return strongest_input.limit_length(1.0)
