# Indigauge Godot Addon

A GDScript addon for [Indigauge](https://indigauge.com) - game analytics, event logging, and in-game feedback collection.

## Requirements

- Godot 4.x
- An Indigauge account and public key (sign up at [indigauge.com](https://indigauge.com))

---

## Installation

1. Copy the addon files into your project under `addons/indigauge/`:

   ```
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

2. Open your project in Godot, go to **Project > Project Settings > Plugins**, and enable **Indigauge**.

3. Add an `IndigaugeClient` node to your main scene, or add `client.gd` as an autoload named `Indigauge`.
   You can configure the public key, game name, version, mode, and automatic startup in the Inspector.

---

## Quick Start

### 1. Set up the client

The shortest setup is one call from any script with a reference to the `IndigaugeClient` node:

```gdscript
@onready var _client: IndigaugeClient = $IndigaugeClient

func _ready() -> void:
    # Use Mode.DEV during development - no API key needed, all output goes to the console.
    _client.mode = IndigaugeTypes.Mode.DEV

    # Switch to Mode.LIVE with your real public key when you are ready to ship.
    # _client.mode = IndigaugeTypes.Mode.LIVE

    _client.session_started.connect(_on_session_started)
    _client.session_failed.connect(_on_session_failed)

    _client.start("YOUR_PUBLIC_KEY", "MyGame", "1.0.0")

func _on_session_started(token: String) -> void:
    print("Session started: ", token)

func _on_session_failed(_code: int, message: String) -> void:
    print("Session failed: ", message)
```

If you prefer the original explicit flow, `setup(...); start_session()` still works. You can also configure the exported fields in the Inspector and enable `auto_start_session` for a no-code startup path. When using an autoload, name the singleton `Indigauge` so it does not collide with the `IndigaugeClient` script type.

### 2. Log events

Event types must be two lowercase words separated by a single dot (e.g. `"player.died"`, `"level.completed"`).

```gdscript
# Log with different severity levels
_client.ig_info("player.jumped")
_client.ig_warn("enemy.escaped", {"enemy_id": "enemy_01"})
_client.ig_error("save.failed", {"reason": "disk_full"})
_client.ig_debug("ui.menu_opened")
_client.ig_trace("physics.collision")
```

Events are batched and flushed automatically every 10 seconds (configurable).

### 3. Collect player feedback

Press **F2** to toggle the built-in feedback panel. You can also open it from code or call `submit_feedback` directly:

```gdscript
_client.show_feedback_panel()
_client.toggle_feedback_panel()

# Or submit feedback directly without the UI:
_client.submit_feedback("The jump feels off", "bug", "", false)
_client.submit_feedback("Add a dash move", "suggestion", "", true)  # true = include screenshot
```

---

## Configuration

Set these properties on `IndigaugeClient` before calling `start(...)` or `start_session()`:

| Property | Type | Default | Description |
|---|---|---|---|
| `mode` | `IndigaugeTypes.Mode` | `LIVE` | `LIVE`, `DEV` (logs to console only), or `DISABLED` |
| `log_level` | `IndigaugeTypes.LogLevel` | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR`, or `SILENT` |
| `auto_start_session` | `bool` | `false` | Starts a session automatically from exported settings when the node enters the scene |
| `feedback_hotkey_enabled` | `bool` | `true` | Enables the feedback panel hotkey |
| `feedback_key` | `int` | `KEY_F2` | Key used to toggle the feedback panel |
| `feedback_canvas_layer` | `int` | `128` | Canvas layer used by the default feedback panel overlay |

The `IndigaugeConfig` object (available as `client.config` after `setup()`) exposes:

| Property | Default | Description |
|---|---|---|
| `batch_size` | `64` | Maximum events per HTTP batch |
| `flush_interval_sec` | `10.0` | How often to flush the event queue (seconds) |
| `max_queue` | `10000` | Maximum events held in memory before dropping |

---

## Signals

| Signal | Arguments | Description |
|---|---|---|
| `session_started` | `session_token: String` | Emitted when the session is established |
| `session_failed` | `http_code: int, error_message: String` | Emitted when session start fails |
| `feedback_sent` | `feedback_id: String` | Emitted after feedback is accepted by the server, or immediately in DEV mode |

---

## Example Project

An immediately runnable example project lives in the `example/` directory.

1. Open Godot and choose **Import** → navigate to `example/project.godot`.
2. Press **F5** (Run) - no API key is needed as it runs in `DEV` mode.
3. Click **Log Events** to see events printed to the Output panel.
4. Press **F2** or click **Open Feedback Panel** to try the built-in feedback UI.

To test with a real Indigauge account, open `example/main.gd`, change:

```gdscript
_client.mode = IndigaugeTypes.Mode.DEV
_client.start("YOUR_PUBLIC_KEY", "ExampleGame", "1.0.0")
```

to:

```gdscript
_client.mode = IndigaugeTypes.Mode.LIVE
_client.start("your-real-public-key", "ExampleGame", "1.0.0")
```

---

## License

See [LICENSE](LICENSE).
