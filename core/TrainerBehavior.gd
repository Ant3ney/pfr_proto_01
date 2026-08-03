class_name TrainerBehavior
extends NPCBehavior

## Detects the player directly ahead and asks the NPCController to approach them.

@export_group("Detection")
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m")
var detection_distance := 8.0
@export_range(0.0, 3.0, 0.05, "or_greater", "suffix:m")
var ray_height := 0.8
@export_flags_3d_physics var detection_collision_mask := 1

@export_group("Approach")
@export_range(0.1, 5.0, 0.05, "or_greater", "suffix:m")
var distance_from_player := 1.0


func process_behavior(
	character: CharacterBody3D,
	controller: NPCController
) -> void:
	var forward_direction := _get_forward_direction(character)
	if forward_direction.is_zero_approx():
		return

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
	var player := hit.get("collider") as PlayerCharacter
	if not player:
		return

	controller.move_to(
		_get_position_next_to_player(
			character,
			player,
			forward_direction
		)
	)


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
	var direction_from_player := character.global_position - player.global_position
	direction_from_player.y = 0.0
	if direction_from_player.is_zero_approx():
		direction_from_player = -forward_direction

	return (
		player.global_position
		+ direction_from_player.normalized() * distance_from_player
	)
