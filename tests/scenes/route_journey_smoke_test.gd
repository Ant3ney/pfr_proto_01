extends Node

class JourneyWatcher:
	extends Node
	const CITY := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
	var failures: Array[String] = []

	func run() -> void:
		ChallengeProgressionSystem.reset_progress()
		GameInstance.scene_transfer_finished.connect(_quiet_scene)
		_check(GameInstance.transfer_to_scene(CITY, &"Route0CityReturn"), "The southeast city return marker should load.")
		await _wait(CITY)
		await _walk("SoutheastRoute0Exit", Vector3(-3, 0, 0))
		await _wait(_route(0))
		_check(ChallengeProgressionSystem.get_active_area_id() == "route_00", "Walking from the city must activate Route 0.")
		await _walk("NextRouteExit", Vector3(0, 0, 3))
		await _wait(_route(1))
		_check(ChallengeProgressionSystem.is_route_completed(0), "Walking onward must complete Route 0.")
		ChallengeProgressionSystem.record_encounter_victory("route-01-trainer-01")
		await _walk("PreviousRouteExit", Vector3(0, 0, -3))
		await _wait(_route(0))
		_check_arrival(&"FromNextRoute")
		await _walk("NextRouteExit", Vector3(0, 0, 3))
		await _wait(_route(1))
		_check(ChallengeProgressionSystem.is_encounter_defeated("route-01-trainer-01"), "Backtracking must preserve victories within a journey.")
		await _walk("NextRouteExit", Vector3(0, 0, 3))
		_check(get_tree().current_scene.scene_file_path == _route(1), "An unfinished route must refuse onward travel.")
		_check(not ChallengeProgressionSystem.is_route_unlocked(2), "The sealed exit must not unlock Route 2.")
		var world := get_tree().current_scene as PFRWorldLevel
		world.get_player().global_position = world.find_spawn_marker(&"EntrySpawn").global_position
		await get_tree().physics_frame
		await get_tree().physics_frame
		for index in range(1, 41):
			var area := ChallengeProgressionSystem.get_area("route_%02d" % index)
			for encounter in area.battle_encounters:
				ChallengeProgressionSystem.record_encounter_victory(encounter.encounter_id)
			_check(ChallengeProgressionSystem.are_route_trainers_defeated(index), "Route %d wins must count toward its checkpoint." % index)
			await _walk("NextRouteExit", Vector3(0, 0, 3))
			await _wait(CITY if index == 40 else _route(index + 1))
			_check(ChallengeProgressionSystem.is_route_completed(index), "Route %d should complete through its physical exit." % index)
			print("JOURNEY route_", index, " completed")
		_check_arrival(&"Route0CityReturn")
		var saved := ChallengeProgressionSystem.get_save_data()
		_check(ChallengeProgressionSystem.validate_save_data(saved).is_empty(), "The full journey must validate for saving.")
		ChallengeProgressionSystem.reset_progress()
		_check(ChallengeProgressionSystem.load_save_data(saved), "All 41 completed routes must reload.")
		_check(ChallengeProgressionSystem.is_route_completed(40), "Route 40 completion must survive save/reload.")
		# Return from Route 0's south mouth to the actual southeast city entrance.
		await _walk("SoutheastRoute0Exit", Vector3(-3, 0, 0))
		await _wait(_route(0))
		await _walk("PreviousRouteExit", Vector3(0, 0, -3))
		await _wait(CITY)
		_check_arrival(&"Route0CityReturn")
		if failures.is_empty():
			print("Route journey passed: physical city connection, all 41 onward exits, backtracking, trainer gates, safe arrivals and save/reload.")
			get_tree().quit(0)
		else:
			for failure in failures:
				push_error(failure)
			get_tree().quit(1)

	func _quiet_scene(_path: String, _marker: StringName, applied: bool) -> void:
		_check(applied, "Travel must apply the requested spawn marker.")
		var world := get_tree().current_scene as PFRWorldLevel
		world.get_node("Gameplay/Actors").process_mode = Node.PROCESS_MODE_DISABLED
		world.get_node("Gameplay/Encounters").process_mode = Node.PROCESS_MODE_DISABLED
		world.get_player().set_process(false)
		world.get_player().set_physics_process(false)

	func _walk(exit_name: String, approach: Vector3) -> void:
		var world := get_tree().current_scene as PFRWorldLevel
		var exit := world.get_node_or_null("Gameplay/Transitions/" + exit_name) as RouteTravelTrigger
		if exit == null:
			_check(false, "Missing exit " + exit_name + " in " + world.scene_file_path)
			return
		var player := world.get_player()
		player.global_position = exit.global_position + approach
		player.velocity = Vector3.ZERO
		await get_tree().physics_frame
		await get_tree().physics_frame
		for frame in 65:
			if not is_instance_valid(player) or GameInstance.is_scene_transfer_in_progress():
				return
			player.velocity = -approach.normalized() * 4.5
			player.move_and_slide()
			await get_tree().physics_frame
		if is_instance_valid(player):
			player.velocity = Vector3.ZERO

	func _wait(path: String) -> void:
		for frame in 600:
			if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == path and not GameInstance.is_scene_transfer_in_progress():
				await get_tree().physics_frame
				await get_tree().physics_frame
				return
			await get_tree().process_frame
		_check(false, "Timed out waiting for " + path)

	func _check_arrival(marker: StringName) -> void:
		var world := get_tree().current_scene as PFRWorldLevel
		_check(world.find_spawn_marker(marker) != null, "Missing arrival marker " + marker)
		if world.find_spawn_marker(marker) == null:
			return
		_check(world.get_player().global_position.distance_to(world.find_spawn_marker(marker).global_position) < 0.2, "Arrival should apply " + marker)
		for exit in world.get_node("Gameplay/Transitions").get_children():
			if exit is RouteTravelTrigger:
				_check(not exit.overlaps_body(world.get_player()), "Arrival must not retrigger " + exit.name)

	func _route(index: int) -> String:
		return "res://game/world/levels/standalone_areas/routes/route_%02d/route_%02d.tscn" % [index, index]

	func _check(value: bool, message: String) -> void:
		if not value:
			failures.append(message)

func _ready() -> void:
	var watcher := JourneyWatcher.new()
	GameInstance.add_child(watcher)
	watcher.run.call_deferred()
