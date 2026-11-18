extends Control
## Phone-sized card picker. Drag tracks the finger, then the focused card snaps
## into place. Only nearby cards are built, so a roll never renders a whole menu.
## The arrows and the page count float over the edges of the roll: a landscape phone
## cannot spare a row of height below the cards.

signal index_changed(index: int)

const MOUSE := -2
const DEADZONE := 13.0
var surface: Control
var _page: Label
var _previous: Button
var _next: Button
var _factory: Callable
var _cards := {}
var _count := 0
var _index := 0
var _cursor := 0.0
var _rtl := 1.0
var _snap: Tween
var _pointer := -1
var _origin := Vector2.ZERO
var _origin_cursor := 0.0
var _dragging := false
## 0 -> 1 while the roll makes its entrance (focused card first, neighbours just after).
var _entrance := 1.0
var _entrance_tween: Tween
## Smallest scale a card was drawn at for lack of height (1.0 = every card at full size).
var _fit := 1.0
## Set by the HUD when the panel is short (notch plus the guide strip): the page count goes
## and the cards get its height.
var tight := false
const ARROW := Vector2(60, 84)

func _ready() -> void:
	custom_minimum_size.y = 136.0
	surface = Control.new()
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	surface.clip_contents = true
	add_child(surface)
	surface.resized.connect(_layout_cards, CONNECT_DEFERRED)
	_previous = _arrow(-1)
	_next = _arrow(1)
	_page = Label.new()
	_page.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page.theme_type_variation = "Small"
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.z_index = 6
	add_child(_page)

func _arrow(side: int) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Icon"
	# The row is always left-to-right, so the glyph points where it moves on screen (the
	# triangles are not bidi-mirrored, unlike < > and ‹ ›); the spoken name follows the
	# reading direction (the left arrow is "next" in Arabic).
	b.text = tr("ui.roll_left") if side < 0 else tr("ui.roll_right")
	b.text_direction = Control.TEXT_DIRECTION_LTR
	var forward := (side > 0) != is_layout_rtl()
	b.tooltip_text = tr("ui.roll_next") if forward else tr("ui.roll_prev")
	b.accessibility_name = b.tooltip_text
	b.add_theme_font_size_override("font_size", 24)
	b.custom_minimum_size = ARROW
	b.focus_mode = Control.FOCUS_NONE
	b.z_index = 6
	b.pressed.connect(func(): move_to(_index + side * int(_rtl)))
	if DevTools.has("uitest"):
		b.set_meta("menu_target", "roll_left" if side < 0 else "roll_right")
	add_child(b)
	return b

func configure(count: int, index: int, factory: Callable) -> void:
	if _snap:
		_snap.kill()
	_pointer = -1
	_dragging = false
	for c in _cards.values():
		surface.remove_child(c)
		c.queue_free()
	_cards.clear()
	_count = count
	_index = clampi(index, 0, maxi(0, count - 1))
	_cursor = _index
	_factory = factory
	_rtl = -1.0 if is_layout_rtl() else 1.0
	_show_index()
	_layout_cards.call_deferred()

## Cards rise and fade into place when a tab opens. Layout owns every card transform, so
## the entrance is a factor _layout_cards applies rather than tweens on the cards.
func play_entrance(duration: float = 0.34) -> void:
	if _entrance_tween:
		_entrance_tween.kill()
	_entrance = 0.0
	_layout_cards()
	_entrance_tween = create_tween()
	_entrance_tween.tween_method(func(v: float):
		_entrance = v
		_layout_cards(), 0.0, 1.0, duration)

## A tap on the focused card opens it. A tap on a neighbour brings it to the middle and
## opens it in the same gesture; swiping or the arrows are for browsing.
func choose(index: int, action: Callable) -> void:
	if index == _index:
		action.call()
		return
	move_to(index)
	_snap.tween_callback(func():
		if _index == index and not _dragging:
			action.call())

func test_view() -> Dictionary:
	var box := get_global_rect().grow(1.0)
	return {"fit": _fit, "count": _count, "index": _index, "arrows": _previous.visible,
		"arrowsInside": box.encloses(_previous.get_global_rect()) and box.encloses(_next.get_global_rect())}

func selected_index() -> int:
	return _index

func is_focused_control(control: Control) -> bool:
	return not surface.is_ancestor_of(control) or (_cards.has(_index) and _cards[_index].is_ancestor_of(control))

func move_to(index: int) -> void:
	if _count == 0:
		return
	var next := clampi(index, 0, _count - 1)
	if next != _index:
		_index = next
		index_changed.emit(_index)
		Sfx.play("switch")
	if _snap:
		_snap.kill()
	_snap = create_tween()
	_snap.tween_method(_set_cursor, _cursor, float(_index), 0.32).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_show_index()

func _show_index() -> void:
	_previous.visible = _count > 1
	_next.visible = _count > 1
	_previous.disabled = _index - int(_rtl) < 0 or _index - int(_rtl) >= _count
	_next.disabled = _index + int(_rtl) < 0 or _index + int(_rtl) >= _count
	_page.text = Loc.ltr("%02d / %02d" % [_index + 1, _count]) if _count > 1 else ""
	_layout_cards()

func _set_cursor(value: float) -> void:
	_cursor = value
	_layout_cards()

func _card_width() -> float:
	return clampf(surface.size.x * 0.42, 280.0, 440.0)

## Distance between neighbouring card centres: the next card stays readable beside
## the focused one instead of peeking in from the edge.
func _step() -> float:
	return _card_width() * 0.92

func _layout_cards() -> void:
	# Arrows sit at the outer edges, vertically centred; the page count under the cards.
	var mid := (size.y - ARROW.y) * 0.5
	_previous.size = ARROW
	_next.size = ARROW
	_previous.position = Vector2(6.0, mid)
	_next.position = Vector2(size.x - ARROW.x - 6.0, mid)
	_page.visible = _count > 1 and not tight
	_page.reset_size()
	_page.position = Vector2((size.x - _page.size.x) * 0.5, size.y - _page.size.y + 4.0)
	if _count == 0 or not _factory.is_valid() or surface.size.x < 1:
		return
	_fit = 1.0
	var near := roundi(_cursor)
	for i in range(maxi(0, near - 1), mini(_count - 1, near + 1) + 1):
		if not _cards.has(i):
			var card: Control = _factory.call(i)
			_cards[i] = card
			card.minimum_size_changed.connect(_layout_cards, CONNECT_DEFERRED)
			surface.add_child(card)
	if _cards.has(_index):
		var focused: Control = _cards[_index]
		if focused.get_index() != surface.get_child_count() - 1:
			surface.move_child(focused, -1)
	for i in _cards.keys():
		var card: Control = _cards[i]
		var offset := (float(i) - _cursor) * _rtl
		var distance := absf(offset)
		card.visible = distance < 1.55
		if not card.visible:
			continue
		var room := maxf(1.0, surface.size.y - (8.0 if tight else 22.0))
		card.size = Vector2(_card_width(), room)
		card.pivot_offset = card.size * 0.5
		var fit := minf(1.0, room / card.size.y)
		_fit = minf(_fit, fit)
		var arrive := 1.0
		if _entrance < 1.0:
			var e := clampf(_entrance * 1.5 - distance * 0.4, 0.0, 1.0)
			arrive = 1.0 - pow(1.0 - e, 3.0)
		card.scale = Vector2.ONE * fit * lerpf(1.0, 0.86, minf(distance, 1.0)) * lerpf(0.95, 1.0, arrive)
		card.rotation = clampf(offset, -1.0, 1.0) * 0.03
		card.position = (surface.size - card.size) * 0.5 + Vector2(offset * _step(), distance * 6.0 + (1.0 - arrive) * 18.0 - (0.0 if tight else 8.0))
		card.modulate.a = lerpf(1.0, 0.8, minf(distance, 1.0)) * arrive
		card.z_index = 3 - mini(roundi(distance * 2.0), 3)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _count < 2 or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventScreenTouch:
		_pointer_event(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag and event.index == _pointer:
		_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_pointer_event(MOUSE, event.position, event.pressed)
	elif event is InputEventMouseMotion and _pointer == MOUSE and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_drag(event.position)

func _pointer_event(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if _pointer != -1 or not surface.get_global_rect().has_point(pos):
			return
		_pointer = index
		_origin = surface.get_global_transform_with_canvas().affine_inverse() * pos
		_origin_cursor = _cursor
		_dragging = false
	elif index == _pointer:
		_pointer = -1
		if _dragging:
			_dragging = false
			var shift := _cursor - _origin_cursor
			var target := _index if absf(shift) < 0.13 else _index + int(signf(shift))
			move_to(target)
			propagate_notification(NOTIFICATION_SCROLL_END)
			get_viewport().set_input_as_handled()

func _drag(pos: Vector2) -> void:
	var delta := surface.get_global_transform_with_canvas().affine_inverse() * pos - _origin
	if not _dragging:
		if absf(delta.x) < DEADZONE or absf(delta.x) < absf(delta.y):
			return
		_dragging = true
		if _snap:
			_snap.kill()
		propagate_notification(NOTIFICATION_SCROLL_BEGIN)
	_set_cursor(clampf(_origin_cursor - delta.x * _rtl / _step(), -0.16, float(_count - 1) + 0.16))
	get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DISABLED or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		if _dragging and what == NOTIFICATION_DISABLED:
			_set_cursor(float(_index))
		_pointer = -1
		_dragging = false
