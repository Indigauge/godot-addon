# Indigauge Godot SDK

The official Godot addon for [Indigauge](https://indigauge.com): production-ready game analytics, structured event logging, session tracking, and in-game player feedback for Godot 4.

Indigauge is designed for teams that want useful telemetry without building and maintaining their own ingestion pipeline. Add the addon, start a session, emit meaningful events, and collect player feedback directly from the game.

## What You Get

- **Fast integration:** one node, one startup call, and simple event helpers
- **Production defaults:** automatic DEV/LIVE mode selection, batching, heartbeats, queue limits, and durable player IDs
- **Session metadata:** maintain a JSON dictionary that syncs to the active Indigauge session when it changes
- **Player feedback:** built-in F2 feedback panel with optional screenshot upload
- **Godot-native workflow:** configure from the Inspector, use as a scene node, or register as an autoload
- **Low ceremony API:** `ig_info`, `ig_warn`, `ig_error`, `show_feedback_panel`, and `submit_feedback`

---

## Requirements

- Godot 4.x
- An Indigauge project public key

Use `Mode.AUTO` during development and production. It resolves to `DEV` while running from the Godot editor or a debug export, and `LIVE` in release exports.

---

## Installation

Copy the addon into your project:

```text
your_project/
└── addons/
    └── indigauge/
        ├── plugin.cfg
        ├── client.gd
        ├── core.gd
        ├── types.gd
        ├── feedback_panel.gd
        └── feedback_panel.tscn
```

Then enable it in Godot:

1. Open **Project > Project Settings > Plugins**.
2. Enable **Indigauge**.
3. Add an `IndigaugeClient` node to your main scene, or add `addons/indigauge/client.gd` as an autoload named `Indigauge`.

Use the autoload name `Indigauge` rather than `IndigaugeClient` so it does not collide with the `IndigaugeClient` script type.

---

## Quick Start

### Scene Node Setup

Add a Node to your main scene, attach `res://addons/indigauge/client.gd`, then start Indigauge from your scene script:

```gdscript
@onready var _indigauge: IndigaugeClient = $IndigaugeClient

func _ready() -> void:
	_indigauge.session_started.connect(_on_indigauge_session_started)
	_indigauge.session_failed.connect(_on_indigauge_session_failed)

	_indigauge.start("YOUR_PUBLIC_KEY", "My Game", "1.0.0")

func _on_indigauge_session_started(_token: String) -> void:
	print("Indigauge session started")

func _on_indigauge_session_failed(_code: int, message: String) -> void:
	push_warning("Indigauge session failed: " + message)
```

### Autoload Setup

If you prefer global access, register `client.gd` as an autoload named `Indigauge`:

```gdscript
func _ready() -> void:
	Indigauge.start("YOUR_PUBLIC_KEY", "My Game", "1.0.0")
```

### Inspector Setup

For a no-code startup path:

1. Select the `IndigaugeClient` node.
2. Set `public_key`, `game_name`, and `game_version` in the Inspector.
3. Leave `mode` as `AUTO`.
4. Enable `auto_start_session`.

---

## Runtime Modes

| Mode | Behavior | Use case |
|---|---|---|
| `AUTO` | Resolves to `DEV` in the editor/debug exports and `LIVE` in release exports | Recommended default |
| `DEV` | Logs locally and does not send analytics to the API | Local development and test scenes |
| `LIVE` | Sends sessions, events, heartbeats, and feedback to Indigauge | Production and live QA |
| `DISABLED` | Skips all telemetry work | Privacy toggles, internal builds, or opt-out states |

To force live telemetry while running from the editor:

```gdscript
_indigauge.mode = IndigaugeTypes.Mode.LIVE
_indigauge.start("YOUR_PUBLIC_KEY", "My Game", "1.0.0")
```

---

## Event Logging

Events use a strict `namespace.action` format, such as `player.jump`, `level.complete`, or `store.purchase`.

```gdscript
_indigauge.ig_info("player.jump")
_indigauge.ig_warn("network.retry", {"attempt": 2})
_indigauge.ig_error("save.failed", {"reason": "disk_full"})
_indigauge.ig_debug("ui.opened", {"screen": "settings"})
_indigauge.ig_trace("physics.collision")
```

Events are queued in memory and flushed automatically. In `DEV` mode, batches are reported in the Godot Output panel instead of being sent to the API.

Recommended event naming:

- Use lowercase names.
- Use exactly one dot: `domain.action`.
- Keep events stable across releases.
- Put dynamic values in metadata, not in the event name.

---

## Session Metadata

Session metadata is a JSON dictionary attached to the current session. Use it for state that describes the play session as a whole, such as selected character, region, difficulty, matchmaking mode, or experiment assignments.

```gdscript
_indigauge.set_session_metadata({
	"difficulty": "hard",
	"region": "eu",
})

_indigauge.set_session_metadata_value("character", "ranger")
_indigauge.update_session_metadata({"partySize": 3, "matchmaking": "ranked"})
_indigauge.remove_session_metadata_value("region")
```

Changes are queued automatically. Once a session is active, the addon sends the latest dictionary to `PATCH /v1/sessions` on the next flush tick, or immediately when possible. In `DEV` mode the update is logged locally.

---

## Player Feedback

The addon includes a ready-to-use feedback panel. By default, players can press **F2** to open or close it.

```gdscript
_indigauge.show_feedback_panel()
_indigauge.toggle_feedback_panel()
```

The panel supports:

- Category selection
- Optional question/context field
- Message validation
- Optional screenshot upload
- Escape-to-close
- Automatic placement in a high-priority `CanvasLayer`

You can also submit feedback directly:

```gdscript
_indigauge.submit_feedback("The jump timing feels inconsistent.", "bug")
_indigauge.submit_feedback("Please add more controller settings.", "suggestion", "", true)
```

The fourth argument controls screenshot upload.

---

## Configuration Reference

Set these properties before calling `start(...)`, or configure them in the Inspector.

| Property | Type | Default | Description |
|---|---|---|---|
| `public_key` | `String` | `""` | Indigauge project public key |
| `game_name` | `String` | Project name | Game name sent with session startup |
| `game_version` | `String` | `1.0.0` | Game/client version sent with session startup |
| `api_base` | `String` | Indigauge ingest API | Override for custom environments |
| `mode` | `IndigaugeTypes.Mode` | `AUTO` | Runtime telemetry mode |
| `log_level` | `IndigaugeTypes.LogLevel` | `INFO` | Minimum SDK log level |
| `auto_start_session` | `bool` | `false` | Starts a session when the node enters the scene tree |
| `feedback_hotkey_enabled` | `bool` | `true` | Enables the feedback panel hotkey |
| `feedback_key` | `int` | `KEY_F2` | Key used to toggle the feedback panel |
| `feedback_canvas_layer` | `int` | `128` | Canvas layer used by the feedback overlay |

After `setup(...)` or `start(...)`, advanced batching settings are available on `client.config`:

| Property | Default | Description |
|---|---|---|
| `batch_size` | `64` | Maximum events sent per batch |
| `flush_interval_sec` | `10.0` | Event flush and heartbeat interval in seconds |
| `max_queue` | `10000` | Maximum queued events before new events are dropped |
| `request_timeout_sec` | `10.0` | HTTP request timeout setting reserved for API requests |

---

## API Reference

### Startup

```gdscript
_indigauge.start(public_key, game_name, game_version, api_base = "")
_indigauge.setup(public_key, game_name, game_version, api_base = "", start_now = false)
_indigauge.start_session()
```

Use `start(...)` for normal integrations. Use `setup(...); start_session()` when you need to modify `client.config` before the first session request.

### Events

```gdscript
_indigauge.ig_trace(event_type, metadata = {})
_indigauge.ig_debug(event_type, metadata = {})
_indigauge.ig_info(event_type, metadata = {})
_indigauge.ig_warn(event_type, metadata = {})
_indigauge.ig_error(event_type, metadata = {})
```

### Session Metadata

```gdscript
_indigauge.set_session_metadata(metadata)
_indigauge.update_session_metadata(metadata)
_indigauge.set_session_metadata_value(key, value)
_indigauge.remove_session_metadata_value(key)
_indigauge.get_session_metadata()
_indigauge.flush_session_metadata()
```

### Feedback

```gdscript
_indigauge.show_feedback_panel(parent = null)
_indigauge.hide_feedback_panel()
_indigauge.toggle_feedback_panel(parent = null)
_indigauge.submit_feedback(message, category, question = "", include_screenshot = false)
```

### Signals

| Signal | Arguments | Description |
|---|---|---|
| `session_started` | `session_token: String` | Emitted when a session is ready |
| `session_failed` | `http_code: int, error_message: String` | Emitted when session startup fails |
| `feedback_sent` | `feedback_id: String` | Emitted after feedback is accepted, or immediately in `DEV` mode |

---

## Example Project

An importable Godot example lives in `godot-addon/example/`.

1. Open Godot.
2. Choose **Import** and select `godot-addon/example/project.godot`.
3. Press **F5**.
4. Play the Breakout example with **A/D**, **Left/Right**, **Space**, or the mouse.
5. Watch the Godot Output panel in DEV mode as gameplay logs events such as `game.start`, `ball.launch`, `brick.hit`, `life.lost`, `level.clear`, and `game.over`.
6. Press **F2** or click **Feedback** to test the in-game feedback panel.

The example uses `Mode.AUTO`, so it runs locally as `DEV` from the editor. Replace `YOUR_PUBLIC_KEY` with your real public key before creating a release export.

---

## Production Checklist

- Set a real `public_key`.
- Use a stable `game_name`.
- Set `game_version` from your release/versioning pipeline.
- Leave `mode` as `AUTO` unless you need to force `LIVE`, `DEV`, or `DISABLED`.
- Verify that release exports include the addon files under `addons/indigauge/`.
- Test the feedback panel with the same input map and UI layers used in production.

---

## Troubleshooting

**No data appears in Indigauge**

- Confirm the build is running in `LIVE` mode. `AUTO` resolves to `DEV` in the editor and debug exports.
- Confirm `public_key` is set before `start(...)`.
- Listen to `session_failed` and log the returned message.

**Events are not sent**

- Events are only queued after a session starts.
- Event names must use the `namespace.action` format.
- In `DEV` mode, events are printed/logged locally instead of being sent.

**F2 does not open the feedback panel**

- Confirm `feedback_hotkey_enabled` is `true`.
- Confirm another script is not consuming F2 before the client receives input.
- Call `_indigauge.show_feedback_panel()` directly to verify the panel scene loads.

**The feedback panel appears behind other UI**

- Increase `feedback_canvas_layer`.
- Or pass your own parent to `show_feedback_panel(parent)`.

---

## License

See [LICENSE](LICENSE).
