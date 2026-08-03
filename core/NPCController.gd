class_name NPCController
extends Resource

## Supplies a persistent map-coordinate target to a PFRCharacter.

@export_group("Behavior")
## NPC-specific behavior. Accepts NPCBehavior resources and their subclasses.
@export var npc_behavior: NPCBehavior

@export_group("Navigation")
@export var map_coordinates := Vector3.ZERO:
	set(value):
		map_coordinates = value
		_has_move_target = true
		_target_changed = true

var _has_move_target := false
var _target_changed := false
var _navigation_agent: NavigationAgent3D
var _navigation_map_iteration := 0


func _init() -> void:
	resource_local_to_scene = true


func get_move_target(character: CharacterBody3D) -> Vector3:
	if npc_behavior:
		npc_behavior.process_behavior(character, self)

	if not _has_move_target:
		map_coordinates = character.global_position
		return map_coordinates

	var navigation_agent := _get_navigation_agent(character)
	var navigation_map := navigation_agent.get_navigation_map()
	var map_iteration := NavigationServer3D.map_get_iteration_id(navigation_map)
	if map_iteration == 0:
		return character.global_position

	if map_iteration != _navigation_map_iteration:
		_navigation_map_iteration = map_iteration
		_target_changed = true

	if _target_changed:
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
