extends SceneTree

const CATALOG_PATH := (
	"res://game/world/levels/standalone_areas/standalone_area_catalog.tres"
)
const LEVEL_BASE_PATH := "res://game/world/level_bases/level_base.tscn"
const ROUTE_SCENE_PATH := (
	"res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"
)
const STRETCHMAN_SCENE_PATH := (
	"res://game/actors/npcs/residents/stretchman/stretchman.tscn"
)
const MENU_BEHAVIOR_PATH := (
	"res://game/actors/npcs/shared/menu_npc_behavior.gd"
)
const ADVENTURE_MENU_PATH := (
	"res://game/ui/adventure_menu/adventure_menu.tscn"
)
const TRAINER_NAMES := [
	"TrainerKyle",
	"PoliceOfficer",
	"Businessman",
	"Backpacker",
	"Jogger",
	"Tourist",
	"DeliveryWorker",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_verify_level_base()
	_verify_standalone_catalog()
	await _verify_route_zero()
	_verify_stretchman()
	_verify_domain_autoloads()

	if _failures.is_empty():
		print(
			"Web export verification passed: the canonical level base, 50 editable "
			+ "standalone areas, static Route 0 trainers, ordinary menu-NPC "
			+ "Stretchman, and schema-6 domain services verified."
		)
		quit(0)
		return
	for failure in _failures:
		push_error("Web export verification failed: %s" % failure)
	quit(1)


func _verify_level_base() -> void:
	var packed := load(LEVEL_BASE_PATH) as PackedScene
	_check(packed != null, "The exported canonical level base should load.")
	if packed == null:
		return
	var level := packed.instantiate()
	_check(level != null, "The exported level base should instantiate.")
	if level == null:
		return
	var grid := level.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid"
	) as GridMap
	_check(
		level.get_node_or_null(^"Runtime") == null
		and level.get_node_or_null(^"Player") is CharacterBody3D
		and level.get_node_or_null(^"Player/Camera3D") is Camera3D
		and level.get_node_or_null(^"Player/GameUI") is CanvasLayer,
		"The exported level base should retain the direct Player/camera/GameUI hierarchy."
	)
	_check(
		grid != null and grid.get_used_cells().is_empty(),
		"The exported base ModularGroundGrid should remain empty."
	)
	level.free()


func _verify_standalone_catalog() -> void:
	var catalog := load(CATALOG_PATH)
	_check(catalog != null, "The exported standalone-area catalog should load.")
	if catalog == null:
		return
	var areas: Array = catalog.get("areas")
	_check(areas.size() == 50, "The exported catalog should contain exactly 50 areas.")
	var seen_ids: Dictionary = {}
	for area_value: Variant in areas:
		var area := area_value as Resource
		if area == null:
			_check(false, "Every exported catalog entry should be a Resource.")
			continue
		var area_id := String(area.get("area_id"))
		var destination := area.get("destination") as PackedScene
		_check(not area_id.is_empty() and not seen_ids.has(area_id), "Exported area IDs should be unique.")
		seen_ids[area_id] = true
		_check(
			destination != null and not destination.resource_path.is_empty(),
			"Exported area %s should retain its editable PackedScene." % area_id
		)
	for route_index in 41:
		_check(seen_ids.has("route_%02d" % route_index), "The export is missing a route area.")
	for gym_index in range(1, 9):
		_check(seen_ids.has("gym_%02d" % gym_index), "The export is missing a gym area.")
	_check(seen_ids.has("champion_challenge"), "The export is missing the champion challenge.")


func _verify_route_zero() -> void:
	var packed_route := load(ROUTE_SCENE_PATH) as PackedScene
	_check(packed_route != null, "The exported Route 0 scene should load.")
	if packed_route == null:
		return
	var route := packed_route.instantiate()
	var inherited_base := packed_route.get_state().get_node_instance(0)
	_check(
		inherited_base != null and inherited_base.resource_path == LEVEL_BASE_PATH,
		"Exported Route 0 should inherit the canonical level base directly."
	)
	var trainer_root := route.get_node_or_null(^"Gameplay/Actors/RouteTrainers")
	if trainer_root != null:
		trainer_root.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(route)
	await process_frame
	await physics_frame

	var player := route.get_node_or_null(^"Player") as Node3D
	var marker := route.get_node_or_null(^"Markers/Route0Start") as Marker3D
	_check(player != null and marker != null, "Route 0 should retain its player and entry marker.")
	_check(
		route.get_node_or_null(^"Player/Camera3D") != null
		and route.get_node_or_null(^"Player/GameUI") != null
		and route.get_node_or_null(^"Runtime") == null
		and route.get_node_or_null(^"NavigationRegion3D/WorldGeometry") != null
		and route.get_node_or_null(^"Gameplay/Encounters/TallGrassFields") != null,
		"Route 0 should retain the common editable level hierarchy."
	)
	var grid := route.get_node_or_null(^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid") as GridMap
	_check(grid != null and grid.get_used_cells().size() > 300, "Route 0 should export its painted grass/dirt terrain.")
	var completion_gate := route.get_node_or_null(
		^"Gameplay/Objectives/Route0CompletionGate"
	) as Area3D
	_check(
		completion_gate != null and int(completion_gate.get("route_index")) == 0,
		"Route 0 should retain its far-end progression gate."
	)
	_check(trainer_root != null and trainer_root.get_child_count() == 7, "Route 0 should retain seven static trainers.")
	# A clean verification profile can have the starter chooser open. This
	# fixture tests exported trainer behavior after normal player control resumes.
	var game_instance := root.get_node_or_null(^"GameInstance")
	if game_instance != null:
		game_instance.call("set_player_movement_enabled", true)
	for trainer_name in TRAINER_NAMES:
		var trainer := route.get_node_or_null(
			NodePath("Gameplay/Actors/RouteTrainers/%s" % trainer_name)
		) as Node3D
		var controller := trainer.get("controller") as Resource if trainer != null else null
		var behavior := controller.get("npc_behavior") as Resource if controller != null else null
		_check(trainer != null, "Route 0 should contain %s." % trainer_name)
		_check(
			behavior != null and not String(controller.get("encounter_id")).is_empty(),
			"Exported trainer %s should retain Inspector-authored encounter data." % trainer_name
		)
		_check(
			trainer != null and player != null and bool(trainer.call("can_interact", player)),
			"Exported trainer %s should accept manual interaction." % trainer_name
		)
		var battle := load(String(controller.get("battle_scene_path"))) as PackedScene if controller != null else null
		var battle_preview := battle.instantiate() if battle != null else null
		_check(
			battle_preview != null and battle_preview.get_script() != null,
			"Exported trainer %s should retain a scripted battle scene." % trainer_name
		)
		if battle_preview != null:
			battle_preview.free()

	route.free()


func _verify_stretchman() -> void:
	var packed := load(STRETCHMAN_SCENE_PATH) as PackedScene
	_check(packed != null, "The exported Stretchman scene should load.")
	if packed == null:
		return
	var stretchman := packed.instantiate()
	var controller := stretchman.get("controller") as Resource
	var behavior := controller.get("npc_behavior") as Resource if controller != null else null
	var menu_scene := behavior.get("menu_scene") as PackedScene if behavior != null else null
	_check(controller != null and behavior != null, "Stretchman should retain an NPC controller and behavior.")
	_check(
		behavior != null
		and behavior.get_script() is Script
		and (behavior.get_script() as Script).resource_path == MENU_BEHAVIOR_PATH,
		"Stretchman should use the reusable MenuNpcBehavior."
	)
	_check(
		menu_scene != null and menu_scene.resource_path == ADVENTURE_MENU_PATH,
		"Stretchman's menu_scene Inspector property should target Adventure Menu."
	)
	stretchman.free()


func _verify_domain_autoloads() -> void:
	var autosave := root.get_node_or_null(^"ProgressionAutosave")
	var autosave_constants: Dictionary = {}
	if autosave != null and autosave.get_script() is Script:
		autosave_constants = (autosave.get_script() as Script).get_script_constant_map()
	_check(
		autosave != null and int(autosave_constants.get("SAVE_SCHEMA_VERSION", 0)) == 6,
		"The exported progression owner should use domain-split schema 6."
	)
	for service_name in [
		&"EconomySystem",
		&"ShopSystem",
		&"InventorySystem",
		&"ChallengeProgressionSystem",
		&"BattleRewardSystem",
	]:
		_check(root.get_node_or_null(NodePath(String(service_name))) != null, "%s should be exported." % service_name)
	_check(root.get_node_or_null(^"StretchGoalSystem") == null, "The removed StretchGoalSystem must not be exported.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
