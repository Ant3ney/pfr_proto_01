extends Node3D

const PROTOTYPE_TRAINER_SCENES: Array[String] = [
	"res://game/actors/npcs/trainers/presets/trainer_delivery_worker.tscn",
	"res://game/actors/npcs/trainers/presets/trainer_police_officer.tscn",
	"res://game/actors/npcs/trainers/presets/trainer_businessman.tscn",
	"res://game/actors/npcs/trainers/presets/trainer_backpacker.tscn",
	"res://game/actors/npcs/trainers/presets/trainer_jogger.tscn",
	"res://game/actors/npcs/trainers/presets/trainer_tourist.tscn",
]

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	for _frame in range(4):
		await get_tree().physics_frame
	_check_prototype_trainers_keep_automatic_sight()

	var player := $Player as PlayerCharacter
	var trainer := $DeliveryWorker as PFRCharacter
	var police_officer := $PoliceOfficer as PFRCharacter
	var detector := player.get_node_or_null(
		^"LookInteraction"
	) as PlayerInteractionDetector
	var interaction_button := $Player/GameUI/InteractionButton as Button
	var trainer_behavior := trainer.controller.npc_behavior as TrainerBehavior
	var police_behavior := (
		police_officer.controller.npc_behavior as TrainerBehavior
	)

	_check(detector != null, "The shared player should own the interaction detector.")
	_check(
		trainer_behavior != null and trainer_behavior.automatic_sight_encounter,
		"Prototype trainers should retain automatic sight encounters."
	)
	_check(
		police_behavior != null and police_behavior.automatic_sight_encounter,
		"Every prototype trainer scene should inherit automatic sight encounters."
	)
	_check(
		detector != null and detector.get_current_target() == trainer,
		"A trainer approached from behind should remain available for optional talk."
	)
	_check(
		interaction_button.visible and not interaction_button.disabled,
		"The HUD interaction button should appear for the selected trainer."
	)
	_check(
		"Delivery Worker" in interaction_button.text,
		"The HUD should identify the selected trainer's action."
	)

	interaction_button.pressed.emit()
	await get_tree().process_frame
	_check(
		trainer_behavior != null
		and trainer_behavior._approach_state == TrainerBehavior.ApproachState.COMPLETE,
		"Pressing the HUD button should dispatch through the trainer behavior."
	)
	_check(
		not GameInstance.is_player_movement_enabled(),
		"Trainer dialog should own the player movement lock."
	)
	var dialog_template := _find_dialog_template()
	_check(dialog_template != null, "Trainer interaction should open its assigned dialog.")
	if dialog_template != null:
		dialog_template.close()
		await get_tree().process_frame
	_check(
		GameInstance.is_player_movement_enabled(),
		"Closing an unadvanced trainer dialog should restore movement."
	)

	player.global_position = Vector3(6.0, 0.0, 0.0)
	for _frame in range(3):
		await get_tree().physics_frame
	_check(
		police_behavior != null
		and police_behavior._approach_state == TrainerBehavior.ApproachState.COMPLETE,
		"Walking into a prototype trainer's forward sight line should force its sequence."
	)
	_check(
		not GameInstance.is_player_movement_enabled(),
		"Automatic trainer sight should lock player movement."
	)
	var automatic_dialog_template := _find_dialog_template()
	_check(
		automatic_dialog_template != null,
		"The forced sight encounter should open the trainer's assigned dialog."
	)
	if automatic_dialog_template != null:
		automatic_dialog_template.close()
		await get_tree().process_frame
	_check(
		GameInstance.is_player_movement_enabled(),
		"Closing the forced trainer dialog should restore movement during the test."
	)
	GameInstance.set_player_movement_enabled(true)

	if _failures.is_empty():
		print(
			"Interaction HUD smoke test passed: optional talk outside the sight "
			+ "line and forced trainer detection from the front verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Interaction HUD smoke test failed: %s" % failure)
	get_tree().quit(1)


func _find_dialog_template() -> UITemplate:
	for child: Node in UIManager.get_children():
		if child is UITemplate:
			return child as UITemplate
	return null


func _check_prototype_trainers_keep_automatic_sight() -> void:
	for scene_path in PROTOTYPE_TRAINER_SCENES:
		var packed_scene := load(scene_path) as PackedScene
		_check(packed_scene != null, "The prototype trainer scene should load: %s" % scene_path)
		if packed_scene == null:
			continue
		var scene_instance := packed_scene.instantiate()
		var prototype_trainer := scene_instance as PFRCharacter
		var behavior := (
			prototype_trainer.controller.npc_behavior as TrainerBehavior
			if prototype_trainer != null
			else null
		)
		_check(
			behavior != null and behavior.automatic_sight_encounter,
			"Prototype trainer should force forward-sight encounters: %s" % scene_path
		)
		scene_instance.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
