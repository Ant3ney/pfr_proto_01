class_name BattleSpritePresenter
extends Node3D

## Scene-agnostic owner for both billboarded battle sprite actors.
##
## BattleScene supplies only authored spawn markers, member presentation data,
## and translated presentation events. This class chooses ani/ani-back, keeps
## the active atlas pair lazy, grounds every GIF frame by alpha bounds, and
## applies non-GIF motion on a separate root.

signal battler_presented(side: StringName, sprite_id: String, placeholder: bool)
signal battler_cleared(side: StringName)

class PresentationCompletion:
	extends RefCounted
	signal finished(completion_id: int)
	var completion_id := 0
	var side := &""
	var _remaining := 0
	var _completed := false

	func wait_for(completion: Signal) -> void:
		if _completed:
			return
		_remaining += 1
		completion.connect(_on_part_finished, CONNECT_ONE_SHOT)

	func complete() -> void:
		if _completed:
			return
		_completed = true
		finished.emit(completion_id)

	func _on_part_finished() -> void:
		if _completed:
			return
		_remaining -= 1
		if _remaining <= 0:
			complete()

const PLAYER_SIDE := &"player"
const OPPONENT_SIDE := &"opponent"
const IDLE_ANIMATION := &"idle"
const SpeciesMapping := preload("res://game/battle/system/battle_species_mapping.gd")
const SpriteScale := preload("res://game/battle/system/battle_sprite_scale.gd")
const HORIZONTAL_SAFE_INSET_PX := 16.0
const SWITCH_OUT_DURATION_S := 0.24
const SWITCH_IN_DURATION_S := 0.32
const HUD_GUTTER_MIN_PX := 16.0
const HUD_GUTTER_WIDTH_RATIO := 0.015
const OPPONENT_STATUS_WIDTH_RATIO := 0.26
const OPPONENT_STATUS_MIN_WIDTH_PX := 236.0
const OPPONENT_STATUS_MAX_WIDTH_PX := 288.0
const OPPONENT_STATUS_BOTTOM_PX := 70.0
const OPPONENT_STATUS_SPRITE_GAP_PX := 4.0

@export_range(0.05, 2.0, 0.05) var attack_lunge_m := 0.55
@export_range(0.01, 0.5, 0.01) var hit_shake_m := 0.13

var _catalog := BattleSpriteCatalog.new()
var _actors: Dictionary = {}
var _active_completions: Dictionary = {}
var _next_completion_id := 0


func _ready() -> void:
	if _catalog.catalog_summary().is_empty():
		_catalog.initialize()


func configure(
	player_spawn: Node3D,
	opponent_spawn: Node3D,
	player_shadow: Node3D = null,
	opponent_shadow: Node3D = null
) -> bool:
	if player_spawn == null or opponent_spawn == null:
		push_error("BattleSpritePresenter requires both authored spawn markers.")
		return false
	if _catalog.catalog_summary().is_empty() and not _catalog.initialize():
		return false
	_remove_actor(PLAYER_SIDE)
	_remove_actor(OPPONENT_SIDE)
	_actors[PLAYER_SIDE] = _create_actor(PLAYER_SIDE, player_spawn, player_shadow)
	_actors[OPPONENT_SIDE] = _create_actor(OPPONENT_SIDE, opponent_spawn, opponent_shadow)
	return true


func present_battlers(player_member: Dictionary, opponent_member: Dictionary) -> Dictionary:
	return {
		"player": _present_side(PLAYER_SIDE, player_member),
		"opponent": _present_side(OPPONENT_SIDE, opponent_member),
	}


func present_snapshot(snapshot: Dictionary) -> Dictionary:
	var parties_value: Variant = snapshot.get("parties", {})
	if typeof(parties_value) != TYPE_DICTIONARY:
		return present_battlers({}, {})
	var parties := parties_value as Dictionary
	return {
		"player": _present_snapshot_side(PLAYER_SIDE, _active_member(parties.get("player", []))),
		"opponent": _present_snapshot_side(OPPONENT_SIDE, _active_member(parties.get("opponent", []))),
	}


func play_event(event: Dictionary):
	var side := _normalized_side(event.get("side", ""))
	match String(event.get("type", "")):
		"attack":
			return play_attack(side)
		"damage":
			return play_hit(side)
		"heal", "status_cleared":
			return play_heal(side)
		"status":
			return play_status(side)
		"switch":
			return _play_switch_event(side)
		"knockout":
			var completion = play_faint(side)
			if _pending_side_is_clear(side):
				completion.connect(_commit_pending_side.bind(side), CONNECT_ONE_SHOT)
			return completion
	# Returning null lets BattleScene hold translated message/result/unknown
	# events for its normal readable fallback duration. Events with no message
	# remain a safe immediate no-op.
	return null if not String(event.get("message", "")).strip_edges().is_empty() else _instant_completion()


func play_attack(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var direction := -1.0 if side == PLAYER_SIDE else 1.0
	var lunge := Vector3(direction * attack_lunge_m, 0.08, -attack_lunge_m * 0.45)
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.tween_property(motion, ^"position", lunge, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(motion, ^"position", Vector3.ZERO, 0.20).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tween.finished


func play_hit(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.tween_property(motion, ^"position:x", -hit_shake_m, 0.045)
	tween.tween_property(motion, ^"position:x", hit_shake_m, 0.055)
	tween.tween_property(motion, ^"position:x", -hit_shake_m * 0.55, 0.055)
	tween.tween_property(motion, ^"position:x", 0.0, 0.085)
	var flash := create_tween()
	_register_tween(actor, flash)
	flash.tween_property(sprite, ^"modulate", Color(1.0, 0.25, 0.25, 1.0), 0.045)
	flash.tween_property(sprite, ^"modulate", Color.WHITE, 0.185)
	var completion := _new_completion(side)
	completion.wait_for(tween.finished)
	completion.wait_for(flash.finished)
	return completion.finished


func play_heal(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", 0.18, 0.18).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(motion, ^"scale", Vector3.ONE * 1.08, 0.18).set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, ^"modulate", Color(0.55, 1.0, 0.62, 1.0), 0.12)
	tween.chain().set_parallel(true)
	tween.tween_property(motion, ^"position:y", 0.0, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_property(motion, ^"scale", Vector3.ONE, 0.22).set_trans(Tween.TRANS_SINE)
	tween.tween_property(sprite, ^"modulate", Color.WHITE, 0.22)
	return tween.finished


func play_status(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var sprite := actor.sprite as AnimatedSprite3D
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.tween_property(sprite, ^"modulate", Color(0.72, 0.45, 0.92, 1.0), 0.11)
	tween.tween_property(sprite, ^"modulate", Color.WHITE, 0.21)
	return tween.finished


func play_switch_out(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	var shadow := actor.get("shadow") as Node3D
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", 0.55, SWITCH_OUT_DURATION_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(motion, ^"scale", Vector3.ONE * 0.15, SWITCH_OUT_DURATION_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, ^"modulate:a", 0.0, 0.20)
	if is_instance_valid(shadow):
		tween.tween_property(shadow, ^"scale", _collapsed_shadow_scale(actor), 0.22)
	return tween.finished


func play_switch_in(side: StringName, preserved_completion_id: int = -1):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side, preserved_completion_id)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	var shadow := actor.get("shadow") as Node3D
	motion.position.y = 0.55
	motion.scale = Vector3.ONE * 0.15
	sprite.modulate.a = 0.0
	sprite.visible = true
	if is_instance_valid(shadow):
		shadow.scale = _collapsed_shadow_scale(actor)
		shadow.visible = true
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", 0.0, SWITCH_IN_DURATION_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(motion, ^"scale", Vector3.ONE, SWITCH_IN_DURATION_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, ^"modulate:a", 1.0, 0.18)
	if is_instance_valid(shadow):
		tween.tween_property(shadow, ^"scale", actor.get("shadow_scale", Vector3.ONE), 0.26)
	return tween.finished


func play_faint(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	var shadow := actor.get("shadow") as Node3D
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", -0.32, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(motion, ^"scale", Vector3(1.08, 0.08, 1.08), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, ^"modulate:a", 0.0, 0.30).set_delay(0.08)
	if is_instance_valid(shadow):
		tween.tween_property(shadow, ^"scale", _collapsed_shadow_scale(actor), 0.34)
		tween.chain().tween_callback(func() -> void:
			if is_instance_valid(shadow):
				shadow.visible = false
		)
	return tween.finished


func clear_side(side: StringName) -> void:
	var normalized := _normalized_side(side)
	var actor := _actor(normalized)
	if actor.is_empty():
		return
	_reset_motion(normalized)
	var sprite := actor.sprite as AnimatedSprite3D
	sprite.stop()
	sprite.sprite_frames = null
	sprite.visible = false
	sprite.scale = Vector3.ONE
	var shadow := actor.get("shadow") as Node3D
	if is_instance_valid(shadow):
		shadow.visible = false
	actor.asset = {}
	actor.member = {}
	actor.scale_profile = {}
	actor.pending_member = {}
	actor.has_pending = false
	_actors[normalized] = actor
	_catalog.release_active(normalized == PLAYER_SIDE)
	battler_cleared.emit(normalized)


func clear() -> void:
	clear_side(PLAYER_SIDE)
	clear_side(OPPONENT_SIDE)
	_catalog.release_all()


func active_atlas_paths() -> PackedStringArray:
	return _catalog.active_atlas_paths()


func catalog_summary() -> Dictionary:
	return _catalog.catalog_summary()


func refresh_layout() -> void:
	for side: StringName in [PLAYER_SIDE, OPPONENT_SIDE]:
		var actor := _actor(side)
		if actor.is_empty():
			continue
		var member_value: Variant = actor.get("member", {})
		var asset_value: Variant = actor.get("asset", {})
		if typeof(member_value) != TYPE_DICTIONARY or typeof(asset_value) != TYPE_DICTIONARY:
			continue
		var member := member_value as Dictionary
		var asset := asset_value as Dictionary
		if member.is_empty() or asset.is_empty():
			continue
		actor.scale_profile = _scale_profile(member, asset, side == PLAYER_SIDE, actor)
		_actors[side] = actor
		_apply_grounding(side)
		var shadow := actor.get("shadow") as Node3D
		var shadow_was_visible := is_instance_valid(shadow) and shadow.visible
		_apply_shadow(side)
		if is_instance_valid(shadow) and not shadow_was_visible:
			shadow.visible = false
		var sprite := actor.sprite as AnimatedSprite3D
		_apply_scale_metadata(sprite, actor.scale_profile as Dictionary)


func _present_side(
	side: StringName,
	member: Dictionary,
	preserved_completion_id: int = -1
) -> Dictionary:
	var actor := _actor(side)
	if actor.is_empty():
		return {"ok": false, "error": "not_configured"}
	if member.is_empty():
		clear_side(side)
		return {"ok": true, "cleared": true}
	var profile := _battle_profile(member)
	var sprite_id := String(
		profile.get("spriteId", profile.get("sprite_id", member.get("spriteId", member.get("sprite_id", ""))))
	)
	var shiny := bool(profile.get("shiny", member.get("shiny", false)))
	var override_path := String(profile.get(
		"spriteOverride",
		profile.get("sprite_override", member.get("spriteOverride", member.get("sprite_override", "")))
	))
	var player_side := side == PLAYER_SIDE
	var asset := _catalog.load_active(sprite_id, player_side, shiny, override_path)
	if asset.is_empty():
		return {"ok": false, "error": _catalog.get_last_error()}
	_reset_motion(side, preserved_completion_id)
	var sprite := actor.sprite as AnimatedSprite3D
	sprite.sprite_frames = asset.sprite_frames as SpriteFrames
	sprite.animation = IDLE_ANIMATION
	sprite.frame = 0
	sprite.visible = true
	sprite.modulate = Color.WHITE
	actor.asset = asset
	actor.member = member.duplicate(true)
	actor.scale_profile = _scale_profile(member, asset, player_side, actor)
	actor.pending_member = {}
	actor.has_pending = false
	_actors[side] = actor
	_apply_grounding(side)
	_apply_shadow(side)
	sprite.play(IDLE_ANIMATION)
	sprite.set_meta("battle_sprite_id", sprite_id)
	sprite.set_meta("battle_sprite_style", String(asset.style))
	sprite.set_meta("battle_sprite_atlas_path", String(asset.atlas_path))
	sprite.set_meta("battle_sprite_placeholder", bool(asset.is_placeholder))
	sprite.set_meta("battle_sprite_placeholder_reason", String(asset.placeholder_reason))
	_apply_scale_metadata(sprite, actor.scale_profile as Dictionary)
	battler_presented.emit(side, sprite_id, bool(asset.is_placeholder))
	return {
		"ok": true,
		"sprite_id": sprite_id,
		"style": String(asset.style),
		"placeholder": bool(asset.is_placeholder),
		"placeholder_reason": String(asset.placeholder_reason),
		"scale": (actor.scale_profile as Dictionary).duplicate(true),
	}


func _present_snapshot_side(side: StringName, member: Dictionary) -> Dictionary:
	var actor := _actor(side)
	if actor.is_empty():
		return {"ok": false, "error": "not_configured"}
	var current_value: Variant = actor.get("member", {})
	var current := current_value as Dictionary if typeof(current_value) == TYPE_DICTIONARY else {}
	if current.is_empty():
		return _present_side(side, member)
	if _same_member(current, member):
		actor.member = member.duplicate(true)
		actor.pending_member = {}
		actor.has_pending = false
		_actors[side] = actor
		return {"ok": true, "unchanged": true}
	# BattleSystem emits the authoritative final snapshot before its event list.
	# Keep the old visual alive for a possible faint animation, then commit this
	# member when the translated switch event reaches the presenter.
	actor.pending_member = member.duplicate(true)
	actor.has_pending = true
	_actors[side] = actor
	return {"ok": true, "pending": true}


func _commit_pending_side(side: StringName, preserved_completion_id: int = -1) -> Dictionary:
	var actor := _actor(side)
	if actor.is_empty() or not bool(actor.get("has_pending", false)):
		return {"ok": true, "unchanged": true}
	var pending_value: Variant = actor.get("pending_member", {})
	var pending := pending_value as Dictionary if typeof(pending_value) == TYPE_DICTIONARY else {}
	actor.has_pending = false
	actor.pending_member = {}
	_actors[side] = actor
	return _present_side(side, pending, preserved_completion_id)


func _play_switch_event(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	if not bool(actor.get("has_pending", false)):
		return play_switch_in(side)
	var sprite := actor.get("sprite") as AnimatedSprite3D
	var shadow := actor.get("shadow") as Node3D
	var outgoing_is_visible := (
		is_instance_valid(sprite)
		and sprite.visible
		and sprite.modulate.a > 0.01
		and (not is_instance_valid(shadow) or shadow.visible)
	)
	if not outgoing_is_visible:
		_commit_pending_side(side)
		return play_switch_in(side)

	# Chain the real tween completion signals instead of mirroring their
	# durations. Tween start ticks vary with frame rate, and BattleScene must not
	# advance until the incoming actor has actually settled.
	var outgoing_completion = play_switch_out(side)
	var completion := _new_completion(side)
	outgoing_completion.connect(
		_finish_visible_switch_out.bind(side, completion.completion_id),
		CONNECT_ONE_SHOT
	)
	return completion.finished


func _finish_visible_switch_out(side: StringName, completion_id: int) -> void:
	if not _active_completions.has(completion_id):
		return
	_commit_pending_side(side, completion_id)
	var incoming_completion = play_switch_in(side, completion_id)
	incoming_completion.connect(
		_emit_switch_completion.bind(completion_id),
		CONNECT_ONE_SHOT
	)


func _emit_switch_completion(completion_id: int) -> void:
	var completion := _active_completions.get(completion_id) as PresentationCompletion
	if completion != null:
		completion.complete()


func _new_completion(side: StringName) -> PresentationCompletion:
	_next_completion_id += 1
	var completion := PresentationCompletion.new()
	completion.completion_id = _next_completion_id
	completion.side = _normalized_side(side)
	_active_completions[completion.completion_id] = completion
	completion.finished.connect(
		_release_completion,
		CONNECT_ONE_SHOT
	)
	return completion


func _release_completion(completion_id: int) -> void:
	_active_completions.erase(completion_id)


func _cancel_completions_for_side(side: StringName, preserved_completion_id: int = -1) -> void:
	var normalized := _normalized_side(side)
	for id_value: Variant in _active_completions.keys():
		var completion_id := int(id_value)
		if completion_id == preserved_completion_id:
			continue
		var completion := _active_completions.get(completion_id) as PresentationCompletion
		if completion != null and completion.side == normalized:
			completion.complete()


func _pending_side_is_clear(side: StringName) -> bool:
	var actor := _actor(side)
	if actor.is_empty() or not bool(actor.get("has_pending", false)):
		return false
	var pending_value: Variant = actor.get("pending_member", {})
	return typeof(pending_value) == TYPE_DICTIONARY and (pending_value as Dictionary).is_empty()


func _same_member(left: Dictionary, right: Dictionary) -> bool:
	if right.is_empty():
		return false
	var left_id := String(left.get("memberId", left.get("member_id", "")))
	var right_id := String(right.get("memberId", right.get("member_id", "")))
	if not left_id.is_empty() or not right_id.is_empty():
		return not left_id.is_empty() and left_id == right_id
	var left_profile := _battle_profile(left)
	var right_profile := _battle_profile(right)
	return String(left_profile.get("spriteId", left.get("spriteId", ""))) == String(
		right_profile.get("spriteId", right.get("spriteId", ""))
	)


func _apply_grounding(side: StringName) -> void:
	var actor := _actor(side)
	if actor.is_empty():
		return
	var sprite := actor.sprite as AnimatedSprite3D
	var asset := actor.asset as Dictionary
	var frame_metadata_value: Variant = asset.get("frame_metadata", [])
	if typeof(frame_metadata_value) != TYPE_ARRAY or (frame_metadata_value as Array).is_empty():
		return
	var frame_index := clampi(sprite.frame, 0, (frame_metadata_value as Array).size() - 1)
	var metadata := (frame_metadata_value as Array)[frame_index] as Dictionary
	var bounds_value: Variant = metadata.get("alpha_bounds", {})
	var bounds := bounds_value as Dictionary if typeof(bounds_value) == TYPE_DICTIONARY else {}
	var canvas_value: Variant = asset.get("canvas", {})
	var canvas := canvas_value as Dictionary if typeof(canvas_value) == TYPE_DICTIONARY else {}
	var canvas_height := maxf(1.0, float(canvas.get("height", 1.0)))
	var alpha_bottom := float(bounds.get("y", 0.0)) + float(bounds.get("height", canvas_height))
	var scale_value: Variant = actor.get("scale_profile", {})
	var scale_profile := scale_value as Dictionary if typeof(scale_value) == TYPE_DICTIONARY else {}
	var target_height := maxf(0.01, float(scale_profile.get(
		"visible_height_m",
		SpriteScale.PLAYER_FALLBACK_HEIGHT_M
			if side == PLAYER_SIDE
			else SpriteScale.OPPONENT_FALLBACK_HEIGHT_M
	)))
	sprite.pixel_size = target_height / maxf(1.0, float(asset.get("content_height", canvas_height)))
	sprite.scale = Vector3(
		maxf(0.01, float(scale_profile.get("width_scale", 1.0))),
		1.0,
		1.0
	)
	# The billboard quad's vertical axis follows camera-up, not world-up. Move
	# its origin along that same axis so every frame's visible alpha bottom
	# projects exactly onto the authored spawn/shadow anchor.
	var center_offset := sprite.pixel_size * (alpha_bottom - canvas_height * 0.5)
	var grounding_axis := Vector3.UP
	var viewport := get_viewport()
	var camera := viewport.get_camera_3d() if is_instance_valid(viewport) else null
	if is_instance_valid(camera) and camera.is_inside_tree():
		grounding_axis = camera.global_transform.basis.y.normalized()
	var actor_root := actor.get("actor") as Node3D
	if is_instance_valid(actor_root) and actor_root.is_inside_tree():
		sprite.position = (
			actor_root.global_transform.basis.inverse()
			* grounding_axis
			* center_offset
		)
	else:
		sprite.position = Vector3.UP * center_offset
	sprite.set_meta("battle_sprite_alpha_bounds", bounds.duplicate(true))
	sprite.set_meta("battle_sprite_ground_y", 0.0)
	sprite.set_meta("battle_sprite_grounding_axis", grounding_axis)


func _scale_profile(
	member: Dictionary,
	asset: Dictionary,
	player_side: bool,
	actor: Dictionary
) -> Dictionary:
	var pokemon_id := int(member.get("pokemonId", member.get("pokemon_id", 0)))
	var dimensions := SpeciesMapping.get_pokedex_dimensions(pokemon_id)
	var content_width := maxf(1.0, float(asset.get("content_width", 1.0)))
	var content_height := maxf(1.0, float(asset.get("content_height", 1.0)))
	var height_dm := int(dimensions.get("height_dm", 0))
	var weight_hg := int(dimensions.get("weight_hg", -1))
	var native_aspect := content_width / content_height
	var profile := SpriteScale.calculate(
		height_dm,
		weight_hg,
		native_aspect,
		player_side
	)
	_add_asset_scale_metrics(profile, asset)
	var horizontal_fit := _camera_horizontal_fit(actor, profile, player_side)
	if horizontal_fit < 0.9999:
		profile = SpriteScale.calculate(
			height_dm,
			weight_hg,
			native_aspect,
			player_side,
			horizontal_fit
		)
		_add_asset_scale_metrics(profile, asset)
	var hud_fit := _opponent_status_fit(actor, profile) if not player_side else 1.0
	if hud_fit < 0.9999:
		_apply_uniform_profile_fit(profile, hud_fit)
		_add_asset_scale_metrics(profile, asset)
	profile["hud_fit"] = hud_fit
	profile["pokemon_id"] = pokemon_id
	profile["content_width_px"] = content_width
	profile["content_height_px"] = content_height
	return profile


func _add_asset_scale_metrics(profile: Dictionary, asset: Dictionary) -> void:
	var content_width := maxf(1.0, float(asset.get("content_width", 1.0)))
	var content_height := maxf(1.0, float(asset.get("content_height", 1.0)))
	var left_extent_px := maxf(
		0.0,
		float(asset.get("content_left_extent", content_width * 0.5))
	)
	var right_extent_px := maxf(
		0.0,
		float(asset.get("content_right_extent", content_width * 0.5))
	)
	var pixel_size := float(profile.get("visible_height_m", 0.0)) / content_height
	var width_scale := maxf(0.01, float(profile.get("width_scale", 1.0)))
	profile["visible_left_extent_m"] = left_extent_px * pixel_size * width_scale
	profile["visible_right_extent_m"] = right_extent_px * pixel_size * width_scale
	profile["visible_envelope_width_m"] = (
		float(profile["visible_left_extent_m"])
		+ float(profile["visible_right_extent_m"])
	)


func _apply_uniform_profile_fit(profile: Dictionary, fit: float) -> void:
	var safe_fit := clampf(fit, 0.01, 1.0)
	profile["visible_width_m"] = float(profile.get("visible_width_m", 0.0)) * safe_fit
	profile["visible_height_m"] = float(profile.get("visible_height_m", 0.0)) * safe_fit


func _opponent_status_fit(actor: Dictionary, profile: Dictionary) -> float:
	var viewport := get_viewport()
	if not is_instance_valid(viewport):
		return 1.0
	var camera := viewport.get_camera_3d()
	var actor_root := actor.get("actor") as Node3D
	if (
		not is_instance_valid(camera)
		or not camera.is_inside_tree()
		or not is_instance_valid(actor_root)
		or not actor_root.is_inside_tree()
	):
		return 1.0
	var viewport_rect := viewport.get_visible_rect()
	var viewport_width := viewport_rect.size.x
	var gutter := maxf(HUD_GUTTER_MIN_PX, viewport_width * HUD_GUTTER_WIDTH_RATIO)
	var status_right := viewport_rect.end.x - gutter
	var status_width := clampf(
		viewport_width * OPPONENT_STATUS_WIDTH_RATIO,
		OPPONENT_STATUS_MIN_WIDTH_PX,
		OPPONENT_STATUS_MAX_WIDTH_PX
	)
	var status_left := status_right - status_width
	var camera_right := camera.global_transform.basis.x.normalized()
	var camera_up := camera.global_transform.basis.y.normalized()
	var visible_height := maxf(0.001, float(profile.get("visible_height_m", 0.0)))
	var sample_center := actor_root.global_position + camera_up * visible_height * 0.5
	var left_screen := camera.unproject_position(
		sample_center
		- camera_right * float(profile.get("visible_left_extent_m", 0.0))
	)
	var right_screen := camera.unproject_position(
		sample_center
		+ camera_right * float(profile.get("visible_right_extent_m", 0.0))
	)
	var sprite_left := minf(left_screen.x, right_screen.x)
	var sprite_right := maxf(left_screen.x, right_screen.x)
	if sprite_right <= status_left or sprite_left >= status_right:
		return 1.0

	var ground_screen := camera.unproject_position(actor_root.global_position)
	var top_screen := camera.unproject_position(
		actor_root.global_position + camera_up * visible_height
	)
	var safe_status_bottom := (
		viewport_rect.position.y
		+ OPPONENT_STATUS_BOTTOM_PX
		+ OPPONENT_STATUS_SPRITE_GAP_PX
	)
	if top_screen.y >= safe_status_bottom:
		return 1.0
	var projected_height := ground_screen.y - top_screen.y
	var available_height := ground_screen.y - safe_status_bottom
	if projected_height <= 0.001 or available_height <= 0.0:
		return 0.01
	return clampf(available_height / projected_height, 0.01, 1.0)


func _camera_horizontal_fit(
	actor: Dictionary,
	profile: Dictionary,
	player_side: bool
) -> float:
	var viewport := get_viewport()
	if not is_instance_valid(viewport):
		return 1.0
	var camera := viewport.get_camera_3d()
	var actor_root := actor.get("actor") as Node3D
	if (
		not is_instance_valid(camera)
		or not camera.is_inside_tree()
		or not is_instance_valid(actor_root)
		or not actor_root.is_inside_tree()
	):
		return 1.0
	var viewport_rect := viewport.get_visible_rect()
	if viewport_rect.size.x <= HORIZONTAL_SAFE_INSET_PX * 2.0:
		return 1.0
	var camera_right := camera.global_transform.basis.x.normalized()
	var camera_up := camera.global_transform.basis.y.normalized()
	var sample_center := (
		actor_root.global_position
		+ camera_up * float(profile.get("visible_height_m", 0.0)) * 0.5
	)
	var center_screen := camera.unproject_position(sample_center)
	var right_screen := camera.unproject_position(sample_center + camera_right)
	var pixels_per_metre := absf(right_screen.x - center_screen.x)
	if pixels_per_metre <= 0.0001:
		return 1.0
	var safe_left := viewport_rect.position.x + HORIZONTAL_SAFE_INSET_PX
	var safe_right := viewport_rect.end.x - HORIZONTAL_SAFE_INSET_PX
	var available_left_m := (center_screen.x - safe_left) / pixels_per_metre
	var available_right_m := (safe_right - center_screen.x) / pixels_per_metre
	if available_left_m <= 0.0 or available_right_m <= 0.0:
		return 0.01
	var left_extent_m := maxf(0.001, float(profile.get("visible_left_extent_m", 0.0)))
	var right_extent_m := maxf(0.001, float(profile.get("visible_right_extent_m", 0.0)))
	var uniform_fit := minf(
		1.0,
		minf(
			available_left_m / left_extent_m,
			available_right_m / right_extent_m
		)
	)
	if uniform_fit >= 0.9999:
		return 1.0
	var authored_width_m := (
		SpriteScale.PLAYER_MAX_VISIBLE_SIZE_M.x
		if player_side
		else SpriteScale.OPPONENT_MAX_VISIBLE_SIZE_M.x
	)
	var current_width_m := maxf(0.001, float(profile.get("visible_width_m", 0.0)))
	return clampf(current_width_m * uniform_fit / authored_width_m, 0.01, 1.0)


func _apply_scale_metadata(sprite: AnimatedSprite3D, profile: Dictionary) -> void:
	sprite.set_meta("battle_pokemon_id", int(profile.get("pokemon_id", 0)))
	sprite.set_meta("battle_sprite_scale_source", String(profile.get("source", "fallback")))
	sprite.set_meta("battle_pokedex_height_dm", int(profile.get("pokedex_height_dm", 0)))
	sprite.set_meta("battle_pokedex_weight_hg", int(profile.get("pokedex_weight_hg", 0)))
	sprite.set_meta("battle_sprite_visible_width_m", float(profile.get("visible_width_m", 0.0)))
	sprite.set_meta("battle_sprite_visible_height_m", float(profile.get("visible_height_m", 0.0)))
	sprite.set_meta("battle_sprite_native_aspect", float(profile.get("native_aspect", 1.0)))
	sprite.set_meta("battle_sprite_effective_aspect", float(profile.get("effective_aspect", 1.0)))
	sprite.set_meta("battle_sprite_bulk_factor", float(profile.get("bulk_factor", 1.0)))
	sprite.set_meta("battle_sprite_horizontal_fit", float(profile.get("horizontal_fit", 1.0)))
	sprite.set_meta("battle_sprite_hud_fit", float(profile.get("hud_fit", 1.0)))
	sprite.set_meta("battle_sprite_left_extent_m", float(profile.get("visible_left_extent_m", 0.0)))
	sprite.set_meta("battle_sprite_right_extent_m", float(profile.get("visible_right_extent_m", 0.0)))


func _apply_shadow(side: StringName) -> void:
	var actor := _actor(side)
	if actor.is_empty():
		return
	var shadow := actor.get("shadow") as Node3D
	if not is_instance_valid(shadow):
		return
	var profile_value: Variant = actor.get("scale_profile", {})
	if typeof(profile_value) != TYPE_DICTIONARY:
		shadow.visible = false
		return
	var profile := profile_value as Dictionary
	var visible_width := maxf(0.01, float(profile.get("visible_width_m", 1.0)))
	var mesh_diameter := maxf(0.01, float(actor.get("shadow_mesh_diameter", 1.76)))
	var footprint_width := clampf(visible_width * 0.80, 0.65, 3.60)
	var footprint_depth := clampf(footprint_width * 0.46, 0.30, 1.50)
	var target_scale := Vector3(
		footprint_width / mesh_diameter,
		1.0,
		footprint_depth / mesh_diameter
	)
	shadow.scale = target_scale
	shadow.visible = true
	shadow.set_meta("battle_shadow_width_m", footprint_width)
	shadow.set_meta("battle_shadow_depth_m", footprint_depth)
	actor.shadow_scale = target_scale
	_actors[side] = actor


func _collapsed_shadow_scale(actor: Dictionary) -> Vector3:
	var target_value: Variant = actor.get("shadow_scale", Vector3.ONE)
	var target := target_value as Vector3 if typeof(target_value) == TYPE_VECTOR3 else Vector3.ONE
	return Vector3(target.x * 0.18, 1.0, target.z * 0.18)


func _create_actor(
	side: StringName,
	spawn: Node3D,
	shadow: Node3D = null
) -> Dictionary:
	var actor_root := Node3D.new()
	actor_root.name = "PlayerBattleSpriteActor" if side == PLAYER_SIDE else "OpponentBattleSpriteActor"
	spawn.add_child(actor_root)
	var motion_root := Node3D.new()
	motion_root.name = "MotionRoot"
	actor_root.add_child(motion_root)
	var sprite := AnimatedSprite3D.new()
	sprite.name = "AnimatedPokemon"
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.centered = true
	sprite.double_sided = true
	sprite.shaded = false
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.alpha_scissor_threshold = 0.01
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	sprite.visible = false
	motion_root.add_child(sprite)
	sprite.frame_changed.connect(_apply_grounding.bind(side))
	var shadow_mesh_diameter := 1.76
	if shadow is MeshInstance3D:
		var cylinder := (shadow as MeshInstance3D).mesh as CylinderMesh
		if cylinder:
			shadow_mesh_diameter = 2.0 * maxf(cylinder.top_radius, cylinder.bottom_radius)
	if is_instance_valid(shadow):
		shadow.visible = false
	return {
		"actor": actor_root,
		"motion": motion_root,
		"sprite": sprite,
		"asset": {},
		"member": {},
		"scale_profile": {},
		"shadow": shadow,
		"shadow_mesh_diameter": shadow_mesh_diameter,
		"shadow_scale": Vector3.ONE,
		"pending_member": {},
		"has_pending": false,
		"tweens": [],
	}


func _remove_actor(side: StringName) -> void:
	if not _actors.has(side):
		return
	var actor := _actors[side] as Dictionary
	_kill_tweens(actor)
	_cancel_completions_for_side(side)
	var shadow := actor.get("shadow") as Node3D
	if is_instance_valid(shadow):
		shadow.visible = false
	var actor_root := actor.get("actor") as Node3D
	if is_instance_valid(actor_root):
		actor_root.queue_free()
	_actors.erase(side)
	_catalog.release_active(side == PLAYER_SIDE)


func _reset_motion(side: StringName, preserved_completion_id: int = -1) -> void:
	var actor := _actor(side)
	if actor.is_empty():
		return
	_kill_tweens(actor)
	_cancel_completions_for_side(side, preserved_completion_id)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	motion.position = Vector3.ZERO
	motion.rotation = Vector3.ZERO
	motion.scale = Vector3.ONE
	sprite.modulate = Color.WHITE
	var shadow := actor.get("shadow") as Node3D
	if is_instance_valid(shadow):
		var shadow_scale_value: Variant = actor.get("shadow_scale", Vector3.ONE)
		shadow.scale = (
			shadow_scale_value as Vector3
			if typeof(shadow_scale_value) == TYPE_VECTOR3
			else Vector3.ONE
		)
		shadow.visible = sprite.visible
	actor.tweens = []
	_actors[side] = actor


func _kill_tweens(actor: Dictionary) -> void:
	var tweens_value: Variant = actor.get("tweens", [])
	if typeof(tweens_value) != TYPE_ARRAY:
		return
	for value: Variant in tweens_value as Array:
		var tween := value as Tween
		if tween != null and tween.is_valid():
			tween.kill()


func _register_tween(actor: Dictionary, tween: Tween) -> void:
	var tweens: Array = actor.get("tweens", []) as Array
	tweens.append(tween)
	actor.tweens = tweens


func _actor(side: StringName) -> Dictionary:
	var normalized := _normalized_side(side)
	return _actors[normalized] as Dictionary if _actors.has(normalized) else {}


func _normalized_side(value: Variant) -> StringName:
	return PLAYER_SIDE if String(value) in ["player", "p1"] else OPPONENT_SIDE


func _active_member(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return {}
	for member_value: Variant in value as Array:
		if typeof(member_value) == TYPE_DICTIONARY and bool((member_value as Dictionary).get("active", false)):
			return (member_value as Dictionary).duplicate(true)
	return {}


func _battle_profile(member: Dictionary) -> Dictionary:
	var value: Variant = member.get("battleProfile", member.get("battle_profile", {}))
	return value as Dictionary if typeof(value) == TYPE_DICTIONARY else {}


func _instant_completion():
	var tween := create_tween()
	tween.tween_interval(0.0)
	return tween.finished
