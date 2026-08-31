extends SceneTree

const CITY_SCENE_PATH := "res://demo/primary_development_enviroment.tscn"
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
	await _verify_city_trainers()
	_verify_destination_pre_spawn_repair()

	if _failures.is_empty():
		print("Web export trainer verification passed.")
		quit(0)
		return
	for failure in _failures:
		push_error("Web export trainer verification failed: %s" % failure)
	quit(1)


func _verify_city_trainers() -> void:
	var packed_city := load(CITY_SCENE_PATH) as PackedScene
	_check(packed_city != null, "The exported city scene should load.")
	if packed_city == null:
		return

	var city := packed_city.instantiate()
	root.add_child(city)
	await process_frame
	await physics_frame
	var player := city.get_node_or_null(^"Player") as Node3D
	_check(player != null, "The exported city should contain its player.")

	var sight_trainer: Node3D
	var sight_behavior: Resource
	for trainer_name in TRAINER_NAMES:
		var trainer := city.get_node_or_null(NodePath(trainer_name)) as Node3D
		var controller := trainer.get("controller") as Resource if trainer != null else null
		var behavior := controller.get("npc_behavior") as Resource if controller != null else null
		_check(trainer != null, "The exported city should contain %s." % trainer_name)
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
			"An exported city trainer should detect a player in its sight line."
		)

	var game_instance := root.get_node_or_null(^"GameInstance")
	if game_instance != null:
		game_instance.call("set_player_movement_enabled", true)
	city.free()


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


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
