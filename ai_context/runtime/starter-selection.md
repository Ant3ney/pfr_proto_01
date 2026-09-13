# Starter Selection and Full Reset

Read this document when changing first-run profile initialization, the starter
roster or presentation, the player-menu reset sequence, or complete progression
deletion. Verify the current owners and focused smoke test before changing the
contract.

## Fresh-profile ownership and roster

[`StarterSelectionSystem.gd`](../../game/progression/starter_selection/starter_selection_system.gd)
is the `StarterSelectionSystem` autoload. It does not decide whether a save
is new: `ProgressionAutosave` prepares it only after the startup menu finds no
save or after an explicitly confirmed reset. The configured project entry first
plays the eight-message Cypress introduction; its final Next action asks the
system to present the mandatory picker. The system blocks movement, validates
the selected ID, and creates
exactly one full-health level-5 PCL in party slot 1 through
`CollectionSystem.add_pokemon()`. Existing saves, including schema-1 through
schema-3 saves, load without being forced through onboarding. Direct F6 scene
launches retain a picker-only first-run path for editor work.

The roster is fixed and ordered:

| Type | Pokemon | PokeAPI ID | Origin | Exact sprite ID |
| --- | --- | ---: | --- | --- |
| Fire | Charmander | 4 | Generation I / Kanto | `charmander` |
| Water | Froakie | 656 | Generation VI / Kalos | `froakie` |
| Grass | Treecko | 252 | Generation III / Hoenn | `treecko` |

[`StarterSelectionUI.gd`](../../game/progression/starter_selection/starter_selection_ui.gd)
shows all three cards together and requires a second confirmation after a card
is chosen. Each card owns a separate initialized `BattleSpriteCatalog` instance
and retains the exact front-facing `ani` `SpriteFrames`, allowing all three
source GIF animations to advance simultaneously with their generated frame
durations. The UI has no close path: Escape backs out of the confirmation but
cannot bypass choosing a starter. The system restores movement only when it
owned the movement lock.

## Schema-6 profile initialization

ProgressionAutosave schema 4 introduced
`profile.starter_pokemon_id`. A newly selected ID must be one of the three
roster IDs. Zero remains accepted only as migrated legacy-profile identity;
schema-1 through schema-3 saves upgrade without discarding their existing
collection. Schema 5 added offline/cloud conflict timestamps and schema 6 split
the economy, inventory, and challenge sections without changing starter
identity. An initialized schema-6 profile cannot have an empty
collection.

A fresh profile is deliberately not written while the introduction, starter
selection, or station entry is pending. Closing the application during that
handoff therefore leaves no empty save; the complete introduction appears
again next launch. Starter confirmation creates the PCL and records its
original starter ID, but the first schema-6 checkpoint waits until the station
concourse has applied `StretchmanReturnSpawn` and startup has enabled player
control. Later evolution does not change the recorded original choice.

## Destructive reset sequence

The permanent player menu exposes a red `RESET PROGRESS` button, and menu New
Game uses the same
[`ProgressResetConfirmation`](../../game/ui/reset_progress/progress_reset_confirmation.gd)
when any local file exists. It never calls the reset API immediately. The
component presents three red warning dialogs: progression loss, irreversibility
without a previously exported JSON backup, and replacement of a linked cloud
save. Every stage requires its own **Yes** press and offers **Cancel**. There is
no text entry or checkbox; only the third Yes emits confirmation, exactly once.
`PlayerMenuHUD` closes its menu first so the menu releases its movement lock,
then calls `ProgressionAutosave.reset_all_progress()`.

The save owner deletes the disk checkpoint, clears the collection and pending
move choices, resets economy, inventory, and challenge progression,
clears process-only standard-trainer sight history, drops the saved world pose,
and returns to
[`startup_controller.tscn`](../../game/startup/startup_controller.tscn).
Autosave remains suppressed throughout the transfer. The complete Cypress
introduction and starter picker replay, and no new save exists until the
replacement starter reaches Stretchman's room. If optional cloud saving is
linked, `CloudSaveSync` advances its
reset epoch before the owners are cleared; the new starter checkpoint then
supersedes older cloud copies, including a later upload from an offline old
device. A separately exported JSON file is outside both deletion targets and
can be imported after the replacement starter is selected; that import keeps
the advanced reset epoch and synchronizes as new progress. This API is valid
only while battle and scene transitions are idle.

## Regression and export checks

```bash
godot --headless --path . --scene res://tests/integration/starter_selection_smoke_test.tscn
godot --headless --path . --scene res://tests/scenes/player_menu_hud_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/progression_autosave_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/startup_entry_smoke_test.tscn
godot --headless --path . --scene res://tests/integration/reset_restart_smoke_test.tscn
```

The focused test verifies exact IDs and regions, multi-frame front animations,
three-card 960-by-540 fit, confirmation, a single battle-ready level-5 PCL,
schema-6 disk output, full owner reset, transient trainer reset, every warning
gate and cancellation point, exactly three Yes presses, one reset emission, and
cloud-reset/portable-backup warning language. The startup entry test verifies
each starter at level 5 and the station checkpoint; the reset restart test
verifies the complete introduction repeats before replacement. The
selected-resource Web export explicitly
includes both starter scripts and its scene. Keep starter implementation under
`game/progression/starter_selection/` and preserve the autoload/save/menu,
transient-reset, export, test, and context boundaries above.
