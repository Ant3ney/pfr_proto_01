class_name RouteCompletionGate
extends Area3D

## Physical far-end checkpoint shared by all authored route scenes. Winning
## the last fight is insufficient: the player must touch this goal before the
## next route appears in the Adventure Menu.

signal completion_attempted(result: Dictionary)

@export_range(0, 39, 1) var route_index := 0

@onready var _label: Label3D = $RouteEndLabel

var _resolved := false


func _ready() -> void:
	_update_label("ROUTE %d END" % route_index)
	if Engine.is_editor_hint():
		return
	body_entered.connect(_on_body_entered)


func configure(index: int) -> void:
	route_index = clampi(index, 0, StandaloneAreaCatalog.ROUTE_COUNT - 1)
	if is_instance_valid(_label):
		_update_label("ROUTE %d END" % route_index)


func attempt_completion() -> Dictionary:
	var result := ChallengeProgressionSystem.complete_route_at_end(route_index)
	if bool(result.get("ok", false)):
		_resolved = true
		monitoring = false
		var next_route := int(result.get("next_route", -1))
		_update_label(
			"ALL 40 ROUTES COMPLETE"
			if next_route < 0
			else "ROUTE %d COMPLETE • ROUTE %d UNLOCKED" % [route_index, next_route]
		)
	else:
		_update_label("ROUTE %d SEALED • DEFEAT EVERY TRAINER" % route_index)
	completion_attempted.emit(result.duplicate(true))
	return result


func is_resolved() -> bool:
	return _resolved


func _on_body_entered(body: Node3D) -> void:
	if _resolved or not body is PlayerCharacter:
		return
	attempt_completion()


func _update_label(value: String) -> void:
	if is_instance_valid(_label):
		_label.text = value
