extends Control

# ---------------------------------------------------------------------------
# Indigauge Breakout Example
#
# A tiny classic arcade game that demonstrates where analytics and player
# feedback naturally fit in a Godot project.
# ---------------------------------------------------------------------------

const BOARD_SIZE := Vector2(800.0, 520.0)
const PADDLE_SIZE := Vector2(116.0, 16.0)
const BALL_RADIUS := 8.0
const BRICK_COLS := 10
const BRICK_ROWS := 5
const BRICK_SIZE := Vector2(68.0, 24.0)
const BRICK_GAP := 8.0
const PADDLE_SPEED := 520.0
const STARTING_LIVES := 3
const STARTING_BALL_SPEED := 330.0
const MAX_BALL_SPEED := 560.0

var _board_origin := Vector2.ZERO
var _paddle_x := 0.0
var _ball_position := Vector2.ZERO
var _ball_velocity := Vector2.ZERO
var _bricks: Array[Dictionary] = []
var _score := 0
var _lives := STARTING_LIVES
var _level := 1
var _shots := 0
var _brick_hits := 0
var _state := "ready"
var _session_ready := false
var _mouse_was_down := false

@onready var _score_label: Label = $Hud/ScoreLabel
@onready var _lives_label: Label = $Hud/LivesLabel
@onready var _status_label: Label = $Hud/StatusLabel
@onready var _telemetry_label: Label = $Hud/TelemetryLabel
@onready var _restart_button: Button = $Hud/Actions/RestartButton
@onready var _feedback_button: Button = $Hud/Actions/FeedbackButton
@onready var _client: IndigaugeClient = $IndigaugeClient


func _ready() -> void:
	_client.session_started.connect(_on_session_started)
	_client.session_failed.connect(_on_session_failed)
	_client.feedback_sent.connect(_on_feedback_sent)
	_client.start("YOUR_PUBLIC_KEY", "Indigauge Breakout", "1.0.0")

	_restart_button.pressed.connect(_new_game)
	_feedback_button.pressed.connect(
		func() -> void:
			_log_info("ui.feedback", {"state": _state, "score": _score, "level": _level})
			_client.toggle_feedback_panel()
	)

	_new_game()
	set_process(true)


func _process(delta: float) -> void:
	_update_board_origin()
	_update_paddle(delta)

	var launch_pressed := _launch_pressed()
	if _state == "ready" and launch_pressed:
		_launch_ball()
	elif _state == "playing":
		_move_ball(delta)
	elif _state == "won" and launch_pressed:
		_reset_round("ready")
		_launch_ball()
	elif _state == "gameover" and launch_pressed:
		_new_game()

	_update_labels()
	queue_redraw()
	_mouse_was_down = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _draw() -> void:
	_update_board_origin()
	_draw_background()
	_draw_bricks()
	_draw_paddle()
	_draw_ball()
	_draw_overlay()


func _new_game() -> void:
	_score = 0
	_lives = STARTING_LIVES
	_level = 1
	_shots = 0
	_brick_hits = 0
	_build_bricks()
	_reset_round("ready")
	_sync_session_metadata(true)
	_log_info("game.start", {"level": _level})


func _build_bricks() -> void:
	_bricks.clear()
	var total_width := BRICK_COLS * BRICK_SIZE.x + (BRICK_COLS - 1) * BRICK_GAP
	var start_x := (BOARD_SIZE.x - total_width) * 0.5
	var colors := [
		Color("f25f5c"),
		Color("ffb000"),
		Color("5cc8ff"),
		Color("58d68d"),
		Color("b58cff"),
	]

	for row in range(BRICK_ROWS):
		for col in range(BRICK_COLS):
			var position := Vector2(
				start_x + col * (BRICK_SIZE.x + BRICK_GAP), 66.0 + row * (BRICK_SIZE.y + BRICK_GAP)
			)
			(
				_bricks
				. append(
					{
						"rect": Rect2(position, BRICK_SIZE),
						"color": colors[row % colors.size()],
						"points": (BRICK_ROWS - row) * 10,
						"alive": true,
					}
				)
			)


func _reset_round(next_state: String) -> void:
	_state = next_state
	_paddle_x = BOARD_SIZE.x * 0.5 - PADDLE_SIZE.x * 0.5
	_ball_position = Vector2(BOARD_SIZE.x * 0.5, BOARD_SIZE.y - 74.0)
	_ball_velocity = Vector2.ZERO


func _update_board_origin() -> void:
	var hud_bottom := 92.0
	var available := size - Vector2(0.0, hud_bottom)
	_board_origin = Vector2(
		max(18.0, (available.x - BOARD_SIZE.x) * 0.5),
		hud_bottom + max(14.0, (available.y - BOARD_SIZE.y) * 0.5)
	)


func _update_paddle(delta: float) -> void:
	var axis := Input.get_axis("ui_left", "ui_right")
	if Input.is_key_pressed(KEY_A):
		axis -= 1.0
	if Input.is_key_pressed(KEY_D):
		axis += 1.0

	if absf(axis) > 0.01:
		_paddle_x += clampf(axis, -1.0, 1.0) * PADDLE_SPEED * delta

	if not _mouse_over_hud() and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_paddle_x = _to_board(get_global_mouse_position()).x - PADDLE_SIZE.x * 0.5

	_paddle_x = clampf(_paddle_x, 0.0, BOARD_SIZE.x - PADDLE_SIZE.x)
	if _state == "ready":
		_ball_position.x = _paddle_x + PADDLE_SIZE.x * 0.5


func _launch_pressed() -> bool:
	var mouse_down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var mouse_just_pressed := mouse_down and not _mouse_was_down and not _mouse_over_hud()
	return Input.is_action_just_pressed("ui_accept") or mouse_just_pressed


func _mouse_over_hud() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != self


func _launch_ball() -> void:
	_state = "playing"
	_shots += 1
	var horizontal := randf_range(-0.35, 0.35)
	_ball_velocity = (
		Vector2(horizontal, -1.0).normalized() * (STARTING_BALL_SPEED + (_level - 1) * 28.0)
	)
	_sync_session_metadata()
	_log_info("ball.launch", {"level": _level, "shot": _shots, "lives": _lives})


func _move_ball(delta: float) -> void:
	_ball_position += _ball_velocity * delta

	if _ball_position.x <= BALL_RADIUS:
		_ball_position.x = BALL_RADIUS
		_ball_velocity.x = absf(_ball_velocity.x)
	elif _ball_position.x >= BOARD_SIZE.x - BALL_RADIUS:
		_ball_position.x = BOARD_SIZE.x - BALL_RADIUS
		_ball_velocity.x = -absf(_ball_velocity.x)

	if _ball_position.y <= BALL_RADIUS:
		_ball_position.y = BALL_RADIUS
		_ball_velocity.y = absf(_ball_velocity.y)

	_check_paddle_collision()
	_check_brick_collision()

	if _ball_position.y > BOARD_SIZE.y + BALL_RADIUS:
		_lives -= 1
		if _lives <= 0:
			_state = "gameover"
			_sync_session_metadata()
			_client.ig_error("game.over", {"score": _score, "level": _level, "hits": _brick_hits})
		else:
			_reset_round("ready")
			_sync_session_metadata()
		_log_warn("life.lost", {"score": _score, "level": _level, "lives": _lives})


func _check_paddle_collision() -> void:
	if _ball_velocity.y <= 0.0:
		return

	var paddle := Rect2(Vector2(_paddle_x, BOARD_SIZE.y - 48.0), PADDLE_SIZE)
	var ball_rect := Rect2(
		_ball_position - Vector2.ONE * BALL_RADIUS, Vector2.ONE * BALL_RADIUS * 2.0
	)
	if not paddle.intersects(ball_rect):
		return

	var hit := clampf((_ball_position.x - paddle.position.x) / paddle.size.x, 0.0, 1.0)
	var angle := lerpf(-0.95, 0.95, hit)
	var speed := minf(_ball_velocity.length() + 8.0, MAX_BALL_SPEED)
	_ball_velocity = Vector2(angle, -1.0).normalized() * speed
	_ball_position.y = paddle.position.y - BALL_RADIUS


func _check_brick_collision() -> void:
	var ball_rect := Rect2(
		_ball_position - Vector2.ONE * BALL_RADIUS, Vector2.ONE * BALL_RADIUS * 2.0
	)
	for i in range(_bricks.size()):
		var brick := _bricks[i]
		if not brick["alive"]:
			continue
		var rect: Rect2 = brick["rect"]
		if not rect.intersects(ball_rect):
			continue

		brick["alive"] = false
		_bricks[i] = brick
		_score += int(brick["points"])
		_brick_hits += 1
		_ball_velocity.y *= -1.0
		_ball_velocity = (
			_ball_velocity.normalized() * minf(_ball_velocity.length() + 10.0, MAX_BALL_SPEED)
		)
		_sync_session_metadata()
		_log_info(
			"brick.hit",
			{
				"row": int(i / BRICK_COLS),
				"col": i % BRICK_COLS,
				"score": _score,
				"remaining": _remaining_bricks(),
			}
		)

		if _remaining_bricks() == 0:
			_level_cleared()
		return


func _level_cleared() -> void:
	_log_info("level.clear", {"level": _level, "score": _score, "shots": _shots})
	_level += 1
	_lives = min(_lives + 1, 5)
	_build_bricks()
	_reset_round("ready")
	_state = "won"
	_sync_session_metadata()


func _remaining_bricks() -> int:
	var count := 0
	for brick in _bricks:
		if brick["alive"]:
			count += 1
	return count


func _draw_background() -> void:
	draw_rect(Rect2(_board_origin, BOARD_SIZE), Color("10131d"))
	draw_rect(Rect2(_board_origin, BOARD_SIZE), Color("3d4964"), false, 2.0)
	for y in range(0, int(BOARD_SIZE.y), 32):
		draw_line(
			_board_origin + Vector2(0.0, y),
			_board_origin + Vector2(BOARD_SIZE.x, y),
			Color(1, 1, 1, 0.035),
			1.0
		)


func _draw_bricks() -> void:
	for brick in _bricks:
		if not brick["alive"]:
			continue
		var rect: Rect2 = brick["rect"]
		var screen_rect := Rect2(_board_origin + rect.position, rect.size)
		draw_rect(screen_rect, brick["color"])
		draw_rect(screen_rect.grow(-3.0), Color(1, 1, 1, 0.13), false, 1.0)


func _draw_paddle() -> void:
	var rect := Rect2(_board_origin + Vector2(_paddle_x, BOARD_SIZE.y - 48.0), PADDLE_SIZE)
	draw_rect(rect, Color("f7f3df"))
	draw_rect(
		Rect2(rect.position + Vector2(10.0, 4.0), Vector2(rect.size.x - 20.0, 4.0)), Color("5cc8ff")
	)


func _draw_ball() -> void:
	draw_circle(_board_origin + _ball_position, BALL_RADIUS + 3.0, Color(1, 1, 1, 0.14))
	draw_circle(_board_origin + _ball_position, BALL_RADIUS, Color("ffffff"))


func _draw_overlay() -> void:
	if _state == "playing":
		return

	var text := "Press Space or click to launch"
	if _state == "gameover":
		text = "Game over - press Space or click to restart"
	elif _state == "won":
		text = "Level clear - press Space or click for the next board"

	var font := get_theme_default_font()
	var font_size := 22
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var position := _board_origin + Vector2((BOARD_SIZE.x - text_size.x) * 0.5, BOARD_SIZE.y * 0.58)
	draw_rect(
		Rect2(position - Vector2(18.0, 26.0), text_size + Vector2(36.0, 42.0)), Color(0, 0, 0, 0.55)
	)
	draw_string(font, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("ffffff"))


func _update_labels() -> void:
	_score_label.text = "Score %d" % _score
	_lives_label.text = "Lives %d" % _lives

	if _state == "gameover":
		_status_label.text = "Game Over"
	elif _state == "won":
		_status_label.text = "Level %d ready" % _level
	elif _state == "ready":
		_status_label.text = "Ready"
	else:
		_status_label.text = "Level %d" % _level


func _to_board(global_position: Vector2) -> Vector2:
	return global_position - _board_origin


func _sync_session_metadata(replace: bool = false) -> void:
	var metadata := {
		"score": _score,
		"lives": _lives,
		"level": _level,
		"shots": _shots,
		"brickHits": _brick_hits,
		"remainingBricks": _remaining_bricks(),
		"state": _state,
	}
	if replace:
		_client.set_session_metadata(metadata)
	else:
		_client.update_session_metadata(metadata)


func _on_session_started(token: String) -> void:
	_session_ready = true
	_telemetry_label.text = (
		"Indigauge DEV session active" if token == "dev" else "Indigauge session active"
	)
	_sync_session_metadata()


func _on_session_failed(_code: int, message: String) -> void:
	_session_ready = false
	_telemetry_label.text = "Indigauge session failed: %s" % message


func _on_feedback_sent(feedback_id: String) -> void:
	_telemetry_label.text = "Feedback sent: %s" % feedback_id


func _log_info(event_type: String, metadata: Dictionary = {}) -> void:
	if _session_ready:
		_client.ig_info(event_type, metadata)


func _log_warn(event_type: String, metadata: Dictionary = {}) -> void:
	if _session_ready:
		_client.ig_warn(event_type, metadata)
