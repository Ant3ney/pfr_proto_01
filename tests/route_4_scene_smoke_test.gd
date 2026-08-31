extends Node

const ROUTE_SCENE := preload("res://overworld/route_4/route_4.tscn")
const WILD_BATTLE_SCENE_PATH := "res://battle/route_4_wild_battle_scene.tscn"
const WILD_ENCOUNTER_PATH := "res://battle/encounters/wild_fletchling_route_4_v1.tres"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var route := ROUTE_SCENE.instantiate() as Node3D
	_check(route != null, "Route 4 should instantiate as a 3D level.")
	if route == null:
		_finish()
		return
	add_child(route)
	await get_tree().process_frame

	var start := route.get_node_or_null(^"Route4Start") as Marker3D
	var player := route.get_node_or_null(^"Player") as PlayerCharacter
	_check(start != null, "Route 4 should expose its named start marker.")
	_check(player != null, "Route 4 should contain the playable character.")
	if start != null and player != null:
		_check(
			player.global_position.is_equal_approx(start.global_position),
			"The authored player spawn should match Route4Start."
		)

	var camera := route.get_node_or_null(^"Camera3D") as Camera3D
	var sun := route.get_node_or_null(^"Sun") as DirectionalLight3D
	var environment := route.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
	_check(camera != null and camera.current and camera.far >= 80.0, "The route should have a camera sized for its full depth.")
	_check(sun != null and sun.shadow_enabled, "The outdoor route should use one shadow-casting sun.")
	_check(environment != null and environment.environment != null, "The route should provide its bright outdoor environment.")

	var ground := route.get_node_or_null(^"GroundTiles") as Node3D
	_check(ground != null and ground.get_child_count() == 96, "Route 4 should use a complete 8 x 12 grid of 4 m ground modules.")
	var path_count := 0
	if ground != null:
		for tile: Node in ground.get_children():
			if String(tile.name).begins_with("Path_"):
				path_count += 1
			_check(tile is Node3D and (tile as Node3D).scale.is_equal_approx(Vector3.ONE), "Ground modules should remain at unit scale.")
		_check(path_count == 21, "The meadow should contain the authored 21-module winding dirt route.")

	var fields := route.get_node_or_null(^"TallGrassFields") as Node3D
	_check(fields != null and fields.get_child_count() == 5, "Route 4 should contain five readable tall-grass fields.")
	if fields != null:
		for field: Node in fields.get_children():
			_check(field is TallGrassEncounterZone, "Every tall-grass field should use the reusable rnd feature.")
			if field is TallGrassEncounterZone:
				var zone := field as TallGrassEncounterZone
				_check(zone.battle_scene_path == WILD_BATTLE_SCENE_PATH, "Every field should use the concrete Route 4 wild battle.")
				_check(zone.encounter_chance_per_check > 0.0, "Every field should have a non-zero encounter chance.")
				_check(zone.scale.is_equal_approx(Vector3.ONE), "Tall-grass patches should keep their art at unit scale.")

	var trees := route.get_node_or_null(^"Vegetation/Trees") as Node3D
	var bushes := route.get_node_or_null(^"Vegetation/Bushes") as Node3D
	var hedges := route.get_node_or_null(^"Vegetation/Hedges") as Node3D
	var plants := route.get_node_or_null(^"Vegetation/Plants") as Node3D
	_check(trees != null and trees.get_child_count() >= 20, "Route 4 should be framed by a substantial tree family.")
	_check(bushes != null and bushes.get_child_count() >= 16, "Route 4 should include varied bushes and shrubs.")
	_check(hedges != null and hedges.get_child_count() >= 5, "Route 4 should use hedges as readable vegetation borders.")
	_check(plants != null and plants.get_child_count() >= 20, "Route 4 should include sparse flower and plant clusters.")
	for family in [trees, bushes, hedges, plants]:
		if family == null:
			continue
		for decoration: Node in family.get_children():
			_check(
				decoration is Node3D and (decoration as Node3D).scale.is_equal_approx(Vector3.ONE),
				"Placed vegetation should retain the environment pack's calibrated unit scale."
			)

	var boundaries := route.get_node_or_null(^"TerrainBoundaries") as Node3D
	_check(boundaries != null and boundaries.get_child_count() == 4, "The playable meadow should have four unobtrusive edge colliders.")
	var exit_trigger := route.get_node_or_null(^"ExitToCity") as SceneTransferTrigger
	_check(exit_trigger != null, "The Route 4 entrance should allow a safe return to the modular city.")
	if exit_trigger != null:
		_check(exit_trigger.destination_scene_path == "res://demo/primary_development_enviroment.tscn", "The route exit should target the modular city.")
		_check(exit_trigger.destination_spawn_marker == &"Route4GatewayReturn", "The route exit should use the safe gateway return marker.")

	var encounter := load(WILD_ENCOUNTER_PATH) as Resource
	_check(encounter != null and encounter.has_method("validate"), "Route 4 should provide an authored battle encounter resource.")
	if encounter != null and encounter.has_method("validate"):
		_check(
			(encounter.call("validate") as PackedStringArray).is_empty(),
			"The Route 4 wild encounter should satisfy the battle data contract."
		)
	var battle_packed := load(WILD_BATTLE_SCENE_PATH) as PackedScene
	var battle_preview := battle_packed.instantiate() if battle_packed != null else null
	_check(battle_preview != null, "The concrete Route 4 wild battle scene should instantiate.")
	if battle_preview != null:
		var provider := battle_preview.get_node_or_null(^"EncounterProvider")
		var provided_encounter: Variant = provider.get("encounter") if provider != null else null
		_check(
			provided_encounter is Resource
			and String((provided_encounter as Resource).get("encounter_id"))
				== "wild-fletchling-route-4-v1",
			"The concrete battle provider should own the exact encounter requested by tall grass."
		)
		battle_preview.free()
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print(
			"Route 4 scene smoke test passed: modular terrain, winding path, lighting, start/exit, "
			+ "trees, bushes, plants, unit-scale vegetation, and five encounter fields verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Route 4 scene smoke test failed: %s" % failure)
	get_tree().quit(1)
