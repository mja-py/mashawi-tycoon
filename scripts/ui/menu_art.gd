extends Control
## Lightweight spot art for the carousel and preparation tabs.

const PALE := Color("f1d7a8")
const INK := Color("274e49")
const DARK := Color("203e3d")
const CLAY := Color("b56348")
const CREAM := Color("fff0ca")
const SKY := Color("93bfb4")

var subject: String

func _init(id: String) -> void:
	subject = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)

func _draw() -> void:
	if subject.begins_with("tab:"):
		_draw_badge(subject.trim_prefix("tab:"))
		return
	if subject.begins_with("dish:"):
		var accent: Color = {"food": CLAY, "side": Color("986241"), "drink": Color("397d77"), "sweet": Color("855e74")}.get(subject.trim_prefix("dish:"), CLAY)
		draw_rect(Rect2(Vector2.ZERO, size), accent.darkened(0.17))
		var ring := minf(size.x, size.y) * 0.62
		draw_circle(size * Vector2(0.50, 0.55), ring, accent, true, -1.0, true)
		draw_arc(size * Vector2(0.50, 0.55), ring * 0.87, 0, TAU, 48, Color(PALE, 0.46), 1.4, true)
		for side in [-1.0, 1.0]:
			for i in range(4):
				var x: float = size.x * 0.5 + side * (ring + i * 10)
				var center := Vector2(x, size.y * 0.52 + (i % 2) * 17 - 9)
				draw_colored_polygon(PackedVector2Array([center + Vector2(0, -6), center + Vector2(5, 0), center + Vector2(0, 6), center + Vector2(-5, 0)]), Color(PALE, 0.42))
		return
	if subject == "ingredient" or subject == "equipment" or subject.begins_with("campaign:"):
		_draw_shop_card()
		return
	_draw_place()

func _draw_shop_card() -> void:
	var base := Color("335e59")
	var accent := Color("a9c7a6")
	if subject == "ingredient":
		base = Color("89583d")
		accent = Color("e0b47e")
	elif subject.begins_with("campaign:"):
		base = {"fliers": Color("844c3c"), "posters": Color("734e65"),
			"social": Color("355c70"), "radio": Color("555c40")}.get(subject.trim_prefix("campaign:"), base)
		accent = Color("e8bd83")
	draw_rect(Rect2(Vector2.ZERO, size), base)
	var center := size * Vector2(0.5, 0.49)
	var radius := size.y * 0.67
	draw_circle(center, radius, base.lightened(0.16), true, -1.0, true)
	draw_arc(center, radius - 5.0, 0.0, TAU, 48, Color(accent, 0.52), 1.6, true)
	var inset := minf(size.x * 0.05, 20.0)
	for y in [inset, size.y - inset]:
		for x in [inset, size.x - inset]:
			var corner := Vector2(x, y)
			var inward := Vector2(signf(center.x - x), signf(center.y - y))
			draw_polyline(PackedVector2Array([corner + Vector2(inward.x * 22.0, 0),
				corner, corner + Vector2(0, inward.y * 14.0)]), accent, 1.3, true)
	for side in [-1.0, 1.0]:
		for i in range(3):
			var point := center + Vector2(side * (radius + 14 + i * 12), i * 7 - 7)
			var diamond := 5.0 - i
			_poly([point + Vector2(0, -diamond), point + Vector2(diamond, 0),
				point + Vector2(0, diamond), point + Vector2(-diamond, 0)], Color(accent, 0.75))

func _rect(x: float, y: float, w: float, h: float, color: Color) -> void:
	draw_rect(Rect2(x, y, w, h), color)

func _poly(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)

func _draw_place() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	var fit := minf(size.x / 300.0, size.y / 115.0)
	draw_set_transform((size - Vector2(300, 115) * fit) * 0.5, 0.0, Vector2.ONE * fit)
	var water := Color("477e77")
	draw_circle(Vector2(215, 43), 31, Color("ddb371"), true, -1, true)
	_poly([Vector2(0, 85), Vector2(55, 58), Vector2(124, 79), Vector2(192, 68), Vector2(300, 91), Vector2(300, 115), Vector2(0, 115)], Color("396962"))
	match subject:
		"fahidi":
			_rect(0, 94, 300, 21, water)
			_rect(76, 51, 118, 46, PALE)
			_rect(88, 27, 44, 38, PALE)
			_rect(84, 23, 52, 6, CREAM)
			for i in range(3):
				_rect(96 + i * 11, 33, 5, 20, DARK)
			_poly([Vector2(154, 95), Vector2(154, 75), Vector2(169, 65), Vector2(184, 75), Vector2(184, 95)], DARK)
			_poly([Vector2(199, 101), Vector2(255, 101), Vector2(244, 109), Vector2(207, 109)], CREAM)
			_rect(213, 88, 32, 5, CLAY)
			_rect(216, 93, 2, 8, PALE)
			_rect(239, 93, 2, 8, PALE)
		"creek", "jbr":
			_rect(0, 91, 300, 24, water if subject == "creek" else PALE)
			_palm(Vector2(75, 99))
			_palm(Vector2(207, 100))
			if subject == "jbr":
				_rect(114, 69, 66, 7, CREAM)
				for i in range(4):
					_rect(118 + i * 16, 69, 7, 7, CLAY)
				_rect(119, 76, 4, 22, DARK)
				_rect(171, 76, 4, 22, DARK)
			else:
				_poly([Vector2(120, 102), Vector2(192, 102), Vector2(178, 110), Vector2(134, 110)], CREAM)
		"metro":
			draw_circle(Vector2(73, 67), 20, PALE, true, -1, true)
			draw_circle(Vector2(224, 67), 20, PALE, true, -1, true)
			_rect(73, 47, 151, 40, PALE)
			for i in range(7):
				_rect(75 + i * 21, 61, 14, 11, DARK)
			_rect(69, 88, 160, 5, CREAM)
			_rect(84, 93, 6, 22, DARK)
			_rect(201, 93, 6, 22, DARK)
		"downtown":
			for i in range(5):
				_rect(55 + i * 37, 72 - (i % 3) * 12, 29, 43 + (i % 3) * 12, SKY)
			_poly([Vector2(109, 113), Vector2(120, 70), Vector2(128, 70), Vector2(128, 49), Vector2(137, 49), Vector2(137, 29), Vector2(145, 29), Vector2(148, 5), Vector2(152, 29), Vector2(154, 113)], CREAM)
		"mall", "gv":
			for i in range(3):
				var x := 77 + i * 49
				var y := 52 - (1 - absi(i - 1)) * 17
				_rect(x, y, 44, 115 - y, PALE)
				_poly([Vector2(x + 7, 115), Vector2(x + 7, y + 25), Vector2(x + 22, y + 12), Vector2(x + 37, y + 25), Vector2(x + 37, 115)], DARK)
				_rect(x - 3, y - 5, 50, 5, CLAY if subject == "gv" else CREAM)

func _palm(p: Vector2) -> void:
	draw_line(p, p + Vector2(6, -56), PALE, 5.0, true)
	for i in range(6):
		var dx := (i - 2.5) * 10.0
		var tip := p + Vector2(6 + dx, -65 + absf(dx) * 0.39)
		_poly([p + Vector2(6, -57), tip, tip + Vector2(-3, 8)], SKY)

func _draw_badge(id: String) -> void:
	var unit := minf(size.x, size.y) / 28.0
	draw_set_transform((size - Vector2.ONE * 28.0 * unit) * 0.5, 0, Vector2.ONE * unit)
	var c := Vector2(14, 14)
	match id:
		"supplies":
			draw_arc(Vector2(14, 9), 5, PI, TAU, 12, PALE, 2.0, true)
			_poly([Vector2(5, 9), Vector2(23, 9), Vector2(25, 24), Vector2(3, 24)], PALE)
		"menu":
			draw_arc(c, 10, 0, TAU, 30, PALE, 2.0, true)
			draw_arc(c, 6, 0, TAU, 24, PALE, 1.2, true)
		"place":
			draw_circle(Vector2(14, 11), 8, PALE, true, -1.0, true)
			_poly([Vector2(7, 14), Vector2(21, 14), Vector2(14, 25)], PALE)
			draw_circle(Vector2(14, 11), 3.0, DARK, true, -1.0, true)
		"build":
			draw_line(Vector2(8, 23), Vector2(17, 10), PALE, 4.0, true)
			_poly([Vector2(7, 8), Vector2(12, 3), Vector2(24, 11), Vector2(20, 16)], PALE)
		"promote":
			_poly([Vector2(4, 11), Vector2(11, 11), Vector2(23, 5), Vector2(23, 22), Vector2(11, 17), Vector2(4, 17)], PALE)
			draw_line(Vector2(8, 17), Vector2(10, 24), PALE, 3.0, true)
		"graphics":
			for i in range(3):
				var y := 6.0 + i * 8.0
				draw_line(Vector2(3, y), Vector2(25, y), DARK, 2.0, true)
				draw_circle(Vector2(8 if i % 2 == 0 else 19, y), 3.2, DARK, true, -1.0, true)
		"goals":
			var points: Array[Vector2] = []
			for i in range(10):
				var a := -PI / 2.0 + TAU * i / 10.0
				points.append(c + Vector2.from_angle(a) * (11.5 if i % 2 == 0 else 5.0))
			_poly(points, PALE)
