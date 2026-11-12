class_name UiTheme
extends RefCounted
## A neighbourhood cafeteria: sand paper, charcoal ink, clay-red stamps and palm green.
## Flat skins and a small woven border keep startup and phone rendering inexpensive.

const NIGHT := Color("e8d6b6")
const NIGHT_DARK := Color("302a23")
const CARD := Color("fbf1dc")
const CARD_LIGHT := Color("dcc29b")
const GOLD := Color("a64b32")
const GOLD_DARK := Color("803c2b")
const GOLD_LIGHT := Color("f0d29c")
const TERRACOTTA := Color("a64b32")
const TERRACOTTA_DARK := Color("803c2b")
const PALM := Color("35634d")
const PALM_DARK := Color("294c3c")
const PALM_LIGHT := Color("4f7d61")
const TURQUOISE := Color("587664")
const SAND := Color("3c3026")
const IVORY := Color("fff4de")
const MUTED := Color("75604b")
const GOOD := Color("2d6246")
const BAD := Color("a13e2b")
const SKY := Color("bfe3ff")
## Readable on the charcoal bars: the money figure flashes these for a gain / a real loss.
const GAIN_LIGHT := Color("9ad7a5")
const LOSS_LIGHT := Color("f39a7f")
const INK := SAND
const CREAM := IVORY

static var _font: Font
static var _bold: Font
static var _lattice: Texture2D

static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/BalooBhaijaan2.ttf")
	return _font

static func bold() -> Font:
	if _bold == null:
		var fv := FontVariation.new()
		fv.base_font = font()
		fv.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("weight"): 700}
		_bold = fv
	return _bold

## Small palm-weave linework; used at low opacity, never behind dense menu text.
static func lattice() -> Texture2D:
	if _lattice == null:
		var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		img.fill(Color.TRANSPARENT)
		for y in range(32):
			for x in range(32):
				if (x + y) % 16 < 2 or (x - y + 32) % 16 < 2:
					img.set_pixel(x, y, Color.WHITE)
		_lattice = ImageTexture.create_from_image(img)
	return _lattice

static var _skins := {}

## Matte paper / painted wood. No per-pixel raster generation or glossy bevels.
static func skin(base: Color, state: String, kind: String = "solid") -> StyleBoxFlat:
	var key := "%s|%s|%s" % [base.to_html(), state, kind]
	if _skins.has(key):
		return _skins[key]
	var fill := base
	var border := base.darkened(0.15)
	if kind == "ghost":
		fill = Color("f4e7cd")
		border = Color("c4aa84")
	elif kind == "glass":
		fill = Color("40382d")
		border = Color("645541")
	if state == "hover":
		fill = fill.lightened(0.07)
	elif state == "pressed":
		fill = fill.darkened(0.08)
	elif state == "disabled":
		fill = Color("dfd2b9")
		border = Color("cdbd9f")
	var sb := flat(fill, 5, border, 1, 2)
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	_skins[key] = sb
	return sb

static func flat(bg: Color, radius: int = 12, border: Color = Color.TRANSPARENT, border_w: int = 0, bottom: int = -1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	if bottom >= 0:
		sb.border_width_bottom = bottom
	sb.set_content_margin_all(10)
	sb.anti_aliasing = true
	return sb

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 20

	# Labels
	t.set_color("font_color", "Label", SAND)
	for v in ["Title", "Heading", "Muted", "Money", "Small", "Light", "Big"]:
		t.add_type(v)
		t.set_type_variation(v, "Label")
	t.set_font("font", "Title", bold())
	t.set_font_size("font_size", "Title", 46)
	t.set_color("font_color", "Title", INK)
	t.set_font("font", "Heading", bold())
	t.set_font_size("font_size", "Heading", 26)
	t.set_color("font_color", "Heading", INK)
	t.set_font_size("font_size", "Muted", 17)
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Small", 16)
	t.set_color("font_color", "Small", SAND)
	t.set_font("font", "Money", bold())
	t.set_font_size("font_size", "Money", 24)
	t.set_color("font_color", "Money", GOOD)
	t.set_font("font", "Light", bold())
	t.set_font_size("font_size", "Light", 22)
	t.set_color("font_color", "Light", IVORY)
	t.set_font("font", "Big", bold())
	t.set_font_size("font_size", "Big", 28)
	t.set_color("font_color", "Big", INK)

	# Buttons: matte clay paint and paper (see skin()).
	_button_styles(t, "Button", GOLD, IVORY)
	for v in ["Primary", "Ghost", "Tab", "Danger", "Icon", "Filter", "Toggle"]:
		t.add_type(v)
		t.set_type_variation(v, "Button")
	_button_styles(t, "Primary", PALM, IVORY)
	_button_styles(t, "Danger", TERRACOTTA, IVORY)
	_button_styles(t, "Ghost", GOLD, SAND, "ghost")
	_button_styles(t, "Icon", GOLD, SAND, "ghost")
	t.set_font_size("font_size", "Primary", 24)
	# Categories: quiet paper when off, clay red when selected.
	_button_styles(t, "Filter", GOLD, SAND, "ghost")
	t.set_stylebox("pressed", "Filter", skin(GOLD, "normal"))
	t.set_stylebox("hover_pressed", "Filter", skin(GOLD, "hover"))
	t.set_color("font_pressed_color", "Filter", IVORY)
	t.set_color("font_hover_pressed_color", "Filter", IVORY)
	t.set_font_size("font_size", "Filter", 19)
	# On/off toggles on cards: outlined when off, palm green when on
	_button_styles(t, "Toggle", GOLD, SAND, "ghost")
	t.set_stylebox("pressed", "Toggle", skin(PALM, "normal"))
	t.set_stylebox("hover_pressed", "Toggle", skin(PALM, "hover"))
	t.set_color("font_pressed_color", "Toggle", IVORY)
	t.set_color("font_hover_pressed_color", "Toggle", IVORY)
	t.set_font_size("font_size", "Toggle", 19)
	# Tabs sit on the charcoal bar; clay red identifies the current section.
	_button_styles(t, "Tab", GOLD, IVORY, "glass")
	t.set_stylebox("pressed", "Tab", skin(GOLD, "normal"))
	t.set_stylebox("hover_pressed", "Tab", skin(GOLD, "hover"))
	t.set_color("font_pressed_color", "Tab", IVORY)
	t.set_color("font_hover_pressed_color", "Tab", IVORY)
	t.set_font_size("font_size", "Tab", 21)

	# Panels
	t.set_stylebox("panel", "PanelContainer", flat(NIGHT, 8, Color("bda17c"), 1))
	for v in ["Card", "Bar", "Toast", "Dim", "Chip", "Plain", "Head"]:
		t.add_type(v)
		t.set_type_variation(v, "PanelContainer")
	var card := flat(CARD, 6, Color("c9b18b"), 1)
	card.border_color = Color("c9b18b")
	card.border_width_top = 1
	card.shadow_color = Color(0, 0, 0, 0.3)
	card.shadow_size = 0
	card.shadow_offset = Vector2(0, 3)
	card.set_content_margin_all(10)
	t.set_stylebox("panel", "Card", card)
	var head := flat(NIGHT, 0, Color("bda17c"), 0, 1)
	head.corner_radius_bottom_left = 0
	head.corner_radius_bottom_right = 0
	head.set_content_margin_all(8)
	head.content_margin_left = 12
	head.content_margin_right = 12
	t.set_stylebox("panel", "Head", head)
	var bar := flat(NIGHT_DARK, 0)
	bar.set_content_margin_all(8)
	bar.content_margin_left = 16
	bar.content_margin_right = 16
	t.set_stylebox("panel", "Bar", bar)
	t.set_stylebox("panel", "Toast", flat(NIGHT_DARK, 6, GOLD_LIGHT, 1))
	# Toast kinds also differ by glyph (hud._toast), never by colour alone.
	for v in ["ToastGood", "ToastWarn", "ToastError"]:
		t.add_type(v)
		t.set_type_variation(v, "PanelContainer")
	t.set_stylebox("panel", "ToastGood", flat(PALM_DARK, 6, GAIN_LIGHT, 1))
	t.set_stylebox("panel", "ToastWarn", flat(NIGHT_DARK, 6, Color("e8b25a"), 2))
	t.set_stylebox("panel", "ToastError", flat(GOLD_DARK, 6, LOSS_LIGHT, 1))
	t.set_stylebox("panel", "Dim", flat(Color(0.02, 0.09, 0.12, 0.6), 0))
	var chip := flat(Color(1, 1, 1, 0.12), 10)
	chip.set_content_margin_all(6)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	t.set_stylebox("panel", "Chip", chip)
	t.set_stylebox("panel", "Plain", StyleBoxEmpty.new())

	# Progress bars
	var pb_bg := flat(Color("cfbea0"), 2)
	pb_bg.set_content_margin_all(0)
	var pb_fill := flat(TURQUOISE, 2)
	pb_fill.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", IVORY)
	t.set_font_size("font_size", "ProgressBar", 15)

	# Scroll
	var grabber := flat(Color(GOLD, 0.55), 6)
	grabber.set_content_margin_all(0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(GOLD, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(GOLD, 6))
	var track := flat(Color(0, 0, 0, 0.2), 6)
	track.set_content_margin_all(0)
	t.set_stylebox("scroll", "VScrollBar", track)

	# Volume sliders: a thick paper track filled in palm green, with a round knob.
	var groove := flat(Color("cfbea0"), 5, Color("b79d77"), 1)
	groove.set_content_margin_all(0)
	groove.content_margin_top = 5
	groove.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", groove)
	var filled := flat(PALM, 5)
	filled.set_content_margin_all(0)
	filled.content_margin_top = 5
	filled.content_margin_bottom = 5
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	t.set_icon("grabber", "HSlider", knob(PALM_DARK))
	t.set_icon("grabber_highlight", "HSlider", knob(PALM))
	return t

## Round slider knob from a radial gradient (no per-pixel loop in script).
static func knob(fill: Color) -> Texture2D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.62, 0.7, 0.86, 0.94])
	g.colors = PackedColorArray([fill, fill, IVORY, IVORY, Color(IVORY, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 34
	tex.height = 34
	return tex

static func _button_styles(t: Theme, type: String, base: Color, fg: Color, kind: String = "solid") -> void:
	t.set_stylebox("normal", type, skin(base, "normal", kind))
	t.set_stylebox("hover", type, skin(base, "hover", kind))
	t.set_stylebox("pressed", type, skin(base, "pressed", kind))
	t.set_stylebox("hover_pressed", type, skin(base, "pressed", kind))
	t.set_stylebox("disabled", type, skin(base, "disabled", kind))
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg)
	t.set_color("font_pressed_color", type, fg)
	t.set_color("font_hover_pressed_color", type, fg)
	t.set_color("font_disabled_color", type, Color("87765f"))
	t.set_font("font", type, bold())
	t.set_font_size("font_size", type, 20)
