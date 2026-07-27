class_name PlayerCamera
extends Camera3D

@export_node_path("Node3D") var target_path: NodePath
@export var offset := Vector3(0.0, 10.5, 8.5)
@export var look_height := 0.65

@onready var _target_node := get_node_or_null(target_path) as Node3D


func _ready() -> void:
	if _target_node:
		global_position = _target_node.global_position + offset
		_update_look_direction()


func _process(_delta: float) -> void:
	if not _target_node:
		return

	global_position = _target_node.global_position + offset
	_update_look_direction()


func _update_look_direction() -> void:
	look_at(_target_node.global_position + Vector3.UP * look_height, Vector3.UP)
