class_name ChallengeBattleEncounterProvider
extends BattleEncounterProvider

## Resolves the launch ID to the editor-authored encounter Resource stored with
## its standalone area.


func _ready() -> void:
	var launch_data := GameInstance.get_active_battle_data()
	if launch_data.is_empty():
		launch_data = GameInstance.get_pending_battle_data()
	var encounter_id := String(launch_data.get("encounter_id", "")).strip_edges()
	encounter = ChallengeProgressionSystem.find_encounter_definition(encounter_id)
	if encounter == null:
		push_error("Unknown standalone challenge encounter: %s" % encounter_id)
