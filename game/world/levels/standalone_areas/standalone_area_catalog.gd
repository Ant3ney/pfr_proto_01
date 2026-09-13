@tool
class_name StandaloneAreaCatalog
extends Resource

const ROUTE_COUNT := 41
const GYM_COUNT := 8
const TOTAL_AREA_COUNT := ROUTE_COUNT + GYM_COUNT + 1

@export var areas: Array[StandaloneAreaDefinition] = []


func get_area(area_id: String) -> StandaloneAreaDefinition:
	var normalized_id := area_id.strip_edges()
	for area in areas:
		if area != null and area.area_id == normalized_id:
			return area
	return null


func get_areas_for_category(category_key: String) -> Array[StandaloneAreaDefinition]:
	var result: Array[StandaloneAreaDefinition] = []
	for area in areas:
		if area != null and area.get_category_key() == category_key:
			result.append(area)
	result.sort_custom(func(left: StandaloneAreaDefinition, right: StandaloneAreaDefinition) -> bool:
		return left.numeric_order < right.numeric_order
	)
	return result


func find_encounter(encounter_id: String) -> BattleEncounterDefinition:
	var normalized_id := encounter_id.strip_edges()
	for area in areas:
		if area == null:
			continue
		for encounter in area.get_all_encounters():
			if encounter != null and encounter.encounter_id == normalized_id:
				return encounter
	return null


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if areas.size() != TOTAL_AREA_COUNT:
		errors.append("catalog must contain exactly %d areas" % TOTAL_AREA_COUNT)
	var seen_ids: Dictionary = {}
	var route_count := 0
	var gym_count := 0
	var champion_count := 0
	for area in areas:
		if area == null:
			errors.append("catalog contains a missing area definition")
			continue
		if seen_ids.has(area.area_id):
			errors.append("catalog repeats area_id: %s" % area.area_id)
		else:
			seen_ids[area.area_id] = true
		match area.category:
			StandaloneAreaDefinition.Category.ROUTE:
				route_count += 1
			StandaloneAreaDefinition.Category.GYM:
				gym_count += 1
			StandaloneAreaDefinition.Category.CHAMPION:
				champion_count += 1
		for area_error in area.validate():
			errors.append("%s: %s" % [area.area_id, area_error])
	if route_count != ROUTE_COUNT:
		errors.append("catalog must contain exactly %d routes" % ROUTE_COUNT)
	if gym_count != GYM_COUNT:
		errors.append("catalog must contain exactly %d gyms" % GYM_COUNT)
	if champion_count != 1:
		errors.append("catalog must contain exactly one champion challenge")
	for route_index in ROUTE_COUNT:
		if not seen_ids.has("route_%02d" % route_index):
			errors.append("catalog is missing route_%02d" % route_index)
	for gym_index in range(1, GYM_COUNT + 1):
		if not seen_ids.has("gym_%02d" % gym_index):
			errors.append("catalog is missing gym_%02d" % gym_index)
	if not seen_ids.has("champion_challenge"):
		errors.append("catalog is missing champion_challenge")
	return errors
