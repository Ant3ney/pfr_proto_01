extends Node

const TALL_GRASS_SCENE := preload("res://game/world/level_kits/gameplay/encounters/tall_grass_encounter_zone.tscn")
const PLAYER_SCENE := preload("res://game/actors/player/player.tscn")
const ENCOUNTER_PATH := "res://game/battle/encounters/wild_fletchling_route_0_v1.tres"
const BATTLE_SCENE_PATH := "res://game/battle/scenes/route_0_wild_battle_scene.tscn"

var _failures: Array[String] = []
var _rolls: Array[Dictionary] = []
var _selected_encounters: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameInstance.set_player_movement_enabled(true)
	var zone := TALL_GRASS_SCENE.instantiate() as TallGrassEncounterZone
	_check(zone != null, "The reusable tall-grass scene should instantiate with its typed script.")
	if zone == null:
		_finish()
		return
	zone.start_battle_automatically = false
	zone.encounter_chance_per_check = 1.0
	zone.distance_between_checks = 1.0
	zone.random_seed = 27
	zone.encounter_roll_completed.connect(
		func(roll: float, chance: float, succeeded: bool) -> void:
			_rolls.append({"roll": roll, "chance": chance, "succeeded": succeeded})
	)
	zone.encounter_selected.connect(
		func(battle_data: Dictionary) -> void:
			_selected_encounters.append(battle_data)
	)
	add_child(zone)
	await get_tree().process_frame

	_check(zone.collision_layer == 0, "Tall grass should not occupy a blocking physics layer.")
	_check(zone.collision_mask == 1, "Tall grass should detect the layer-1 player.")
	var encounter_shape := zone.get_node_or_null(^"EncounterVolume") as CollisionShape3D
	_check(
		encounter_shape != null
		and encounter_shape.shape is BoxShape3D
		and (encounter_shape.shape as BoxShape3D).size.is_equal_approx(Vector3(8.5, 2.0, 4.5)),
		"The reusable scene should expose the authored 8 x 4 m walkable encounter volume."
	)
	var visuals := zone.get_node_or_null(^"TallGrassVisuals") as Node3D
	_check(visuals != null and visuals.get_child_count() == 6, "A grass patch should contain six grounded visual clumps.")
	if visuals != null:
		for visual: Node in visuals.get_children():
			_check(
				visual is Node3D and (visual as Node3D).scale.is_equal_approx(Vector3.ONE),
				"Tall-grass art instances should remain at unit scale."
			)

	var npc := CharacterBody3D.new()
	npc.name = "NPCControl"
	add_child(npc)
	zone.body_entered.emit(npc)
	zone._physics_process(0.0)
	_check(_rolls.is_empty(), "A non-player body must not register encounter movement.")

	var player := PLAYER_SCENE.instantiate() as PlayerCharacter
	_check(player != null, "The PlayerCharacter fixture should instantiate.")
	if player == null:
		_finish()
		return
	add_child(player)
	player.global_position = Vector3.ZERO
	zone.body_entered.emit(player)

	zone._physics_process(0.0)
	zone._physics_process(0.0)
	_check(_rolls.is_empty(), "Standing still inside tall grass must not roll an encounter.")
	player.global_position.x += 0.6
	zone._physics_process(0.0)
	_check(_rolls.is_empty(), "Movement below the configured distance should not roll early.")
	player.global_position.x += 0.6
	zone._physics_process(0.0)
	_check(_rolls.size() == 1, "Crossing one distance interval should produce exactly one roll.")
	_check(_selected_encounters.size() == 1, "A guaranteed successful roll should select one encounter.")
	_check(zone.is_encounter_pending(), "A selected encounter should debounce further checks.")
	if not _selected_encounters.is_empty():
		var battle_data := _selected_encounters[0]
		_check(battle_data.get("encounter_type") == "wild", "Tall grass should author a wild encounter launch.")
		_check(
			battle_data.get("battle_scene_path") == BATTLE_SCENE_PATH,
			"Tall grass should launch the concrete Route 0 battle scene."
		)
		_check(
			battle_data.get("encounter_id") == "wild-fletchling-route-0-v1",
			"Tall grass and the authored encounter should share one stable ID."
		)

	zone.reset_encounter_state()
	zone.encounter_chance_per_check = 0.0
	player.global_position.x += 1.1
	zone._physics_process(0.0)
	_check(_rolls.size() == 2, "The next travelled interval should perform another roll after reset.")
	_check(_selected_encounters.size() == 1, "A zero-percent roll should never select another encounter.")

	var encounter := load(ENCOUNTER_PATH) as Resource
	_check(encounter != null, "The Route 0 encounter resource should load.")
	if encounter != null and encounter.has_method("validate"):
		_check(
			(encounter.call("validate") as PackedStringArray).is_empty(),
			"The authored wild Fletchling encounter should pass battle validation."
		)
	_check(ResourceLoader.exists(BATTLE_SCENE_PATH, "PackedScene"), "The concrete wild battle scene should exist.")

	zone.reset_encounter_state()
	zone.encounter_chance_per_check = 1.0
	zone.start_battle_automatically = true
	player.global_position.x += 1.1
	zone._physics_process(0.0)
	_check(
		GameInstance.is_battle_start_in_progress(),
		"A successful production-mode grass roll should enter the GameInstance battle transition."
	)
	var pending_launch := GameInstance.get_pending_battle_data()
	_check(
		pending_launch.get("encounter_id") == "wild-fletchling-route-0-v1"
		and pending_launch.get("battle_scene_path") == BATTLE_SCENE_PATH,
		"The automatic integration path should preserve the concrete encounter ID and scene."
	)
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print(
			"Tall grass encounter smoke test passed: player-only distance checks, stationary safety, "
			+ "chance handling, debounce, visuals, and automatic Route 0 battle start verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Tall grass encounter smoke test failed: %s" % failure)
	get_tree().quit(1)
