extends Control

@onready var category: OptionButton = $PanelContainer/VBox/Category
@onready var message: TextEdit = $PanelContainer/VBox/Message
@onready var screenshot: CheckBox = $PanelContainer/VBox/Screenshot
@onready var submit: Button = $PanelContainer/VBox/Buttons/Submit
@onready var cancel: Button = $PanelContainer/VBox/Buttons/Cancel

var question: String = ""

func _ready() -> void:
	submit.pressed.connect(_on_submit)
	cancel.pressed.connect(queue_free)

func _on_submit() -> void:
	var cat := category.get_item_text(category.selected)
	IndigaugeClient.submit_feedback(message.text, cat, question, screenshot.button_pressed)
	queue_free()
