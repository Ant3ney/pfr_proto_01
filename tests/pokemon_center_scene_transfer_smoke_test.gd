extends Node


class TransferWatcher:
	extends Node

	const CITY_PATH := "res://demo/primary_development_enviroment.tscn"
	const MAIN_INTERIOR_PATH := "res://art/environments/new_bouffalant_city/pokemon_center_interior/pokemon_center_interior.tscn"
	const EAST_ANNEX_PATH := "res://art/environments/new_bouffalant_city/pokemon_center_annex/pokemon_center_annex.tscn"

	var failures: Array[String] = []
	var transfer_failures: Array[String] = []


	func run() -> void:
		GameInstance.scene_transfer_failed.connect(_on_transfer_failed)
		_check(
			GameInstance.transfer_to_scene(CITY_PATH, &"PokemonCenterEntrance"),
			"The city scene and Pokemon Center arrival marker should be accepted."
		)
		await _wait_for_scene(CITY_PATH)

		var city := get_tree().current_scene
		_check(city != null and city.scene_file_path == CITY_PATH, "The city should load first.")
		if city == null or city.scene_file_path != CITY_PATH:
			_finish()
			return
		var city_player := _find_player_character(city)
		var south_marker := city.get_node_or_null(^"PokemonCenterEntrance") as Marker3D
		var east_marker := city.get_node_or_null(^"PokemonCenterEastEntrance") as Marker3D
		_check(
			city_player != null and south_marker != null and east_marker != null,
			"The city should contain its player and both safe Pokemon Center return markers."
		)
		if city_player != null and south_marker != null:
			_check(
				city_player.global_transform.is_equal_approx(south_marker.global_transform),
				"Returning from the interior should place and face the player outside the south door."
			)

		var south_trigger := city.get_node_or_null(^"PokemonCenterSouthEntranceTrigger") as SceneTransferTrigger
		var east_trigger := city.get_node_or_null(^"PokemonCenterEastEntranceTrigger") as SceneTransferTrigger
		_check(south_trigger != null and east_trigger != null, "Both exterior Pokemon Center doors should have triggers.")
		if south_trigger != null:
			_check(
				south_trigger.destination_scene_path == MAIN_INTERIOR_PATH,
				"The south door should target the main clinic interior."
			)
			_check(south_trigger.destination_spawn_marker == &"EntrySpawn", "The south door should use EntrySpawn.")
		if east_trigger != null:
			_check(
				east_trigger.destination_scene_path == EAST_ANNEX_PATH,
				"The east door should target the distinct service-annex interior."
			)
			_check(east_trigger.destination_spawn_marker == &"EntrySpawn", "The east door should use EntrySpawn.")
		if south_trigger == null or east_trigger == null or city_player == null:
			_finish()
			return

		await _exercise_route(
			"PokemonCenterSouthEntranceTrigger",
			MAIN_INTERIOR_PATH,
			&"PokemonCenterEntrance",
			"south main clinic"
		)
		await _exercise_route(
			"PokemonCenterEastEntranceTrigger",
			EAST_ANNEX_PATH,
			&"PokemonCenterEastEntrance",
			"east service annex"
		)
		_check(transfer_failures.is_empty(), "No configured Pokemon Center transfer should fail.")
		_finish()


	func _exercise_route(
		trigger_name: String,
		destination_path: String,
		return_marker_name: StringName,
		route_label: String
	) -> void:
		var city := get_tree().current_scene
		_check(city != null and city.scene_file_path == CITY_PATH, "%s should begin in the city." % route_label)
		if city == null or city.scene_file_path != CITY_PATH:
			return
		var city_player := _find_player_character(city)
		var entrance_trigger := city.get_node_or_null(trigger_name) as SceneTransferTrigger
		_check(city_player != null and entrance_trigger != null, "%s is missing its player or entrance trigger." % route_label)
		if city_player == null or entrance_trigger == null:
			return

		entrance_trigger.body_entered.emit(city_player)
		await _wait_for_scene(destination_path)
		var interior := get_tree().current_scene
		_check(
			interior != null and interior.scene_file_path == destination_path,
			"The %s door should load its assigned interior." % route_label
		)
		if interior == null or interior.scene_file_path != destination_path:
			return
		var interior_player := _find_player_character(interior)
		var entry_spawn := interior.get_node_or_null(^"EntrySpawn") as Marker3D
		_check(
			interior_player != null and entry_spawn != null,
			"The %s interior should contain its player and EntrySpawn." % route_label
		)
		if interior_player != null and entry_spawn != null:
			_check(
				interior_player.global_transform.is_equal_approx(entry_spawn.global_transform),
				"The %s door should place and face the player at EntrySpawn." % route_label
			)

		var exit_trigger := interior.get_node_or_null(^"ExitToCity") as SceneTransferTrigger
		_check(exit_trigger != null, "The %s interior should have a SceneTransferTrigger exit." % route_label)
		if exit_trigger == null or interior_player == null:
			return
		_check(exit_trigger.destination_scene_path == CITY_PATH, "The %s exit should target the city." % route_label)
		_check(
			exit_trigger.destination_spawn_marker == return_marker_name,
			"The %s exit should use its matching safe exterior marker." % route_label
		)

		exit_trigger.body_entered.emit(interior_player)
		await _wait_for_scene(CITY_PATH)
		for _frame in 3:
			await get_tree().physics_frame
		city = get_tree().current_scene
		_check(
			city != null and city.scene_file_path == CITY_PATH,
			"The %s exterior marker should prevent an immediate reverse-trigger loop." % route_label
		)
		if city == null or city.scene_file_path != CITY_PATH:
			return
		city_player = _find_player_character(city)
		var return_marker := city.get_node_or_null(NodePath(String(return_marker_name))) as Marker3D
		_check(
			city_player != null and return_marker != null,
			"The %s return should find its player and exterior marker." % route_label
		)
		if city_player != null and return_marker != null:
			_check(
				city_player.global_transform.is_equal_approx(return_marker.global_transform),
				"The %s exit should return the player to its matching exterior opening." % route_label
			)


	func _wait_for_scene(scene_path: String) -> void:
		for _frame in 240:
			if (
				get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == scene_path
				and not GameInstance.is_scene_transfer_in_progress()
			):
				return
			await get_tree().process_frame


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
				"Pokemon Center scene transfer smoke test passed: the south door enters the main clinic, "
				+ "the east door enters the distinct service annex, both exits use matching safe city markers, "
				+ "and no transfer loop occurs."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("Pokemon Center scene transfer smoke test failed: %s" % failure)
		get_tree().quit(1)


func _ready() -> void:
	var watcher := TransferWatcher.new()
	watcher.name = "PokemonCenterTransferTestWatcher"
	GameInstance.add_child(watcher)
	watcher.run()
