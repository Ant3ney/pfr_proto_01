extends Node


class GatewayWatcher:
	extends Node

	const GATEWAY_SCENE := preload("res://overworld/route_4/route_4_gateway.tscn")
	const PLAYER_SCENE := preload("res://demo/player.tscn")
	const ROUTE_PATH := "res://overworld/route_4/route_4.tscn"

	var failures: Array[String] = []
	var marker_applied := false


	func run() -> void:
		GameInstance.scene_transfer_finished.connect(_on_scene_transfer_finished)
		var source := get_tree().current_scene
		_check(source != null, "The gateway test source scene should be current.")
		if source == null:
			_finish()
			return

		var gateway := GATEWAY_SCENE.instantiate() as Route4Gateway
		_check(gateway != null, "The green Route 4 gateway should instantiate with its typed script.")
		if gateway == null:
			_finish()
			return
		source.add_child(gateway)
		await get_tree().process_frame

		var prompt := gateway.get_node_or_null(^"InteractionPrompt") as CanvasLayer
		var button := gateway.get_node_or_null(
			^"InteractionPrompt/PromptMargin/PromptPanel/PromptPadding/InteractionButton"
		) as Button
		_check(prompt != null and not prompt.visible, "The interaction prompt should begin hidden.")
		_check(button != null and button.custom_minimum_size.y >= 48.0, "The gateway should include a touch-sized interaction button.")
		var beacon := gateway.get_node_or_null(^"Visual/Beacon") as MeshInstance3D
		var beacon_material := (
			beacon.mesh.material as StandardMaterial3D
			if beacon != null and beacon.mesh != null
			else null
		)
		_check(
			beacon_material != null
			and beacon_material.albedo_color.g > beacon_material.albedo_color.r
			and beacon_material.albedo_color.g > beacon_material.albedo_color.b
			and beacon_material.emission_enabled,
			"The route object should be unmistakably green with a restrained emissive beacon."
		)

		var npc := CharacterBody3D.new()
		source.add_child(npc)
		gateway.body_entered.emit(npc)
		_check(not gateway.is_player_in_interaction_range(), "NPC proximity must not enable the route interaction.")

		var player := PLAYER_SCENE.instantiate() as PlayerCharacter
		_check(player != null, "The PlayerCharacter fixture should instantiate.")
		if player == null:
			_finish()
			return
		source.add_child(player)
		gateway.body_entered.emit(player)
		await get_tree().process_frame
		_check(gateway.is_player_in_interaction_range(), "Player proximity should enable the gateway.")
		_check(prompt != null and prompt.visible, "Player proximity should reveal the interaction prompt.")
		_check(button != null and not button.disabled, "The visible prompt should be actionable.")

		if button != null:
			button.pressed.emit()
		_check(GameInstance.is_scene_transfer_in_progress(), "Pressing the prompt should request a scene transfer.")
		_check(not GameInstance.is_player_movement_enabled(), "The gateway should lock movement during transfer.")

		for _frame in 240:
			if (
				get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == ROUTE_PATH
				and not GameInstance.is_scene_transfer_in_progress()
			):
				break
			await get_tree().process_frame

		var route := get_tree().current_scene
		_check(route != null and route.scene_file_path == ROUTE_PATH, "The green object should open Route 4.")
		_check(marker_applied, "The transfer should apply the named Route4Start marker.")
		_check(GameInstance.is_player_movement_enabled(), "Movement should restore after Route 4 is ready.")
		if route != null:
			var route_player := route.get_node_or_null(^"Player") as PlayerCharacter
			var route_start := route.get_node_or_null(^"Route4Start") as Marker3D
			_check(route_player != null and route_start != null, "Route 4 should contain its player and start marker.")
			if route_player != null and route_start != null:
				_check(
					route_player.global_position.is_equal_approx(route_start.global_position),
					"The gateway should place the player at the start of Route 4."
				)
		_finish()


	func _on_scene_transfer_finished(
		destination_scene_path: String,
		destination_spawn_marker: StringName,
		spawn_marker_applied: bool
	) -> void:
		if destination_scene_path == ROUTE_PATH and destination_spawn_marker == &"Route4Start":
			marker_applied = spawn_marker_applied


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


	func _finish() -> void:
		if failures.is_empty():
			print(
				"Route 4 gateway smoke test passed: green presentation, player-only proximity, "
				+ "touch interaction, movement lock, transfer, and Route4Start placement verified."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("Route 4 gateway smoke test failed: %s" % failure)
		get_tree().quit(1)


func _ready() -> void:
	var watcher := GatewayWatcher.new()
	watcher.name = "Route4GatewayTestWatcher"
	GameInstance.add_child(watcher)
	watcher.run()
