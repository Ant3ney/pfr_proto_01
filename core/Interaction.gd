class_name Interaction
extends Resource

## Base resource for interactions.
## Extend this class to define what happens when one entity interacts with another.


func _init() -> void:
	resource_local_to_scene = true


## Called when an entity interacts with the resource's owning entity.
func interact(_interactor: Node, _interaction_target: Node) -> void:
	pass
