class_name UiTheme
extends RefCounted
## Warm, chunky, touch-friendly theme built in code (no .tres to maintain).

const CREAM := Color("fff7e8")
const PAPER := Color("f7e4bf")
const WOOD := Color("5a3418")
const WOOD_DARK := Color("3e2210")
const BROWN := Color("8a5a2b")
const ORANGE := Color("f08a2c")
const ORANGE_DARK := Color("c4661a")
const ORANGE_LIGHT := Color("ffa64d")
const RED := Color("d9442b")
const GREEN := Color("4a9f4f")
const GREEN_DARK := Color("2f7a35")
const INK := Color("3a2416")
const MUTED := Color("8c6b50")
const GOLD := Color("f3c13a")
const SKY := Color("bfe3ff")

static var _font: Font
static var _bold: Font

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
	t.set_color("font_color", "Label", INK)
	for v in ["Title", "Heading", "Muted", "Money", "Small", "Light", "Big"]:
		t.add_type(v)
		t.set_type_variation(v, "Label")
	t.set_font("font", "Title", bold())
	t.set_font_size("font_size", "Title", 46)
	t.set_color("font_color", "Title", WOOD)
	t.set_font("font", "Heading", bold())
	t.set_font_size("font_size", "Heading", 26)
	t.set_color("font_color", "Heading", WOOD)
	t.set_font_size("font_size", "Muted", 17)
	t.set_color("font_color", "Muted", MUTED)
	t.set_font_size("font_size", "Small", 16)
	t.set_color("font_color", "Small", INK)
	t.set_font("font", "Money", bold())
	t.set_font_size("font_size", "Money", 24)
	t.set_color("font_color", "Money", GREEN_DARK)
	t.set_font("font", "Light", bold())
	t.set_font_size("font_size", "Light", 22)
	t.set_color("font_color", "Light", CREAM)
	t.set_font("font", "Big", bold())
	t.set_font_size("font_size", "Big", 32)
	t.set_color("font_color", "Big", INK)

	# Buttons
	_button_styles(t, "Button", ORANGE, ORANGE_DARK, ORANGE_LIGHT, INK)
	for v in ["Primary", "Ghost", "Tab", "Danger", "Icon"]:
		t.add_type(v)
		t.set_type_variation(v, "Button")
	_button_styles(t, "Primary", GREEN, GREEN_DARK, Color("5fb865"), CREAM)
	_button_styles(t, "Danger", RED, Color("a0301d"), Color("e8604a"), CREAM)
	_button_styles(t, "Ghost", CREAM, BROWN, Color.WHITE, INK, 2)
	_button_styles(t, "Icon", CREAM, BROWN, Color.WHITE, INK, 2)
	t.set_font_size("font_size", "Primary", 24)
	t.set_font("font", "Primary", bold())
	# Tabs live on the wooden bar
	var tab_n := flat(Color(1, 1, 1, 0.08), 12)
	var tab_p := flat(ORANGE, 12, ORANGE_DARK, 0, 4)
	var tab_h := flat(Color(1, 1, 1, 0.16), 12)
	t.set_stylebox("normal", "Tab", tab_n)
	t.set_stylebox("hover", "Tab", tab_h)
	t.set_stylebox("pressed", "Tab", tab_p)
	t.set_stylebox("focus", "Tab", StyleBoxEmpty.new())
	t.set_color("font_color", "Tab", CREAM)
	t.set_color("font_hover_color", "Tab", Color.WHITE)
	t.set_color("font_pressed_color", "Tab", INK)
	t.set_font("font", "Tab", bold())
	t.set_font_size("font_size", "Tab", 21)

	# Panels
	t.set_stylebox("panel", "PanelContainer", flat(PAPER, 20, BROWN, 3))
	for v in ["Card", "Bar", "Toast", "Dim", "Chip", "Plain"]:
		t.add_type(v)
		t.set_type_variation(v, "PanelContainer")
	var card := flat(CREAM, 14, Color(BROWN, 0.35), 2)
	card.set_content_margin_all(12)
	t.set_stylebox("panel", "Card", card)
	var bar := flat(WOOD, 0)
	bar.set_content_margin_all(8)
	bar.content_margin_left = 16
	bar.content_margin_right = 16
	t.set_stylebox("panel", "Bar", bar)
	t.set_stylebox("panel", "Toast", flat(WOOD_DARK, 14, GOLD, 2))
	t.set_stylebox("panel", "Dim", flat(Color(0.1, 0.05, 0.02, 0.55), 0))
	var chip := flat(Color(1, 1, 1, 0.14), 10)
	chip.set_content_margin_all(6)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	t.set_stylebox("panel", "Chip", chip)
	t.set_stylebox("panel", "Plain", StyleBoxEmpty.new())

	# Progress bars
	var pb_bg := flat(Color(0, 0, 0, 0.12), 8)
	pb_bg.set_content_margin_all(0)
	var pb_fill := flat(GREEN, 8)
	pb_fill.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", pb_bg)
	t.set_stylebox("fill", "ProgressBar", pb_fill)
	t.set_color("font_color", "ProgressBar", INK)
	t.set_font_size("font_size", "ProgressBar", 15)

	# Check buttons
	t.set_color("font_color", "CheckButton", INK)
	t.set_font_size("font_size", "CheckButton", 19)
	t.set_font("font", "CheckButton", bold())

	# Scroll
	var grabber := flat(Color(BROWN, 0.6), 6)
	grabber.set_content_margin_all(0)
	t.set_stylebox("grabber", "VScrollBar", grabber)
	t.set_stylebox("grabber_highlight", "VScrollBar", flat(BROWN, 6))
	t.set_stylebox("grabber_pressed", "VScrollBar", flat(BROWN, 6))
	var track := flat(Color(0, 0, 0, 0.06), 6)
	track.set_content_margin_all(0)
	t.set_stylebox("scroll", "VScrollBar", track)
	return t

static func _button_styles(t: Theme, type: String, bg: Color, dark: Color, light: Color, fg: Color, border_w: int = 0) -> void:
	var n := flat(bg, 12, dark, border_w, 4)
	n.content_margin_left = 18
	n.content_margin_right = 18
	n.content_margin_top = 10
	n.content_margin_bottom = 10
	var h := n.duplicate() as StyleBoxFlat
	h.bg_color = light
	var p := n.duplicate() as StyleBoxFlat
	p.bg_color = dark
	p.border_width_bottom = border_w
	p.content_margin_top = 12
	p.content_margin_bottom = 8
	var d := n.duplicate() as StyleBoxFlat
	d.bg_color = Color(0.75, 0.72, 0.68)
	d.border_color = Color(0.55, 0.52, 0.48)
	t.set_stylebox("normal", type, n)
	t.set_stylebox("hover", type, h)
	t.set_stylebox("pressed", type, p)
	t.set_stylebox("disabled", type, d)
	t.set_stylebox("focus", type, StyleBoxEmpty.new())
	t.set_color("font_color", type, fg)
	t.set_color("font_hover_color", type, fg)
	t.set_color("font_pressed_color", type, fg)
	t.set_color("font_disabled_color", type, Color(0.35, 0.3, 0.28))
	t.set_font("font", type, bold())
	t.set_font_size("font_size", type, 20)
