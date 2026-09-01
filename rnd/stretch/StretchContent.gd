class_name RNDStretchContent
extends RefCounted

## Authored R&D destination and opponent rosters used by Stretchman's hub.

const DESTINATION_SCENE_PATH := "res://rnd/stretch/worlds/stretch_destination.tscn"
const BATTLE_SCENE_PATH := "res://rnd/stretch/battle/stretch_battle_scene.tscn"
const ROUTE_ZERO_SCENE_PATH := "res://overworld/route_0/route_0.tscn"
const ROUTE_COUNT := 40
const ROUTES_PER_LEVEL_BAND := 4

const GYM_DATA: Array[Dictionary] = [
	{
		"index": 1,
		"name": "Gym 1 — Granite Hall",
		"description": "A first badge match against a Rock specialist (Lv. 12–14).",
		"leader": "Leader Petra",
		"team": [[74, 12], [95, 14]],
	},
	{
		"index": 2,
		"name": "Gym 2 — Tidal Court",
		"description": "A Water specialist's mirrored arena (Lv. 18–20).",
		"leader": "Leader Marina",
		"team": [[120, 18], [121, 20]],
	},
	{
		"index": 3,
		"name": "Gym 3 — Dynamo Works",
		"description": "An Electric team built to punish slow challengers (Lv. 23–27).",
		"leader": "Leader Volta",
		"team": [[81, 23], [25, 25], [26, 27]],
	},
	{
		"index": 4,
		"name": "Gym 4 — Verdant House",
		"description": "A status-heavy Grass progression battle (Lv. 29–33).",
		"leader": "Leader Briar",
		"team": [[43, 29], [44, 31], [45, 33]],
	},
	{
		"index": 5,
		"name": "Gym 5 — Miasma Lab",
		"description": "Poison and Ghost pressure in a compact lab (Lv. 34–38).",
		"leader": "Leader Vesper",
		"team": [[109, 34], [110, 36], [94, 38]],
	},
	{
		"index": 6,
		"name": "Gym 6 — Mirage Stage",
		"description": "A Psychic specialist with four battle-ready partners (Lv. 39–44).",
		"leader": "Leader Satori",
		"team": [[64, 39], [65, 41], [122, 42], [124, 44]],
	},
	{
		"index": 7,
		"name": "Gym 7 — Astral Vault",
		"description": "A high-level cosmic and Steel roster (Lv. 45–51).",
		"leader": "Leader Solenne",
		"team": [[337, 45], [338, 47], [344, 49], [376, 51]],
	},
	{
		"index": 8,
		"name": "Gym 8 — Dragon Crown",
		"description": "The final badge trial fields five Dragons (Lv. 50–58).",
		"leader": "Leader Drayke",
		"team": [[147, 50], [148, 52], [130, 54], [445, 55], [149, 58]],
	},
]

## Twenty biome families are each used twice across the forty-route chain. The
## second visit has a distinct deeper title, stronger route geometry, and a
## later level band. Four neighboring routes deliberately share each level
## band so progression offers environmental variety instead of one route per
## level range.
const ROUTE_BIOMES: Array[Dictionary] = [
	{
		"id": "clover-meadow", "title": "Clover Verge", "deep_title": "Clover Labyrinth",
		"biome": "flower meadow", "decor": "trees", "pool": [19, 16, 10, 13, 29, 32, 21, 43],
		"sky": "75bff2", "ambient": "d9f1ff", "ground": "4f9b4d", "path": "9a7046",
		"wall": "255d2b", "accent": "f4df69", "foliage": "3eaa49",
	},
	{
		"id": "sunflower-prairie", "title": "Sunpetal Prairie", "deep_title": "Sunpetal Maze",
		"biome": "sunflower prairie", "decor": "flowers", "pool": [161, 163, 187, 191, 192, 203, 234, 427],
		"sky": "83c9f4", "ambient": "fff0bf", "ground": "75a84d", "path": "b58549",
		"wall": "496b2d", "accent": "ffd84f", "foliage": "78b743",
	},
	{
		"id": "oldgrowth-forest", "title": "Bramblewood Cut", "deep_title": "Bramblewood Depths",
		"biome": "old-growth forest", "decor": "trees", "pool": [41, 43, 69, 46, 48, 27, 23, 52],
		"sky": "6e9f9a", "ambient": "b7d1b5", "ground": "315f39", "path": "745638",
		"wall": "173c26", "accent": "9bd36a", "foliage": "2e7440",
	},
	{
		"id": "mist-marsh", "title": "Mistral Fen", "deep_title": "Mistral Sink",
		"biome": "mist marsh", "decor": "reeds", "pool": [54, 60, 72, 98, 118, 129, 90, 116],
		"sky": "7694a0", "ambient": "bed1cf", "ground": "456d59", "path": "7a6850",
		"wall": "294b43", "accent": "74d7c5", "foliage": "5a9472",
	},
	{
		"id": "redrock-canyon", "title": "Redrock Switchback", "deep_title": "Redrock Crucible",
		"biome": "redrock canyon", "decor": "rocks", "pool": [21, 23, 56, 66, 74, 77, 58, 111],
		"sky": "d68b69", "ambient": "ffd0a7", "ground": "9b573b", "path": "c68a55",
		"wall": "713722", "accent": "ffb45f", "foliage": "77763a",
	},
	{
		"id": "azure-coast", "title": "Azure Bluff", "deep_title": "Azure Undertow",
		"biome": "coastal bluff", "decor": "reeds", "pool": [72, 90, 98, 116, 170, 194, 278, 320],
		"sky": "5baee8", "ambient": "d8f5ff", "ground": "4f9074", "path": "d1ad72",
		"wall": "2e6570", "accent": "63e3ed", "foliage": "66aa72",
	},
	{
		"id": "amber-savanna", "title": "Amber Savanna", "deep_title": "Amber Stampede",
		"biome": "dry savanna", "decor": "rocks", "pool": [179, 203, 228, 234, 239, 261, 307, 522],
		"sky": "dfaa69", "ambient": "ffe2a8", "ground": "9b8b45", "path": "bd8150",
		"wall": "6d5b30", "accent": "f1cf57", "foliage": "849444",
	},
	{
		"id": "ember-caldera", "title": "Ember Caldera", "deep_title": "Ember Maw",
		"biome": "volcanic caldera", "decor": "vents", "pool": [37, 58, 77, 126, 218, 219, 322, 324],
		"sky": "632d36", "ambient": "d27052", "ground": "4d3533", "path": "7d4937",
		"wall": "2b2022", "accent": "ff6b35", "foliage": "775643",
	},
	{
		"id": "stormworks", "title": "Static Yard", "deep_title": "Stormworks Core",
		"biome": "storm-powered industrial yard", "decor": "pillars", "pool": [81, 92, 100, 109, 123, 125, 126, 135],
		"sky": "50627d", "ambient": "a8b8d8", "ground": "48545a", "path": "747a70",
		"wall": "29333d", "accent": "75e6ff", "foliage": "527d68",
	},
	{
		"id": "moonlit-fen", "title": "Moonlit Walk", "deep_title": "Moonlit Hollow",
		"biome": "moonlit fen", "decor": "mushrooms", "pool": [133, 147, 172, 175, 200, 203, 207, 214],
		"sky": "252c58", "ambient": "7779a8", "ground": "32475a", "path": "5e5268",
		"wall": "1d2843", "accent": "bda7ff", "foliage": "446d69",
	},
	{
		"id": "frostpine", "title": "Frostpine Trail", "deep_title": "Frostpine Whiteout",
		"biome": "snowy pine forest", "decor": "pines", "pool": [215, 220, 228, 246, 280, 304, 302, 308],
		"sky": "90b6d3", "ambient": "e7f6ff", "ground": "829ca1", "path": "bac4bf",
		"wall": "49666a", "accent": "d5fbff", "foliage": "47746c",
	},
	{
		"id": "bamboo-grove", "title": "Jade Bamboo Run", "deep_title": "Jade Bamboo Snare",
		"biome": "bamboo grove", "decor": "bamboo", "pool": [83, 123, 127, 163, 273, 274, 285, 357],
		"sky": "8fc6a3", "ambient": "d6edbf", "ground": "537b45", "path": "9b8050",
		"wall": "30552f", "accent": "a9e56b", "foliage": "5f9f46",
	},
	{
		"id": "crystal-cavern", "title": "Prism Cavern", "deep_title": "Prism Abyss",
		"biome": "crystal cavern", "decor": "crystals", "pool": [74, 95, 299, 302, 337, 338, 525, 703],
		"sky": "24223f", "ambient": "716a9c", "ground": "393653", "path": "635b76",
		"wall": "201d35", "accent": "75e4ef", "foliage": "5d6f8f",
	},
	{
		"id": "haunted-thicket", "title": "Wispwood Thicket", "deep_title": "Wispwood Haunt",
		"biome": "haunted thicket", "decor": "mushrooms", "pool": [92, 93, 200, 302, 353, 355, 425, 442],
		"sky": "312743", "ambient": "806f92", "ground": "3e4a3e", "path": "66576a",
		"wall": "252c2d", "accent": "dd82ff", "foliage": "536b53",
	},
	{
		"id": "desert-ruins", "title": "Sirocco Ruins", "deep_title": "Sirocco Vault",
		"biome": "desert ruins", "decor": "pillars", "pool": [27, 50, 74, 95, 111, 328, 331, 449],
		"sky": "d7a76d", "ambient": "ffe0ad", "ground": "b28b56", "path": "d2ad72",
		"wall": "82643f", "accent": "ffd17a", "foliage": "8c844a",
	},
	{
		"id": "autumn-highlands", "title": "Copperleaf Rise", "deep_title": "Copperleaf Gauntlet",
		"biome": "autumn highlands", "decor": "trees", "pool": [58, 128, 190, 198, 207, 234, 335, 585],
		"sky": "b67f72", "ambient": "f4c39e", "ground": "805d3e", "path": "aa784d",
		"wall": "5e3b2e", "accent": "ff9c4a", "foliage": "a05f37",
	},
	{
		"id": "mangrove-delta", "title": "Mangrove Delta", "deep_title": "Mangrove Tangle",
		"biome": "mangrove delta", "decor": "reeds", "pool": [60, 98, 102, 193, 270, 341, 349, 536],
		"sky": "668f93", "ambient": "bad4c7", "ground": "3f6757", "path": "75664b",
		"wall": "29483d", "accent": "6fd9ad", "foliage": "4b8560",
	},
	{
		"id": "obsidian-wastes", "title": "Obsidian Wastes", "deep_title": "Obsidian Furnace",
		"biome": "obsidian badlands", "decor": "vents", "pool": [95, 208, 229, 248, 323, 324, 464, 631],
		"sky": "382a32", "ambient": "875149", "ground": "302c31", "path": "594348",
		"wall": "1b191d", "accent": "e85d3f", "foliage": "5d4b42",
	},
	{
		"id": "aurora-tundra", "title": "Aurora Tundra", "deep_title": "Aurora Crevasse",
		"biome": "aurora tundra", "decor": "crystals", "pool": [124, 215, 221, 225, 361, 362, 459, 613],
		"sky": "33587a", "ambient": "9bd7cf", "ground": "6b8e92", "path": "a8c2b9",
		"wall": "395b64", "accent": "84ffd3", "foliage": "56877d",
	},
	{
		"id": "victory-summit", "title": "Victory Approach", "deep_title": "Victory Summit",
		"biome": "alpine victory highlands", "decor": "pillars", "pool": [359, 361, 371, 374, 443, 447, 633, 636],
		"sky": "655b91", "ambient": "d0c8ed", "ground": "56616a", "path": "9b8f84",
		"wall": "343845", "accent": "f3cf70", "foliage": "667a64",
	},
]

const CHAMPION_ENCOUNTERS: Array[Dictionary] = [
	{
		"id": "stretch-elite-four-1",
		"name": "Elite Four Terra",
		"team": [[450, 62], [473, 64], [472, 65], [445, 66]],
	},
	{
		"id": "stretch-elite-four-2",
		"name": "Elite Four Tides",
		"team": [[121, 66], [350, 67], [423, 68], [130, 69], [658, 70]],
	},
	{
		"id": "stretch-elite-four-3",
		"name": "Elite Four Shade",
		"team": [[94, 70], [609, 71], [442, 72], [778, 73], [197, 74]],
	},
	{
		"id": "stretch-elite-four-4",
		"name": "Elite Four Aegis",
		"team": [[212, 74], [227, 75], [448, 76], [376, 77], [823, 78]],
	},
	{
		"id": "stretch-champion",
		"name": "Champion Aurelia",
		"team": [[6, 80], [282, 81], [248, 82], [448, 83], [887, 84], [150, 85]],
	},
]

const BORING_LOOT_POKEMON_IDS: Array[int] = [
	100, # Voltorb
	101, # Electrode
	174, # Igglybuff
	173, # Cleffa
	311, # Plusle
	312, # Minun
	406, # Budew
	458, # Mantyke
	399, # Bidoof
]

const LOOT_BOX_DATA: Array[Dictionary] = [
	{
		"id": "scuffed-parcel",
		"index": 1,
		"name": "Scuffed Parcel",
		"price": 400,
		"level": 10,
		"tier": "Tier 1",
		"quality_label": "Starter and mascot favorites",
		"high_quality_pool": [1, 4, 7, 25, 133, 92, 147],
	},
	{
		"id": "bronze-spinner",
		"index": 2,
		"name": "Bronze Spinner",
		"price": 2_000,
		"level": 20,
		"tier": "Tier 2",
		"quality_label": "Classic fully evolved favorites",
		"high_quality_pool": [3, 6, 9, 94, 130, 143, 196, 197],
	},
	{
		"id": "silver-spinner",
		"index": 3,
		"name": "Silver Spinner",
		"price": 10_000,
		"level": 30,
		"tier": "Tier 3",
		"quality_label": "Pseudo-legends and rare fan favorites",
		"high_quality_pool": [149, 212, 248, 257, 282, 330, 350, 359, 373, 376],
	},
	{
		"id": "gold-spinner",
		"index": 4,
		"name": "Gold Spinner",
		"price": 40_000,
		"level": 40,
		"tier": "Tier 4",
		"quality_label": "Modern high-appeal and pseudo-legend pool",
		"high_quality_pool": [445, 448, 571, 609, 635, 658, 700, 706, 724, 778, 823, 887, 937, 998],
	},
	{
		"id": "ultra-vault",
		"index": 5,
		"name": "Ultra Vault",
		"price": 400_000,
		"level": 50,
		"tier": "Tier 5",
		"quality_label": "Legendary trios and exceptional favorites",
		"high_quality_pool": [144, 145, 146, 243, 244, 245, 377, 378, 379, 445, 448, 638, 639, 640, 887],
	},
	{
		"id": "legend-vault",
		"index": 6,
		"name": "Legend Vault",
		"price": 4_000_000,
		"level": 60,
		"tier": "Tier 6",
		"quality_label": "Top box-art and restricted legendaries",
		"high_quality_pool": [150, 249, 250, 382, 383, 384, 483, 484, 487, 643, 644, 646, 716, 717, 718, 791, 792, 800, 888, 889, 1007, 1008],
	},
]


static func get_loot_boxes() -> Array[Dictionary]:
	return LOOT_BOX_DATA.duplicate(true)


static func get_loot_box(box_id: String) -> Dictionary:
	for offer in LOOT_BOX_DATA:
		if String(offer.get("id", "")) == box_id:
			return offer.duplicate(true)
	return {}


static func get_destinations(kind: String) -> Array[Dictionary]:
	match kind:
		"gym":
			return GYM_DATA.duplicate(true)
		"route":
			var routes: Array[Dictionary] = []
			for route_index in ROUTE_COUNT:
				routes.append(_make_route_destination(route_index))
			return routes
		"champion":
			return [{
				"index": 1,
				"name": "Elite Four + Champion Challenge",
				"description": (
					"Five forced battles in order: Elite Four at Lv. 62–78, then "
					+ "Champion Aurelia at Lv. 80–85."
				),
			}]
	return []


static func get_destination(kind: String, destination_index: int) -> Dictionary:
	for destination in get_destinations(kind):
		if int(destination.get("index", 0)) == destination_index:
			return destination.duplicate(true)
	return {}


static func get_encounters(kind: String, destination_index: int) -> Array[Dictionary]:
	match kind:
		"gym":
			var gym := get_destination("gym", destination_index)
			if gym.is_empty():
				return []
			return [_make_encounter(
				"stretch-gym-%d-leader" % destination_index,
				String(gym["leader"]),
				gym["team"] as Array,
				0
			)]
		"route":
			return _route_encounters(destination_index)
		"champion":
			var encounters: Array[Dictionary] = []
			for encounter_index in CHAMPION_ENCOUNTERS.size():
				var source := CHAMPION_ENCOUNTERS[encounter_index]
				encounters.append(_make_encounter(
					String(source["id"]),
					String(source["name"]),
					source["team"] as Array,
					encounter_index
				))
			return encounters
	return []


static func _route_encounters(route_index: int) -> Array[Dictionary]:
	# Route 0 is the renamed authored meadow. Its seven standard trainers keep
	# their authored battle scenes, while Routes 1–39 use the generated provider.
	if route_index < 1 or route_index >= ROUTE_COUNT:
		return []
	var route := _make_route_destination(route_index)
	var layout := get_route_layout(route_index)
	var pool := layout.get("pool", []) as Array
	if pool.is_empty():
		return []
	var encounters: Array[Dictionary] = []
	var trainer_count := int(route.get("trainer_count", 4))
	var first_level := int(route.get("level_min", 3))
	var final_level := int(route.get("level_max", first_level + 7))
	var level_span := maxi(final_level - first_level, 0)
	var level_band := route_index / ROUTES_PER_LEVEL_BAND
	for trainer_index in trainer_count:
		var team: Array = []
		var team_size := mini(2 + level_band / 3, 4)
		for member_index in team_size:
			var pool_index := (
				route_index * 3 + trainer_index * 2 + member_index
			) % pool.size()
			var encounter_progress := (
				float(trainer_index) / float(maxi(trainer_count - 1, 1))
			)
			var member_level := mini(
				first_level + roundi(float(level_span) * encounter_progress) + member_index,
				final_level
			)
			team.append([
				int(pool[pool_index]),
				member_level,
			])
		encounters.append(_make_encounter(
			"stretch-route-%d-trainer-%d" % [route_index, trainer_index + 1],
			"Route %d Trainer %d" % [route_index, trainer_index + 1],
			team,
			trainer_index
		))
	return encounters


static func get_route_layout(route_index: int) -> Dictionary:
	if route_index < 0 or route_index >= ROUTE_COUNT:
		return {}
	return ROUTE_BIOMES[route_index % ROUTE_BIOMES.size()].duplicate(true)


static func get_route_wild_encounter(route_index: int) -> Dictionary:
	if route_index < 1 or route_index >= ROUTE_COUNT:
		return {}
	var route := _make_route_destination(route_index)
	var layout := get_route_layout(route_index)
	var pool := layout.get("pool", []) as Array
	if pool.is_empty():
		return {}
	var pokemon_id := int(pool[(route_index * 5 + 1) % pool.size()])
	var level := int(roundi(
		(float(route.get("level_min", 3)) + float(route.get("level_max", 10))) * 0.5
	))
	var encounter := _make_encounter(
		"stretch-route-%d-wild" % route_index,
		"Wild %s Pokemon" % String(route.get("biome", "Route")).capitalize(),
		[[pokemon_id, level]],
		-1
	)
	encounter["is_wild"] = true
	return encounter


static func _make_route_destination(route_index: int) -> Dictionary:
	var layout := get_route_layout(route_index)
	if layout.is_empty():
		return {}
	var level_band := route_index / ROUTES_PER_LEVEL_BAND
	var first_level := 3 if level_band == 0 else 1 + level_band * 6
	var final_level := mini(first_level + 7, 60)
	var second_biome_pass := route_index >= ROUTE_BIOMES.size()
	var title_key := "deep_title" if second_biome_pass else "title"
	var trainer_count := 7 if route_index == 0 else mini(4 + level_band / 2, 8)
	var world_length := (
		48
		if route_index == 0
		else 76 + level_band * 12 + (route_index % ROUTES_PER_LEVEL_BAND) * 4
	)
	var world_width := 32 if route_index == 0 else 18 + level_band
	var grass_fields := 5 if route_index == 0 else mini(4 + level_band / 2 + route_index % 2, 9)
	# Routes are grouped four at a time so each advertised level range has
	# several distinct dungeons instead of a single route. Route 0's authored
	# Lv. 3–6 trainer sequence defines the first band's ceiling.
	if level_band == 0:
		final_level = 6
	return {
		"index": route_index,
		"name": "Route %d — %s" % [route_index, String(layout.get(title_key, "Wilds"))],
		"description": (
			"%s dungeon route with %d mandatory trainer checkpoints, %d tall-grass "
			+ "fields, and a twisting %d m path (Lv. %d–%d). Reach the end to unlock "
			+ ("the next route." if route_index < ROUTE_COUNT - 1 else "the final clear.")
		) % [
			String(layout.get("biome", "Outdoor")).capitalize(),
			trainer_count,
			grass_fields,
			world_length,
			first_level,
			final_level,
		],
		"biome": String(layout.get("biome", "outdoor route")),
		"biome_id": String(layout.get("id", "route")),
		"level_band": level_band,
		"level_min": first_level,
		"level_max": final_level,
		"trainer_count": trainer_count,
		"grass_fields": grass_fields,
		"world_length": world_length,
		"world_width": world_width,
		"generated": route_index != 0,
		"scene_path": DESTINATION_SCENE_PATH if route_index != 0 else ROUTE_ZERO_SCENE_PATH,
		"spawn_marker": "EntrySpawn" if route_index != 0 else "Route0Start",
	}


static func _make_encounter(
	encounter_id: String,
	display_name: String,
	team: Array,
	sequence_index: int
) -> Dictionary:
	var members: Array[Dictionary] = []
	for member_index in team.size():
		var member := team[member_index] as Array
		members.append({
			"pokemon_id": int(member[0]),
			"level": int(member[1]),
			"member_id": "%s-member-%d" % [encounter_id, member_index + 1],
		})
	return {
		"encounter_id": encounter_id,
		"display_name": display_name,
		"api_name": _safe_api_name(display_name),
		"members": members,
		"sequence_index": sequence_index,
		"battle_scene_path": BATTLE_SCENE_PATH,
	}


static func _safe_api_name(display_name: String) -> String:
	var value := display_name.replace("Elite Four ", "Elite ")
	if value.length() > 18:
		value = value.left(18)
	return value.strip_edges()
