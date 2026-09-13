class_name LoadingBattleRules
extends RefCounted

## Pure, practice-only team and difficulty rules for the loading battle.

const STARTERS := ["charmander", "froakie", "treecko"]
const TIERS := ["easy", "medium", "hard", "impossible"]

const STANDARD_MOVES := {
	"charmander": ["Fire Fang", "Scratch", "Smokescreen", "Thunder Punch"],
	"froakie": ["Water Pulse", "Quick Attack", "Smokescreen", "Ice Beam"],
	"treecko": ["Leaf Blade", "Quick Attack", "Leer", "Rock Tomb"],
}

const EXHIBITION_MOVES := {
	"charmander": ["Scratch", "Slash", "Dragon Claw", "Brick Break"],
	"froakie": ["Pound", "Quick Attack", "Aerial Ace", "Thief"],
	"treecko": ["Pound", "Quick Attack", "Aerial Ace", "Brick Break"],
}

const EASY_OPPONENTS := {
	"charmander": {
		"species": "Treecko",
		"moves": ["Absorb", "Mega Drain", "Pound", "Leer"],
	},
	"froakie": {
		"species": "Charmander",
		"moves": ["Ember", "Fire Spin", "Scratch", "Smokescreen"],
	},
	"treecko": {
		"species": "Froakie",
		"moves": ["Water Gun", "Bubble", "Pound", "Smokescreen"],
	},
}

const HARD_OPPONENTS := {
	"charmander": {
		"species": "Froakie",
		"moves": ["Water Pulse", "Bubble Beam", "Quick Attack", "Smokescreen"],
		"nature": "Modest",
		"evs": {"spa": 84},
	},
	"froakie": {
		"species": "Treecko",
		"moves": ["Leaf Blade", "Magical Leaf", "Quick Attack", "Leer"],
		"evs": {"hp": 84, "atk": 84, "spa": 84, "spd": 84},
		"item": "Oran Berry",
	},
	"treecko": {
		"species": "Charmander",
		"moves": ["Fire Fang", "Flame Burst", "Scratch", "Smokescreen"],
	},
}


static func is_valid_starter(starter_id: String) -> bool:
	return starter_id in STARTERS


static func next_difficulty(current: String, winner: String) -> String:
	var index := TIERS.find(current)
	if index < 0:
		index = 1
	if winner == "player":
		index = mini(index + 1, TIERS.size() - 1)
	else:
		index = maxi(index - 1, 0)
	return TIERS[index]


static func tier_title(tier: String) -> String:
	match tier:
		"easy":
			return "Easy Practice"
		"hard":
			return "Hard Counter Match"
		"impossible":
			return "Impossible Exhibition — survive as long as you can"
	return "Medium Mirror Match"


static func start_payload(starter_id: String, tier: String) -> Dictionary:
	if not is_valid_starter(starter_id) or tier not in TIERS:
		return {}
	var player_moves: Array = (
		EXHIBITION_MOVES[starter_id]
		if tier == "impossible"
		else STANDARD_MOVES[starter_id]
	)
	var opponent := _opponent_for(starter_id, tier)
	return {
		"player": {
			"name": "Player",
			"team": [{
				"memberId": "practice-player",
				"species": _display_species(starter_id),
				"level": 20,
				"health": 1.0,
				"moves": player_moves.duplicate(),
			}],
		},
		"opponent": {
			"name": "Practice CPU",
			"team": [opponent],
		},
	}


static func opponent_sprite_id(starter_id: String, tier: String) -> String:
	var opponent := _opponent_for(starter_id, tier)
	return String(opponent.get("species", "ditto")).to_lower()


static func _opponent_for(starter_id: String, tier: String) -> Dictionary:
	if tier == "medium":
		return {
			"memberId": "practice-opponent",
			"species": "Ditto",
			"level": 22,
			"health": 0.85,
			"moves": ["Transform"],
			"ability": "Imposter",
			"item": "Leftovers",
		}
	if tier == "impossible":
		return {
			"memberId": "practice-opponent",
			"species": "Wobbuffet",
			"level": 50,
			"health": 1.0,
			"moves": ["Counter"],
			"nature": "Sassy",
			"ivs": {"spe": 0},
			"evs": {"spe": 0},
		}
	var authored: Dictionary = (
		EASY_OPPONENTS[starter_id]
		if tier == "easy"
		else HARD_OPPONENTS[starter_id]
	)
	var opponent := {
		"memberId": "practice-opponent",
		"species": String(authored.species),
		"level": 18 if tier == "easy" else 22,
		"health": 1.0,
		"moves": (authored.moves as Array).duplicate(),
	}
	for key in ["nature", "evs", "item"]:
		if authored.has(key):
			opponent[key] = (authored[key] as Dictionary).duplicate(true) if key == "evs" else authored[key]
	return opponent


static func _display_species(starter_id: String) -> String:
	return starter_id.left(1).to_upper() + starter_id.substr(1)
