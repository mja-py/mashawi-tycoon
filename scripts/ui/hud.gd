extends CanvasLayer
## All 2D UI: top bar, prep tabs + panels, day controls, end-of-day report, title screen.
## Built in code so the layout stays touch-friendly at any phone aspect ratio.

var main: Node
var root: Control
var top_bar: PanelContainer
var money_label: Label
var day_label: Label
var loc_label: Label
var weather_icon: TextureRect
var weather_label: Label
var star_box: HBoxContainer
var clock_label: Label
var clock_chip: PanelContainer
var costs_chip: PanelContainer
var costs_label: Label
var prep_bar: PanelContainer
var day_bar: PanelContainer
var tabs := {}
var speed_buttons := {}
var live_label: Label
var ticker_label: Label
var panel_dim: PanelContainer
var panel: PanelContainer
var panel_title: Label
var panel_scroll: ScrollContainer
var panel_body: VBoxContainer
var current_panel := ""
var report_dim: PanelContainer
var report_panel: PanelContainer
var report_body: VBoxContainer
var title_screen: Control
var toast: PanelContainer
var toast_label: Label
var continue_btn: Button
var _toast_tween: Tween
var _refreshing := false

const PANELS := {
	"supplies": "ui.supplies", "menu": "ui.menu", "place": "ui.place", "upgrades": "ui.upgrades", "promote": "ui.promote",
}

func _ready() -> void:
	_build_all()
	get_viewport().size_changed.connect(_apply_safe_area)
	Game.changed.connect(_refresh)
	Game.notify.connect(_toast)
	Loc.language_changed.connect(_on_language_changed)
	if main and main.sim:
		main.sim.clock_changed.connect(_on_clock)
		main.sim.stats_changed.connect(_on_stats)
		main.sim.event.connect(_toast)
	_refresh()

func _build_all() -> void:
	root = Control.new()
	root.theme = UiTheme.build()
	root.layout_direction = Control.LAYOUT_DIRECTION_RTL if Loc.is_rtl() else Control.LAYOUT_DIRECTION_LTR
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_apply_safe_area()
	_build_top_bar()
	_build_prep_bar()
	_build_day_bar()
	_build_panel()
	_build_report()
	_build_toast()
	_build_title()

## Rebuild every control in the new language and direction (only offered on the title screen).
func _on_language_changed() -> void:
	current_panel = ""
	root.queue_free()
	_build_all()
	if main.world:
		main.world.reload()
	show_title()
	_refresh()

## Keep bars and panels out of notches / rounded corners on phones.
func _apply_safe_area() -> void:
	var vp := root.get_viewport_rect().size
	# The safe area is in screen pixels; only meaningful where the window is the screen.
	if OS.has_feature("mobile"):
		var win := DisplayServer.window_get_size()
		if win.x > 0 and win.y > 0:
			var safe := DisplayServer.get_display_safe_area()
			var sx := vp.x / float(win.x)
			var sy := vp.y / float(win.y)
			root.offset_left = maxf(0.0, safe.position.x) * sx
			root.offset_top = maxf(0.0, safe.position.y) * sy
			root.offset_right = -maxf(0.0, win.x - safe.end.x) * sx
			root.offset_bottom = -maxf(0.0, win.y - safe.end.y) * sy
	var w := vp.x - root.offset_left + root.offset_right
	var h := vp.y - root.offset_top + root.offset_bottom
	if panel:
		panel.custom_minimum_size = Vector2(minf(900.0, w - 32.0), maxf(300.0, h - 60.0 - 84.0 - 16.0))
	if report_panel:
		report_panel.custom_minimum_size = Vector2(minf(860.0, w - 32.0), maxf(300.0, h - 24.0))

# ================================================================= builders

func _label(text: String, variation: String = "", align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	l.horizontal_alignment = align
	# long descriptions wrap; short value labels never do
	if variation == "Muted" or text.length() > 48:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func _bottom_bar() -> PanelContainer:
	var bar := PanelContainer.new()
	bar.theme_type_variation = "Bar"
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -84
	bar.offset_bottom = 0
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(bar)
	return bar

func _button(text: String, variation: String = "", min_size: Vector2 = Vector2(0, 56)) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	return b

func _card() -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = "Card"
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c

func _chip(text: String, icon: Texture2D = null, dark: bool = false) -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = "Card" if dark else "Chip"
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	c.add_child(h)
	if icon:
		var t := TextureRect.new()
		t.texture = icon
		t.custom_minimum_size = Vector2(26, 26)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(t)
	var l := Label.new()
	l.text = text
	l.theme_type_variation = "Light"
	l.add_theme_font_size_override("font_size", 19)
	if dark:
		l.add_theme_color_override("font_color", UiTheme.INK)
	h.add_child(l)
	return c

func _icon(tex: Texture2D, size: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex
	t.custom_minimum_size = Vector2(size, size)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return t

func _spacer(h: bool = true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _build_top_bar() -> void:
	top_bar = PanelContainer.new()
	top_bar.theme_type_variation = "Bar"
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 60
	root.add_child(top_bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	top_bar.add_child(h)
	money_label = _label(Loc.money(0), "Light")
	money_label.size_flags_horizontal = 0
	money_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	money_label.add_theme_font_size_override("font_size", 28)
	money_label.add_theme_color_override("font_color", Color("ffd86b"))
	h.add_child(money_label)
	var day_chip := _chip(tr("ui.day") % 1)
	day_label = day_chip.get_child(0).get_child(0)
	h.add_child(day_chip)
	var loc_chip := _chip("")
	loc_label = loc_chip.get_child(0).get_child(0)
	h.add_child(loc_chip)
	var w_chip := _chip(tr("weather.sunny"), Icons.weather_icon("sunny"))
	weather_icon = w_chip.get_child(0).get_child(0)
	weather_label = w_chip.get_child(0).get_child(1)
	h.add_child(w_chip)
	costs_chip = _chip(tr("ui.costs_today") % Loc.money(0))
	costs_label = costs_chip.get_child(0).get_child(0)
	costs_chip.visible = false
	h.add_child(costs_chip)
	h.add_child(_spacer())
	star_box = HBoxContainer.new()
	star_box.add_theme_constant_override("separation", 2)
	for i in range(5):
		star_box.add_child(_icon(Icons.star_icon(0.0), 28))
	h.add_child(star_box)
	clock_chip = _chip("10:00")
	clock_label = clock_chip.get_child(0).get_child(0)
	clock_label.add_theme_font_size_override("font_size", 24)
	clock_chip.visible = false
	h.add_child(clock_chip)

func _build_prep_bar() -> void:
	prep_bar = _bottom_bar()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	prep_bar.add_child(h)
	for id in PANELS:
		var b := _button(tr(PANELS[id]), "Tab", Vector2(128, 60))
		b.toggle_mode = true
		b.pressed.connect(func(): _toggle_panel(id))
		h.add_child(b)
		tabs[id] = b
	h.add_child(_spacer())
	var open := _button(tr("ui.open_shop"), "Primary", Vector2(220, 64))
	open.pressed.connect(_on_open_shop)
	h.add_child(open)

func _build_day_bar() -> void:
	day_bar = _bottom_bar()
	day_bar.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	day_bar.add_child(h)
	for s in [1.0, 2.0, 4.0]:
		var b := _button("%dx" % int(s), "Tab", Vector2(72, 60))
		b.toggle_mode = true
		b.pressed.connect(func(): _set_speed(s))
		h.add_child(b)
		speed_buttons[s] = b
	var skip := _button(tr("ui.skip"), "Ghost", Vector2(170, 56))
	skip.pressed.connect(func():
		Sfx.play("click")
		main.skip_day()
		_set_speed(12.0))
	h.add_child(skip)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	live_label = _label(tr("ui.live") % [0, Loc.money(0), 0], "Light", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(live_label)
	ticker_label = _label("", "Muted", HORIZONTAL_ALIGNMENT_RIGHT)
	ticker_label.add_theme_color_override("font_color", Color("ffd86b"))
	v.add_child(ticker_label)

func _build_panel() -> void:
	panel_dim = PanelContainer.new()
	panel_dim.theme_type_variation = "Dim"
	panel_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_dim.offset_top = 60
	panel_dim.offset_bottom = -84
	panel_dim.visible = false
	panel_dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			close_panel())
	root.add_child(panel_dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_dim.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 540)
	center.add_child(panel)
	_apply_safe_area()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	panel_title = _label(tr("ui.supplies"), "Heading")
	head.add_child(panel_title)
	var close := _button(tr("ui.close"), "Ghost", Vector2(100, 48))
	close.pressed.connect(close_panel)
	head.add_child(close)
	panel_scroll = ScrollContainer.new()
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(panel_scroll)
	panel_body = VBoxContainer.new()
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_body.add_theme_constant_override("separation", 10)
	panel_scroll.add_child(panel_body)

func _build_report() -> void:
	report_dim = PanelContainer.new()
	report_dim.theme_type_variation = "Dim"
	report_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	report_dim.visible = false
	root.add_child(report_dim)
	var center := CenterContainer.new()
	report_dim.add_child(center)
	report_panel = PanelContainer.new()
	center.add_child(report_panel)
	report_body = VBoxContainer.new()
	report_body.add_theme_constant_override("separation", 8)
	report_panel.add_child(report_body)
	_apply_safe_area()

func _build_toast() -> void:
	toast = PanelContainer.new()
	toast.theme_type_variation = "Toast"
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(0, 74)
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast)
	toast_label = _label("", "Light", HORIZONTAL_ALIGNMENT_CENTER)
	toast_label.custom_minimum_size = Vector2(420, 0)
	toast.add_child(toast_label)

func _build_title() -> void:
	title_screen = PanelContainer.new()
	title_screen.theme_type_variation = "Dim"
	title_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_screen.visible = false
	root.add_child(title_screen)
	var center := CenterContainer.new()
	title_screen.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(560, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var logo := _label(tr("ui.title"), "Title", HORIZONTAL_ALIGNMENT_CENTER)
	logo.add_theme_font_size_override("font_size", 64)
	logo.add_theme_color_override("font_color", UiTheme.RED)
	v.add_child(logo)
	v.add_child(_label(tr("ui.subtitle"), "Muted", HORIZONTAL_ALIGNMENT_CENTER))
	var new_btn := _button(tr("ui.new_game"), "Primary", Vector2(0, 64))
	new_btn.pressed.connect(func():
		Sfx.play("confirm")
		main.new_game())
	v.add_child(new_btn)
	var cont := _button(tr("ui.continue"), "", Vector2(0, 60))
	continue_btn = cont
	cont.pressed.connect(func():
		Sfx.play("confirm")
		main.continue_game())
	v.add_child(cont)
	var lang := _button(tr("ui.lang_toggle"), "Ghost", Vector2(0, 54))
	lang.pressed.connect(func():
		Sfx.play("switch")
		Loc.toggle())
	v.add_child(lang)
	v.add_child(_label(tr("ui.credits"), "Small", HORIZONTAL_ALIGNMENT_CENTER))

# ================================================================= phases

func show_title() -> void:
	close_panel()
	report_dim.visible = false
	prep_bar.visible = false
	day_bar.visible = false
	top_bar.visible = false
	title_screen.visible = true
	continue_btn.visible = Game.has_save()

func show_prep() -> void:
	title_screen.visible = false
	report_dim.visible = false
	top_bar.visible = true
	prep_bar.visible = true
	day_bar.visible = false
	clock_chip.visible = false
	close_panel()
	_refresh()

func show_day() -> void:
	close_panel()
	title_screen.visible = false
	report_dim.visible = false
	top_bar.visible = true
	prep_bar.visible = false
	day_bar.visible = true
	clock_chip.visible = true
	ticker_label.text = ""
	_set_speed(1.0)
	_refresh()

func show_report(r: Dictionary) -> void:
	day_bar.visible = false
	for c in report_body.get_children():
		c.queue_free()
	var head := HBoxContainer.new()
	report_body.add_child(head)
	var rt := _label(tr("ui.r_title") % [r["day"], tr(Data.LOCATIONS[r["location"]]["name"])], "Title")
	rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(rt)
	var wchip := _chip(tr(Data.WEATHER[r["weather"]]["name"]), Icons.weather_icon(r["weather"]), true)
	head.add_child(wchip)
	var cols_scroll := ScrollContainer.new()
	cols_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	report_body.add_child(cols_scroll)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols_scroll.add_child(cols)
	# customers column
	var c1 := _card()
	cols.add_child(c1)
	var v1 := VBoxContainer.new()
	v1.add_theme_constant_override("separation", 8)
	c1.add_child(v1)
	var g1 := _grid()
	v1.add_child(g1)
	_row(g1, tr("ui.r_passers"), str(r["passers"]))
	_row(g1, tr("ui.r_served"), str(r["served"]), UiTheme.GREEN_DARK)
	_row(g1, tr("ui.r_left_wait"), str(r["left_wait"]), UiTheme.RED if r["left_wait"] > 0 else UiTheme.INK)
	_row(g1, tr("ui.r_left_full"), str(r["queue_full"]), UiTheme.RED if r["queue_full"] > 0 else UiTheme.INK)
	_row(g1, tr("ui.r_sold_out"), str(r["sold_out"]), UiTheme.RED if r["sold_out"] > 0 else UiTheme.INK)
	if int(r.get("lost_rival", 0)) > 0:
		_row(g1, tr("ui.r_lost_rival"), str(r["lost_rival"]), UiTheme.RED)
	if int(r.get("too_pricey", 0)) > 0:
		_row(g1, tr("ui.r_too_pricey"), str(r["too_pricey"]), UiTheme.RED)
	_row(g1, tr("ui.r_satisfaction"), "%d%%" % int(round(float(r["satisfaction"]) * 100.0)))
	var pd := float(r["pop_delta"])
	_row(g1, tr("ui.r_reputation"), (tr("ui.r_stars") % Loc.ltr("%+.2f" % (pd * 5.0))), UiTheme.GREEN_DARK if pd >= 0 else UiTheme.RED)
	# the sold list can get long, so it gets its own wrapped line under the table
	var sold_lines := []
	for id in r["sold"]:
		sold_lines.append("%d %s" % [r["sold"][id], tr(Data.MENU_ITEMS[id]["name"])])
	var sold := _label(tr("ui.r_sold") % (", ".join(sold_lines) if not sold_lines.is_empty() else tr("ui.r_nothing")), "Small")
	sold.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sold.add_theme_font_override("font", UiTheme.bold())
	v1.add_child(sold)
	# money column
	var c2 := _card()
	cols.add_child(c2)
	var g2 := _grid()
	c2.add_child(g2)
	_row(g2, tr("ui.r_revenue"), Loc.money(r["revenue"]), UiTheme.GREEN_DARK)
	_row(g2, tr("ui.r_cogs"), Loc.money(float(r["cogs"])), UiTheme.RED)
	_row(g2, tr("ui.r_rent"), Loc.money(float(r["rent"])), UiTheme.RED)
	if float(r["wages"]) > 0:
		_row(g2, tr("ui.r_wages"), Loc.money(float(r["wages"])), UiTheme.RED)
	var sp: Dictionary = r["spoiled"]
	if not sp.is_empty():
		var parts := []
		for ing in sp:
			parts.append("%d %s" % [sp[ing], tr(Data.INGREDIENTS[ing]["name"])])
		_row(g2, tr("ui.r_spoiled") % ", ".join(parts), Loc.money(float(r["spoil_cost"])), UiTheme.RED)
	var profit := float(r["profit"])
	var pl := _row(g2, tr("ui.r_profit"), Loc.money(profit), UiTheme.GREEN_DARK if profit >= 0 else UiTheme.RED)
	pl.theme_type_variation = "Big"
	_row(g2, tr("ui.r_cash"), Loc.money(r["money"]))
	# footer
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	report_body.add_child(foot)
	var fc := _chip(tr("ui.r_forecast") % tr(Data.WEATHER[Game.forecast]["name"]), Icons.weather_icon(Game.forecast), true)
	foot.add_child(fc)
	foot.add_child(_spacer())
	var next := _button(tr("ui.next_day"), "Primary", Vector2(220, 64))
	next.pressed.connect(func():
		Sfx.play("confirm")
		main.show_prep())
	foot.add_child(next)
	_apply_safe_area()
	report_dim.visible = true
	Sfx.play("bong")

func _grid() -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 6)
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return g

func _row(g: GridContainer, k: String, v: String, color: Color = UiTheme.INK) -> Label:
	var kl := _label(k, "Muted")
	if k.length() <= 40:
		kl.autowrap_mode = TextServer.AUTOWRAP_OFF
	g.add_child(kl)
	var vl := _label(v, "", HORIZONTAL_ALIGNMENT_RIGHT)
	vl.autowrap_mode = TextServer.AUTOWRAP_OFF
	vl.add_theme_color_override("font_color", color)
	vl.add_theme_font_override("font", UiTheme.bold())
	vl.size_flags_horizontal = Control.SIZE_SHRINK_END | Control.SIZE_EXPAND
	g.add_child(vl)
	return vl

# ================================================================= top bar / live

func _refresh() -> void:
	if _refreshing:
		return
	_refreshing = true
	money_label.text = Loc.money(Game.money)
	day_label.text = tr("ui.day") % Game.day
	loc_label.text = tr(Game.loc()["name"])
	var in_day: bool = main != null and main.phase == main.Phase.DAY
	var w: String = Game.weather if in_day else Game.forecast
	weather_icon.texture = Icons.weather_icon(w)
	weather_label.text = tr(Data.WEATHER[w]["name"]) if in_day else tr("ui.forecast") % tr(Data.WEATHER[w]["name"])
	var daily := float(Game.loc()["rent"]) + Game.daily_wages()
	costs_chip.visible = daily > 0.0 and not in_day
	costs_label.text = tr("ui.costs_today") % Loc.money(daily)
	var stars := Game.stars()
	for i in range(5):
		var t: TextureRect = star_box.get_child(i)
		t.texture = Icons.star_icon(clampf(stars - i, 0.0, 1.0))
	if current_panel != "":
		_rebuild_panel()
	_refreshing = false

func _on_clock(hour: float) -> void:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	clock_label.text = "%02d:%02d" % [h % 24, m]

func _on_stats(stats: Dictionary) -> void:
	money_label.text = Loc.money(Game.money)
	live_label.text = tr("ui.live") % [stats.get("served", 0), Loc.money(stats.get("revenue", 0.0)), main.sim.queue.size()]

func _set_speed(s: float) -> void:
	for k in speed_buttons:
		speed_buttons[k].button_pressed = is_equal_approx(k, s)
	if main:
		main.set_speed(s)

func _toast(text: String, kind: String = "info") -> void:
	toast_label.text = text
	if kind == "error":
		Sfx.play("error")
	elif kind == "warn":
		Sfx.play("question")
	if main and main.phase == main.Phase.DAY:
		ticker_label.text = text
	toast.visible = true
	toast.modulate = Color(1, 1, 1, 0)
	toast.reset_size()
	toast.position.x = (root.size.x - toast.size.x) / 2.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.15)
	_toast_tween.tween_interval(2.4)
	_toast_tween.tween_property(toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(func(): toast.visible = false)

func _on_open_shop() -> void:
	if not Game.food_on_sale():
		var any_food_unlocked_off := false
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["kind"] == "food" and Game.menu[id]["unlocked"] and not Game.menu[id]["enabled"]:
				any_food_unlocked_off = true
		if any_food_unlocked_off:
			_toast(tr("ui.no_food"), "error")
			open_panel("menu")
		else:
			_toast(tr("ui.buy_first"), "error")
			open_panel("supplies")
		return
	Sfx.play("confirm")
	main.start_day()

## Simple modal with a title, a few lines and one button (reuses the report overlay).
func show_dialog(title: String, lines: Array, button: String) -> void:
	for c in report_body.get_children():
		c.queue_free()
	report_body.add_child(_label(title, "Title"))
	for line in lines:
		var l := _label(String(line), "")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		report_body.add_child(l)
	report_body.add_child(_spacer(false))
	var ok := _button(button, "Primary", Vector2(220, 64))
	ok.pressed.connect(func():
		Sfx.play("confirm")
		report_dim.visible = false)
	var foot := HBoxContainer.new()
	foot.add_child(_spacer())
	foot.add_child(ok)
	report_body.add_child(foot)
	_apply_safe_area()
	report_dim.visible = true

# ================================================================= panels

func _toggle_panel(id: String) -> void:
	if current_panel == id:
		close_panel()
	else:
		open_panel(id)

func open_panel(id: String) -> void:
	Sfx.play("open")
	current_panel = id
	for k in tabs:
		tabs[k].button_pressed = (k == id)
	panel_title.text = tr(PANELS[id])
	_apply_safe_area()
	panel_dim.visible = true
	_rebuild_panel()
	panel_scroll.scroll_vertical = 0

func close_panel() -> void:
	if current_panel != "":
		Sfx.play("close")
	current_panel = ""
	for k in tabs:
		tabs[k].button_pressed = false
	panel_dim.visible = false

func _rebuild_panel() -> void:
	var scroll := panel_scroll.scroll_vertical
	for c in panel_body.get_children():
		panel_body.remove_child(c)
		c.queue_free()
	match current_panel:
		"supplies": _fill_supplies()
		"menu": _fill_menu()
		"place": _fill_place()
		"upgrades": _fill_upgrades()
		"promote": _fill_promote()
	await get_tree().process_frame
	panel_scroll.scroll_vertical = scroll

func _needed_ingredients() -> Array:
	var out := []
	for id in Data.MENU_ITEMS:
		if not Game.menu[id]["unlocked"]:
			continue
		for ing in Data.MENU_ITEMS[id]["ingredients"]:
			if not out.has(ing) and Game.ingredient_available(ing):
				out.append(ing)
	var ordered := []
	for ing in Data.INGREDIENTS:
		if out.has(ing):
			ordered.append(ing)
	return ordered

func _fill_supplies() -> void:
	var hint := tr("ui.s_hint") % int(Game.spoil_rate("chicken") * 100)
	if not Game.has_upgrade("fridge2"):
		hint += tr("ui.s_hint_fridge") % int(float(Data.UPGRADES["fridge"]["spoil_meat"]) * 100)
	else:
		hint += "."
	if not Game.history.is_empty():
		var last: Dictionary = Game.history.back()
		hint += tr("ui.s_yesterday") % int(last["served"])
	panel_body.add_child(_label(hint, "Muted"))
	var can := []
	for id in Data.MENU_ITEMS:
		if Game.is_on_sale(id):
			can.append("%d %s" % [Game.portions_possible(id), tr(Data.MENU_ITEMS[id]["name"])])
	panel_body.add_child(_label(tr("ui.s_can_make") % (", ".join(can) if not can.is_empty() else tr("ui.r_nothing")), "Heading"))
	var expect := Game.expected_customers()
	panel_body.add_child(_label(tr("ui.s_expect") % [Loc.ltr("%d-%d" % [int(expect * 0.8), int(expect * 1.2)]), tr(Data.WEATHER[Game.forecast]["name"])], "Muted"))
	for ing in _needed_ingredients():
		var def: Dictionary = Data.INGREDIENTS[ing]
		var v := _item_card(Icons.model_icon(def["model"]), tr(def["name"]), "", 64)
		var stock := tr("ui.s_stock") % [int(Game.inventory.get(ing, 0)), tr(def["unit"])]
		var spoil := Game.spoil_rate(ing)
		if spoil >= 0.3:
			stock += "   ·   " + tr("ui.s_spoils") % int(spoil * 100)
		elif spoil > 0.0:
			stock += "   ·   " + tr("ui.s_loses") % int(spoil * 100)
		v.add_child(_label(stock, "Muted"))
		var packs: Array = def["packs"]
		for i in range(packs.size()):
			var text := "%s\n%s" % [Loc.ltr("+%d" % int(packs[i][0])), Loc.money(float(packs[i][1]))]
			v.get_parent().add_child(_buy_button(text, float(packs[i][1]), Game.buy_pack.bind(ing, i), 118, ""))

func _quality_text(q: float) -> String:
	if q >= 1.1:
		return tr("ui.q_legendary")
	if q >= 0.95:
		return tr("ui.q_excellent")
	if q >= 0.82:
		return tr("ui.q_good")
	if q >= 0.7:
		return tr("ui.q_okay")
	if q >= 0.55:
		return tr("ui.q_poor")
	return tr("ui.q_awful")

func _fill_menu() -> void:
	panel_body.add_child(_label(tr("ui.m_hint"), "Muted"))
	for group in Data.MENU_GROUPS:
		panel_body.add_child(_label(tr(group[1]), "Heading"))
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["kind"] == group[0]:
				_menu_card(id)

func _menu_card(id: String) -> void:
	var def: Dictionary = Data.MENU_ITEMS[id]
	var m: Dictionary = Game.menu[id]
	var v := _item_card(Icons.model_icon(def["model"]), "", tr(def["desc"]), 80)
	v.add_theme_constant_override("separation", 6)
	# name row with the on/off switch
	var head := HBoxContainer.new()
	v.add_child(head)
	v.move_child(head, 0)
	head.add_child(_label(tr(def["name"]), "Heading"))
	if m["unlocked"]:
		var cb := CheckButton.new()
		cb.text = tr("ui.m_on") if m["enabled"] else tr("ui.m_off")
		cb.button_pressed = m["enabled"]
		cb.focus_mode = Control.FOCUS_NONE
		if not m["enabled"]:
			cb.add_theme_color_override("font_color", UiTheme.RED)
		cb.toggled.connect(func(on: bool):
			Sfx.play("toggle")
			Game.set_enabled(id, on))
		head.add_child(cb)
	if not m["unlocked"]:
		if not Game.item_available(id):
			v.add_child(_locked_button(tr("ui.locked_by") % tr(Data.UPGRADES[def["requires"]]["name"]), 260))
		else:
			v.add_child(_buy_button(tr("ui.m_add") % Loc.money(float(def["unlock_cost"])), float(def["unlock_cost"]), Game.unlock_item.bind(id), 260))
		return
	# price + cost + quality
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	v.add_child(pr)
	_stepper(pr, tr("ui.m_price"), Loc.money(float(m["price"])), 110, "Big",
		func(d: int): Game.set_price(id, float(Game.menu[id]["price"]) + d))
	var q := Game.quality(id)
	pr.add_child(_label(tr("ui.m_cost") % [Loc.money(Game.unit_cost(id)), _quality_text(q)], "Small"))
	var bar := ProgressBar.new()
	bar.min_value = 0.3
	bar.max_value = 1.3
	bar.value = q
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	v.add_child(bar)
	# recipe
	if def["recipe"]:
		var rr := HBoxContainer.new()
		rr.add_theme_constant_override("separation", 14)
		v.add_child(rr)
		for key in Data.RECIPE_SLIDERS:
			var g := HBoxContainer.new()
			g.add_theme_constant_override("separation", 4)
			rr.add_child(g)
			_stepper(g, tr(Data.RECIPE_SLIDERS[key]["name"]), str(int(m["recipe"][key])), 34, "Heading",
				func(d: int): Game.set_recipe(id, key, int(Game.menu[id]["recipe"][key]) + d))
	# enhancements
	var enh: Array = def["enhance"]
	var level := int(m["level"])
	var er := HBoxContainer.new()
	er.add_theme_constant_override("separation", 10)
	v.add_child(er)
	var owned := []
	for i in range(level):
		owned.append(tr(enh[i]["name"]))
	er.add_child(_label((tr("ui.m_upgrades") % ", ".join(owned)) if not owned.is_empty() else tr("ui.m_no_upgrades"), "Small"))
	if level < enh.size():
		var nxt: Dictionary = enh[level]
		er.add_child(_buy_button("%s  -  %s" % [tr(nxt["name"]), Loc.money(float(nxt["cost"]))], float(nxt["cost"]), Game.enhance_item.bind(id), 240, ""))
	else:
		er.add_child(_label(tr("ui.m_full"), "Money"))

func _fill_place() -> void:
	panel_body.add_child(_label(tr("ui.p_hint"), "Muted"))
	for id in Game.stage_locations():
		var def: Dictionary = Data.LOCATIONS[id]
		var v := _item_card(null, tr(def["name"]), tr(def["desc"]))
		v.add_theme_constant_override("separation", 4)
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 8)
		chips.add_theme_constant_override("v_separation", 6)
		v.add_child(chips)
		chips.add_child(_chip((tr("ui.p_rent") % Loc.money(float(def["rent"]))) if float(def["rent"]) > 0 else tr("ui.p_free"), null, true))
		var t := float(def["traffic"])
		var words := tr("ui.t_low") if t < 0.7 else (tr("ui.t_medium") if t < 1.0 else (tr("ui.t_high") if t < 1.3 else tr("ui.t_vhigh")))
		chips.add_child(_chip(tr("ui.p_traffic") % words, null, true))
		var hrs: Array = Data.location_hours(id)
		chips.add_child(_chip(tr("ui.p_open") % Loc.ltr("%02d:00 - %02d:00" % [int(hrs[0]), int(hrs[1])]), null, true))
		var comp := float(def.get("competition", 0.0))
		if comp > 0.0:
			var cc := _chip(tr("ui.p_competition") % (tr("ui.c_fierce") if comp >= 0.65 else tr("ui.c_high")), null, true)
			cc.get_child(0).get_child(0).add_theme_color_override("font_color", UiTheme.RED)
			chips.add_child(cc)
			chips.add_child(_chip(tr("ui.p_promo") % float(def.get("promo_power", 1.0)), null, true))
		var tier := int(def.get("vehicle", 0))
		var vdef: Dictionary = Data.VEHICLES[Data.vehicle_for_tier(tier)]
		if tier > 0:
			chips.add_child(_chip(tr(vdef["name"]), Icons.model_icon(vdef["icon"]), true))
		var b: Button
		if Game.location == id:
			b = _locked_button(tr("ui.p_here"), 200)
		elif not Game.location_unlocked(id):
			b = _locked_button(tr("ui.p_needs") % (float(def["unlock_pop"]) * 5.0), 200)
		elif not Game.location_vehicle_ok(id):
			b = _locked_button(tr("ui.locked_by") % tr(vdef["name"]), 220)
		else:
			b = _button(tr("ui.p_move"), "Primary", Vector2(200, 56))
			b.pressed.connect(func():
				if Game.set_location(id):
					Sfx.play("confirm")
					main.world.set_location(id)
					main.world.set_time(Data.location_hours(id)[0], Game.forecast))
		_card_action(v, b)

func _fill_upgrades() -> void:
	panel_body.add_child(_label(tr("ui.u_hint"), "Muted"))
	panel_body.add_child(_label(tr("ui.veh_title"), "Heading"))
	for id in Data.VEHICLES:
		var def: Dictionary = Data.VEHICLES[id]
		var v := _item_card(Icons.model_icon(def["icon"]), tr(def["name"]), tr(def["desc"]))
		var reach := []
		for lid in Game.stage_locations():
			if int(Data.LOCATIONS[lid].get("vehicle", 0)) == int(def["tier"]):
				reach.append(tr(Data.LOCATIONS[lid]["name"]))
		v.add_child(_label(tr("ui.veh_reach") % ", ".join(reach), "Small"))
		var b: Button
		if Game.vehicle == id:
			b = _locked_button(tr("ui.veh_current"))
		elif int(def["tier"]) < Game.vehicle_tier():
			b = _locked_button(tr("ui.u_owned"))
		else:
			b = _buy_button(tr("ui.u_buy") % Loc.money(float(def["cost"])), float(def["cost"]), Game.buy_vehicle.bind(id))
			b.disabled = b.disabled or int(def["tier"]) > Game.vehicle_tier() + 1
		_card_action(v, b)
	panel_body.add_child(_label(tr("ui.upgrades"), "Heading"))
	for id in Data.UPGRADES:
		var def: Dictionary = Data.UPGRADES[id]
		var v := _item_card(Icons.model_icon(def["icon"]), tr(def["name"]), tr(def["desc"]))
		var b: Button
		if Game.has_upgrade(id):
			b = _locked_button(tr("ui.u_owned"))
		elif def.has("requires") and not Game.has_upgrade(def["requires"]):
			b = _locked_button(tr("ui.locked_by") % tr(Data.UPGRADES[def["requires"]]["name"]), 220)
		elif int(def.get("requires_vehicle", 0)) > Game.vehicle_tier():
			b = _locked_button(tr("ui.locked_by") % tr(Data.VEHICLES[Data.vehicle_for_tier(int(def["requires_vehicle"]))]["name"]), 220)
		else:
			b = _buy_button(tr("ui.u_buy") % Loc.money(float(def["cost"])), float(def["cost"]), Game.buy_upgrade.bind(id))
		_card_action(v, b)

func _fill_promote() -> void:
	panel_body.add_child(_label(tr("ui.a_hint"), "Muted"))
	var eff: Label
	if Game.competition() > 0.0:
		eff = _label(tr("ui.a_effect") % [Game.promo_power(), int(round(Game.competition_loss() * 100.0))], "Heading")
		eff.add_theme_color_override("font_color", UiTheme.RED if Game.competition_loss() > 0.2 else UiTheme.GREEN_DARK)
	else:
		eff = _label(tr("ui.a_effect_none") % Game.promo_power(), "Heading")
	panel_body.add_child(eff)
	for id in Data.MARKETING:
		var def: Dictionary = Data.MARKETING[id]
		var v := _item_card(Icons.model_icon(def["icon"]), tr(def["name"]), tr(def["desc"]))
		var b: Button
		if Game.marketing.has(id):
			b = _locked_button(tr("ui.a_active") % int(Game.marketing[id]), 220)
		else:
			b = _buy_button(tr("ui.a_start") % Loc.money(float(def["cost"])), float(def["cost"]), Game.start_marketing.bind(id), 220)
		_card_action(v, b)

# ================================================================= card helpers

## A card with an optional icon, a title and a description. Returns the text column so
## callers can add rows; the card's HBox is the column's parent for side buttons.
func _item_card(icon_tex: Texture2D, title: String, desc: String, icon_size: int = 72) -> VBoxContainer:
	var card := _card()
	panel_body.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	if icon_tex:
		var ic := _icon(icon_tex, icon_size)
		ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	if title != "":
		v.add_child(_label(title, "Heading"))
	if desc != "":
		v.add_child(_label(desc, "Muted"))
	return v

## Puts the card's action button beside the text column, vertically centred.
func _card_action(v: VBoxContainer, b: Button) -> void:
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.get_parent().add_child(b)

func _locked_button(text: String, width: float = 180.0) -> Button:
	var b := _button(text, "Ghost", Vector2(width, 56))
	b.disabled = true
	return b

## A buy button: disabled when unaffordable; `action` returns true when the purchase went through.
func _buy_button(text: String, cost: float, action: Callable, width: float = 180.0, variation: String = "Primary") -> Button:
	var b := _button(text, variation, Vector2(width, 56 if variation == "Primary" else 60))
	b.disabled = cost > Game.money
	b.pressed.connect(func():
		if action.call():
			Sfx.play("buy"))
	return b

## label  [-]  value  [+]   with on_delta.call(-1 / +1).
func _stepper(parent: Container, label: String, value: String, value_w: float, variation: String, on_delta: Callable) -> void:
	var nl := _label(label, "Muted")
	nl.size_flags_horizontal = 0
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(nl)
	for d in [-1, 1]:
		if d == 1:
			var vl := _label(value, variation, HORIZONTAL_ALIGNMENT_CENTER)
			vl.custom_minimum_size = Vector2(value_w, 0)
			vl.size_flags_horizontal = 0
			parent.add_child(vl)
		var b := _button("-" if d < 0 else "+", "Ghost", Vector2(56, 52))
		b.pressed.connect(func():
			Sfx.play("tick")
			on_delta.call(d))
		parent.add_child(b)
