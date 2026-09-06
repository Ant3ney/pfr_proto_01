extends Node


class GatewayWatcher:
	extends Node

	const CITY_PATH := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
	const GATEHOUSE_PATH := (
		"res://game/world/levels/new_bouffalant_city/interiors/gatehouse_interior.tscn"
	)
	const ROUTE_PATH := "res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"

	var failures: Array[String] = []
	var route_start_applied := false
	var gatehouse_return_applied := false
	var rear_door_started := false
	var rear_door_locked_when_started := false


	func run() -> void:
		GameInstance.scene_transfer_started.connect(_on_scene_transfer_started)
		GameInstance.scene_transfer_finished.connect(_on_scene_transfer_finished)
		_check(
			GameInstance.transfer_to_scene(CITY_PATH, &"GateBuildingFrontReturn"),
			"The modular city should accept its Gate Building return marker."
		)
		await _wait_for_scene(CITY_PATH)
		var city := get_tree().current_scene
		_check(city != null and city.scene_file_path == CITY_PATH, "The modular city should load.")
		if city == null or city.scene_file_path != CITY_PATH:
			_finish()
			return

		var city_player := city.get_node_or_null(^"Runtime/Player") as PlayerCharacter
		var city_entrance := city.get_node_or_null(
			^"Gameplay/Transitions/GateBuildingFrontEntranceTrigger"
		) as SceneTransferTrigger
		var gate_model := city.get_node_or_null(
			^"NavigationRegion3D/WorldGeometry/Structures/NewBouffalantCityAssets2/T1BGateBuilding"
		) as Node3D
		_check(city_player != null, "The modular city should contain its PlayerCharacter.")
		_check(city_entrance != null, "The city-facing Gate Building doorway should be interactive.")
		_check(
			city_entrance != null
			and city_entrance.destination_scene_path == GATEHOUSE_PATH
			and city_entrance.destination_spawn_marker == &"FrontEntrySpawn",
			"The city-facing doorway should target the Gate Building's front room."
		)
		_check(
			city_entrance != null
			and gate_model != null
			and city_entrance.global_position.x > gate_model.global_position.x,
			"The sole city doorway should be on the accessible city-facing side of the building."
		)
		if city_player == null or city_entrance == null:
			_finish()
			return
		city_entrance.body_entered.emit(city_player)
		await _wait_for_scene(GATEHOUSE_PATH)
		for _frame in 3:
			await get_tree().physics_frame

		var gatehouse := get_tree().current_scene
		_check(
			gatehouse != null and gatehouse.scene_file_path == GATEHOUSE_PATH,
			"Entering the city-facing doorway should load and remain in the Gate Building interior."
		)
		if gatehouse == null or gatehouse.scene_file_path != GATEHOUSE_PATH:
			_finish()
			return

		var exit_room := gatehouse.get_node_or_null(^"Gameplay/Transitions/Route0ExitRoom") as Node3D
		var route_exit := gatehouse.get_node_or_null(
			^"Gameplay/Transitions/Route0ExitRoom/ExitToRoute0"
		) as SceneTransferTrigger
		var return_spawn := gatehouse.get_node_or_null(
			^"Gameplay/Transitions/Route0ExitRoom/Route0ReturnSpawn"
		) as Marker3D
		var player := gatehouse.get_node_or_null(^"Runtime/Player") as PlayerCharacter
		var front_entry := gatehouse.get_node_or_null(^"Markers/FrontEntrySpawn") as Marker3D
		var front_exit := gatehouse.get_node_or_null(^"Gameplay/Transitions/ExitFront") as SceneTransferTrigger
		var city_exit_label := gatehouse.get_node_or_null(^"NavigationRegion3D/WorldGeometry/Props/CityExitLabel") as Label3D
		var city_exit_guide := gatehouse.get_node_or_null(^"NavigationRegion3D/WorldGeometry/Props/CityExitGuide") as MeshInstance3D
		var route_exit_label := gatehouse.get_node_or_null(
			^"Gameplay/Transitions/Route0ExitRoom/Route0DoorLabel"
		) as Label3D
		var route_exit_guide := gatehouse.get_node_or_null(
			^"Gameplay/Transitions/Route0ExitRoom/Route0DoorGuide"
		) as MeshInstance3D
		_check(player != null and front_entry != null, "The Gate Building should contain its player and city entry spawn.")
		if player != null and front_entry != null:
			_check(
				player.global_transform.is_equal_approx(front_entry.global_transform),
				"The city doorway should place the player safely inside the Gate Building."
			)
		_check(
			front_exit != null and player != null and not front_exit.overlaps_body(player),
			"The front arrival should remain outside the city exit trigger without requiring immediate movement."
		)
		_check(
			city_exit_label != null
			and city_exit_label.text == "CITY EXIT"
			and city_exit_guide != null,
			"The way back to the city should have a clear illuminated label and floor guide."
		)
		_check(exit_room != null, "The Gate Building should have a dedicated rear Route 0 exit room.")
		_check(route_exit != null, "The rear doorway should contain a contact transfer to Route 0.")
		_check(return_spawn != null, "The rear exit room should contain Route0ReturnSpawn.")
		_check(
			gatehouse.get_node_or_null(^"Gameplay/Transitions/Route0ExitRoom/Route0Gateway") == null
			and gatehouse.get_node_or_null(^"Gameplay/Transitions/Route0ExitRoom/AreaGateway") == null,
			"The Gate Building should not require a green interaction prop to enter Route 0."
		)
		_check(
			route_exit_label != null
			and route_exit_label.text == "ROUTE 0"
			and route_exit_guide != null,
			"The walk-through Route 0 doorway should have a clear illuminated label and floor guide."
		)
		if route_exit == null or player == null:
			_finish()
			return

		var npc := CharacterBody3D.new()
		gatehouse.add_child(npc)
		route_exit.body_entered.emit(npc)
		await get_tree().process_frame
		_check(get_tree().current_scene == gatehouse, "NPC contact must not activate the Route 0 doorway.")
		route_exit.body_entered.emit(player)

		await _wait_for_scene(ROUTE_PATH)

		var route := get_tree().current_scene
		_check(route != null and route.scene_file_path == ROUTE_PATH, "Walking through the rear door should open Route 0.")
		_check(rear_door_started, "Walking through the rear door should request Route 0.")
		_check(rear_door_locked_when_started, "The rear doorway should lock movement before transfer.")
		_check(route_start_applied, "The transfer should apply the named Route0Start marker.")
		_check(GameInstance.is_player_movement_enabled(), "Movement should restore after Route 0 is ready.")
		if route == null or route.scene_file_path != ROUTE_PATH:
			_finish()
			return
		var trainer_root := route.get_node_or_null(^"Gameplay/Actors/RouteTrainers") as Node3D
		if trainer_root != null:
			trainer_root.process_mode = Node.PROCESS_MODE_DISABLED
		var route_player := route.get_node_or_null(^"Runtime/Player") as PlayerCharacter
		var route_start := route.get_node_or_null(^"Markers/Route0Start") as Marker3D
		var return_gateway := route.get_node_or_null(
			^"Gameplay/Transitions/Route0ReturnGateway"
		) as AreaGateway
		_check(route_player != null and route_start != null, "Route 0 should contain its player and start marker.")
		if route_player != null and route_start != null:
			_check(
				route_player.global_position.is_equal_approx(route_start.global_position),
				"The rear door should place the player at the start of Route 0."
			)
		_check(return_gateway != null, "Route 0 should have a red interactive return object at its start.")
		if return_gateway == null or route_player == null:
			_finish()
			return
		var prompt := return_gateway.get_node_or_null(^"InteractionPrompt") as CanvasLayer
		var button := return_gateway.get_node_or_null(
			^"InteractionPrompt/PromptMargin/PromptPanel/PromptPadding/InteractionButton"
		) as Button
		var beacon := return_gateway.get_node_or_null(^"Visual/Beacon") as MeshInstance3D
		var beacon_material := (
			beacon.mesh.material as StandardMaterial3D
			if beacon != null and beacon.mesh != null
			else null
		)
		_check(
			beacon_material != null
			and beacon_material.albedo_color.r > beacon_material.albedo_color.g
			and beacon_material.albedo_color.r > beacon_material.albedo_color.b
			and beacon_material.emission_enabled,
			"The Route 0 return object should be unmistakably red and emissive."
		)
		_check(
			return_gateway.destination_scene_path == GATEHOUSE_PATH
			and return_gateway.destination_spawn_marker == &"Route0ReturnSpawn",
			"The red return object should target the Gate Building rear room."
		)
		_check(prompt != null and not prompt.visible, "The red return prompt should begin hidden.")
		_check(button != null and button.custom_minimum_size.y >= 48.0, "The red return should include a touch-sized interaction button.")
		return_gateway.body_entered.emit(route_player)
		await get_tree().process_frame
		_check(return_gateway.is_player_in_interaction_range(), "Player proximity should enable the red return object.")
		_check(prompt != null and prompt.visible, "Player proximity should reveal the red return prompt.")
		_check(button != null and not button.disabled, "The red return prompt should be actionable.")
		if button != null:
			button.pressed.emit()
		await _wait_for_scene(GATEHOUSE_PATH)
		for _frame in 3:
			await get_tree().physics_frame
		var returned_gatehouse := get_tree().current_scene
		_check(
			returned_gatehouse != null and returned_gatehouse.scene_file_path == GATEHOUSE_PATH,
			"The red Route 0 object should return to the Gate Building without looping."
		)
		_check(gatehouse_return_applied, "The red return should apply Route0ReturnSpawn.")
		if returned_gatehouse != null and returned_gatehouse.scene_file_path == GATEHOUSE_PATH:
			var returned_player := returned_gatehouse.get_node_or_null(^"Runtime/Player") as PlayerCharacter
			var returned_marker := returned_gatehouse.get_node_or_null(
				^"Gameplay/Transitions/Route0ExitRoom/Route0ReturnSpawn"
			) as Marker3D
			var returned_route_exit := returned_gatehouse.get_node_or_null(
				^"Gameplay/Transitions/Route0ExitRoom/ExitToRoute0"
			) as SceneTransferTrigger
			_check(
				returned_player != null
				and returned_marker != null
				and returned_player.global_transform.is_equal_approx(returned_marker.global_transform),
				"The red return should place the player safely beside the rear door."
			)
			_check(
				returned_route_exit != null
				and returned_player != null
				and not returned_route_exit.overlaps_body(returned_player),
				"Returning from Route 0 should not immediately send the player back through the door."
			)
		_finish()


	func _wait_for_scene(scene_path: String) -> void:
		for _frame in 300:
			if (
				get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == scene_path
				and not GameInstance.is_scene_transfer_in_progress()
			):
				return
			await get_tree().process_frame


	func _on_scene_transfer_finished(
		destination_scene_path: String,
		destination_spawn_marker: StringName,
		spawn_marker_applied: bool
	) -> void:
		if destination_scene_path == ROUTE_PATH and destination_spawn_marker == &"Route0Start":
			route_start_applied = spawn_marker_applied
		elif (
			destination_scene_path == GATEHOUSE_PATH
			and destination_spawn_marker == &"Route0ReturnSpawn"
		):
			gatehouse_return_applied = spawn_marker_applied


	func _on_scene_transfer_started(
		destination_scene_path: String,
		destination_spawn_marker: StringName
	) -> void:
		if destination_scene_path == ROUTE_PATH and destination_spawn_marker == &"Route0Start":
			rear_door_started = true
			rear_door_locked_when_started = not GameInstance.is_player_movement_enabled()


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


	func _finish() -> void:
		if failures.is_empty():
			print(
				"Route 0 gateway smoke test passed: stable Gate Building arrival, clear city and "
				+ "route exits, walk-through rear door, Route0Start placement, and red interactive "
				+ "return to the safe rear-room marker verified."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("Route 0 gateway smoke test failed: %s" % failure)
		get_tree().quit(1)


func _ready() -> void:
	var watcher := GatewayWatcher.new()
	watcher.name = "Route0GatewayTestWatcher"
	GameInstance.add_child(watcher)
	watcher.run()
