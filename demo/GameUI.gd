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

var _web_bridge: Object
var _web_state_check_elapsed := 0.0


func _ready() -> void:
	fullscreen_button.pressed.connect(_toggle_fullscreen)
	floating_joystick.input_changed.connect(
		PlayerController.set_floating_joystick_input
	)

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
