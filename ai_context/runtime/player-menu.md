# R&D Player Menu HUD

Read this document when changing the permanent overworld menu button, the
Party/PC organizer, the persistent bag UI, or the Pokedex browser. Verify the
current implementation and focused smoke test before changing these contracts.

## Shared HUD entry and modal ownership

[`player_menu_hud.tscn`](../../rnd/player_menu/player_menu_hud.tscn) is
instanced by the shared [`game_ui.tscn`](../../demo/game_ui.tscn), so every
authored overworld scene that uses GameUI receives the same visible `Menu`
button. It renders on CanvasLayer 150, above the interaction HUD and UIManager,
and opens by touch/click, keyboard M, or gamepad Y. The menu records the prior
movement state, clears joystick input, and restores only the lock it acquired;
closing a menu opened over an already-running sequence does not unlock that
sequence.

[`PlayerMenuUI`](../../rnd/player_menu/PlayerMenuUI.gd) is a blocking,
keyboard/gamepad-focusable modal with Party & PC, Bag & Items, and Pokedex
tabs. Escape, M, gamepad B, or its close button dismiss it. Search is local,
accent/punctuation-normalized, and typo-tolerant. Text-driven result refreshes
must preserve the search `LineEdit` focus so keyboard and virtual-keyboard users
can enter a complete query; tab and filter navigation may focus the list.

The header's red `RESET PROGRESS` action is intentionally difficult to finish:
three full-screen danger stages enumerate deleted state, require two separate
irreversibility acknowledgements, and finally require typing `RESET FOREVER`.
Only then does the HUD close its own movement lock and call the save owner's
complete reset. The warnings include any linked cloud copy, whose reset epoch
advances before the new starter checkpoint. See
[`starter-selection.md`](starter-selection.md).

## Party and PC organization

The Pokemon screen reads the complete collection from `CollectionSystem` and
shows all six party slots followed by every stored PCL. It never owns a second
collection. `CollectionSystem.move_to_party_slot()` is the atomic organizer
boundary: moving a stored Pokemon into an occupied slot sends that occupant to
PC storage, while moving a party member onto another occupied party slot swaps
the two. `remove_from_party()` sends a member to storage; the UI prevents the
last party member from being removed.

Each captured-Pokemon row shows `XP earned/XP required` for the current level,
and its detail panel adds the exact remaining amount and next level. This is
separate from cumulative `currentXp`: for example, Gible's slow curve starts
Lv. 5 at 156 cumulative XP and reaches Lv. 6 at 270, so 184 cumulative XP is
displayed as `28/114` with 86 remaining.

The selected PCL also lists its direct evolution targets and required levels.
When its current level reaches at least one threshold, a separate `Evolve`
action appears. A single target uses the same blocking prompt as confirmation;
branching species populate a keyboard/gamepad-focusable target selector before
calling `CollectionSystem.evolve_pokemon()`. Eligibility is derived, so a shop,
loot-box, imported, or captured Pokemon obtained above its threshold receives
the action immediately. See [`evolution.md`](evolution.md) for the balance and
mutation contract.

Stretchman shop purchases and loot-box awards call `add_pokemon(..., 0)`, so
both arrive in PC storage with `inParty: false` and `slot: null`. They become
battle party members only through the organizer.

## Bag and Pokedex

The Bag lists only owned item stacks from `StretchGoalSystem`'s persisted
`item_inventory`, with search and category filters. Discards require a quantity
and confirmation, then call `StretchGoalSystem.discard_item()`. Most item
effects remain outside this R&D screen, but the Pokemon detail panel can give
an owned Exp. Share to the selected PCL or take its held item back. A give
removes one item from the bag, a take returns it, and replacing an item returns
the previous item in the same synchronous transaction. Party/PC moves retain
the held item because it belongs to the PCL rather than its slot.

The Pokedex browses all 1,025 default entries in the committed Stretchman
Pokemon catalog. Owned counts are derived from the complete collection,
including PC storage, so no parallel seen/owned save state exists. Filters cover
owned, missing, legendary, and mythical entries. Visible list rows use one still
frame through `BattleSpriteCatalog.load_front_thumbnail()`, while the selected
entry plays the existing full front GIF atlas with original frame timing.

## Optional cloud-save panel

The tab row's `Cloud Save` button opens a blocking settings overlay without
adding a fourth collection tab. Its 12–128 character Save ID field is masked by
default and explicitly warns that the ID acts like a password. `Use ID & Sync`
enables background sync, `Sync Now` requests an immediate pass, and `Opt Out`
clears the local cloud linkage while leaving ordinary autosave enabled. Status
text exposes pending, syncing, offline, server-configuration, merged, and
successful states plus the last revision/time; it never prints database
credentials. See [`cloud-save.md`](cloud-save.md) for persistence and merge
ownership.

## Persistence, export, and regression check

Party/PC operations, evolution, and `CollectionSystem.set_held_item()` emit the
existing collection update signal. Item discards and held-item bag transfers
emit the existing Stretch progression and inventory signals. Schema-4
ProgressionAutosave therefore persists the optional PCL `heldItem` field and
the bag without a new top-level save section. The selected-resource Web export
explicitly includes the player-menu scripts and scenes.

```bash
godot --headless --path . --scene res://rnd/tests/player_menu_hud_smoke_test.tscn
godot --headless --path . --scene res://tests/collection_system_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/progression_autosave_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/starter_selection_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/cloud_save_sync_smoke_test.tscn
```
