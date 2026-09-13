@tool
class_name RouteTravelTrigger
extends SceneTransferTrigger

## Walking between connected routes keeps the journey's trainer victories.
## Menu travel continues to start a fresh run through launch_area's defaults.

@export var destination_area_id := ""
@export var completion_gate_path: NodePath


func _on_body_entered(body: Node3D) -> void:
	if not enabled or _transfer_requested or not body is PlayerCharacter:
		return
	# Keep monitoring during validation so a sealed exit only retries after
	# the player leaves and enters again, rather than toggling overlap each frame.
	_transfer_requested = true
	call_deferred("_request_scene_transfer")


func _request_scene_transfer() -> void:
	if (
		GameInstance.is_scene_transfer_in_progress()
		or GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
	):
		_reset_after_rejected_transfer()
		return
	if not completion_gate_path.is_empty():
		var gate := get_node_or_null(completion_gate_path) as RouteCompletionGate
		if gate == null or not bool(gate.attempt_completion().get("ok", false)):
			_reset_after_rejected_transfer()
			return
	if destination_area_id.is_empty():
		super._request_scene_transfer()
		return
	if not ChallengeProgressionSystem.launch_area(
		destination_area_id, destination_spawn_marker, true
	):
		_reset_after_rejected_transfer()
		return
	var failure_callback := Callable(self, "_on_scene_transfer_failed")
	if not GameInstance.scene_transfer_failed.is_connected(failure_callback):
		GameInstance.scene_transfer_failed.connect(failure_callback)
	transfer_requested.emit(destination_scene_path, destination_spawn_marker)
