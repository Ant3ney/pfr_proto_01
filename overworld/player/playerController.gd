extends CharacterBody3D

@export_group("Movement")
@export_range(1.0, 10.0) var move_speed := 4.0

@export_group("Turning")
## Radius of normal moving turns, measured in meters. Lower values turn tighter.
@export_range(0.1, 5.0, 0.05, "or_greater") var turn_radius := 0.75 
## Rotation speed used while the character is stopped and turning in place.
@export_range(45.0, 720.0, 1.0, "degrees") var turn_in_place_speed := 970.0
## Direction changes at or above this angle trigger a turn in place.
@export_range(91.0, 179.0, 1.0, "degrees") var turn_in_place_angle := 91.0

@onready var visual: Node3D = $Visual

var is_turning_in_place := false


func _physics_process(delta: float) -> void:
	var input_vector := _get_input_vector()
	var move_direction := _screen_input_to_world(input_vector)
	var input_strength := input_vector.length()

	velocity.x = 0.0
	velocity.z = 0.0
	velocity.y = 0.0

	if not move_direction.is_zero_approx():
		_steer_toward(move_direction, input_strength, delta)
	else:
		is_turning_in_place = false

	move_and_slide()


func _steer_toward(target_direction: Vector3, input_strength: float, delta: float) -> void:
	var target_angle := atan2(-target_direction.x, -target_direction.z)
	var angle_to_target := absf(
		wrapf(target_angle - visual.rotation.y, -PI, PI)
	)
	var turn_in_place_threshold := deg_to_rad(turn_in_place_angle)

	if angle_to_target >= turn_in_place_threshold:
		is_turning_in_place = true

	if is_turning_in_place:
		var pivot_step := deg_to_rad(turn_in_place_speed) * delta
		visual.rotation.y = rotate_toward(visual.rotation.y, target_angle, pivot_step)

		angle_to_target = absf(
			wrapf(target_angle - visual.rotation.y, -PI, PI)
		)
		if angle_to_target >= turn_in_place_threshold:
			return

		is_turning_in_place = false

	# Moving along the current facing direction while rotating produces an arc.
	# angular_speed = linear_speed / radius, so turn_radius is measured in meters.
	var current_speed := move_speed * input_strength
	var turn_speed := current_speed / maxf(turn_radius, 0.001)
	visual.rotation.y = rotate_toward(
		visual.rotation.y,
		target_angle,
		turn_speed * delta
	)

	var facing_direction := -visual.global_basis.z
	facing_direction.y = 0.0
	facing_direction = facing_direction.normalized()
	velocity.x = facing_direction.x * current_speed
	velocity.z = facing_direction.z * current_speed


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
