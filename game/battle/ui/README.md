# UI Template System

The UI Template System displays reusable message, dialog, confirmation, and
sequence UI above the active scene. It consists of four pieces:

| Piece | Responsibility |
| --- | --- |
| [`UIManager`](../../ui/shared/ui_manager.gd) | Global factory that creates and displays a template |
| [`UITemplate`](../../ui/shared/ui_template.gd) | The displayed `Control` and its button/text API |
| Caller | Owns state, callbacks, advancement, gameplay locks, and cleanup |
| [`Dialog`](../../dialogue/dialog.gd) | Optional data resource containing a speaker and ordered lines |

`UIManager` is an autoload, so gameplay scripts call it directly. Do not add
`ui_template.tscn` to each gameplay scene manually.

## Show a single message

Keep the returned `UITemplate` when the caller needs to update or close it:

```gdscript
var _message_ui: UITemplate


func show_message() -> void:
	if is_instance_valid(_message_ui):
		return

	_message_ui = UIManager.show_ui("The door is locked.")
	if not _message_ui:
		return

	_message_ui.set_speaker_name("System")
	_message_ui.set_action_text("Okay")
	_message_ui.set_action_callback(_accept_message)
	_message_ui.set_dismiss_callback(_message_closed)


func _accept_message() -> void:
	if is_instance_valid(_message_ui):
		_message_ui.close()


func _message_closed() -> void:
	_message_ui = null
```

`show_ui(text)` creates the template, adds it above the game scene, initializes
the message, and returns that exact instance. The primary action does not close
automatically; its callback must update the UI or call `close()`.

## Show confirm and cancel actions

The dismiss button is hidden by default. Make it visible when the player needs
a separate cancel or back action:

```gdscript
var _confirmation_ui: UITemplate


func ask_to_use_item() -> void:
	if is_instance_valid(_confirmation_ui):
		return

	_confirmation_ui = UIManager.show_ui("Use the potion?")
	if not _confirmation_ui:
		return

	_confirmation_ui.set_action_text("Use")
	_confirmation_ui.set_action_callback(_confirm_item)
	_confirmation_ui.set_dismiss_text("Cancel")
	_confirmation_ui.set_dismiss_visible(true)
	_confirmation_ui.set_dismiss_callback(_confirmation_closed)


func _confirm_item() -> void:
	use_item()
	if is_instance_valid(_confirmation_ui):
		_confirmation_ui.close()


func _confirmation_closed() -> void:
	_confirmation_ui = null
```

Pressing the dismiss button calls `close()`. Calling `close()` after confirming
runs the same dismiss lifecycle, which makes the dismiss callback the right
place for shared cleanup. If confirm and cancel need different outcomes, store
that outcome in the caller before closing.

## Play a multi-line Dialog resource

`Dialog` stores data only. It does not display or advance itself. A playback
caller owns the active resource, line index, returned template, and completion
behavior:

```gdscript
var _active_dialog: Dialog
var _dialog_ui: UITemplate
var _line_index := -1


func play_dialog(dialog: Dialog) -> void:
	if not dialog or dialog.is_empty():
		return
	if is_instance_valid(_dialog_ui):
		return

	GameInstance.set_player_movement_enabled(false)
	_active_dialog = dialog
	_line_index = 0
	_dialog_ui = UIManager.show_ui(_active_dialog.dialog_lines[_line_index])
	if not _dialog_ui:
		_finish_dialog()
		return

	_dialog_ui.set_speaker_name(_active_dialog.character_name)
	_dialog_ui.set_action_text("Next")
	_dialog_ui.set_action_callback(_advance_dialog)
	_dialog_ui.set_dismiss_callback(_finish_dialog)


func _advance_dialog() -> void:
	if not is_instance_valid(_dialog_ui):
		_finish_dialog()
		return

	_line_index += 1
	if _line_index >= _active_dialog.dialog_lines.size():
		_dialog_ui.close()
		return

	_dialog_ui.set_text(_active_dialog.dialog_lines[_line_index])


func _finish_dialog() -> void:
	_dialog_ui = null
	_active_dialog = null
	_line_index = -1
	GameInstance.set_player_movement_enabled(true)
```

This is the same ownership pattern used by
[`TrainerBehavior`](../../actors/npcs/trainers/trainer_behavior.gd). Its assigned resources are examples
of how trainer dialogs use the template system.

## Create and assign Dialog data

To create reusable dialog in the Godot editor:

1. In the FileSystem dock, create a new **Resource**.
2. Select the `Dialog` resource type.
3. Set **Character Name** and add entries to **Dialog Lines**.
4. Save the resource in a relevant content directory, such as
   [`game/dialogue/resources/trainers`](../../dialogue/resources/trainers/).
5. Expose an assignment point with `@export var dialog: Dialog`, or load the
   resource explicitly, and pass it to caller-owned playback code.

The speaker panel is hidden when `character_name` is empty. `Dialog.is_empty()`
checks whether there are any lines; always check it before indexing line `0`.

## UITemplate API

All setters update the live instance and return that same `UITemplate`.

| API | Behavior |
| --- | --- |
| `set_text(text)` | Replaces the main message |
| `set_speaker_name(name)` | Sets the speaker; an empty name hides its panel |
| `set_action_text(text)` | Sets the primary label; the template adds the arrow |
| `set_dismiss_text(text)` | Sets the dismiss label |
| `set_action_callback(callback)` | Sets the zero-argument primary callback |
| `set_dismiss_callback(callback)` | Sets the zero-argument cleanup callback |
| `set_action_enabled(enabled)` | Enables or disables the primary button |
| `set_dismiss_visible(visible)` | Shows or hides the dismiss button |
| `close()` | Emits dismissal, runs cleanup, and queues the instance for deletion |

The template also exposes zero-argument `action_pressed` and `dismissed`
signals. On an action press, `action_pressed` is emitted before the configured
action callback. During `close()`, `dismissed` is emitted before the configured
dismiss callback.

Callbacks are invoked without arguments. Bind required values beforehand:

```gdscript
_message_ui.set_action_callback(_select_reward.bind(reward_id))
```

Use either the setter callbacks or signal connections for a behavior. Connecting
the same handler through both mechanisms runs it twice.

## Defaults and lifecycle

- The primary action starts as `Next` and automatically receives keyboard or
  controller focus.
- The primary label renders an arrow after its text. Pass `Continue`, not
  `Continue ➜`.
- The dismiss action starts as `Close` and is hidden.
- The speaker panel is hidden until a non-empty speaker is assigned.
- `UIManager` displays templates on `CanvasLayer` layer `100`.
- `close()` is guarded against repeated calls.
- Deletion is queued, so clear the caller's reference in the dismiss callback.

The fullscreen template prevents pointer clicks from reaching controls behind
it, but it does not disable keyboard, controller, NPC, or gameplay logic. The
caller must acquire and release the relevant gameplay state, as the dialog
example does with `GameInstance`.

Always use `close()` when cleanup depends on `set_dismiss_callback()`. Calling
`queue_free()` directly skips the dismissed signal and dismiss callback.

## Multiple templates and caller cleanup

`UIManager` does not queue, replace, or deduplicate templates. Every
`show_ui()` call creates another fullscreen instance. A caller should normally
guard against opening a second instance and retain only the one it owns.

If the caller can leave the scene while its UI is open, close its template from
the caller's teardown path:

```gdscript
func _exit_tree() -> void:
	if is_instance_valid(_message_ui):
		_message_ui.close()
```

Do not close a template owned by another caller. A future queue or modal-stack
system would need a separate ownership contract.

## Customize the shared presentation

Edit [`ui_template.tscn`](../../ui/shared/ui_template.tscn) to change the common layout,
anchors, typography, colors, and button styling. `UITemplate.gd` resolves these
scene nodes by unique name:

- `%Message`
- `%SpeakerPanel`
- `%Speaker`
- `%ActionButton`
- `%DismissButton`

Keep those nodes and their **Unique Name in Owner** settings when restyling the
scene, or update the script and all callers together.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| The UI never closes | The action callback must eventually call `close()`, or the dismiss button must be visible |
| The dismiss button is missing | Call `set_dismiss_visible(true)` |
| The speaker panel is missing | Assign a non-empty speaker name |
| The player moves during dialog | Lock movement or other gameplay state in the caller and restore it in dismiss cleanup |
| Two dialogs overlap | Guard the caller's reference and coordinate ownership before another `show_ui()` call |
| Cleanup did not run | Use `close()` instead of direct `queue_free()` |
| A callback reports missing arguments | Use `Callable.bind(...)`; template callbacks receive no arguments |
| The action label has two arrows | Do not include an arrow in `set_action_text()` |

The current system has no global queue, branching choices, localization,
typewriter effect, history, or global conversation state machine. Add those as
separate features when required rather than assuming `UIManager` provides them.
