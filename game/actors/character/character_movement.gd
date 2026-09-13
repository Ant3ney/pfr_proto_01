class_name CharacterMovement
extends Resource

## Reusable locomotion settings and behavior for a PFRCharacter.

@export_group("Movement")
@export_range(1.0, 10.0) var move_speed := 4.0
@export_range(0.001, 0.5, 0.001, "or_greater") var arrival_distance := 0.025

@export_group("Turning")
## Radius of normal moving turns, measured in meters. Lower values turn tighter.
@export_range(0.1, 5.0, 0.05, "or_greater") var turn_radius := 0.15
## Maximum rotation speed while traveling toward the input direction.
@export_range(1.0, 720.0, 1.0, "degrees") var travel_to_target_angle_speed := 460.0
## Rotation speed used while the character is stopped and turning in place.
@export_range(45.0, 1080.0, 1.0, "degrees") var turn_in_place_speed := 970.0
## Direction changes at or above this angle trigger a turn in place.
@export_range(91.0, 179.0, 1.0, "degrees") var turn_in_place_angle := 91.0

@export_group("Grounding")
## Seconds between downward ground probes after the required startup probe.
@export_range(0.05, 5.0, 0.05, "or_greater") var ground_check_interval := 0.25
## The probe starts above the character's foot-level root so it can also
## recover a character placed slightly inside a walkable surface.
@export_range(0.01, 2.0, 0.01, "or_greater") var ground_ray_start_height := 0.5
## Maximum distance below the foot-level root that can be recovered in one
## grounding check.
@export_range(0.1, 100.0, 0.1, "or_greater") var ground_ray_depth := 12.0
@export_range(0.0, 0.25, 0.001, "or_greater") var ground_snap_tolerance := 0.02
@export_flags_3d_physics var ground_collision_mask := 1

var is_turning_in_place := false
var _ground_check_time_remaining := 0.0


func _init() -> void:
	resource_local_to_scene = true


## Starts each PFRCharacter on the walkable surface immediately, then arms the
## lower-frequency checks used while it remains in the scene.
func prepare_for_character(character: CharacterBody3D) -> void:
	_ground_check_time_remaining = ground_check_interval
	snap_to_ground(character)


func process_movement(
	character: CharacterBody3D,
	visual: Node3D,
	move_target: Vector3,
	delta: float
) -> void:
	var target_offset := move_target - character.global_position
	target_offset.y = 0.0
	var target_distance := target_offset.length()

	character.velocity = Vector3.ZERO

	if target_distance > arrival_distance:
		var move_direction := target_offset / target_distance
		var movement_strength := minf(target_distance, 1.0)
		_steer_toward(
			character,
			visual,
			move_direction,
			movement_strength,
			delta
		)
	else:
		is_turning_in_place = false

	character.move_and_slide()
	_process_grounding(character, delta)


## Places the character's foot-level root on the first configured collision
## surface directly beneath it. Returns false when the probe finds no ground.
func snap_to_ground(character: CharacterBody3D) -> bool:
	if (
		not character.is_inside_tree()
		or character.get_world_3d() == null
		or ground_collision_mask == 0
	):
		return false

	var character_position := character.global_position
	var ray_origin := character_position + Vector3.UP * ground_ray_start_height
	var ray_end := character_position - Vector3.UP * ground_ray_depth
	var excluded_bodies: Array[RID] = [character.get_rid()]
	var ray_query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		ground_collision_mask,
		excluded_bodies
	)
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false

	var hit := character.get_world_3d().direct_space_state.intersect_ray(ray_query)
	if hit.is_empty():
		return false

	var ground_position: Vector3 = hit["position"]
	if absf(character_position.y - ground_position.y) <= ground_snap_tolerance:
		return true

	character_position.y = ground_position.y
	character.global_position = character_position
	character.velocity.y = 0.0
	return true


func _process_grounding(character: CharacterBody3D, delta: float) -> void:
	_ground_check_time_remaining -= delta
	if _ground_check_time_remaining > 0.0:
		return

	snap_to_ground(character)
	_ground_check_time_remaining = ground_check_interval


func _steer_toward(
	character: CharacterBody3D,
	visual: Node3D,
	target_direction: Vector3,
	input_strength: float,
	delta: float
) -> void:
	var local_target_direction := target_direction
	var visual_parent := visual.get_parent_node_3d()
	if visual_parent:
		local_target_direction = (
			visual_parent.global_basis.orthonormalized().inverse()
			* target_direction
		)
	local_target_direction.y = 0.0
	local_target_direction = local_target_direction.normalized()

	var target_angle := atan2(
		-local_target_direction.x,
		-local_target_direction.z
	)
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
