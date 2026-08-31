class_name RNDStretchBattleEncounterProvider
extends BattleEncounterProvider

## Builds one validated encounter from the standard GameInstance launch ID
## before BattleScene's parent-ready callback asks BattleSystem to discover it.

const SpeciesMapping := preload("res://battle/system/BattleSpeciesMapping.gd")


func _ready() -> void:
	var launch_data := GameInstance.get_active_battle_data()
	if launch_data.is_empty():
		# Child nodes become ready before BattleScene promotes pending launch data.
		launch_data = GameInstance.get_pending_battle_data()
	if not configure_from_launch_data(launch_data):
		push_error(
			"Unknown Stretchman encounter launch ID: %s"
			% String(launch_data.get("encounter_id", "")).strip_edges()
		)


func configure_from_launch_data(launch_data: Dictionary) -> bool:
	var encounter_id := String(launch_data.get("encounter_id", "")).strip_edges()
	var payload := StretchGoalSystem.get_encounter_by_id(encounter_id)
	if payload.is_empty():
		encounter = null
		return false
	_build_encounter(payload)
	return encounter != null


func _build_encounter(payload: Dictionary) -> void:

	var definition := BattleEncounterDefinition.new()
	definition.encounter_id = String(payload.get("encounter_id", ""))
	definition.display_name = String(payload.get("display_name", "Stretch Trainer"))
	definition.api_name = String(payload.get("api_name", "Stretch Trainer"))
	definition.forfeit_policy = BattleEncounterDefinition.ForfeitPolicy.ALLOWED

	var built_members: Array[BattleEncounterMember] = []
	var members_value: Variant = payload.get("members", [])
	if typeof(members_value) == TYPE_ARRAY:
		for member_value: Variant in members_value as Array:
			if typeof(member_value) != TYPE_DICTIONARY:
				continue
			var source := member_value as Dictionary
			var pokemon_id := int(source.get("pokemon_id", 0))
			var mapping := SpeciesMapping.get_entry(pokemon_id)
			if mapping.is_empty():
				push_error("Stretch encounter Pokemon ID %d has no battle mapping." % pokemon_id)
				continue
			var member := BattleEncounterMember.new()
			member.member_id = String(source.get("member_id", ""))
			member.pokemon_id = pokemon_id
			member.species = String(mapping.get("species", ""))
			member.sprite_id = String(mapping.get("spriteId", ""))
			member.level = int(source.get("level", 1))
			member.health = 1.0
			var moves: Array[String] = []
			for move_value: Variant in mapping.get("defaultMoves", []) as Array:
				moves.append(String(move_value))
			member.moves = moves
			built_members.append(member)
	definition.members = built_members
	encounter = definition
