class_name TrainerKyle
extends NPCController

## Controller configuration for Trainer Kyle in the lake overworld.

const KYLE_BATTLE_SCENE_PATH := "res://battle/kyle_battle_scene.tscn"
const KYLE_ENCOUNTER_ID := "trainer-kyle-lake-v1"

@export_group("Trainer")
@export var dialog: Dialog:
	set(value):
		dialog = value
		var trainer_behavior := npc_behavior as TrainerBehavior
		if trainer_behavior:
			trainer_behavior.dialog = dialog

@export_file("*.tscn") var battle_scene_path := KYLE_BATTLE_SCENE_PATH:
	set(value):
		battle_scene_path = value
		var trainer_behavior := npc_behavior as TrainerBehavior
		if trainer_behavior:
			trainer_behavior.battle_scene_path = battle_scene_path

@export var encounter_id := KYLE_ENCOUNTER_ID:
	set(value):
		encounter_id = value
		var trainer_behavior := npc_behavior as TrainerBehavior
		if trainer_behavior:
			trainer_behavior.encounter_id = encounter_id


func _init() -> void:
	var trainer_behavior := TrainerBehavior.new()
	trainer_behavior.detection_distance = 80.0
	trainer_behavior.ray_height = 0.8
	trainer_behavior.detection_collision_mask = 1
	trainer_behavior.stopping_buffer = 0.15
	trainer_behavior.arrival_distance = 0.15
	trainer_behavior.dialog = dialog
	trainer_behavior.battle_scene_path = battle_scene_path
	trainer_behavior.encounter_id = encounter_id
	npc_behavior = trainer_behavior
