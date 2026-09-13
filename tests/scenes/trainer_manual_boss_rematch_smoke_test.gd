extends Node

const SIGHT_OBSERVATION_FRAMES := 90
const MAXIMUM_IDLE_HORIZONTAL_DRIFT := 0.05
const INTERACTION_OFFSET := Vector3(0.0, 0.0, 2.0)

var _failures: Array[String] = []

@onready var gym: PFRWorldLevel = $Gym01


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameInstance.reset_profile_transient_progress()
	GameInstance.set_player_movement_enabled(true)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)

	var player := gym.get_node_or_null(^"Player") as PlayerCharacter
	var trainer := gym.get_node_or_null(
		^"Gameplay/Actors/Leader Petra"
	) as PFRCharacter
	var controller := trainer.controller as TrainerController if trainer != null else null
	var behavior := controller.npc_behavior as TrainerBehavior if controller != null else null
	var detector := (
		player.get_node_or_null(^"LookInteraction") as PlayerInteractionDetector
		if player != null
		else null
	)
	_check(player != null, "Gym 1 should contain its inherited player.")
	_check(trainer != null, "Gym 1 should contain Leader Petra.")
	_check(detector != null, "The gym player should own the shared interaction detector.")
	_check(
		controller != null and behavior != null,
		"Leader Petra should have the shared trainer controller and behavior."
	)
	if (
		player == null
		or trainer == null
		or detector == null
		or controller == null
		or behavior == null
	):
		_finish()
		return

	_check(
		not controller.automatic_sight_encounter
		and not behavior.automatic_sight_encounter,
		"Leader Petra should be configured for manual interaction only."
	)
	var trainer_start := trainer.global_position
	for _frame in range(SIGHT_OBSERVATION_FRAMES):
		await get_tree().physics_frame
	var horizontal_drift := Vector2(
		trainer.global_position.x - trainer_start.x,
		trainer.global_position.z - trainer_start.z
	).length()
	_check(
		horizontal_drift <= MAXIMUM_IDLE_HORIZONTAL_DRIFT,
		"Leader Petra should not approach a player standing in her sight lane."
	)
	_check(
		behavior._approach_state == TrainerBehavior.ApproachState.WAITING,
		"Leader Petra should remain waiting until the player talks to her."
	)
	_check(
		not is_instance_valid(behavior._dialog_template),
		"Manual-only boss dialog should not open from sight detection."
	)
	_check(
		GameInstance.is_player_movement_enabled(),
		"Waiting in a boss sight lane should not lock player movement."
	)

	# Reproduce the one-scene suppression retained after returning from this
	# encounter. A manual Highly Aggro boss must remain waiting for a rematch.
	GameInstance.set("_one_scene_suppression_id", controller.encounter_id)
	GameInstance.set(
		"_suppression_scene_instance_id",
		get_tree().current_scene.get_instance_id()
	)
	behavior._suppression_checked = false
	_check(
		GameInstance.is_encounter_suppressed(controller.encounter_id),
		"The fixture should reproduce the immediate post-battle suppression window."
	)
	_check(
		trainer.can_interact(player),
		"A returned manual-only boss should remain available for a rematch."
	)
	_check(
		behavior._approach_state == TrainerBehavior.ApproachState.WAITING,
		"Post-battle suppression should leave a manual-only boss waiting."
	)
	var automatic_behavior := TrainerBehavior.new()
	automatic_behavior.aggression_mode = TrainerBehavior.AggressionMode.HIGHLY_AGGRO
	automatic_behavior.automatic_sight_encounter = true
	automatic_behavior.encounter_id = controller.encounter_id
	automatic_behavior._apply_encounter_suppression(
		trainer,
		NPCController.new()
	)
	_check(
		automatic_behavior._approach_state
		== TrainerBehavior.ApproachState.COMPLETE,
		"Automatic Highly Aggro trainers should retain immediate-return loop protection."
	)

	player.global_position = trainer.global_position + INTERACTION_OFFSET
	var player_visual := player.get_node_or_null(^"Visual") as Node3D
	if player_visual != null:
		var look_target := trainer.global_position
		look_target.y = player_visual.global_position.y
		player_visual.look_at(look_target, Vector3.UP)
	for _frame in range(4):
		await get_tree().physics_frame

	_check(
		detector.get_current_target() == trainer,
		"Looking at Leader Petra nearby should select her for manual interaction."
	)
	_check(
		detector.get_current_prompt() == "Talk to Leader Petra",
		"The interaction prompt should invite the player to talk to Leader Petra."
	)
	_check(
		detector.try_interact(),
		"The shared interaction action should start Leader Petra's dialog."
	)
	var dialog_template := behavior._dialog_template
	_check(
		is_instance_valid(dialog_template),
		"Talking to Leader Petra should open her authored dialog."
	)
	_check(
		not GameInstance.is_player_movement_enabled(),
		"Boss dialog should own the player movement lock."
	)
	if not is_instance_valid(dialog_template):
		_finish()
		return

	_check(
		dialog_template.speaker_label.text == "Leader Petra",
		"The manual dialog should identify Leader Petra."
	)
	_check(
		dialog_template.message_label.text == controller.dialog.dialog_lines[0],
		"The manual dialog should display Petra's authored line."
	)

	behavior._advance_dialog()
	_check(
		GameInstance.is_battle_start_in_progress(),
		"Advancing Petra's final dialog line should start the configured battle."
	)
	var pending_data := GameInstance.get_pending_battle_data()
	_check(
		pending_data.get("encounter_id") == "gym-01-leader",
		"Manual interaction should launch Petra's gym encounter."
	)
	_check(
		pending_data.get("trainer_name") == "Leader Petra",
		"Manual interaction should hand Petra's name to battle start."
	)
	_check(
		int(pending_data.get("trainer_aggression_mode", -1))
		== TrainerBehavior.AggressionMode.HIGHLY_AGGRO,
		"Boss rematches should preserve Highly Aggro challenge identity."
	)
	_check(
		not GameInstance.is_player_movement_enabled(),
		"The battle transition should take over the player movement lock."
	)

	_finish()


func _finish() -> void:
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	if _failures.is_empty():
		print(
			"Trainer manual boss rematch smoke test passed: Gym 1 waits for "
			+ "talk, launches dialog and battle manually, and remains rematchable "
			+ "during post-battle suppression."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Trainer manual boss rematch smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
