class_name NPCBehavior
extends Resource

## Base resource for NPC-specific behavior.
## Extend this class to create behaviors that can be assigned to an NPCController.


func _init() -> void:
	resource_local_to_scene = true


## Called by the owning controller during each physics movement update.
func process_behavior(
	_character: CharacterBody3D,
	_controller: NPCController
) -> void:
	pass
