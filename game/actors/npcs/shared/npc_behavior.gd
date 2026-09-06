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


## Interaction capability advertised to the player-look dispatcher.
func can_interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> bool:
	return false


## Starts this behavior's interaction sequence when accepted.
func interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> bool:
	return false


func get_interaction_prompt(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> String:
	return "Interact"
