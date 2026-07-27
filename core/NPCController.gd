class_name NPCController
extends Resource

## Supplies a persistent map-coordinate target to a PFRCharacter.

@export var map_coordinates := Vector3.ZERO:
	set(value):
		map_coordinates = value
		_has_move_target = true

var _has_move_target := false


func _init() -> void:
	resource_local_to_scene = true


func get_move_target(character: CharacterBody3D) -> Vector3:
	if not _has_move_target:
		map_coordinates = character.global_position

	return map_coordinates


func move_to(target_map_coordinates: Vector3) -> void:
	map_coordinates = target_map_coordinates
