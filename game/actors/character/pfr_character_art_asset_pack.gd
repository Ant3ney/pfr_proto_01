class_name PFRCharacterArtAssetPack
extends Resource

## The minimum visual and animation data required by PFRCharacter.

@export_group("Character Scene")
@export var character_scene: PackedScene
@export var character_scene_rotation_degrees := Vector3.ZERO

@export_group("Animations")
@export var animation_player_path: NodePath = ^"AnimationPlayer"
@export var idle_animation: StringName
@export var run_animation: StringName
@export var root_motion_bone: StringName = &"origin"


func get_validation_error() -> String:
	if not character_scene:
		return "A character scene is required."
	if animation_player_path.is_empty():
		return "An AnimationPlayer path is required."
	if idle_animation.is_empty():
		return "An idle animation is required."
	if run_animation.is_empty():
		return "A run animation is required."
	return ""
