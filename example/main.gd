extends Node

# ---------------------------------------------------------------------------
# Indigauge Example
#
# Mode.AUTO runs as DEV from the Godot editor and LIVE in release exports.
# ---------------------------------------------------------------------------

@onready var _status_label: Label = $UI/StatusLabel
@onready var _event_button: Button = $UI/EventButton
@onready var _feedback_button: Button = $UI/FeedbackButton
@onready var _client: IndigaugeClient = $IndigaugeClient

func _ready() -> void:
	_client.session_started.connect(_on_session_started)
	_client.session_failed.connect(_on_session_failed)
	_client.feedback_sent.connect(_on_feedback_sent)

	_client.start("YOUR_PUBLIC_KEY", "ExampleGame", "1.0.0")

	_event_button.pressed.connect(_on_event_button_pressed)
	_feedback_button.pressed.connect(_on_feedback_button_pressed)

func _on_session_started(token: String) -> void:
	_status_label.text = "Session started (token: %s)" % token

func _on_session_failed(_code: int, message: String) -> void:
	_status_label.text = "Session failed: %s" % message

func _on_feedback_sent(feedback_id: String) -> void:
	print("Feedback submitted, id: ", feedback_id)

func _on_event_button_pressed() -> void:
	_client.ig_info("player.jumped")
	_client.ig_info("ui.button_clicked", {"button": "EventButton"})
	_status_label.text = "Events logged (check Output panel in DEV mode)"

func _on_feedback_button_pressed() -> void:
	_client.toggle_feedback_panel()
