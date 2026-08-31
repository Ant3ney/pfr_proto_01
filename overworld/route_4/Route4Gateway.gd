@tool
class_name Route4Gateway
extends Area3D

## Close-range, button-driven scene gateway. It supports keyboard, gamepad, and
## touch through the same visible interaction prompt.

signal interaction_became_available
signal interaction_became_unavailable
signal route_transfer_requested(destination_scene_path: String, destination_spawn_marker: StringName)

@export_group("Route Destination")
@export_file("*.tscn") var destination_scene_path := "res://overworld/route_4/route_4.tscn"
@export var destination_spawn_marker: StringName = &"Route4Start"
@export var interaction_text := "Enter Route 4"
@export var enabled := true

@onready var _interaction_prompt: CanvasLayer = $InteractionPrompt
@onready var _interaction_button: Button = $InteractionPrompt/PromptMargin/PromptPanel/PromptPadding/InteractionButton

var _nearby_player: PlayerCharacter
var _transfer_requested := false


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_interaction_button.pressed.connect(interact)
	_update_prompt()
	set_process_unhandled_input(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_interaction_event(event):
		return
	get_viewport().set_input_as_handled()
	interact()


## Activates only while a PlayerCharacter is inside the interaction radius.
func interact() -> bool:
	if (
		not enabled
		or _transfer_requested
		or not is_instance_valid(_nearby_player)
		or GameInstance.is_scene_transfer_in_progress()
		or GameInstance.is_battle_start_in_progress()
		or GameInstance.is_battle_return_in_progress()
	):
		return false

	var normalized_path := destination_scene_path.strip_edges()
	if normalized_path.is_empty() or not ResourceLoader.exists(normalized_path, "PackedScene"):
		push_warning("%s cannot open missing Route 4 scene: %s" % [get_path(), normalized_path])
		return false

	_transfer_requested = true
	_update_prompt()
	set_process_unhandled_input(false)
	if not GameInstance.transfer_to_scene(normalized_path, destination_spawn_marker):
		_transfer_requested = false
		_update_prompt()
		set_process_unhandled_input(is_instance_valid(_nearby_player))
		return false
	route_transfer_requested.emit(normalized_path, destination_spawn_marker)
	return true


func is_player_in_interaction_range() -> bool:
	return is_instance_valid(_nearby_player)


func _on_body_entered(body: Node3D) -> void:
	if not enabled or _transfer_requested or not body is PlayerCharacter:
		return
	_nearby_player = body as PlayerCharacter
	_update_prompt()
	set_process_unhandled_input(true)
	interaction_became_available.emit()


func _on_body_exited(body: Node3D) -> void:
	if body != _nearby_player:
		return
	_nearby_player = null
	_update_prompt()
	set_process_unhandled_input(false)
	interaction_became_unavailable.emit()


func _update_prompt() -> void:
	if not is_instance_valid(_interaction_prompt) or not is_instance_valid(_interaction_button):
		return
	var available := enabled and is_instance_valid(_nearby_player) and not _transfer_requested
	_interaction_prompt.visible = available or _transfer_requested
	_interaction_button.disabled = not available
	_interaction_button.text = (
		"Traveling to Route 4..."
		if _transfer_requested
		else "%s   •   E / A" % interaction_text.strip_edges()
	)


func _is_interaction_event(event: InputEvent) -> bool:
	if not event.is_pressed():
		return false
	if event is InputEventKey:
		var key_event := event as InputEventKey
		return (
			not key_event.echo
			and key_event.keycode in [KEY_E, KEY_ENTER, KEY_SPACE]
		)
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).button_index == JOY_BUTTON_A
	return false


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var normalized_path := destination_scene_path.strip_edges()
	if normalized_path.is_empty():
		warnings.append("Choose the Route 4 destination scene.")
	elif not ResourceLoader.exists(normalized_path, "PackedScene"):
		warnings.append("The configured Route 4 destination scene does not exist.")
	var has_enabled_shape := false
	for node: Node in find_children("*", "CollisionShape3D", true, false):
		var collision_shape := node as CollisionShape3D
		if collision_shape != null and collision_shape.shape != null and not collision_shape.disabled:
			has_enabled_shape = true
			break
	if not has_enabled_shape:
		warnings.append("Add an enabled interaction CollisionShape3D.")
	return warnings
