class_name PokemonCenterHealerBehavior
extends NPCBehavior

## Stationary Pokemon Center attendant behavior. Entering the authored desk
## interaction area opens one touch-friendly confirmation sequence. The player
## must leave and re-enter the area before the prompt can open again.

signal healing_sequence_started
signal party_healed(restored_count: int)
signal healing_sequence_finished

enum SequenceState {
	IDLE,
	CONFIRMING,
	RESULT,
}

@export_group("Interaction")
@export_node_path("Area3D") var interaction_area_path := NodePath("InteractionArea")
## Existing scenes can retain proximity prompting; RND-authored attendants can
## disable it and wait for the shared look/interact HUD instead.
@export var automatic_proximity_prompt := true

@export_group("Dialog")
@export var speaker_name := "Center Attendant"
@export_multiline var prompt_text := (
	"Welcome! Would you like me to restore your Pokemon to full health?"
)
@export_multiline var healed_text := (
	"All done! Your Pokemon are back to full health."
)
@export_multiline var already_healthy_text := (
	"Your Pokemon are already in perfect health."
)
@export_multiline var empty_party_text := (
	"You don't have any Pokemon with you yet. Come back when you do."
)
@export var heal_action_text := "Heal"
@export var decline_action_text := "Not now"
@export var completion_action_text := "Done"

var _sequence_state := SequenceState.IDLE
var _dialog_template: UITemplate
var _interaction_area: Area3D
var _player_was_in_range := false
var _owns_movement_lock := false


func process_behavior(
	character: CharacterBody3D,
	_controller: NPCController
) -> void:
	if not automatic_proximity_prompt:
		return
	var player_is_in_range := _find_player_in_range(character) != null
	if not player_is_in_range:
		_player_was_in_range = false
		return
	if _player_was_in_range:
		return

	_player_was_in_range = true
	start_healing_sequence()


func can_interact(
	_character: CharacterBody3D,
	_controller: NPCController,
	interactor: PlayerCharacter
) -> bool:
	return (
		interactor != null
		and _sequence_state == SequenceState.IDLE
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
	return start_healing_sequence()


func get_interaction_prompt(
	_character: CharacterBody3D,
	_controller: NPCController,
	_interactor: PlayerCharacter
) -> String:
	return "Talk to %s" % speaker_name.strip_edges()


## Public entry point for this behavior and a future generic Interaction
## dispatcher. Returns false when another sequence owns player movement or this
## attendant already owns an active dialog.
func start_healing_sequence() -> bool:
	if _sequence_state != SequenceState.IDLE:
		return false
	if is_instance_valid(_dialog_template):
		return false
	if not GameInstance.is_player_movement_enabled():
		return false

	GameInstance.set_player_movement_enabled(false)
	_owns_movement_lock = true
	healing_sequence_started.emit()

	var has_party := CollectionSystem.get_party_size() > 0
	_sequence_state = SequenceState.CONFIRMING if has_party else SequenceState.RESULT
	var initial_text := prompt_text if has_party else empty_party_text
	_dialog_template = UIManager.show_ui(initial_text)
	if not _dialog_template:
		_finish_healing_sequence()
		return false

	_dialog_template.set_speaker_name(speaker_name)
	_dialog_template.set_action_callback(_advance_healing_sequence)
	_dialog_template.set_dismiss_callback(_finish_healing_sequence)
	if has_party:
		_dialog_template.set_action_text(heal_action_text)
		_dialog_template.set_dismiss_text(decline_action_text)
		_dialog_template.set_dismiss_visible(true)
	else:
		_dialog_template.set_action_text(completion_action_text)
		_dialog_template.set_dismiss_visible(false)
	return true


func is_healing_sequence_active() -> bool:
	return _sequence_state != SequenceState.IDLE


func cancel_healing_sequence() -> void:
	if is_instance_valid(_dialog_template):
		_dialog_template.close()
	else:
		_finish_healing_sequence()


func _advance_healing_sequence() -> void:
	if not is_instance_valid(_dialog_template):
		_finish_healing_sequence()
		return

	if _sequence_state == SequenceState.CONFIRMING:
		var restored_count := CollectionSystem.heal_party()
		party_healed.emit(restored_count)
		_sequence_state = SequenceState.RESULT
		_dialog_template.set_text(
			healed_text if restored_count > 0 else already_healthy_text
		)
		_dialog_template.set_action_text(completion_action_text)
		_dialog_template.set_dismiss_visible(false)
		return

	_dialog_template.close()


func _finish_healing_sequence() -> void:
	var had_active_sequence := _sequence_state != SequenceState.IDLE
	_sequence_state = SequenceState.IDLE
	_dialog_template = null
	if _owns_movement_lock:
		_owns_movement_lock = false
		GameInstance.set_player_movement_enabled(true)
	if had_active_sequence:
		healing_sequence_finished.emit()


func _find_player_in_range(character: CharacterBody3D) -> PlayerCharacter:
	if not is_instance_valid(_interaction_area):
		_interaction_area = character.get_node_or_null(interaction_area_path) as Area3D
	if not is_instance_valid(_interaction_area):
		return null

	for body: Node3D in _interaction_area.get_overlapping_bodies():
		if body is PlayerCharacter:
			return body as PlayerCharacter
	return null
