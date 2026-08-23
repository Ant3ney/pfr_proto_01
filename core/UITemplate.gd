class_name UITemplate
extends Control

## Reusable popup returned by UIManager.show_ui().

signal action_pressed
signal dismissed

@onready var message_label: Label = %Message
@onready var speaker_panel: PanelContainer = %SpeakerPanel
@onready var speaker_label: Label = %Speaker
@onready var action_button: Button = %ActionButton
@onready var dismiss_button: Button = %DismissButton

var _text := ""
var _speaker_name := ""
var _action_text := "Next"
var _dismiss_text := "Close"
var _action_enabled := true
var _dismiss_visible := false
var _action_callback := Callable()
var _dismiss_callback := Callable()
var _is_closing := false


func _ready() -> void:
	message_label.text = _text
	speaker_label.text = _speaker_name
	speaker_panel.visible = not _speaker_name.is_empty()
	action_button.text = _get_action_button_text()
	action_button.disabled = not _action_enabled
	dismiss_button.text = _dismiss_text
	dismiss_button.visible = _dismiss_visible
	action_button.pressed.connect(_on_action_pressed)
	dismiss_button.pressed.connect(close)
	action_button.grab_focus()


func set_text(text: String) -> UITemplate:
	_text = text
	if is_instance_valid(message_label):
		message_label.text = _text
	return self


func set_speaker_name(speaker_name: String) -> UITemplate:
	_speaker_name = speaker_name
	if is_instance_valid(speaker_label):
		speaker_label.text = _speaker_name
	if is_instance_valid(speaker_panel):
		speaker_panel.visible = not _speaker_name.is_empty()
	return self


func set_action_text(text: String) -> UITemplate:
	_action_text = text
	if is_instance_valid(action_button):
		action_button.text = _get_action_button_text()
	return self


func set_dismiss_text(text: String) -> UITemplate:
	_dismiss_text = text
	if is_instance_valid(dismiss_button):
		dismiss_button.text = _dismiss_text
	return self


func set_action_callback(callback: Callable) -> UITemplate:
	_action_callback = callback
	return self


func set_dismiss_callback(callback: Callable) -> UITemplate:
	_dismiss_callback = callback
	return self


func set_action_enabled(is_enabled: bool) -> UITemplate:
	_action_enabled = is_enabled
	if is_instance_valid(action_button):
		action_button.disabled = not is_enabled
	return self


func set_dismiss_visible(is_visible: bool) -> UITemplate:
	_dismiss_visible = is_visible
	if is_instance_valid(dismiss_button):
		dismiss_button.visible = _dismiss_visible
	return self


func close() -> void:
	if _is_closing:
		return

	_is_closing = true
	dismissed.emit()
	if _dismiss_callback.is_valid():
		_dismiss_callback.call()
	queue_free()


func _on_action_pressed() -> void:
	action_pressed.emit()
	if _action_callback.is_valid():
		_action_callback.call()


func _get_action_button_text() -> String:
	return "%s   ➜" % _action_text
