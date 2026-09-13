extends Node

var _failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := ChallengeProgressionSystem.get_catalog()
	for area in catalog.get_areas_for_category("route"):
		var world := area.destination.instantiate() as PFRWorldLevel
		var trainer_poses: Array[Vector3] = []
		for trainer in world.get_node("Gameplay/Actors").find_children("*", "PFRCharacter", true, false):
			trainer_poses.append(trainer.position)
			var toward_path: Vector3 = trainer.get_meta("path_checkpoint") - trainer.position
			_check((-trainer.basis.z).dot(toward_path.normalized()) > 0.99, "%s: %s should face the path." % [area.area_id, trainer.name])
		var grass_poses: Array[Vector3] = []
		for grass in world.find_children("*", "TallGrassEncounterZone", true, false):
			grass_poses.append(grass.position)
		var entry := world.find_spawn_marker(area.entry_spawn_marker).position
		var back := world.find_spawn_marker(&"FromNextRoute").position
		var next_exit := world.get_node("Gameplay/Transitions/NextRouteExit") as RouteTravelTrigger
		var previous_exit := world.get_node("Gameplay/Transitions/PreviousRouteExit") as RouteTravelTrigger
		var i := area.numeric_order
		_check(next_exit.destination_area_id == ("route_%02d" % (i + 1) if i < 40 else ""), "%s should lead to the next route or city." % area.area_id)
		_check(previous_exit.destination_area_id == ("route_%02d" % (i - 1) if i > 0 else ""), "%s should lead back to the previous route or city." % area.area_id)
		_check(next_exit.get_node_or_null(next_exit.completion_gate_path) is RouteCompletionGate, "%s onward travel must enforce its completion gate." % area.area_id)
		_check(entry.distance_to(previous_exit.position) > 4 and back.distance_to(next_exit.position) > 4, "%s arrivals must clear the exit triggers." % area.area_id)
		var samples: PackedVector3Array = world.get_meta("route_main_path")
		world.get_node("Player").free()
		world.get_node("Gameplay").free()
		add_child(world)
		await get_tree().process_frame
		await get_tree().physics_frame
		await get_tree().physics_frame
		var map := world.get_world_3d().navigation_map
		NavigationServer3D.map_force_update(map)
		for sync_frame in 6:
			await get_tree().physics_frame
		var space := world.get_world_3d().direct_space_state
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3
		capsule.height = 1.65
		for p in samples:
			_check_ground(space, p, area.area_id)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.transform.origin = p + Vector3(0, 0.88, 0)
			query.collision_mask = 1
			_check(space.intersect_shape(query, 1).is_empty(), "%s: main path is obstructed at %s." % [area.area_id, p])
			var nearest := NavigationServer3D.map_get_closest_point(map, p)
			_check(Vector2(nearest.x, nearest.z).distance_to(Vector2(p.x, p.z)) < 0.7 and absf(nearest.y) < 0.8, "%s: path needs ground-level navigation at %s (got %s)." % [area.area_id, p, nearest])
		var path := NavigationServer3D.map_get_path(map, entry, back, true)
		_check(path.size() > 1 and path[path.size()-1].distance_to(back) < 0.8, "%s: the entry must connect to the far return spawn." % area.area_id)
		for p in trainer_poses + grass_poses:
			_check_ground(space, p, area.area_id)
			var approach := NavigationServer3D.map_get_path(map, entry, p, true)
			_check(approach.size() > 1 and approach[approach.size()-1].distance_to(p) < 0.85, "%s: trainer/grass clearing at %s must be reachable." % [area.area_id, p])
		world.free()
		await get_tree().physics_frame
		print("GEOMETRY ", area.area_id, " checked")
	if _failures.is_empty():
		print("Route network geometry passed: all 41 routes have clear paths, reachable trainers/grass, navigation and paired safe exits.")
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		get_tree().quit(1)

func _check_ground(space: PhysicsDirectSpaceState3D, p: Vector3, area_id: String) -> void:
	var ray := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p - Vector3.UP, 1)
	var hit := space.intersect_ray(ray)
	_check(not hit.is_empty() and absf((hit.get("position", Vector3.INF) as Vector3).y) < 0.05, "%s: missing ground at %s." % [area_id, p])

func _check(value: bool, message: String) -> void:
	if not value:
		_failures.append(message)
