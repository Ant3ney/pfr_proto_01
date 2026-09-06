extends CanvasLayer

## Displays reusable UI templates above the current game scene.

const UI_TEMPLATE_SCENE: PackedScene = preload(
	"res://game/ui/shared/ui_template.tscn"
)


func _ready() -> void:
	layer = 100


func show_ui(text: String) -> UITemplate:
	var template := UI_TEMPLATE_SCENE.instantiate() as UITemplate
	if not template:
		push_error("UIManager could not instantiate its UI template.")
		return null

	template.set_text(text)
	add_child(template, true)
	return template
