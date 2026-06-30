extends Control

var client: IndigaugeClient

@onready var _category: OptionButton = $Center/PanelContainer/VBox/Form/CategoryRow/Category
@onready var _question: LineEdit = $Center/PanelContainer/VBox/Form/QuestionRow/Question
@onready var _message: TextEdit = $Center/PanelContainer/VBox/Form/MessageRow/Message
@onready var _screenshot: CheckBox = $Center/PanelContainer/VBox/Form/OptionsRow/Screenshot
@onready var _error: Label = $Center/PanelContainer/VBox/Footer/Error
@onready var _submit: Button = $Center/PanelContainer/VBox/Footer/Buttons/Submit
@onready var _cancel: Button = $Center/PanelContainer/VBox/Footer/Buttons/Cancel

func _ready() -> void:
	if client == null:
		client = _find_client()

	_submit.pressed.connect(_on_submit)
	_cancel.pressed.connect(queue_free)
	_message.call_deferred("grab_focus")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		queue_free()
		get_viewport().set_input_as_handled()

func _on_submit() -> void:
	if client == null:
		_show_error("Feedback client is not available.")
		push_error("[Indigauge] FeedbackPanel: client is not set.")
		return

	var message := _message.text.strip_edges()
	if message.length() < 2:
		_show_error("Enter at least 2 characters.")
		return

	var cat := _category.get_item_text(_category.selected)
	var question := _question.text.strip_edges()
	var include_screenshot := _screenshot.button_pressed

	if include_screenshot:
		_submit.disabled = true
		_cancel.disabled = true
		visible = false
		await RenderingServer.frame_post_draw

	client.submit_feedback(message, cat, question, include_screenshot)
	queue_free()

func _show_error(message: String) -> void:
	_error.text = message
	_error.visible = true

func _find_client() -> IndigaugeClient:
	var clients := get_tree().get_nodes_in_group("indigauge_clients")
	if clients.is_empty():
		return null
	return clients[0] as IndigaugeClient
