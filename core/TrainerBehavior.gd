class_name TrainerBehavior
extends NPCBehavior

## Detects the player directly ahead, approaches them once, and stops nearby.

enum ApproachState {
	WAITING,
	APPROACHING,
	COMPLETE,
}

enum AggressionMode {
	STANDARD,
	HIGHLY_AGGRO,
}

@export_group("Detection")
@export_range(0.1, 100.0, 0.1, "or_greater", "suffix:m")
var detection_distance := 80.0
@export_range(0.0, 3.0, 0.05, "or_greater", "suffix:m")
var ray_height := 0.8
@export_flags_3d_physics var detection_collision_mask := 1
## Keep classic line-of-sight trainer challenges available for authored NPCs.
## Set false when the trainer should wait for the HUD interaction button.
@export var automatic_sight_encounter := true
## Standard trainers force one sight encounter per play session, then remain
## available for manual rematches. Highly Aggro is reserved for generated
## Stretchman opponents and resets whenever their destination is entered anew.
@export var aggression_mode: AggressionMode = AggressionMode.STANDARD

@export_group("Approach")
## Additional space left between the trainer's and player's collision bounds.
@export_range(0.0, 3.0, 0.05, "or_greater", "suffix:m")
var stopping_buffer := 0.15
## Distance from the locked target at which the approach is complete.
@export_range(0.01, 1.0, 0.01, "or_greater", "suffix:m")
var arrival_distance := 0.15

var dialog: Dialog
var battle_scene_path := ""
var encounter_id := ""

var _approach_state := ApproachState.WAITING
var _approach_target := Vector3.ZERO
var _dialog_template: UITemplate
var _dialog_line_index := -1
var _start_battle_after_dialog := false
var _suppression_checked := false


func process_behavior(
	character: CharacterBody3D,
	controller: NPCController
) -> void:
	_apply_encounter_suppression(character, controller)
	if _approach_state == ApproachState.COMPLETE:
		return

	if _approach_state == ApproachState.APPROACHING:
		if _has_reached_approach_target(character):
			_complete_approach(character, controller)
		return
	if not _can_start_automatic_sight_encounter():
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


func can_interact(
	character: CharacterBody3D,
	controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	_apply_encounter_suppression(character, controller)
	return (
		interactor != null
		and _approach_state == ApproachState.WAITING
		and not is_instance_valid(_dialog_template)
		and GameInstance.is_player_movement_enabled()
		and not GameInstance.is_battle_start_in_progress()
		and not GameInstance.is_battle_return_in_progress()
		and not GameInstance.is_scene_transfer_in_progress()
	)


func interact(
	character: CharacterBody3D,
	controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	if not can_interact(character, controller, interactor):
		return false

	_approach_state = ApproachState.COMPLETE
	controller.stop_moving(character)
	_face_interactor(character, interactor)
	GameInstance.set_player_movement_enabled(false)
	if dialog != null and not dialog.is_empty():
		_start_dialog()
		return true

	if _start_configured_battle():
		return true
	_approach_state = ApproachState.WAITING
	return false


func get_interaction_prompt(
	character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> String:
	var trainer_name := dialog.character_name.strip_edges() if dialog != null else ""
	if trainer_name.is_empty():
		trainer_name = String(character.name)
	return (
		"Talk to %s" % trainer_name
		if dialog != null and not dialog.is_empty()
		else "Battle %s" % trainer_name
	)


func is_highly_aggro() -> bool:
	return aggression_mode == AggressionMode.HIGHLY_AGGRO


func _can_start_automatic_sight_encounter() -> bool:
	return (
		automatic_sight_encounter
		and (
			is_highly_aggro()
			or not GameInstance.has_consumed_standard_trainer_sight_encounter(
				encounter_id
			)
		)
	)


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
	_start_dialog()


func _start_dialog() -> void:
	_start_battle_after_dialog = false
	if not dialog or dialog.is_empty():
		_finish_dialog()
		return

	GameInstance.set_player_movement_enabled(false)
	_dialog_line_index = 0
	_dialog_template = UIManager.show_ui(dialog.dialog_lines[_dialog_line_index])
	if not _dialog_template:
		_finish_dialog()
		return

	_dialog_template.set_speaker_name(dialog.character_name)
	_dialog_template.set_action_text("Next")
	_dialog_template.set_action_callback(_advance_dialog)
	_dialog_template.set_dismiss_callback(_finish_dialog)


func _advance_dialog() -> void:
	if not is_instance_valid(_dialog_template):
		_finish_dialog()
		return

	_dialog_line_index += 1
	if _dialog_line_index >= dialog.dialog_lines.size():
		_start_battle_after_dialog = true
		_dialog_template.close()
		return

	_dialog_template.set_text(dialog.dialog_lines[_dialog_line_index])


func _finish_dialog() -> void:
	var should_start_battle := _start_battle_after_dialog
	_start_battle_after_dialog = false
	_dialog_template = null
	_dialog_line_index = -1
	GameInstance.set_player_movement_enabled(true)
	if should_start_battle:
		_start_configured_battle()


func _start_configured_battle() -> bool:
	# startBattle owns the next movement lock. Release the dialog/interaction
	# lock first so a failed launch restores normal player control.
	GameInstance.set_player_movement_enabled(true)
	var accepted := GameInstance.startBattle({
		"encounter_type": "trainer",
		"trainer_name": dialog.character_name if dialog else "",
		"battle_scene_path": battle_scene_path,
		"encounter_id": encounter_id,
		"trainer_aggression_mode": aggression_mode,
	})
	if not accepted:
		GameInstance.set_player_movement_enabled(true)
	return accepted


func _apply_encounter_suppression(
	character: CharacterBody3D,
	controller: NPCController
) -> void:
	if _suppression_checked:
		return
	_suppression_checked = true
	if GameInstance.is_encounter_suppressed(encounter_id):
		# A standard trainer returns ready for a manual rematch, while a Highly
		# Aggro destination trainer stays quiet for this one return scene so it
		# cannot immediately loop back into battle underneath the player.
		_approach_state = (
			ApproachState.COMPLETE
			if is_highly_aggro()
			else ApproachState.WAITING
		)
		controller.stop_moving(character)


func _face_interactor(
	character: CharacterBody3D,
	interactor: PlayerCharacter
) -> void:
	var visual := character.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	var offset := interactor.global_position - character.global_position
	offset.y = 0.0
	if offset.is_zero_approx():
		return
	var local_direction := character.global_basis.orthonormalized().inverse() * offset.normalized()
	visual.rotation.y = atan2(-local_direction.x, -local_direction.z)
