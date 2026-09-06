extends Node


class TransferWatcher:
	extends Node

	const TRIGGER_SCENE := preload("res://game/world/level_kits/gameplay/transitions/scene_transfer_trigger.tscn")
	const PLAYER_SCENE := preload("res://game/actors/player/player.tscn")
	const DESTINATION_PATH := "res://tests/scenes/fixtures/scene_transfer_destination.tscn"
	const DESTINATION_MARKER: StringName = &"ArrivalMarker"

	var failures: Array[String] = []
	var started_count := 0
	var finished_count := 0
	var failed_count := 0
	var marker_applied := false
	var movement_locked_when_started := false
	var transfer_active_when_started := false


	func run() -> void:
		GameInstance.scene_transfer_started.connect(_on_transfer_started)
		GameInstance.scene_transfer_finished.connect(_on_transfer_finished)
		GameInstance.scene_transfer_failed.connect(_on_transfer_failed)

		var source_scene := get_tree().current_scene
		_check(source_scene != null, "The test source scene should be current.")
		if source_scene == null:
			_finish()
			return

		var trigger := TRIGGER_SCENE.instantiate() as SceneTransferTrigger
		_check(trigger != null, "The reusable SceneTransferTrigger scene should instantiate.")
		if trigger == null:
			_finish()
			return
		trigger.destination_scene_path = DESTINATION_PATH
		trigger.destination_spawn_marker = DESTINATION_MARKER
		source_scene.add_child(trigger)
		await get_tree().process_frame

		_check(trigger.collision_layer == 0, "Scene transfers should not occupy a physics layer.")
		_check(trigger.collision_mask == 1, "Scene transfers should detect the layer-1 player.")
		var trigger_shape := trigger.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
		_check(
			trigger_shape != null and trigger_shape.shape is BoxShape3D,
			"The reusable trigger scene should include an editable box volume."
		)

		var npc := CharacterBody3D.new()
		npc.name = "NPCControl"
		source_scene.add_child(npc)
		trigger.body_entered.emit(npc)
		await get_tree().process_frame
		_check(
			get_tree().current_scene == source_scene,
			"A non-player CharacterBody3D must not activate the scene trigger."
		)
		_check(not GameInstance.is_scene_transfer_in_progress(), "NPC contact must not begin a transfer.")

		var player := PLAYER_SCENE.instantiate() as PlayerCharacter
		_check(player != null, "The PlayerCharacter fixture should instantiate.")
		if player == null:
			_finish()
			return
		source_scene.add_child(player)
		trigger.body_entered.emit(player)
		trigger.body_entered.emit(player)
		await get_tree().process_frame
		_check(started_count == 1, "Player contact should request exactly one scene transfer.")
		_check(movement_locked_when_started, "Movement should lock before the scene change starts.")
		_check(transfer_active_when_started, "The transfer should be active when its started signal emits.")

		for _frame in 180:
			if (
				get_tree().current_scene != null
				and get_tree().current_scene.scene_file_path == DESTINATION_PATH
				and not GameInstance.is_scene_transfer_in_progress()
			):
				break
			await get_tree().process_frame

		var destination_scene := get_tree().current_scene
		_check(
			destination_scene != null and destination_scene.scene_file_path == DESTINATION_PATH,
			"The inspector-selected PackedScene path should become the current scene."
		)
		_check(finished_count == 1, "A successful scene change should finish exactly once.")
		_check(failed_count == 0, "A valid scene transfer should not emit failure.")
		_check(marker_applied, "The configured destination marker should be applied.")
		_check(GameInstance.is_player_movement_enabled(), "Movement should restore after the destination is ready.")

		if destination_scene != null:
			var destination_player := _find_player_character(destination_scene)
			var marker := destination_scene.find_child(String(DESTINATION_MARKER), true, false) as Node3D
			_check(destination_player != null, "The destination should contain a PlayerCharacter.")
			_check(marker != null, "The destination should contain the configured marker.")
			if destination_player != null and marker != null:
				_check(
					destination_player.global_position.is_equal_approx(marker.global_position),
					"The destination player should be placed at the configured marker."
				)
				_check(
					destination_player.global_basis.is_equal_approx(marker.global_basis),
					"The destination marker should also define player facing."
				)

		_finish()


	func _on_transfer_started(
		destination_scene_path: String,
		destination_spawn_marker: StringName
	) -> void:
		started_count += 1
		movement_locked_when_started = not GameInstance.is_player_movement_enabled()
		transfer_active_when_started = GameInstance.is_scene_transfer_in_progress()
		_check(destination_scene_path == DESTINATION_PATH, "Started signal should expose the destination path.")
		_check(destination_spawn_marker == DESTINATION_MARKER, "Started signal should expose the spawn marker.")


	func _on_transfer_finished(
		destination_scene_path: String,
		destination_spawn_marker: StringName,
		spawn_marker_applied: bool
	) -> void:
		finished_count += 1
		marker_applied = spawn_marker_applied
		_check(destination_scene_path == DESTINATION_PATH, "Finished signal should expose the destination path.")
		_check(destination_spawn_marker == DESTINATION_MARKER, "Finished signal should expose the spawn marker.")


	func _on_transfer_failed(_message: String) -> void:
		failed_count += 1


	func _find_player_character(root: Node) -> PlayerCharacter:
		if root is PlayerCharacter:
			return root as PlayerCharacter
		for child: Node in root.get_children():
			var player := _find_player_character(child)
			if player != null:
				return player
		return null


	func _check(condition: bool, message: String) -> void:
		if not condition:
			failures.append(message)


	func _finish() -> void:
		if failures.is_empty():
			print(
				"SceneTransferTrigger smoke test passed: inspector destination, player-only activation, "
				+ "single request, movement lock, scene handoff, and marker placement verified."
			)
			get_tree().quit(0)
			return
		for failure in failures:
			push_error("SceneTransferTrigger smoke test failed: %s" % failure)
		get_tree().quit(1)


func _ready() -> void:
	var watcher := TransferWatcher.new()
	watcher.name = "SceneTransferTestWatcher"
	GameInstance.add_child(watcher)
	watcher.run()
