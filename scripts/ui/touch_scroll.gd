extends ScrollContainer
## Vertical drag-to-scroll for touch screens that works wherever the finger lands.
## Godot's built-in drag only starts when the press reaches the ScrollContainer itself, so a
## list full of buttons (every panel here) could not be flicked on phones. This listens to the
## raw touch events instead, scrolls immediately on every move, cancels the pressed button via
## NOTIFICATION_SCROLL_BEGIN once the finger moved past the dead zone, and keeps a little
## momentum after release. A real mouse drag scrolls the same way.

const DEADZONE := 12.0 # px of travel before a press turns into a scroll
const FRICTION := 1800.0 # px/s^2
const MIN_SPEED := 40.0 # px/s

var _touching := false
var _index := 0
var _dragging := false
var _start_y := 0.0
var _start_scroll := 0.0
var _last_y := 0.0
var _last_ms := 0
var _speed := 0.0 # content px/s, positive = scrolling down
var _pos := 0.0

func _ready() -> void:
	scroll_deadzone = 1 << 30 # the built-in drag never kicks in
	set_process(false)

## Swallow the (emulated) mouse press/motion so ScrollContainer's own drag never starts;
## wheel events still fall through to it.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		accept_event()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()

const MOUSE_INDEX := -2 # pseudo touch index for a real mouse drag

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Events the engine synthesised from the other device are ignored, so a real touch and a
	# real mouse each count once.
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		# Browsers hand out arbitrary touch ids, so follow the first finger by its own index.
		if t.pressed:
			_press(t.index, t.position)
		elif _touching and t.index == _index:
			_release()
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if _touching and d.index == _index:
			_move(d.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_press(MOUSE_INDEX, mb.position)
		elif _touching and _index == MOUSE_INDEX:
			_release()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _touching and _index == MOUSE_INDEX and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
			_move(mm.position)

func _press(index: int, pos: Vector2) -> void:
	if _touching or not get_global_rect().has_point(pos):
		return
	_touching = true
	_index = index
	_dragging = false
	_start_y = pos.y
	_last_y = _start_y
	_start_scroll = get_v_scroll_bar().value
	_last_ms = Time.get_ticks_msec()
	_speed = 0.0
	set_process(false)

func _move(pos: Vector2) -> void:
	var dy := pos.y - _start_y
	if not _dragging:
		if absf(dy) < DEADZONE:
			return
		_dragging = true
		propagate_notification(NOTIFICATION_SCROLL_BEGIN)
	var now := Time.get_ticks_msec()
	var dt := maxf(0.001, float(now - _last_ms) / 1000.0)
	_speed = lerpf(_speed, (_last_y - pos.y) / dt, 0.5)
	_last_y = pos.y
	_last_ms = now
	get_v_scroll_bar().value = _start_scroll - dy
	get_viewport().set_input_as_handled()

func _release() -> void:
	_touching = false
	# Holding still before lifting a finger should stop the list, not revive an old flick.
	if Time.get_ticks_msec() - _last_ms > 120:
		_speed = 0.0
	if _dragging:
		_dragging = false
		propagate_notification(NOTIFICATION_SCROLL_END)
		if absf(_speed) > MIN_SPEED:
			_pos = get_v_scroll_bar().value
			set_process(true)

func _process(delta: float) -> void:
	var bar := get_v_scroll_bar()
	_pos += _speed * delta
	var limit := bar.max_value - bar.page
	if _pos <= 0.0 or _pos >= limit:
		_pos = clampf(_pos, 0.0, limit)
		set_process(false)
	bar.value = _pos
	var s := absf(_speed) - FRICTION * delta
	if s <= MIN_SPEED:
		set_process(false)
	else:
		_speed = signf(_speed) * s

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		_touching = false
		_dragging = false
		set_process(false)
