class_name IndigaugeClient
extends Node

signal session_started(session_token: String)
signal session_failed(http_code: int, error_message: String)
signal feedback_sent(feedback_id: String)

var config: IndigaugeTypes.IndigaugeConfig
var mode: int = IndigaugeTypes.Mode.LIVE
var log_level: int = IndigaugeTypes.LogLevel.INFO

var _http: HTTPRequest
var _flush_timer: Timer

var _session_token: String = ""
var _session_start_ms: int = 0
var _queue: Array[IndigaugeTypes.EventPayload] = []
var _player_id: String = ""

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)

	_flush_timer = Timer.new()
	_flush_timer.one_shot = false
	add_child(_flush_timer)
	_flush_timer.timeout.connect(_tick)

	IndigaugeCore.set_event_dispatcher(Callable(self, "_dispatch_from_core"))

func setup(public_key: String, game_name: String, game_version: String, api_base: String = "") -> void:
	config = IndigaugeTypes.IndigaugeConfig.new(game_name, public_key, game_version, api_base)
	_flush_timer.wait_time = config.flush_interval_sec
	_flush_timer.start()
	_player_id = _load_or_create_player_id()

func start_session() -> void:
	if mode == IndigaugeTypes.Mode.DISABLED:
		_log_info("Indigauge disabled; skipping session start.")
		return

	_session_start_ms = Time.get_ticks_msec()

	if mode == IndigaugeTypes.Mode.DEV:
		_session_token = "dev"
		emit_signal("session_started", _session_token)
		_log_info("DEVMODE: session started.")
		return

	if mode == IndigaugeTypes.Mode.LIVE and (config == null or not config.has_public_key()):
		_log_warn("No public key set in LIVE mode; cannot start session.")
		emit_signal("session_failed", 0, "missing_public_key")
		return

	var p := IndigaugeTypes.StartSessionPayload.new()
	p.client_version = config.game_version
	p.sdk_version = "godot-gdscript"
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

func _on_start_session_completed(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
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

func _dispatch_from_core(level: String, event_type: String, metadata: Variant, _ctxdict: Dictionary) -> bool:
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
	var sent := flush_events()
	if sent == 0:
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

	match mode:
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

	match mode:
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

# ---- Feedback (submit + optional screenshot upload) ----
func submit_feedback(message: String, category: String, question: String = "", include_screenshot: bool = false) -> void:
	if _session_token == "":
		return

	var msg := message.strip_edges()
	if msg.length() < 2:
		_log_warn("Feedback cannot be less than 2 characters.")
		return

	var elapsed := max(0, Time.get_ticks_msec() - _session_start_ms)
	var p := IndigaugeTypes.FeedbackPayload.new()
	p.message = msg
	p.category = category.to_lower()
	p.elapsed_ms = elapsed
	p.question = question

	match mode:
		IndigaugeTypes.Mode.DEV:
			_log_info("DEVMODE: feedback: %s" % JSON.stringify(p.to_json()))
			return
		IndigaugeTypes.Mode.LIVE:
			var url := config.api_url("feedback")
			var headers := [
				"Content-Type: application/json",
				"X-Indigauge-Key: %s" % _session_token,
			]
			_http.request_completed.connect(func(_r:int, code:int, _h:PackedStringArray, body:PackedByteArray) -> void:
				if code < 200 or code >= 300:
					_log_error("Failed to send feedback (HTTP %d)" % code)
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

				if include_screenshot:
					_upload_feedback_screenshot(idr.id)
			, CONNECT_ONE_SHOT)
			_http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(p.to_json()))
		_:
			pass

func _upload_feedback_screenshot(feedback_id: String) -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null:
		_log_warn("No screenshot image available.")
		return
	var png: PackedByteArray = img.save_png_to_buffer()
	if png.is_empty():
		_log_warn("Failed to encode screenshot PNG.")
		return

	var url := config.api_url("feedback/%s/screenshot" % feedback_id)
	var headers := [
		"Content-Type: image/png",
		"X-Indigauge-Key: %s" % _session_token,
	]
	_http.request(url, headers, HTTPClient.METHOD_POST, png)

# ---- helpers ----
func _meta_or_null(d: Dictionary) -> Variant:
	return null if d.is_empty() else d

func _ctx() -> Dictionary:
	return {}

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

func _log_info(s: String) -> void:
	if log_level <= IndigaugeTypes.LogLevel.INFO:
		print("[Indigauge] ", s)

func _log_warn(s: String) -> void:
	if log_level <= IndigaugeTypes.LogLevel.WARN:
		push_warning("[Indigauge] " + s)

func _log_error(s: String) -> void:
	if log_level <= IndigaugeTypes.LogLevel.ERROR:
		push_error("[Indigauge] " + s)
