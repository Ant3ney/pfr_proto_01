class_name NPCController
extends Resource

## Supplies movement and navigation state to a PFRCharacter.

## Serialized compatibility mirror for scenes authored before PFRCharacter
## directly owned its NPC behavior. New content must assign
## PFRCharacter.npc_behavior instead.
@export_storage var npc_behavior: NPCBehavior

@export_group("Navigation")
## Last requested destination. Merely deserializing this stored value must not
## activate navigation; callers start travel explicitly through move_to().
@export var map_coordinates := Vector3.ZERO

var _has_move_target := false
var _target_changed := false
var _navigation_agent: NavigationAgent3D
var _navigation_map_iteration := 0


func _init() -> void:
	resource_local_to_scene = true


## Gives custom controller resources one deterministic point to synchronize
## configuration after PackedScene resource duplication.
func prepare_for_character(_character: CharacterBody3D) -> void:
	pass


func get_move_target(character: CharacterBody3D) -> Vector3:
	if not _has_move_target:
		return character.global_position

	var navigation_agent := _get_navigation_agent(character)
	var navigation_map := navigation_agent.get_navigation_map()
	var map_iteration := NavigationServer3D.map_get_iteration_id(navigation_map)
	if map_iteration == 0:
		return character.global_position

	if map_iteration != _navigation_map_iteration:
		_navigation_map_iteration = map_iteration
		_target_changed = true

	if _target_changed:
		_align_path_height_with_character(
			character,
			navigation_agent,
			navigation_map
		)
		navigation_agent.target_position = map_coordinates
		_target_changed = false
	elif navigation_agent.is_navigation_finished():
		return character.global_position

	return navigation_agent.get_next_path_position()


func move_to(target_map_coordinates: Vector3) -> void:
	if (
		_has_move_target
		and map_coordinates.is_equal_approx(target_map_coordinates)
	):
		return

	map_coordinates = target_map_coordinates
	_has_move_target = true
	_target_changed = true


func stop_moving(character: CharacterBody3D) -> void:
	_has_move_target = false
	_target_changed = false

	if is_instance_valid(_navigation_agent):
		_navigation_agent.target_position = character.global_position


func can_interact(
	character: CharacterBody3D,
	interactor: PlayerCharacter
) -> bool:
	return (
		npc_behavior != null
		and npc_behavior.can_interact(character, self, interactor)
	)


func interact(
	character: CharacterBody3D,
	interactor: PlayerCharacter
) -> bool:
	if not can_interact(character, interactor):
		return false
	return npc_behavior.interact(character, self, interactor)


func get_interaction_prompt(
	character: CharacterBody3D,
	interactor: PlayerCharacter
) -> String:
	if npc_behavior == null:
		return ""
	return npc_behavior.get_interaction_prompt(character, self, interactor)


func _get_navigation_agent(character: CharacterBody3D) -> NavigationAgent3D:
	if is_instance_valid(_navigation_agent):
		return _navigation_agent

	_navigation_agent = NavigationAgent3D.new()
	_navigation_agent.name = "NavigationAgent3D"
	_navigation_agent.path_desired_distance = 0.35
	_navigation_agent.target_desired_distance = 0.1
	character.add_child(_navigation_agent)
	_target_changed = true
	return _navigation_agent


## Navigation baking can place returned path points above the visible floor.
## Align those points with the character's foot-level pivot so planar locomotion
## can advance through the path without moving the character vertically.
func _align_path_height_with_character(
	character: CharacterBody3D,
	navigation_agent: NavigationAgent3D,
	navigation_map: RID
) -> void:
	var closest_path_point := NavigationServer3D.map_get_closest_point(
		navigation_map,
		character.global_position
	)
	navigation_agent.path_height_offset = (
		closest_path_point.y - character.global_position.y
	)
