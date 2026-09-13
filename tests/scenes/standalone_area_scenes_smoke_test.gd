extends Node

const CATALOG_PATH := "res://game/world/levels/standalone_areas/standalone_area_catalog.tres"
const LEVEL_BASE_PATH := "res://game/world/level_bases/level_base.tscn"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := load(CATALOG_PATH) as StandaloneAreaCatalog
	_check(catalog != null, "The standalone-area catalog should load as its typed Resource.")
	if catalog == null:
		_finish()
		return
	_check(catalog.validate().is_empty(), "The 50-area catalog and its encounter resources should validate.")
	_check(catalog.areas.size() == StandaloneAreaCatalog.TOTAL_AREA_COUNT, "The catalog should contain exactly 41 routes, eight gyms, and one champion challenge.")

	var seen_scene_paths: Dictionary = {}
	var seen_area_ids: Dictionary = {}
	for area in catalog.areas:
		_check(area != null, "Every catalog slot should reference an area definition.")
		if area == null:
			continue
		_check(not seen_area_ids.has(area.area_id), "Area IDs should be unique: %s" % area.area_id)
		seen_area_ids[area.area_id] = true
		_check(area.destination != null, "%s should reference an editable destination scene." % area.area_id)
		if area.destination == null:
			continue
		var scene_path := area.destination.resource_path
		_check(not seen_scene_paths.has(scene_path), "Every menu destination should own an independent scene: %s" % scene_path)
		seen_scene_paths[scene_path] = true
		_check(scene_path.get_base_dir().path_join("area_definition.tres") == area.resource_path, "%s should keep area_definition.tres beside its scene." % area.area_id)
		_check(ResourceLoader.exists(scene_path, "PackedScene"), "%s should reference a loadable PackedScene." % area.area_id)
		_check(_source_uses_level_base(scene_path), "%s should inherit the canonical level base directly." % area.area_id)
		_check_area_scene(area)

	for route_index in StandaloneAreaCatalog.ROUTE_COUNT:
		_check(seen_area_ids.has("route_%02d" % route_index), "The catalog should contain route_%02d." % route_index)
	for gym_index in range(1, 9):
		_check(seen_area_ids.has("gym_%02d" % gym_index), "The catalog should contain gym_%02d." % gym_index)
	_check(seen_area_ids.has("champion_challenge"), "The catalog should contain champion_challenge.")
	_check(not ResourceLoader.exists("res://rnd/stretch/worlds/stretch_destination.tscn"), "The procedural destination scene should be removed.")
	_check(not ResourceLoader.exists("res://rnd/stretch/StretchContent.gd"), "Runtime destination content generation should be removed.")
	_finish()


func _check_area_scene(area: StandaloneAreaDefinition) -> void:
	var world := area.destination.instantiate() as PFRWorldLevel
	_check(world != null, "%s should instantiate as PFRWorldLevel." % area.area_id)
	if world == null:
		return
	_check(world.area_id == area.area_id, "%s should expose its stable area_id on the level root." % area.area_id)
	_check(world.entry_spawn_marker == area.entry_spawn_marker, "%s should use the definition's entry marker." % area.area_id)
	for required_path in [
		^"Player",
		^"Player/Camera3D",
		^"Player/GameUI",
		^"Environment",
		^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid",
		^"NavigationRegion3D/WorldGeometry/Ground",
		^"NavigationRegion3D/WorldGeometry/Structures",
		^"NavigationRegion3D/WorldGeometry/Props",
		^"NavigationRegion3D/WorldGeometry/Boundaries",
		^"Gameplay/Actors",
		^"Gameplay/Encounters",
		^"Gameplay/Interactions",
		^"Gameplay/Transitions",
		^"Gameplay/Objectives",
		^"Markers",
		^"Backdrop",
	]:
		_check(world.get_node_or_null(required_path) != null, "%s should expose common level node %s." % [area.area_id, required_path])
	_check(world.find_spawn_marker(area.entry_spawn_marker) != null, "%s should contain its Inspector-selected entry marker." % area.area_id)

	var actors := world.get_node_or_null(^"Gameplay/Actors")
	var trainers: Array[Node] = []
	if actors != null:
		trainers = actors.find_children("*", "PFRCharacter", true, false)
	_check(trainers.size() == area.battle_encounters.size(), "%s should contain one visible trainer instance per authored battle encounter." % area.area_id)
	for trainer_node in trainers:
		var trainer := trainer_node as PFRCharacter
		var controller := trainer.controller as TrainerController
		var behavior := controller.npc_behavior as TrainerBehavior if controller != null else null
		_check(controller != null and behavior != null, "%s trainers should inherit the shared trainer controller and behavior." % area.area_id)
		if controller == null:
			continue
		_check(
			trainer.has_meta("encounter_id") or not controller.encounter_id.is_empty(),
			"%s trainers should expose encounter IDs in the Inspector." % area.area_id
		)
		_check(
			controller.dialog != null and not controller.dialog.is_empty(),
			"%s trainer %s should have non-empty pre-battle dialog."
			% [area.area_id, trainer.name]
		)
		_check(
			ResourceLoader.exists(controller.battle_scene_path, "PackedScene"),
			"%s trainer %s should reference a loadable battle scene."
			% [area.area_id, trainer.name]
		)
		_check(
			_encounter_list_has_id(area.battle_encounters, controller.encounter_id),
			"%s trainer %s should reference an encounter owned by its area."
			% [area.area_id, trainer.name]
		)
		if area.category == StandaloneAreaDefinition.Category.ROUTE:
			_check(
				controller.aggression_mode == TrainerBehavior.AggressionMode.STANDARD
				and behavior != null and not behavior.is_highly_aggro(),
				"%s trainer %s should allow only one forced sight battle, then manual rematches."
				% [area.area_id, trainer.name]
			)
			_check(
				controller.automatic_sight_encounter
				and behavior != null and behavior.automatic_sight_encounter,
				"%s trainer %s should retain the initial sight challenge."
				% [area.area_id, trainer.name]
			)
		else:
			_check(
				not controller.automatic_sight_encounter,
				"%s boss %s should wait for player interaction instead of sight detection."
				% [area.area_id, trainer.name]
			)
			_check(
				behavior != null and not behavior.automatic_sight_encounter,
				"%s boss %s should synchronize manual-only interaction into its behavior."
				% [area.area_id, trainer.name]
			)

	if area.category == StandaloneAreaDefinition.Category.ROUTE:
		var grass_zones := world.find_children("*", "TallGrassEncounterZone", true, false)
		_check(not grass_zones.is_empty(), "%s should contain authored tall-grass scene instances." % area.area_id)
		for grass_node in grass_zones:
			var grass := grass_node as TallGrassEncounterZone
			_check(_encounter_list_has_id(area.wild_encounters, grass.encounter_id), "%s grass should reference its area-owned wild encounter." % area.area_id)
		_check(world.find_children("*", "RouteCompletionGate", true, false).size() == 1, "%s should contain one physical completion gate." % area.area_id)
	elif area.category == StandaloneAreaDefinition.Category.GYM:
		_check(area.battle_encounters.size() == 1, "%s should own exactly one gym-leader encounter." % area.area_id)
	else:
		_check(area.battle_encounters.size() == 5, "The champion scene should visibly contain Elite Four 1–4 and the Champion.")
	world.free()


func _source_uses_level_base(scene_path: String) -> bool:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return false
	var inherited_base := packed.get_state().get_node_instance(0)
	return inherited_base != null and inherited_base.resource_path == LEVEL_BASE_PATH


func _encounter_list_has_id(encounters: Array[BattleEncounterDefinition], encounter_id: String) -> bool:
	for encounter in encounters:
		if encounter != null and encounter.encounter_id == encounter_id:
			return true
	return false


func _finish() -> void:
	if _failures.is_empty():
		print("Standalone area scene smoke test passed: exactly 50 independent scenes inherit the canonical level base with local definitions, static trainers, manual bosses, grass, gates, encounters, and common level structure verified.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Standalone area scene smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
