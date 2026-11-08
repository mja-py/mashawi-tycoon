extends Control
## A small, non-blocking mentor beside the real controls and real service actors.
const Portrait := preload("res://scripts/ui/character_portrait.gd")
var hud: CanvasLayer
var card: PanelContainer
var _heading: Label
var _words: Label
var _next: Button
var _later: Button
var _host: Control
var _portrait: TextureRect
var _outline: Panel
var _target: Control
var _poll := 0.0
var _pulse := 0.0
var _last_topic := ""
var _last_layout := ""

func setup(owner_hud: CanvasLayer) -> void:
	hud = owner_hud
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 14
	_outline = Panel.new()
	_outline.add_theme_stylebox_override("panel", UiTheme.flat(Color(0,0,0,0), 13, UiTheme.GOLD_LIGHT, 3))
	_outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_outline)
	card = PanelContainer.new()
	card.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.PALM_DARK, 18, UiTheme.GOLD_LIGHT, 2))
	add_child(card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	card.add_child(row)
	_host = Control.new()
	_host.custom_minimum_size = Vector2(80, 104)
	row.add_child(_host)
	var speech := VBoxContainer.new()
	speech.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(speech)
	_heading = hud._label("", "Light")
	_heading.add_theme_font_size_override("font_size", 20)
	speech.add_child(_heading)
	_words = hud._label("", "Light")
	_words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_words.add_theme_font_size_override("font_size", 22)
	_words.add_theme_constant_override("line_spacing", -8)
	_words.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	speech.add_child(_words)
	var actions := VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(actions)
	_next = hud._menu_target(hud._button("", "Primary", Vector2(156, 50)), "coach_next")
	_next.pressed.connect(_continue)
	actions.add_child(_next)
	_later = hud._menu_target(hud._button(tr("coach.save_later"), "Ghost", Vector2(156, 48)), "coach_defer")
	_later.pressed.connect(_defer)
	actions.add_child(_later)
	var close: Button = hud._menu_target(hud._button("×", "Ghost", Vector2(48, 48)), "coach_close")
	close.tooltip_text = tr("coach.pause")
	close.accessibility_name = tr("coach.pause")
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(hud.pause_tutorial)
	row.add_child(close)
	_refresh()

func topic() -> String:
	return GuideJourney.STEPS[int(Game.tutorial["step"])]

func reserve_height() -> float:
	if not is_instance_valid(card) or card.get_parent() != self or not card.visible:
		return 0.0
	return card.get_combined_minimum_size().y + 6.0

func detach_card() -> void:
	if is_instance_valid(card) and card.get_parent() != self:
		card.reparent(self)

func dispose() -> void:
	detach_card()
	hud.root.remove_child(self)
	queue_free()

func _sync_layout() -> void:
	var reading: bool = hud.report_dim.visible and (hud._graphics_open or hud.main.phase != hud.main.Phase.REPORT)
	var show: bool = Game.tutorial["active"] and not reading and hud.main.phase != hud.main.Phase.TITLE
	if show and hud.main.phase == hud.main.Phase.REPORT and hud.report_dim.visible:
		if card.get_parent() != hud.report_body:
			card.reparent(hud.report_body)
			hud.report_body.move_child(card, 1)
	else:
		detach_card()
	card.visible = show
	if show and not is_instance_valid(_portrait):
		_portrait = Portrait.new()
		_portrait.max_edge = 320
		_portrait.mentor_mode = true
		_portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_host.add_child(_portrait)
	if not show and is_instance_valid(_portrait):
		_host.remove_child(_portrait)
		_portrait.queue_free()
		_portrait = null
	if card.get_parent() == self:
		card.position = Vector2(8, maxf(hud.TOP_BAR_HEIGHT, hud.top_bar.size.y) + 6)
		card.size = Vector2(hud.root.size.x - 16, card.get_combined_minimum_size().y)
	var layout := "%s:%s:%s" % [show, card.get_parent() == self, reserve_height()]
	if layout != _last_layout:
		_last_layout = layout
		hud._layout_prep_panel()

func _process(delta: float) -> void:
	_sync_layout()
	if not card.visible:
		_outline.hide()
		return
	var real_delta := delta / maxf(Engine.time_scale, 0.01)
	_pulse += real_delta
	_poll += real_delta
	if _poll >= 0.2:
		_poll = 0.0
		# Settling is an automatic transition; keep the report and its real Next day button.
		if topic() in ["open", "order", "sale", "finish"] and hud.main.phase == hud.main.Phase.REPORT:
			Game.tutorial["step"] = GuideJourney.STEPS.find("report")
			Game.tutorial["done"] = false
			_store()
		if int(Game.tutorial["step"]) < 7 and hud.main.phase == hud.main.Phase.DAY:
			Game.tutorial["step"] = GuideJourney.STEPS.find("order")
			Game.tutorial["done"] = false
		if not Game.tutorial["done"] and GuideJourney.reached(Game.tutorial, _view()):
			Game.tutorial["done"] = true
			Sfx.play("confirm")
			if is_instance_valid(_portrait):
				_portrait.gesture()
			_store()
		_refresh()
	_outline.visible = is_instance_valid(_target) and not Game.tutorial["done"]
	if _outline.visible:
		var rect := _target.get_global_rect().grow(4)
		_outline.position = rect.position - global_position
		_outline.size = rect.size
		_outline.modulate.a = 0.65 + sin(_pulse * 4.0) * 0.25

func _view() -> Dictionary:
	var sim: Node = hud.main.sim
	var phase: String = ["title", "prep", "day", "report"][hud.main.phase]
	var ordered := false
	if phase == "day":
		for guest in hud.main.world._level.get_children():
			if guest is Customer and guest.model and guest.order_shown:
				ordered = true
	return {"phase": phase, "panel": hud.current_panel, "dish": hud.selected_dish,
		"sauce": Game.menu["chicken_tikka"]["recipe"]["sauce"], "price": Game.menu["chicken_tikka"]["price"],
		"portions": Game.portions_possible("chicken_tikka") if Game.is_on_sale("chicken_tikka") else 0, "foodReady": Game.food_on_sale(), "day": Game.day, "ordered": ordered,
		"served": int(sim.stats.get("served", 0)) if phase == "day" else 0,
		"level": Game.station_level(Game.tutorial["station"]), "campaign": Game.marketing.has("fliers"), "claimed": Game.goals_claimed.size()}

func _store() -> void:
	# Do not create partial business-day saves just to record a mentor message.
	if hud.main.phase != hud.main.Phase.DAY:
		Game.save()

func _refresh() -> void:
	var key := topic()
	var done: bool = Game.tutorial["done"]
	var text_key := "coach.%s.%s" % [key, "done" if done else "say"]
	_heading.text = tr("coach.progress") % [int(Game.tutorial["step"]) + 1, GuideJourney.STEPS.size(), tr("coach." + key + ".title")]
	_words.text = tr(text_key)
	if key == "price":
		if not done:
			_words.text = tr("coach.price." + Game.location)
		_words.text += " " + tr("coach.margin") % [tr(Game.loc()["name"]), Loc.money(Game.unit_cost("chicken_tikka")), Loc.money(Game.menu["chicken_tikka"]["price"])]
	if key == "upgrade":
		_words.text = tr(text_key) % [tr(Data.STATIONS[Game.tutorial["station"]]["name"])]
		if Game.tutorial["station"] == "signage":
			_words.text = tr("coach.upgrade.attract_done" if done else "coach.upgrade.attract")
	if key == "report" and not Game.history.is_empty():
		var r: Dictionary = Game.history.back()
		_words.text = tr("coach.report.live") % [int(r["served"]), Loc.money(float(r["profit"])), int(r["too_pricey"]), int(r["left_wait"])]
	_target = hud.guide_target(_target_id()) if not done else null
	var manual := key in ["welcome", "graduate"]
	_next.text = tr("coach.finish") if key == "graduate" else (tr("coach.next") if done or manual else tr("coach.show"))
	_next.disabled = not done and not manual and key in ["order", "sale", "finish", "report"]
	_next.visible = not _next.disabled
	_later.visible = not done and ((key == "upgrade" and hud.current_panel == "build" and hud._prep_detail == Game.tutorial["station"]) or (key == "campaign" and hud.current_panel == "promote" and hud._prep_detail == "fliers") or (key == "goals" and hud.current_panel == "goals" and not Game.goal_ready()))
	_later.text = tr("coach.keep_growing") if key == "goals" else tr("coach.save_later")
	if key in ["stock", "open"] and not done and not Game.food_on_sale():
		_words.text = tr("coach.enable_food") if _food_disabled() else tr("coach.restock")
	if key == "campaign" and not done and Game.money < float(Data.MARKETING["fliers"]["cost"]) + Game.daily_wages() + float(Game.loc()["rent"]):
		_words.text = tr("coach.campaign.wait")
	if _last_topic != key:
		_last_topic = key
		if is_instance_valid(_portrait):
			_portrait.gesture()
		hud._fade_in(_words, 0.2)

func _food_disabled() -> bool:
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "food" and Game.is_on_sale(id): return false
	return true

func _target_id() -> String:
	if topic() in ["stock", "open"] and _food_disabled():
		return "on_sale" if hud.current_panel == "menu" and hud.selected_dish == "chicken_tikka" else "tab_menu"
	match topic():
		"menu": return "tab_menu"
		"dish": return "select_chicken_tikka" if hud.current_panel == "menu" else "tab_menu"
		"recipe": return "recipe_sauce_up" if int(Game.menu["chicken_tikka"]["recipe"]["sauce"]) < 2 else "recipe_sauce_down"
		"price": return "price_up" if float(Game.menu["chicken_tikka"]["price"]) < float(Game.price_range("chicken_tikka")[1]) else "price_down"
		"supplies": return "tab_supplies"
		"stock": return "stock_today" if hud.current_panel == "supplies" else "tab_supplies"
		"open": return "open_shop"
		"finish": return "skip_day"
		"report": return "next_day"
		"upgrade": return "buy_station" if hud._prep_detail == Game.tutorial["station"] else "tab_build"
		"campaign": return "start_promo" if hud._prep_detail == "fliers" else "tab_promote"
		"goals": return "claim_goal" if hud.current_panel == "goals" and Game.goal_ready() else "tab_goals"
	return ""

func _continue() -> void:
	if Game.tutorial["done"] or topic() in ["welcome", "graduate"]:
		if topic() == "graduate":
			Game.tutorial["completed"] = true
			hud.pause_tutorial()
			return
		Game.tutorial["step"] = mini(int(Game.tutorial["step"]) + 1, GuideJourney.STEPS.size() - 1)
		Game.tutorial["done"] = false
		if topic() == "price":
			Game.tutorial["price"] = float(Game.menu["chicken_tikka"]["price"])
		if topic() == "upgrade":
			Game.tutorial["station"] = GuideJourney.station_for(Game.history.back() if not Game.history.is_empty() else {})
			Game.tutorial["level"] = Game.station_level(Game.tutorial["station"])
		Game.tutorial["claimed"] = Game.goals_claimed.size()
		_store()
		_refresh()
		return
	_focus()

func _focus() -> void:
	if hud.main.phase != hud.main.Phase.PREP:
		return
	match topic():
		"menu", "dish", "recipe", "price":
			if hud.current_panel != "menu": hud.open_panel("menu")
			if topic() != "menu": hud._select_dish("chicken_tikka")
		"supplies", "stock", "open":
			if topic() != "supplies" and _food_disabled():
				if hud.current_panel != "menu": hud.open_panel("menu")
				hud._select_dish("chicken_tikka")
			else:
				hud.open_panel("supplies")
		"upgrade":
			if hud.current_panel != "build": hud.open_panel("build")
			hud._open_prep_detail(Game.tutorial["station"])
		"campaign":
			if hud.current_panel != "promote": hud.open_panel("promote")
			hud._open_prep_detail("fliers")
		"goals": hud.open_panel("goals")
	await get_tree().process_frame
	await get_tree().process_frame
	# Opening panels scales them briefly; reveal after their final geometry settles.
	await get_tree().create_timer(0.32, true, false, true).timeout
	if not is_inside_tree(): return
	var target: Control = hud.guide_target(_target_id(), false)
	if target and hud.panel_scroll.is_ancestor_of(target):
		hud.panel_scroll.set_process(false)
		var content_y: float = target.get_global_rect().get_center().y - hud.panel_body.global_position.y
		hud.panel_scroll.scroll_vertical = maxi(0, roundi(content_y - hud.panel_scroll.size.y * 0.5))

func _defer() -> void:
	Game.tutorial["done"] = true
	_store()
	_refresh()

func test_view() -> Dictionary:
	var r := card.get_global_rect()
	return {"step": int(Game.tutorial["step"]), "topic": topic(), "done": Game.tutorial["done"],
		"text": _words.text, "target": _target_id(), "visible": card.is_visible_in_tree(),
		"fits": hud.root.get_global_rect().encloses(r), "bottom": r.end.y,
		"portrait": _portrait.test_view() if is_instance_valid(_portrait) else {},
		"embedded": card.get_parent() == hud.report_body}
