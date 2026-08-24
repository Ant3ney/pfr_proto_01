# Battle Start and Transition Contract

Use this document when launching a battle, adding fields to battle launch data,
changing the transition presentation, or consuming the temporary data in the
battle scene. The contributor-facing UI Template System guide is maintained
separately; this document covers only the battle-specific relationship with
that system.

## Entry point

[`GameInstance.startBattle(battle_data := {})`](../../core/GameInstance.gd) is
the single battle-launch entry point. It returns `true` when the launch request
is accepted and `false` when it cannot start. A `true` result means the visual
sequence has begun; the scene change completes asynchronously.

```gdscript
var accepted := GameInstance.startBattle({
	"encounter_type": "trainer",
	"trainer_name": "Ranger Mira",
	"player_party": player_party,
	"opponent_party": opponent_party,
})
```

The function does not run battle rules, spawn creatures, or construct the
battle HUD. It owns the transition, movement lock, scene swap, and temporary
launch-data handoff.

## Launch data

All caller-provided fields are preserved in a deep copy. Callers can therefore
pass the party, trainer, encounter, or later server data needed by battle code
without allowing later mutations of the caller's dictionary to alter the
pending launch.

The presentation recognizes these optional fields:

| Field | Effect |
| --- | --- |
| `encounter_type` | Selects the default title; currently `wild`, `trainer`, `rival`, or a custom value |
| `transition_title` | Overrides the large transition heading |
| `transition_subtitle` | Overrides the opposing-side transition label |
| `opponent_name` | First fallback for the transition subtitle |
| `trainer_name` | Second fallback for the transition subtitle |
| `encounter_name` | Third fallback for the transition subtitle |
| `intro_title` | Overrides the short banner shown inside the battle scene |
| `return_scene_path` | Explicit scene to return to after a future battle-end flow |

`GameInstance` supplies these fields when the caller omits them:

- `source_scene_path` is captured from the current scene.
- `return_scene_path` defaults to that source scene.
- `encounter_type` defaults to `wild`.
- `transition_title` defaults to `WILD ENCOUNTER`, `TRAINER BATTLE`,
  `RIVAL BATTLE`, or `BATTLE START` according to the encounter type.
- `transition_subtitle` defaults to the first available opposing name, then
  `A NEW CHALLENGER APPROACHES`.

`get_pending_battle_data()` returns a defensive copy while the old scene is
being covered. When the battle scene enters, that pending dictionary is moved
to active state. `get_active_battle_data()` then returns a defensive copy for
future battle setup. The active dictionary is not a save format.

## Transition and UI-template handoff

The transition uses one `UITemplate` instance owned by `GameInstance` across
both scenes:

| Stage | Owner and action |
| --- | --- |
| Launch accepted | `GameInstance` disables overworld movement and stores the prepared launch data |
| Old-scene cover | `GameInstance` calls `UIManager.show_ui("")`, retains the returned template, installs its dismiss cleanup, and calls `play_battle_transition_out(data, covered_callback)` |
| Fully covered | The template invokes the supplied callback; only then does `GameInstance` call `change_scene_to_file()` |
| Battle scene ready | [`BattleScene`](../../battle/BattleScene.gd) prepares its local intro visuals and calls `GameInstance.enter_battle_scene()` |
| Data promotion | `GameInstance` moves pending data to active data and emits `battle_scene_entered` |
| New-scene reveal | `GameInstance` calls `play_battle_transition_in(completed_callback)` on the same template |
| Template completion | The template closes itself through `UITemplate.close()`, so its dismiss callback clears `GameInstance`'s transition reference |
| Launch completion | The duplicate-start guard is released and `battle_start_finished` is emitted only after both the template reveal and the battle scene's local intro finish |

Keeping the cover and reveal on the same autoload-owned template prevents a
visible blank frame between scenes. The template runs at `UIManager` layer
`100`; the battle scene's short flash, ring, streak, banner, and camera snap-in
run locally at layer `50`, becoming visible as the global cover opens.
`BattleScene` reports its completion through
`GameInstance.notify_battle_intro_finished()`; later battle setup can wait for
`battle_start_finished` when it must not appear underneath the intro.

## UI ownership at the call site

`GameInstance` owns only the transition template it creates. It does not close
a dialog or other template owned by another caller. If a battle begins from an
existing dialog, that dialog's owner must close it normally and launch the
battle from its completion path:

```gdscript
func _finish_dialog() -> void:
	_dialog_template = null
	GameInstance.startBattle(_prepared_battle_data)


func _accept_final_line() -> void:
	_dialog_template.set_dismiss_callback(_finish_dialog)
	_dialog_template.close()
```

Do not call `queue_free()` on the old template; that bypasses its dismiss
lifecycle. Do not call `startBattle` twice while
`is_battle_start_in_progress()` is true. A repeated request is rejected rather
than creating overlapping transition templates.

[`TrainerBehavior`](../../core/TrainerBehavior.gd) performs this handoff after
the player advances past the assigned dialog's final line. It marks only that
normal completion path for battle, closes its dialog through `close()`,
releases the trainer sequence's movement lock, and calls `startBattle()` with
`encounter_type = "trainer"` and the dialog's `character_name` as
`trainer_name`. Missing dialog data, an invalid template, and other early
finish paths restore movement without starting a battle.

## Movement and failure behavior

The launch captures the previous player-movement state and immediately locks
movement. Any failure before the battle scene enters clears pending data,
closes the owned template through its lifecycle, and restores the captured
movement state.

A successful launch deliberately leaves overworld movement disabled after the
intro. The future battle-end/return flow owns restoring movement when it returns
to an overworld scene. That return flow is not implemented yet.

The following signals expose milestones without transferring ownership:

- `battle_starting(battle_data)`
- `battle_scene_entered(battle_data)`
- `battle_start_finished(battle_data)`
- `battle_start_failed(message)`

Signal dictionaries are defensive copies produced by the public data getters.

## Battle-scene boundary

[`battle_scene.tscn`](../../battle/battle_scene.tscn) retains the established
camera and spawn transforms. Its [`BattleScene`](../../battle/BattleScene.gd)
script only consumes launch data and plays presentation effects. Creature
spawning, battle rules, server communication, commands, battle HUD state, and
battle completion remain intentionally unimplemented.

Running the scene directly is supported for visual preview. With no active
`startBattle` request, it receives an empty launch dictionary and still plays
its local intro; no global transition or data promotion occurs.

## Regression check

Run the end-to-end smoke test with:

```bash
godot --headless --path . --scene res://tests/battle_start_smoke_test.tscn
godot --headless --path . --scene res://tests/trainer_dialog_battle_start_smoke_test.tscn
```

It verifies deep-copy isolation, implicit launch fields, duplicate-start
rejection, movement locking, one-template ownership, scene change, data
promotion, transition cleanup, local intro completion, and the preserved camera
and spawn transforms. The focused trainer-dialog check verifies that only
normal final-line completion hands the trainer name into `startBattle()`.
