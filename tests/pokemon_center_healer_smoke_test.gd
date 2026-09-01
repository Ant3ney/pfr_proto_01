extends Node

const HEALER_SCENE := preload(
	"res://overworld/pokemon_center/PokemonCenterHealer.tscn"
)
const PLAYER_SCENE := preload("res://demo/player.tscn")
const EXPECTED_HEALER_TRIANGLES := 7656
const EXPECTED_HEALER_DRAWS := 9
const MAX_HEALER_TEXTURE_DIMENSION := 256

var _failures: Array[String] = []
var _collection_change_count := 0
var _sequence_started_count := 0
var _sequence_finished_count := 0
var _party_healed_count := 0
var _last_restored_count := -1


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_movement_enabled := GameInstance.is_player_movement_enabled()
	await _close_all_templates()

	var healer_character := HEALER_SCENE.instantiate() as PFRCharacter
	_check(healer_character != null, "The Pokemon Center healer scene should instantiate as a PFRCharacter.")
	if healer_character != null:
		add_child(healer_character)
		await get_tree().process_frame
		var behavior := healer_character.npc_behavior as PokemonCenterHealerBehavior
		_check(behavior != null, "The Center clerk should use PokemonCenterHealerBehavior.")
		_check(
			healer_character.character_art_asset_pack != null
			and healer_character.character_art_asset_pack.resource_name == "Waiter",
			"The healer should use the existing male waiter art pack."
		)
		var healer_meshes: Array[MeshInstance3D] = []
		_collect_mesh_instances(healer_character.character_art, healer_meshes)
		var healer_triangles := 0
		var healer_draws := 0
		var healer_textures := 0
		var largest_texture_dimension := 0
		for mesh_instance: MeshInstance3D in healer_meshes:
			var mesh := mesh_instance.mesh
			if mesh == null:
				continue
			healer_draws += mesh.get_surface_count()
			for surface_index in mesh.get_surface_count():
				var arrays := mesh.surface_get_arrays(surface_index)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				healer_triangles += (
					indices.size() / 3
					if not indices.is_empty()
					else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
				)
				var material := mesh.surface_get_material(surface_index) as BaseMaterial3D
				if material != null and material.albedo_texture != null:
					healer_textures += 1
					largest_texture_dimension = maxi(
						largest_texture_dimension,
						maxi(
							material.albedo_texture.get_width(),
							material.albedo_texture.get_height()
						)
					)
		_check(
			healer_triangles == EXPECTED_HEALER_TRIANGLES
			and healer_draws == EXPECTED_HEALER_DRAWS,
			(
				"The healer has %d triangles and %d draws; expected the verified "
				+ "7,656-triangle, nine-draw mobile budget."
			) % [healer_triangles, healer_draws]
		)
		_check(
			healer_textures == EXPECTED_HEALER_DRAWS
			and largest_texture_dimension <= MAX_HEALER_TEXTURE_DIMENSION,
			"The healer should retain nine compact albedo textures no larger than 256 px."
		)
		var interaction_area := healer_character.get_node_or_null(^"InteractionArea") as Area3D
		_check(interaction_area != null, "The healer should include a desk interaction area.")
		if interaction_area != null:
			_check(interaction_area.collision_layer == 0, "The interaction area should not block movement.")
			_check(interaction_area.collision_mask == 1, "The interaction area should detect the layer-1 player.")
			var area_shape := interaction_area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
			_check(
				area_shape != null
				and area_shape.shape is SphereShape3D
				and (area_shape.shape as SphereShape3D).radius >= 2.2,
				"The interaction sphere should reach a player standing in front of the desk."
			)

		if behavior != null:
			var player := PLAYER_SCENE.instantiate() as PlayerCharacter
			_check(player != null, "The look-interaction fixture should instantiate a player.")
			if player != null:
				player.position = Vector3(0, 0, 2.0)
				add_child(player)
				for _frame in 4:
					await get_tree().physics_frame
				_check(
					not behavior.automatic_proximity_prompt
					and not behavior.is_healing_sequence_active(),
					"The authored Center attendant should wait for explicit interaction."
				)
				var detector := player.get_node_or_null(
					^"LookInteraction"
				) as RNDPlayerInteractionDetector
				_check(
					detector != null and detector.get_current_target() == healer_character,
					"Looking at the Center attendant should select her as the interaction target."
				)
				_check(
					detector != null and detector.try_interact(),
					"Pressing interact should open the healer conversation."
				)
				await _wait_for_sequence_state(behavior, true)
				var interaction_template := _only_template()
				_check(
					interaction_template != null and interaction_template.dismiss_button.visible,
					"The interaction prompt should expose the decline action."
				)
				if interaction_template != null:
					interaction_template.dismiss_button.pressed.emit()
				await _wait_for_sequence_state(behavior, false)
				await get_tree().process_frame
				_check(
					not behavior.is_healing_sequence_active() and _template_count() == 0,
					"Declining should close the interaction conversation."
				)
				for _frame in 3:
					await get_tree().physics_frame
				_check(
					detector != null and detector.get_current_target() == healer_character,
					"Remaining in view should offer a later interaction without auto-opening it."
				)
				_check(
					detector != null and detector.try_interact(),
					"The player should be able to explicitly start a later visit."
				)
				await _wait_for_sequence_state(behavior, true)
				_check(
					behavior.is_healing_sequence_active(),
					"A later interaction should start a new healer conversation."
				)
				behavior.cancel_healing_sequence()
				await _wait_for_sequence_state(behavior, false)
				player.queue_free()
				await get_tree().process_frame
		healer_character.queue_free()
		await get_tree().process_frame
		GameInstance.set_player_movement_enabled(true)
		await _close_all_templates()

	CollectionSystem.clear_collection()
	var damaged := CollectionSystem.add_pokemon(25, 5, 0.25, -1, 1)
	var fainted := CollectionSystem.add_pokemon(1, 5, 0.0, -1, 3)
	var healthy := CollectionSystem.add_pokemon(4, 5, 1.0, -1, 6)
	var stored := CollectionSystem.add_pokemon(7, 5, 0.2)
	_check(
		[damaged, fainted, healthy, stored].all(func(pcl: Dictionary) -> bool: return not pcl.is_empty()),
		"The healer test collection should be created."
	)

	CollectionSystem.collection_changed.connect(_on_collection_changed)
	_collection_change_count = 0
	var behavior := PokemonCenterHealerBehavior.new()
	behavior.healing_sequence_started.connect(_on_sequence_started)
	behavior.party_healed.connect(_on_party_healed)
	behavior.healing_sequence_finished.connect(_on_sequence_finished)

	_check(behavior.start_healing_sequence(), "A free healer should start its UI sequence.")
	await get_tree().process_frame
	_check(behavior.is_healing_sequence_active(), "The healer sequence should remain active at confirmation.")
	_check(not GameInstance.is_player_movement_enabled(), "The confirmation should hold the movement lock.")
	_check(_sequence_started_count == 1, "The healer should announce one started sequence.")
	var template := _only_template()
	_check(template != null, "The healer should display one UI template.")
	if template != null:
		_check(template.message_label.text == behavior.prompt_text, "The first UI step should ask to heal the party.")
		_check(template.speaker_label.text == behavior.speaker_name, "The UI should identify the Center attendant.")
		_check(template.dismiss_button.visible, "The confirmation should offer a Not now action.")
		_check(
			template.action_button.size.y >= 40.0 and template.dismiss_button.size.y >= 40.0,
			"Both healer actions should retain at least 40 px mobile touch height."
		)
		template.action_button.pressed.emit()

	_check(_party_healed_count == 1, "Confirming should perform exactly one party heal.")
	_check(_last_restored_count == 2, "Only the damaged and fainted party members should be restored.")
	_check(_collection_change_count == 1, "Party healing should emit one atomic collection update.")
	for pcl: Dictionary in CollectionSystem.get_party():
		_check(
			is_equal_approx(float(pcl["instanceStats"]["health"]), 1.0),
			"Every current party member should be at full health."
		)
	_check(
		is_equal_approx(
			float(CollectionSystem.get_pcl(String(stored["pclID"]))["instanceStats"]["health"]),
			0.2
		),
		"A stored Pokemon should not be healed."
	)
	_check(template == _only_template(), "The result should reuse the same UI template.")
	if template != null:
		_check(template.message_label.text == behavior.healed_text, "The result should confirm full health.")
		_check(not template.dismiss_button.visible, "The completed sequence should collapse to one Done action.")
		template.action_button.pressed.emit()
	await get_tree().process_frame
	_check(not behavior.is_healing_sequence_active(), "Done should finish the healer sequence.")
	_check(GameInstance.is_player_movement_enabled(), "Finishing should restore player movement.")
	_check(_sequence_finished_count == 1, "The completed UI should emit one finish signal.")
	_check(_template_count() == 0, "The healer should retire its owned UI template.")

	_check(behavior.start_healing_sequence(), "The attendant should support a later repeat visit.")
	await get_tree().process_frame
	template = _only_template()
	if template != null:
		template.action_button.pressed.emit()
		_check(
			template.message_label.text == behavior.already_healthy_text,
			"A full-health party should receive the already-healthy result."
		)
		template.action_button.pressed.emit()
	await get_tree().process_frame
	_check(_last_restored_count == 0, "A healthy party should report zero restored members.")
	_check(_collection_change_count == 1, "A no-op heal should not emit another collection update.")

	CollectionSystem.clear_collection()
	_collection_change_count = 0
	_check(behavior.start_healing_sequence(), "An empty party should still receive a helpful message.")
	await get_tree().process_frame
	template = _only_template()
	_check(template != null, "The empty-party result should display a UI template.")
	if template != null:
		_check(template.message_label.text == behavior.empty_party_text, "The empty-party branch should explain the issue.")
		_check(not template.dismiss_button.visible, "The empty-party result should have one compact action.")
		template.action_button.pressed.emit()
	await get_tree().process_frame
	_check(_collection_change_count == 0, "The empty-party branch should not emit a collection update.")
	_check(GameInstance.is_player_movement_enabled(), "The empty-party result should release movement.")

	GameInstance.set_player_movement_enabled(false)
	_check(
		not behavior.start_healing_sequence(),
		"The healer should not overlap a sequence that already owns movement."
	)
	_check(_template_count() == 0, "A rejected overlapping sequence should not create UI.")
	GameInstance.set_player_movement_enabled(true)

	CollectionSystem.collection_changed.disconnect(_on_collection_changed)
	CollectionSystem.clear_collection()
	_check(
		CollectionSystem.load_save_data(original_collection),
		"The original test-process collection should restore cleanly."
	)
	GameInstance.set_player_movement_enabled(original_movement_enabled)

	if _failures.is_empty():
		print(
			"Pokemon Center healer smoke test passed: 7,656-triangle male clerk, 40 px touch actions, "
			+ "look-button confirmation, atomic party-only healing, repeat/empty branches, UI cleanup, "
			+ "and movement ownership verified."
		)
		get_tree().quit(0)
		return

	for failure in _failures:
		push_error("Pokemon Center healer smoke test failed: %s" % failure)
	get_tree().quit(1)


func _close_all_templates() -> void:
	for child: Node in UIManager.get_children():
		if child is UITemplate:
			(child as UITemplate).close()
	await get_tree().process_frame


func _wait_for_sequence_state(
	behavior: PokemonCenterHealerBehavior,
	is_active: bool
) -> void:
	for _frame in 16:
		if behavior.is_healing_sequence_active() == is_active:
			return
		await get_tree().physics_frame


func _collect_mesh_instances(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		_collect_mesh_instances(child, output)


func _only_template() -> UITemplate:
	for child: Node in UIManager.get_children():
		if child is UITemplate:
			return child as UITemplate
	return null


func _template_count() -> int:
	var count := 0
	for child: Node in UIManager.get_children():
		if child is UITemplate:
			count += 1
	return count


func _on_collection_changed() -> void:
	_collection_change_count += 1


func _on_sequence_started() -> void:
	_sequence_started_count += 1


func _on_party_healed(restored_count: int) -> void:
	_party_healed_count += 1
	_last_restored_count = restored_count


func _on_sequence_finished() -> void:
	_sequence_finished_count += 1


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
