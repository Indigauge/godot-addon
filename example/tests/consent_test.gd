extends SceneTree

const CONSENT = IndigaugeTypes.ConsentChoice

var _failures := 0
var _preference_path := (
	"user://consent_test_%s.txt" % Crypto.new().generate_random_bytes(16).hex_encode()
)
var _server := TCPServer.new()
var _connections: Array[Dictionary] = []
var _requests: Array[Dictionary] = []
var _hold_responses := false


class TestClient:
	extends IndigaugeClient
	var preference_path: String

	func _consent_file_path() -> String:
		return preference_path


func _initialize() -> void:
	_run.call_deferred()


func _process(_delta: float) -> bool:
	while _server.is_connection_available():
		_connections.append({"peer": _server.take_connection(), "data": "", "recorded": false})
	for connection in _connections:
		var peer: StreamPeerTCP = connection.peer
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		var count := peer.get_available_bytes()
		if count > 0:
			connection.data += peer.get_utf8_string(count)
		if connection.recorded:
			continue
		var data: String = connection.data
		var header_end := data.find("\r\n\r\n")
		if header_end == -1:
			continue
		var length := 0
		for line in data.substr(0, header_end).split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				length = int(line.split(":")[1].strip_edges())
		if data.length() < header_end + 4 + length:
			continue
		var path := data.split(" ")[1]
		_requests.append({"path": path, "body": JSON.parse_string(data.substr(header_end + 4))})
		connection.recorded = true
		if not _hold_responses:
			var body := '{"sessionToken":"test-session"}' if path.ends_with("/start") else "{}"
			if path.ends_with("/feedback"):
				body = '{"id":"test-feedback"}'
			peer.put_data(
				(
					(
						"HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
						+ (
							"Content-Length: %d\r\nConnection: close\r\n\r\n%s"
							% [body.length(), body]
						)
					)
					. to_utf8_buffer()
				)
			)
	return false


func _client(mode_value: int = IndigaugeTypes.Mode.DEV) -> TestClient:
	var client := TestClient.new()
	client.preference_path = _preference_path
	client.persist_consent_choice = false
	client.mode = mode_value
	root.add_child(client)
	return client


func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		printerr("FAIL: ", description)


func _wait_until(predicate: Callable, description: String) -> void:
	for i in range(200):
		if predicate.call():
			return
		await create_timer(0.01).timeout
	_check(false, description)


func _run() -> void:
	await _test_modal_and_gates()
	await _test_startup_paths()
	await _test_persistence()
	await _test_live_requests()
	_server.stop()
	for connection in _connections:
		connection.peer.disconnect_from_host()
	if FileAccess.file_exists(_preference_path):
		DirAccess.remove_absolute(_preference_path)
	print("Consent tests: %d failure(s)" % _failures)
	quit(0 if _failures == 0 else 1)


func _test_modal_and_gates() -> void:
	var client := _client()
	var choices: Array[int] = []
	client.consent_selected.connect(func(choice: int) -> void: choices.append(choice))
	client.start()
	await process_frame
	_check(client.consent_choice == CONSENT.UNKNOWN, "consent defaults to unknown")
	_check(client._session_token == "", "unknown consent blocks DEV session")
	_check(client._consent_panel != null, "startup shows a consent modal")
	_check(client.show_consent_panel() == client._consent_panel, "modal is a singleton")
	_check(client.show_feedback_panel() == null, "feedback cannot cover consent")
	var panel := client._consent_panel
	_check(panel.get_node("%Title").text == "Share anonymous gameplay data?", "Bevy default title")
	_check(panel.get_node("%Accept").text == "Allow", "Bevy default allow label")
	_check(
		panel.get_node("%Accept").find_next_valid_focus() == panel.get_node("%Decline"),
		"keyboard focus cycles inside the consent modal"
	)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	Input.parse_input_event(escape)
	await process_frame
	_check(is_instance_valid(panel), "Escape does not select or dismiss consent")
	_check(client.consent_choice == CONSENT.UNKNOWN, "Escape never grants consent")
	await _test_modal_layout(panel)
	panel.get_node("%Accept").pressed.emit()
	_check(client._session_token == "dev", "acceptance resumes requested DEV session")
	_check(choices == [CONSENT.ACCEPTED], "acceptance emits selected signal")
	client.ig_info("player.jump")
	_check(client._queue.size() == 1, "accepted consent permits event queue")
	client.set_session_metadata_value("difficulty", "hard")
	client.set_consent_choice(CONSENT.DECLINED)
	_check(client._session_token == "", "revocation clears credentials")
	_check(client._queue.is_empty(), "revocation discards queued events")
	_check(client.get_session_metadata().is_empty(), "revocation discards metadata")
	_check(not client._session_metadata_dirty, "revocation clears metadata retry")
	client.ig_info("player.jump")
	_check(client._queue.is_empty(), "declined consent drops new events")
	client.start_session()
	_check(client._session_token == "", "decline blocks explicit session starts")
	_check(client.show_consent_panel() == null, "known choice suppresses the modal")
	client.set_consent_choice(CONSENT.UNKNOWN)
	client.consent_modal_enabled = false
	client.start_session()
	_check(client._consent_panel == null, "custom UI option suppresses built-in modal")
	_check(client._session_token == "", "custom UI option cannot bypass consent")
	client.set_consent_choice(CONSENT.ACCEPTED)
	_check(client._session_token == "dev", "custom consent resumes pending startup")
	client.mode = IndigaugeTypes.Mode.DISABLED
	client.ig_info("player.jump")
	_check(client._queue.is_empty(), "DISABLED mode blocks new events")
	client.free()
	client = _client()
	client.start()
	panel = client._consent_panel
	panel.get_node("%Decline").pressed.emit()
	_check(client.consent_choice == CONSENT.DECLINED, "decline button selects opt-out")
	_check(client._session_token == "", "decline button never starts telemetry")
	client.free()
	await process_frame
	client = _client(IndigaugeTypes.Mode.DISABLED)
	client.start()
	_check(client._consent_panel == null, "DISABLED startup does not show a modal")
	client.free()


func _test_modal_layout(panel: Control) -> void:
	for viewport_size in [Vector2i(320, 240), Vector2i(960, 680)]:
		root.size = viewport_size
		await process_frame
		await process_frame
		var card: Control = panel.get_node("Center/Card")
		var bounds := card.get_global_rect()
		_check(bounds.position.x >= 0 and bounds.position.y >= 0, "modal stays inside viewport")
		_check(bounds.end.x <= root.size.x and bounds.end.y <= root.size.y, "modal fits viewport")
		var scroll: ScrollContainer = card.get_node("Scroll")
		scroll.ensure_control_visible(panel.get_node("%Accept"))
		await process_frame
		_check(
			scroll.get_global_rect().intersects(panel.get_node("%Accept").get_global_rect()),
			"allow button is reachable on small screens"
		)
	var screenshot_path := OS.get_environment("INDIGAUGE_CONSENT_SCREENSHOT")
	if screenshot_path != "" and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(
			root.get_texture().get_image().save_png(screenshot_path) == OK, "modal screenshot saves"
		)


func _test_persistence() -> void:
	var client := _client()
	client.persist_consent_choice = true
	client.set_consent_choice(CONSENT.ACCEPTED)
	_check(FileAccess.get_file_as_string(_preference_path) == "accepted", "acceptance persists")
	client.free()
	client = _client()
	client.persist_consent_choice = true
	client.start()
	_check(client.consent_choice == CONSENT.ACCEPTED, "accepted choice restores")
	_check(client._session_token == "dev", "restored acceptance permits startup")
	client.set_consent_choice(CONSENT.DECLINED)
	client.free()
	client = _client()
	client.persist_consent_choice = true
	client.start()
	_check(client.consent_choice == CONSENT.DECLINED, "declined choice restores")
	_check(client._session_token == "", "restored decline blocks startup")
	_check(client._consent_panel == null, "restored decline suppresses modal")
	client.set_consent_choice(CONSENT.UNKNOWN)
	_check(not FileAccess.file_exists(_preference_path), "reset removes saved choice")
	client.free()
	var file := FileAccess.open(_preference_path, FileAccess.WRITE)
	file.store_string("invalid")
	file.close()
	client = _client()
	client.persist_consent_choice = true
	client.setup()
	_check(client.consent_choice == CONSENT.UNKNOWN, "invalid saved choice fails closed")
	client.free()
	file = FileAccess.open(_preference_path, FileAccess.WRITE)
	file.store_string("accepted")
	file.close()
	client = _client()
	client.setup()
	_check(client.consent_choice == CONSENT.UNKNOWN, "disabled persistence does not load")
	client.set_consent_choice(CONSENT.DECLINED)
	_check(
		FileAccess.get_file_as_string(_preference_path) == "accepted",
		"disabled persistence does not overwrite saved choice"
	)
	client.free()


func _test_startup_paths() -> void:
	for startup in ["start_session", "setup", "configure_and_start", "auto"]:
		var client := TestClient.new()
		client.preference_path = _preference_path
		client.persist_consent_choice = false
		client.mode = IndigaugeTypes.Mode.DEV
		client.auto_start_session = startup == "auto"
		root.add_child(client)
		match startup:
			"start_session":
				client.start_session()
			"setup":
				client.setup("", "", "", "", true)
			"configure_and_start":
				client.configure_and_start()
		_check(client._session_token == "", "%s cannot bypass consent" % startup)
		_check(client._consent_panel != null, "%s presents consent" % startup)
		client.set_consent_choice(CONSENT.ACCEPTED)
		_check(client._session_token == "dev", "%s resumes after acceptance" % startup)
		client.free()
		await process_frame


func _test_live_requests() -> void:
	var error := _server.listen(0, "127.0.0.1")
	_check(error == OK, "mock server starts")
	if error != OK:
		return
	var client := _client(IndigaugeTypes.Mode.LIVE)
	client.consent_modal_enabled = false
	client.start(
		"test-key", "Consent Test", "1.0", "http://127.0.0.1:%d" % _server.get_local_port()
	)
	client.ig_info("player.jump")
	client.send_heartbeat()
	client.submit_feedback("test feedback", "general")
	client.flush_session_metadata()
	client.flush_events()
	await create_timer(0.05).timeout
	_check(_requests.is_empty(), "unknown consent sends zero HTTP requests")
	client.set_consent_choice(CONSENT.ACCEPTED)
	await _wait_until(func() -> bool: return client._session_token != "", "LIVE session starts")
	_check(_requests.size() == 1, "acceptance starts exactly one request")
	if _requests.is_empty():
		client.free()
		return
	_check(
		_requests[0].body == {"clientVersion": "1.0", "sdkVersion": "godot-gdscript:0.1.0"},
		"startup omits all automatic player and hardware identifiers"
	)
	client.set_session_metadata_value("difficulty", "hard")
	await _wait_until(
		func() -> bool: return not client._session_metadata_request_in_flight, "metadata completes"
	)
	_check(_requests[-1].path == "/v1/sessions", "accepted metadata reaches API")
	client.ig_info("player.jump")
	_check(client.flush_events() == 1, "accepted event flush succeeds")
	await _wait_until(func() -> bool: return _requests.size() == 3, "event batch reaches API")
	await create_timer(0.05).timeout
	client.send_heartbeat()
	await _wait_until(func() -> bool: return _requests.size() == 4, "heartbeat reaches API")
	await create_timer(0.05).timeout
	var feedback_ids: Array[String] = []
	client.feedback_sent.connect(func(id: String) -> void: feedback_ids.append(id))
	client.submit_feedback("test feedback", "general")
	await _wait_until(func() -> bool: return not feedback_ids.is_empty(), "feedback completes")
	_check(feedback_ids == ["test-feedback"], "accepted feedback reaches API")
	client.set_consent_choice(CONSENT.DECLINED)
	var request_count := _requests.size()
	client.send_heartbeat()
	client.submit_feedback("test feedback", "general")
	client.ig_info("player.jump")
	client.set_session_metadata_value("blocked", true)
	client._tick()
	await create_timer(0.05).timeout
	_check(_requests.size() == request_count, "revocation blocks every HTTP surface")
	client.set_consent_choice(CONSENT.ACCEPTED)
	_hold_responses = true
	client.start_session()
	await _wait_until(
		func() -> bool: return _requests.size() > request_count, "delayed startup reaches API"
	)
	_check(client._session_start_in_flight, "session request is pending")
	client.set_consent_choice(CONSENT.DECLINED)
	_check(not client._session_start_in_flight, "revocation cancels pending startup")
	_check(
		not client._http.request_completed.is_connected(client._on_start_session_completed),
		"revocation disconnects pending startup callback"
	)
	client._on_start_session_completed(
		HTTPRequest.RESULT_SUCCESS,
		200,
		PackedStringArray(),
		'{"sessionToken":"late"}'.to_utf8_buffer()
	)
	_check(client._session_token == "", "late response cannot restore revoked credentials")
	client.free()
