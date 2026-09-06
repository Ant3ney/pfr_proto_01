class_name PlayerCamera
extends Camera3D

@export_group("Target")
@export_node_path("Node3D") var target_path: NodePath

@export_group("Camera")
@export var offset := Vector3(0.0, 10.5, 8.5)
@export_range(1.0, 40.0, 0.1, "suffix:m") var camera_distance := 4.5
@export_range(-89.0, 89.0, 1.0, "degrees") var camera_pitch_degrees := 12
@export_range(10.0, 120.0, 1.0, "degrees") var camera_fov_degrees := 55.0:
	set(value):
		camera_fov_degrees = value
		fov = value
@export var look_height := 0.65

@onready var _target_node := get_node_or_null(target_path) as Node3D


func _ready() -> void:
	if _target_node:
		_update_position()
		_update_look_direction()


func _process(_delta: float) -> void:
	if not _target_node:
		return

	_update_position()
	_update_look_direction()


func _update_position() -> void:
	var offset_direction := offset.normalized()
	if offset_direction.is_zero_approx():
		offset_direction = Vector3.BACK

	var angled_offset := offset_direction.rotated(
		Vector3.RIGHT,
		deg_to_rad(camera_pitch_degrees)
	) * camera_distance
	global_position = _target_node.global_position + angled_offset


func _update_look_direction() -> void:
	look_at(_target_node.global_position + Vector3.UP * look_height, Vector3.UP)
