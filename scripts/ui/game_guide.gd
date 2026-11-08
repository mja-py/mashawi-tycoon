extends VBoxContainer
## A replayable conversation. Uses the existing cast; no extra downloaded models.

const TouchScroll := preload("res://scripts/ui/touch_scroll.gd")
const CharacterPortrait := preload("res://scripts/ui/character_portrait.gd")
const TOPICS := ["welcome", "stock", "price", "quality", "build", "promote", "stars", "day"]
const PANELS := ["", "supplies", "menu", "menu", "build", "promote", "goals", "supplies"]
const ART := ["food/chicken-skewer", "food/chicken-tray", "food/mutton-skewer", "food/salad-bowl", "icons/stand-big", "icons/fliers", "icons/flagship", "food/tikka-sandwich"]

var hud: CanvasLayer
var step := 0
var _portrait: TextureRect
var heading: Label
var dialogue: Label
var tip: Label
var fact: Label
var artwork: TextureRect
var back: Button
var next: Button
var try_it: Button
var chapters: Array[Button] = []
var _scroll: ScrollContainer

func setup(owner_hud: CanvasLayer, start: int) -> void:
	hud = owner_hud
	step = clampi(start, 0, TOPICS.size() - 1)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 12)
	var header := HBoxContainer.new()
	add_child(header)
	header.add_child(hud._label(tr("guide.title"), "Heading"))
	var swipe: Label = hud._label(tr("guide.swipe"), "Small")
	swipe.size_flags_horizontal = Control.SIZE_SHRINK_END
	swipe.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(swipe)
	var close: Button = hud._menu_target(hud._button(tr("ui.close"), "Ghost", Vector2(112, 52)), "guide_close")
	close.pressed.connect(hud.close_graphics)
	header.add_child(close)
	var progress := HBoxContainer.new()
	progress.add_theme_constant_override("separation", 8)
	add_child(progress)
	for i in TOPICS.size():
		var chapter: Button = hud._menu_target(hud._button(str(i + 1), "Filter", Vector2(48, 48)), "guide_step_%d" % i)
		chapter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		chapter.toggle_mode = true
		chapter.tooltip_text = tr("guide.%s.title" % TOPICS[i])
		chapter.accessibility_name = chapter.tooltip_text
		chapter.pressed.connect(func(): _show_step(i))
		chapters.append(chapter)
		progress.add_child(chapter)
	var conversation := HBoxContainer.new()
	conversation.size_flags_vertical = Control.SIZE_EXPAND_FILL
	conversation.add_theme_constant_override("separation", 20)
	add_child(conversation)
	var portrait := PanelContainer.new()
	portrait.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.PALM_DARK, 20, UiTheme.GOLD_LIGHT, 2))
	portrait.custom_minimum_size = Vector2(224, 0)
	conversation.add_child(portrait)
	var host := VBoxContainer.new()
	portrait.add_child(host)
	var viewport_box := CharacterPortrait.new()
	_portrait = viewport_box
	viewport_box.custom_minimum_size = Vector2(200, 220)
	viewport_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(viewport_box)
	var nameplate: Label = hud._label(tr("guide.host"), "Light", HORIZONTAL_ALIGNMENT_CENTER)
	nameplate.add_theme_font_size_override("font_size", 24)
	host.add_child(nameplate)
	var speech := VBoxContainer.new()
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speech.add_theme_constant_override("separation", 10)
	conversation.add_child(speech)
	heading = hud._label("", "Heading")
	heading.add_theme_font_size_override("font_size", 34)
	speech.add_child(heading)
	var scroll := TouchScroll.new()
	_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	speech.add_child(scroll)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 12)
	scroll.add_child(words)
	dialogue = hud._label("")
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.add_theme_font_size_override("font_size", 24)
	dialogue.add_theme_constant_override("line_spacing", -6)
	words.add_child(dialogue)
	var practical := PanelContainer.new()
	practical.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.CARD_LIGHT, 16))
	words.add_child(practical)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	practical.add_child(row)
	artwork = TextureRect.new()
	artwork.custom_minimum_size = Vector2(96, 96)
	artwork.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(artwork)
	var tips := VBoxContainer.new()
	tips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(tips)
	tips.add_child(hud._label(tr("guide.try"), "Small"))
	tip = hud._label("")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.add_theme_font_size_override("font_size", 24)
	tip.add_theme_constant_override("line_spacing", -6)
	tips.add_child(tip)
	fact = hud._label("", "Muted")
	fact.add_theme_font_size_override("font_size", 22)
	fact.add_theme_constant_override("line_spacing", -6)
	words.add_child(fact)
	var extra: Label = hud._label("", "Muted")
	extra.name = "Extra"
	extra.add_theme_font_size_override("font_size", 22)
	extra.add_theme_constant_override("line_spacing", -6)
	words.add_child(extra)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	add_child(footer)
	back = hud._menu_target(hud._button(tr("guide.back"), "Ghost", Vector2(128, 58)), "guide_back")
	back.pressed.connect(func(): _show_step(step - 1))
	footer.add_child(back)
	if hud.main.phase == hud.main.Phase.PREP:
		var practice: Button = hud._menu_target(hud._button(tr("coach.practice"), "Primary", Vector2(0, 58)), "guide_practice")
		practice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		practice.pressed.connect(hud.start_tutorial)
		footer.add_child(practice)
	try_it = hud._menu_target(hud._button(tr("guide.show_menu"), "Ghost", Vector2(0, 58)), "guide_try")
	try_it.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	try_it.pressed.connect(_try_menu)
	footer.add_child(try_it)
	next = hud._menu_target(hud._button(tr("guide.next"), "Primary", Vector2(210, 58)), "guide_next")
	next.pressed.connect(func():
		if step == TOPICS.size() - 1:
			hud.close_graphics()
			if hud.main.phase == hud.main.Phase.PREP:
				hud.open_panel("supplies")
		else:
			_show_step(step + 1))
	footer.add_child(next)
	_show_step(step)

func _show_step(index: int) -> void:
	step = clampi(index, 0, TOPICS.size() - 1)
	hud.guide_step = step
	var topic: String = TOPICS[step]
	heading.text = tr("guide.%s.title" % topic)
	dialogue.text = tr("guide.%s.say" % topic)
	tip.text = tr("guide.%s.tip" % topic)
	fact.text = tr("guide.%s.fact" % topic)
	var extra: Label = fact.get_parent().get_node("Extra")
	extra.visible = topic in ["price", "build"]
	if extra.visible:
		extra.text = tr("guide.%s.extra" % topic)
	if topic == "price":
		fact.text = tr("guide.price.live") % [tr(Game.loc()["name"]), Loc.money(Game.unit_cost("chicken_tikka")), Loc.money(Game.menu["chicken_tikka"]["price"])]
	# The first/last chapters use the same real dish art as the game's menu.
	var model: String = ART[step]
	if not ResourceLoader.exists("res://assets/models/%s.glb" % model):
		model = "food/chicken-skewer"
	artwork.texture = Icons.model_icon(model, 128)
	back.disabled = step == 0
	next.text = tr("guide.ready") if step == TOPICS.size() - 1 else tr("guide.next")
	try_it.disabled = PANELS[step] == "" or hud.main.phase != hud.main.Phase.PREP
	try_it.visible = not try_it.disabled
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in chapters.size():
		chapters[i].set_pressed_no_signal(i == step)
	_portrait.gesture()
	Sfx.play("tick")
	if dialogue.get_parent().get_parent() is ScrollContainer:
		dialogue.get_parent().get_parent().scroll_vertical = 0
	hud._fade_in(dialogue, 0.2)

func _try_menu() -> void:
	hud.close_graphics()
	hud.open_panel(PANELS[step])
	if TOPICS[step] in ["price", "quality"]:
		hud._select_dish("chicken_tikka")

func test_view() -> Dictionary:
	return {"step": step, "topic": TOPICS[step], "title": heading.text,
		"portrait": _portrait.test_view(),
		"dialogue": dialogue.text, "tip": tip.text, "fact": fact.text,
		"scroll": _scroll.scroll_vertical, "scrollNeeded": _scroll.get_v_scroll_bar().max_value > _scroll.size.y + 1.0,
		"fits": hud.root.get_global_rect().encloses(hud.report_panel.get_global_rect())}
