extends Control

# Set this to an IndigaugeClient instance before adding this scene to the tree.
var client: IndigaugeClient

@onready var _category: OptionButton = $Center/PanelContainer/VBox/Form/CategoryRow/Category
@onready var _question: LineEdit = $Center/PanelContainer/VBox/Form/QuestionRow/Question
@onready var _message: TextEdit = $Center/PanelContainer/VBox/Form/MessageRow/Message
@onready var _screenshot: CheckBox = $Center/PanelContainer/VBox/Form/OptionsRow/Screenshot
@onready var _submit: Button = $Center/PanelContainer/VBox/Footer/Buttons/Submit
@onready var _cancel: Button = $Center/PanelContainer/VBox/Footer/Buttons/Cancel

func _ready() -> void:
_submit.pressed.connect(_on_submit)
_cancel.pressed.connect(queue_free)

func _on_submit() -> void:
if client == null:
push_error("[Indigauge] FeedbackPanel: client is not set.")
return
var cat := _category.get_item_text(_category.selected)
client.submit_feedback(_message.text, cat, _question.text, _screenshot.button_pressed)
queue_free()
