extends Node


class TransferWatcher:
	extends Node

	const CITY_PATH := "res://demo/primary_development_enviroment.tscn"
	const ROUTES := [
		{
			"trigger": "PokemonCenterSouthEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/pokemon_center_interior/pokemon_center_interior.tscn",
			"spawn": "EntrySpawn",
			"return": "PokemonCenterEntrance",
			"exit": "ExitToCity",
		},
		{
			"trigger": "PokemonCenterEastEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn",
			"spawn": "EntrySpawn",
			"return": "PokemonCenterEastEntrance",
			"exit": "ExitToCity",
		},
		{
			"trigger": "CityHallFrontEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/city_hall_interior.tscn",
			"spawn": "FrontEntrySpawn",
			"return": "CityHallFrontReturn",
			"exit": "ExitFront",
		},
		{
			"trigger": "CityHallRearEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/city_hall_interior.tscn",
			"spawn": "RearEntrySpawn",
			"return": "CityHallRearReturn",
			"exit": "ExitRear",
		},
		{
			"trigger": "CityHallSideEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/city_hall_interior.tscn",
			"spawn": "SideEntrySpawn",
			"return": "CityHallSideReturn",
			"exit": "ExitSide",
		},
		{
			"trigger": "MiareStationEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/miare_station_concourse.tscn",
			"spawn": "EntrySpawn",
			"return": "MiareStationReturn",
			"exit": "ExitToCity",
		},
		{
			"trigger": "GateBuildingFrontEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/gatehouse_interior.tscn",
			"spawn": "FrontEntrySpawn",
			"return": "GateBuildingFrontReturn",
			"exit": "ExitFront",
		},
		{
			"trigger": "WestTenantEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/west_tenant_lobby.tscn",
			"spawn": "EntrySpawn",
			"return": "WestTenantReturn",
			"exit": "ExitToCity",
		},
		{
			"trigger": "MuseumEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/museum_gallery.tscn",
			"spawn": "EntrySpawn",
			"return": "MuseumReturn",
			"exit": "ExitToCity",
		},
		{
			"trigger": "NorthTenantEntranceTrigger",
			"destination": "res://art/environments/new_bouffalant_city/city_interiors/north_tenant_lobby.tscn",
			"spawn": "EntrySpawn",
			"return": "NorthTenantReturn",
			"exit": "ExitToCity",
		},
	]
	const REMOVED_CITY_TRANSITIONS: Array[StringName] = [
		&"Route0Gateway",
		&"Route0GatewayReturn",
		&"Route4Gateway",
		&"Route4GatewayReturn",
		&"RougeTowerSouthReturn",
		&"RougeTowerNorthReturn",
		&"RougeTowerEastReturn",
		&"RougeTowerSouthEntranceTrigger",
		&"RougeTowerNorthEntranceTrigger",
		&"RougeTowerEastEntranceTrigger",
		&"GarageOfficeReturn",
		&"GarageBayReturn",
		&"GarageSideReturn",
		&"GarageOfficeEntranceTrigger",
		&"GarageBayEntranceTrigger",
		&"GarageSideEntranceTrigger",
		&"GateBuildingRearReturn",
		&"GateBuildingRearEntranceTrigger",
	]
	const RED_CITY_BARRIERS: Array[StringName] = [
		&"MeshInstance3D",
		&"MeshInstance3D2",
		&"MeshInstance3D3",
		&"MeshInstance3D4",
	]

	var failures: Array[String] = []
	var transfer_failures: Array[String] = []


	func run() -> void:
		GameInstance.scene_transfer_failed.connect(_on_transfer_failed)
		_check(
			GameInstance.transfer_to_scene(CITY_PATH, &"MiareStationReturn"),
			"The modular city and photographed station return marker should load."
		)
		await _wait_for_scene(CITY_PATH)

		var city := get_tree().current_scene
		_check(city != null and city.scene_file_path == CITY_PATH, "The modular city should be current.")
		if city == null or city.scene_file_path != CITY_PATH:
			_finish()
			return
		_validate_red_city_barriers(city)
		_check(ROUTES.size() == 10, "The city should retain exactly ten authored building transitions.")
		for removed_name in REMOVED_CITY_TRANSITIONS:
			_check(
				city.get_node_or_null(NodePath(String(removed_name))) == null,
				"Removed city transition %s should stay absent." % removed_name
			)

		var player := _find_player_character(city)
		_check(player != null, "The modular city should contain a PlayerCharacter.")
		if player == null:
			_finish()
			return
		player.set_process(false)
		player.set_physics_process(false)

		var triggers: Array[SceneTransferTrigger] = []
		for route: Dictionary in ROUTES:
			var trigger := city.get_node_or_null(NodePath(route.trigger)) as SceneTransferTrigger
			_check(trigger != null, "Exterior route '%s' is missing its SceneTransferTrigger." % route.trigger)
			if trigger == null:
				continue
			trigger.enabled = false
			triggers.append(trigger)
			_validate_route_configuration(city, trigger, route)

		await get_tree().physics_frame
		for route: Dictionary in ROUTES:
			var trigger := city.get_node_or_null(NodePath(route.trigger)) as SceneTransferTrigger
			if trigger == null:
				continue
			if not String(route.trigger).begins_with("PokemonCenter"):
				var return_marker := city.get_node_or_null(NodePath(String(route.return))) as Marker3D
				if return_marker != null:
					await _validate_compact_threshold(player, trigger, return_marker)
			await _validate_live_approach(player, trigger)

		var station_trigger := city.get_node_or_null(^"MiareStationEntranceTrigger") as SceneTransferTrigger
		_check(station_trigger != null, "The photographed station door should have a live trigger.")
		if station_trigger != null:
			await _exercise_photographed_station_route(city, player, station_trigger)

		_check(transfer_failures.is_empty(), "No configured modular-city transfer should fail.")
		_finish()


	func _validate_red_city_barriers(city: Node) -> void:
		for barrier_name in RED_CITY_BARRIERS:
			var barrier := city.get_node_or_null(NodePath(String(barrier_name))) as MeshInstance3D
			_check(
				barrier != null,
				"The primary development environment should retain red mesh %s at runtime."
				% barrier_name
			)
			if barrier == null:
				continue
			_check(barrier.visible, "Red mesh %s should be visible." % barrier_name)
			var box_mesh := barrier.mesh as BoxMesh
			_check(box_mesh != null, "Red mesh %s should retain its box geometry." % barrier_name)
			if box_mesh == null:
				continue
			var material := box_mesh.material as StandardMaterial3D
			_check(material != null, "Red mesh %s should retain its authored material." % barrier_name)
			if material != null:
				_check(
					material.albedo_color.is_equal_approx(Color(1, 0.2901961, 0, 1)),
					"Red mesh %s should retain its red-orange color." % barrier_name
				)


	func _validate_route_configuration(
		city: Node,
		trigger: SceneTransferTrigger,
		route: Dictionary
	) -> void:
		var destination_path := String(route.destination)
		var spawn_name := StringName(route.spawn)
		var return_name := StringName(route.return)
		_check(
			trigger.destination_scene_path == destination_path,
			"%s should target %s." % [route.trigger, destination_path]
		)
		_check(
			trigger.destination_spawn_marker == spawn_name,
			"%s should target spawn marker %s." % [route.trigger, spawn_name]
		)
		_check(
			ResourceLoader.exists(destination_path, "PackedScene"),
			"%s should reference an importable PackedScene." % route.trigger
		)

		var return_marker := city.get_node_or_null(NodePath(String(return_name))) as Marker3D
		_check(return_marker != null, "%s is missing safe exterior marker %s." % [route.trigger, return_name])
		if return_marker != null:
			_check(
				not _point_is_inside_trigger(trigger, return_marker.global_position + Vector3(0, 0.8, 0)),
				"%s return marker must sit outside its exterior trigger." % route.trigger
			)

		if not ResourceLoader.exists(destination_path, "PackedScene"):
			return
		var packed := load(destination_path) as PackedScene
		var destination := packed.instantiate() if packed != null else null
		_check(destination != null, "%s destination should instantiate." % route.trigger)
		if destination == null:
			return
		var spawn := _find_node_by_name(destination, spawn_name) as Marker3D
		var exit_trigger := _find_node_by_name(destination, StringName(route.exit)) as SceneTransferTrigger
		_check(spawn != null, "%s destination is missing spawn %s." % [route.trigger, spawn_name])
		_check(exit_trigger != null, "%s destination is missing exit %s." % [route.trigger, route.exit])
		_check(_find_player_character(destination) != null, "%s destination needs a PlayerCharacter." % route.trigger)
		if exit_trigger != null:
			_check(exit_trigger.destination_scene_path == CITY_PATH, "%s interior exit should target the city." % route.trigger)
			_check(
				exit_trigger.destination_spawn_marker == return_name,
				"%s interior exit should use return marker %s." % [route.trigger, return_name]
			)
		destination.free()


	func _validate_live_approach(
		player: PlayerCharacter,
		trigger: SceneTransferTrigger
	) -> void:
		var approach := trigger.get_meta("approach_position", Vector3.INF) as Vector3
		_check(approach != Vector3.INF, "%s needs an authored sidewalk approach point." % trigger.name)
		if approach == Vector3.INF:
			return
		_check(
			_point_is_inside_trigger(trigger, approach + Vector3(0, 0.8, 0)),
			"%s should reach over its authored walkable approach point." % trigger.name
		)
		var static_blocker := _static_blocker_at_approach(player, approach)
		_check(
			static_blocker.is_empty(),
			"%s approach point should remain outside imported solid collision (hit %s)."
			% [trigger.name, static_blocker]
		)

		player.global_position = Vector3(0, 0, 38)
		await get_tree().physics_frame
		player.global_position = approach
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(
			trigger.overlaps_body(player),
			"%s should physically overlap the PlayerCharacter before the facade stops movement." % trigger.name
		)


	func _validate_compact_threshold(
		player: PlayerCharacter,
		trigger: SceneTransferTrigger,
		return_marker: Marker3D
	) -> void:
		var collision_shape := trigger.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		_check(collision_shape != null, "%s needs a collision shape." % trigger.name)
		if collision_shape == null or not collision_shape.shape is BoxShape3D:
			return
		var box := collision_shape.shape as BoxShape3D
		var threshold_depth := collision_shape.global_transform.basis.z.length() * box.size.z
		_check(
			threshold_depth <= 0.4,
			"%s should use a narrow doorway threshold, not a broad approach volume (%.2f m deep)."
			% [trigger.name, threshold_depth]
		)

		var outward := return_marker.global_position - trigger.global_position
		outward.y = 0.0
		_check(not outward.is_zero_approx(), "%s needs an exterior-facing return direction." % trigger.name)
		if outward.is_zero_approx():
			return
		var nearby_position := trigger.global_position + outward.normalized() * 0.9
		player.global_position = Vector3(0, 0, 38)
		await get_tree().physics_frame
		player.global_position = nearby_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(
			not trigger.overlaps_body(player),
			"%s should not activate while the player is merely near the entrance." % trigger.name
		)


	func _static_blocker_at_approach(player: PlayerCharacter, approach: Vector3) -> String:
		var probe := SphereShape3D.new()
		probe.radius = 0.24
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = probe
		query.transform = Transform3D(Basis.IDENTITY, approach + Vector3(0, 0.86, 0))
		query.collision_mask = 1
		query.collide_with_areas = false
		query.collide_with_bodies = true
		query.exclude = [player.get_rid()]
		for hit: Dictionary in player.get_world_3d().direct_space_state.intersect_shape(query, 32):
			var collider := hit.get("collider") as Node
			if collider is StaticBody3D:
				return String(collider.get_path())
		return ""


	func _point_is_inside_trigger(trigger: SceneTransferTrigger, point: Vector3) -> bool:
		var collision_shape := trigger.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		if collision_shape == null or not collision_shape.shape is BoxShape3D:
			return false
		var local_point := collision_shape.global_transform.affine_inverse() * point
		var half_size := (collision_shape.shape as BoxShape3D).size * 0.5
		return (
			absf(local_point.x) <= half_size.x
			and absf(local_point.y) <= half_size.y
			and absf(local_point.z) <= half_size.z
		)


	func _exercise_photographed_station_route(
		city: Node,
		player: PlayerCharacter,
		station_trigger: SceneTransferTrigger
	) -> void:
		const STATION_PATH := "res://art/environments/new_bouffalant_city/city_interiors/miare_station_concourse.tscn"
		player.global_position = Vector3(9, 0, -16.4)
		await get_tree().physics_frame
		await get_tree().physics_frame
		station_trigger.enabled = true
		player.global_position = station_trigger.get_meta("approach_position") as Vector3
		await _wait_for_scene(STATION_PATH)

		var station := get_tree().current_scene
		_check(
			station != null and station.scene_file_path == STATION_PATH,
			"Walking into the photographed Miare Station doors should load the concourse."
		)
		if station == null or station.scene_file_path != STATION_PATH:
			return
		var station_player := _find_player_character(station)
		var entry_spawn := _find_node_by_name(station, &"EntrySpawn") as Marker3D
		_check(station_player != null and entry_spawn != null, "The station concourse should contain its player and EntrySpawn.")
		if station_player != null and entry_spawn != null:
			_check(
				station_player.global_transform.is_equal_approx(entry_spawn.global_transform),
				"The station doors should place the player at the concourse entrance."
			)
		var exit_trigger := _find_node_by_name(station, &"ExitToCity") as SceneTransferTrigger
		_check(exit_trigger != null, "The station concourse should have an exit back to the city.")
		var stretchman := _find_node_by_name(station, &"Stretchman") as PFRCharacter
		var stretchman_return := _find_node_by_name(
			station,
			&"StretchmanReturnSpawn"
		) as Marker3D
		_check(
			stretchman != null
			and stretchman.controller != null
			and stretchman.controller.npc_behavior is RNDStretchmanBehavior,
			"Miare Station should contain the interactive Stretchman hub NPC."
		)
		_check(
			stretchman_return != null,
			"Miare Station should own Stretchman's generated-destination return marker."
		)
		if exit_trigger == null or station_player == null:
			return
		exit_trigger.body_entered.emit(station_player)
		await _wait_for_scene(CITY_PATH)
		for _frame in 3:
			await get_tree().physics_frame
		city = get_tree().current_scene
		_check(city != null and city.scene_file_path == CITY_PATH, "The station exit should return to the city without looping.")
		if city == null or city.scene_file_path != CITY_PATH:
			return
		var returned_player := _find_player_character(city)
		var return_marker := city.get_node_or_null(^"MiareStationReturn") as Marker3D
		_check(returned_player != null and return_marker != null, "Station return should find the exterior player and marker.")
		if returned_player != null and return_marker != null:
			_check(
				returned_player.global_transform.is_equal_approx(return_marker.global_transform),
				"The station exit should place the player safely beyond the exterior trigger."
			)


	func _wait_for_scene(scene_path: String) -> void:
		for _frame in 300:
			if (
				get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == scene_path
				and not GameInstance.is_scene_transfer_in_progress()
			):
				return
			await get_tree().process_frame


	func _find_node_by_name(root: Node, target_name: StringName) -> Node:
		if root.name == target_name:
			return root
		for child: Node in root.get_children():
			var match := _find_node_by_name(child, target_name)
			if match != null:
				return match
		return null


	func _find_player_character(root: Node) -> PlayerCharacter:
		if root is PlayerCharacter:
			return root as PlayerCharacter
		for child: Node in root.get_children():
			var player := _find_player_character(child)
			if player != null:
				return player
		return null


	func _on_transfer_failed(message: String) -> void:
		transfer_failures.append(message)


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


	func _finish() -> void:
		if failures.is_empty():
			print(
				"Modular city scene transfer smoke test passed: all 10 retained exterior openings have valid "
				+ "destinations and safe returns, all 8 non-Pokemon-Center triggers are compact "
				+ "threshold strips that ignore nearby players while retaining live collision-free contact, "
				+ "all four red city meshes remain visible, removed transitions stay absent, and Miare Station "
				+ "contains Stretchman."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("Modular city scene transfer smoke test failed: %s" % failure)
		get_tree().quit(1)


func _ready() -> void:
	var watcher := TransferWatcher.new()
	watcher.name = "ModularCityTransferTestWatcher"
	GameInstance.add_child(watcher)
	watcher.run()
