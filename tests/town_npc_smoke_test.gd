extends Node

const CITY_PATH := "res://demo/primary_development_enviroment.tscn"
const XP_SHARE_GIFT_ID := "new-bouffalant-lumen-exp-share"

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_stretch := StretchGoalSystem.get_save_data()
	var isolated_stretch := original_stretch.duplicate(true)
	isolated_stretch["item_inventory"] = {}
	isolated_stretch["claimed_gifts"] = []
	_check(
		StretchGoalSystem.load_save_data(isolated_stretch),
		"The town NPC fixture should isolate its gift inventory."
	)
	GameInstance.set_player_movement_enabled(true)

	var packed := load(CITY_PATH) as PackedScene
	var city := packed.instantiate() if packed != null else null
	_check(city != null, "The primary development environment should instantiate.")
	if city == null:
		_finish(original_collection, original_stretch)
		return
	add_child(city)
	for _frame in 4:
		await get_tree().physics_frame

	var residents := city.get_node_or_null(^"TownResidents")
	_check(residents != null, "The town should own a dedicated TownResidents group.")
	if residents == null:
		city.queue_free()
		_finish(original_collection, original_stretch)
		return
	_check(residents.get_child_count() == 7, "The town should contain seven conversational residents.")

	var resident_names: Array[String] = []
	var roaming_count := 0
	var women_model_count := 0
	var combined_lore := ""
	for child in residents.get_children():
		var resident := child as PFRCharacter
		_check(resident != null, "%s should be a PFRCharacter." % child.name)
		if resident == null:
			continue
		resident_names.append(String(resident.name))
		var behavior := resident.controller.npc_behavior if resident.controller != null else null
		_check(
			behavior is TownNpcBehavior and not behavior is TrainerBehavior,
			"%s should talk without owning trainer or battle behavior." % resident.name
		)
		if behavior is TownNpcBehavior:
			var town_behavior := behavior as TownNpcBehavior
			_check(
				not town_behavior.speaker_name.strip_edges().is_empty()
				and not town_behavior.dialog_lines.is_empty(),
				"%s should have authored speaker and dialog data." % resident.name
			)
			combined_lore += " " + " ".join(town_behavior.dialog_lines)
			combined_lore += " " + " ".join(town_behavior.gift_dialog_lines)
			combined_lore += " " + " ".join(town_behavior.claimed_gift_dialog_lines)
		if behavior is RoamingTownNpcBehavior:
			roaming_count += 1
		var art_path := resident.character_art_asset_pack.resource_path
		if (
			"za_tr0007_friend_f" in art_path
			or "za_tr0010_nu_boss_f" in art_path
			or "za_tr0006_secretary" in art_path
		):
			women_model_count += 1
		_check(
			_static_blocker_at(resident.global_position, city).is_empty(),
			"%s should begin on open town ground rather than inside a building collider."
			% resident.name
		)

	resident_names.sort()
	_check(
		resident_names == ["Bram", "Cam", "Iris", "Mara", "Nia", "ResearcherLumen", "Theo"],
		"The authored resident roster should remain stable."
	)
	_check(women_model_count >= 3, "At least three town residents should use clearly authored women models.")
	_check(roaming_count == 3, "Exactly three residents should use the separate local-roaming behavior.")
	_check(
		"Team Bastion" in combined_lore
		and "rival borough" in combined_lore
		and "regional councils fractured" in combined_lore,
		"Resident conversations should build civic history, regional division, and Team Bastion lore."
	)

	var player := city.get_node_or_null(^"Player") as PlayerCharacter
	var mara := residents.get_node_or_null(^"Mara") as PFRCharacter
	_check(player != null and mara != null, "The conversation fixture should find the player and Mara.")
	if player != null and mara != null:
		var mara_behavior := mara.controller.npc_behavior as TownNpcBehavior
		_check(
			mara.can_interact(player) and mara.get_interaction_prompt(player) == "Talk to Mara",
			"A nearby resident should advertise a Talk interaction rather than a battle."
		)
		_check(mara.interact(player), "Mara should accept the shared interaction request.")
		_check(
			mara_behavior.is_conversation_active()
			and not GameInstance.is_player_movement_enabled(),
			"A town conversation should own its UI and movement lock."
		)
		for _line in 8:
			if not mara_behavior.is_conversation_active():
				break
			mara_behavior.advance_conversation()
			await get_tree().process_frame
		_check(
			not mara_behavior.is_conversation_active()
			and GameInstance.is_player_movement_enabled(),
			"Finishing town dialog should restore player movement without starting a battle."
		)

	var lumen := residents.get_node_or_null(^"ResearcherLumen") as PFRCharacter
	_check(lumen != null, "Researcher Lumen should be present in town.")
	if lumen != null:
		var city_grid := city.get_node_or_null(^"NavigationRegion3D/ModularGroundGrid") as GridMap
		_check(city_grid != null, "The town NPC fixture should find the authored city paving.")
		if city_grid != null:
			var lumen_cell := city_grid.local_to_map(city_grid.to_local(lumen.global_position))
			_check(
				city_grid.get_cell_item(lumen_cell) != GridMap.INVALID_CELL_ITEM,
				"Researcher Lumen should stand on authored cobblestone instead of the grass underlay."
			)
	if player != null and lumen != null:
		var lumen_behavior := lumen.controller.npc_behavior as TownNpcBehavior
		_check(lumen.interact(player), "Researcher Lumen should accept the first conversation.")
		_check(
			StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 1
			and StretchGoalSystem.has_claimed_gift(XP_SHARE_GIFT_ID)
			and "You received an Exp. Share!" in " ".join(lumen_behavior._active_lines),
			"Lumen's first conversation should grant and announce exactly one Exp. Share."
		)
		lumen_behavior.cancel_conversation()
		await get_tree().process_frame
		_check(lumen.interact(player), "Lumen should remain conversational after the gift.")
		_check(
			StretchGoalSystem.get_item_count(StretchGoalSystem.XP_SHARE_ITEM_KEY) == 1
			and "League may be divided" in " ".join(lumen_behavior._active_lines),
			"Repeated conversations should use lore dialog without duplicating the unique gift."
		)
		lumen_behavior.cancel_conversation()
		await get_tree().process_frame

	var cam := residents.get_node_or_null(^"Cam") as PFRCharacter
	if cam != null and cam.controller.npc_behavior is RoamingTownNpcBehavior:
		var roaming := cam.controller.npc_behavior as RoamingTownNpcBehavior
		roaming.minimum_pause_seconds = 0.0
		roaming.maximum_pause_seconds = 0.0
		cam.controller.stop_moving(cam)
		roaming._moving = false
		roaming._wait_until_msec = 0
		roaming.process_behavior(cam, cam.controller)
		_check(roaming.is_currently_roaming(), "A roaming resident should choose a nearby patrol target.")
		var patrol_offset := cam.controller.map_coordinates - roaming.get_roaming_origin()
		patrol_offset.y = 0.0
		_check(
			patrol_offset.length() <= roaming.roaming_radius + 0.01,
			"A roaming resident should stay within its small authored town radius."
		)

	city.queue_free()
	await get_tree().process_frame
	_finish(original_collection, original_stretch)


func _static_blocker_at(position: Vector3, city: Node3D) -> String:
	var world := city.get_world_3d()
	if world == null:
		return "missing world"
	var shape := SphereShape3D.new()
	shape.radius = 0.22
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3(0, 0.85, 0))
	query.collision_mask = 1
	query.collide_with_areas = false
	query.collide_with_bodies = true
	for hit: Dictionary in world.direct_space_state.intersect_shape(query, 32):
		var collider := hit.get("collider") as Node
		if collider is StaticBody3D:
			return String(collider.get_path())
	return ""


func _finish(original_collection: Array[Dictionary], original_stretch: Dictionary) -> void:
	GameInstance.set_player_movement_enabled(true)
	CollectionSystem.load_save_data(original_collection)
	StretchGoalSystem.load_save_data(original_stretch)
	if _failures.is_empty():
		print(
			"Town NPC smoke test passed: seven non-battling lore residents, three women models, "
			+ "three local roamers, repeatable dialog, and Lumen's one-time Exp. Share gift verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Town NPC smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
