class_name TrainerKyle
extends NPCController

## Controller configuration for Trainer Kyle in the lake overworld.

const KYLE_BATTLE_SCENE_PATH := "res://battle/kyle_battle_scene.tscn"
const KYLE_ENCOUNTER_ID := "trainer-kyle-lake-v1"

@export_group("Trainer")
@export var automatic_sight_encounter := true:
	set(value):
		automatic_sight_encounter = value
		_synchronize_behavior_configuration()

@export var aggression_mode: TrainerBehavior.AggressionMode = (
	TrainerBehavior.AggressionMode.STANDARD
):
	set(value):
		aggression_mode = value
		_synchronize_behavior_configuration()

@export var dialog: Dialog:
	set(value):
		dialog = value
		_synchronize_behavior_configuration()

@export_file("*.tscn") var battle_scene_path := KYLE_BATTLE_SCENE_PATH:
	set(value):
		battle_scene_path = value
		_synchronize_behavior_configuration()

@export var encounter_id := KYLE_ENCOUNTER_ID:
	set(value):
		encounter_id = value
		_synchronize_behavior_configuration()


func _init() -> void:
	var trainer_behavior := TrainerBehavior.new()
	trainer_behavior.detection_distance = 80.0
	trainer_behavior.ray_height = 0.8
	trainer_behavior.detection_collision_mask = 1
	trainer_behavior.automatic_sight_encounter = automatic_sight_encounter
	trainer_behavior.stopping_buffer = 0.15
	trainer_behavior.arrival_distance = 0.15
	npc_behavior = trainer_behavior
	_synchronize_behavior_configuration()


func prepare_for_character(_character: CharacterBody3D) -> void:
	# PackedScene duplication copies exported controller fields without invoking
	# their setters. Reapply them so the scene-local behavior cannot fall back to
	# the generic battle preview.
	_synchronize_behavior_configuration()


func _synchronize_behavior_configuration() -> void:
	var trainer_behavior := npc_behavior as TrainerBehavior
	if trainer_behavior == null:
		return
	trainer_behavior.automatic_sight_encounter = automatic_sight_encounter
	trainer_behavior.aggression_mode = aggression_mode
	trainer_behavior.dialog = dialog
	trainer_behavior.battle_scene_path = battle_scene_path
	trainer_behavior.encounter_id = encounter_id
