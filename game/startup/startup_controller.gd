class_name StartupController
extends Node

## Project-entry coordinator for menu, introduction, starter selection, save
## loading, and the first safe gameplay checkpoint.

const ROUTE_0_SCENE: PackedScene = preload(
	"res://game/world/levels/standalone_areas/routes/route_00/route_00.tscn"
)
const RESET_CONFIRMATION_SCENE: PackedScene = preload(
	"res://game/ui/reset_progress/progress_reset_confirmation.tscn"
)
const CYPRESS_ILLUSTRATION: Texture2D = preload(
	"res://art/ui/startup/professor_cypress_intro.png"
)

const MENU_TITLE := "Pokémon Fracture × Revolt"
const CAMERA_CIRCUIT_SECONDS := 60.0
const INTRO_MESSAGES: Array[String] = [
	"Welcome, young Trainer. I’m Professor Cypress.",
	"Pokémon share our homes, our cities, and the wild places beyond.",
	"A few choose to travel beside us. We call them partners.",
	"Travel the region, earn Gym Badges, and challenge the Pokémon League.",
	"Dream of becoming Champion—but remember who stands beside you.",
	"Our region is changing. Kindness and friendship still matter.",
	"Your journey begins in New Bouffalant City.",
	"Choose your first partner. The road is waiting.",
]
const CAMERA_POINTS: Array[Vector3] = [
	Vector3(12.0, 9.5, 14.0),
	Vector3(-9.0, 10.5, -8.0),
	Vector3(-17.0, 11.5, -34.0),
	Vector3(17.0, 11.5, -51.0),
	Vector3(18.0, 12.5, -70.0),
	Vector3(-15.0, 11.5, -83.0),
	Vector3(-8.0, 12.5, -106.0),
	Vector3(10.0, 13.5, -127.0),
	Vector3(19.0, 12.0, -96.0),
	Vector3(18.0, 11.0, -52.0),
	Vector3(17.0, 10.0, -9.0),
]
const CAMERA_TARGETS: Array[Vector3] = [
	Vector3(0.0, 0.5, 2.0),
	Vector3(12.0, 0.5, -12.0),
	Vector3(-24.0, 0.5, -40.0),
	Vector3(24.0, 0.5, -56.0),
	Vector3(7.0, 0.5, -72.0),
	Vector3(-20.0, 0.5, -76.0),
	Vector3(16.0, 0.5, -104.0),
	Vector3(4.0, 0.5, -122.0),
	Vector3(16.0, 0.5, -104.0),
	Vector3(12.0, 0.5, -59.0),
	Vector3(12.0, 0.5, -12.0),
]

var _ui_root: Control
var _backdrop_slot: Control
var _menu: Control
var _intro_art: Control
var _loading_overlay: Control
var _loading_title: Label
var _loading_message: Label
var _retry_button: Button
var _continue_button: Button
var _new_game_button: Button
var _menu_status: Label
var _reset_confirmation: ProgressResetConfirmation
var _backdrop_container: SubViewportContainer
var _backdrop_viewport: SubViewport
var _route_backdrop: Node3D
var _camera_path: Path3D
var _camera_follow: PathFollow3D
var _camera: Camera3D
var _target_curve: Curve3D
var _camera_elapsed := 0.0
var _intro_index := 0
var _intro_template: UITemplate
var _save_status: Dictionary = {}


func _ready() -> void:
	GameInstance.set_player_movement_enabled(false)
	PlayerController.set_floating_joystick_input(Vector2.ZERO)
	_build_interface()
	ProgressionAutosave.startup_entry_started.connect(_on_startup_entry_started)
	ProgressionAutosave.startup_entry_failed.connect(_on_startup_entry_failed)
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_initialize_startup.call_deferred()


func _exit_tree() -> void:
	_stop_menu_backdrop()
	if is_instance_valid(_intro_template):
		_intro_template.close()


func _process(delta: float) -> void:
	if not is_instance_valid(_camera_follow) or not is_instance_valid(_camera):
		return
	_camera_elapsed = fposmod(_camera_elapsed + delta, CAMERA_CIRCUIT_SECONDS)
	var ratio := _camera_elapsed / CAMERA_CIRCUIT_SECONDS
	_camera_follow.progress_ratio = ratio
	if _target_curve != null and _target_curve.get_baked_length() > 0.0:
		var target := _target_curve.sample_baked(
			ratio * _target_curve.get_baked_length(),
			true
		)
		_camera.look_at(target, Vector3.UP)


func get_intro_messages() -> Array[String]:
	return INTRO_MESSAGES.duplicate()


func is_menu_backdrop_rendering() -> bool:
	return (
		is_instance_valid(_backdrop_viewport)
		and _backdrop_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
	)


func get_camera_circuit_progress() -> float:
	return _camera_elapsed / CAMERA_CIRCUIT_SECONDS


func get_camera_curve() -> Curve3D:
	return _camera_path.curve if is_instance_valid(_camera_path) else null


func get_route_backdrop() -> Node3D:
	return _route_backdrop if is_instance_valid(_route_backdrop) else null


func _initialize_startup() -> void:
	_save_status = ProgressionAutosave.begin_startup_session()
	var entry_error := String(_save_status.get("entry_error", ""))
	if not entry_error.is_empty():
		_show_entry_failure(entry_error)
		return
	if bool(_save_status.get("intro_pending", false)):
		_start_intro()
		return
	_show_main_menu()


func _show_main_menu() -> void:
	_intro_art.visible = false
	_loading_overlay.visible = false
	_menu.visible = true
	_start_menu_backdrop()
	var save_exists := bool(_save_status.get("exists", false))
	var save_valid := bool(_save_status.get("valid", false))
	_continue_button.visible = save_valid
	if not save_exists:
		_menu_status.text = "A new journey is waiting."
	elif not save_valid:
		_menu_status.text = (
			"SAVE DATA ERROR\n%s\nChoose New Game to replace it after confirmation."
			% String(_save_status.get("error", "The local save could not be read."))
		)
	elif not bool(_save_status.get("has_usable_location", false)):
		_menu_status.text = (
			"Your progress is ready. Continue will resume safely in Stretchman’s room."
		)
	else:
		_menu_status.text = "Your saved journey is ready to continue."
	if _continue_button.visible:
		_continue_button.grab_focus()
	else:
		_new_game_button.grab_focus()


func _on_continue_pressed() -> void:
	_leave_menu_for_loading("Restoring your journey…")
	ProgressionAutosave.continue_from_startup()


func _on_new_game_pressed() -> void:
	if bool(_save_status.get("exists", false)):
		_reset_confirmation.open()
		return
	if not ProgressionAutosave.prepare_new_profile_for_startup():
		_menu_status.text = "A new profile could not be prepared. Please try again."
		return
	_start_intro()


func _on_reset_confirmed() -> void:
	if not ProgressionAutosave.reset_all_progress(false):
		_reset_confirmation.visible = false
		_menu_status.text = "The reset could not begin. Your existing save is unchanged."
		_new_game_button.grab_focus()
		return
	_reset_confirmation.visible = false
	_start_intro()


func _on_reset_cancelled() -> void:
	_new_game_button.grab_focus()


func _start_intro() -> void:
	_stop_menu_backdrop()
	_menu.visible = false
	_loading_overlay.visible = false
	_intro_art.visible = true
	_intro_index = 0
	if is_instance_valid(_intro_template):
		_intro_template.close()
	_intro_template = UIManager.show_ui(INTRO_MESSAGES[_intro_index])
	if _intro_template == null:
		_show_entry_failure("The introduction dialog could not be opened.")
		return
	_intro_template.set_speaker_name("Professor Cypress")
	_intro_template.set_action_text("Next")
	_intro_template.set_dismiss_visible(false)
	_intro_template.set_action_callback(_advance_intro)


func _advance_intro() -> void:
	if not is_instance_valid(_intro_template):
		return
	_intro_index += 1
	if _intro_index < INTRO_MESSAGES.size():
		_intro_template.set_text(INTRO_MESSAGES[_intro_index])
		return
	_intro_template.set_action_enabled(false)
	_intro_template.close()
	_intro_template = null
	_intro_art.visible = false
	if not ProgressionAutosave.show_startup_starter_selection():
		_show_entry_failure("The starter selection could not be opened.")


func _on_startup_entry_started(_destination_scene_path: String) -> void:
	_leave_menu_for_loading(
		"Beginning your journey…"
		if ProgressionAutosave.is_profile_initialization_pending()
		else "Restoring your journey…"
	)


func _on_startup_entry_failed(message: String) -> void:
	_show_entry_failure(message)


func _show_entry_failure(message: String) -> void:
	_stop_menu_backdrop()
	_menu.visible = false
	_intro_art.visible = false
	_loading_overlay.visible = true
	_loading_title.text = "COULDN’T ENTER THE GAME"
	_loading_message.text = (
		message
		+ "\n\nYour selected starter and saved progress are still intact."
	)
	_retry_button.visible = true
	_retry_button.text = "Retry"
	_retry_button.grab_focus()


func _on_retry_pressed() -> void:
	_retry_button.visible = false
	_loading_title.text = "ENTERING THE GAME"
	_loading_message.text = "Trying the gameplay scene again…"
	if not ProgressionAutosave.retry_startup_entry():
		_save_status = ProgressionAutosave.begin_startup_session()
		_show_main_menu()


func _leave_menu_for_loading(message: String) -> void:
	_stop_menu_backdrop()
	_menu.visible = false
	_intro_art.visible = false
	_loading_overlay.visible = true
	_loading_title.text = "ENTERING THE GAME"
	_loading_message.text = message
	_retry_button.visible = false


func _start_menu_backdrop() -> void:
	if is_instance_valid(_backdrop_container):
		_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		return

	_backdrop_container = SubViewportContainer.new()
	_backdrop_container.name = "Route0Backdrop"
	_backdrop_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_container.stretch = true
	_backdrop_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop_slot.add_child(_backdrop_container)

	_backdrop_viewport = SubViewport.new()
	_backdrop_viewport.name = "IsolatedRouteViewport"
	_backdrop_viewport.own_world_3d = true
	_backdrop_viewport.handle_input_locally = false
	_backdrop_viewport.gui_disable_input = true
	_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_backdrop_viewport.size = _safe_viewport_size()
	_backdrop_container.add_child(_backdrop_viewport)

	_route_backdrop = ROUTE_0_SCENE.instantiate() as Node3D
	if _route_backdrop == null:
		push_error("The Route 0 menu backdrop could not be instantiated.")
		return
	_sanitize_route_backdrop(_route_backdrop)
	_backdrop_viewport.add_child(_route_backdrop)
	_build_camera_circuit()
	_camera_elapsed = 0.0


func _stop_menu_backdrop() -> void:
	if is_instance_valid(_backdrop_viewport):
		_backdrop_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_backdrop_container):
		_backdrop_container.queue_free()
	_backdrop_container = null
	_backdrop_viewport = null
	_route_backdrop = null
	_camera_path = null
	_camera_follow = null
	_camera = null
	_target_curve = null


func _sanitize_route_backdrop(route: Node3D) -> void:
	route.process_mode = Node.PROCESS_MODE_DISABLED
	for path in [
		^"Player",
		^"Gameplay/Actors",
		^"Gameplay/Interactions",
		^"Gameplay/Transitions",
		^"Gameplay/Objectives",
	]:
		var unwanted := route.get_node_or_null(path)
		if unwanted != null:
			unwanted.free()
	var encounters := route.get_node_or_null(^"Gameplay/Encounters")
	if encounters == null:
		return
	for child in encounters.find_children("*", "TallGrassEncounterZone", true, false):
		var grass := child as TallGrassEncounterZone
		if grass == null:
			continue
		grass.enabled = false
		grass.start_battle_automatically = false
		grass.collision_layer = 0
		grass.collision_mask = 0
		grass.monitoring = false
		grass.monitorable = false
		grass.process_mode = Node.PROCESS_MODE_DISABLED
		for shape_node in grass.find_children("*", "CollisionShape3D", true, false):
			(shape_node as CollisionShape3D).disabled = true


func _build_camera_circuit() -> void:
	_camera_path = Path3D.new()
	_camera_path.name = "MenuCameraCircuit"
	_camera_path.curve = _smooth_closed_curve(CAMERA_POINTS)
	_backdrop_viewport.add_child(_camera_path)

	_camera_follow = PathFollow3D.new()
	_camera_follow.name = "MenuCameraFollow"
	_camera_follow.loop = true
	_camera_follow.cubic_interp = true
	_camera_path.add_child(_camera_follow)

	_camera = Camera3D.new()
	_camera.name = "MenuCamera"
	_camera.current = true
	_camera.fov = 46.0
	_camera.near = 0.15
	_camera.far = 220.0
	_camera_follow.add_child(_camera)
	_target_curve = _smooth_closed_curve(CAMERA_TARGETS)
	_camera_follow.progress_ratio = 0.0
	_camera.look_at(CAMERA_TARGETS[0], Vector3.UP)


func _smooth_closed_curve(points: Array[Vector3]) -> Curve3D:
	var curve := Curve3D.new()
	curve.closed = true
	curve.bake_interval = 0.5
	for index in points.size():
		var previous := points[(index - 1 + points.size()) % points.size()]
		var next := points[(index + 1) % points.size()]
		var tangent := (next - previous) / 6.0
		curve.add_point(points[index], -tangent, tangent)
	return curve


func _on_viewport_size_changed() -> void:
	if is_instance_valid(_backdrop_viewport):
		_backdrop_viewport.size = _safe_viewport_size()


func _safe_viewport_size() -> Vector2i:
	var visible_size := get_viewport().get_visible_rect().size
	return Vector2i(maxi(int(visible_size.x), 1), maxi(int(visible_size.y), 1))


func _build_interface() -> void:
	_ui_root = Control.new()
	_ui_root.name = "StartupUI"
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_ui_root)

	var base := ColorRect.new()
	base.color = Color("071326")
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(base)

	_backdrop_slot = Control.new()
	_backdrop_slot.name = "BackdropSlot"
	_backdrop_slot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_backdrop_slot)

	_build_intro_art()
	_build_main_menu()
	_build_loading_overlay()

	_reset_confirmation = (
		RESET_CONFIRMATION_SCENE.instantiate() as ProgressResetConfirmation
	)
	_reset_confirmation.confirmed.connect(_on_reset_confirmed)
	_reset_confirmation.cancelled.connect(_on_reset_cancelled)
	_ui_root.add_child(_reset_confirmation)


func _build_intro_art() -> void:
	_intro_art = Control.new()
	_intro_art.name = "CypressIntroduction"
	_intro_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_art.visible = false
	_ui_root.add_child(_intro_art)
	var illustration := TextureRect.new()
	illustration.name = "ProfessorCypressIllustration"
	illustration.texture = CYPRESS_ILLUSTRATION
	illustration.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	illustration.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	illustration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	illustration.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_art.add_child(illustration)
	var shade := ColorRect.new()
	shade.color = Color(0.015, 0.025, 0.045, 0.16)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_intro_art.add_child(shade)


func _build_main_menu() -> void:
	_menu = Control.new()
	_menu.name = "MainMenu"
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.mouse_filter = Control.MOUSE_FILTER_PASS
	_menu.visible = false
	_ui_root.add_child(_menu)

	var readability := ColorRect.new()
	readability.color = Color(0.01, 0.025, 0.055, 0.34)
	readability.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	readability.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_menu.add_child(readability)

	var panel := PanelContainer.new()
	panel.name = "MainMenuPanel"
	panel.anchor_left = 0.045
	panel.anchor_top = 0.07
	panel.anchor_right = 0.46
	panel.anchor_bottom = 0.93
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.add_theme_stylebox_override(
		"panel",
		_style_box(Color(0.025, 0.075, 0.145, 0.94), Color("6bc8ff"), 3, 18)
	)
	_menu.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 30)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)

	var kicker := Label.new()
	kicker.text = "A NEW REGION AWAITS"
	kicker.add_theme_color_override("font_color", Color("79c9ff"))
	kicker.add_theme_font_size_override("font_size", 13)
	column.add_child(kicker)
	var title := Label.new()
	title.name = "GameTitle"
	title.text = MENU_TITLE
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_color_override("font_color", Color("f5fbff"))
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.9))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)

	var identity_line := HBoxContainer.new()
	identity_line.custom_minimum_size = Vector2(0.0, 7.0)
	identity_line.add_theme_constant_override("separation", 0)
	column.add_child(identity_line)
	var blue := ColorRect.new()
	blue.color = Color("3399ed")
	blue.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_line.add_child(blue)
	var red := ColorRect.new()
	red.color = Color("ef4355")
	red.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity_line.add_child(red)

	var subtitle := Label.new()
	subtitle.text = "Every alliance leaves a mark."
	subtitle.add_theme_color_override("font_color", Color("bad8ee"))
	subtitle.add_theme_font_size_override("font_size", 16)
	column.add_child(subtitle)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	_continue_button = _menu_button("Continue", Color("1a6da8"), Color("74caff"))
	_continue_button.name = "Continue"
	_continue_button.pressed.connect(_on_continue_pressed)
	column.add_child(_continue_button)
	_new_game_button = _menu_button("New Game", Color("8b1d2c"), Color("ff6878"))
	_new_game_button.name = "NewGame"
	_new_game_button.pressed.connect(_on_new_game_pressed)
	column.add_child(_new_game_button)
	if not OS.has_feature("web") and not OS.has_feature("mobile"):
		var quit := _menu_button("Quit", Color("1c2b3d"), Color("7893ad"))
		quit.name = "Quit"
		quit.pressed.connect(get_tree().quit)
		column.add_child(quit)

	_menu_status = Label.new()
	_menu_status.name = "SaveStatus"
	_menu_status.custom_minimum_size = Vector2(0.0, 66.0)
	_menu_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_menu_status.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_menu_status.add_theme_color_override("font_color", Color("c8dcec"))
	_menu_status.add_theme_font_size_override("font_size", 14)
	column.add_child(_menu_status)


func _build_loading_overlay() -> void:
	_loading_overlay = ColorRect.new()
	_loading_overlay.name = "LoadingOverlay"
	_loading_overlay.color = Color(0.015, 0.035, 0.075, 0.98)
	_loading_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_overlay.visible = false
	_loading_overlay.z_index = 50
	_ui_root.add_child(_loading_overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(540.0, 210.0)
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	_loading_title = Label.new()
	_loading_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_title.add_theme_color_override("font_color", Color("79c9ff"))
	_loading_title.add_theme_font_size_override("font_size", 28)
	column.add_child(_loading_title)
	_loading_message = Label.new()
	_loading_message.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_loading_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_loading_message.add_theme_color_override("font_color", Color("e9f5ff"))
	_loading_message.add_theme_font_size_override("font_size", 17)
	column.add_child(_loading_message)
	_retry_button = _menu_button("Retry", Color("8b1d2c"), Color("ff6878"))
	_retry_button.name = "RetryEntry"
	_retry_button.pressed.connect(_on_retry_pressed)
	column.add_child(_retry_button)


func _menu_button(label: String, background: Color, border: Color) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 52.0)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_color_override("font_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_stylebox_override(
		"normal", _style_box(background, border, 2, 10)
	)
	button.add_theme_stylebox_override(
		"hover", _style_box(background.lightened(0.14), border.lightened(0.12), 3, 10)
	)
	button.add_theme_stylebox_override(
		"pressed", _style_box(background.darkened(0.12), border, 3, 10)
	)
	button.add_theme_stylebox_override(
		"focus", _style_box(background.lightened(0.1), Color.WHITE, 3, 10)
	)
	return button


func _style_box(
	background: Color,
	border: Color,
	border_width: int,
	radius: int
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
