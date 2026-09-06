extends Node

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	GameInstance.set_player_movement_enabled(false)
	var empty_behavior := TrainerBehavior.new()
	empty_behavior._start_dialog()
	_check(
		GameInstance.is_player_movement_enabled(),
		"An absent trainer dialog should restore movement."
	)
	_check(
		not GameInstance.is_battle_start_in_progress(),
		"An absent trainer dialog should not start a battle."
	)

	var trainer_dialog := Dialog.new()
	trainer_dialog.character_name = "Trainer Kyle"
	trainer_dialog.dialog_lines = ["Show me what you and your partner can do!"]
	var trainer_behavior := TrainerBehavior.new()
	trainer_behavior.dialog = trainer_dialog
	trainer_behavior._start_dialog()
	_check(
		not GameInstance.is_player_movement_enabled(),
		"Trainer dialog should hold the movement lock."
	)

	trainer_behavior._advance_dialog()
	_check(
		GameInstance.is_battle_start_in_progress(),
		"Advancing past the final trainer line should start a battle."
	)
	var pending_data := GameInstance.get_pending_battle_data()
	_check(
		pending_data.get("encounter_type") == "trainer",
		"The trainer dialog should launch a trainer encounter."
	)
	_check(
		pending_data.get("trainer_name") == "Trainer Kyle",
		"The trainer speaker name should be handed to the battle start."
	)
	_check(
		not GameInstance.is_player_movement_enabled(),
		"The battle start should immediately take over the movement lock."
	)

	await get_tree().process_frame
	_check(
		_ui_template_count() == 1,
		"The dialog should retire, leaving one battle-transition template."
	)

	if _failures.is_empty():
		print(
			"Trainer dialog battle-start smoke test passed: final-line handoff "
			+ "and empty-dialog cleanup verified."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Trainer dialog battle-start smoke test failed: %s" % failure)
	get_tree().quit(1)


func _ui_template_count() -> int:
	var count := 0
	for child in UIManager.get_children():
		if child is UITemplate:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
