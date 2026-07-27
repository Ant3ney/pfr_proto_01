class_name CharacterMovement
extends Resource

## Reusable locomotion settings and behavior for a PFRCharacter.

@export_group("Movement")
@export_range(1.0, 10.0) var move_speed := 4.0

@export_group("Turning")
## Radius of normal moving turns, measured in meters. Lower values turn tighter.
@export_range(0.1, 5.0, 0.05, "or_greater") var turn_radius := 0.75
## Maximum rotation speed while traveling toward the input direction.
@export_range(1.0, 720.0, 1.0, "degrees") var travel_to_target_angle_speed := 460.0
## Rotation speed used while the character is stopped and turning in place.
@export_range(45.0, 1080.0, 1.0, "degrees") var turn_in_place_speed := 970.0
## Direction changes at or above this angle trigger a turn in place.
@export_range(91.0, 179.0, 1.0, "degrees") var turn_in_place_angle := 91.0

var is_turning_in_place := false


func _init() -> void:
	resource_local_to_scene = true


func process_movement(
	character: CharacterBody3D,
	visual: Node3D,
	input_vector: Vector2,
	delta: float
) -> void:
	var move_direction := _screen_input_to_world(character, input_vector)
	var input_strength := input_vector.length()

	character.velocity = Vector3.ZERO

	if not move_direction.is_zero_approx():
		_steer_toward(character, visual, move_direction, input_strength, delta)
	else:
		is_turning_in_place = false

	character.move_and_slide()


func _steer_toward(
	character: CharacterBody3D,
	visual: Node3D,
	target_direction: Vector3,
	input_strength: float,
	delta: float
) -> void:
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
	var radius_turn_speed := current_speed / maxf(turn_radius, 0.001)
	var travel_turn_speed := deg_to_rad(travel_to_target_angle_speed)
	var turn_speed := minf(radius_turn_speed, travel_turn_speed)
	visual.rotation.y = rotate_toward(
		visual.rotation.y,
		target_angle,
		turn_speed * delta
	)

	var facing_direction := -visual.global_basis.z
	facing_direction.y = 0.0
	facing_direction = facing_direction.normalized()
	character.velocity.x = facing_direction.x * current_speed
	character.velocity.z = facing_direction.z * current_speed


func _screen_input_to_world(
	character: CharacterBody3D,
	input_vector: Vector2
) -> Vector3:
	if input_vector.is_zero_approx():
		return Vector3.ZERO

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
