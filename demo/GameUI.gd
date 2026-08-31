extends CanvasLayer

const WEB_FULLSCREEN_TOGGLE := """
(() => {
	const doc = document;
	const target = doc.documentElement;
	const active = doc.fullscreenElement
		|| doc.webkitFullscreenElement
		|| doc.webkitCurrentFullScreenElement
		|| doc.mozFullScreenElement
		|| doc.msFullscreenElement;

	if (active) {
		const exitFullscreen = doc.exitFullscreen
			|| doc.webkitExitFullscreen
			|| doc.webkitCancelFullScreen
			|| doc.mozCancelFullScreen
			|| doc.msExitFullscreen;
		if (typeof exitFullscreen !== 'function') {
			return 'unsupported';
		}
		try {
			const result = exitFullscreen.call(doc);
			if (result && typeof result.catch === 'function') {
				result.catch((err) => console.warn('Could not exit fullscreen:', err));
			}
			return 'exit_requested';
		} catch (err) {
			console.warn('Could not exit fullscreen:', err);
			return 'failed';
		}
	}

	const requestFullscreen = target.requestFullscreen
		|| target.webkitRequestFullscreen
		|| target.webkitRequestFullScreen
		|| target.mozRequestFullScreen
		|| target.msRequestFullscreen;
	if (typeof requestFullscreen !== 'function') {
		return 'unsupported';
	}
	try {
		const result = requestFullscreen.call(target);
		if (result && typeof result.catch === 'function') {
			result.catch((err) => console.warn('Could not enter fullscreen:', err));
		}
		return 'enter_requested';
	} catch (err) {
		console.warn('Could not enter fullscreen:', err);
		return 'failed';
	}
})()
"""

const WEB_FULLSCREEN_STATE := """
Boolean(
	document.fullscreenElement
	|| document.webkitFullscreenElement
	|| document.webkitCurrentFullScreenElement
	|| document.mozFullScreenElement
	|| document.msFullscreenElement
)
"""

@onready var fullscreen_button: Button = $FullscreenButton
@onready var fullscreen_help: AcceptDialog = $FullscreenHelp
@onready var floating_joystick: Control = $FloatingJoystick
@onready var interaction_button: Button = $InteractionButton

var _web_bridge: Object
var _web_state_check_elapsed := 0.0
var _interaction_detector: RNDPlayerInteractionDetector


func _ready() -> void:
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	floating_joystick.input_changed.connect(
		PlayerController.set_floating_joystick_input
	)
	interaction_button.pressed.connect(_on_interaction_pressed)
	interaction_button.visible = false
	interaction_button.disabled = true
	_bind_interaction_detector.call_deferred()

	if OS.has_feature("web") and Engine.has_singleton("JavaScriptBridge"):
		_web_bridge = Engine.get_singleton("JavaScriptBridge")

	_update_button()


func _exit_tree() -> void:
	PlayerController.set_floating_joystick_input(Vector2.ZERO)


func _process(delta: float) -> void:
	if not _web_bridge:
		return

	_web_state_check_elapsed += delta
	if _web_state_check_elapsed >= 0.25:
		_web_state_check_elapsed = 0.0
		_update_button()


func _toggle_fullscreen() -> void:
	if _web_bridge:
		var result := str(_web_bridge.eval(WEB_FULLSCREEN_TOGGLE, true))
		if result == "unsupported" or result == "failed":
			_show_web_fullscreen_help()
		elif result == "enter_requested":
			_verify_web_fullscreen.call_deferred()
		return

	var mode := DisplayServer.window_get_mode()
	if mode in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_button()


func _verify_web_fullscreen() -> void:
	await get_tree().create_timer(1.0).timeout
	if not _is_fullscreen():
		_show_web_fullscreen_help()


func _show_web_fullscreen_help() -> void:
	fullscreen_help.dialog_text = (
		"This browser does not allow page fullscreen here.\n\n"
		+ "On iPhone, open the page in Safari, tap Share, choose "
		+ "\"Add to Home Screen,\" then launch the game from its saved icon."
	)
	fullscreen_help.popup_centered(Vector2i(360, 220))


func _update_button() -> void:
	fullscreen_button.text = "Exit Fullscreen" if _is_fullscreen() else "Fullscreen"


func _is_fullscreen() -> bool:
	if _web_bridge:
		return bool(_web_bridge.eval(WEB_FULLSCREEN_STATE, true))

	return DisplayServer.window_get_mode() in [
		DisplayServer.WINDOW_MODE_FULLSCREEN,
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
	]


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
