class_name UiTheme
extends RefCounted
## "Dubai dusk" theme built in code (no .tres to maintain): deep Gulf teal panels edged in
## souk gold, sand-coloured text, palm green for "go", terracotta for danger, turquoise for
## progress. Panels carry a faint eight-pointed-star lattice (classic Arabic geometry).

const NIGHT := Color("12343f")       # panel background: the Gulf after sunset
const NIGHT_DARK := Color("0b2129")  # top/bottom bars, toasts
const CARD := Color("1b4653")        # cards on a panel
const CARD_LIGHT := Color("23596a")  # hovered ghost buttons
const GOLD := Color("e2b24a")        # souk brass: default buttons, headings, borders
const GOLD_DARK := Color("a97b20")
const GOLD_LIGHT := Color("f5cf74")
const TERRACOTTA := Color("d2562f")  # danger buttons, Danger text
const TERRACOTTA_DARK := Color("98391c")
const PALM := Color("3f9a63")        # primary (go) buttons
const PALM_DARK := Color("2a6f45")
const PALM_LIGHT := Color("5cb57d")
const TURQUOISE := Color("2fb7c2")   # progress fills, selected accents
const SAND := Color("f1e3c3")        # body text
const IVORY := Color("fbf4e4")       # text on coloured buttons / bars
const MUTED := Color("b7ad97")       # secondary text on dark
const GOOD := Color("8fe3a8")        # positive numbers on dark
const BAD := Color("ff8f70")         # negative numbers on dark
const SKY := Color("bfe3ff")
# names kept for callers that think in roles rather than colours
const INK := SAND
const CREAM := IVORY

static var _font: Font
static var _bold: Font
static var _lattice: Texture2D
static var _sunset: Texture2D

## Horizontal terracotta -> gold -> terracotta band for the title (Dubai sunset).
static func sunset() -> Texture2D:
	if _sunset == null:
		var g := Gradient.new()
		g.colors = PackedColorArray([Color(TERRACOTTA, 0.0), TERRACOTTA, GOLD_DARK, TERRACOTTA, Color(TERRACOTTA, 0.0)])
		g.offsets = PackedFloat32Array([0.0, 0.2, 0.5, 0.8, 1.0])
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 256
		gt.height = 8
		_sunset = gt
	return _sunset

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

## A 64 px tile of the eight-pointed star (khatam) lattice, white on transparent; drawn once
## at startup and tiled at low alpha behind panels (one draw call per panel).
static func lattice() -> Texture2D:
	if _lattice:
		return _lattice
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var star := PackedVector2Array()
	var c := Vector2(n / 2.0, n / 2.0)
	for i in range(16):
		var r := n * (0.46 if i % 2 == 0 else 0.30)
		var a := i * PI / 8.0
		star.append(c + Vector2(cos(a), sin(a)) * r)
	var cross := PackedVector2Array() # the small cross that fills the gaps between stars sits on the tile corners
	for i in range(8):
		var r := n * (0.17 if i % 2 == 0 else 0.07)
		var a := i * PI / 4.0 + PI / 8.0
		cross.append(Vector2(cos(a), sin(a)) * r)
	for y in range(n):
		for x in range(n):
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := Geometry2D.is_point_in_polygon(p, star)
			# 2 px outline of the star only
			var edge := inside and not (Geometry2D.is_point_in_polygon(p + Vector2(2, 0), star) and Geometry2D.is_point_in_polygon(p - Vector2(2, 0), star)
				and Geometry2D.is_point_in_polygon(p + Vector2(0, 2), star) and Geometry2D.is_point_in_polygon(p - Vector2(0, 2), star))
			var in_cross := false
			for corner in [Vector2(0, 0), Vector2(n, 0), Vector2(0, n), Vector2(n, n)]:
				if Geometry2D.is_point_in_polygon(p - corner, cross):
					in_cross = true
			if edge or in_cross:
				img.set_pixel(x, y, Color(1, 1, 1, 1))
	_lattice = ImageTexture.create_from_image(img)
	return _lattice


static var _skins := {}
static var _pixel_scale := 0

## Physical pixels per logical pixel, rounded up and capped at 2 (phones); 1 on desktop.
static func pixel_scale() -> int:
	if _pixel_scale == 0:
		_pixel_scale = 1
		var win := DisplayServer.window_get_size()
		var logical := float(ProjectSettings.get_setting("display/window/size/viewport_height", 720))
		if win.y > 0 and logical > 0.0:
			_pixel_scale = clampi(int(ceil(float(win.y) / (logical * 0.8))), 1, 2)
	return _pixel_scale

## Signed distance to a rounded rectangle (centre `c`, half size `h`, radius `r`); < 0 inside.
static func _sd_box(p: Vector2, c: Vector2, h: Vector2, r: float) -> float:
	var q := (p - c).abs() - h + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r

static func _blend(dst: Color, src: Color, cov: float) -> Color:
	var a := src.a * cov
	if a <= 0.0:
		return dst
	var out_a := a + dst.a * (1.0 - a)
	var rgb := (Color(src.r, src.g, src.b) * a + Color(dst.r, dst.g, dst.b) * dst.a * (1.0 - a)) / maxf(out_a, 0.0001)
	return Color(rgb.r, rgb.g, rgb.b, out_a)

## A bevelled, glossy button skin drawn once per (colour, state, kind) into a 72 px nine-patch:
## vertical gradient, inner top highlight, darker bottom edge (depth), soft drop shadow. `kind`
## is "solid" (coloured), "ghost" (translucent with a gold border) or "glass" (translucent, no
## border, for tabs on the dark bar). `state`: normal / hover / pressed / disabled.
static func skin(base: Color, state: String, kind: String = "solid") -> StyleBoxTexture:
	var key := "%s|%s|%s" % [base.to_html(), state, kind]
	if _skins.has(key):
		return _skins[key]
	# Drawn at the screen's pixel density (2x on phones) and reported at logical size, so the
	# corners stay crisp instead of being upscaled.
	var k := pixel_scale()
	var n := 72 * k
	var radius := 16.0 * k
	var pressed := state == "pressed"
	var disabled := state == "disabled"
	var shadow := 0.0 if (pressed or disabled) else 3.0 * k
	var edge := 0.0 if (pressed or disabled) else 6.0 * k
	var fill := base
	if disabled:
		fill = Color(0.22, 0.29, 0.32)
	elif state == "hover":
		fill = base.lightened(0.12)
	elif pressed:
		fill = base.darkened(0.18)
	var top_c := fill.lightened(0.05 if pressed else 0.2)
	var bot_c := fill.darkened(0.05) if pressed else fill
	if pressed: # inset look: darker at the top
		top_c = fill.darkened(0.12)
		bot_c = fill
	var edge_c := fill.darkened(0.38)
	var border_c := Color(GOLD, 0.8 if not disabled else 0.25)
	if kind != "solid":
		var a := 0.08
		if state == "hover":
			a = 0.16
		elif pressed:
			a = 0.04
		elif disabled:
			a = 0.04
		top_c = Color(1, 1, 1, a + 0.05)
		bot_c = Color(1, 1, 1, a)
		edge_c = Color(GOLD, 0.8 if kind == "ghost" else 0.0) if not disabled else Color(1, 1, 1, 0.1)
		if kind == "glass":
			edge_c = Color(1, 1, 1, 0.1)
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var body_h := float(n) - shadow
	var c := Vector2(n / 2.0, body_h / 2.0)
	var h := Vector2(n / 2.0, body_h / 2.0)
	var hi := Color(1, 1, 1, 0.35 if kind == "solid" else 0.18)
	var inner := -2.5 * k # pixels deeper than this are plain rows: no edge work needed
	for y in range(n):
		var py := y + 0.5
		# the row's flat colour (gradient / edge band / highlight) computed once
		var row := top_c.lerp(bot_c, clampf(py / body_h, 0.0, 1.0))
		if edge > 0.0 and py > body_h - edge:
			row = edge_c
		var hi_row := not pressed and not disabled and py > 1.5 * k and py < 4.0 * k
		var row_px := _blend(row, hi, 1.0) if hi_row else row
		var near_bottom := py > body_h - radius - 1.0
		for x in range(n):
			var p := Vector2(x + 0.5, py)
			var d := _sd_box(p, c, h, radius)
			if d < inner and not near_bottom:
				img.set_pixel(x, y, row_px)
				continue
			var px := Color(0, 0, 0, 0)
			if shadow > 0.0 and near_bottom:
				var ds := _sd_box(p, c + Vector2(0, shadow), h, radius)
				px = _blend(px, Color(0, 0, 0, 0.3), clampf(0.5 - ds, 0.0, 1.0))
			var cov := clampf(0.5 - d, 0.0, 1.0)
			if cov > 0.0:
				var col := row
				if kind == "ghost" and d > -2.0 * k:
					col = border_c
				elif kind == "glass" and d > -1.0 * k:
					col = Color(1, 1, 1, 0.12)
				px = _blend(px, col, cov)
				if hi_row and d < -2.0 * k:
					px = _blend(px, hi, 1.0)
			img.set_pixel(x, y, px)
	var sb := StyleBoxTexture.new()
	var tex := ImageTexture.create_from_image(img)
	tex.set_size_override(Vector2i(72, 72))
	sb.texture = tex
	sb.texture_margin_left = 24
	sb.texture_margin_right = 24
	sb.texture_margin_top = 24
	sb.texture_margin_bottom = 24
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14 if pressed else 10
	sb.content_margin_bottom = 8 if pressed else 12
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
	t.set_color("font_color", "Title", GOLD)
	t.set_font("font", "Heading", bold())
	t.set_font_size("font_size", "Heading", 26)
	t.set_color("font_color", "Heading", GOLD_LIGHT)
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
	t.set_color("font_color", "Big", IVORY)

	# Buttons: bevelled nine-patch skins (see skin())
	_button_styles(t, "Button", GOLD, NIGHT_DARK)
	for v in ["Primary", "Ghost", "Tab", "Danger", "Icon", "Filter", "Toggle"]:
		t.add_type(v)
		t.set_type_variation(v, "Button")
	_button_styles(t, "Primary", PALM, IVORY)
	_button_styles(t, "Danger", TERRACOTTA, IVORY)
	_button_styles(t, "Ghost", GOLD, SAND, "ghost")
	_button_styles(t, "Icon", GOLD, SAND, "ghost")
	t.set_font_size("font_size", "Primary", 24)
	# Filter chips: outlined when off, gold when selected
	_button_styles(t, "Filter", GOLD, SAND, "ghost")
	t.set_stylebox("pressed", "Filter", skin(GOLD, "normal"))
	t.set_stylebox("hover_pressed", "Filter", skin(GOLD, "hover"))
	t.set_color("font_pressed_color", "Filter", NIGHT_DARK)
	t.set_color("font_hover_pressed_color", "Filter", NIGHT_DARK)
	t.set_font_size("font_size", "Filter", 19)
	# On/off toggles on cards: outlined when off, palm green when on
	_button_styles(t, "Toggle", GOLD, SAND, "ghost")
	t.set_stylebox("pressed", "Toggle", skin(PALM, "normal"))
	t.set_stylebox("hover_pressed", "Toggle", skin(PALM, "hover"))
	t.set_color("font_pressed_color", "Toggle", IVORY)
	t.set_color("font_hover_pressed_color", "Toggle", IVORY)
	t.set_font_size("font_size", "Toggle", 19)
	# Tabs live on the dark bar: glass when idle, lit gold when selected
	_button_styles(t, "Tab", GOLD, SAND, "glass")
	t.set_stylebox("pressed", "Tab", skin(GOLD, "normal"))
	t.set_stylebox("hover_pressed", "Tab", skin(GOLD, "hover"))
	t.set_color("font_pressed_color", "Tab", NIGHT_DARK)
	t.set_color("font_hover_pressed_color", "Tab", NIGHT_DARK)
	t.set_font_size("font_size", "Tab", 21)

	# Panels
	t.set_stylebox("panel", "PanelContainer", flat(NIGHT, 20, GOLD, 2))
	for v in ["Card", "Bar", "Toast", "Dim", "Chip", "Plain", "Head"]:
		t.add_type(v)
		t.set_type_variation(v, "PanelContainer")
	var card := flat(CARD, 14, Color(GOLD, 0.28), 1)
	card.border_color = Color(GOLD, 0.28)
	card.border_width_top = 2
	card.shadow_color = Color(0, 0, 0, 0.3)
	card.shadow_size = 6
	card.shadow_offset = Vector2(0, 3)
	card.set_content_margin_all(10)
	t.set_stylebox("panel", "Card", card)
	var head := flat(NIGHT_DARK, 14, GOLD, 0, 2)
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
	t.set_stylebox("panel", "Toast", flat(NIGHT_DARK, 14, GOLD, 2))
	t.set_stylebox("panel", "Dim", flat(Color(0.02, 0.09, 0.12, 0.6), 0))
	var chip := flat(Color(1, 1, 1, 0.12), 10)
	chip.set_content_margin_all(6)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	t.set_stylebox("panel", "Chip", chip)
	t.set_stylebox("panel", "Plain", StyleBoxEmpty.new())

	# Progress bars
	var pb_bg := flat(Color(0, 0, 0, 0.3), 8)
	pb_bg.set_content_margin_all(0)
	var pb_fill := flat(TURQUOISE, 8)
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
	return t

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
	t.set_color("font_disabled_color", type, Color(0.6, 0.64, 0.64))
	t.set_font("font", type, bold())
	t.set_font_size("font_size", type, 20)
