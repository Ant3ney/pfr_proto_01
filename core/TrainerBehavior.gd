class_name TrainerBehavior
extends NPCBehavior

## Detects the player directly ahead, approaches them once, and stops nearby.

enum ApproachState {
	WAITING,
	APPROACHING,
	COMPLETE,
}

@export_group("Detection")
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m")
var detection_distance := 80.0
@export_range(0.0, 3.0, 0.05, "or_greater", "suffix:m")
var ray_height := 0.8
@export_flags_3d_physics var detection_collision_mask := 1

@export_group("Approach")
## Additional space left between the trainer's and player's collision bounds.
@export_range(0.0, 3.0, 0.05, "or_greater", "suffix:m")
var stopping_buffer := 0.15
## Distance from the locked target at which the approach is complete.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:m")
var arrival_distance := 0.15

var _approach_state := ApproachState.WAITING
var _approach_target := Vector3.ZERO


func process_behavior(
	character: CharacterBody3D,
	controller: NPCController
) -> void:
	if _approach_state == ApproachState.COMPLETE:
		return

	if _approach_state == ApproachState.APPROACHING:
		if _has_reached_approach_target(character):
			_complete_approach(character, controller)
		return

	var forward_direction := _get_forward_direction(character)
	if forward_direction.is_zero_approx():
		return

	var player := _detect_player(character, forward_direction)
	if not player:
		return

	GameInstance.set_player_movement_enabled(false)
	_approach_target = _get_position_next_to_player(
		character,
		player,
		forward_direction
	)
	if _has_reached_approach_target(character):
		_complete_approach(character, controller)
		return

	_approach_state = ApproachState.APPROACHING
	controller.move_to(_approach_target)


func _detect_player(
	character: CharacterBody3D,
	forward_direction: Vector3
) -> PlayerCharacter:
	var ray_origin := character.global_position + Vector3.UP * ray_height
	var ray_end := ray_origin + forward_direction * detection_distance
	var excluded_bodies: Array[RID] = [character.get_rid()]
	var ray_query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_end,
		detection_collision_mask,
		excluded_bodies
	)
	var hit := character.get_world_3d().direct_space_state.intersect_ray(ray_query)
	return hit.get("collider") as PlayerCharacter


func _get_forward_direction(character: CharacterBody3D) -> Vector3:
	var visual := character.get_node_or_null(^"Visual") as Node3D
	var facing_basis := visual.global_basis if visual else character.global_basis
	var forward_direction := -facing_basis.z
	forward_direction.y = 0.0
	return forward_direction.normalized()


func _get_position_next_to_player(
	character: CharacterBody3D,
	player: PlayerCharacter,
	forward_direction: Vector3
) -> Vector3:
	var offset_to_player := player.global_position - character.global_position
	offset_to_player.y = 0.0
	var distance_to_player := offset_to_player.length()
	var direction_to_player := (
		offset_to_player / distance_to_player
		if distance_to_player > 0.0
		else forward_direction
	)
	var stopping_distance := (
		_get_horizontal_collision_radius(character)
		+ _get_horizontal_collision_radius(player)
		+ stopping_buffer
	)
	var travel_distance := maxf(distance_to_player - stopping_distance, 0.0)
	return character.global_position + direction_to_player * travel_distance


func _get_horizontal_collision_radius(body: CollisionObject3D) -> float:
	var greatest_radius := 0.0
	var collision_nodes := body.find_children(
		"*",
		"CollisionShape3D",
		true,
		false
	)
	for collision_node in collision_nodes:
		var collision_shape := collision_node as CollisionShape3D
		if not collision_shape or collision_shape.disabled or not collision_shape.shape:
			continue

		var local_radius := _get_shape_horizontal_radius(collision_shape.shape)
		var shape_scale := collision_shape.global_basis.get_scale()
		var horizontal_scale := maxf(absf(shape_scale.x), absf(shape_scale.z))
		var offset_from_body := collision_shape.global_position - body.global_position
		offset_from_body.y = 0.0
		greatest_radius = maxf(
			greatest_radius,
			offset_from_body.length() + local_radius * horizontal_scale
		)
	return greatest_radius


func _get_shape_horizontal_radius(shape: Shape3D) -> float:
	if shape is CapsuleShape3D:
		return (shape as CapsuleShape3D).radius
	if shape is CylinderShape3D:
		return (shape as CylinderShape3D).radius
	if shape is SphereShape3D:
		return (shape as SphereShape3D).radius
	if shape is BoxShape3D:
		var box_size := (shape as BoxShape3D).size
		return Vector2(box_size.x, box_size.z).length() * 0.5
	if shape is ConvexPolygonShape3D:
		var greatest_radius := 0.0
		for point in (shape as ConvexPolygonShape3D).points:
			greatest_radius = maxf(
				greatest_radius,
				Vector2(point.x, point.z).length()
			)
		return greatest_radius
	return 0.0


func _has_reached_approach_target(character: CharacterBody3D) -> bool:
	var offset_to_target := _approach_target - character.global_position
	offset_to_target.y = 0.0
	return offset_to_target.length() <= arrival_distance


func _complete_approach(
	character: CharacterBody3D,
	controller: NPCController
) -> void:
	_approach_state = ApproachState.COMPLETE
	controller.stop_moving(character)
