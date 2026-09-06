extends Node

const EXPECTED_ANIMATIONS := 2106
const EXPECTED_FRAMES := 121213
const SpriteScale := preload("res://game/battle/system/battle_sprite_scale.gd")

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_front_thumbnail_extraction()

	var player_spawn := Node3D.new()
	player_spawn.name = "PlayerSpawn"
	player_spawn.position = Vector3(-2.35, 0.0, 1.45)
	player_spawn.rotation = Vector3(0.0, PI, 0.0)
	add_child(player_spawn)
	var opponent_spawn := Node3D.new()
	opponent_spawn.name = "OpponentSpawn"
	opponent_spawn.position = Vector3(2.25, 0.0, -1.85)
	add_child(opponent_spawn)
	var player_shadow := _new_shadow("PlayerShadow")
	add_child(player_shadow)
	var opponent_shadow := _new_shadow("OpponentShadow")
	add_child(opponent_shadow)
	var presenter := BattleSpritePresenter.new()
	presenter.name = "BattleSpritePresenter"
	add_child(presenter)
	await get_tree().process_frame

	_check(
		presenter.configure(
			player_spawn,
			opponent_spawn,
			player_shadow,
			opponent_shadow
		),
		"presenter should configure with authored markers and proportional shadows"
	)
	_check(
		not player_shadow.visible and not opponent_shadow.visible,
		"empty battler sides should not leave orphaned shadows"
	)
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
		{"pokemonId": 484, "spriteId": "palkia"},
		{"pokemonId": 194, "spriteId": "wooper"}
	)
	_check(bool((initial.player as Dictionary).get("ok", false)), "Palkia back sprite should load")
	_check(bool((initial.opponent as Dictionary).get("ok", false)), "Wooper front sprite should load")
	_check(String((initial.player as Dictionary).get("style", "")) == "ani-back", "player should use ani-back")
	_check(String((initial.opponent as Dictionary).get("style", "")) == "ani", "opponent should use ani")
	_check(not bool((initial.player as Dictionary).get("placeholder", true)), "Palkia should be exact")
	_check(not bool((initial.opponent as Dictionary).get("placeholder", true)), "Wooper should be exact")
	_check(presenter.active_atlas_paths().size() == 2, "only the active front/back atlas pair should be retained")
	var palkia_scale: Dictionary = (initial.player as Dictionary).get("scale", {})
	var wooper_scale: Dictionary = (initial.opponent as Dictionary).get("scale", {})
	_check(palkia_scale.get("source") == "pokedex", "Palkia should use Pokédex-driven scale")
	_check(wooper_scale.get("source") == "pokedex", "Wooper should use Pokédex-driven scale")
	_check(int(palkia_scale.get("pokedex_height_dm", 0)) == 42, "Palkia scale should use 4.2 m")
	_check(int(wooper_scale.get("pokedex_height_dm", 0)) == 4, "Wooper scale should use 0.4 m")
	_check(
		float(palkia_scale.get("visible_height_m", 0.0))
		> float(wooper_scale.get("visible_height_m", 1.0)) * 2.5,
		"Exaggerated Palkia/Wooper visible-height contrast should exceed 2.5x"
	)
	_check(
		float(palkia_scale.get("visible_width_m", 0.0))
		> float(wooper_scale.get("visible_width_m", 1.0)) * 2.5,
		"Exaggerated Palkia/Wooper visible-width contrast should exceed 2.5x"
	)
	_check(player_shadow.visible and opponent_shadow.visible, "presented battlers should reveal their shadows")
	_check(
		float(player_shadow.get_meta("battle_shadow_width_m", 0.0))
		> float(opponent_shadow.get_meta("battle_shadow_width_m", 0.0)) * 2.0,
		"Shadow footprints should follow the species width contrast"
	)
	var camera := Camera3D.new()
	camera.name = "BattleCamera"
	camera.position = Vector3(0.0, 4.7, 8.7)
	camera.rotation = Vector3(-0.5061455, 0.0, 0.0)
	camera.fov = 42.0
	camera.current = true
	add_child(camera)
	presenter.refresh_layout()
	await get_tree().create_timer(0.08).timeout
	_check_grounding(_sprite(player_spawn), player_spawn, camera, "Palkia")
	_check_grounding(_sprite(opponent_spawn), opponent_spawn, camera, "Wooper")
	_test_scale_curve_extremes()

	var required_pairs := [
		{"player": "mothim", "player_id": 414, "opponent": "magikarp", "opponent_id": 129},
		{"player": "hoothoot", "player_id": 163, "opponent": "wooper", "opponent_id": 194},
		{"player": "vespiquen", "player_id": 416, "opponent": "magikarp", "opponent_id": 129},
		{"player": "luxray", "player_id": 405, "opponent": "wooper", "opponent_id": 194},
		{"player": "pelipper", "player_id": 279, "opponent": "magikarp", "opponent_id": 129},
	]
	for pair: Dictionary in required_pairs:
		var required := presenter.present_battlers(
			{"pokemonId": int(pair.player_id), "spriteId": String(pair.player)},
			{"pokemonId": int(pair.opponent_id), "spriteId": String(pair.opponent)}
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
		{"pokemonId": 54, "spriteId": "psyduck"},
		{"pokemonId": 1011, "spriteId": "dipplin"}
	)
	_check(not bool((variable.player as Dictionary).get("placeholder", true)), "Variable-timing back asset should load")
	_check(not bool((variable.opponent as Dictionary).get("placeholder", true)), "Variable-timing front asset should load")
	_check(_has_variable_durations(_sprite(player_spawn)), "Psyduck back should preserve variable frame durations")
	_check(_has_variable_durations(_sprite(opponent_spawn)), "Dipplin front should preserve variable frame durations")

	var representative := presenter.present_battlers(
		{"pokemonId": 597, "spriteId": "ferroseed"},
		{"pokemonId": 894, "spriteId": "regieleki"}
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
	var ferroseed_pixel_size := ferroseed.pixel_size
	var ferroseed_species_scale := ferroseed.scale
	var regieleki_pixel_size := regieleki.pixel_size
	var regieleki_species_scale := regieleki.scale
	var full_player_shadow_scale := player_shadow.scale

	await presenter.play_attack(&"player")
	var player_motion := player_spawn.get_node(^"PlayerBattleSpriteActor/MotionRoot") as Node3D
	_check(player_motion.position.is_zero_approx(), "attack lunge should settle on the motion root")
	_check(
		is_equal_approx(ferroseed.pixel_size, ferroseed_pixel_size)
		and ferroseed.scale.is_equal_approx(ferroseed_species_scale),
		"Attack motion should preserve the player's species proportions"
	)
	await presenter.play_hit(&"opponent")
	var opponent_motion := opponent_spawn.get_node(^"OpponentBattleSpriteActor/MotionRoot") as Node3D
	_check(opponent_motion.position.is_zero_approx(), "hit shake should settle on the motion root")
	_check(_sprite(opponent_spawn).modulate == Color.WHITE, "hit flash should reset")
	_check(
		is_equal_approx(regieleki.pixel_size, regieleki_pixel_size)
		and regieleki.scale.is_equal_approx(regieleki_species_scale),
		"Hit motion should preserve the opponent's species proportions"
	)
	var interrupted_hit_state := {"finished": false}
	var interrupted_hit_completion = presenter.play_hit(&"opponent")
	interrupted_hit_completion.connect(func(_completion_id: int) -> void:
		interrupted_hit_state.finished = true
	, CONNECT_ONE_SHOT)
	await get_tree().create_timer(0.05).timeout
	presenter.clear_side(&"opponent")
	await get_tree().process_frame
	_check(
		bool(interrupted_hit_state.finished)
		and (presenter.get("_active_completions") as Dictionary).is_empty(),
		"Clearing an interrupted composite animation should release its completion waiter"
	)
	await presenter.play_heal(&"player")
	_check(
		is_equal_approx(ferroseed.pixel_size, ferroseed_pixel_size)
		and ferroseed.scale.is_equal_approx(ferroseed_species_scale),
		"Healing motion should preserve the player's species proportions"
	)
	await presenter.play_switch_out(&"player")
	_check(
		player_shadow.scale.x < full_player_shadow_scale.x * 0.25,
		"Switch-out motion should collapse the current species shadow"
	)
	await presenter.play_switch_in(&"player")
	_check(
		ferroseed.scale.is_equal_approx(ferroseed_species_scale)
		and player_shadow.scale.is_equal_approx(full_player_shadow_scale),
		"Switch-in motion should restore sprite proportions and the species shadow"
	)
	_check(
		presenter.play_event({"type": "message", "message": "Readable fallback"}) == null,
		"message-only events should defer readable timing to BattleScene"
	)

	presenter.present_battlers(
		{"memberId": "player-palkia", "pokemonId": 484, "spriteId": "palkia"},
		{"memberId": "kyle-wooper", "pokemonId": 194, "spriteId": "wooper"}
	)
	var voluntary_switch := presenter.present_snapshot({
		"parties": {
			"player": [{
				"memberId": "player-mothim",
				"pokemonId": 414,
				"spriteId": "mothim",
				"active": true,
			}],
			"opponent": [{
				"memberId": "kyle-wooper",
				"pokemonId": 194,
				"spriteId": "wooper",
				"active": true,
			}],
		}
	})
	_check(
		bool((voluntary_switch.player as Dictionary).get("pending", false)),
		"A voluntary replacement should remain queued behind the outgoing battler"
	)
	var voluntary_completion = presenter.play_event({
		"type": "switch",
		"side": "player",
		"actor": "Mothim",
	})
	await get_tree().create_timer(0.12).timeout
	_check(
		int(_sprite(player_spawn).get_meta("battle_pokemon_id", 0)) == 484
		and _sprite(player_spawn).modulate.a < 1.0,
		"A voluntary switch should animate the outgoing species before replacement"
	)
	await voluntary_completion
	_check(
		int(_sprite(player_spawn).get_meta("battle_pokemon_id", 0)) == 414
		and player_motion.scale.is_equal_approx(Vector3.ONE),
		"A voluntary switch should reveal and settle the queued incoming species"
	)
	var interrupted_switch := presenter.present_snapshot({
		"parties": {
			"player": [{
				"memberId": "player-palkia",
				"pokemonId": 484,
				"spriteId": "palkia",
				"active": true,
			}],
			"opponent": [{
				"memberId": "kyle-wooper",
				"pokemonId": 194,
				"spriteId": "wooper",
				"active": true,
			}],
		}
	})
	_check(
		bool((interrupted_switch.player as Dictionary).get("pending", false)),
		"The switch interruption case should begin with a queued replacement"
	)
	var interrupted_switch_state := {"finished": false}
	var interrupted_switch_completion = presenter.play_event({
		"type": "switch",
		"side": "player",
		"actor": "Palkia",
	})
	interrupted_switch_completion.connect(func(_completion_id: int) -> void:
		interrupted_switch_state.finished = true
	, CONNECT_ONE_SHOT)
	await get_tree().create_timer(0.12).timeout
	presenter.clear_side(&"player")
	await get_tree().process_frame
	_check(
		bool(interrupted_switch_state.finished)
		and (presenter.get("_active_completions") as Dictionary).is_empty(),
		"Clearing an interrupted switch should release its completion waiter"
	)

	presenter.present_battlers(
		{"memberId": "player-active", "pokemonId": 484, "spriteId": "palkia"},
		{"memberId": "kyle-wooper", "pokemonId": 194, "spriteId": "wooper"}
	)
	var queued_switch := presenter.present_snapshot({
		"parties": {
			"player": [{"memberId": "player-active", "pokemonId": 484, "spriteId": "palkia", "active": true}],
			"opponent": [{"memberId": "kyle-magikarp", "pokemonId": 129, "spriteId": "magikarp", "active": true}],
		}
	})
	_check(bool((queued_switch.opponent as Dictionary).get("pending", false)), "new snapshot battler should wait for switch presentation")
	_check(
		int(_sprite(opponent_spawn).get_meta("battle_pokemon_id", 0)) == 194,
		"A queued snapshot replacement should retain the outgoing species proportions"
	)
	_check(
		presenter.active_atlas_paths().has("res://art/battle/sprites/generated/ani/wooper.png"),
		"old opponent should remain loaded for its knockout event"
	)
	await presenter.play_event({"type": "knockout", "side": "opponent", "actor": "Wooper"})
	_check(
		presenter.active_atlas_paths().has("res://art/battle/sprites/generated/ani/wooper.png"),
		"knockout should not target the final snapshot replacement"
	)
	_check(
		not opponent_shadow.visible,
		"A completed faint should not leave an orphaned shadow on a terminal result"
	)
	var collapsed_shadow_x := opponent_shadow.scale.x
	presenter.refresh_layout()
	_check(
		not opponent_shadow.visible,
		"A camera/layout refresh should preserve a terminally fainted shadow's hidden state"
	)
	await presenter.play_event({"type": "switch", "side": "opponent", "actor": "Magikarp"})
	_check(
		presenter.active_atlas_paths().has("res://art/battle/sprites/generated/ani/magikarp.png"),
		"switch event should commit and animate the queued replacement"
	)
	_check(
		int(_sprite(opponent_spawn).get_meta("battle_pokemon_id", 0)) == 129
		and int(_sprite(opponent_spawn).get_meta("battle_pokedex_height_dm", 0)) == 9,
		"The switch event should apply the incoming species dimensions"
	)
	_check(
		opponent_shadow.visible and opponent_shadow.scale.x > collapsed_shadow_x * 2.0,
		"switching should replace and restore the incoming species shadow footprint"
	)

	var missing := presenter.present_battlers(
		{"pokemonId": 597, "spriteId": "ferroseed", "shiny": true},
		{"pokemonId": 994, "spriteId": "ironmoth"}
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
	_check(
		not player_shadow.visible and not opponent_shadow.visible,
		"clearing the presenter should hide both proportional shadows"
	)
	presenter.queue_free()
	await get_tree().process_frame
	_finish()


func _test_front_thumbnail_extraction() -> void:
	var catalog := BattleSpriteCatalog.new()
	_check(catalog.initialize(), "thumbnail catalog should initialize")
	_check(
		catalog.active_atlas_paths().is_empty(),
		"thumbnail catalog should begin without retained active atlases"
	)
	var exact := catalog.load_front_thumbnail("vespiquen", false, "", Vector2i(32, 32))
	var exact_texture := exact.get("texture") as Texture2D
	_check(exact_texture != null, "Vespiquen should produce a switch-menu thumbnail")
	_check(String(exact.get("style", "")) == "ani", "switch thumbnails should use front-facing ani art")
	_check(int(exact.get("frame_index", -1)) == 0, "switch thumbnails should use the first composited GIF frame")
	_check(
		String(exact.get("atlas_path", ""))
		== "res://art/battle/sprites/generated/ani/vespiquen.png",
		"Vespiquen thumbnail should retain exact front-atlas provenance"
	)
	_check(not bool(exact.get("is_placeholder", true)), "Vespiquen thumbnail should load exactly")
	if exact_texture != null:
		var exact_image := exact_texture.get_image()
		_check(exact_image.get_size() == Vector2i(32, 32), "switch thumbnails should use the requested compact size")
		_check(exact_image.get_used_rect().has_area(), "switch thumbnails should retain visible alpha-cropped pixels")

	var missing := catalog.load_front_thumbnail("definitely-missing-form")
	_check(missing.get("texture") is Texture2D, "missing exact forms should still produce a neutral thumbnail")
	_check(bool(missing.get("is_placeholder", false)), "missing exact forms should use the placeholder thumbnail")
	_check(
		String(missing.get("placeholder_reason", "")) == "exact_sprite_missing",
		"missing switch thumbnail should preserve its exact fallback reason"
	)
	_check(
		catalog.active_atlas_paths().is_empty(),
		"extracting party thumbnails must not retain any full animation atlas"
	)


func _sprite(spawn: Node3D) -> AnimatedSprite3D:
	return spawn.get_node("%s/MotionRoot/AnimatedPokemon" % (
		"PlayerBattleSpriteActor" if spawn.name == "PlayerSpawn" else "OpponentBattleSpriteActor"
	)) as AnimatedSprite3D


func _new_shadow(shadow_name: String) -> MeshInstance3D:
	var shadow := MeshInstance3D.new()
	shadow.name = shadow_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.88
	mesh.bottom_radius = 0.88
	mesh.height = 0.025
	shadow.mesh = mesh
	return shadow


func _test_scale_curve_extremes() -> void:
	var joltik := SpriteScale.calculate(1, 6, 1.52, true)
	var wailord := SpriteScale.calculate(145, 3980, 1.82, true)
	var narrow_fit := 0.75
	var dondozo_wide := SpriteScale.calculate(120, 2200, 178.0 / 62.0, true)
	var dondozo_narrow := SpriteScale.calculate(
		120,
		2200,
		178.0 / 62.0,
		true,
		narrow_fit
	)
	_check(joltik.get("source") == "pokedex", "Tiny species should use the Pokédex curve")
	_check(wailord.get("source") == "pokedex", "Huge species should use the Pokédex curve")
	_check(
		is_equal_approx(
			float(joltik.get("visible_height_m", 0.0)),
			SpriteScale.PLAYER_MIN_VISIBLE_HEIGHT_M
		),
		"Joltik should reach the deliberate phone-readability floor"
	)
	_check(
		float(wailord.get("visible_height_m", 99.0))
		<= SpriteScale.PLAYER_MAX_VISIBLE_SIZE_M.y + 0.0001,
		"Wailord should remain inside the player camera height bound"
	)
	_check(
		float(wailord.get("visible_width_m", 99.0))
		<= SpriteScale.PLAYER_MAX_VISIBLE_SIZE_M.x + 0.0001,
		"Wailord should remain inside the player camera width bound"
	)
	_check(
		float(wailord.get("visible_height_m", 0.0))
		> float(joltik.get("visible_height_m", 1.0)) * 2.5,
		"The exaggerated tiny-to-huge height contrast should remain obvious"
	)
	_check(
		float(dondozo_narrow.get("visible_width_m", 99.0))
		<= SpriteScale.PLAYER_MAX_VISIBLE_SIZE_M.x * narrow_fit + 0.0001
		and float(dondozo_narrow.get("visible_width_m", 0.0))
		< float(dondozo_wide.get("visible_width_m", 0.0)),
		"Extremely wide species should honor a camera-derived horizontal fit"
	)
	var zero_weight := SpriteScale.calculate(1000, 0, 1.2, false)
	_check(
		is_equal_approx(float(zero_weight.get("bulk_factor", 0.0)), 1.0),
		"Unknown zero Pokédex weight should use neutral bulk"
	)
	_check(
		float(zero_weight.get("visible_height_m", 99.0))
		<= SpriteScale.OPPONENT_MAX_VISIBLE_SIZE_M.y + 0.0001,
		"Eternatus-Eternamax should remain finite and camera-safe"
	)
	var ordinary := SpriteScale.calculate(10, 300, 1.0, false)
	var heavy := SpriteScale.calculate(10, 3000, 1.0, false)
	_check(
		float(heavy.get("effective_aspect", 0.0))
		> float(ordinary.get("effective_aspect", 1.0)),
		"Weight should widen silhouettes only through the restrained bulk correction"
	)
	var fallback := SpriteScale.calculate(0, -1, 1.4, true)
	_check(fallback.get("source") == "fallback", "Missing dimensions should use a safe fallback")
	_check(
		is_equal_approx(float(fallback.get("width_scale", 0.0)), 1.0),
		"Fallback scaling should not invent a width correction"
	)


func _check_grounding(
	sprite: AnimatedSprite3D,
	spawn: Node3D,
	camera: Camera3D,
	label: String
) -> void:
	if sprite == null or sprite.sprite_frames == null:
		_failures.append("%s sprite is unavailable for grounding validation" % label)
		return
	var original_frame := sprite.frame
	var spawn_screen := camera.unproject_position(spawn.global_position)
	for frame_index in sprite.sprite_frames.get_frame_count(&"idle"):
		sprite.frame = frame_index
		var texture := sprite.sprite_frames.get_frame_texture(&"idle", sprite.frame)
		var bounds_value: Variant = sprite.get_meta("battle_sprite_alpha_bounds", {})
		var bounds := bounds_value as Dictionary if typeof(bounds_value) == TYPE_DICTIONARY else {}
		var alpha_bottom := float(bounds.get("y", 0.0)) + float(bounds.get("height", texture.get_height()))
		var axis_value: Variant = sprite.get_meta("battle_sprite_grounding_axis", Vector3.UP)
		var grounding_axis := axis_value as Vector3 if typeof(axis_value) == TYPE_VECTOR3 else Vector3.UP
		var visible_bottom_world := (
			sprite.global_position
			+ grounding_axis
			* sprite.pixel_size
			* (float(texture.get_height()) * 0.5 - alpha_bottom)
		)
		var visible_bottom := camera.unproject_position(visible_bottom_world)
		_check(
			visible_bottom.distance_to(spawn_screen) <= 0.05,
			"%s frame %d billboard bottom should project onto its shadow; got %s"
			% [label, frame_index, str(visible_bottom - spawn_screen)]
		)
	sprite.frame = original_frame


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
