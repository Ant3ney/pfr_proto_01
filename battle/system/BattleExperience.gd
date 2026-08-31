class_name BattleExperience
extends RefCounted

## Local PvE reward policy. The validated battle snapshot supplies the levels;
## CreatureSystem supplies the pinned community-derived species multiplier.

const BASE_XP_PER_DEFEATED_LEVEL := 10.0
const LEVEL_DIFFERENTIAL_STEP := 0.18
const MINIMUM_LEVEL_FACTOR := 0.4
const MAXIMUM_LEVEL_FACTOR := 2.2


static func calculate_award(
	participant_level: int,
	defeated_level: int,
	defeated_pokemon_id: int
) -> Dictionary:
	if (
		participant_level < 1
		or participant_level > 100
		or defeated_level < 1
		or defeated_level > 100
	):
		return {}
	var species_multiplier := CreatureSystem.get_xp_multiplier(defeated_pokemon_id)
	if species_multiplier <= 0.0:
		return {}
	var level_difference := defeated_level - participant_level
	var level_factor := clampf(
		1.0 + float(level_difference) * LEVEL_DIFFERENTIAL_STEP,
		MINIMUM_LEVEL_FACTOR,
		MAXIMUM_LEVEL_FACTOR
	)
	var base_xp := maxi(
		1,
		int(round(float(defeated_level) * BASE_XP_PER_DEFEATED_LEVEL * level_factor))
	)
	return {
		"amount": maxi(1, int(round(float(base_xp) * species_multiplier))),
		"baseXp": base_xp,
		"levelDifference": level_difference,
		"levelFactor": level_factor,
		"speciesMultiplier": species_multiplier,
	}
