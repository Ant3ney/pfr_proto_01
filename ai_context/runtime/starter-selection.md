# R&D Starter Selection and Full Reset

Read this document when changing first-run profile initialization, the starter
roster or presentation, the player-menu reset sequence, or complete progression
deletion. Verify the current owners and focused smoke test before changing the
contract.

## Fresh-profile ownership and roster

[`StarterSelectionSystem.gd`](../../rnd/starter_selection/StarterSelectionSystem.gd)
is the `RNDStarterSelectionSystem` autoload. It does not decide whether a save
is new: `ProgressionAutosave` calls `prepare_new_profile()` only after no valid
save exists or after an explicitly confirmed reset. The system then blocks
movement, presents the mandatory picker, validates the selected ID, and creates
exactly one full-health level-5 PCL in party slot 1 through
`CollectionSystem.add_pokemon()`. Existing saves, including schema-1 through
schema-3 saves, load without being forced through onboarding.

The roster is fixed and ordered:

| Type | Pokemon | PokeAPI ID | Origin | Exact sprite ID |
| --- | --- | ---: | --- | --- |
| Fire | Charmander | 4 | Generation I / Kanto | `charmander` |
| Water | Froakie | 656 | Generation VI / Kalos | `froakie` |
| Grass | Treecko | 252 | Generation III / Hoenn | `treecko` |

[`StarterSelectionUI.gd`](../../rnd/starter_selection/StarterSelectionUI.gd)
shows all three cards together and requires a second confirmation after a card
is chosen. Each card owns a separate initialized `BattleSpriteCatalog` instance
and retains the exact front-facing `ani` `SpriteFrames`, allowing all three
source GIF animations to advance simultaneously with their generated frame
durations. The UI has no close path: Escape backs out of the confirmation but
cannot bypass choosing a starter. The system restores movement only when it
owned the movement lock.

## Schema-5 profile initialization

ProgressionAutosave schema 4 introduced
`profile.starter_pokemon_id`. A newly selected ID must be one of the three
roster IDs. Zero remains accepted only as migrated legacy-profile identity;
schema-1 through schema-3 saves upgrade without discarding their existing
collection. The current schema 5 adds offline/cloud conflict timestamps without
changing starter identity. An initialized schema-5 profile cannot have an empty
collection.

A fresh profile is deliberately not written while starter selection is
pending. Closing the application on the picker therefore leaves no empty save;
the picker appears again next launch. The first starter confirmation creates
the PCL, records its original starter ID, captures the main-scene pose, and
writes the first schema-5 checkpoint. Later evolution does not change the
recorded original choice.

## Destructive reset sequence

The permanent player menu exposes a red `RESET PROGRESS` button. It never calls
the reset API immediately. [`PlayerMenuUI`](../../rnd/player_menu/PlayerMenuUI.gd)
requires all of these gates:

1. A full-screen permanent-deletion warning.
2. A detailed list of erased systems plus separate acknowledgements for Pokemon
   deletion and the absence of recovery.
3. A final point-of-no-return warning and the exact phrase `RESET FOREVER`.

Only the last red button emits `reset_progress_confirmed`. `PlayerMenuHUD`
closes its menu first so the menu releases its movement lock, then calls
`ProgressionAutosave.reset_all_progress()`.

The final phrase field keeps `LineEdit.virtual_keyboard_enabled` on and handles
its touchscreen press by explicitly entering edit mode and requesting
`DisplayServer.virtual_keyboard_show()`. The Web export must also set
`html/experimental_virtual_keyboard=true`. These boundaries are required for a
tap to summon a phone's native keyboard even when the field already owns focus;
the Netlify build rejects generated HTML whose Godot config disables support.

The save owner deletes the disk checkpoint, clears the collection and pending
move choices, restores the Stretch economy/inventory/badges/Champion/run state,
clears process-only standard-trainer sight history, drops the saved world pose,
and returns to
[`primary_development_enviroment.tscn`](../../demo/primary_development_enviroment.tscn).
Autosave remains suppressed throughout the transfer. The starter picker then
acquires movement control, and no new save exists until a new starter is
confirmed. If optional cloud saving is linked, `CloudSaveSync` advances its
reset epoch before the owners are cleared; the new starter checkpoint then
supersedes older cloud copies, including a later upload from an offline old
device. This API is valid only while battle and scene transitions are idle.

## Regression and export checks

```bash
godot --headless --path . --scene res://rnd/tests/starter_selection_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/player_menu_hud_smoke_test.tscn
godot --headless --path . --scene res://rnd/tests/progression_autosave_smoke_test.tscn
```

The focused test verifies exact IDs and regions, multi-frame front animations,
three-card 960-by-540 fit, confirmation, a single battle-ready level-5 PCL,
schema-5 disk output, full owner reset, transient trainer reset, every warning
gate, touchscreen-keyboard-enabled reset focus, exact-phrase enforcement, and
cloud-reset warning language. The
selected-resource Web export explicitly
includes both starter scripts and its scene. Keep starter implementation under
`rnd/starter_selection/`; outside changes should remain thin autoload, save,
menu, transient-reset, export, test, and context wiring.
