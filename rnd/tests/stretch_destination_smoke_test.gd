extends Node

const DestinationScene := preload("res://rnd/stretch/worlds/stretch_destination.tscn")
const MIARE_STATION_PATH := (
	"res://art/environments/new_bouffalant_city/city_interiors/"
	+ "miare_station_concourse.tscn"
)
const TRAINER_SCENE_PATHS: Array[String] = [
	"res://overworld/trainer_lake/TrainerKyle.tscn",
	"res://overworld/trainer_lake/TrainerBackpacker.tscn",
	"res://overworld/trainer_lake/TrainerBusinessman.tscn",
	"res://overworld/trainer_lake/TrainerDeliveryWorker.tscn",
	"res://overworld/trainer_lake/TrainerJogger.tscn",
	"res://overworld/trainer_lake/TrainerPoliceOfficer.tscn",
	"res://overworld/trainer_lake/TrainerTourist.tscn",
]

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_stretch := StretchGoalSystem.get_save_data()
	_check_stretchman_hub_contract()
	_check_trainer_resource_isolation()
	_check_release_export_pre_spawn_repair()

	StretchGoalSystem.begin_destination("champion", 1)
	var world := await _build_world()
	_check(_count_stretch_trainers(world) == 5, "A fresh champion room should place Elite Four 1–4 and the Champion in sequence.")
	var champion_positions := _trainer_z_positions(world)
	_check(champion_positions.size() == 5, "Every champion opponent should have an authored corridor position.")
	for position_index in range(1, champion_positions.size()):
		_check(champion_positions[position_index] < champion_positions[position_index - 1], "Champion opponents should be ordered deeper into the room.")

	var first_encounter := StretchGoalSystem.get_active_encounters()[0]
	StretchGoalSystem._apply_battle_result(
		first_encounter,
		{"winner": "player", "reason": "all_pokemon_fainted"}
	)
	world.free()
	world = await _build_world()
	_check(_count_stretch_trainers(world) == 4, "A defeated Elite Four member should stay removed when the room reloads after battle.")
	world.free()

	_check(
		_load_route_unlock_fixture(4)
		and not StretchGoalSystem.begin_destination("route", 4).is_empty(),
		"A contiguous Route 0–3 clear should make Route 4 available."
	)
	world = await _build_world()
	_check(world.get_node_or_null(^"DirtPath") != null, "A selected route should build outdoor route geometry.")
	_check(world.get_node_or_null(^"NavigationRegion3D") != null, "R&D routes should provide navigation for the existing trainer approach behavior.")
	_check(_count_stretch_trainers(world) == 4, "Route 4's level band should place four mandatory trainers.")
	var route_path := world.get_node_or_null(^"DirtPath") as Node3D
	var route_walls := world.get_node_or_null(^"RouteWalls") as Node3D
	var route_points := world.get_meta("route_path_points", []) as Array
	_check(
		route_path != null
		and route_path.get_child_count() >= 7
		and _route_x_span(route_points) >= 4.0,
		"Generated routes should visibly twist through multiple path segments instead of forming a straight corridor."
	)
	_check(
		route_walls != null
		and route_walls.find_children("RouteWall*", "StaticBody3D", false, false).size()
		== route_path.get_child_count() * 2,
		"Both sides of every winding path segment should have continuous collision walls."
	)
	var grass_fields := world.get_node_or_null(^"TallGrassFields") as Node3D
	_check(
		grass_fields != null
		and grass_fields.get_child_count()
		== int(StretchGoalSystem.get_active_destination().get("grass_fields", 0)),
		"A generated route should place every configured real tall-grass encounter field."
	)
	if grass_fields != null:
		for field: Node in grass_fields.get_children():
			_check(
				field is TallGrassEncounterZone
				and not String((field as TallGrassEncounterZone).encounter_id).is_empty(),
				"Every generated grass patch should use the shared encounter zone with a route-specific wild encounter."
			)
	_check(
		world.get_node_or_null(^"RouteCompletionGate") is RNDRouteCompletionGate,
		"Every generated dungeon should end at a physical route-completion gate."
	)
	_check(
		world.find_children("TrainerGate*", "StaticBody3D", false, false).size() == 8,
		"Each route trainer should have a two-sided geometry choke that crosses the existing sight ray."
	)
	var first_route_gate := world.get_node_or_null(^"TrainerGate1LCollision") as StaticBody3D
	var authored_route_trainers := _stretch_trainers(world)
	var first_route_direction: Vector3 = world.call("_trainer_direction", 0)
	_check(
		first_route_gate != null
		and not authored_route_trainers.is_empty()
		and is_equal_approx(
			(first_route_gate.position - authored_route_trainers[0].position).dot(
				first_route_direction
			),
			-0.65
		),
		"Each route choke should sit immediately before its trainer across the local winding path."
	)
	for trainer in _stretch_trainers(world):
		var behavior := trainer.npc_behavior as TrainerBehavior
		_check(behavior != null and behavior.automatic_sight_encounter, "Route trainers should use automatic sight encounters.")
		_check(
			behavior != null and behavior.is_highly_aggro(),
			"Stretchman destination trainers should use Highly Aggro mode."
		)
		_check(
			String((trainer.get_script() as Script).resource_path) == "res://core/PFRCharacter.gd",
			"R&D opponents should reuse the existing PFRCharacter trainer scenes."
		)
		_check(
			String((behavior.get_script() as Script).resource_path) == "res://core/TrainerBehavior.gd",
			"R&D opponents must use the existing TrainerBehavior without an R&D subclass."
		)
		_check(
			is_equal_approx(behavior.stopping_buffer, 0.15),
			"R&D opponents should retain the normal trainer approach distance."
		)
	var route_trainers := _stretch_trainers(world)
	var route_player := world.get_node_or_null(^"Player") as PlayerCharacter
	if route_player != null and not route_trainers.is_empty():
		var first_route_trainer := route_trainers[0]
		var first_route_behavior := (
			first_route_trainer.npc_behavior as TrainerBehavior
		)
		var trainer_forward := _trainer_forward(first_route_trainer)
		route_player.global_position = first_route_trainer.global_position + trainer_forward * 6.0
		for _frame in 12:
			await get_tree().physics_frame
			if (
				first_route_behavior._approach_state
				!= TrainerBehavior.ApproachState.WAITING
			):
				break
		_check(
			first_route_behavior._approach_state
			!= TrainerBehavior.ApproachState.WAITING,
			"A generated route trainer should notice a player entering its sight line."
		)
	else:
		_check(false, "The route interaction fixture should contain a player and trainer.")
	GameInstance.set_player_movement_enabled(true)
	world.free()

	# Re-entering the same generated scene must provide a fresh Highly Aggro
	# behavior. It also deliberately ignores the session-level consumption used
	# to silence standard prototype trainers after their first forced battle.
	var repeated_route_encounter_id := String(
		StretchGoalSystem.get_active_encounters()[0].get("encounter_id", "")
	)
	GameInstance.mark_standard_trainer_sight_encounter_consumed(
		repeated_route_encounter_id
	)
	world = await _build_world()
	route_trainers = _stretch_trainers(world)
	route_player = world.get_node_or_null(^"Player") as PlayerCharacter
	if route_player != null and not route_trainers.is_empty():
		var repeated_route_trainer := route_trainers[0]
		var repeated_route_behavior := (
			repeated_route_trainer.npc_behavior as TrainerBehavior
		)
		var repeated_forward := _trainer_forward(repeated_route_trainer)
		route_player.global_position = repeated_route_trainer.global_position + repeated_forward * 6.0
		for _frame in 12:
			await get_tree().physics_frame
			if (
				repeated_route_behavior._approach_state
				!= TrainerBehavior.ApproachState.WAITING
			):
				break
		_check(
			repeated_route_behavior._approach_state
			!= TrainerBehavior.ApproachState.WAITING,
			"A Highly Aggro trainer should force sight again after scene re-entry."
		)
	else:
		_check(false, "The re-entered route fixture should contain a player and trainer.")
	GameInstance.set_player_movement_enabled(true)
	world.free()

	_check(
		_load_route_unlock_fixture(39)
		and not StretchGoalSystem.begin_destination("route", 39).is_empty(),
		"A contiguous Route 0–38 clear should make the final route available."
	)
	world = await _build_world()
	var final_path := world.get_node_or_null(^"DirtPath") as Node3D
	var final_grass := world.get_node_or_null(^"TallGrassFields") as Node3D
	_check(
		int(world.get_meta("route_index", -1)) == 39
		and float(world.get_meta("route_world_length", 0.0)) >= 190.0
		and final_path != null
		and final_path.get_child_count() >= 17,
		"Route 39 should build as a substantially larger final dungeon."
	)
	_check(
		_count_stretch_trainers(world) == 8
		and world.find_children("TrainerGate*", "StaticBody3D", false, false).size() == 16,
		"The final route should enforce all eight scaled trainer checkpoints."
	)
	_check(
		final_grass != null and final_grass.get_child_count() == 9,
		"The final route should contain its full scaled set of nine tall-grass fields."
	)
	_check(
		world.get_node_or_null(^"BiomeDecorations") != null
		and world.get_node_or_null(^"RouteCompletionGate") is RNDRouteCompletionGate,
		"The final biome should retain themed decoration and a physical far-end goal."
	)
	world.free()

	StretchGoalSystem.begin_destination("gym", 8)
	world = await _build_world()
	_check(world.get_node_or_null(^"ArenaRing") != null, "A selected gym should build an indoor arena.")
	_check(_count_stretch_trainers(world) == 1, "A gym destination should place exactly its selected leader.")
	var gym_player := world.get_node_or_null(^"Player") as PlayerCharacter
	var gym_leader := _stretch_trainers(world)[0] if not _stretch_trainers(world).is_empty() else null
	var gym_detector := (
		gym_player.get_node_or_null(^"LookInteraction") as RNDPlayerInteractionDetector
		if gym_player != null
		else null
	)
	var gym_ui := world.get_node_or_null(^"GameUI")
	var gym_button := (
		gym_ui.get_node_or_null(^"InteractionButton") as Button
		if gym_ui != null
		else null
	)
	if gym_player != null and gym_leader != null:
		var gym_behavior := gym_leader.npc_behavior as TrainerBehavior
		gym_behavior.automatic_sight_encounter = false
		gym_player.global_position = gym_leader.global_position + Vector3(0.0, 0.0, 2.0)
		var player_visual := gym_player.get_node_or_null(^"Visual") as Node3D
		if player_visual != null:
			player_visual.rotation.y = 0.0
		for _frame in 3:
			await get_tree().physics_frame
		_check(
			gym_detector != null and gym_detector.get_current_target() == gym_leader,
			"A generated gym leader should be selected by the shared interaction detector."
		)
		_check(
			gym_button != null and gym_button.visible and not gym_button.disabled,
			"Looking at a generated gym leader should show the interaction prompt."
		)
		if gym_ui != null:
			var interact_key := InputEventKey.new()
			interact_key.keycode = KEY_E
			interact_key.pressed = true
			gym_ui.call("_unhandled_input", interact_key)
			await get_tree().process_frame
		_check(
			gym_behavior._approach_state == TrainerBehavior.ApproachState.COMPLETE,
			"Pressing E should dispatch the generated gym leader interaction."
		)
		var dialog_template := _find_dialog_template()
		_check(
			dialog_template != null,
			"Interacting with a generated gym leader should open its challenge dialog."
		)
		if dialog_template != null:
			dialog_template.close()
			await get_tree().process_frame
	else:
		_check(false, "The gym interaction fixture should contain a player and leader.")
	_check(
		GameInstance.is_player_movement_enabled(),
		"Closing the generated leader dialog should restore player movement."
	)
	world.free()

	StretchGoalSystem.load_save_data(original_stretch)
	if _failures.is_empty():
		print(
			"Stretch destination smoke test passed: winding biome routes, real tall grass, "
			+ "mandatory trainer chokes, scaled Route 39 geometry, Highly Aggro re-entry, "
			+ "Gym 8 E interaction, champion progression, and Miare Station return verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Stretch destination smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check_stretchman_hub_contract() -> void:
	_check(
		RNDStretchDestination.STRETCHMAN_HUB_SCENE_PATH == MIARE_STATION_PATH,
		"Generated destinations should return to Miare Station."
	)
	var packed := load(MIARE_STATION_PATH) as PackedScene
	var hub := packed.instantiate() if packed != null else null
	_check(hub != null, "The Miare Station Stretchman hub should instantiate.")
	if hub == null:
		return
	_check(
		hub.get_node_or_null(^"Stretchman") is PFRCharacter,
		"Miare Station should contain Stretchman."
	)
	_check(
		hub.get_node_or_null(^"StretchmanReturnSpawn") is Marker3D,
		"Miare Station should contain the generated-destination return marker."
	)
	hub.free()


func _build_world() -> RNDStretchDestination:
	var world := DestinationScene.instantiate() as RNDStretchDestination
	add_child(world)
	for _frame in 3:
		await get_tree().process_frame
	return world


func _load_route_unlock_fixture(route_index: int) -> bool:
	var save := StretchGoalSystem.get_save_data()
	save["completed_routes"] = range(route_index)
	save["active_destination"] = {}
	save["run_defeated_ids"] = []
	return StretchGoalSystem.load_save_data(save)


func _route_x_span(points: Array) -> float:
	if points.is_empty():
		return 0.0
	var minimum_x := INF
	var maximum_x := -INF
	for point_value: Variant in points:
		if point_value is Vector3:
			minimum_x = minf(minimum_x, (point_value as Vector3).x)
			maximum_x = maxf(maximum_x, (point_value as Vector3).x)
	return maximum_x - minimum_x


func _trainer_forward(trainer: PFRCharacter) -> Vector3:
	var visual := trainer.get_node_or_null(^"Visual") as Node3D
	var facing_basis := visual.global_basis if visual != null else trainer.global_basis
	var forward := -facing_basis.z
	forward.y = 0.0
	return forward.normalized()


func _check_trainer_resource_isolation() -> void:
	for scene_path in TRAINER_SCENE_PATHS:
		var trainer_scene := load(scene_path) as PackedScene
		_check(trainer_scene != null, "The trainer template should load: %s" % scene_path)
		if trainer_scene == null:
			continue
		var completed_trainer := trainer_scene.instantiate() as PFRCharacter
		var completed_behavior := (
			completed_trainer.npc_behavior as TrainerBehavior
			if completed_trainer != null
			else null
		)
		_check(
			completed_behavior != null,
			"The trainer template should own a TrainerBehavior: %s" % scene_path
		)
		if completed_behavior == null:
			if completed_trainer != null:
				completed_trainer.free()
			continue
		completed_behavior._approach_state = TrainerBehavior.ApproachState.COMPLETE

		var fresh_trainer := trainer_scene.instantiate() as PFRCharacter
		var fresh_behavior := (
			fresh_trainer.npc_behavior as TrainerBehavior
			if fresh_trainer != null
			else null
		)
		_check(
			fresh_trainer != null
			and completed_trainer.controller != fresh_trainer.controller,
			"Each trainer instance should own a scene-local controller: %s" % scene_path
		)
		_check(
			fresh_behavior != null and completed_behavior != fresh_behavior,
			"Each trainer instance should own a scene-local behavior: %s" % scene_path
		)
		_check(
			fresh_behavior != null
			and fresh_behavior._approach_state == TrainerBehavior.ApproachState.WAITING,
			"A completed trainer must not disable later instances: %s" % scene_path
		)
		if completed_trainer != null:
			completed_trainer.free()
		if fresh_trainer != null:
			fresh_trainer.free()


func _check_release_export_pre_spawn_repair() -> void:
	var trainer_scene := load(TRAINER_SCENE_PATHS[0]) as PackedScene
	var trainer := trainer_scene.instantiate() as PFRCharacter if trainer_scene != null else null
	var destination := DestinationScene.instantiate() as RNDStretchDestination
	if trainer == null or destination == null:
		_check(false, "The release-export trainer repair fixture should instantiate.")
		if trainer != null:
			trainer.free()
		if destination != null:
			destination.free()
		return

	trainer.npc_behavior = null
	var configured: bool = bool(destination.call(
		"_configure_existing_trainer",
		trainer,
		{
			"encounter_id": "web-export-repair-test",
			"battle_scene_path": "res://rnd/stretch/battle/stretch_battle_scene.tscn",
			"display_name": "Export Repair Trainer",
		}
	))
	var repaired_behavior := trainer.npc_behavior as TrainerBehavior
	_check(
		configured
		and repaired_behavior != null
		and repaired_behavior.encounter_id == "web-export-repair-test"
		and repaired_behavior.is_highly_aggro(),
		"A generated destination should repair a release-exported null direct behavior before spawning."
	)
	trainer.free()
	destination.free()


func _find_dialog_template() -> UITemplate:
	for child: Node in UIManager.get_children():
		if child is UITemplate:
			return child as UITemplate
	return null


func _stretch_trainers(root: Node) -> Array[PFRCharacter]:
	var trainers: Array[PFRCharacter] = []
	for child: Node in root.get_children():
		if child is PFRCharacter and child.has_meta("stretch_encounter_id"):
			trainers.append(child as PFRCharacter)
	return trainers


func _count_stretch_trainers(root: Node) -> int:
	return _stretch_trainers(root).size()


func _trainer_z_positions(root: Node) -> Array[float]:
	var positions: Array[float] = []
	for trainer in _stretch_trainers(root):
		positions.append(trainer.position.z)
	return positions


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
