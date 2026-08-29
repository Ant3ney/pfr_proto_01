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

const PLAYER_SIDE := &"player"
const OPPONENT_SIDE := &"opponent"
const IDLE_ANIMATION := &"idle"

@export_range(0.25, 8.0, 0.05) var player_visible_height_m := 2.35
@export_range(0.25, 8.0, 0.05) var opponent_visible_height_m := 2.15
@export_range(0.05, 2.0, 0.05) var attack_lunge_m := 0.55
@export_range(0.01, 0.5, 0.01) var hit_shake_m := 0.13

var _catalog := BattleSpriteCatalog.new()
var _actors: Dictionary = {}


func _ready() -> void:
	if _catalog.catalog_summary().is_empty():
		_catalog.initialize()


func configure(player_spawn: Node3D, opponent_spawn: Node3D) -> bool:
	if player_spawn == null or opponent_spawn == null:
		push_error("BattleSpritePresenter requires both authored spawn markers.")
		return false
	if _catalog.catalog_summary().is_empty() and not _catalog.initialize():
		return false
	_remove_actor(PLAYER_SIDE)
	_remove_actor(OPPONENT_SIDE)
	_actors[PLAYER_SIDE] = _create_actor(PLAYER_SIDE, player_spawn)
	_actors[OPPONENT_SIDE] = _create_actor(OPPONENT_SIDE, opponent_spawn)
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
			_commit_pending_side(side)
			return play_switch_in(side)
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
	return tween.finished


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
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", 0.55, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(motion, ^"scale", Vector3.ONE * 0.15, 0.24).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, ^"modulate:a", 0.0, 0.20)
	return tween.finished


func play_switch_in(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	motion.position.y = 0.55
	motion.scale = Vector3.ONE * 0.15
	sprite.modulate.a = 0.0
	sprite.visible = true
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", 0.0, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(motion, ^"scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, ^"modulate:a", 1.0, 0.18)
	return tween.finished


func play_faint(side: StringName):
	var actor := _actor(side)
	if actor.is_empty():
		return _instant_completion()
	_reset_motion(side)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	var tween := create_tween()
	_register_tween(actor, tween)
	tween.set_parallel(true)
	tween.tween_property(motion, ^"position:y", -0.32, 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(motion, ^"scale", Vector3(1.08, 0.08, 1.08), 0.38).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_property(sprite, ^"modulate:a", 0.0, 0.30).set_delay(0.08)
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
	actor.asset = {}
	actor.member = {}
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


func _present_side(side: StringName, member: Dictionary) -> Dictionary:
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
	_reset_motion(side)
	var sprite := actor.sprite as AnimatedSprite3D
	sprite.sprite_frames = asset.sprite_frames as SpriteFrames
	sprite.animation = IDLE_ANIMATION
	sprite.frame = 0
	sprite.visible = true
	sprite.modulate = Color.WHITE
	actor.asset = asset
	actor.member = member.duplicate(true)
	actor.pending_member = {}
	actor.has_pending = false
	_actors[side] = actor
	_apply_grounding(side)
	sprite.play(IDLE_ANIMATION)
	sprite.set_meta("battle_sprite_id", sprite_id)
	sprite.set_meta("battle_sprite_style", String(asset.style))
	sprite.set_meta("battle_sprite_atlas_path", String(asset.atlas_path))
	sprite.set_meta("battle_sprite_placeholder", bool(asset.is_placeholder))
	sprite.set_meta("battle_sprite_placeholder_reason", String(asset.placeholder_reason))
	battler_presented.emit(side, sprite_id, bool(asset.is_placeholder))
	return {
		"ok": true,
		"sprite_id": sprite_id,
		"style": String(asset.style),
		"placeholder": bool(asset.is_placeholder),
		"placeholder_reason": String(asset.placeholder_reason),
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


func _commit_pending_side(side: StringName) -> Dictionary:
	var actor := _actor(side)
	if actor.is_empty() or not bool(actor.get("has_pending", false)):
		return {"ok": true, "unchanged": true}
	var pending_value: Variant = actor.get("pending_member", {})
	var pending := pending_value as Dictionary if typeof(pending_value) == TYPE_DICTIONARY else {}
	actor.has_pending = false
	actor.pending_member = {}
	_actors[side] = actor
	return _present_side(side, pending)


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
	var target_height := player_visible_height_m if side == PLAYER_SIDE else opponent_visible_height_m
	sprite.pixel_size = target_height / maxf(1.0, float(asset.get("content_height", canvas_height)))
	# AnimatedSprite3D centers the frame; this offset pins the visible alpha
	# bottom to the authored marker's local y=0 for every GIF frame.
	sprite.position.y = sprite.pixel_size * (alpha_bottom - canvas_height * 0.5)
	sprite.set_meta("battle_sprite_alpha_bounds", bounds.duplicate(true))
	sprite.set_meta("battle_sprite_ground_y", 0.0)


func _create_actor(side: StringName, spawn: Node3D) -> Dictionary:
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
	return {
		"actor": actor_root,
		"motion": motion_root,
		"sprite": sprite,
		"asset": {},
		"member": {},
		"pending_member": {},
		"has_pending": false,
		"tweens": [],
	}


func _remove_actor(side: StringName) -> void:
	if not _actors.has(side):
		return
	var actor := _actors[side] as Dictionary
	_kill_tweens(actor)
	var actor_root := actor.get("actor") as Node3D
	if is_instance_valid(actor_root):
		actor_root.queue_free()
	_actors.erase(side)
	_catalog.release_active(side == PLAYER_SIDE)


func _reset_motion(side: StringName) -> void:
	var actor := _actor(side)
	if actor.is_empty():
		return
	_kill_tweens(actor)
	var motion := actor.motion as Node3D
	var sprite := actor.sprite as AnimatedSprite3D
	motion.position = Vector3.ZERO
	motion.rotation = Vector3.ZERO
	motion.scale = Vector3.ONE
	sprite.modulate = Color.WHITE
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
