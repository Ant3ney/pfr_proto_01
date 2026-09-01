class_name PFRCharacter
extends CharacterBody3D

## Reusable character locomotion and behavior composition. The controller owns
## movement/navigation state while the optional NPC behavior owns gameplay.

@export_group("Movement")
@export var character_movement: CharacterMovement = CharacterMovement.new()

@export_group("Movement & Navigation")
@export var controller: NPCController = NPCController.new():
	set(value):
		controller = value
		if controller == null:
			return
		if npc_behavior == null and controller.npc_behavior != null:
			# Adopt scenes serialized with behavior nested in their controller.
			npc_behavior = controller.npc_behavior
		else:
			_sync_behavior_to_controller()

@export_group("NPC Behavior")
## Optional gameplay behavior composed directly onto this character.
## Assign TownNpcBehavior, TrainerBehavior, PokemonCenterHealerBehavior, or any
## other NPCBehavior subclass here. Player characters normally leave it empty.
@export var npc_behavior: NPCBehavior:
	set(value):
		npc_behavior = value
		_sync_behavior_to_controller()

@export_group("Character Art")
@export var character_art_asset_pack: PFRCharacterArtAssetPack

@export_group("Animation")
@export_range(0.0, 1.0, 0.01) var animation_blend_time := 0.15

var visual: Node3D
var character_art: Node3D
var animation_player: AnimationPlayer

var _idle_playback_animation: StringName
var _run_playback_animation: StringName
var _current_animation: StringName


func _ready() -> void:
	add_to_group(&"pfr_characters")
	prepare_runtime_composition()

	if not _load_character_art_asset_pack():
		set_physics_process(false)
		return

	if not _prepare_animation_library():
		set_physics_process(false)
		return

	_play_animation(_idle_playback_animation)


func can_interact(interactor: PlayerCharacter) -> bool:
	return (
		npc_behavior != null
		and controller != null
		and npc_behavior.can_interact(self, controller, interactor)
	)


func interact(interactor: PlayerCharacter) -> bool:
	if npc_behavior == null or controller == null:
		return false
	if not npc_behavior.can_interact(self, controller, interactor):
		return false
	return npc_behavior.interact(self, controller, interactor)


func get_interaction_prompt(interactor: PlayerCharacter) -> String:
	if npc_behavior == null or controller == null:
		return ""
	return npc_behavior.get_interaction_prompt(self, controller, interactor)


func _physics_process(delta: float) -> void:
	if npc_behavior != null:
		npc_behavior.process_behavior(self, controller)
	character_movement.process_movement(
		self,
		visual,
		controller.get_move_target(self),
		delta
	)
	_update_animation()


## Resolves direct authoring and the serialized pre-composition controller
## format before runtime code inspects this character. Runtime spawners may call
## this before adding a character to the tree.
func prepare_runtime_composition() -> void:
	if not character_movement:
		character_movement = CharacterMovement.new()
	if not controller:
		controller = NPCController.new()

	controller.prepare_for_character(self)
	if npc_behavior == null and controller.npc_behavior != null:
		# Compatibility for scenes saved before behavior moved onto PFRCharacter.
		npc_behavior = controller.npc_behavior
	else:
		_sync_behavior_to_controller()


func _sync_behavior_to_controller() -> void:
	if controller != null:
		# Kept as a serialized compatibility mirror for older scenes and scripts.
		controller.npc_behavior = npc_behavior


func _load_character_art_asset_pack() -> bool:
	if not character_art_asset_pack:
		push_error("%s requires a character art asset pack." % name)
		return false

	var validation_error := character_art_asset_pack.get_validation_error()
	if not validation_error.is_empty():
		push_error("%s has an invalid character art asset pack: %s" % [
			name,
			validation_error,
		])
		return false

	visual = get_node_or_null(^"Visual") as Node3D
	if not visual:
		visual = Node3D.new()
		visual.name = "Visual"
		add_child(visual)

	character_art = visual.get_node_or_null(^"CharacterArt") as Node3D
	if not character_art:
		var art_instance := character_art_asset_pack.character_scene.instantiate()
		if not art_instance is Node3D:
			push_error("%s's character art scene must have a Node3D root." % name)
			art_instance.free()
			return false

		character_art = art_instance as Node3D
		visual.add_child(character_art)

	character_art.name = "CharacterArt"
	character_art.rotation_degrees = (
		character_art_asset_pack.character_scene_rotation_degrees
	)

	animation_player = character_art.get_node_or_null(
		character_art_asset_pack.animation_player_path
	) as AnimationPlayer
	if not animation_player:
		push_error(
			"%s's character art pack does not contain the required AnimationPlayer at '%s'."
			% [name, character_art_asset_pack.animation_player_path]
		)
		return false

	return true


func _prepare_animation_library() -> bool:
	var idle_clip := _duplicate_without_root_motion(
		character_art_asset_pack.idle_animation
	)
	var run_clip := _duplicate_without_root_motion(
		character_art_asset_pack.run_animation
	)
	if not idle_clip or not run_clip:
		return false

	var locomotion_library := AnimationLibrary.new()
	locomotion_library.add_animation(&"idle", idle_clip)
	locomotion_library.add_animation(&"run", run_clip)
	_idle_playback_animation = &"locomotion/idle"
	_run_playback_animation = &"locomotion/run"

	if animation_player.has_animation_library(&"locomotion"):
		animation_player.remove_animation_library(&"locomotion")
	animation_player.add_animation_library(&"locomotion", locomotion_library)
	return true


func _duplicate_without_root_motion(animation_name: StringName) -> Animation:
	if not animation_player.has_animation(animation_name):
		push_error(
			"%s's character art pack is missing animation '%s'."
			% [name, animation_name]
		)
		return null

	var animation := animation_player.get_animation(animation_name).duplicate(true) as Animation
	for track_index in range(animation.get_track_count() - 1, -1, -1):
		var track_path := animation.track_get_path(track_index)
		var targets_root_motion := (
			animation.track_get_type(track_index) == Animation.TYPE_POSITION_3D
			and track_path.get_subname_count() > 0
			and track_path.get_subname(track_path.get_subname_count() - 1)
				== character_art_asset_pack.root_motion_bone
		)
		if targets_root_motion:
			animation.remove_track(track_index)

	return animation


func _update_animation() -> void:
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var desired_animation := (
		_run_playback_animation
		if horizontal_speed > 0.05
		else _idle_playback_animation
	)
	_play_animation(desired_animation)


func _play_animation(animation_name: StringName) -> void:
	if animation_name.is_empty() or animation_name == _current_animation:
		return

	animation_player.play(animation_name, animation_blend_time)
	_current_animation = animation_name
