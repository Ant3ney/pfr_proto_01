class_name FloatingJoystick
extends Control

## A touch-first joystick that appears wherever a valid press begins.
##
## This control listens globally while remaining click-through itself. Presses
## beginning over another interactive Control are left to that UI. One touch is
## tracked by index so additional fingers remain available to other controls.

signal input_changed(input_vector: Vector2)

@export_group("Input")
@export_range(0.0, 64.0, 1.0, "suffix:px") var dead_zone_radius := 14.0
@export_range(32.0, 160.0, 1.0, "suffix:px") var maximum_radius := 72.0
@export var enable_mouse_input := true

@export_group("Appearance")
@export_range(8.0, 64.0, 1.0, "suffix:px") var knob_radius := 27.0
@export var base_color := Color(0.035, 0.055, 0.09, 0.58)
@export var ring_color := Color(0.82, 0.92, 1.0, 0.78)
@export var dead_zone_color := Color(0.82, 0.92, 1.0, 0.24)
@export var knob_color := Color(0.85, 0.94, 1.0, 0.88)

var input_vector := Vector2.ZERO

var _active_touch_index := -1
var _mouse_is_active := false
var _center := Vector2.ZERO
var _pointer_position := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _exit_tree() -> void:
	_reset()


func _notification(what: int) -> void:
	if what in [
		NOTIFICATION_APPLICATION_FOCUS_OUT,
		NOTIFICATION_WM_WINDOW_FOCUS_OUT,
	]:
		_reset()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_handle_screen_drag(event as InputEventScreenDrag)
	elif enable_mouse_input and event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif enable_mouse_input and event is InputEventMouseMotion:
		_handle_mouse_motion(event as InputEventMouseMotion)


func _draw() -> void:
	if not _is_active():
		return

	var local_center := _screen_to_local(_center)
	var local_pointer := _screen_to_local(_pointer_position)
	var knob_offset := (local_pointer - local_center).limit_length(maximum_radius)

	draw_circle(local_center + Vector2(0.0, 3.0), maximum_radius + 7.0, Color(0, 0, 0, 0.24))
	draw_circle(local_center, maximum_radius, base_color)
	draw_arc(local_center, maximum_radius, 0.0, TAU, 64, ring_color, 3.0, true)
	if dead_zone_radius > 0.0:
		draw_arc(
			local_center,
			minf(dead_zone_radius, maximum_radius),
			0.0,
			TAU,
			32,
			dead_zone_color,
			2.0,
			true
		)

	var knob_center := local_center + knob_offset
	draw_circle(knob_center + Vector2(0.0, 3.0), knob_radius + 3.0, Color(0, 0, 0, 0.28))
	draw_circle(knob_center, knob_radius, knob_color)
	draw_arc(knob_center, knob_radius, 0.0, TAU, 40, ring_color, 2.0, true)


func _handle_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if _is_active() or _is_over_interactive_ui(event.position):
			return
		_active_touch_index = event.index
		_begin(event.position)
		get_viewport().set_input_as_handled()
	elif event.index == _active_touch_index:
		_reset()
		get_viewport().set_input_as_handled()


func _handle_screen_drag(event: InputEventScreenDrag) -> void:
	if event.index != _active_touch_index:
		return

	_update_pointer(event.position)
	get_viewport().set_input_as_handled()


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		if _is_active() or _is_over_interactive_ui(event.position):
			return
		_mouse_is_active = true
		_begin(event.position)
		get_viewport().set_input_as_handled()
	elif _mouse_is_active:
		_reset()
		get_viewport().set_input_as_handled()


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _mouse_is_active:
		return

	if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		_reset()
		return

	_update_pointer(event.position)
	get_viewport().set_input_as_handled()


func _begin(screen_position: Vector2) -> void:
	_center = screen_position
	_pointer_position = screen_position
	_set_input_vector(Vector2.ZERO)
	queue_redraw()


func _update_pointer(screen_position: Vector2) -> void:
	_pointer_position = screen_position
	var offset := _pointer_position - _center
	var distance := offset.length()
	var clamped_dead_zone := minf(dead_zone_radius, maximum_radius - 0.001)

	if distance <= clamped_dead_zone or distance <= 0.001:
		_set_input_vector(Vector2.ZERO)
	else:
		var usable_distance := maxf(maximum_radius - clamped_dead_zone, 0.001)
		var strength := clampf(
			(distance - clamped_dead_zone) / usable_distance,
			0.0,
			1.0
		)
		_set_input_vector(offset / distance * strength)

	queue_redraw()


func _reset() -> void:
	if not _is_active() and input_vector.is_zero_approx():
		return

	_active_touch_index = -1
	_mouse_is_active = false
	_center = Vector2.ZERO
	_pointer_position = Vector2.ZERO
	_set_input_vector(Vector2.ZERO)
	queue_redraw()


func _set_input_vector(value: Vector2) -> void:
	value = value.limit_length(1.0)
	if input_vector.is_equal_approx(value):
		return

	input_vector = value
	input_changed.emit(input_vector)


func _is_active() -> bool:
	return _active_touch_index >= 0 or _mouse_is_active


func _screen_to_local(screen_position: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * screen_position


func _is_over_interactive_ui(screen_position: Vector2) -> bool:
	return _node_contains_interactive_control(get_tree().root, screen_position)


func _node_contains_interactive_control(
	node: Node,
	screen_position: Vector2
) -> bool:
	for child in node.get_children():
		if child == self:
			continue

		if child is Control:
			var control := child as Control
			if (
				control.get_viewport() == get_viewport()
				and control.is_visible_in_tree()
				and control.mouse_filter != Control.MOUSE_FILTER_IGNORE
				and _control_contains_screen_position(control, screen_position)
			):
				return true

		if _node_contains_interactive_control(child, screen_position):
			return true

	return false


func _control_contains_screen_position(
	control: Control,
	screen_position: Vector2
) -> bool:
	var local_position := (
		control.get_global_transform_with_canvas().affine_inverse()
		* screen_position
	)
	return Rect2(Vector2.ZERO, control.size).has_point(local_position)
