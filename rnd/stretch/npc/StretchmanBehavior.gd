class_name RNDStretchmanBehavior
extends NPCBehavior

## Owns Stretchman's interaction lock and the lifecycle of his large R&D hub.

const HubScene := preload("res://rnd/stretch/ui/stretch_goal_ui.tscn")

var _hub: RNDStretchGoalUI


func can_interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	return (
		interactor != null
		and not is_instance_valid(_hub)
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
	_face_interactor(character, interactor)
	GameInstance.set_player_movement_enabled(false)
	_hub = HubScene.instantiate() as RNDStretchGoalUI
	if _hub == null:
		GameInstance.set_player_movement_enabled(true)
		return false
	_hub.closed.connect(_finish_sequence)
	_hub.travel_requested.connect(_travel_to_destination)
	UIManager.add_child(_hub)
	return true


func get_interaction_prompt(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> String:
	return "Talk to Stretchman"


func _finish_sequence() -> void:
	_hub = null
	GameInstance.set_player_movement_enabled(true)


func _travel_to_destination(kind: String, destination_index: int) -> void:
	var hub := _hub
	_hub = null
	if is_instance_valid(hub):
		hub.dismiss_for_travel()
	GameInstance.set_player_movement_enabled(true)
	var destination := StretchGoalSystem.begin_destination(kind, destination_index)
	if destination.is_empty():
		return
	if not GameInstance.transfer_to_scene(
		String(destination.get("scene_path", "")),
		&"EntrySpawn"
	):
		GameInstance.set_player_movement_enabled(true)


func _face_interactor(character: CharacterBody3D, interactor: PlayerCharacter) -> void:
	var visual := character.get_node_or_null(^"Visual") as Node3D
	if visual == null:
		return
	var offset := interactor.global_position - character.global_position
	offset.y = 0.0
	if offset.is_zero_approx():
		return
	var local_direction := character.global_basis.orthonormalized().inverse() * offset.normalized()
	visual.rotation.y = atan2(-local_direction.x, -local_direction.z)

