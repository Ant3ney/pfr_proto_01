extends SceneTree

const AssetPaletteDock := preload(
	"res://addons/new_bouffalant_city_asset_palette/asset_palette_dock.gd"
)
const CATALOG_PATH := (
	"res://art/environments/new_bouffalant_city/reference_city_pack/catalog.json"
)

func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var assets := _load_assets()
	if assets.is_empty():
		_fail("Could not load catalog assets.")
		return

	var dock := AssetPaletteDock.new()
	root.add_child(dock)
	dock.initialize(
		assets,
		null,
		null,
		"Mesa Intel(R) Graphics (ADL GT2)",
		"forward_plus",
		true
	)
	for asset_id: String in [
		"t1_b_gate_building",
		"t1_b_museum",
		"t1_b_tenant_building",
	]:
		var asset_index := _asset_index(dock, asset_id)
		if asset_index < 0:
			_fail("Vulkan-safe asset is missing from the palette: %s" % asset_id)
			return
		dock.set_placement_active(false)
		dock.call("_on_asset_activated", asset_index)
		if not dock.is_placement_active():
			_fail("Forward+ double-click did not activate placement: %s" % asset_id)
			return
		if String(dock.get_selected_asset().get("id", "")) != asset_id:
			_fail("Forward+ double-click selected the wrong asset: %s" % asset_id)
			return

	if not dock.start_placement_for_asset("t1_b_gate_building"):
		_fail("Programmatic Gate Building placement could not be activated.")
		return

	print(
		"Bouffalant palette activation smoke test passed: Gate Building, Museum, and "
		+ "Tenant Building double-click into normal Forward+ viewport placement."
	)
	quit(0)


func _load_assets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		return result
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return result
	for value: Variant in (parsed as Dictionary).get("assets", []):
		if value is Dictionary:
			result.append(value)
	return result


func _asset_index(dock: VBoxContainer, asset_id: String) -> int:
	var asset_list := dock.get("_asset_list") as ItemList
	if asset_list == null:
		return -1
	for index in range(asset_list.item_count):
		var asset: Dictionary = asset_list.get_item_metadata(index)
		if String(asset.get("id", "")) == asset_id:
			return index
	return -1


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
