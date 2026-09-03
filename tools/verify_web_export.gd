extends SceneTree

const ROUTE_SCENE_PATH := "res://overworld/route_0/route_0.tscn"
const DESTINATION_SCENE_PATH := "res://rnd/stretch/worlds/stretch_destination.tscn"
const TRAINER_SCENE_PATH := "res://overworld/trainer_lake/TrainerKyle.tscn"
const TRAINER_NAMES := [
	"TrainerKyle",
	"PoliceOfficer",
	"Businessman",
	"Backpacker",
	"Jogger",
	"Tourist",
	"DeliveryWorker",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	await _verify_route_trainers()
	_verify_destination_pre_spawn_repair()
	_verify_cloud_save_runtime()

	if _failures.is_empty():
		print("Web export trainer verification passed.")
		quit(0)
		return
	for failure in _failures:
		push_error("Web export trainer verification failed: %s" % failure)
	quit(1)


func _verify_route_trainers() -> void:
	var packed_route := load(ROUTE_SCENE_PATH) as PackedScene
	_check(packed_route != null, "The exported Route 0 scene should load.")
	if packed_route == null:
		return

	var route := packed_route.instantiate()
	root.add_child(route)
	await process_frame
	await physics_frame
	var player := route.get_node_or_null(^"Player") as Node3D
	_check(player != null, "The exported Route 0 scene should contain its player.")
	var checkpoint_root := route.get_node_or_null(^"TrainerChokepoints")
	_check(
		checkpoint_root != null
		and checkpoint_root.find_children(
			"TrainerGate*", "StaticBody3D", false, false
		).size() == 14,
		"The exported Route 0 scene should retain all seven mandatory trainer chokes."
	)
	var completion_gate := route.get_node_or_null(^"Route0CompletionGate") as Area3D
	_check(
		completion_gate != null and int(completion_gate.get("route_index")) == 0,
		"The exported Route 0 scene should retain its far-end progression gate."
	)

	var sight_trainer: Node3D
	var sight_behavior: Resource
	for trainer_name in TRAINER_NAMES:
		var trainer := route.get_node_or_null(
			NodePath("RouteTrainers/%s" % trainer_name)
		) as Node3D
		var controller := trainer.get("controller") as Resource if trainer != null else null
		var behavior := controller.get("npc_behavior") as Resource if controller != null else null
		_check(trainer != null, "The exported Route 0 scene should contain %s." % trainer_name)
		_check(
			behavior != null,
			"The exported %s controller should repair its trainer behavior." % trainer_name
		)
		_check(
			trainer != null
			and player != null
			and bool(trainer.call("can_interact", player)),
			"The exported %s trainer should accept manual interaction." % trainer_name
		)
		if trainer_name == "TrainerKyle":
			sight_trainer = trainer
			sight_behavior = behavior

	if player != null and sight_trainer != null and sight_behavior != null:
		var forward: Vector3 = sight_behavior.call(
			"_get_forward_direction",
			sight_trainer
		)
		player.global_position = sight_trainer.global_position + forward * 5.0
		for _frame in 4:
			await physics_frame
		_check(
			int(sight_behavior.get("_approach_state")) != 0,
			"An exported Route 0 trainer should detect a player in its sight line."
		)

	var game_instance := root.get_node_or_null(^"GameInstance")
	if game_instance != null:
		game_instance.call("set_player_movement_enabled", true)
	route.free()


func _verify_destination_pre_spawn_repair() -> void:
	var trainer_scene := load(TRAINER_SCENE_PATH) as PackedScene
	var destination_scene := load(DESTINATION_SCENE_PATH) as PackedScene
	_check(trainer_scene != null, "The exported trainer template should load dynamically.")
	_check(destination_scene != null, "The exported destination scene should load dynamically.")
	if trainer_scene == null or destination_scene == null:
		return

	var trainer := trainer_scene.instantiate()
	var destination := destination_scene.instantiate()
	var controller := trainer.get("controller") as Resource
	controller.set("npc_behavior", null)
	var configured: bool = bool(destination.call(
		"_configure_existing_trainer",
		trainer,
		{
			"encounter_id": "web-export-verification",
			"battle_scene_path": "res://rnd/stretch/battle/stretch_battle_scene.tscn",
			"display_name": "Web Export Trainer",
		}
	))
	var repaired_behavior := controller.get("npc_behavior") as Resource
	_check(
		configured
		and repaired_behavior != null
		and String(repaired_behavior.get("encounter_id")) == "web-export-verification",
		"An exported route, gym, or League trainer should be repaired before spawning."
	)
	trainer.free()
	destination.free()


func _verify_cloud_save_runtime() -> void:
	var autosave := root.get_node_or_null(^"ProgressionAutosave")
	var cloud_sync := root.get_node_or_null(^"CloudSaveSync")
	var autosave_constants: Dictionary = {}
	if autosave != null and autosave.get_script() is Script:
		autosave_constants = (autosave.get_script() as Script).get_script_constant_map()
	_check(
		autosave != null and int(autosave_constants.get("SAVE_SCHEMA_VERSION", 0)) == 5,
		"The exported progression owner should use timestamped schema 5."
	)
	_check(
		cloud_sync != null
		and cloud_sync.has_method("enable_with_save_id")
		and cloud_sync.has_method("disable_cloud_sync")
		and cloud_sync.has_method("request_sync"),
		"The exported project should retain the optional cloud-save coordinator."
	)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
