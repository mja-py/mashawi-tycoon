class_name FloatLayer
extends Control
## Words above the street (customer lines, "+AED n" sale pops) as small rounded chips that
## follow their 3D speaker. A fixed pool, a cap on live chips, and chips that would touch
## stack upwards, so two never draw on top of each other even at 12x.

const GROUP := &"float_texts"
const MAX_CHIPS := 7
const POP_IN := 0.16
const FADE_OUT := 0.35
## Upward drift of a sale pop over its life (logical px).
const MONEY_RISE := 26.0
const GAP := 3.0

var _pool: Array[PanelContainer] = []
## Oldest first: {chip, label, owner, anchor, height, age, life, kind}
var _live: Array[Dictionary] = []
var _say_style: StyleBoxFlat
var _money_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_to_group(GROUP)
	_say_style = UiTheme.flat(Color(UiTheme.NIGHT_DARK, 0.82), 9)
	_say_style.content_margin_left = 9
	_say_style.content_margin_right = 9
	_say_style.content_margin_top = 1
	_say_style.content_margin_bottom = 2
	_money_style = _say_style.duplicate()
	_money_style.bg_color = Color(UiTheme.PALM_DARK, 0.92)
	_money_style.border_color = Color(UiTheme.GOLD_LIGHT, 0.7)
	_money_style.set_border_width_all(1)
	set_process(false)

## A customer's line. One line per speaker: speaking again replaces the old line.
func say(speaker: Node3D, text: String, color: Color, duration: float, height: float) -> void:
	for e in _live:
		if e["owner"] == speaker and e["kind"] == &"say":
			_fill(e, text, Color(color, 1.0), _say_style)
			e["age"] = 0.0
			e["life"] = duration + POP_IN + FADE_OUT
			e["height"] = height
			return
	_spawn(speaker, text, Color(color, 1.0), duration, height, &"say")

## "+AED 12" over the buyer for every sale.
func money(buyer: Node3D, amount: float, height: float = 0.95) -> void:
	var text := Loc.money(amount)
	text = ("\u200e+" if Loc.is_rtl() else "+") + text
	_spawn(buyer, text, UiTheme.GOLD_LIGHT, 0.75, height, &"money")

func clear() -> void:
	for e in _live:
		_release(e)
	_live.clear()
	set_process(false)

func live_count() -> int:
	return _live.size()

func _spawn(speaker: Node3D, text: String, color: Color, duration: float, height: float, kind: StringName) -> void:
	if not is_instance_valid(speaker) or not speaker.is_inside_tree():
		return
	if _live.size() >= MAX_CHIPS:
		_release(_live.pop_front())
	var chip: PanelContainer
	if _pool.is_empty():
		chip = PanelContainer.new()
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var label := Label.new()
		label.add_theme_font_override("font", UiTheme.bold())
		label.add_theme_font_size_override("font_size", 17)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.add_child(label)
		add_child(chip)
	else:
		chip = _pool.pop_back()
	chip.show()
	move_child(chip, -1)
	var e := {"chip": chip, "label": chip.get_child(0), "owner": speaker, "anchor": speaker.global_position,
		"height": height, "age": 0.0, "life": duration + POP_IN + FADE_OUT, "kind": kind}
	_fill(e, text, color, _money_style if kind == &"money" else _say_style)
	_live.append(e)
	_place(e, Vector2.ZERO)
	chip.modulate.a = 0.0
	set_process(true)

func _fill(e: Dictionary, text: String, color: Color, style: StyleBoxFlat) -> void:
	var chip: PanelContainer = e["chip"]
	var label: Label = e["label"]
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 18 if e["kind"] == &"money" else 17)
	chip.add_theme_stylebox_override("panel", style)
	chip.size = chip.get_combined_minimum_size()
	chip.pivot_offset = Vector2(chip.size.x * 0.5, chip.size.y)

func _release(e: Dictionary) -> void:
	var chip: PanelContainer = e["chip"]
	chip.hide()
	_pool.append(chip)

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var to_local := get_global_transform().affine_inverse()
	var placed: Array[Rect2] = []
	var i := 0
	while i < _live.size():
		var e: Dictionary = _live[i]
		e["age"] = float(e["age"]) + delta
		if float(e["age"]) >= float(e["life"]):
			_release(e)
			_live.remove_at(i)
			continue
		var speaker: Node3D = e["owner"] if is_instance_valid(e["owner"]) else null
		if speaker and speaker.is_inside_tree() and speaker.is_visible_in_tree():
			e["anchor"] = speaker.global_position
		var chip: PanelContainer = e["chip"]
		if cam == null:
			chip.visible = false
			i += 1
			continue
		var point := to_local * cam.unproject_position(e["anchor"] + Vector3.UP * float(e["height"]))
		var rect := Rect2(point - Vector2(chip.size.x * 0.5, chip.size.y), chip.size)
		# Stack above anything already placed this frame (oldest keep their spot).
		for _pass in range(MAX_CHIPS):
			var moved := false
			for other in placed:
				if rect.intersects(other.grow(GAP * 0.5)):
					rect.position.y = other.position.y - rect.size.y - GAP
					moved = true
			if not moved:
				break
		placed.append(rect)
		_place(e, rect.position)
		i += 1
	if _live.is_empty():
		set_process(false)

func _place(e: Dictionary, top_left: Vector2) -> void:
	var chip: PanelContainer = e["chip"]
	var age := float(e["age"])
	var life := float(e["life"])
	var appear := clampf(age / POP_IN, 0.0, 1.0)
	var fade := clampf((life - age) / FADE_OUT, 0.0, 1.0)
	var rise := 0.0
	if e["kind"] == &"money":
		rise = MONEY_RISE * (1.0 - pow(1.0 - clampf(age / life, 0.0, 1.0), 2.0))
	chip.visible = true
	chip.position = top_left - Vector2(0.0, rise)
	# A small overshoot on arrival, like the old bubble's back-ease pop.
	chip.scale = Vector2.ONE * (0.6 + 0.4 * appear + 0.08 * sin(appear * PI))
	chip.modulate.a = minf(appear * 1.6, 1.0) * fade
