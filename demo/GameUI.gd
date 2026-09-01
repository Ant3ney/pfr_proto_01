extends CanvasLayer

@onready var floating_joystick: Control = $FloatingJoystick
@onready var interaction_button: Button = $InteractionButton

var _interaction_detector: RNDPlayerInteractionDetector


func _ready() -> void:
	floating_joystick.input_changed.connect(
		PlayerController.set_floating_joystick_input
	)
	interaction_button.pressed.connect(_on_interaction_pressed)
	interaction_button.visible = false
	interaction_button.disabled = true
	_bind_interaction_detector.call_deferred()


func _exit_tree() -> void:
	PlayerController.set_floating_joystick_input(Vector2.ZERO)


func _unhandled_input(event: InputEvent) -> void:
	if interaction_button.visible and _is_interaction_event(event):
		get_viewport().set_input_as_handled()
		_on_interaction_pressed()


func _bind_interaction_detector() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return
	var player := _find_player_character(scene)
	if player == null:
		return
	_interaction_detector = player.get_node_or_null(
		^"LookInteraction"
	) as RNDPlayerInteractionDetector
	if _interaction_detector == null:
		return
	_interaction_detector.target_changed.connect(_on_interaction_target_changed)
	_on_interaction_target_changed(
		_interaction_detector.get_current_target(),
		_interaction_detector.get_current_prompt()
	)


func _on_interaction_target_changed(
	target: PFRCharacter,
	prompt_text: String
) -> void:
	var available := target != null and not prompt_text.strip_edges().is_empty()
	interaction_button.visible = available
	interaction_button.disabled = not available
	interaction_button.text = "%s   •   E / A" % prompt_text if available else "Interact"


func _on_interaction_pressed() -> void:
	if _interaction_detector == null:
		return
	if _interaction_detector.try_interact():
		interaction_button.visible = false
		interaction_button.disabled = true


func _find_player_character(root: Node) -> PlayerCharacter:
	if root is PlayerCharacter:
		return root as PlayerCharacter
	for child: Node in root.get_children():
		var player := _find_player_character(child)
		if player != null:
			return player
	return null


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
