extends CharacterBody3D

@export_range(1.0, 10.0) var move_speed := 4.0

@onready var visual: Node3D = $Visual


func _physics_process(_delta: float) -> void:
	var input_vector := _get_input_vector()
	var move_direction := _screen_input_to_world(input_vector)
	velocity.x = move_direction.x * move_speed
	velocity.z = move_direction.z * move_speed
	velocity.y = 0.0
	move_and_slide()

	if not move_direction.is_zero_approx():
		visual.rotation.y = atan2(-move_direction.x, -move_direction.z)


func _get_input_vector() -> Vector2:
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


func _screen_input_to_world(input_vector: Vector2) -> Vector3:
	if input_vector.is_zero_approx():
		return Vector3.ZERO

	var camera := get_viewport().get_camera_3d()
	if not camera:
		return Vector3(input_vector.x, 0.0, input_vector.y).normalized()

	var camera_right := camera.global_basis.x
	var camera_forward := -camera.global_basis.z
	camera_right.y = 0.0
	camera_forward.y = 0.0
	camera_right = camera_right.normalized()
	camera_forward = camera_forward.normalized()

	return (camera_right * input_vector.x - camera_forward * input_vector.y).normalized()
