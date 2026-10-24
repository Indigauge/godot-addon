extends Control

@export var title: String = "Share anonymous gameplay data?"
@export_multiline var message: String = (
	"We use gameplay telemetry and diagnostics to improve game balance, stability, "
	+ "and performance. You can change this later in your game settings."
)
@export var accept_button_text: String = "Allow"
@export var decline_button_text: String = "Decline"

var client: IndigaugeClient

@onready var _card: PanelContainer = $Center/Card
@onready var _scroll: ScrollContainer = $Center/Card/Scroll
@onready var _title: Label = %Title
@onready var _message: Label = %Message
@onready var _accept: Button = %Accept
@onready var _decline: Button = %Decline


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_title.text = title
	_message.text = message
	_accept.text = accept_button_text
	_decline.text = decline_button_text
	_accept.pressed.connect(_select.bind(IndigaugeTypes.ConsentChoice.ACCEPTED))
	_decline.pressed.connect(_select.bind(IndigaugeTypes.ConsentChoice.DECLINED))
	resized.connect(_fit_card)
	_fit_card()
	_decline.grab_focus()


func _fit_card() -> void:
	_card.custom_minimum_size = Vector2(minf(size.x * 0.95, 500.0), 0.0)
	_scroll.custom_minimum_size.y = maxf(0.0, minf(size.y * 0.9 - 40.0, 300.0))


func _select(choice: IndigaugeTypes.ConsentChoice) -> void:
	if not is_instance_valid(client):
		push_error("[Indigauge] ConsentPanel: client is not set.")
		return
	client.set_consent_choice(choice)


func _unhandled_key_input(_event: InputEvent) -> void:
	get_viewport().set_input_as_handled()
