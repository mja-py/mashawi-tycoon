extends CanvasLayer
## All 2D UI: top bar, prep tabs + panels, day controls, end-of-day report, title screen.
## Built in code so the layout stays touch-friendly at any phone aspect ratio.

var main: Node
var fade_rect: ColorRect
var _fade_tween: Tween
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
var skip_button: Button
var live_label: Label
var ticker_label: Label
var panel_dim: PanelContainer
var panel: PanelContainer
var panel_title: Label
var stock_button: Button
const TouchScroll := preload("res://scripts/ui/touch_scroll.gd")
const CardRoll := preload("res://scripts/ui/card_roll.gd")
const MenuArt := preload("res://scripts/ui/menu_art.gd")

var panel_scroll: ScrollContainer
var panel_roll: CardRoll
var _fps_label: Label
var panel_body: VBoxContainer
## Filter chips under the panel title (menu groups); hidden for the other panels.
var panel_chips: HBoxContainer
## Cards of the open panel are laid out in a grid: two columns on wide screens.
var panel_grid: GridContainer
var menu_group := "food"
var selected_dish := ""
var _browse_dish := ""
var _browse_place := ""
var _roll_ids: Array[String] = []
var current_panel := ""
## Width (logical px) from which panels show two columns of cards.
const TWO_COLUMNS_FROM := 1100.0
var report_dim: PanelContainer
var report_panel: PanelContainer
var report_body: VBoxContainer
var title_screen: Control
var title_card: PanelContainer
var toast: PanelContainer
var toast_label: Label
var continue_btn: Button
var _toast_tween: Tween
var _panel_tween: Tween
var _report_tween: Tween
var _money_tween: Tween
var _last_money := NAN
var _shown_money := 0.0
var _title_shown := false
var banner: PanelContainer
var banner_label: Label
var _banner_tween: Tween
var _refreshing := false

const PANELS := {
	"supplies": "ui.supplies", "menu": "ui.menu", "place": "ui.place", "build": "ui.build", "promote": "ui.promote", "goals": "ui.goals",
}

func _ready() -> void:
	_build_all()
	if DevTools.has("fps"):
		_build_fps_overlay()
	get_viewport().size_changed.connect(_apply_safe_area)
	Game.changed.connect(_refresh)
	Game.notify.connect(_toast)
	Game.goal_claimed.connect(_on_goal_claimed)
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
	_build_title()
	_build_report() # above the title so its dialogs (new-game confirm) show over it
	_build_toast()
	_build_fade()

## Rebuild every control in the new language and direction (only offered on the title screen).
func _on_language_changed() -> void:
	current_panel = ""
	root.queue_free()
	_build_all()
	if main.world:
		main.world.reload()
	show_title()
	_refresh()

## Full-screen curtain for scene rebuilds (new place, bigger plot): fade out, swap, fade in.
func _build_fade() -> void:
	fade_rect = ColorRect.new()
	fade_rect.color = UiTheme.NIGHT_DARK
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.visible = false
	root.add_child(fade_rect)

func fade_through(action: Callable, out_dur: float = 0.18, in_dur: float = 0.32) -> void:
	if _fade_tween:
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.modulate.a = 0.0
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "modulate:a", 1.0, out_dur).set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_callback(action)
	_fade_tween.tween_property(fade_rect, "modulate:a", 0.0, in_dur).set_trans(Tween.TRANS_SINE)
	_fade_tween.tween_callback(func(): fade_rect.visible = false)

## `--fps` dev flag: frame rate and draw calls in the top-left corner (web: `?dev=--fps`).
func _build_fps_overlay() -> void:
	_fps_label = Label.new()
	_fps_label.position = Vector2(8, 90)
	_fps_label.add_theme_color_override("font_color", Color.YELLOW)
	_fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_fps_label)

func _process(_delta: float) -> void:
	if OS.has_feature("web") and DevTools.has("uitest") and Engine.get_process_frames() % 15 == 0:
		_publish_menu_targets()
	if _fps_label and Engine.get_process_frames() % 15 == 0:
		_fps_label.text = "%d fps  %d draws  %dx%d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]

## Dev-only geometry for real browser taps across phone sizes and RTL/LTR layouts.
func _menu_target(b: Button, id: String) -> Button:
	if DevTools.has("uitest"):
		b.set_meta("menu_target", id)
	return b

func _publish_menu_targets() -> void:
	var targets := {}
	var vp := root.get_viewport_rect().size
	for node in panel.find_children("*", "Button", true, false):
		var b := node as Button
		if not b.is_visible_in_tree() or not b.has_meta("menu_target"):
			continue
		var center := b.get_global_rect().get_center()
		if panel_scroll.is_ancestor_of(b) and not panel_scroll.get_global_rect().encloses(b.get_global_rect()):
			continue
		if panel_roll.is_ancestor_of(b) and not panel_roll.is_focused_control(b):
			continue
		targets[b.get_meta("menu_target")] = {"x": center.x / vp.x, "y": center.y / vp.y, "disabled": b.disabled}
	JavaScriptBridge.eval("window.godotMenuTargets = " + JSON.stringify(targets))

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
	elif OS.has_feature("web"):
		# The HTML shell measures the CSS safe-area insets (notch, home bar) in canvas pixels.
		var win := DisplayServer.window_get_size()
		var r: Variant = JavaScriptBridge.eval("window.godotSafeInsets ? window.godotSafeInsets() : ''")
		if win.x > 0 and win.y > 0 and r is String and String(r) != "":
			var ins := String(r).split(",")
			if ins.size() == 4:
				var sx := vp.x / float(win.x)
				var sy := vp.y / float(win.y)
				root.offset_top = maxf(0.0, float(ins[0])) * sy
				root.offset_right = -maxf(0.0, float(ins[1])) * sx
				root.offset_bottom = -maxf(0.0, float(ins[2])) * sy
				root.offset_left = maxf(0.0, float(ins[3])) * sx
	var w := vp.x - root.offset_left + root.offset_right
	var h := vp.y - root.offset_top + root.offset_bottom
	# Panels use the whole width between the bars: phones are wide but short.
	if panel:
		panel.custom_minimum_size = Vector2(w - 16.0, maxf(300.0, h - 60.0 - 84.0 - 8.0))
	if report_panel:
		report_panel.custom_minimum_size = Vector2(minf(1100.0, w - 16.0), maxf(300.0, h - 16.0))

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
	b.button_down.connect(_pulse.bind(b))
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
	money_label.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
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
		var b := _button("", "Tab", Vector2(108, 64))
		b.tooltip_text = tr(PANELS[id])
		b.toggle_mode = true
		b.pressed.connect(func(): _toggle_panel(id))
		h.add_child(b)
		tabs[id] = b
		var face := VBoxContainer.new()
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		face.alignment = BoxContainer.ALIGNMENT_CENTER
		face.add_theme_constant_override("separation", 0)
		b.add_child(face)
		var glyph := MenuArt.new("tab:" + id)
		glyph.custom_minimum_size.y = 24.0
		face.add_child(glyph)
		var caption := _label(tr(PANELS[id]), "Light", HORIZONTAL_ALIGNMENT_CENTER)
		caption.add_theme_font_size_override("font_size", 16)
		face.add_child(caption)
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
	skip_button = skip
	skip.pressed.connect(func():
		Sfx.play("click")
		main.skip_day())
	h.add_child(skip)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(v)
	live_label = _label(tr("ui.live") % [0, Loc.money(0), 0, 0, 0], "Light", HORIZONTAL_ALIGNMENT_RIGHT)
	v.add_child(live_label)
	ticker_label = _label("", "Muted", HORIZONTAL_ALIGNMENT_RIGHT)
	ticker_label.add_theme_color_override("font_color", UiTheme.GOLD_LIGHT)
	v.add_child(ticker_label)

func _build_panel() -> void:
	panel_dim = PanelContainer.new()
	panel_dim.theme_type_variation = "Dim"
	panel_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel_dim.offset_top = 60
	panel_dim.offset_bottom = -84
	panel_dim.visible = false
	panel_dim.gui_input.connect(func(ev: InputEvent):
		# mouse-wheel / trackpad scrolling bubbles up through the panel as button events, so only
		# a real tap on the backdrop closes the panel
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT \
				and not panel.get_global_rect().has_point(ev.global_position):
			close_panel())
	root.add_child(panel_dim)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel_dim.add_child(center)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 540)
	center.add_child(panel)
	_lattice_bg(panel)
	_apply_safe_area()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var head_box := PanelContainer.new()
	head_box.theme_type_variation = "Head"
	v.add_child(head_box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head_box.add_child(head)
	panel_title = _label(tr("ui.supplies"), "Heading")
	panel_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(panel_title)
	stock_button = _button("", "Primary", Vector2(180, 60))
	stock_button.visible = false
	stock_button.pressed.connect(func():
		if Game.stock_for_today():
			Sfx.play("confirm"))
	head.add_child(stock_button)
	var close := _button(tr("ui.close"), "Ghost", Vector2(110, 48))
	close.pressed.connect(close_panel)
	head.add_child(close)
	panel_chips = HBoxContainer.new()
	panel_chips.add_theme_constant_override("separation", 8)
	panel_chips.visible = false
	v.add_child(panel_chips)
	panel_scroll = TouchScroll.new()
	panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(panel_scroll)
	panel_body = VBoxContainer.new()
	panel_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel_body.add_theme_constant_override("separation", 10)
	panel_scroll.add_child(panel_body)
	panel_roll = CardRoll.new()
	panel_roll.hide()
	panel_roll.index_changed.connect(func(index: int):
		if current_panel == "menu":
			_browse_dish = _roll_ids[index]
		elif current_panel == "place":
			_browse_place = _roll_ids[index])
	v.add_child(panel_roll)

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
	_lattice_bg(report_panel)
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
	_lattice_bg(p)
	title_card = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	# The title reads like the painted name above a neighbourhood cafeteria.
	var band := PanelContainer.new()
	band.theme_type_variation = "Plain"
	v.add_child(band)
	var logo := _label(tr("ui.title"), "Title", HORIZONTAL_ALIGNMENT_CENTER)
	logo.add_theme_font_size_override("font_size", 64)
	logo.add_theme_color_override("font_color", UiTheme.INK)
	logo.add_theme_color_override("font_outline_color", UiTheme.NIGHT_DARK)
	logo.add_theme_constant_override("outline_size", 0)
	band.add_child(logo)
	v.add_child(_divider())
	v.add_child(_label(tr("ui.subtitle"), "Muted", HORIZONTAL_ALIGNMENT_CENTER))
	var new_btn := _button(tr("ui.new_game"), "Primary", Vector2(0, 64))
	new_btn.pressed.connect(func():
		Sfx.play("confirm")
		var s: Dictionary = Game.save_summary()
		if s.is_empty():
			main.new_game()
		else:
			# don't let a stray tap wipe days of progress
			show_dialog(tr("ui.new_game"), [tr("ui.ng_confirm") % int(s["day"])], tr("ui.ng_yes"),
				func(): main.new_game(), tr("ui.cancel")))
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
	_fade_in(title_screen, 0.35)
	if _title_shown:
		_pop_in(title_card, 0.4)
	_title_shown = true
	var s: Dictionary = Game.save_summary()
	continue_btn.visible = not s.is_empty()
	if not s.is_empty():
		continue_btn.text = tr("ui.continue_day") % [int(s["day"]), Loc.money(float(s["money"]))]

func show_prep() -> void:
	title_screen.visible = false
	report_dim.visible = false
	top_bar.visible = true
	prep_bar.visible = true
	day_bar.visible = false
	clock_chip.visible = false
	close_panel()
	_slide_in(top_bar, -1)
	_slide_in(prep_bar, 1)
	_refresh()

func show_day() -> void:
	skip_button.disabled = false
	skip_button.text = tr("ui.skip")
	for b in speed_buttons.values():
		b.disabled = false
	close_panel()
	title_screen.visible = false
	report_dim.visible = false
	top_bar.visible = true
	prep_bar.visible = false
	day_bar.visible = true
	clock_chip.visible = true
	_slide_in(day_bar, 1)
	_banner("%s  ·  %s" % [tr("ui.day") % Game.day, tr(Game.loc()["name"])])
	ticker_label.text = ""
	_set_speed(1.0)
	_refresh()

func show_finishing() -> void:
	skip_button.disabled = true
	skip_button.text = tr("ui.finishing")
	for b in speed_buttons.values():
		b.disabled = true
		b.button_pressed = false

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
	var cols_scroll: ScrollContainer = TouchScroll.new()
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
	_row(g1, tr("ui.r_served"), str(r["served"]), UiTheme.GOOD)
	if int(r.get("dine_in", 0)) > 0:
		_row(g1, tr("ui.r_dine_in"), str(r["dine_in"]), UiTheme.GOOD)
	_row(g1, tr("ui.r_left_wait"), str(r["left_wait"]), UiTheme.BAD if r["left_wait"] > 0 else UiTheme.INK)
	_row(g1, tr("ui.r_left_full"), str(r["queue_full"]), UiTheme.BAD if r["queue_full"] > 0 else UiTheme.INK)
	_row(g1, tr("ui.r_sold_out"), str(r["sold_out"]), UiTheme.BAD if r["sold_out"] > 0 else UiTheme.INK)
	if int(r.get("lost_rival", 0)) > 0:
		_row(g1, tr("ui.r_lost_rival"), str(r["lost_rival"]), UiTheme.BAD)
	if int(r.get("too_pricey", 0)) > 0:
		_row(g1, tr("ui.r_too_pricey"), str(r["too_pricey"]), UiTheme.BAD)
	_row(g1, tr("ui.r_satisfaction"), "%d%%" % int(round(float(r["satisfaction"]) * 100.0)))
	var pd := float(r["pop_delta"])
	_row(g1, tr("ui.r_reputation"), (tr("ui.r_stars") % Loc.ltr("%+.2f" % (pd * 5.0))), UiTheme.GOOD if pd >= 0 else UiTheme.BAD)
	var ld := float(r.get("local_delta", 0.0))
	_row(g1, tr("ui.r_local"), (tr("ui.r_stars") % Loc.ltr("%+.2f" % (ld * 5.0))), UiTheme.GOOD if ld >= 0 else UiTheme.BAD)
	var bn := String(r.get("bottleneck", ""))
	if bn != "" and bn != "arrivals":
		var bl := _label(tr("ui.r_bottleneck") % _station_name(bn), "Small")
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bl.add_theme_color_override("font_color", UiTheme.GOLD)
		bl.add_theme_font_override("font", UiTheme.bold())
		v1.add_child(bl)
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
	_row(g2, tr("ui.r_revenue"), Loc.money(r["revenue"]), UiTheme.GOOD)
	_row(g2, tr("ui.r_cogs"), Loc.money(float(r["cogs"])), UiTheme.BAD)
	_row(g2, tr("ui.r_rent"), Loc.money(float(r["rent"])), UiTheme.BAD)
	if float(r["wages"]) > 0:
		_row(g2, tr("ui.r_wages"), Loc.money(float(r["wages"])), UiTheme.BAD)
	var sp: Dictionary = r["spoiled"]
	if not sp.is_empty():
		var parts := []
		for ing in sp:
			parts.append("%d %s" % [sp[ing], tr(Data.INGREDIENTS[ing]["name"])])
		_row(g2, tr("ui.r_spoiled") % ", ".join(parts), Loc.money(float(r["spoil_cost"])), UiTheme.BAD)
	var profit := float(r["profit"])
	var pl := _row(g2, tr("ui.r_profit"), Loc.money(profit), UiTheme.GOOD if profit >= 0 else UiTheme.BAD)
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
	_show_report_overlay()
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
	if not is_nan(_last_money) and not is_equal_approx(_last_money, Game.money):
		_money_pop(Game.money > _last_money)
	else:
		money_label.text = Loc.money(Game.money)
		_shown_money = Game.money
	_last_money = Game.money
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
	live_label.text = tr("ui.live") % [stats.get("served", 0), Loc.money(stats.get("revenue", 0.0)), stats.get("queue", 0), stats.get("kitchen", 0), stats.get("seated", 0)]

func _set_speed(s: float) -> void:
	for k in speed_buttons:
		speed_buttons[k].button_pressed = is_equal_approx(k, s)
	if main:
		main.set_speed(s)

func _toast(text: String, kind: String = "info") -> void:
	var glyph := "\u221a  " if kind == "info" else ("\u00d7  " if kind == "error" else "!  ")
	toast_label.text = glyph + text
	if kind == "error":
		Sfx.play("error")
	elif kind == "warn":
		Sfx.play("question")
	if main and main.phase == main.Phase.DAY:
		ticker_label.text = text
	toast.visible = true
	toast.modulate = Color(1, 1, 1, 0)
	toast.reset_size()
	toast.position = Vector2((root.size.x - toast.size.x) / 2.0, 58.0)
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween().set_parallel(true)
	_toast_tween.tween_property(toast, "modulate:a", 1.0, 0.18)
	_toast_tween.tween_property(toast, "position:y", 74.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_toast_tween.set_parallel(false)
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
## `on_ok` runs after the main button closes it; `alt` adds a second (ghost) button that
## just closes the dialog (or runs `on_alt`).
func show_dialog(title: String, lines: Array, button: String, on_ok: Callable = Callable(), alt: String = "", on_alt: Callable = Callable()) -> void:
	for c in report_body.get_children():
		c.queue_free()
	report_body.add_child(_label(title, "Title"))
	for line in lines:
		var l := _label(String(line), "")
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		report_body.add_child(l)
	report_body.add_child(_spacer(false))
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 12)
	foot.add_child(_spacer())
	if alt != "":
		var cancel := _button(alt, "Ghost", Vector2(180, 64))
		cancel.pressed.connect(func():
			Sfx.play("close")
			report_dim.visible = false
			if on_alt.is_valid():
				on_alt.call())
		foot.add_child(cancel)
	var ok := _button(button, "Primary", Vector2(220, 64))
	ok.pressed.connect(func():
		Sfx.play("confirm")
		report_dim.visible = false
		if on_ok.is_valid():
			on_ok.call())
	foot.add_child(ok)
	report_body.add_child(foot)
	_apply_safe_area()
	# a dialog is a short card, not the full-height report sheet
	report_panel.custom_minimum_size = Vector2(minf(720.0, report_panel.custom_minimum_size.x), 0.0)
	_show_report_overlay()

# ================================================================= panels

func _toggle_panel(id: String) -> void:
	if current_panel == id:
		close_panel()
	else:
		open_panel(id)

func open_panel(id: String) -> void:
	if current_panel != id:
		selected_dish = ""
	Sfx.play("open")
	current_panel = id
	for k in tabs:
		tabs[k].button_pressed = (k == id)
	panel_title.text = tr(PANELS[id])
	_apply_safe_area()
	if tabs.has(id):
		_pulse(tabs[id])
	if _panel_tween:
		_panel_tween.kill()
	panel_dim.visible = true
	panel_dim.modulate.a = 1.0
	# grows up out of the tab bar
	panel.pivot_offset = Vector2(panel.custom_minimum_size.x / 2.0, panel.custom_minimum_size.y)
	panel.scale = Vector2(0.9, 0.9)
	panel.modulate.a = 0.0
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(panel, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_panel_tween.tween_property(panel, "modulate:a", 1.0, 0.16)
	_rebuild_panel(true)
	panel_scroll.scroll_vertical = 0
	if main:
		main._publish_state()

func close_panel() -> void:
	if current_panel != "":
		Sfx.play("close")
	current_panel = ""
	for k in tabs:
		tabs[k].button_pressed = false
	if not panel_dim.visible:
		return
	if main:
		main._publish_state()
	if _panel_tween:
		_panel_tween.kill()
	_panel_tween = create_tween().set_parallel(true)
	_panel_tween.tween_property(panel, "scale", Vector2(0.92, 0.92), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_panel_tween.tween_property(panel, "modulate:a", 0.0, 0.14)
	_panel_tween.tween_property(panel_dim, "modulate:a", 0.0, 0.16)
	_panel_tween.set_parallel(false)
	_panel_tween.tween_callback(func():
		panel_dim.visible = false
		panel_dim.modulate.a = 1.0
		panel.scale = Vector2.ONE
		panel.modulate.a = 1.0)

## `animate` staggers the cards in (used when the panel opens or the filter changes, not on
## every refresh after a purchase).
func _rebuild_panel(animate: bool = false) -> void:
	var scroll := panel_scroll.scroll_vertical
	for c in panel_body.get_children():
		panel_body.remove_child(c)
		c.queue_free()
	panel_grid = null
	stock_button.visible = current_panel == "supplies"
	panel_chips.visible = current_panel == "menu"
	panel_roll.visible = current_panel == "place" or (current_panel == "menu" and selected_dish.is_empty())
	panel_scroll.visible = not panel_roll.visible
	for c in panel_chips.get_children():
		panel_chips.remove_child(c)
		c.queue_free()
	match current_panel:
		"supplies": _fill_supplies()
		"menu": _fill_menu()
		"place": _fill_place()
		"build": _fill_build()
		"promote": _fill_promote()
		"goals": _fill_goals()
	await get_tree().process_frame
	panel_scroll.scroll_vertical = scroll
	if animate:
		_stagger_cards()

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
	var plan := Game.daily_stock_plan()
	var cost := float(plan["cost"])
	stock_button.text = tr("ui.stock_today") % Loc.money(cost) if cost > 0.0 else tr("ui.stock_ready")
	stock_button.disabled = cost <= 0.0 or cost > maxf(0.0, Game.money - float(Game.loc()["rent"]) - Game.daily_wages())
	stock_button.tooltip_text = tr("ui.stock_hint")
	var hint := tr("ui.s_hint") % int(Game.spoil_rate("chicken") * 100)
	if Game.station_level("coldbox") < 3:
		hint += tr("ui.s_hint_fridge") % int(float(Data.STATIONS["coldbox"]["spoil_meat"][1]) * 100)
	else:
		hint += "."
	if not Game.history.is_empty():
		var last: Dictionary = Game.history.back()
		hint += tr("ui.s_yesterday") % int(last["served"])
	_hint(hint)
	var can := []
	for id in Data.MENU_ITEMS:
		if Game.is_on_sale(id):
			can.append("%d %s" % [Game.portions_possible(id), tr(Data.MENU_ITEMS[id]["name"])])
	var expect := Game.expected_customers()
	var summary := _label(tr("ui.s_can_make") % (", ".join(can) if not can.is_empty() else tr("ui.r_nothing")), "Small")
	summary.add_theme_font_override("font", UiTheme.bold())
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.add_child(summary)
	_hint(tr("ui.s_expect") % [Loc.ltr("%d-%d" % [int(expect * 0.8), int(expect * 1.2)]), tr(Data.WEATHER[Game.forecast]["name"])])
	for ing in _needed_ingredients():
		var def: Dictionary = Data.INGREDIENTS[ing]
		var v := _item_card(Icons.model_icon(def["model"]), tr(def["name"]), "", 48)
		var stock := tr("ui.s_stock") % [int(Game.inventory.get(ing, 0)), tr(def["unit"])]
		var spoil := Game.spoil_rate(ing)
		if spoil >= 0.3:
			stock += "   ·   " + tr("ui.s_spoils") % int(spoil * 100)
		elif spoil > 0.0:
			stock += "   ·   " + tr("ui.s_loses") % int(spoil * 100)
		v.add_child(_label(stock, "Muted"))
		# the three pack sizes in one row under the text, so a card stays two rows tall
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		v.add_child(row)
		var packs: Array = def["packs"]
		for i in range(packs.size()):
			var text := "%s  ·  %s" % [Loc.ltr("+%d" % int(packs[i][0])), Loc.money(float(packs[i][1]))]
			var b := _buy_button(text, float(packs[i][1]), Game.buy_pack.bind(ing, i), 0, "")
			b.custom_minimum_size = Vector2(0, 60)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(b)

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

func _select_dish(id: String) -> void:
	selected_dish = id
	panel_scroll.scroll_vertical = 0
	_rebuild_panel(true)
	if main:
		main._publish_state()

func _fill_menu() -> void:
	if selected_dish != "" and Data.MENU_ITEMS.has(selected_dish):
		var back := _button(tr("ui.m_back"), "Ghost", Vector2(200, 52))
		_menu_target(back, "back_dishes")
		back.pressed.connect(func(): _select_dish(""))
		panel_chips.add_child(back)
		_menu_detail(selected_dish)
		return
	var groups := {}
	for id in Data.MENU_ITEMS:
		if not Game.item_available(id):
			continue
		var kind: String = Data.MENU_ITEMS[id]["kind"]
		if not groups.has(kind):
			groups[kind] = []
		groups[kind].append(id)
	if not groups.has(menu_group):
		menu_group = "food"
	for group in Data.MENU_GROUPS:
		var gid: String = group[0]
		if not groups.has(gid):
			continue
		var b := _button(tr(group[1]), "Filter", Vector2(0, 48))
		_menu_target(b, "category_" + gid)
		b.toggle_mode = true
		b.button_pressed = gid == menu_group
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(func():
			Sfx.play("switch")
			if menu_group != gid:
				_browse_dish = ""
			menu_group = gid
			_select_dish(""))
		panel_chips.add_child(b)
	_roll_ids.assign(groups.get(menu_group, []))
	panel_roll.configure(_roll_ids.size(), _roll_ids.find(_browse_dish), _dish_roll_card)

## Give most of the card to the art, with a short caption below.
func _roll_card(art_id: String, title: String, value: String) -> PanelContainer:
	var card := _card()
	var frame := UiTheme.flat(UiTheme.CARD, 13, Color("a58258"), 2, 3)
	frame.set_content_margin_all(8.0)
	card.add_theme_stylebox_override("panel", frame)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	card.add_child(body)
	var art := MenuArt.new(art_id)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.custom_minimum_size.y = 94
	body.add_child(art)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	body.add_child(line)
	var name := _label(title, "Heading")
	name.add_theme_font_size_override("font_size", 24)
	name.autowrap_mode = TextServer.AUTOWRAP_OFF
	name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	line.add_child(name)
	if value != "":
		var tag := _label(value, "Money", HORIZONTAL_ALIGNMENT_RIGHT)
		tag.size_flags_horizontal = Control.SIZE_SHRINK_END
		tag.add_theme_font_size_override("font_size", 19)
		line.add_child(tag)
	return card

func _dish_roll_card(index: int) -> PanelContainer:
	var id := _roll_ids[index]
	var def: Dictionary = Data.MENU_ITEMS[id]
	var m: Dictionary = Game.menu[id]
	var value := Loc.money(float(m["price"])) if m["unlocked"] else Loc.money(float(def["unlock_cost"]))
	var card := _roll_card("dish:" + String(def["kind"]), tr(def["name"]), value)
	var body := card.get_child(0)
	var art := body.get_child(0)
	var plate := _icon(Icons.dish_icon(id), 0)
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.add_child(plate)
	var caption := tr("ui.m_edit_dish") if m["unlocked"] else tr("ui.m_view_dish")
	var action := _menu_target(Button.new(), "select_" + id)
	action.flat = true
	action.focus_mode = Control.FOCUS_NONE
	action.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	action.tooltip_text = caption
	action.pressed.connect(func():
		panel_roll.choose(index, func():
			Sfx.play("open")
			_browse_dish = id
			_select_dish(id)))
	card.add_child(action)
	return card

func _menu_sheet() -> VBoxContainer:
	var card := _card()
	panel_body.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	return v

## One dish at a time. Buying, selling, price and recipe have separate readable rows.
func _menu_detail(id: String) -> void:
	var def: Dictionary = Data.MENU_ITEMS[id]
	var m: Dictionary = Game.menu[id]
	var intro := _menu_sheet()
	var hero := HBoxContainer.new()
	hero.add_theme_constant_override("separation", 18)
	intro.add_child(hero)
	hero.add_child(_icon(Icons.dish_icon(id), 112))
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hero.add_child(info)
	info.add_child(_label(tr(def["name"]), "Heading"))
	if not m["unlocked"]:
		info.add_child(_label(tr(def["desc"]), "Muted"))
		if not Game.item_available(id):
			intro.add_child(_locked_button(tr("ui.locked_by") % tr(Data.STATIONS[Game.required_station(def)]["name"])))
		else:
			intro.add_child(_menu_target(_buy_button(tr("ui.m_add") % Loc.money(float(def["unlock_cost"])), float(def["unlock_cost"]), Game.unlock_item.bind(id)), "unlock"))
		return
	info.add_child(_label(tr("ui.m_quality") % _quality_text(Game.quality(id)), "Small"))
	var toggle := _toggle_button(m["enabled"], tr("ui.m_on"), tr("ui.m_off"), func(on: bool): Game.set_enabled(id, on))
	toggle.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hero.add_child(_menu_target(toggle, "on_sale"))
	var pricing := _menu_sheet()
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 12)
	pricing.add_child(price_row)
	var r := Game.price_range(id)
	var price := float(m["price"])
	var price_buttons := _stepper(price_row, tr("ui.m_price"), Loc.money(price), 130, "Big",
		func(d: int): Game.set_price(id, float(Game.menu[id]["price"]) + d), Vector2(64, 60), price > float(r[0]), price < float(r[1]))
	_menu_target(price_buttons[0], "price_down")
	_menu_target(price_buttons[1], "price_up")
	pricing.add_child(_label(tr("ui.m_range_cost") % [Loc.ltr("%d–%d" % [int(r[0]), int(r[1])]), Loc.money(Game.unit_cost(id))], "Muted"))
	if def["recipe"]:
		var recipe := _menu_sheet()
		recipe.add_child(_label(tr("ui.m_house_recipe"), "Heading"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 24)
		flow.add_theme_constant_override("v_separation", 10)
		recipe.add_child(flow)
		for key in Data.RECIPE_SLIDERS:
			var group := VBoxContainer.new()
			group.custom_minimum_size.x = 240
			flow.add_child(group)
			var s: Dictionary = Data.RECIPE_SLIDERS[key]
			group.add_child(_label(tr(s["name"]), "Muted"))
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 10)
			group.add_child(row)
			var cur := int(m["recipe"][key])
			var recipe_buttons := _stepper(row, "", str(cur), 50, "Big",
				func(d: int): Game.set_recipe(id, key, int(Game.menu[id]["recipe"][key]) + d), Vector2(60, 56),
				cur > int(s["min"]), cur < int(s["max"]))
			_menu_target(recipe_buttons[0], "recipe_" + key + "_down")
			_menu_target(recipe_buttons[1], "recipe_" + key + "_up")
	var enh: Array = def["enhance"]
	var level := int(m["level"])
	if level < enh.size():
		var upgrade := _menu_sheet()
		upgrade.add_child(_label(tr("ui.m_make_special"), "Heading"))
		var nxt: Dictionary = enh[level]
		upgrade.add_child(_menu_target(_buy_button("%s  ·  %s" % [tr(nxt["name"]), Loc.money(float(nxt["cost"]))], float(nxt["cost"]), Game.enhance_item.bind(id)), "enhance"))
	else:
		intro.add_child(_label(tr("ui.m_full"), "Money"))


func _fill_place() -> void:
	_roll_ids.clear()
	for id in Game.stage_locations():
		if id == Game.location or (Game.location_unlocked(id) and Game.location_stage_ok(id)):
			_roll_ids.append(id)
	var preferred := _browse_place if _browse_place in _roll_ids else Game.location
	panel_roll.configure(_roll_ids.size(), _roll_ids.find(preferred), _place_roll_card)

func _place_roll_card(index: int) -> PanelContainer:
	var id := _roll_ids[index]
	var def: Dictionary = Data.LOCATIONS[id]
	var rent := float(def["rent"])
	var card := _roll_card(id, tr(def["name"]), (tr("ui.p_rent") % Loc.money(rent)) if rent > 0 else tr("ui.p_free"))
	var body := card.get_child(0)
	var action: Button
	if Game.location == id:
		action = _locked_button(tr("ui.p_here"))
	else:
		action = _button(tr("ui.p_move"), "Primary", Vector2(0, 49))
		action.pressed.connect(func():
			panel_roll.choose(index, func():
				if Game.set_location(id):
					Sfx.play("confirm")
					main.world.set_location(id)
					main.world.set_time(Data.location_hours(id)[0], Game.forecast)))
	action.tooltip_text = tr(def["desc"])
	body.add_child(_menu_target(action, "move_" + id))
	return card

func _station_name(id: String) -> String:
	if Data.STATIONS.has(id):
		return tr(Data.STATIONS[id]["name"])
	return tr("station.seating") if id == "seating" else id

func _fill_build() -> void:
	var sd := Game.stage_def()
	var nxt := Game.next_stage_def()
	var ctx := Game.sim_context()
	var est := Economy.throughput_estimate(ctx)
	# the stage you sell from, and the next one (a full-width card above the station grid)
	panel_grid = null
	var v := _item_card(Icons.model_icon(sd["icon"]), tr(sd["name"]), tr(sd["desc"]), 56)
	panel_grid.columns = 1
	panel_grid = null
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 6)
	v.add_child(chips)
	chips.add_child(_chip(tr("ui.b_fixed") if Game.is_fixed() else tr("ui.b_mobile"), null, true))
	chips.add_child(_chip(tr("ui.b_appeal") % float(sd["appeal"]), null, true))
	chips.add_child(_chip(tr("ui.p_prices") % Data.price_cap_mult(Game.loc(), sd), null, true))
	chips.add_child(_chip(tr("ui.b_line") % Game.queue_capacity(), null, true))
	if float(sd["dine_in"]) > 0.0:
		chips.add_child(_chip(tr("ui.b_dine") % int(round(float(sd["dine_in"]) * 100.0)), null, true))
	if not nxt.is_empty():
		var nl := _label(tr("ui.b_next") % [tr(nxt["name"]), tr(nxt["desc"])], "Small")
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(nl)
		var why := Game.stage_lock_reason()
		if why != "":
			_card_action(v, _locked_button(why, 260))
		else:
			_card_action(v, _buy_button(tr("ui.b_build") % [tr(nxt["name"]), Loc.money(float(nxt["cost"]))], float(nxt["cost"]), Game.buy_stage, 260))
	# where today's customers would get stuck
	var bn: String = est["bottleneck"]
	if bn == "arrivals":
		_hint(tr("ui.b_bn_arrivals"))
	elif bn != "":
		_hint(tr("ui.b_bn") % _station_name(bn))
	else:
		_hint(tr("ui.b_bn_none") % int(round(float(est["served"]))))
	for group in Data.STATION_GROUPS:
		var ids := []
		for id in Data.STATIONS:
			var def: Dictionary = Data.STATIONS[id]
			if def["group"] != group[0] or def.get("virtual", false):
				continue
			if Game.station_available(id) and not def.get("later", false):
				ids.append(id)
		if ids.is_empty():
			continue
		_section(tr(group[1]))
		for id in ids:
			_station_card(id, est)

func _station_card(id: String, est: Dictionary) -> void:
	var def: Dictionary = Data.STATIONS[id]
	var lvl := Game.station_level(id)
	var cap := Game.station_cap(id)
	var v := _item_card(Icons.model_icon(def["icon"]), tr(def["name"]), tr(def["desc"]))
	v.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	var lv := _label(tr("ui.b_level") % [lvl, cap], "Small")
	lv.add_theme_font_override("font", UiTheme.bold())
	row.add_child(lv)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 3)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var segs := mini(cap, 10)
	for i in range(segs):
		var seg := ColorRect.new()
		seg.custom_minimum_size = Vector2(14, 8)
		var filled := float(lvl) / float(cap) * segs > i + 0.01
		seg.color = UiTheme.GOLD if filled else Color(UiTheme.GOLD, 0.2)
		bar.add_child(seg)
	var eff := _label(tr(def["effect"]), "Small")
	eff.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(eff)
	var why := Game.station_lock_reason(id)
	if why != "":
		_card_action(v, _locked_button(why, 230))
		return
	# what one more level would do to today's numbers
	var next := Economy.throughput_estimate(Game.what_if({"stations": {id: lvl + 1}}))
	var gain := float(next["served"]) - float(est["served"])
	var pgain := float(next["profit"]) - float(est["profit"])
	if gain >= 1.0 or pgain >= 5.0:
		var g := _label(tr("ui.b_gain") % [int(round(gain)), Loc.money(pgain)], "Small")
		g.add_theme_color_override("font_color", UiTheme.GOOD)
		v.add_child(g)
	var cost := Game.station_cost(id)
	var text := (tr("ui.b_unlock") % Loc.money(cost)) if lvl == 0 and int(def.get("owned_from", 0)) > 0 else (tr("ui.b_buy_level") % [lvl + 1, Loc.money(cost)])
	_card_action(v, _buy_button(text, cost, Game.buy_station_level.bind(id), 230))

func _fill_goals() -> void:
	var g := Game.current_goal()
	if g.is_empty():
		_hint(tr("ui.g_all_done"))
	else:
		panel_grid = null
		var v := _item_card(null, tr("goal." + String(g["id"])), tr("goal." + String(g["id"]) + ".desc"))
		panel_grid.columns = 1
		panel_grid = null
		var prog := Game.goal_progress()
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = prog
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		v.add_child(bar)
		var reward: Dictionary = g["reward"]
		var rw := tr("ui.g_reward") % Loc.money(float(reward.get("money", 0.0)))
		if reward.has("popularity"):
			rw += "  +" + (tr("ui.r_stars") % Loc.ltr("%.1f" % (float(reward["popularity"]) * 5.0)))
		v.add_child(_label(rw, "Small"))
		if Game.goal_ready():
			var b := _button(tr("ui.g_claim"), "Primary", Vector2(230, 52))
			b.pressed.connect(func():
				if Game.claim_goal():
					Sfx.play("confirm"))
			_card_action(v, b)
		else:
			_card_action(v, _locked_button(tr("ui.g_progress") % int(round(prog * 100.0)), 230))
	if not Game.goals_claimed.is_empty():
		_section(tr("ui.g_done"))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 8)
		flow.add_theme_constant_override("v_separation", 6)
		panel_body.add_child(flow)
		for id in Game.goals_claimed:
			flow.add_child(_chip("\u221a " + tr("goal." + String(id)), null, true))
	_section(tr("ui.x_title"))
	var card := _card()
	panel_body.add_child(card)
	var grid := _grid()
	card.add_child(grid)
	var st: Dictionary = Game.stats
	_row(grid, tr("ui.x_served"), str(Game.total_served))
	_row(grid, tr("ui.x_best_served"), str(int(st["best_day_served"])))
	_row(grid, tr("ui.x_best_profit"), Loc.money(float(st["best_day_profit"])))
	_row(grid, tr("ui.x_total_profit"), Loc.money(float(st["total_profit"])))
	_row(grid, tr("ui.x_days"), str(int(st["days_played"])))
	_row(grid, tr("ui.x_levels"), str(Game.levels_owned()))
	_row(grid, tr("ui.x_stages"), str(int(st["stages_built"])))
	_row(grid, tr("ui.x_places"), str(st["locations_visited"].size()))

func _on_goal_claimed(g: Dictionary) -> void:
	show_dialog(tr(Data.MENTOR), [tr(String(g.get("say", "")))], tr("ui.g_ok"))

func _fill_promote() -> void:
	_hint(tr("ui.a_hint"))
	var eff: Label
	if Game.competition() > 0.0:
		eff = _label(tr("ui.a_effect") % [Game.promo_power(), int(round(Game.competition_loss() * 100.0))], "Heading")
		eff.add_theme_color_override("font_color", UiTheme.BAD if Game.competition_loss() > 0.2 else UiTheme.GOOD)
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

## One-line explanation at the top of a panel.
func _hint(text: String) -> void:
	var l := _label(text, "Muted")
	l.add_theme_font_size_override("font_size", 16)
	panel_body.add_child(l)

## A heading between two groups of cards; the next card starts a fresh grid under it.
func _section(title: String) -> void:
	panel_body.add_child(_label(title, "Heading"))
	panel_grid = null

## The grid the next card goes into: two equal columns on wide screens, one on narrow ones.
func _cards_grid() -> GridContainer:
	if panel_grid == null:
		panel_grid = GridContainer.new()
		panel_grid.columns = 2 if panel.custom_minimum_size.x >= TWO_COLUMNS_FROM else 1
		panel_grid.add_theme_constant_override("h_separation", 10)
		panel_grid.add_theme_constant_override("v_separation", 10)
		panel_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel_body.add_child(panel_grid)
	return panel_grid

## A card with an optional icon, a title and a description. Returns the text column so
## callers can add rows; the card's HBox is the column's parent for side buttons.
func _item_card(icon_tex: Texture2D, title: String, desc: String, icon_size: int = 48) -> VBoxContainer:
	var card := _card()
	_cards_grid().add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
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
		var d := _label(desc, "Muted")
		d.add_theme_font_size_override("font_size", 15)
		v.add_child(d)
	return v

## Puts the card's action button beside the text column, vertically centred.
func _card_action(v: VBoxContainer, b: Button) -> void:
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.get_parent().add_child(b)

func _locked_button(text: String, width: float = 170.0) -> Button:
	var b := _button(text, "Ghost", Vector2(width, 52))
	b.disabled = true
	b.add_theme_font_size_override("font_size", 18)
	return b

## A buy button: disabled when unaffordable; `action` returns true when the purchase went through.
func _buy_button(text: String, cost: float, action: Callable, width: float = 170.0, variation: String = "Primary") -> Button:
	var b := _button(text, variation, Vector2(width, 52))
	b.disabled = cost > Game.money
	b.pressed.connect(func():
		if action.call():
			Sfx.play("buy"))
	return b

## label  [-]  value  [+]   with on_delta.call(-1 / +1). The buttons grey out at the ends.
func _stepper(parent: Container, label: String, value: String, value_w: float, variation: String, on_delta: Callable,
		btn: Vector2 = Vector2(56, 52), can_dec: bool = true, can_inc: bool = true) -> Array[Button]:
	var buttons: Array[Button] = []
	var nl := _label(label, "Muted")
	nl.size_flags_horizontal = 0
	nl.autowrap_mode = TextServer.AUTOWRAP_OFF
	parent.add_child(nl)
	for d in [-1, 1]:
		if d == 1:
			var vl := _label(value, variation, HORIZONTAL_ALIGNMENT_CENTER)
			vl.custom_minimum_size = Vector2(value_w, 0)
			vl.size_flags_horizontal = 0
			vl.autowrap_mode = TextServer.AUTOWRAP_OFF
			parent.add_child(vl)
		var b := _button("\u2212" if d < 0 else "+", "Ghost", btn)
		b.add_theme_font_size_override("font_size", 26)
		b.disabled = not (can_dec if d < 0 else can_inc)
		b.pressed.connect(func():
			Sfx.play("tick")
			on_delta.call(d))
		parent.add_child(b)
		buttons.append(b)
	return buttons

# ================================================================= motion

## Short squash on every press so taps feel acknowledged (does not depend on the release,
## which a drag-to-scroll can swallow).
func _pulse(b: Control) -> void:
	b.pivot_offset = b.size / 2.0
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(0.92, 0.92), 0.06).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(b, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _fade_in(c: Control, dur: float) -> void:
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, dur)

## Scale-and-fade a centred card into place.
func _pop_in(c: Control, dur: float = 0.35) -> void:
	c.modulate.a = 0.0
	await get_tree().process_frame # a card that was hidden has no size yet
	if not is_instance_valid(c) or not c.is_visible_in_tree():
		if is_instance_valid(c):
			c.modulate.a = 1.0
		return
	c.pivot_offset = c.size / 2.0
	c.scale = Vector2(0.96, 0.96)
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.5)

## Bars slide in from their screen edge (`dir` 1 = bottom, -1 = top). Anchored controls keep
## their layout position, so only the offsets are animated and restored.
func _slide_in(bar: Control, dir: int) -> void:
	var top := bar.offset_top
	var bottom := bar.offset_bottom
	var d := 24.0 * dir
	bar.offset_top = top + d
	bar.offset_bottom = bottom + d
	bar.modulate.a = 0.0
	var tw := bar.create_tween().set_parallel(true)
	tw.tween_property(bar, "offset_top", top, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bar, "offset_bottom", bottom, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(bar, "modulate:a", 1.0, 0.25)

func _show_report_overlay() -> void:
	report_dim.visible = true
	_fade_in(report_dim, 0.2)
	_pop_in(report_panel, 0.4)

## Cards of the open panel fade up one after another (first eight only; the rest are below the fold).
func _stagger_cards() -> void:
	var cards: Array[Node] = []
	for n in panel_body.get_children():
		if n is GridContainer:
			cards.append_array(n.get_children())
		elif n is PanelContainer or n is HBoxContainer:
			cards.append(n)
	var i := 0
	for c in cards:
		if not c is Control:
			continue
		var ctl := c as Control
		if i >= 6:
			break
		ctl.pivot_offset = Vector2(ctl.size.x / 2.0, 0.0)
		ctl.modulate.a = 0.0
		ctl.scale = Vector2(0.97, 0.97)
		var tw := ctl.create_tween().set_parallel(true)
		tw.tween_property(ctl, "modulate:a", 1.0, 0.2).set_delay(0.03 * i)
		tw.tween_property(ctl, "scale", Vector2.ONE, 0.28).set_delay(0.03 * i).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1

## The money figure jumps and flashes green (gain) or coral (loss).
func _money_pop(gain: bool) -> void:
	if _money_tween:
		_money_tween.kill()
	money_label.pivot_offset = Vector2(money_label.size.x / 2.0, money_label.size.y / 2.0)
	money_label.scale = Vector2.ONE
	money_label.add_theme_color_override("font_color", UiTheme.GOOD if gain else UiTheme.BAD)
	_money_tween = create_tween()
	# the figure counts towards the new value instead of jumping
	_money_tween.tween_method(func(v: float):
		_shown_money = v
		money_label.text = Loc.money(v), _shown_money, Game.money, 0.4)
	_money_tween.parallel()
	_money_tween.tween_property(money_label, "scale", Vector2(1.18, 1.18), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_money_tween.tween_property(money_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_money_tween.parallel().tween_method(func(k: float):
		money_label.add_theme_color_override("font_color", (UiTheme.GOOD if gain else UiTheme.BAD).lerp(UiTheme.GOLD_LIGHT, k)), 0.0, 1.0, 0.5)

## Faint woven-paper texture behind panels (one cached texture / draw call).
func _lattice_bg(p: PanelContainer) -> void:
	var t := TextureRect.new()
	t.texture = UiTheme.lattice()
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.modulate = Color(UiTheme.MUTED, 0.035)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(t)

## "Day 3 · Al Fahidi" strip that sweeps in at the top when a day starts.
func _banner(text: String) -> void:
	if banner == null:
		banner = PanelContainer.new()
		banner.theme_type_variation = "Toast"
		banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.set_anchors_preset(Control.PRESET_CENTER)
		root.add_child(banner)
		banner_label = _label("", "Title", HORIZONTAL_ALIGNMENT_CENTER)
		banner_label.add_theme_font_size_override("font_size", 40)
		banner_label.add_theme_color_override("font_color", UiTheme.IVORY)
		banner_label.custom_minimum_size = Vector2(420, 0)
		banner.add_child(banner_label)
	banner_label.text = text
	banner.visible = true
	banner.modulate.a = 0.0
	await get_tree().process_frame # layout first: the strip and the root need their sizes
	banner.reset_size()
	var w := root.size.x
	var y := root.size.y * 0.3
	banner.modulate.a = 0.0
	banner.position = Vector2((w - banner.size.x) / 2.0 + 80.0, y)
	if _banner_tween:
		_banner_tween.kill()
	_banner_tween = create_tween()
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "position:x", (w - banner.size.x) / 2.0, 0.35).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_banner_tween.tween_property(banner, "modulate:a", 1.0, 0.2)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_interval(0.9)
	_banner_tween.set_parallel(true)
	_banner_tween.tween_property(banner, "position:x", (w - banner.size.x) / 2.0 - 80.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_banner_tween.tween_property(banner, "modulate:a", 0.0, 0.3)
	_banner_tween.set_parallel(false)
	_banner_tween.tween_callback(func(): banner.visible = false)

## On/off switch drawn as a proper button (Godot's CheckButton knob overlapped Arabic text).
func _toggle_button(on: bool, text_on: String, text_off: String, on_toggle: Callable, width: float = 150.0) -> Button:
	var b := _button(("\u221a  " + text_on) if on else ("\u00d7  " + text_off), "Toggle", Vector2(width, 48))
	b.toggle_mode = true
	b.button_pressed = on
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not on:
		b.add_theme_color_override("font_color", UiTheme.BAD)
	b.toggled.connect(func(v: bool):
		Sfx.play("toggle")
		on_toggle.call(v))
	return b

## Thin star-lattice strip used as an ornamental divider.
func _divider() -> TextureRect:
	var t := TextureRect.new()
	t.texture = UiTheme.lattice()
	t.stretch_mode = TextureRect.STRETCH_TILE
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.custom_minimum_size = Vector2(0, 10)
	t.modulate = Color(UiTheme.GOLD, 0.35)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t
