# Dialog and UI Runtime Contract

Use this document when displaying a UI template, creating dialog data, or
implementing dialog playback. The current implementation deliberately keeps
conversation state in the caller rather than in a global dialog manager.

The contributor-facing [UI Template System guide](../../game/battle/ui/README.md)
contains copyable single-message, confirmation, and multi-line dialog recipes,
plus styling and troubleshooting instructions. This AI Context document records
the narrower runtime ownership contract that those recipes follow.

## Ownership model

- [`UIManager`](../../game/ui/shared/ui_manager.gd) is an autoloaded `CanvasLayer`. It
  creates visual templates above the active game scene at layer `100`.
- `UIManager.show_ui(text: String) -> UITemplate` instantiates the current
  [`ui_template.tscn`](../../game/ui/shared/ui_template.tscn), initializes its message,
  adds it beneath the manager, and returns that specific template object.
- The caller owns the meaning of the UI, its state, line index, callbacks, and
  completion behavior. `UIManager` does not own or advance conversations.
- `UIManager` does not currently queue, replace, or deduplicate templates.
  Multiple calls can therefore produce overlapping instances unless callers
  coordinate them.

## Dialog data

[`Dialog`](../../game/dialogue/dialog.gd) is a data-only `Resource` with two exported
fields:

| Field | Meaning |
| --- | --- |
| `character_name: String` | Speaker name displayed by the template |
| `dialog_lines: Array[String]` | Ordered messages advanced by the caller |

`Dialog.is_empty()` checks only whether `dialog_lines` is empty. An empty
speaker name is valid and causes the speaker panel to be hidden. Reusable
examples live in [`game/dialogue/resources/trainers`](../../game/dialogue/resources/trainers/).

## Returned template API

[`UITemplate`](../../game/ui/shared/ui_template.gd) is both the displayed `Control` and the
object callers use to update that instance.

| API | Effect |
| --- | --- |
| `set_text(text)` | Replaces the message |
| `set_speaker_name(name)` | Sets the speaker and hides its panel when empty |
| `set_action_text(text)` | Changes the primary button label |
| `set_dismiss_text(text)` | Changes the dismiss button label |
| `set_action_callback(callback)` | Assigns the primary action behavior |
| `set_dismiss_callback(callback)` | Assigns completion or cleanup behavior |
| `set_action_enabled(enabled)` | Enables or disables the primary action |
| `set_dismiss_visible(visible)` | Shows or hides the dismiss button |
| `close()` | Runs the dismiss lifecycle and queues the template for deletion |

The template also emits `action_pressed` and `dismissed`. A primary action
emits `action_pressed` before invoking its assigned callback. `close()` is
guarded against repeated calls; it emits `dismissed`, invokes the dismiss
callback, and then calls `queue_free()`.

Call `close()` when cleanup depends on the dismiss callback. Directly freeing
the node does not run that callback. The dismiss button is hidden by default,
while the primary button defaults to `Next` and receives focus when ready.

## Caller-controlled playback

A dialog caller should:

1. Reject or finish an absent or empty `Dialog` before indexing its lines.
2. Pass the first line to `UIManager.show_ui()` and retain the returned object.
3. Configure the speaker and action callback on that object.
4. Update the same object's text as its own line index advances.
5. Call `close()` after the final line.
6. Put external-state cleanup in the dismiss callback or a shared finish path.

[`TrainerBehavior`](../../game/actors/npcs/trainers/trainer_behavior.gd) is the current reference
implementation. On automatic arrival or accepted HUD interaction it opens the
first assigned line, owns the line index, updates the returned template when
`Next` is pressed, and closes it after the last line. Its dismiss callback
restores player movement and, only after normal final-line completion, hands
control to `GameInstance.startBattle()` for a trainer encounter. See
[`sequences.md`](sequences.md) for the control-state contract.

Trainer dialog data is assigned through the exported `dialog` property on
[`TrainerKyle`](../../game/actors/npcs/trainers/trainer_controller.gd); the lake trainer
scene demonstrates that resource assignment in
[`TrainerKyle.tscn`](../../game/actors/npcs/trainers/presets/trainer_kyle.tscn).

[`PokemonCenterHealerBehavior`](../../game/actors/npcs/services/pokemon_center_healer/pokemon_center_healer_behavior.gd) is
the current confirmation-and-result example. Its authored scene waits for the
shared look-interaction HUD, then opens one template with **Heal** and **Not
now**, applies the party mutation only from the primary callback, and reuses
that same template for the full-health, already-healthy, or empty-party result.
The behavior owns the movement lock, template reference, sequence state, and
cleanup. It will not start while another sequence has movement disabled. Its
optional legacy proximity mode still requires an exit before auto-prompting
again.

## Current boundaries

There is no global dialog state machine, conversation queue, branching dialog
graph, localization layer, typewriter effect, or dialog history. Individual
callers can compose a confirmation from the template's action and dismiss
callbacks, as the healer does. Preserve caller ownership unless the project
deliberately adopts a different architecture.
