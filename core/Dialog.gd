class_name Dialog
extends Resource

## Data displayed by a caller-controlled dialog sequence.

@export var character_name := ""
@export var dialog_lines: Array[String] = []


func is_empty() -> bool:
	return dialog_lines.is_empty()
