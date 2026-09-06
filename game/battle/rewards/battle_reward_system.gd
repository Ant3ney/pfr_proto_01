class_name BattleRewardService
extends Node

## Converts completed battle outcomes into money and challenge progression.

signal reward_granted(summary: Dictionary)


func _ready() -> void:
	if not BattleSystem.battle_ended.is_connected(_on_battle_ended):
		BattleSystem.battle_ended.connect(_on_battle_ended)


func _on_battle_ended(result: Dictionary) -> void:
	var launch_data := GameInstance.get_active_battle_data()
	var encounter_id := String(launch_data.get("encounter_id", "")).strip_edges()
	if encounter_id.is_empty():
		return
	var area := ChallengeProgressionSystem.get_area_for_encounter(encounter_id)
	var winner := String(result.get("winner", "tie"))
	var reason := String(result.get("reason", ""))
	if winner == "player" and area != null:
		ChallengeProgressionSystem.record_encounter_victory(encounter_id)
	var requested_reward := _calculate_reward(area, encounter_id, winner, reason)
	var granted_reward := EconomySystem.grant_money(requested_reward)
	var summary := {
		"amount": granted_reward,
		"winner": winner,
		"reason": reason,
		"encounter_id": encounter_id,
		"opponent": _opponent_name(launch_data, area, encounter_id),
		"area_id": area.area_id if area != null else "",
	}
	EconomySystem.record_battle_reward(summary)
	reward_granted.emit(summary.duplicate(true))


func _calculate_reward(
	area: StandaloneAreaDefinition,
	encounter_id: String,
	winner: String,
	reason: String
) -> int:
	if reason == "forfeit":
		return 0
	var base_reward := _win_reward(area, encounter_id)
	match winner:
		"player":
			return base_reward
		"tie":
			return maxi(roundi(base_reward * 0.25), 1)
		"opponent":
			return maxi(roundi(base_reward * 0.1), 1)
	return 0


func _win_reward(area: StandaloneAreaDefinition, encounter_id: String) -> int:
	if area == null:
		return 20
	match area.category:
		StandaloneAreaDefinition.Category.ROUTE:
			return 20 + roundi(float(area.numeric_order * area.numeric_order) * 6.21875) * 10
		StandaloneAreaDefinition.Category.GYM:
			var rewards: Array[int] = [200, 400, 750, 1_200, 2_000, 3_000, 4_500, 6_000]
			return rewards[clampi(area.numeric_order, 1, rewards.size()) - 1]
		StandaloneAreaDefinition.Category.CHAMPION:
			var encounter_ids: Array[String] = [
				"elite-four-01", "elite-four-02", "elite-four-03",
				"elite-four-04", "champion",
			]
			return 8_000 + maxi(encounter_ids.find(encounter_id), 0) * 1_000
	return 20


func _opponent_name(
	launch_data: Dictionary,
	area: StandaloneAreaDefinition,
	encounter_id: String
) -> String:
	var definition := ChallengeProgressionSystem.find_encounter_definition(encounter_id)
	if definition != null:
		return definition.display_name
	for field in ["trainer_name", "opponent_name", "encounter_name"]:
		var candidate := String(launch_data.get(field, "")).strip_edges()
		if not candidate.is_empty():
			return candidate
	return area.display_name if area != null else "Opponent"
