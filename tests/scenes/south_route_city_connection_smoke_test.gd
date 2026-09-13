extends Node


class ConnectionWatcher:
	extends Node

	const CITY := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
	const ROUTE := "res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"
	var failures: Array[String] = []


	func run() -> void:
		GameInstance.scene_transfer_finished.connect(_quiet_scene)
		_check(GameInstance.transfer_to_scene(CITY, &"Route0CityReturn"), "The city return marker should load.")
		if not await _wait(CITY):
			_finish()
			return
		var city := get_tree().current_scene as PFRWorldLevel
		var player := city.get_player()
		var exit := city.get_node("Gameplay/Transitions/SouthRoute0Exit") as RouteTravelTrigger
		var marker := exit.get_node("TransitionMarker") as MeshInstance3D
		var volume := exit.get_node("Volume") as CollisionShape3D
		_check(marker.visible, "The south exit should retain the visible red transition marker.")
		var footprint := marker.transform * marker.get_aabb()
		var size := (volume.shape as BoxShape3D).size
		_check(is_equal_approx(footprint.size.x, size.x) and is_equal_approx(footprint.size.z, size.z), "The red footprint should mark the actual contact volume.")
		var approach := city.get_node("NavigationRegion3D/WorldGeometry/Structures/SouthRouteApproach")
		_check(approach.find_children("*Sign", "", true, false).is_empty(), "The south approach should have no wooden signs.")
		_check(not exit.overlaps_body(player), "The return spawn should be safely before the red threshold.")
		await _check_walkable_path(city)
		# Walk onto the near edge of the photographed red shape using live physics.
		await _walk_to(Vector3(1.96, 0, 10))
		if not await _wait(ROUTE):
			_finish()
			return
		var route := get_tree().current_scene as PFRWorldLevel
		_check(ChallengeProgressionSystem.get_active_area_id() == "route_00", "The south alley should activate Route 0.")
		_check(route.get_player().global_position.distance_to(route.find_spawn_marker(&"Route0Start").global_position) < 0.2, "Arrival should use Route 0's safe start marker.")
		await _walk_to(route.get_node("Gameplay/Transitions/PreviousRouteExit").global_position)
		if not await _wait(CITY):
			_finish()
			return
		city = get_tree().current_scene as PFRWorldLevel
		player = city.get_player()
		_check(player.global_position.distance_to(city.find_spawn_marker(&"Route0CityReturn").global_position) < 0.2, "Route 0 should return to the photographed south alley.")
		_check(not city.get_node("Gameplay/Transitions/SouthRoute0Exit").overlaps_body(player), "The return trip must not immediately enter Route 0 again.")
		for _frame in 20:
			await get_tree().physics_frame
		_check(get_tree().current_scene == city and not GameInstance.is_scene_transfer_in_progress(), "The city arrival should stay stable after the return.")
		_finish()


	func _check_walkable_path(city: PFRWorldLevel) -> void:
		var shape := CapsuleShape3D.new()
		shape.radius = 0.32
		shape.height = 1.6
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.exclude = [city.get_player().get_rid()]
		var space := city.get_world_3d().direct_space_state
		for z in range(6, 31):
			var point := Vector3(1.96 if z < 19 else 1.0, 0, z)
			query.transform = Transform3D(Basis.IDENTITY, point + Vector3(0, 0.82, 0))
			_check(space.intersect_shape(query).is_empty(), "The south path should fit the player at z=%d." % z)
			var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP, point - Vector3.UP, 1, query.exclude)
			_check(not space.intersect_ray(ray).is_empty(), "The south path should have ground at z=%d." % z)
		var map := city.get_world_3d().navigation_map
		NavigationServer3D.map_force_update(map)
		for _frame in 6:
			await get_tree().physics_frame
		var target := Vector3(1, 0.5, 29)
		var path := NavigationServer3D.map_get_path(map, Vector3(1.96, 0.5, 7), target, true)
		_check(not path.is_empty() and path[-1].distance_to(target) < 0.25, "The south path navigation should connect to the city.")


	func _quiet_scene(_path: String, _marker: StringName, applied: bool) -> void:
		_check(applied, "The requested travel marker should apply.")
		var world := get_tree().current_scene as PFRWorldLevel
		world.get_node("Gameplay/Actors").process_mode = Node.PROCESS_MODE_DISABLED
		world.get_node("Gameplay/Encounters").process_mode = Node.PROCESS_MODE_DISABLED
		world.get_player().set_process(false)
		world.get_player().set_physics_process(false)
		GameInstance.set_player_movement_enabled(true)


	func _walk_to(target: Vector3) -> void:
		var player := (get_tree().current_scene as PFRWorldLevel).get_player()
		for _frame in 300:
			if not is_instance_valid(player) or GameInstance.is_scene_transfer_in_progress():
				return
			var offset := target - player.global_position
			offset.y = 0
			player.velocity = offset.normalized() * 4.5
			player.move_and_slide()
			await get_tree().physics_frame
		_check(false, "Walking through the visible threshold should transfer the player.")


	func _wait(path: String) -> bool:
		for _frame in 600:
			if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path and not GameInstance.is_scene_transfer_in_progress():
				await get_tree().physics_frame
				await get_tree().physics_frame
				return true
			await get_tree().process_frame
		_check(false, "Timed out waiting for " + path)
		return false


	func _finish() -> void:
		if failures.is_empty():
			print("South city connection passed: visible red threshold, clear ground/navigation, live Route 0 entry, safe return, and no arrival loop.")
			get_tree().quit(0)
			return
		for failure in failures:
			push_error(failure)
		get_tree().quit(1)


	func _check(value: bool, message: String) -> void:
		if not value:
			failures.append(message)


func _ready() -> void:
	var watcher := ConnectionWatcher.new()
	GameInstance.add_child(watcher)
	watcher.run.call_deferred()
