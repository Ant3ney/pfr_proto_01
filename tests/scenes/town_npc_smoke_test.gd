extends Node

const CITY_PATH := "res://game/world/levels/new_bouffalant_city/new_bouffalant_city.tscn"
const MIARE_STATION_PATH := (
	"res://game/world/levels/new_bouffalant_city/interiors/miare_station_concourse.tscn"
)
const XP_SHARE_GIFT_ID := "new-bouffalant-lumen-exp-share"
const INTERIOR_RESIDENT_FIXTURES := [
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/city_hall_interior.tscn",
		"resident_name": "Elian",
		"navigation_name": "ElianRoamingNavigation",
	},
	{
		"scene_path": MIARE_STATION_PATH,
		"resident_name": "Pia",
		"navigation_name": "PiaRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/gatehouse_interior.tscn",
		"resident_name": "Ren",
		"navigation_name": "RenRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/west_tenant_lobby.tscn",
		"resident_name": "Jo",
		"navigation_name": "JoRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/north_tenant_lobby.tscn",
		"resident_name": "Jo",
		"navigation_name": "JoRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/museum_gallery.tscn",
		"resident_name": "Sol",
		"navigation_name": "SolRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_interior.tscn",
		"resident_name": "Arden",
		"navigation_name": "ArdenRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/pokemon_center/pokemon_center_annex.tscn",
		"resident_name": "Miko",
		"navigation_name": "MikoRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/garage_workshop.tscn",
		"resident_name": "Dax",
		"navigation_name": "DaxRoamingNavigation",
	},
	{
		"scene_path": "res://game/world/levels/new_bouffalant_city/interiors/rouge_tower_lobby.tscn",
		"resident_name": "Vesper",
		"navigation_name": "VesperRoamingNavigation",
	},
]

var _failures: Array[String] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var original_collection := CollectionSystem.get_save_data()
	var original_inventory := InventorySystem.get_save_data()
	InventorySystem.reset_progress()
	GameInstance.set_player_movement_enabled(true)

	var packed := load(CITY_PATH) as PackedScene
	var city := packed.instantiate() if packed != null else null
	_check(city != null, "The primary development environment should instantiate.")
	if city == null:
		_finish(original_collection, original_inventory)
		return
	add_child(city)
	for _frame in 4:
		await get_tree().physics_frame

	var residents := city.get_node_or_null(^"Gameplay/Actors/TownResidents")
	_check(residents != null, "The town should own a dedicated TownResidents group.")
	if residents == null:
		city.queue_free()
		_finish(original_collection, original_inventory)
		return
	_check(residents.get_child_count() == 13, "The town should contain thirteen conversational residents.")

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
		var static_blocker := _static_blocker_at(resident.global_position, city)
		_check(
			static_blocker.is_empty(),
			"%s should begin on open town ground rather than inside a building collider (%s)."
			% [resident.name, static_blocker]
		)

	resident_names.sort()
	_check(
		resident_names == [
			"Aya",
			"Bram",
			"Cam",
			"Dax",
			"Elian",
			"Iris",
			"Mara",
			"Nia",
			"Pia",
			"Ren",
			"ResearcherLumen",
			"Sol",
			"Theo",
		],
		"The authored resident roster should remain stable."
	)
	_check(women_model_count >= 3, "At least three town residents should use clearly authored women models.")
	_check(roaming_count == 9, "Exactly nine residents should use the separate local-roaming behavior.")
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
		var city_grid := city.get_node_or_null(^"NavigationRegion3D/WorldGeometry/Ground/ModularGroundGrid") as GridMap
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
			InventorySystem.get_item_count(InventoryService.XP_SHARE_ITEM_KEY) == 1
			and InventorySystem.has_claimed_gift(XP_SHARE_GIFT_ID)
			and "You received an Exp. Share!" in " ".join(lumen_behavior._active_lines),
			"Lumen's first conversation should grant and announce exactly one Exp. Share."
		)
		lumen_behavior.cancel_conversation()
		await get_tree().process_frame
		_check(lumen.interact(player), "Lumen should remain conversational after the gift.")
		_check(
			InventorySystem.get_item_count(InventoryService.XP_SHARE_ITEM_KEY) == 1
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
	await _test_interior_residents()
	_finish(original_collection, original_inventory)


func _test_interior_residents() -> void:
	for fixture: Dictionary in INTERIOR_RESIDENT_FIXTURES:
		var scene_path := String(fixture["scene_path"])
		var resident_name := String(fixture["resident_name"])
		var navigation_name := String(fixture["navigation_name"])
		var packed := load(scene_path) as PackedScene
		_check(packed != null, "%s should load." % scene_path)
		if packed == null:
			continue

		var interior := packed.instantiate() as Node3D
		_check(interior != null, "%s should instantiate." % scene_path)
		if interior == null:
			continue
		add_child(interior)
		for _frame in 8:
			await get_tree().physics_frame

		var resident := interior.get_node_or_null(
			"Gameplay/Actors/%s" % resident_name
		) as PFRCharacter
		var navigation := interior.get_node_or_null(navigation_name) as NavigationRegion3D
		_check(
			resident != null,
			"%s should contain the ambient resident %s." % [scene_path, resident_name]
		)
		_check(
			navigation != null and navigation.navigation_mesh != null,
			"%s should provide %s with a bounded navigation patch."
			% [scene_path, resident_name]
		)

		if resident != null:
			_check(
				_static_blocker_at(resident.global_position, interior).is_empty(),
				"%s should begin clear of interior static collision." % resident_name
			)
			var behavior := (
				resident.controller.npc_behavior if resident.controller != null else null
			)
			_check(
				behavior is RoamingTownNpcBehavior,
				"%s should use bounded roaming behavior indoors." % resident_name
			)
			if behavior is RoamingTownNpcBehavior:
				_verify_interior_roaming_clearance(
					resident,
					behavior as RoamingTownNpcBehavior,
					interior
				)
				await _verify_resident_roams(resident, behavior as RoamingTownNpcBehavior)

		if scene_path == MIARE_STATION_PATH:
			_verify_miare_station_exit_mat(interior)

		interior.queue_free()
		await get_tree().process_frame


func _verify_interior_roaming_clearance(
	resident: PFRCharacter,
	roaming: RoamingTownNpcBehavior,
	interior: Node3D
) -> void:
	for direction: Vector3 in [
		Vector3.FORWARD,
		Vector3.BACK,
		Vector3.LEFT,
		Vector3.RIGHT,
		Vector3(-1.0, 0.0, -1.0).normalized(),
		Vector3(1.0, 0.0, -1.0).normalized(),
		Vector3(-1.0, 0.0, 1.0).normalized(),
		Vector3(1.0, 0.0, 1.0).normalized(),
	]:
		var patrol_point: Vector3 = (
			resident.global_position + direction * roaming.roaming_radius
		)
		var blocker := _static_blocker_at(patrol_point, interior)
		_check(
			blocker.is_empty(),
			"%s's indoor roaming radius should stay clear of static collision (%s)."
			% [resident.name, blocker]
		)


func _verify_resident_roams(
	resident: PFRCharacter,
	roaming: RoamingTownNpcBehavior
) -> void:
	var starting_position := resident.global_position
	roaming.minimum_pause_seconds = 0.0
	roaming.maximum_pause_seconds = 0.0
	resident.controller.stop_moving(resident)
	roaming._origin_initialized = false
	roaming._moving = false
	roaming._wait_until_msec = 0
	roaming.process_behavior(resident, resident.controller)
	_check(
		roaming.is_currently_roaming(),
		"%s should choose a nearby indoor patrol target." % resident.name
	)
	var patrol_offset := resident.controller.map_coordinates - roaming.get_roaming_origin()
	patrol_offset.y = 0.0
	_check(
		patrol_offset.length() <= roaming.roaming_radius + 0.01,
		"%s should remain within its authored indoor roaming radius." % resident.name
	)

	var moved := false
	for _frame in 75:
		await get_tree().physics_frame
		var planar_offset := resident.global_position - starting_position
		planar_offset.y = 0.0
		if planar_offset.length() > 0.08:
			moved = true
			break
	_check(moved, "%s should physically move on its interior navigation patch." % resident.name)


func _verify_miare_station_exit_mat(interior: Node3D) -> void:
	var exit_to_city := interior.get_node_or_null(
		^"Gameplay/Transitions/ExitToCity"
	) as Area3D
	var exit_mat := interior.get_node_or_null(
		^"NavigationRegion3D/WorldGeometry/Props/CityExitMat"
	) as MeshInstance3D
	_check(exit_to_city != null, "Miare Station should retain its ExitToCity transition.")
	_check(exit_mat != null, "Miare Station should show a red mat beneath its city exit.")
	if exit_to_city == null or exit_mat == null:
		return

	var trigger_collision := exit_to_city.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	var trigger_shape := (
		trigger_collision.shape as BoxShape3D if trigger_collision != null else null
	)
	var mat_mesh := exit_mat.mesh as BoxMesh
	var mat_material := mat_mesh.material as StandardMaterial3D if mat_mesh != null else null
	_check(
		exit_to_city.position.is_equal_approx(Vector3(0.0, 0.0, 4.68))
		and exit_to_city.scale.is_equal_approx(Vector3(1.45, 1.0, 0.9))
		and trigger_collision != null
		and trigger_collision.position.is_equal_approx(Vector3(0.0, 1.0, 0.0))
		and trigger_shape != null
		and trigger_shape.size.is_equal_approx(Vector3(2.0, 2.0, 1.0)),
		"Adding the station exit affordance must not change its transition collision."
	)
	_check(
		mat_mesh != null
		and mat_mesh.size.is_equal_approx(Vector3(2.9, 0.025, 0.9))
		and is_equal_approx(exit_mat.global_position.x, exit_to_city.global_position.x)
		and is_equal_approx(exit_mat.global_position.z, exit_to_city.global_position.z),
		"The station exit mat should match and center beneath the transition footprint."
	)
	_check(
		mat_material != null
		and mat_material.albedo_color.r > 0.6
		and mat_material.albedo_color.g < 0.1
		and mat_material.albedo_color.b < 0.1,
		"The station exit affordance should be visibly red."
	)
	_check(
		exit_mat.find_children("*", "CollisionShape3D", true, false).is_empty(),
		"The station exit mat should remain visual-only and add no collision."
	)


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


func _finish(original_collection: Array[Dictionary], original_inventory: Dictionary) -> void:
	GameInstance.set_player_movement_enabled(true)
	CollectionSystem.load_save_data(original_collection)
	InventorySystem.load_save_data(original_inventory)
	if _failures.is_empty():
		print(
			"Town NPC smoke test passed: thirteen outdoor residents, nine outdoor roamers, "
			+ "ten interior roamers, the Miare Station exit mat, repeatable dialog, and "
			+ "Lumen's one-time Exp. Share gift verified."
		)
		get_tree().quit(0)
		return
	for failure in _failures:
		push_error("Town NPC smoke test failed: %s" % failure)
	get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
