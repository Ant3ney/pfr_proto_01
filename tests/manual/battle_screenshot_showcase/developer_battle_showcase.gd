extends BattleScene

## Network-free battle presentation made for promotional screenshots.
## Press K to cycle curated matchups and H to hide the developer title card.

signal matchup_changed(index: int, matchup: Dictionary)

const SpeciesMapping := preload(
	"res://game/battle/system/battle_species_mapping.gd"
)
const MATCHUPS: Array[Dictionary] = [
	{
		"title": "SKYBREAKER VS DISTORTION",
		"player_id": 384,
		"opponent_id": 487,
		"player_level": 100,
		"opponent_level": 100,
		"message": "The sky tears open as two legendary dragons collide!",
		"legendary_pair": true,
	},
	{
		"title": "ANCIENT CATACLYSM",
		"player_id": 383,
		"opponent_id": 382,
		"player_level": 100,
		"opponent_level": 100,
		"message": "Land and sea meet again in an ancient reckoning!",
		"legendary_pair": true,
	},
	{
		"title": "TEMPORAL RIFT",
		"player_id": 483,
		"opponent_id": 484,
		"player_level": 100,
		"opponent_level": 100,
		"message": "Time bends. Space fractures. Neither legend yields.",
		"legendary_pair": true,
	},
	{
		"title": "ECLIPSE OF ALOLA",
		"player_id": 791,
		"opponent_id": 792,
		"player_level": 85,
		"opponent_level": 85,
		"message": "The radiant sun challenges the ruler of moonlight!",
		"legendary_pair": true,
	},
	{
		"title": "TRUTH AND IDEALS",
		"player_id": 643,
		"opponent_id": 644,
		"player_level": 90,
		"opponent_level": 90,
		"message": "White flame and black lightning shake the battlefield!",
		"legendary_pair": true,
	},
	{
		"title": "SWORD AND SHIELD",
		"player_id": 888,
		"opponent_id": 889,
		"player_level": 80,
		"opponent_level": 80,
		"message": "The crowned sword tests the strength of the royal shield!",
		"legendary_pair": true,
	},
	{
		"title": "DARK STAR APOCALYPSE",
		"player_id": 800,
		"opponent_id": 890,
		"player_level": 100,
		"opponent_level": 100,
		"message": "Blinding light stands against a world-ending shadow!",
		"legendary_pair": true,
	},
	{
		"title": "TINY BUT FEARLESS",
		"player_id": 595,
		"opponent_id": 321,
		"player_level": 12,
		"opponent_level": 72,
		"message": "Joltik refuses to be intimidated by the biggest target imaginable!",
		"legendary_pair": false,
	},
	{
		"title": "THE ORIGINAL RIVALS",
		"player_id": 6,
		"opponent_id": 9,
		"player_level": 75,
		"opponent_level": 75,
		"message": "A classic rivalry burns brighter than ever!",
		"legendary_pair": false,
	},
	{
		"title": "SHADOWS AT MIDNIGHT",
		"player_id": 778,
		"opponent_id": 94,
		"player_level": 70,
		"opponent_level": 70,
		"message": "Two grinning shadows wait for the other to blink.",
		"legendary_pair": false,
	},
]

@onready var _showcase_card: PanelContainer = %ShowcaseCard
@onready var _showcase_title: Label = %ShowcaseTitle
@onready var _showcase_pair: Label = %ShowcasePair
@onready var _showcase_hint: Label = %ShowcaseHint
@onready var _matchup_curtain: ColorRect = %MatchupCurtain

var _matchup_index := 0
var _transition_in_progress := false


func _ready() -> void:
	super._ready()
	_showcase_card.visible = false
	intro_finished.connect(_on_showcase_intro_finished, CONNECT_ONE_SHOT)
	select_matchup(0)


func _input(event: InputEvent) -> void:
	var key_event := event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	var pressed_key := key_event.physical_keycode
	if pressed_key == KEY_NONE:
		pressed_key = key_event.keycode
	match pressed_key:
		KEY_K:
			_cycle_matchup()
			get_viewport().set_input_as_handled()
		KEY_H:
			_showcase_card.visible = not _showcase_card.visible
			get_viewport().set_input_as_handled()


func get_matchup_count() -> int:
	return MATCHUPS.size()


func get_current_matchup_index() -> int:
	return _matchup_index


func get_current_matchup() -> Dictionary:
	return MATCHUPS[_matchup_index].duplicate(true)


func select_matchup(index: int) -> Dictionary:
	_matchup_index = posmod(index, MATCHUPS.size())
	var matchup := MATCHUPS[_matchup_index]
	var player_entry := SpeciesMapping.get_entry(int(matchup.player_id))
	var opponent_entry := SpeciesMapping.get_entry(int(matchup.opponent_id))
	if player_entry.is_empty() or opponent_entry.is_empty():
		var error := "The developer showcase matchup references an unmapped Pokémon."
		push_error(error)
		return {"ok": false, "error": error}
	if not is_instance_valid(_sprite_presenter):
		var error := "The developer showcase could not create its sprite presenter."
		push_error(error)
		return {"ok": false, "error": error}

	var player_member := _build_member(
		int(matchup.player_id),
		int(matchup.player_level),
		player_entry,
		"showcase-player"
	)
	var opponent_member := _build_member(
		int(matchup.opponent_id),
		int(matchup.opponent_level),
		opponent_entry,
		"showcase-opponent"
	)
	var presentation := _sprite_presenter.call(
		"present_battlers",
		player_member,
		opponent_member
	) as Dictionary
	battle_data = {
		"intro_title": String(matchup.title),
		"player_pokemon_name": String(player_entry.species),
		"player_level": int(matchup.player_level),
		"player_health": float(matchup.get("player_health", 1.0)),
		"player_experience_progress": 0.72,
		"opponent_pokemon_name": String(opponent_entry.species),
		"opponent_level": int(matchup.opponent_level),
		"opponent_health": float(matchup.get("opponent_health", 1.0)),
		"battle_message": String(matchup.message),
		"can_fight": true,
		"can_bag": false,
		"can_party": true,
		"can_run": true,
	}
	intro_title.text = String(matchup.title)
	_showcase_title.text = String(matchup.title)
	_showcase_pair.text = "%s  VS  %s" % [
		String(player_entry.species).to_upper(),
		String(opponent_entry.species).to_upper(),
	]
	_showcase_hint.text = "%02d / %02d   •   K  NEXT MATCHUP   •   H  CLEAN FRAME" % [
		_matchup_index + 1,
		MATCHUPS.size(),
	]
	if is_instance_valid(_battle_ui_template):
		_battle_ui_template.update_battle_ui(_build_battle_ui_data())
	_sprite_layout_refresh_pending = true
	_refresh_sprite_layout_if_safe.call_deferred()
	matchup_changed.emit(_matchup_index, matchup.duplicate(true))
	return {
		"ok": bool((presentation.player as Dictionary).get("ok", false))
			and bool((presentation.opponent as Dictionary).get("ok", false)),
		"matchup": matchup.duplicate(true),
		"presentation": presentation,
	}


func advance_matchup_immediately() -> Dictionary:
	return select_matchup(_matchup_index + 1)


func _cycle_matchup() -> void:
	if _transition_in_progress:
		return
	_transition_in_progress = true
	var transition := create_tween()
	transition.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	transition.tween_property(_matchup_curtain, ^"color:a", 0.88, 0.12)
	transition.tween_callback(advance_matchup_immediately)
	transition.tween_interval(0.04)
	transition.tween_property(_matchup_curtain, ^"color:a", 0.0, 0.18)
	transition.tween_callback(func() -> void: _transition_in_progress = false)


func _on_showcase_intro_finished() -> void:
	_showcase_card.visible = true


func _build_member(
	pokemon_id: int,
	level: int,
	mapping: Dictionary,
	member_id: String
) -> Dictionary:
	return {
		"memberId": member_id,
		"pokemonId": pokemon_id,
		"species": String(mapping.species),
		"nickname": String(mapping.species),
		"level": level,
		"normalizedHealth": 1.0,
		"active": true,
		"battleProfile": {
			"spriteId": String(mapping.spriteId),
			"shiny": false,
		},
	}
