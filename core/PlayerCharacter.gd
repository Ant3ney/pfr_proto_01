class_name PlayerCharacter
extends PFRCharacter

## A PFRCharacter configured to use player input.


func _init() -> void:
	controller = PlayerController.new()
