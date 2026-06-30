# gdlint: disable=max-public-methods
class_name IndigaugeClient
extends Node

signal session_started(session_token: String)
signal session_failed(http_code: int, error_message: String)
signal feedback_sent(feedback_id: String)

const FeedbackPanelScene := preload("res://addons/indigauge/feedback_panel.tscn")

@export var public_key: String = ""
@export var game_name: String = ""
@export var game_version: String = ""
@export var api_base: String = ""
@export var auto_start_session: bool = false
@export var feedback_hotkey_enabled: bool = true
@export var feedback_key: int = KEY_F2
@export var feedback_canvas_layer: int = 128
@export_enum("LIVE", "DEV", "DISABLED", "AUTO") var mode: int = IndigaugeTypes.Mode.AUTO
@export_enum("DEBUG", "INFO", "WARN", "ERROR", "SILENT")
var log_level: int = IndigaugeTypes.LogLevel.INFO

var config: IndigaugeTypes.IndigaugeConfig

var _http: HTTPRequest
var _metadata_http: HTTPRequest
var _flush_timer: Timer
var _feedback_layer: CanvasLayer
var _feedback_panel: Control

var _session_token: String = ""
var _session_start_ms: int = 0
var _queue: Array[IndigaugeTypes.EventPayload] = []
var _player_id: String = ""
var _session_metadata: Dictionary = {}
var _session_metadata_dirty: bool = false
var _session_metadata_request_in_flight: bool = false


func _ready() -> void:
	_ensure_runtime_nodes()

	IndigaugeCore.set_event_dispatcher(Callable(self, "_dispatch_from_core"))

	if auto_start_session:
		setup()
		start_session()


func _ensure_runtime_nodes() -> void:
	if not is_in_group("indigauge_clients"):
		add_to_group("indigauge_clients")
	set_process_input(true)

	if _http == null:
		_http = HTTPRequest.new()
		add_child(_http)

	if _metadata_http == null:
		_metadata_http = HTTPRequest.new()
		add_child(_metadata_http)

	if _flush_timer == null:
		_flush_timer = Timer.new()
		_flush_timer.one_shot = false
		add_child(_flush_timer)
		_flush_timer.timeout.connect(_tick)


func _input(event: InputEvent) -> void:
	if not feedback_hotkey_enabled:
		return
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == feedback_key
	):
		toggle_feedback_panel()
		get_viewport().set_input_as_handled()


func setup(
	_public_key: String = "",
	_game_name: String = "",
	_game_version: String = "",
	_api_base: String = "",
	start_now: bool = false
) -> void:
	_ensure_runtime_nodes()

	if _public_key != "":
		public_key = _public_key
	if _game_name != "":
		game_name = _game_name
	if _game_version != "":
		game_version = _game_version
	if _api_base != "":
		api_base = _api_base

	var resolved_game_name := _resolve_game_name()
	var resolved_game_version := _resolve_game_version()

	config = IndigaugeTypes.IndigaugeConfig.new(
		resolved_game_name, public_key, resolved_game_version, api_base
	)
	_flush_timer.wait_time = config.flush_interval_sec
	_flush_timer.start()
	_player_id = _load_or_create_player_id()

	if start_now:
		start_session()


func start(
	_public_key: String = "",
	_game_name: String = "",
	_game_version: String = "",
	_api_base: String = ""
) -> void:
	setup(_public_key, _game_name, _game_version, _api_base)
	start_session()


func configure_and_start(
	_public_key: String = "",
	_game_name: String = "",
	_game_version: String = "",
	_api_base: String = ""
) -> void:
	start(_public_key, _game_name, _game_version, _api_base)


func start_session() -> void:
	var active_mode := effective_mode()

	if active_mode == IndigaugeTypes.Mode.DISABLED:
		_log_info("Indigauge disabled; skipping session start.")
		return

	if config == null:
		setup()

	_session_start_ms = Time.get_ticks_msec()

	if active_mode == IndigaugeTypes.Mode.DEV:
		_session_token = "dev"
		emit_signal("session_started", _session_token)
		_log_info("DEVMODE: session started.")
		flush_session_metadata()
		return

	if active_mode == IndigaugeTypes.Mode.LIVE and (config == null or not config.has_public_key()):
		_log_warn("No public key set in LIVE mode; cannot start session.")
		emit_signal("session_failed", 0, "missing_public_key")
		return

	var p := IndigaugeTypes.StartSessionPayload.new()
	p.client_version = config.game_version
	p.sdk_version = "godot-gdscript:0.1.0"
	p.player_id = _player_id
	p.platform = OS.get_name()
	p.os = OS.get_name()

	var cpu := OS.get_processor_name()
	var cpu_coarse := IndigaugeCore.coarsen_cpu_name(cpu)
	p.cpu_family = cpu_coarse if cpu_coarse != "" else ""

	p.cores = IndigaugeCore.bucket_cores(OS.get_processor_count())
	p.memory = ""

	var url := config.api_url("sessions/start")
	var headers := [
		"Content-Type: application/json",
		"X-Indigauge-Key: %s" % config.public_key,
	]

	_http.request_completed.connect(_on_start_session_completed, CONNECT_ONE_SHOT)
	_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(p.to_json()))


func _on_start_session_completed(
	_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var text := body.get_string_from_utf8()
	if code < 200 or code >= 300:
		_log_error("Failed to start session (HTTP %d): %s" % [code, text])
		emit_signal("session_failed", code, text)
		return

	var parsed := JSON.parse_string(text)
	var env := IndigaugeTypes.parse_api_response(parsed)
	if not env.ok:
		var err: IndigaugeTypes.ErrorBody = env.error
		_log_error("Failed to start session: %s (%s)" % [err.message, err.code])
		emit_signal("session_failed", code, err.message)
		return

	var resp := IndigaugeTypes.StartSessionResponse.from_dict(env.data)
	if resp.session_token == "":
		_log_error("Start session response missing sessionToken.")
		emit_signal("session_failed", code, "missing_session_token")
		return

	_session_token = resp.session_token
	emit_signal("session_started", _session_token)
	_log_info("Session started.")
	flush_session_metadata()


# ---- Session metadata ----
func set_session_metadata(metadata: Dictionary) -> void:
	var next_metadata := metadata.duplicate(true)
	if _session_metadata == next_metadata:
		return
	_session_metadata = next_metadata
	_mark_session_metadata_dirty()


func update_session_metadata(metadata: Dictionary) -> void:
	var changed := false
	for key in metadata:
		if not _session_metadata.has(key) or _session_metadata[key] != metadata[key]:
			changed = true
		_session_metadata[key] = metadata[key]
	if changed:
		_mark_session_metadata_dirty()


func set_session_metadata_value(key: String, value: Variant) -> void:
	if _session_metadata.has(key) and _session_metadata[key] == value:
		return
	_session_metadata[key] = value
	_mark_session_metadata_dirty()


func remove_session_metadata_value(key: String) -> void:
	if _session_metadata.has(key):
		_session_metadata.erase(key)
		_mark_session_metadata_dirty()


func get_session_metadata() -> Dictionary:
	return _session_metadata.duplicate(true)


func _mark_session_metadata_dirty() -> void:
	_session_metadata_dirty = true
	flush_session_metadata()


func flush_session_metadata() -> bool:
	if _session_token == "" or not _session_metadata_dirty or _session_metadata_request_in_flight:
		return false

	match effective_mode():
		IndigaugeTypes.Mode.DEV:
			_session_metadata_dirty = false
			_log_info("DEVMODE: update session metadata: %s" % JSON.stringify(_session_metadata))
			return true
		IndigaugeTypes.Mode.LIVE:
			var url := config.api_url("sessions")
			var headers := [
				"Content-Type: application/json",
				"X-Indigauge-Key: %s" % _session_token,
			]
			_session_metadata_dirty = false
			_session_metadata_request_in_flight = true
			_metadata_http.request_completed.connect(
				_on_session_metadata_completed, CONNECT_ONE_SHOT
			)
			var request_error := _metadata_http.request(
				url, headers, HTTPClient.METHOD_PATCH, JSON.stringify(_session_metadata)
			)
			if request_error != OK:
				_session_metadata_request_in_flight = false
				_session_metadata_dirty = true
				if _metadata_http.request_completed.is_connected(_on_session_metadata_completed):
					_metadata_http.request_completed.disconnect(_on_session_metadata_completed)
				_log_error("Failed to start session metadata request (error %d)" % request_error)
				return false
			return true
		_:
			return false


func _on_session_metadata_completed(
	_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	_session_metadata_request_in_flight = false
	if code < 200 or code >= 300:
		_session_metadata_dirty = true
		_log_error(
			"Failed to update session metadata (HTTP %d): %s" % [code, body.get_string_from_utf8()]
		)
		return

	_log_info("Session metadata updated.")
	if _session_metadata_dirty:
		flush_session_metadata()


# ---- Feedback panel ----
func show_feedback_panel(parent: Node = null) -> Control:
	if is_instance_valid(_feedback_panel):
		_feedback_panel.grab_focus()
		return _feedback_panel

	var panel: Control = FeedbackPanelScene.instantiate()
	panel.set("client", self)
	_feedback_panel = panel
	_feedback_panel.tree_exited.connect(func() -> void: _feedback_panel = null)

	var target_parent := parent if parent != null else _get_feedback_layer()
	target_parent.add_child(panel)
	return panel


func hide_feedback_panel() -> void:
	if is_instance_valid(_feedback_panel):
		_feedback_panel.queue_free()
	_feedback_panel = null


func toggle_feedback_panel(parent: Node = null) -> void:
	if is_instance_valid(_feedback_panel):
		hide_feedback_panel()
	else:
		show_feedback_panel(parent)


func _get_feedback_layer() -> CanvasLayer:
	if is_instance_valid(_feedback_layer):
		return _feedback_layer
	_feedback_layer = CanvasLayer.new()
	_feedback_layer.name = "IndigaugeFeedbackLayer"
	_feedback_layer.layer = feedback_canvas_layer
	add_child(_feedback_layer)
	return _feedback_layer


# ---- Event logging helpers ----
func ig_trace(event_type: String, metadata: Dictionary = {}) -> void:
	IndigaugeCore.emit("trace", event_type, _meta_or_null(metadata), _ctx())


func ig_debug(event_type: String, metadata: Dictionary = {}) -> void:
	IndigaugeCore.emit("debug", event_type, _meta_or_null(metadata), _ctx())


func ig_info(event_type: String, metadata: Dictionary = {}) -> void:
	IndigaugeCore.emit("info", event_type, _meta_or_null(metadata), _ctx())


func ig_warn(event_type: String, metadata: Dictionary = {}) -> void:
	IndigaugeCore.emit("warn", event_type, _meta_or_null(metadata), _ctx())


func ig_error(event_type: String, metadata: Dictionary = {}) -> void:
	IndigaugeCore.emit("error", event_type, _meta_or_null(metadata), _ctx())


func _dispatch_from_core(
	level: String, event_type: String, metadata: Variant, _ctxdict: Dictionary
) -> bool:
	# Only queue events once a session is established.
	if _session_token == "":
		return false
	if _queue.size() >= config.max_queue:
		return false

	var elapsed := max(0, Time.get_ticks_msec() - _session_start_ms)
	var e := IndigaugeTypes.EventPayload.new()
	e.event_type = event_type
	e.level = level
	e.metadata = metadata
	e.elapsed_ms = elapsed
	e.idempotency_key = _new_id()
	e.context = null

	_queue.append(e)
	return true


# ---- Periodic tick: flush + heartbeat ----
func _tick() -> void:
	var metadata_sent := flush_session_metadata()
	var sent := flush_events()
	if sent == 0 and not metadata_sent:
		send_heartbeat()


func flush_events() -> int:
	if _session_token == "" or _queue.is_empty():
		return 0

	var count := min(_queue.size(), config.batch_size)
	var batch_events: Array = []
	for i in range(count):
		batch_events.append(_queue[i])
	_queue = _queue.slice(count, _queue.size())

	var payload := IndigaugeTypes.BatchEventPayload.new()
	payload.events = batch_events

	match effective_mode():
		IndigaugeTypes.Mode.DEV:
			_log_info("DEVMODE: sending event batch (%d)" % count)
			return count
		IndigaugeTypes.Mode.LIVE:
			var url := config.api_url("events/batch")
			var headers := [
				"Content-Type: application/json",
				"X-Indigauge-Key: %s" % _session_token,
			]
			_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload.to_json()))
			return count
		_:
			return 0


func send_heartbeat() -> void:
	if _session_token == "":
		return

	match effective_mode():
		IndigaugeTypes.Mode.DEV:
			_log_info("DEVMODE: heartbeat")
		IndigaugeTypes.Mode.LIVE:
			var url := config.api_url("sessions/heartbeat")
			var headers := [
				"Content-Type: application/json",
				"X-Indigauge-Key: %s" % _session_token,
			]
			_http.request(url, headers, HTTPClient.METHOD_POST, "{}")
		_:
			pass


func _feedback_category(requested_category: String) -> String:
	var valid_categories := [
		"bugs",
		"general",
		"ui",
		"performance",
		"gameplay",
		"controls",
		"audio",
		"balance",
		"graphics",
		"visual",
		"art",
		"other"
	]
	var cat := requested_category.strip_edges().to_lower()
	if cat == "" or not valid_categories.has(cat):
		return "other"
	return cat


# ---- Feedback (submit + optional screenshot upload) ----
func submit_feedback(
	message: String, category: String, question: String = "", include_screenshot: bool = false
) -> void:
	if _session_token == "":
		_log_warn("Cannot submit feedback before a session has started.")
		return

	var msg := message.strip_edges()
	if msg.length() < 2:
		_log_warn("Feedback cannot be less than 2 characters.")
		return

	var elapsed := max(0, Time.get_ticks_msec() - _session_start_ms)
	var p := IndigaugeTypes.FeedbackPayload.new()
	p.message = msg
	p.category = _feedback_category(category)
	p.elapsed_ms = elapsed
	p.question = question

	match effective_mode():
		IndigaugeTypes.Mode.DEV:
			_log_info("DEVMODE: feedback: %s" % JSON.stringify(p.to_json()))
			emit_signal("feedback_sent", "dev-%s" % _new_id())
			return
		IndigaugeTypes.Mode.LIVE:
			var url := config.api_url("feedback")
			_http.request_completed.connect(_on_feedback_completed, CONNECT_ONE_SHOT)
			var request_error := OK
			var headers := []

			if include_screenshot:
				var png := _capture_screenshot_png()
				if png.is_empty():
					_log_warn(
						"Feedback screenshot was requested, but no screenshot could be captured."
					)
					_http.request_completed.disconnect(_on_feedback_completed)
					return

				var boundary := _multipart_boundary()
				headers = [
					"Content-Type: multipart/form-data; boundary=%s" % boundary,
					"X-Indigauge-Key: %s" % _session_token,
				]
				var body := _build_feedback_multipart_body(p, png, boundary)
				request_error = _http.request_raw(url, headers, HTTPClient.METHOD_POST, body)
			else:
				headers = [
					"Content-Type: application/json",
					"X-Indigauge-Key: %s" % _session_token,
				]
				request_error = _http.request(
					url, headers, HTTPClient.METHOD_POST, JSON.stringify(p.to_json())
				)

			if request_error != OK:
				if _http.request_completed.is_connected(_on_feedback_completed):
					_http.request_completed.disconnect(_on_feedback_completed)
				_log_error("Failed to start feedback request (error %d)" % request_error)
		_:
			pass


func _on_feedback_completed(
	_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	if code < 200 or code >= 300:
		_log_error("Failed to send feedback (HTTP %d): %s" % [code, body.get_string_from_utf8()])
		return

	var parsed := JSON.parse_string(body.get_string_from_utf8())
	var env := IndigaugeTypes.parse_api_response(parsed)
	if not env.ok:
		var err: IndigaugeTypes.ErrorBody = env.error
		_log_error("Feedback error: %s (%s)" % [err.message, err.code])
		return

	var idr := IndigaugeTypes.IdResponse.from_dict(env.data)
	if idr.id == "":
		_log_warn("Feedback response missing id.")
		return

	emit_signal("feedback_sent", idr.id)


func _capture_screenshot_png() -> PackedByteArray:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_log_warn("No screenshot image available.")
		return PackedByteArray()
	var png: PackedByteArray = img.save_png_to_buffer()
	if png.is_empty():
		_log_warn("Failed to encode screenshot PNG.")
	return png


func _multipart_boundary() -> String:
	return "----IndigaugeGodot%s" % _new_id().replace("-", "")


func _build_feedback_multipart_body(
	payload, png: PackedByteArray, boundary: String
) -> PackedByteArray:
	var body := PackedByteArray()
	_append_multipart_text(body, boundary, "message", payload.message)
	_append_multipart_text(body, boundary, "elapsedMs", str(payload.elapsed_ms))
	_append_multipart_text(body, boundary, "category", payload.category)
	if payload.question != "":
		_append_multipart_text(body, boundary, "question", payload.question)
	_append_multipart_file(body, boundary, "screenshot", "screenshot.png", "image/png", png)
	body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return body


func _append_multipart_text(
	body: PackedByteArray, boundary: String, field_name: String, value: String
) -> void:
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(
		('Content-Disposition: form-data; name="%s"\r\n\r\n' % field_name).to_utf8_buffer()
	)
	body.append_array(value.to_utf8_buffer())
	body.append_array("\r\n".to_utf8_buffer())


func _append_multipart_file(
	body: PackedByteArray,
	boundary: String,
	field_name: String,
	filename: String,
	content_type: String,
	file_bytes: PackedByteArray
) -> void:
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array(
		(
			(
				'Content-Disposition: form-data; name="%s"; filename="%s"\r\n'
				% [field_name, filename]
			)
			. to_utf8_buffer()
		)
	)
	body.append_array(("Content-Type: %s\r\n\r\n" % content_type).to_utf8_buffer())
	body.append_array(file_bytes)
	body.append_array("\r\n".to_utf8_buffer())


# ---- helpers ----
func _meta_or_null(d: Dictionary) -> Variant:
	return null if d.is_empty() else d


func _ctx() -> Dictionary:
	return {}


func effective_mode() -> int:
	if mode != IndigaugeTypes.Mode.AUTO:
		return mode
	if OS.has_feature("editor") or OS.has_feature("debug"):
		return IndigaugeTypes.Mode.DEV
	return IndigaugeTypes.Mode.LIVE


func _new_id() -> String:
	# good-enough idempotency key for client-side batching
	return "%s-%s" % [str(Time.get_unix_time_from_system()), str(randi())]


func _load_or_create_player_id() -> String:
	var path := "user://indigauge_player_id.txt"
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		var s := f.get_as_text().strip_edges()
		if s != "":
			return s
	var new_id := _new_id()
	var wf := FileAccess.open(path, FileAccess.WRITE)
	wf.store_string(new_id)
	return new_id


func _resolve_game_name() -> String:
	var configured := game_name.strip_edges()
	if configured != "":
		return configured
	var project_name := (
		str(ProjectSettings.get_setting("application/config/name", "")).strip_edges()
	)
	return project_name if project_name != "" else "GodotGame"


func _resolve_game_version() -> String:
	var configured := game_version.strip_edges()
	if configured != "":
		return configured
	var project_version := (
		str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
	)
	return project_version if project_version != "" else "1.0.0"


func _log_info(s: String) -> void:
	if log_level <= IndigaugeTypes.LogLevel.INFO:
		print("[Indigauge] ", s)


func _log_warn(s: String) -> void:
	if log_level <= IndigaugeTypes.LogLevel.WARN:
		push_warning("[Indigauge] " + s)


func _log_error(s: String) -> void:
	if log_level <= IndigaugeTypes.LogLevel.ERROR:
		push_error("[Indigauge] " + s)
