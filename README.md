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

3. Add an `IndigaugeClient` node to your main scene (or an autoload scene).

---

## Quick Start

### 1. Set up the client

Attach a script to the node that holds `IndigaugeClient`, or do this from any script that has a reference to the node:

```gdscript
@onready var _client: IndigaugeClient = $IndigaugeClient

func _ready() -> void:
    # Use Mode.DEV during development - no API key needed, all output goes to the console.
    _client.mode = IndigaugeTypes.Mode.DEV

    # Switch to Mode.LIVE with your real public key when you are ready to ship.
    # _client.mode = IndigaugeTypes.Mode.LIVE

    _client.setup("YOUR_PUBLIC_KEY", "MyGame", "1.0.0")

    _client.session_started.connect(_on_session_started)
    _client.session_failed.connect(_on_session_failed)

    _client.start_session()

func _on_session_started(token: String) -> void:
    print("Session started: ", token)

func _on_session_failed(_code: int, message: String) -> void:
    print("Session failed: ", message)
```

### 2. Log events

Event types must be two lowercase words separated by a single dot (e.g. `"player.died"`, `"level.completed"`).

```gdscript
# Log with different severity levels
_client.ig_info("player.jumped")
_client.ig_warn("enemy.escaped", {"enemy_id": "goblin_01"})
_client.ig_error("save.failed", {"reason": "disk_full"})
_client.ig_debug("ui.menu_opened")
_client.ig_trace("physics.collision")
```

Events are batched and flushed automatically every 10 seconds (configurable).

### 3. Collect player feedback

Use the built-in feedback panel scene, or call `submit_feedback` directly:

```gdscript
const FeedbackPanel := preload("res://addons/indigauge/feedback_panel.tscn")

func _show_feedback_panel() -> void:
    var panel: Control = FeedbackPanel.instantiate()
    panel.client = _client  # required - must be set before adding to the tree
    add_child(panel)

# Or submit feedback directly without the UI:
_client.submit_feedback("The jump feels off", "bug", "", false)
_client.submit_feedback("Add a dash move", "suggestion", "", true)  # true = include screenshot
```

---

## Configuration

After calling `setup()`, you can adjust these properties on `IndigaugeClient` before calling `start_session()`:

| Property | Type | Default | Description |
|---|---|---|---|
| `mode` | `IndigaugeTypes.Mode` | `LIVE` | `LIVE`, `DEV` (logs to console only), or `DISABLED` |
| `log_level` | `IndigaugeTypes.LogLevel` | `INFO` | `DEBUG`, `INFO`, `WARN`, `ERROR`, or `SILENT` |

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
| `feedback_sent` | `feedback_id: String` | Emitted after feedback is accepted by the server |

---

## Example Project

An immediately runnable example project lives in the `example/` directory.

1. Open Godot and choose **Import** → navigate to `example/project.godot`.
2. Press **F5** (Run) - no API key is needed as it runs in `DEV` mode.
3. Click **Log Events** to see events printed to the Output panel.
4. Click **Open Feedback Panel** to try the built-in feedback UI.

To test with a real Indigauge account, open `example/main.gd`, change:

```gdscript
_client.mode = IndigaugeTypes.Mode.DEV
_client.setup("YOUR_PUBLIC_KEY", "ExampleGame", "1.0.0")
```

to:

```gdscript
_client.mode = IndigaugeTypes.Mode.LIVE
_client.setup("your-real-public-key", "ExampleGame", "1.0.0")
```

---

## License

See [LICENSE](LICENSE).
