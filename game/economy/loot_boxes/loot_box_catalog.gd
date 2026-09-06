class_name LootBoxCatalog
extends RefCounted

const HIGH_QUALITY_CHANCE := 0.10

const COMMON_POKEMON_IDS: Array[int] = [
	100, 101, 174, 173, 311, 312, 406, 458, 399,
]

const OFFERS: Array[Dictionary] = [
	{
		"id": "scuffed-parcel", "index": 1, "name": "Scuffed Parcel",
		"price": 400, "level": 10, "tier": "Tier 1",
		"quality_label": "Starter and mascot favorites",
		"high_quality_pool": [1, 4, 7, 25, 133, 92, 147],
	},
	{
		"id": "bronze-spinner", "index": 2, "name": "Bronze Spinner",
		"price": 2_000, "level": 20, "tier": "Tier 2",
		"quality_label": "Classic fully evolved favorites",
		"high_quality_pool": [3, 6, 9, 94, 130, 143, 196, 197],
	},
	{
		"id": "silver-spinner", "index": 3, "name": "Silver Spinner",
		"price": 10_000, "level": 30, "tier": "Tier 3",
		"quality_label": "Pseudo-legends and rare fan favorites",
		"high_quality_pool": [149, 212, 248, 257, 282, 330, 350, 359, 373, 376],
	},
	{
		"id": "gold-spinner", "index": 4, "name": "Gold Spinner",
		"price": 40_000, "level": 40, "tier": "Tier 4",
		"quality_label": "Modern high-appeal and pseudo-legend pool",
		"high_quality_pool": [445, 448, 571, 609, 635, 658, 700, 706, 724, 778, 823, 887, 937, 998],
	},
	{
		"id": "ultra-vault", "index": 5, "name": "Ultra Vault",
		"price": 400_000, "level": 50, "tier": "Tier 5",
		"quality_label": "Legendary trios and exceptional favorites",
		"high_quality_pool": [144, 145, 146, 243, 244, 245, 377, 378, 379, 445, 448, 638, 639, 640, 887],
	},
	{
		"id": "legend-vault", "index": 6, "name": "Legend Vault",
		"price": 4_000_000, "level": 60, "tier": "Tier 6",
		"quality_label": "Top box-art and restricted legendaries",
		"high_quality_pool": [150, 249, 250, 382, 383, 384, 483, 484, 487, 643, 644, 646, 716, 717, 718, 791, 792, 800, 888, 889, 1007, 1008],
	},
]


static func get_offers() -> Array[Dictionary]:
	return OFFERS.duplicate(true)


static func get_offer(box_id: String) -> Dictionary:
	for offer in OFFERS:
		if String(offer.get("id", "")) == box_id.strip_edges():
			return offer.duplicate(true)
	return {}
