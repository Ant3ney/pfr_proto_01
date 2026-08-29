extends Node

const EXPECTED_ANIMATIONS := 2106
const EXPECTED_FRAMES := 121213

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player_spawn := Node3D.new()
	player_spawn.name = "PlayerSpawn"
	add_child(player_spawn)
	var opponent_spawn := Node3D.new()
	opponent_spawn.name = "OpponentSpawn"
	add_child(opponent_spawn)
	var presenter := BattleSpritePresenter.new()
	presenter.name = "BattleSpritePresenter"
	add_child(presenter)
	await get_tree().process_frame

	_check(presenter.configure(player_spawn, opponent_spawn), "presenter should configure with two authored markers")
	var summary := presenter.catalog_summary()
	_check(int(summary.get("animations", 0)) == EXPECTED_ANIMATIONS, "catalog should contain all 2,106 animations")
	_check(int(summary.get("frames", 0)) == EXPECTED_FRAMES, "catalog should contain all 121,213 frames")
	_check(int(summary.get("front", 0)) == 1054, "catalog should contain 1,054 front atlases")
	_check(int(summary.get("back", 0)) == 1052, "catalog should contain 1,052 back atlases")
	_check(int(summary.get("maximumFrameCount", 0)) == 315, "catalog should preserve the 315-frame maximum")
	var absent_value: Variant = summary.get("absentBaseSpecies", [])
	_check(
		typeof(absent_value) == TYPE_ARRAY and (absent_value as Array).size() == 21,
		"catalog should preserve the verified 21-species absence list"
	)

	var initial := presenter.present_battlers(
		{"spriteId": "palkia"},
		{"spriteId": "wooper"}
	)
	_check(bool((initial.player as Dictionary).get("ok", false)), "Palkia back sprite should load")
	_check(bool((initial.opponent as Dictionary).get("ok", false)), "Wooper front sprite should load")
	_check(String((initial.player as Dictionary).get("style", "")) == "ani-back", "player should use ani-back")
	_check(String((initial.opponent as Dictionary).get("style", "")) == "ani", "opponent should use ani")
	_check(not bool((initial.player as Dictionary).get("placeholder", true)), "Palkia should be exact")
	_check(not bool((initial.opponent as Dictionary).get("placeholder", true)), "Wooper should be exact")
	_check(presenter.active_atlas_paths().size() == 2, "only the active front/back atlas pair should be retained")
	await get_tree().create_timer(0.08).timeout
	_check_grounding(_sprite(player_spawn), "Palkia")
	_check_grounding(_sprite(opponent_spawn), "Wooper")

	var required_pairs := [
		{"player": "mothim", "opponent": "magikarp"},
		{"player": "hoothoot", "opponent": "wooper"},
		{"player": "vespiquen", "opponent": "magikarp"},
		{"player": "luxray", "opponent": "wooper"},
		{"player": "pelipper", "opponent": "magikarp"},
	]
	for pair: Dictionary in required_pairs:
		var required := presenter.present_battlers(
			{"spriteId": String(pair.player)},
			{"spriteId": String(pair.opponent)}
		)
		_check(
			not bool((required.player as Dictionary).get("placeholder", true)),
			"Current party sprite %s should load exactly" % String(pair.player)
		)
		_check(
			not bool((required.opponent as Dictionary).get("placeholder", true)),
			"Kyle sprite %s should load exactly" % String(pair.opponent)
		)
		_check(
			presenter.active_atlas_paths().size() == 2,
			"Required-party coverage should retain only one atlas per side"
		)

	var variable := presenter.present_battlers(
		{"spriteId": "psyduck"},
		{"spriteId": "dipplin"}
	)
	_check(not bool((variable.player as Dictionary).get("placeholder", true)), "Variable-timing back asset should load")
	_check(not bool((variable.opponent as Dictionary).get("placeholder", true)), "Variable-timing front asset should load")
	_check(_has_variable_durations(_sprite(player_spawn)), "Psyduck back should preserve variable frame durations")
	_check(_has_variable_durations(_sprite(opponent_spawn)), "Dipplin front should preserve variable frame durations")

	var representative := presenter.present_battlers(
		{"spriteId": "ferroseed"},
		{"spriteId": "regieleki"}
	)
	_check(not bool((representative.player as Dictionary).get("placeholder", true)), "Ferroseed back should load exactly")
	_check(not bool((representative.opponent as Dictionary).get("placeholder", true)), "Regieleki front should load exactly")
	var ferroseed := _sprite(player_spawn)
	var regieleki := _sprite(opponent_spawn)
	_check(
		ferroseed.sprite_frames.get_frame_count(&"idle") == 1,
		"Ferroseed should exercise the single-frame case"
	)
	_check(
		regieleki.sprite_frames.get_frame_count(&"idle") == 315,
		"Regieleki front should exercise the maximum-frame case"
	)
	_check(presenter.active_atlas_paths().size() == 2, "switching should replace, not accumulate, atlas references")

	await presenter.play_attack(&"player")
	var player_motion := player_spawn.get_node(^"PlayerBattleSpriteActor/MotionRoot") as Node3D
	_check(player_motion.position.is_zero_approx(), "attack lunge should settle on the motion root")
	await presenter.play_hit(&"opponent")
	var opponent_motion := opponent_spawn.get_node(^"OpponentBattleSpriteActor/MotionRoot") as Node3D
	_check(opponent_motion.position.is_zero_approx(), "hit shake should settle on the motion root")
	_check(_sprite(opponent_spawn).modulate == Color.WHITE, "hit flash should reset")
	_check(
		presenter.play_event({"type": "message", "message": "Readable fallback"}) == null,
		"message-only events should defer readable timing to BattleScene"
	)

	presenter.present_battlers(
		{"memberId": "player-active", "spriteId": "palkia"},
		{"memberId": "kyle-wooper", "spriteId": "wooper"}
	)
	var queued_switch := presenter.present_snapshot({
		"parties": {
			"player": [{"memberId": "player-active", "spriteId": "palkia", "active": true}],
			"opponent": [{"memberId": "kyle-magikarp", "spriteId": "magikarp", "active": true}],
		}
	})
	_check(bool((queued_switch.opponent as Dictionary).get("pending", false)), "new snapshot battler should wait for switch presentation")
	_check(
		presenter.active_atlas_paths().has("res://art/battle/sprites/generated/ani/wooper.png"),
		"old opponent should remain loaded for its knockout event"
	)
	await presenter.play_event({"type": "knockout", "side": "opponent", "actor": "Wooper"})
	_check(
		presenter.active_atlas_paths().has("res://art/battle/sprites/generated/ani/wooper.png"),
		"knockout should not target the final snapshot replacement"
	)
	await presenter.play_event({"type": "switch", "side": "opponent", "actor": "Magikarp"})
	_check(
		presenter.active_atlas_paths().has("res://art/battle/sprites/generated/ani/magikarp.png"),
		"switch event should commit and animate the queued replacement"
	)

	var missing := presenter.present_battlers(
		{"spriteId": "ferroseed", "shiny": true},
		{"spriteId": "ironmoth"}
	)
	_check(bool((missing.player as Dictionary).get("placeholder", false)), "shiny requests should not use normal art")
	_check(
		String((missing.player as Dictionary).get("placeholder_reason", "")) == "shiny_not_approved",
		"shiny placeholder should report its exact reason"
	)
	_check(bool((missing.opponent as Dictionary).get("placeholder", false)), "missing exact forms should use the placeholder")
	_check(
		String((missing.opponent as Dictionary).get("placeholder_reason", "")) == "exact_sprite_missing",
		"absent base species should not silently substitute another sprite"
	)

	presenter.clear()
	_check(presenter.active_atlas_paths().is_empty(), "clear should release both active atlas references")
	presenter.queue_free()
	await get_tree().process_frame
	_finish()


func _sprite(spawn: Node3D) -> AnimatedSprite3D:
	return spawn.get_node("%s/MotionRoot/AnimatedPokemon" % (
		"PlayerBattleSpriteActor" if spawn.name == "PlayerSpawn" else "OpponentBattleSpriteActor"
	)) as AnimatedSprite3D


func _check_grounding(sprite: AnimatedSprite3D, label: String) -> void:
	if sprite == null or sprite.sprite_frames == null:
		_failures.append("%s sprite is unavailable for grounding validation" % label)
		return
	var texture := sprite.sprite_frames.get_frame_texture(&"idle", sprite.frame)
	var bounds_value: Variant = sprite.get_meta("battle_sprite_alpha_bounds", {})
	var bounds := bounds_value as Dictionary if typeof(bounds_value) == TYPE_DICTIONARY else {}
	var alpha_bottom := float(bounds.get("y", 0.0)) + float(bounds.get("height", texture.get_height()))
	var visible_bottom := sprite.position.y + sprite.pixel_size * (float(texture.get_height()) * 0.5 - alpha_bottom)
	_check(absf(visible_bottom) <= 0.0001, "%s alpha bottom should stay grounded; got %.6f" % [label, visible_bottom])


func _has_variable_durations(sprite: AnimatedSprite3D) -> bool:
	if sprite == null or sprite.sprite_frames == null:
		return false
	var durations: Dictionary = {}
	for frame_index in sprite.sprite_frames.get_frame_count(&"idle"):
		durations[sprite.sprite_frames.get_frame_duration(&"idle", frame_index)] = true
	return durations.size() > 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("Battle sprite catalog smoke test passed.")
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Battle sprite catalog smoke test failed: %s" % failure)
	get_tree().quit(1)
