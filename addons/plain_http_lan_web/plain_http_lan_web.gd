@tool
extends EditorPlugin

const TOOL_MENU_NAME := "Apply Plain HTTP LAN Web Fix"
const EXPORT_PRESETS_PATH := "res://export_presets.cfg"
const SHELL_PATH := "res://addons/plain_http_lan_web/plain_http_shell.html"


func _enter_tree() -> void:
	add_tool_menu_item(TOOL_MENU_NAME, _apply_fix)
	call_deferred("_apply_fix", false)


func _exit_tree() -> void:
	remove_tool_menu_item(TOOL_MENU_NAME)


func _apply_fix(show_success := true) -> void:
	var editor_settings_changed := _configure_editor_web_server()
	var result := _configure_web_presets()

	if not result.success:
		_show_message(result.message, EditorToaster.SEVERITY_ERROR)
		push_error("[Plain HTTP LAN Web] %s" % result.message)
		return

	var project_changed: bool = result.changed
	if project_changed or editor_settings_changed:
		var message := (
			"Plain HTTP LAN Web configured %d Web preset(s). Godot will restart once."
			% result.preset_count
		)
		print("[Plain HTTP LAN Web] %s" % message)
		_show_message(message)
		get_editor_interface().restart_editor(true)
	elif show_success:
		var message := "Plain HTTP LAN Web is already configured."
		print("[Plain HTTP LAN Web] %s" % message)
		_show_message(message)


func _configure_editor_web_server() -> bool:
	var settings := get_editor_interface().get_editor_settings()
	var changed := false

	changed = _set_editor_setting(settings, "export/web/http_port", 8060) or changed
	changed = _set_editor_setting(settings, "export/web/http_host", "0.0.0.0") or changed
	changed = _set_editor_setting(settings, "export/web/use_tls", false) or changed
	changed = _set_editor_setting(settings, "export/web/tls_key", "") or changed
	changed = _set_editor_setting(settings, "export/web/tls_certificate", "") or changed

	return changed


func _set_editor_setting(settings: EditorSettings, key: String, value: Variant) -> bool:
	if settings.has_setting(key) and settings.get_setting(key) == value:
		return false

	settings.set_setting(key, value)
	settings.mark_setting_changed(key)
	return true


func _configure_web_presets() -> Dictionary:
	var config := ConfigFile.new()
	var load_error := config.load(EXPORT_PRESETS_PATH)

	if load_error != OK and load_error != ERR_FILE_NOT_FOUND:
		return {
			"success": false,
			"changed": false,
			"preset_count": 0,
			"message": "Could not read export_presets.cfg (error %d)." % load_error,
		}

	var preset_sections := _find_web_preset_sections(config)
	var changed := false

	if preset_sections.is_empty():
		var preset_section := _create_web_preset(config)
		preset_sections.append(preset_section)
		changed = true

	for preset_section in preset_sections:
		var options_section := "%s.options" % preset_section
		changed = _set_config_value(
			config, options_section, "html/custom_html_shell", SHELL_PATH
		) or changed
		changed = _set_config_value(
			config, options_section, "variant/thread_support", false
		) or changed

	if changed:
		var save_error := config.save(EXPORT_PRESETS_PATH)
		if save_error != OK:
			return {
				"success": false,
				"changed": false,
				"preset_count": preset_sections.size(),
				"message": "Could not save export_presets.cfg (error %d)." % save_error,
			}

	return {
		"success": true,
		"changed": changed,
		"preset_count": preset_sections.size(),
		"message": "",
	}


func _find_web_preset_sections(config: ConfigFile) -> PackedStringArray:
	var result := PackedStringArray()

	for section in config.get_sections():
		if (
			section.begins_with("preset.")
			and not section.ends_with(".options")
			and config.get_value(section, "platform", "") == "Web"
		):
			result.append(section)

	return result


func _create_web_preset(config: ConfigFile) -> String:
	var preset_index := _next_preset_index(config)
	var preset_section := "preset.%d" % preset_index
	var options_section := "%s.options" % preset_section
	var preset_name := _unique_preset_name(config, "Web")

	config.set_value("runnable_presets", "Web", preset_name)

	config.set_value(preset_section, "name", preset_name)
	config.set_value(preset_section, "platform", "Web")
	config.set_value(preset_section, "dedicated_server", false)
	config.set_value(preset_section, "custom_features", "")
	config.set_value(preset_section, "export_filter", "all_resources")
	config.set_value(preset_section, "include_filter", "")
	config.set_value(preset_section, "exclude_filter", "")
	config.set_value(preset_section, "export_path", "")
	config.set_value(preset_section, "patches", PackedStringArray())
	config.set_value(preset_section, "patch_delta_encoding", false)
	config.set_value(preset_section, "patch_delta_compression_level_zstd", 19)
	config.set_value(preset_section, "patch_delta_min_reduction", 0.1)
	config.set_value(preset_section, "patch_delta_include_filters", "*")
	config.set_value(preset_section, "patch_delta_exclude_filters", "")
	config.set_value(preset_section, "encryption_include_filters", "")
	config.set_value(preset_section, "encryption_exclude_filters", "")
	config.set_value(preset_section, "seed", 0)
	config.set_value(preset_section, "encrypt_pck", false)
	config.set_value(preset_section, "encrypt_directory", false)
	config.set_value(preset_section, "script_export_mode", 2)

	config.set_value(options_section, "custom_template/debug", "")
	config.set_value(options_section, "custom_template/release", "")
	config.set_value(options_section, "variant/extensions_support", false)
	config.set_value(options_section, "variant/thread_support", false)
	config.set_value(options_section, "vram_texture_compression/for_desktop", true)
	config.set_value(options_section, "vram_texture_compression/for_mobile", false)
	config.set_value(options_section, "html/export_icon", true)
	config.set_value(options_section, "html/custom_html_shell", SHELL_PATH)
	config.set_value(options_section, "html/head_include", "")
	config.set_value(options_section, "html/canvas_resize_policy", 2)
	config.set_value(options_section, "html/focus_canvas_on_start", true)
	config.set_value(options_section, "html/experimental_virtual_keyboard", false)
	config.set_value(options_section, "progressive_web_app/enabled", false)
	config.set_value(
		options_section, "progressive_web_app/ensure_cross_origin_isolation_headers", true
	)
	config.set_value(options_section, "progressive_web_app/offline_page", "")
	config.set_value(options_section, "progressive_web_app/display", 1)
	config.set_value(options_section, "progressive_web_app/orientation", 0)
	config.set_value(options_section, "progressive_web_app/icon_144x144", "")
	config.set_value(options_section, "progressive_web_app/icon_180x180", "")
	config.set_value(options_section, "progressive_web_app/icon_512x512", "")
	config.set_value(
		options_section, "progressive_web_app/background_color", Color(0, 0, 0, 1)
	)
	config.set_value(options_section, "threads/emscripten_pool_size", 8)
	config.set_value(options_section, "threads/godot_pool_size", 4)

	return preset_section


func _next_preset_index(config: ConfigFile) -> int:
	var next_index := 0

	for section in config.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue

		var index_text := section.trim_prefix("preset.")
		if index_text.is_valid_int():
			next_index = maxi(next_index, index_text.to_int() + 1)

	return next_index


func _unique_preset_name(config: ConfigFile, base_name: String) -> String:
	var used_names := {}

	for section in config.get_sections():
		if section.begins_with("preset.") and not section.ends_with(".options"):
			used_names[config.get_value(section, "name", "")] = true

	if not used_names.has(base_name):
		return base_name

	var suffix := 2
	while used_names.has("%s %d" % [base_name, suffix]):
		suffix += 1
	return "%s %d" % [base_name, suffix]


func _set_config_value(
	config: ConfigFile, section: String, key: String, value: Variant
) -> bool:
	if config.has_section_key(section, key) and config.get_value(section, key) == value:
		return false

	config.set_value(section, key, value)
	return true


func _show_message(message: String, severity := EditorToaster.SEVERITY_INFO) -> void:
	get_editor_interface().get_editor_toaster().push_toast(message, severity)
