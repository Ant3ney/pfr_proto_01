extends Node

const LEVEL_BASE_DIRECTORY := "res://game/world/level_bases"
const LEVEL_BASE_PATH := LEVEL_BASE_DIRECTORY + "/level_base.tscn"
const PLAYER_SCENE_PATH := "res://game/actors/player/player.tscn"
const GROUND_LIBRARY_PATH := (
	"res://game/world/level_kits/terrain/new_bouffalant_city/ground/"
	+ "ground_tile_mesh_library.tres"
)
const CITY_PATH := (
	"res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
)
const ROUTE_ZERO_PATH := (
	"res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"
)
const STANDALONE_CATALOG_PATH := (
	"res://game/world/levels/standalone_areas/standalone_area_catalog.tres"
)
const CITY_LEVEL_PATHS: Array[String] = [
	CITY_PATH,
	"res://game/world/levels/new_bouffalant_city/interiors/city_hall_interior.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/garage_workshop.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/gatehouse_interior.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/miare_station_concourse.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/museum_gallery.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/north_tenant_lobby.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_annex.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_interior.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/rouge_tower_lobby.tscn",
	"res://game/world/levels/new_bouffalant_city/interiors/west_tenant_lobby.tscn",
]
const REQUIRED_LEVEL_PATHS: Array[NodePath] = [
	^"Player",
	^"Player/Camera3D",
	^"Player/GameUI",
	^"Environment",
	^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid",
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
]
const DESCRIBED_CONTAINER_PATHS: Array[NodePath] = [
	^"NavigationRegion3D/WorldGeometry/Ground",
	^"NavigationRegion3D/WorldGeometry/Structures",
	^"NavigationRegion3D/WorldGeometry/Props",
	^"Gameplay/Actors",
	^"Gameplay/Encounters",
	^"Gameplay/Transitions",
	^"Gameplay/Objectives",
]
const EMPTY_BASE_CONTAINER_PATHS: Array[NodePath] = [
	^"Environment",
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
]

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_single_base_file()
	_check_base_scene()
	_check_all_playable_levels()
	_finish()


func _check_single_base_file() -> void:
	var base_scene_files: Array[String] = []
	for file_name: String in DirAccess.get_files_at(LEVEL_BASE_DIRECTORY):
		if file_name.get_extension() == "tscn":
			base_scene_files.append(file_name)
	base_scene_files.sort()
	_check(
		base_scene_files == ["level_base.tscn"],
		"level_bases should contain only level_base.tscn; found %s."
		% [base_scene_files]
	)


func _check_base_scene() -> void:
	var packed := load(LEVEL_BASE_PATH) as PackedScene
	_check(packed != null, "The canonical level base should load.")
	if packed == null:
		return
	var world := packed.instantiate() as PFRWorldLevel
	_check(world != null, "The canonical level base root should be PFRWorldLevel.")
	if world == null:
		return
	_check(world.name == &"PFRWorldLevel", "The canonical base root name should remain PFRWorldLevel.")
	_check(world.get_node_or_null(^"Runtime") == null, "The canonical base should not contain Runtime.")
	for required_path: NodePath in REQUIRED_LEVEL_PATHS:
		_check(
			world.get_node_or_null(required_path) != null,
			"The canonical base is missing %s." % required_path
		)
	for described_path: NodePath in DESCRIBED_CONTAINER_PATHS:
		var container := world.get_node_or_null(described_path)
		_check(
			container != null and not container.editor_description.strip_edges().is_empty(),
			"The designer container %s should explain its purpose." % described_path
		)
	for empty_path: NodePath in EMPTY_BASE_CONTAINER_PATHS:
		var container := world.get_node_or_null(empty_path)
		_check(
			container != null and container.get_child_count() == 0,
			"The canonical base container %s should have no level-specific content."
			% empty_path
		)

	var player := world.get_player()
	var camera := world.get_node_or_null(^"Player/Camera3D") as PlayerCamera
	var game_ui := world.get_node_or_null(^"Player/GameUI") as CanvasLayer
	_check(
		player != null
			and player.get_parent() == world
			and player.scene_file_path == PLAYER_SCENE_PATH,
		"The base should instance player.tscn directly as its top-level Player."
	)
	_check(
		camera != null
			and camera.get_parent() == player
			and camera.current
			and camera.target_path == NodePath(".."),
		"The complete Player should own its current parent-targeted Camera3D."
	)
	_check(
		game_ui != null and game_ui.get_parent() == player,
		"The complete Player should own GameUI."
	)

	var grid := world.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid"
	) as GridMap
	_check(grid != null, "The canonical base should provide ModularGroundGrid.")
	if grid != null:
		_check(grid.get_used_cells().is_empty(), "The base ModularGroundGrid should have no painted cells.")
		_check(
			grid.transform.is_equal_approx(
				Transform3D(Basis.from_scale(Vector3(2.0, 2.0, 2.0)), Vector3.ZERO)
			),
			"The base ModularGroundGrid should use scale (2, 2, 2) at the origin."
		)
		_check(
			grid.cell_size.is_equal_approx(Vector3(2.0, 0.25, 2.0))
				and not grid.cell_center_y,
			"The base ModularGroundGrid should retain the canonical cell settings."
		)
		_check(
			grid.mesh_library != null
				and grid.mesh_library.resource_path == GROUND_LIBRARY_PATH,
			"The base ModularGroundGrid should use the New Bouffalant City MeshLibrary."
		)
	world.free()


func _check_all_playable_levels() -> void:
	var level_paths := CITY_LEVEL_PATHS.duplicate()
	var catalog := load(STANDALONE_CATALOG_PATH) as StandaloneAreaCatalog
	_check(catalog != null, "The standalone-area catalog should load for level-base verification.")
	if catalog != null:
		for area: StandaloneAreaDefinition in catalog.areas:
			if area != null and area.destination != null:
				level_paths.append(area.destination.resource_path)
	var unique_paths := {}
	for scene_path: String in level_paths:
		unique_paths[scene_path] = true
	_check(
		level_paths.size() == 61 and unique_paths.size() == 61,
		"The canonical-base check should cover exactly 61 unique playable levels."
	)

	for scene_path: String in level_paths:
		_check_playable_level(scene_path)


func _check_playable_level(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "Playable level should load: %s." % scene_path)
	if packed == null:
		return
	var inherited_base := packed.get_state().get_node_instance(0)
	_check(
		inherited_base != null and inherited_base.resource_path == LEVEL_BASE_PATH,
		"Playable level should inherit level_base.tscn directly: %s." % scene_path
	)
	var world := packed.instantiate() as PFRWorldLevel
	_check(world != null, "Playable level should instantiate as PFRWorldLevel: %s." % scene_path)
	if world == null:
		return
	_check(world.get_node_or_null(^"Runtime") == null, "Playable level should not contain Runtime: %s." % scene_path)
	for required_path: NodePath in REQUIRED_LEVEL_PATHS:
		_check(
			world.get_node_or_null(required_path) != null,
			"Playable level %s is missing %s." % [scene_path, required_path]
		)

	var counts := {
		"players": 0,
		"cameras": 0,
		"game_uis": 0,
	}
	_count_playable_nodes(world, counts)
	var player := world.get_node_or_null(^"Player") as PlayerCharacter
	var camera := world.get_node_or_null(^"Player/Camera3D") as Camera3D
	_check(
		counts.players == 1 and world.get_player() == player,
		"Playable level should have exactly one direct PlayerCharacter: %s." % scene_path
	)
	_check(
		counts.cameras == 1 and camera != null and camera.current,
		"Playable level should have exactly one current Camera3D: %s." % scene_path
	)
	_check(
		counts.game_uis == 1,
		"Playable level should have exactly one GameUI: %s." % scene_path
	)

	if scene_path == CITY_PATH:
		_check(
			player != null
				and player.position.is_equal_approx(Vector3(2.0512445, 0.0, 0.0)),
			"New Bouffalant City should preserve its authored Player transform override."
		)
		var grid := world.get_node_or_null(
			^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid"
		) as GridMap
		_check(
			grid != null
				and grid.transform.is_equal_approx(
					Transform3D(
						Basis.from_scale(Vector3(2.0, 2.0, 2.0)),
						Vector3(3.0, 0.0, -1.0)
					)
				)
				and grid.get_used_cells().size() == 291,
			"New Bouffalant City should preserve its 291-cell inherited grid override at (3, 0, -1)."
		)
	elif scene_path == ROUTE_ZERO_PATH:
		_check(
			player != null
				and player.position.is_equal_approx(Vector3.ZERO),
			"Route 0 should preserve its authored Player transform override."
		)
	world.free()


func _count_playable_nodes(node: Node, counts: Dictionary) -> void:
	if node is PlayerCharacter:
		counts.players = int(counts.players) + 1
	if node is Camera3D:
		counts.cameras = int(counts.cameras) + 1
	if node.name == &"GameUI" and node is CanvasLayer:
		counts.game_uis = int(counts.game_uis) + 1
	for child: Node in node.get_children():
		_count_playable_nodes(child, counts)


func _finish() -> void:
	if _failures.is_empty():
		print(
			"Level base smoke test passed: level_base.tscn is the sole base, its "
			+ "grid is empty, all 61 playable levels inherit it directly with one "
			+ "Player/camera/GameUI and no Runtime, and the city retains 291 cells."
		)
		get_tree().quit(0)
		return
	for failure: String in _failures:
		push_error("Level base smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
