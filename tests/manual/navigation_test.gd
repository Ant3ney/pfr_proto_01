extends Node3D

## Demonstrates an NPC navigating around the center wall to a map coordinate.

@export var navigation_destination := Vector3(6.0, 0.0, 0.0)

@onready var npc: PFRCharacter = $NPC
@onready var status_label: Label = $UI/Status


func _ready() -> void:
	npc.controller.move_to(navigation_destination)


func _process(_delta: float) -> void:
	var distance_to_destination := Vector2(
		npc.global_position.x - navigation_destination.x,
		npc.global_position.z - navigation_destination.z
	).length()

	if distance_to_destination <= 0.2:
		status_label.text = "NPC arrived at %s" % navigation_destination
	else:
		status_label.text = (
			"NPC navigating to %s\nDistance remaining: %.2f m"
			% [navigation_destination, distance_to_destination]
		)
