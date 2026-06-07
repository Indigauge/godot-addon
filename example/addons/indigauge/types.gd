class_name IndigaugeTypes

enum Mode { LIVE, DEV, DISABLED, AUTO }
enum LogLevel { DEBUG, INFO, WARN, ERROR, SILENT }

# ---- API response models ----
class ErrorBody:
	var code: String = ""
	var message: String = ""

	static func from_dict(d: Dictionary) -> ErrorBody:
		var e := ErrorBody.new()
		e.code = str(d.get("code", ""))
		e.message = str(d.get("message", ""))
		return e

class IdResponse:
	var id: String = ""
	static func from_dict(d: Dictionary) -> IdResponse:
		var r := IdResponse.new()
		r.id = str(d.get("id", ""))
		return r

static func parse_api_response(json_value: Variant) -> Dictionary:
	# Server returns either a success object OR { code, message } for errors.
	if typeof(json_value) != TYPE_DICTIONARY:
		return {"ok": false, "error": ErrorBody.from_dict({"code":"invalid_json","message":"Response was not an object"})}
	var d: Dictionary = json_value
	if d.has("code") and d.has("message"):
		return {"ok": false, "error": ErrorBody.from_dict(d)}
	return {"ok": true, "data": d}

# ---- Config ----
class IndigaugeConfig:
	var api_base: String = ""
	var game_name: String = ""
	var public_key: String = ""
	var game_version: String = ""

	var batch_size: int = 64
	var flush_interval_sec: float = 10.0
	var max_queue: int = 10000
	var request_timeout_sec: float = 10.0

	func _init(_game_name: String, _public_key: String, _game_version: String, _api_base: String = "") -> void:
		api_base = _api_base if _api_base != "" else "https://ingest.indigauge.com"
		game_name = _game_name
		public_key = _public_key
		game_version = _game_version

	func has_public_key() -> bool:
		return public_key.strip_edges() != ""

	func api_url(path: String) -> String:
		return "%s/v1/%s" % [api_base, path]

# ---- Session models ----
class StartSessionPayload:
	var client_version: String = ""
	var sdk_version: String = ""
	var player_id: String = ""          # optional
	var platform: String = ""           # optional
	var os: String = ""                 # optional
	var cpu_family: String = ""         # optional
	var cores: String = ""              # optional (bucketed string)
	var memory: String = ""             # optional (bucketed string)
	var gpu: String = ""                # optional

	func to_json() -> Dictionary:
		return {
			"clientVersion": client_version,
			"sdkVersion": sdk_version,
			"playerId": null if player_id == "" else player_id,
			"platform": null if platform == "" else platform,
			"os": null if os == "" else os,
			"cpuFamily": null if cpu_family == "" else cpu_family,
			"cores": null if cores == "" else cores,
			"memory": null if memory == "" else memory,
			"gpu": null if gpu == "" else gpu,
		}

class StartSessionResponse:
	var session_token: String = ""
	static func from_dict(d: Dictionary) -> StartSessionResponse:
		var r := StartSessionResponse.new()
		r.session_token = str(d.get("sessionToken", ""))
		return r

# ---- Event models ----
class EventPayloadCtx:
	var file: String = ""
	var line: int = 0
	var module: String = "" # optional

	func to_json() -> Dictionary:
		return {
			"file": file,
			"line": line,
			"module": null if module == "" else module,
		}

class EventPayload:
	var event_type: String = ""
	var metadata: Variant = null # Dictionary or null
	var level: String = ""       # "info" / "warn" / ...
	var elapsed_ms: int = 0
	var idempotency_key: String = ""
	var context: EventPayloadCtx = null

	func to_json() -> Dictionary:
		var d := {
			"eventType": event_type,
			"metadata": metadata,
			"level": level,
			"elapsedMs": elapsed_ms,
			"idempotencyKey": idempotency_key,
			"context": null if context == null else context.to_json(),
		}
		return d

class BatchEventPayload:
	var events: Array = [] # of EventPayload
	func to_json() -> Dictionary:
		var arr: Array = []
		for e in events:
			arr.append(e.to_json())
		return {"events": arr}

# ---- Feedback models ----
class FeedbackPayload:
	var message: String = ""
	var elapsed_ms: int = 0
	var question: String = ""   # optional
	var category: String = ""   # required

	func to_json() -> Dictionary:
		return {
			"message": message,
			"elapsedMs": elapsed_ms,
			"question": null if question == "" else question,
			"category": category,
		}
