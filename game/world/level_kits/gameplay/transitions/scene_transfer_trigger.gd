@tool
class_name SceneTransferTrigger
extends Area3D

## Reusable player-only volume that changes to an inspector-selected scene.
## A destination marker is optional; without one, the destination scene keeps
## its authored player position.

signal transfer_requested(destination_scene_path: String, destination_spawn_marker: StringName)

@export_group("Scene Transfer")
@export_file("*.tscn") var destination_scene_path := ""
@export var destination_spawn_marker: StringName = &""
@export var enabled := true

var _transfer_requested := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or _transfer_requested or not body is PlayerCharacter:
		return
	_transfer_requested = true
	set_deferred("monitoring", false)
	call_deferred("_request_scene_transfer")


func _request_scene_transfer() -> void:
	var normalized_path := destination_scene_path.strip_edges()
	if normalized_path.is_empty():
		push_warning("%s has no Destination Scene Path." % get_path())
		_reset_after_rejected_transfer()
		return
	if not GameInstance.transfer_to_scene(normalized_path, destination_spawn_marker):
		_reset_after_rejected_transfer()
		return
	var failure_callback := Callable(self, "_on_scene_transfer_failed")
	if not GameInstance.scene_transfer_failed.is_connected(failure_callback):
		GameInstance.scene_transfer_failed.connect(failure_callback)
	transfer_requested.emit(normalized_path, destination_spawn_marker)


func _reset_after_rejected_transfer() -> void:
	_transfer_requested = false
	set_deferred("monitoring", true)


func _on_scene_transfer_failed(_message: String) -> void:
	if is_inside_tree() and not GameInstance.is_scene_transfer_in_progress():
		_reset_after_rejected_transfer()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if destination_scene_path.strip_edges().is_empty():
		warnings.append("Choose a Destination Scene Path in the Scene Transfer inspector group.")
	var has_enabled_shape := false
	for node: Node in find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null and not collision_shape.disabled:
			has_enabled_shape = true
			break
	if not has_enabled_shape:
		warnings.append("Add an enabled CollisionShape3D so the player can enter this trigger.")
	return warnings
