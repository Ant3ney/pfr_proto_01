class_name MoveLearningUI
extends CanvasLayer

## Blocking, touch-safe move replacement prompt owned by move progression.

signal replacement_selected(move_index: int)
signal continued

const TYPE_COLORS := {
	"Bug": Color("79b84b"),
	"Dark": Color("53627a"),
	"Dragon": Color("6b70d6"),
	"Electric": Color("e5bd35"),
	"Fairy": Color("d982b6"),
	"Fighting": Color("c95d45"),
	"Fire": Color("e8733d"),
	"Flying": Color("7ca4d8"),
	"Ghost": Color("75669b"),
	"Grass": Color("59a957"),
	"Ground": Color("b78a50"),
	"Ice": Color("62b8c3"),
	"Normal": Color("8e948e"),
	"Poison": Color("9a62a5"),
	"Psychic": Color("d96982"),
	"Rock": Color("a89455"),
	"Steel": Color("778d9d"),
	"Water": Color("4b89cf"),
}

@onready var root: Control = %Root
@onready var title_label: Label = %Title
@onready var pokemon_label: Label = %PokemonSummary
@onready var new_move_name: Label = %NewMoveName
@onready var new_move_details: Label = %NewMoveDetails
@onready var instruction_label: Label = %Instruction
@onready var move_grid: GridContainer = %MoveGrid
@onready var keep_button: Button = %KeepButton
@onready var continue_button: Button = %ContinueButton

var _mode := &"hidden"
var _input_locked := false


func _ready() -> void:
	keep_button.pressed.connect(_submit_replacement.bind(-1))
	continue_button.pressed.connect(_submit_continue)
	root.visible = false


func show_replacement(request: Dictionary) -> void:
	_mode = &"replacement"
	_input_locked = false
	_configure_header(request)
	title_label.text = "%s CAN LEARN %s!" % [
		String(request.get("pokemonName", "Pokémon")).to_upper(),
		String(request.get("moveName", "a move")).to_upper(),
	]
	instruction_label.text = (
		"It already knows four moves. Choose one to forget, or keep its current moves."
	)
	_clear_move_buttons()
	var current_moves: Array = request.get("currentMoves", []) as Array
	for move_index in current_moves.size():
		var move_value: Variant = current_moves[move_index]
		if typeof(move_value) != TYPE_DICTIONARY:
			continue
		var move := move_value as Dictionary
		var button := _new_move_button(move, move_index)
		move_grid.add_child(button)
	keep_button.visible = true
	continue_button.visible = false
	root.visible = true
	var first_button := move_grid.get_child(0) as Button if move_grid.get_child_count() > 0 else null
	if first_button != null:
		first_button.grab_focus()
	else:
		keep_button.grab_focus()


func show_result(request: Dictionary, result: Dictionary) -> void:
	_mode = &"result"
	_input_locked = false
	_configure_header(request)
	_clear_move_buttons()
	var status := String(result.get("status", "skipped"))
	match status:
		"learned":
			title_label.text = "%s LEARNED %s!" % [
				String(request.get("pokemonName", "Pokémon")).to_upper(),
				String(request.get("moveName", "the move")).to_upper(),
			]
			instruction_label.text = "The new move filled an open move slot."
		"replaced":
			title_label.text = "%s LEARNED %s!" % [
				String(request.get("pokemonName", "Pokémon")).to_upper(),
				String(request.get("moveName", "the move")).to_upper(),
			]
			instruction_label.text = "%s was forgotten." % String(
				result.get("forgottenMoveName", "The selected move")
			)
		"already_known":
			title_label.text = "%s ALREADY KNOWS %s" % [
				String(request.get("pokemonName", "Pokémon")).to_upper(),
				String(request.get("moveName", "the move")).to_upper(),
			]
			instruction_label.text = "No move slot changed."
		_:
			title_label.text = "%s KEPT ITS CURRENT MOVES" % String(
				request.get("pokemonName", "Pokémon")
			).to_upper()
			instruction_label.text = "%s was not learned." % String(
				request.get("moveName", "The new move")
			)
	keep_button.visible = false
	continue_button.visible = true
	root.visible = true
	continue_button.grab_focus()


func hide_ui() -> void:
	_mode = &"hidden"
	_input_locked = false
	root.visible = false
	_clear_move_buttons()


func get_move_buttons() -> Array[Button]:
	var buttons: Array[Button] = []
	for child: Node in move_grid.get_children():
		if child is Button:
			buttons.append(child as Button)
	return buttons


func _unhandled_input(event: InputEvent) -> void:
	if not root.visible or _input_locked or not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _mode == &"replacement":
		_submit_replacement(-1)
	elif _mode == &"result":
		_submit_continue()


func _configure_header(request: Dictionary) -> void:
	pokemon_label.text = "%s reached Lv. %d" % [
		String(request.get("pokemonName", "Pokémon")),
		int(request.get("currentLevel", request.get("learnedLevel", 1))),
	]
	new_move_name.text = String(request.get("moveName", "Unknown Move"))
	var move_type := String(request.get("moveType", "Unknown"))
	new_move_details.text = "%s TYPE  ·  LEARNED AT LV. %d" % [
		move_type.to_upper(),
		int(request.get("learnedLevel", 1)),
	]
	new_move_details.add_theme_color_override(
		"font_color",
		TYPE_COLORS.get(move_type, Color("d6e4da"))
	)


func _new_move_button(move: Dictionary, move_index: int) -> Button:
	var button := Button.new()
	button.name = "MoveOption%d" % (move_index + 1)
	button.custom_minimum_size = Vector2(230.0, 64.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var move_type := String(move.get("type", "Unknown"))
	button.text = "%s\n%s" % [
		String(move.get("name", "Unknown Move")),
		move_type.to_upper(),
	]
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override(
		"font_color",
		TYPE_COLORS.get(move_type, Color("eef6ef"))
	)
	button.pressed.connect(_submit_replacement.bind(move_index))
	return button


func _clear_move_buttons() -> void:
	for child: Node in move_grid.get_children():
		move_grid.remove_child(child)
		child.queue_free()


func _submit_replacement(move_index: int) -> void:
	if _input_locked or _mode != &"replacement":
		return
	_input_locked = true
	replacement_selected.emit(move_index)


func _submit_continue() -> void:
	if _input_locked or _mode != &"result":
		return
	_input_locked = true
	continued.emit()
