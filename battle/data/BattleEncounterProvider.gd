class_name BattleEncounterProvider
extends Node

## Scene-local marker used by BattleSystem to discover exactly one authored
## encounter without receiving an opponent DTO from overworld code.

const GROUP_NAME := &"battle_encounter_provider"

@export var encounter: BattleEncounterDefinition


func _enter_tree() -> void:
	add_to_group(GROUP_NAME)


func get_encounter() -> BattleEncounterDefinition:
	return encounter
