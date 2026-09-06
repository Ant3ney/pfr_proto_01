# Learning to Build Godot Editor Docks from Bouffalant Assets

This guide explains how the **Bouffalant Assets** window is built and gives you
a practical path for making your own Godot editor windows. It is based on the
current project source and was verified with Godot 4.7.2.

## What This Window Actually Is

**Bouffalant Assets is an editor dock, not an in-game UI and not a separate OS
window.** Its root is an [`EditorDock`](https://docs.godotengine.org/en/4.7/classes/class_editordock.html)
created by an [`EditorPlugin`](https://docs.godotengine.org/en/4.7/classes/class_editorplugin.html).
Godot can place that dock beside the Inspector or float it as a separate editor
panel.

Use the following Godot types for different goals:

| Goal | Start with |
| --- | --- |
| A dock like Bouffalant Assets | `EditorPlugin` + `EditorDock` + `Control` nodes |
| A modal editor prompt | `EditorPlugin` + `AcceptDialog` or `ConfirmationDialog` |
| A free-floating editor tool | `EditorPlugin` + `Window` |
| A menu shown while playing the game | Ordinary `Control` nodes in a game scene |

This guide follows the first route.

## Try the Existing Tool Before Reading Its Code

1. Open this project in Godot 4.7.2.
2. Find **Bouffalant Assets** on the right side of the editor. If it is hidden,
   use **Editor > Editor Docks > Bouffalant Assets**.
3. Open a 3D scene, select an asset, and click **Add at Scene Origin**.
4. Press undo and redo. Notice that placement participates in the editor's
   normal history.
5. Turn on **Place in 3D View**, move the cursor over a floor, press `Q` or `E`,
   and left-click. Press `Escape` to stop.
6. Search for an asset and change categories. Notice that the cards are backed
   by data rather than being individually authored buttons.

Those interactions reveal the six main systems worth learning: editor plugin
lifecycle, Control UI, signals, data loading, scene editing with undo, and 3D
viewport input.

## Architecture at a Glance

```text
project.godot
    enables the add-on
        |
        v
plugin.cfg ---> plugin.gd (EditorPlugin and editor integration)
                    |                         |
                    | creates/connects        | edits the open scene
                    v                         v
              EditorDock              PackedScene instances
                    |                         |
                    v                         v
       asset_palette_dock.gd          Editor undo/redo history
          (Control UI and state)
                    ^
                    |
            catalog.json + PNG thumbnails
                    ^
                    |
           generate_thumbnails.gd
```

The most important architectural choice is the split between two scripts:

- [`asset_palette_dock.gd`](asset_palette_dock.gd) owns widgets, filtering,
  selection, presentation state, and user-intent signals.
- [`plugin.gd`](plugin.gd) owns editor-only operations: registering the dock,
  reading the edited scene, receiving 3D viewport input, creating nodes, and
  recording undo actions.

That boundary is worth preserving in your own tools. A reusable UI should not
need to know how Godot's editor mutates the scene tree.

## Read the Project in This Order

| Order | File | What to learn |
| --- | --- | --- |
| 1 | [`plugin.cfg`](plugin.cfg) | The small manifest Godot uses to discover an editor add-on. |
| 2 | [`plugin.gd`](plugin.gd), `_enter_tree()` and `_exit_tree()` | Plugin startup, dock registration, signal wiring, and cleanup. |
| 3 | [`asset_palette_dock.gd`](asset_palette_dock.gd), `_build_interface()` | Building a responsive editor UI from `Control` and `Container` nodes. |
| 4 | [`asset_palette_dock.gd`](asset_palette_dock.gd), `_refresh_assets()` | Search, category filtering, `ItemList`, selection, and item metadata. |
| 5 | [`plugin.gd`](plugin.gd), `_place_selected_asset()` | Loading and instantiating scenes, node ownership, transforms, selection, and undo. |
| 6 | [`plugin.gd`](plugin.gd), `_forward_3d_gui_input()` | Turning mouse and keyboard input in the 3D editor into tool actions. |
| 7 | [`plugin.gd`](plugin.gd), `_placement_position()` | Camera rays, physics queries, a fallback plane, surface normals, and snapping. |
| 8 | [`asset_palette_dock.gd`](asset_palette_dock.gd), `_request_visible_thumbnails()` | Bundled previews, asynchronous editor previews, caching, and invalidation. |
| 9 | [`generate_thumbnails.gd`](generate_thumbnails.gd) | Rendering deterministic preview images with a `SubViewport`. |
| 10 | [`validation/asset_palette_activation_smoke_test.gd`](validation/asset_palette_activation_smoke_test.gd) | A small headless test for an editor-facing Control. |

Also inspect the `editor_plugins` section of [`../../project.godot`](../../project.godot)
and one entry in
[`catalog.json`](../../art/environments/new_bouffalant_city/reference_city_pack/catalog.json).

## The Godot Concepts to Learn

### 1. GDScript, nodes, and signals

Start here if scripts, nodes, and scenes are still new:

- [Your first script](https://docs.godotengine.org/en/4.7/getting_started/step_by_step/scripting_first_script.html)
- [Using signals](https://docs.godotengine.org/en/4.7/getting_started/step_by_step/signals.html)

Both main scripts begin with `@tool`. That annotation tells Godot to execute
the script in the editor. Tool scripts can change editor state, so a parse or
runtime error can break the dock before the game ever starts.

The dock declares signals such as `placement_toggled` and
`place_at_origin_requested`. Buttons emit those signals; `plugin.gd` connects
them to functions that are allowed to interact with the editor. This is the
same event-driven pattern used by ordinary game UI.

### 2. Control nodes and containers

Read [Using Containers](https://docs.godotengine.org/en/4.7/tutorials/ui/gui_containers.html),
then study `_build_interface()` in `asset_palette_dock.gd`.

This window is constructed entirely in code. Its visible hierarchy includes:

```text
EditorDock
└── ScrollContainer
    └── VBoxContainer (AssetPaletteDock)
        ├── Label
        ├── LineEdit
        ├── OptionButton
        ├── ItemList
        ├── placement Controls
        └── navigation Buttons
```

`VBoxContainer` and `HBoxContainer` calculate their children's layout. Size
flags, minimum sizes, wrapping, and separation theme constants are therefore
more important than hand-authored pixel positions.

The project builds the UI in code, but your own dock may use a `.tscn` scene
with a `Control` root. A scene-built UI is often easier to learn visually; the
plugin can instantiate it and place it inside the same `EditorDock` wrapper.

### 3. EditorPlugin and EditorDock

Read [Making plugins](https://docs.godotengine.org/en/4.7/tutorials/plugins/editor/making_plugins.html),
then the `EditorPlugin` and `EditorDock` class references linked above.

The startup flow is:

1. Godot sees the enabled `plugin.cfg` in `addons/`.
2. It creates `plugin.gd` because that is the manifest's `script`.
3. `_enter_tree()` loads data, creates the UI, connects signals, wraps it in an
   `EditorDock`, and calls `add_dock()`.
4. `_exit_tree()` calls `remove_dock()` and frees the dock.

The cleanup step matters. Editor plugins are enabled, disabled, and reloaded
without closing the editor. Missing cleanup can leave duplicate or invalid UI
behind.

This project uses Godot 4.7's `EditorDock` and `add_dock()` API. Older tutorials
may show `add_control_to_dock()`; that older API is deprecated in Godot 4.7.
`EditorDock` is still marked experimental in the 4.7 reference, so keep your
plugin's target engine version explicit and recheck this API when upgrading.

### 4. A data-driven catalog

The palette uses [`FileAccess`](https://docs.godotengine.org/en/4.7/classes/class_fileaccess.html)
and [`JSON`](https://docs.godotengine.org/en/4.7/classes/class_json.html) to load
an array of dictionaries. A minimal catalog for your own tool could be:

```json
{
  "asset_count": 2,
  "assets": [
    {
      "id": "oak_tree",
      "title": "Oak Tree",
      "category": "Nature",
      "kind": "prop",
      "model_path": "res://game/props/oak_tree.tscn"
    },
    {
      "id": "wooden_crate",
      "title": "Wooden Crate",
      "category": "Props",
      "kind": "prop",
      "model_path": "res://game/props/wooden_crate.tscn"
    }
  ]
}
```

The real catalog contains far more import and material data, but the basic dock
only needs `id`, `title`, `category`, `kind`, and `model_path`. Dimensions and
mesh counts are used for details and warnings. Do not copy fields that your
tool does not use.

The [`ItemList`](https://docs.godotengine.org/en/4.7/classes/class_itemlist.html)
stores each complete asset dictionary as item metadata. When a row is selected,
the tool retrieves the dictionary rather than trying to reconstruct an asset
from visible label text. `_refresh_assets()` also remembers the selected asset
by stable ID while rebuilding filtered results.

JSON is a good fit when a catalog is generated by another pipeline. If humans
will author every entry in Godot, custom `Resource` files may provide stronger
typing and a friendlier Inspector workflow.

### 5. Scene insertion, ownership, and undo

Read the references for
[`PackedScene`](https://docs.godotengine.org/en/4.7/classes/class_packedscene.html),
[`Node.owner`](https://docs.godotengine.org/en/4.7/classes/class_node.html#class-node-property-owner),
and [`EditorUndoRedoManager`](https://docs.godotengine.org/en/4.7/classes/class_editorundoredomanager.html).

`_place_selected_asset()` performs these steps:

1. Get the currently edited scene root from `EditorInterface`.
2. Load `model_path` as a `PackedScene`.
3. Instantiate it as a `Node3D` using editor instance state.
4. Find or create a `NewBouffalantCityAssets` organization node.
5. Convert the desired world transform into the parent's local space.
6. Register child insertion and ownership as one undoable editor action.
7. Select the new instance in the editor.

Two details cause many first-plugin bugs:

- `add_child()` puts a node in the live tree, but setting its `owner` to the
  edited scene root is what makes it part of the scene that will be saved.
- A world-space click cannot be assigned directly as a local transform when the
  parent is transformed. The code uses the parent's inverse global transform.

The code also calls `add_do_reference()` so the new nodes stay alive as the
action moves through undo and redo history. Scene mutations made by an editor
tool should normally go through the editor undo manager.

### 6. Input from the 3D editor viewport

`plugin.gd` enables input and overlay forwarding, then implements:

- `_forward_3d_gui_input()` for mouse motion, mouse buttons, `Q`, `E`, and
  `Escape`.
- `_forward_3d_force_draw_over_viewport()` for the placement reticle and label.

The callback returns either `AFTER_GUI_INPUT_PASS` or
`AFTER_GUI_INPUT_STOP`. Pass lets Godot continue handling the event; stop
consumes a placement click or tool shortcut so it does not also select or edit
something in the viewport.

Learn this only after origin placement works. It combines several concerns and
is much easier to debug when scene loading and undo are already proven.

### 7. Turning a mouse position into a 3D position

Read the references for
[`Camera3D`](https://docs.godotengine.org/en/4.7/classes/class_camera3d.html) and
[`PhysicsRayQueryParameters3D`](https://docs.godotengine.org/en/4.7/classes/class_physicsrayqueryparameters3d.html).

The placement calculation has two layers:

1. Project a ray from the viewport camera through the mouse position and query
   the 3D physics world.
2. If there is no suitable floor hit, intersect the ray with a horizontal
   mathematical `Plane` at the chosen fallback Y value.

A physics hit is accepted only when `normal.dot(Vector3.UP) >= 0.55`. That
rejects steep walls. Finally, X and Z are snapped to the selected grid size and
Y is snapped to 0.5 m.

For a first version of your own tool, implement only the fallback plane. Add
physics surface placement after that works.

### 8. Preview images and asynchronous work

The dock first looks for a bundled PNG named after the asset ID. If none exists,
it asks [`EditorResourcePreview`](https://docs.godotengine.org/en/4.7/classes/class_editorresourcepreview.html)
for a preview asynchronously.

Three dictionaries track preview state:

- `_thumbnail_cache` contains successful previews.
- `_thumbnail_failures` prevents endless retries for failed resources.
- `_thumbnail_requests` prevents duplicate requests while a preview is queued.

The dock also listens for `preview_invalidated`, clears stale cache state, and
requests the visible preview again. This is a useful pattern for any editor UI
that performs work asynchronously.

Bundled previews are generated separately by `generate_thumbnails.gd`. That
script creates a [`SubViewport`](https://docs.godotengine.org/en/4.7/classes/class_subviewport.html)
with its own 3D world, lighting, environment, and camera. For each asset it:

1. Instantiates the scene.
2. Combines the bounds of its visible `VisualInstance3D` nodes.
3. Moves the camera far enough away to frame those bounds.
4. Waits for rendered frames.
5. Saves the viewport texture as a PNG.

This is an advanced polish step. A default icon is enough for your first dock.

### 9. Testing editor tools

The current smoke test constructs the dock without opening the graphical editor
and verifies that important catalog entries can be selected and activated. Run
it with:

```sh
godot --headless --path . \
  --script res://addons/new_bouffalant_city_asset_palette/validation/asset_palette_activation_smoke_test.gd
```

It does not simulate a real 3D viewport click or prove that undo saves a scene.
Those behaviors still deserve a short manual check. A useful test strategy is:

- Unit-like headless checks for catalog parsing, filtering, selection, and
  button state.
- A headless editor startup check for parse errors and plugin initialization.
- A tiny temporary scene or manual check for placement, ownership, undo, and
  transformed parents.

## Build Your Own Dock in Seven Milestones

Do not begin by copying all 900-plus lines of the finished tool. Build a small
vertical slice and keep it working after every milestone.

### Milestone 1: Show one label in a dock

Create this structure:

```text
addons/my_asset_dock/
├── plugin.cfg
└── plugin.gd
```

Use a manifest like this:

```ini
[plugin]

name="My Asset Dock"
description="A small asset placement tool."
author="Your Name"
version="0.1.0"
script="plugin.gd"
```

Use this minimal Godot 4.7 plugin:

```gdscript
@tool
extends EditorPlugin

var _dock: EditorDock


func _enter_tree() -> void:
	_dock = EditorDock.new()
	_dock.title = "My Assets"
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_BL
	_dock.available_layouts = (
		EditorDock.DOCK_LAYOUT_VERTICAL | EditorDock.DOCK_LAYOUT_FLOATING
	)

	var content := VBoxContainer.new()
	var heading := Label.new()
	heading.text = "My first editor dock"
	content.add_child(heading)
	_dock.add_child(content)
	add_dock(_dock)


func _exit_tree() -> void:
	if is_instance_valid(_dock):
		remove_dock(_dock)
		_dock.queue_free()
	_dock = null
```

Enable it through **Project > Project Settings > Plugins**. You are done when
the dock can be enabled, disabled, moved, and floated without errors or duplicate
controls.

### Milestone 2: Build a static asset list

Add a `LineEdit`, an `OptionButton`, and an `ItemList`. Hard-code three asset
dictionaries first. Connect `text_changed`, `item_selected`, and
`item_activated` signals.

You are done when search filters the three rows, changing category rebuilds the
list, and each row still retrieves the correct dictionary from item metadata.

### Milestone 3: Load a catalog

Move those dictionaries into a small JSON file. Validate the parsed top-level
type, every asset's required keys, duplicate IDs, and the declared count. Show
a useful error in the dock instead of assuming parsing succeeded.

You are done when a bad path or malformed JSON produces a readable error and
does not crash or partially populate the tool.

### Milestone 4: Add one scene at the origin with undo

Before touching viewport input, add a button that places the selected
`PackedScene` at `(0, 0, 0)`. Guard against no open scene, an invalid resource,
and a non-`Node3D` asset root. Decide whether your first version should reject
an edited scene whose root is not `Node3D`; that is simpler than supporting it.
Set ownership and use `get_undo_redo()`.

You are done when save, undo, and redo all work and the placed node retains its
scene connection.

### Milestone 5: Add viewport placement

Enable 3D input forwarding. First intersect the camera ray with a flat Y plane.
Then add snapping, rotation, an overlay reticle, and finally collision-surface
raycasts.

You are done when placement works beneath a transformed organization node,
wall hits fall back or are rejected as intended, and tool clicks do not also
change the editor selection unexpectedly.

### Milestone 6: Add thumbnails without blocking the editor

Begin with the editor's `PackedScene` icon. Add `EditorResourcePreview` next.
Only build a `SubViewport` thumbnail generator if you need consistent framing or
have enough assets that prebuilt previews materially improve the experience.

You are done when filtering rapidly does not submit duplicate preview work and
an invalidated preview refreshes correctly.

### Milestone 7: Harden and test

Test empty filters, invalid paths, non-3D scenes, transformed roots, repeated
placement, continuous placement off, plugin disable/re-enable, and undo/redo.
Add a focused headless test for the UI and catalog rules that matter most to
your tool.

## What Is Project-Specific and Should Not Be Copied Blindly

These parts support this particular environment pack rather than editor docks
in general:

- [`collision_profiles.gd`](../../tools/new_bouffalant_city_import/collision_profiles.gd)
  maps city asset IDs to collision policy.
- [`runtime_contract.gd`](../../game/world/level_kits/structures/new_bouffalant_city/runtime_contract.gd)
  calculates imported scale, performance warnings, and special mesh-import
  status.
- The `NewBouffalantCityAssets` container name and metadata keys are organization
  conventions for this project.
- The Ground Grid and Metric Browser buttons open hard-coded project scenes.
- The renderer launcher shell scripts are operational helpers, not requirements
  for building a dock.
- The `_unsafe_intel_vulkan_renderer` parameter in `initialize()` is currently
  unused legacy plumbing. Do not reproduce it in a new tool.
- `_build()` in `plugin.gd` currently just returns `true`; a minimal plugin can
  omit that hook unless it has real pre-run build work.

Start with generic concepts, then add domain rules only when your own assets
actually need them.

## Common Failure Modes

| Symptom | Likely cause |
| --- | --- |
| The plugin is listed but no dock appears | A tool-script parse/runtime error, or `_enter_tree()` never reaches `add_dock()`. |
| Enabling twice creates duplicate controls | `_exit_tree()` does not remove and free everything registered by `_enter_tree()`. |
| Controls overlap or stay tiny | Missing container size flags, minimum size, anchors, or wrapping. |
| A placed node disappears after saving/reopening | Its `owner` was never assigned to the edited scene root. |
| Placement is offset under a moved parent | A world transform was assigned as if it were local. |
| Undo does nothing or leaves an empty container | The insertion, ownership, and container creation were not registered in one coherent undo action. |
| A viewport click also selects another object | The input callback returned pass when the tool should have returned stop. |
| Placement sticks to walls | The raycast result was accepted without checking its surface normal. |
| Thumbnails continually retry | Requests, failures, and successful cache entries are not tracked separately. |
| Reloading the add-on breaks callbacks | A signal was connected more than once or a freed editor object was retained. |

## A Sensible First Personal Project

Build a palette containing only three scenes you own: one prop, one building,
and one ground tile. Support search, selection, **Add at Origin**, and undo. That
small version teaches most of the architecture without 3D input or rendering
complexity.

After it is stable, add features in this order:

1. Category filtering.
2. Placement on a flat Y plane.
3. Snap and 90-degree rotation.
4. Placement on upward-facing collision surfaces.
5. Overlay feedback.
6. Asynchronous or bundled thumbnails.
7. Tool-specific metadata and validation.

At that point you will understand the design of Bouffalant Assets rather than
merely having copied it.
