class_name TownNpcBehavior
extends NPCBehavior

## Repeatable, stationary town conversation owned by the NPC behavior.

signal conversation_started
signal conversation_finished

@export_group("Dialog")
@export var speaker_name := "Resident"
@export_multiline var dialog_lines: Array[String] = [
	"It's a good day for a walk around New Bouffalant City.",
]

@export_group("Optional One-Time Gift")
@export var gift_id := ""
@export var gift_item_key := ""
@export_multiline var gift_dialog_lines: Array[String] = []
@export_multiline var claimed_gift_dialog_lines: Array[String] = []

var _dialog_template: UITemplate
var _active_lines: Array[String] = []
var _line_index := 0
var _owns_movement_lock := false


func can_interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	return (
		interactor != null
		and _has_dialog()
		and not is_instance_valid(_dialog_template)
		and GameInstance.is_player_movement_enabled()
		and not GameInstance.is_battle_start_in_progress()
		and not GameInstance.is_battle_return_in_progress()
		and not GameInstance.is_scene_transfer_in_progress()
	)


func interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> bool:
	return start_conversation()


func get_interaction_prompt(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> String:
	var display_name := speaker_name.strip_edges()
	return "Talk" if display_name.is_empty() else "Talk to %s" % display_name


func start_conversation() -> bool:
	if is_instance_valid(_dialog_template) or not _has_dialog():
		return false
	if not GameInstance.is_player_movement_enabled():
		return false

	_active_lines.clear()
	for line in _resolved_dialog_lines():
		var normalized_line := line.strip_edges()
		if not normalized_line.is_empty():
			_active_lines.append(normalized_line)
	if _active_lines.is_empty():
		return false

	GameInstance.set_player_movement_enabled(false)
	_owns_movement_lock = true
	_line_index = 0
	_dialog_template = UIManager.show_ui(_active_lines[0])
	if not is_instance_valid(_dialog_template):
		_finish_conversation()
		return false

	_dialog_template.set_speaker_name(speaker_name)
	_dialog_template.set_action_text("Next" if _active_lines.size() > 1 else "Done")
	_dialog_template.set_action_callback(_advance_conversation)
	_dialog_template.set_dismiss_callback(_finish_conversation)
	_dialog_template.set_dismiss_visible(false)
	conversation_started.emit()
	return true


func is_conversation_active() -> bool:
	return is_instance_valid(_dialog_template)


func advance_conversation() -> void:
	_advance_conversation()


func cancel_conversation() -> void:
	if is_instance_valid(_dialog_template):
		_dialog_template.close()
	else:
		_finish_conversation()


func _advance_conversation() -> void:
	if not is_instance_valid(_dialog_template):
		_finish_conversation()
		return
	_line_index += 1
	if _line_index >= _active_lines.size():
		_dialog_template.close()
		return
	_dialog_template.set_text(_active_lines[_line_index])
	_dialog_template.set_action_text(
		"Done" if _line_index == _active_lines.size() - 1 else "Next"
	)


func _finish_conversation() -> void:
	var was_active := not _active_lines.is_empty() or is_instance_valid(_dialog_template)
	_dialog_template = null
	_active_lines.clear()
	_line_index = 0
	if _owns_movement_lock:
		_owns_movement_lock = false
		GameInstance.set_player_movement_enabled(true)
	if was_active:
		conversation_finished.emit()


func _has_dialog() -> bool:
	for line in dialog_lines + gift_dialog_lines + claimed_gift_dialog_lines:
		if not line.strip_edges().is_empty():
			return true
	return false


func _resolved_dialog_lines() -> Array[String]:
	if gift_id.strip_edges().is_empty() or gift_item_key.strip_edges().is_empty():
		return dialog_lines.duplicate()
	var result := StretchGoalSystem.claim_unique_item(gift_id, gift_item_key)
	if not bool(result.get("ok", false)):
		var failure_lines := dialog_lines.duplicate()
		failure_lines.append(
			"I couldn't hand over the item yet: %s"
			% String(result.get("error", "your bag is not ready"))
		)
		return failure_lines
	var summary := result.get("summary", {}) as Dictionary
	if bool(summary.get("newly_claimed", false)) and not gift_dialog_lines.is_empty():
		return gift_dialog_lines.duplicate()
	if not bool(summary.get("newly_claimed", false)) and not claimed_gift_dialog_lines.is_empty():
		return claimed_gift_dialog_lines.duplicate()
	return dialog_lines.duplicate()
