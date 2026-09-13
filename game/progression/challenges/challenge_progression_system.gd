class_name ChallengeProgressionService
extends Node

## Owns standalone-area unlocks, active runs, defeated encounters, badges, and
## champion completion. Area layout and encounter rosters live in Resources.

signal progression_changed
signal area_started(area: StandaloneAreaDefinition)
signal route_progression_changed(completed_routes: Array[int])

const CATALOG_PATH := (
	"res://game/world/levels/standalone_areas/standalone_area_catalog.tres"
)

var _catalog: StandaloneAreaCatalog
var _earned_badges: Array[int] = []
var _champion_completed := false
var _completed_routes: Array[int] = []
var _active_area_id := ""
var _run_defeated_ids: Dictionary = {}
var _run_id := 0
var _last_error := ""


func _ready() -> void:
	_catalog = load(CATALOG_PATH) as StandaloneAreaCatalog
	if _catalog == null:
		push_error("Standalone area catalog could not be loaded.")
		return
	var catalog_errors := _catalog.validate()
	if not catalog_errors.is_empty():
		push_error("Standalone area catalog is invalid: %s" % "; ".join(catalog_errors))


func get_catalog() -> StandaloneAreaCatalog:
	return _catalog


func get_area(area_id: String) -> StandaloneAreaDefinition:
	return _catalog.get_area(area_id) if _catalog != null else null


func get_destinations(category_key: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _catalog == null:
		return entries
	for area in _catalog.get_areas_for_category(category_key):
		var entry := area.to_menu_entry()
		if category_key == "route":
			entry["unlocked"] = is_area_unlocked(area.area_id)
			entry["completed"] = is_route_completed(area.numeric_order)
			entry["unlock_requirement"] = (
				"Available from the beginning."
				if area.route_completion_prerequisite.is_empty()
				else "Reach the end of %s."
				% area.route_completion_prerequisite.replace("_", " ").capitalize()
			)
		entries.append(entry)
	return entries


func launch_area(
	area_id: String,
	spawn_marker: StringName = &"",
	continue_journey: bool = false
) -> bool:
	_last_error = ""
	var area := get_area(area_id)
	if area == null:
		_last_error = "Unknown standalone area: %s" % area_id
		return false
	if not is_area_unlocked(area.area_id):
		_last_error = "%s is locked. Complete %s first." % [
			area.display_name,
			area.route_completion_prerequisite.replace("_", " ").capitalize(),
		]
		return false
	var previous_area_id := _active_area_id
	var previous_defeated := _run_defeated_ids.duplicate(true)
	var previous_run_id := _run_id
	_active_area_id = area.area_id
	if not continue_journey:
		_run_defeated_ids.clear()
		_run_id += 1
	if not GameInstance.transfer_to_scene(
		area.destination.resource_path,
		area.entry_spawn_marker if spawn_marker.is_empty() else spawn_marker
	):
		_active_area_id = previous_area_id
		_run_defeated_ids = previous_defeated
		_run_id = previous_run_id
		_last_error = "The selected area could not be opened."
		return false
	progression_changed.emit()
	area_started.emit(area)
	return true


func get_active_area_id() -> String:
	return _active_area_id


func get_active_area() -> StandaloneAreaDefinition:
	return get_area(_active_area_id)


func get_completed_routes() -> Array[int]:
	return _completed_routes.duplicate()


func is_route_completed(route_index: int) -> bool:
	return route_index in _completed_routes


func is_route_unlocked(route_index: int) -> bool:
	return is_area_unlocked("route_%02d" % route_index)


func is_area_unlocked(area_id: String) -> bool:
	var area := get_area(area_id)
	if area == null:
		return false
	if area.category != StandaloneAreaDefinition.Category.ROUTE:
		return true
	return (
		area.route_completion_prerequisite.is_empty()
		or is_route_completed(area.numeric_order - 1)
	)


func are_route_trainers_defeated(route_index: int) -> bool:
	if route_index == 0:
		return true
	var area := get_area("route_%02d" % route_index)
	if area == null or not _is_current_run_for_area(area.area_id):
		return false
	if area.battle_encounters.is_empty():
		return false
	for encounter in area.battle_encounters:
		if encounter == null or not _run_defeated_ids.has(encounter.encounter_id):
			return false
	return true


func complete_route_at_end(route_index: int) -> Dictionary:
	_last_error = ""
	if not is_route_unlocked(route_index):
		_last_error = "Route %d is not unlocked." % route_index
		return {"ok": false, "error": _last_error}
	if route_index > 0 and not are_route_trainers_defeated(route_index):
		_last_error = "Defeat every Route %d trainer before using the exit." % route_index
		return {"ok": false, "error": _last_error}
	var newly_completed := route_index not in _completed_routes
	if newly_completed:
		_completed_routes.append(route_index)
		_completed_routes.sort()
		progression_changed.emit()
		route_progression_changed.emit(_completed_routes.duplicate())
	var next_route := route_index + 1 if route_index < StandaloneAreaCatalog.ROUTE_COUNT - 1 else -1
	return {
		"ok": true,
		"route_index": route_index,
		"newly_completed": newly_completed,
		"next_route": next_route,
		"next_route_unlocked": next_route >= 0 and is_route_unlocked(next_route),
		"all_routes_completed": next_route < 0,
	}


func find_encounter_definition(encounter_id: String) -> BattleEncounterDefinition:
	if _catalog == null:
		return null
	return _catalog.find_encounter(encounter_id)


func get_area_for_encounter(encounter_id: String) -> StandaloneAreaDefinition:
	if _catalog == null:
		return null
	var normalized_id := encounter_id.strip_edges()
	for area in _catalog.areas:
		if area == null:
			continue
		for encounter in area.get_all_encounters():
			if encounter != null and encounter.encounter_id == normalized_id:
				return area
	return null


func is_wild_encounter(encounter_id: String) -> bool:
	var area := get_area_for_encounter(encounter_id)
	if area == null:
		return false
	for encounter in area.wild_encounters:
		if encounter != null and encounter.encounter_id == encounter_id:
			return true
	return false


func record_encounter_victory(encounter_id: String) -> void:
	var normalized_id := encounter_id.strip_edges()
	if normalized_id.is_empty() or is_wild_encounter(normalized_id):
		return
	var area := get_area_for_encounter(normalized_id)
	if area == null:
		return
	if _active_area_id.is_empty():
		_active_area_id = area.area_id
	if area.area_id == _active_area_id:
		_run_defeated_ids[normalized_id] = true
	match area.category:
		StandaloneAreaDefinition.Category.GYM:
			if area.numeric_order not in _earned_badges:
				_earned_badges.append(area.numeric_order)
				_earned_badges.sort()
		StandaloneAreaDefinition.Category.CHAMPION:
			if normalized_id == "champion":
				_champion_completed = true
	progression_changed.emit()


func is_encounter_defeated(encounter_id: String) -> bool:
	return _run_defeated_ids.has(encounter_id.strip_edges())


func get_run_defeated_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: Variant in _run_defeated_ids.keys():
		ids.append(String(key))
	ids.sort()
	return ids


func get_earned_badges() -> Array[int]:
	return _earned_badges.duplicate()


func has_badge(gym_index: int) -> bool:
	return gym_index in _earned_badges


func is_champion_completed() -> bool:
	return _champion_completed


func get_last_error() -> String:
	return _last_error


func get_save_data() -> Dictionary:
	return {
		"earned_badges": _earned_badges.duplicate(),
		"champion_completed": _champion_completed,
		"completed_routes": _completed_routes.duplicate(),
		"active_area_id": _active_area_id,
		"run_defeated_ids": get_run_defeated_ids(),
		"run_id": _run_id,
	}


func validate_save_data(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "Challenge progression is not an object."
	var data := value as Dictionary
	var badges: Variant = data.get("earned_badges", [])
	if typeof(badges) != TYPE_ARRAY:
		return "Challenge progression has an invalid badge list."
	var seen_badges: Dictionary = {}
	for badge_value: Variant in badges as Array:
		if not _is_integer(badge_value) or int(badge_value) < 1 or int(badge_value) > 8:
			return "Challenge progression contains an invalid badge."
		if seen_badges.has(int(badge_value)):
			return "Challenge progression repeats a badge."
		seen_badges[int(badge_value)] = true
	if typeof(data.get("champion_completed", false)) != TYPE_BOOL:
		return "Challenge progression has an invalid champion flag."
	var routes: Variant = data.get("completed_routes", [])
	if typeof(routes) != TYPE_ARRAY:
		return "Challenge progression has an invalid completed-route list."
	var seen_routes: Dictionary = {}
	for route_value: Variant in routes as Array:
		if not _is_integer(route_value) or int(route_value) < 0 or int(route_value) >= StandaloneAreaCatalog.ROUTE_COUNT:
			return "Challenge progression contains an invalid completed route."
		var route_index := int(route_value)
		if seen_routes.has(route_index):
			return "Challenge progression repeats a completed route."
		if route_index > 0 and not seen_routes.has(route_index - 1):
			return "Challenge progression skips a required route."
		seen_routes[route_index] = true
	var active_area_id: Variant = data.get("active_area_id", "")
	if typeof(active_area_id) != TYPE_STRING:
		return "Challenge progression has an invalid active area ID."
	if not String(active_area_id).is_empty() and get_area(String(active_area_id)) == null:
		return "Challenge progression references an unknown active area."
	var defeated: Variant = data.get("run_defeated_ids", [])
	if typeof(defeated) != TYPE_ARRAY:
		return "Challenge progression has an invalid defeated-encounter list."
	var seen_defeated: Dictionary = {}
	for encounter_value: Variant in defeated as Array:
		if (
			typeof(encounter_value) != TYPE_STRING
			or find_encounter_definition(String(encounter_value)) == null
		):
			return "Challenge progression references an unknown defeated encounter."
		if seen_defeated.has(String(encounter_value)):
			return "Challenge progression repeats a defeated encounter."
		seen_defeated[String(encounter_value)] = true
	var run_id: Variant = data.get("run_id", 0)
	if not _is_integer(run_id) or int(run_id) < 0:
		return "Challenge progression has an invalid run ID."
	return ""


func load_save_data(value: Variant) -> bool:
	_last_error = validate_save_data(value)
	if not _last_error.is_empty():
		return false
	var data := value as Dictionary
	_earned_badges.clear()
	for badge_value: Variant in data.get("earned_badges", []) as Array:
		_earned_badges.append(int(badge_value))
	_earned_badges.sort()
	_champion_completed = bool(data.get("champion_completed", false))
	_completed_routes.clear()
	for route_value: Variant in data.get("completed_routes", []) as Array:
		_completed_routes.append(int(route_value))
	_completed_routes.sort()
	_active_area_id = String(data.get("active_area_id", ""))
	_run_defeated_ids.clear()
	for encounter_value: Variant in data.get("run_defeated_ids", []) as Array:
		_run_defeated_ids[String(encounter_value)] = true
	_run_id = int(data.get("run_id", 0))
	progression_changed.emit()
	route_progression_changed.emit(_completed_routes.duplicate())
	return true


func reset_progress() -> void:
	_earned_badges.clear()
	_champion_completed = false
	_completed_routes.clear()
	_active_area_id = ""
	_run_defeated_ids.clear()
	_run_id = 0
	_last_error = ""
	progression_changed.emit()
	route_progression_changed.emit(_completed_routes.duplicate())


func _is_current_run_for_area(area_id: String) -> bool:
	if _active_area_id == area_id:
		return true
	var scene := get_tree().current_scene
	return scene is PFRWorldLevel and (scene as PFRWorldLevel).area_id == area_id


func _is_integer(value: Variant) -> bool:
	return (
		typeof(value) == TYPE_INT
		or (
			typeof(value) == TYPE_FLOAT
			and is_finite(float(value))
			and floorf(float(value)) == float(value)
		)
	)
