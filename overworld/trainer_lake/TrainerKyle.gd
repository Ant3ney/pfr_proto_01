class_name TrainerKyle
extends NPCController

## Controller configuration for Trainer Kyle in the lake overworld.

@export_group("Trainer")
@export var dialog: Dialog:
	set(value):
		dialog = value
		var trainer_behavior := npc_behavior as TrainerBehavior
		if trainer_behavior:
			trainer_behavior.dialog = dialog


func _init() -> void:
	var trainer_behavior := TrainerBehavior.new()
	trainer_behavior.detection_distance = 80.0
	trainer_behavior.ray_height = 0.8
	trainer_behavior.detection_collision_mask = 1
	trainer_behavior.stopping_buffer = 0.15
	trainer_behavior.arrival_distance = 0.15
	trainer_behavior.dialog = dialog
	npc_behavior = trainer_behavior
