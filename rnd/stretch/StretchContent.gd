class_name RNDStretchContent
extends RefCounted

## Authored R&D destination and opponent rosters used by Stretchman's hub.

const DESTINATION_SCENE_PATH := "res://rnd/stretch/worlds/stretch_destination.tscn"
const BATTLE_SCENE_PATH := "res://rnd/stretch/battle/stretch_battle_scene.tscn"

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

const ROUTE_NAMES: Array[String] = [
	"Route 1 — Clover Verge",
	"Route 2 — Bramble Cut",
	"Route 3 — Riverside Run",
	"Route 4 — Ember Pass",
	"Route 5 — Static Yard",
	"Route 6 — Moonlit Walk",
	"Route 7 — Frostline Trail",
	"Route 8 — Victory Approach",
]

const ROUTE_POKEMON_POOLS: Array[Array] = [
	[19, 16, 10, 13, 29, 32, 21, 43],
	[41, 43, 69, 46, 48, 27, 23, 52],
	[54, 60, 72, 98, 118, 129, 90, 116],
	[21, 23, 56, 66, 74, 77, 58, 111],
	[81, 92, 100, 109, 123, 125, 126, 135],
	[133, 147, 172, 175, 200, 203, 207, 214],
	[215, 220, 228, 246, 280, 304, 302, 308],
	[359, 361, 371, 374, 443, 447, 633, 636],
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
		"price": 100,
		"level": 10,
		"tier": "Tier 1",
		"quality_label": "Starter and mascot favorites",
		"high_quality_pool": [1, 4, 7, 25, 133, 92, 147],
	},
	{
		"id": "bronze-spinner",
		"index": 2,
		"name": "Bronze Spinner",
		"price": 500,
		"level": 20,
		"tier": "Tier 2",
		"quality_label": "Classic fully evolved favorites",
		"high_quality_pool": [3, 6, 9, 94, 130, 143, 196, 197],
	},
	{
		"id": "silver-spinner",
		"index": 3,
		"name": "Silver Spinner",
		"price": 2_500,
		"level": 30,
		"tier": "Tier 3",
		"quality_label": "Pseudo-legends and rare fan favorites",
		"high_quality_pool": [149, 212, 248, 257, 282, 330, 350, 359, 373, 376],
	},
	{
		"id": "gold-spinner",
		"index": 4,
		"name": "Gold Spinner",
		"price": 10_000,
		"level": 40,
		"tier": "Tier 4",
		"quality_label": "Modern high-appeal and pseudo-legend pool",
		"high_quality_pool": [445, 448, 571, 609, 635, 658, 700, 706, 724, 778, 823, 887, 937, 998],
	},
	{
		"id": "ultra-vault",
		"index": 5,
		"name": "Ultra Vault",
		"price": 100_000,
		"level": 50,
		"tier": "Tier 5",
		"quality_label": "Legendary trios and exceptional favorites",
		"high_quality_pool": [144, 145, 146, 243, 244, 245, 377, 378, 379, 445, 448, 638, 639, 640, 887],
	},
	{
		"id": "legend-vault",
		"index": 6,
		"name": "Legend Vault",
		"price": 1_000_000,
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
			for route_index in range(1, ROUTE_NAMES.size() + 1):
				var first_level := 4 + route_index * 6
				routes.append({
					"index": route_index,
					"name": ROUTE_NAMES[route_index - 1],
					"description": (
						"Outdoor trainer run with four forced battles (about Lv. %d–%d)."
						% [first_level, first_level + 8]
					),
				})
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
	if route_index < 1 or route_index > ROUTE_POKEMON_POOLS.size():
		return []
	var pool := ROUTE_POKEMON_POOLS[route_index - 1]
	var encounters: Array[Dictionary] = []
	var base_level := 4 + route_index * 6
	for trainer_index in 4:
		var team: Array = []
		var team_size := 2 if route_index < 5 else 3
		for member_index in team_size:
			var pool_index := (trainer_index * 2 + member_index) % pool.size()
			team.append([
				int(pool[pool_index]),
				mini(base_level + trainer_index * 2 + member_index, 60),
			])
		encounters.append(_make_encounter(
			"stretch-route-%d-trainer-%d" % [route_index, trainer_index + 1],
			"Route %d Trainer %d" % [route_index, trainer_index + 1],
			team,
			trainer_index
		))
	return encounters


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
