@tool
class_name StandaloneAreaDefinition
extends Resource

## Inspector-editable identity, travel, progression, and encounter data for one
## menu-accessible walkable area.

enum Category {
	ROUTE,
	GYM,
	CHAMPION,
}

@export_group("Identity")
@export var area_id := ""
@export var category: Category = Category.ROUTE
@export_range(0, 40, 1) var numeric_order := 0
@export var display_name := ""
@export_multiline var description := ""
@export var biome := ""

@export_group("Travel")
@export var destination: PackedScene
@export var entry_spawn_marker: StringName = &"EntrySpawn"

@export_group("Difficulty")
@export_range(1, 100, 1) var suggested_level_min := 1
@export_range(1, 100, 1) var suggested_level_max := 1

@export_group("Battles")
@export var battle_encounters: Array[BattleEncounterDefinition] = []
@export var wild_encounters: Array[BattleEncounterDefinition] = []

@export_group("Progression")
## Area ID of the route that must be completed first. Empty for Route 0 and
## every non-route challenge.
@export var route_completion_prerequisite := ""


func get_category_key() -> String:
	match category:
		Category.ROUTE:
			return "route"
		Category.GYM:
			return "gym"
		Category.CHAMPION:
			return "champion"
	return ""


func get_all_encounters() -> Array[BattleEncounterDefinition]:
	var result: Array[BattleEncounterDefinition] = []
	result.append_array(battle_encounters)
	result.append_array(wild_encounters)
	return result


func to_menu_entry() -> Dictionary:
	return {
		"area_id": area_id,
		"kind": get_category_key(),
		"index": numeric_order,
		"name": display_name,
		"description": description,
		"biome": biome,
		"level_min": suggested_level_min,
		"level_max": suggested_level_max,
		"scene_path": destination.resource_path if destination != null else "",
		"spawn_marker": String(entry_spawn_marker),
		"route_completion_prerequisite": route_completion_prerequisite,
	}


func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if not _is_area_id_valid():
		errors.append("area_id does not match its category and numeric order")
	if display_name.strip_edges().is_empty():
		errors.append("display_name is required")
	if description.strip_edges().is_empty():
		errors.append("description is required")
	if destination == null or destination.resource_path.is_empty():
		errors.append("destination must reference a saved PackedScene")
	if entry_spawn_marker.is_empty():
		errors.append("entry_spawn_marker is required")
	if suggested_level_min > suggested_level_max:
		errors.append("suggested_level_min cannot exceed suggested_level_max")
	if category == Category.ROUTE:
		var expected_prerequisite := (
			"" if numeric_order == 0 else "route_%02d" % (numeric_order - 1)
		)
		if route_completion_prerequisite != expected_prerequisite:
			errors.append("route_completion_prerequisite must name the previous route")
	elif not route_completion_prerequisite.is_empty():
		errors.append("only routes may have a route completion prerequisite")
	var seen_encounters: Dictionary = {}
	for encounter in get_all_encounters():
		if encounter == null:
			errors.append("encounter reference is missing")
			continue
		if seen_encounters.has(encounter.encounter_id):
			errors.append("encounter_id is repeated: %s" % encounter.encounter_id)
		else:
			seen_encounters[encounter.encounter_id] = true
		for encounter_error in encounter.validate():
			errors.append("%s: %s" % [encounter.encounter_id, encounter_error])
	return errors


func _is_area_id_valid() -> bool:
	match category:
		Category.ROUTE:
			return numeric_order >= 0 and numeric_order < StandaloneAreaCatalog.ROUTE_COUNT and area_id == "route_%02d" % numeric_order
		Category.GYM:
			return numeric_order >= 1 and numeric_order <= 8 and area_id == "gym_%02d" % numeric_order
		Category.CHAMPION:
			return numeric_order == 1 and area_id == "champion_challenge"
	return false
