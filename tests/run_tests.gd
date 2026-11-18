extends Node
## Headless logic tests:  godot --headless --path . -- --tests

var failures := 0
var passes := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
	else:
		failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)

func _ready() -> void:
	var game := Game
	_test_economy()
	_test_stations()
	_test_game_flow(game)
	_test_stages(game)
	_test_goals(game)
	_test_goal_ladder(game)
	_test_save_load(game)
	_test_pricing(game)
	_test_save_validation(game)
	_test_migration(game)
	_test_daily_stock(game)
	_test_mobile_stages_and_lighting(game)
	_test_later_item_handoff(game)
	_test_skip_pickup(game)
	_test_restaurant_service(game)
	_test_closing_meal_handoff(game)
	_test_dine_in_share(game)
	_test_reopen_same_district(game)
	_test_terrace_clearance(game)
	_test_cast_appearances()
	_test_ambient_animation()
	_test_guide_journey()
	_test_logic_audit(game)
	_test_reload_audit(game)
	_test_economy_audit(game)
	_test_station_copy()
	_test_played_day_reputation(game)
	_test_group_orders(game)
	_test_reveal_before_open(game)
	_test_loss_stats(game)
	_test_opening_buzz(game)
	_test_wages(game)
	_test_promotions(game)
	_test_advisor(game)
	_test_advisor_variety(game)
	_test_feedback_ui()
	_test_release3_strings()
	_test_fame_levels(game)
	_test_fame_guests(game)
	_test_upgrade_jobs(game)
	game.delete_save() # the suite must not leave user://save_test.json behind
	print("tests: %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _test_reload_audit(game) -> void:
	game.new_game()
	game.money = -125.0
	game.stats["total_profit"] = -80.0
	game.prepared_day = game.day
	game.begin_day()
	var seed_before: int = game.day_seed
	var weather_before: String = game.weather
	game.begin_day()
	check(game.day_seed == seed_before and game.weather == weather_before, "repeated Open actions cannot reroll the day's weather or customers")
	game.save()
	check(game.load_game() and game.money == -125.0 and game.stats["total_profit"] == -80.0, "negative cash and lifetime losses survive actual save/load")
	game.begin_day()
	check(game.day_seed == seed_before and game.weather == weather_before, "reload cannot reroll a committed business day")
	check(game.day_committed(), "a reloaded open day is flagged as already in progress")
	game.tutorial = GuideJourney.clean({"active": true, "step": 11, "started_day": 999})
	game._validate()
	check(game.tutorial["started_day"] == game.day, "corrupt future tutorial dates cannot strand the report lesson")
	game.new_game()
	_write_save(game, {"version": 4, "money": {}, "day": [], "saved_at": {}, "inventory": false, "avg_cost": [],
		"menu": {"chicken_tikka": {"recipe": false, "price": {}, "level": []}}, "marketing": [], "history": {},
		"rig": {"stage": {}, "stations": {"grill": {}}}, "stats": {"total_profit": {}, "locations_visited": [[], "creek"]}})
	check(game.save_summary()["day"] == 1 and game.load_game(), "malformed nested save fields recover without a load-screen crash")
	check(is_finite(game.money) and game.inventory["chicken"] == 0 and game.menu["chicken_tikka"]["recipe"]["sauce"] == 1, "recovered state keeps finite money and a usable recipe")
	game.delete_save()
	game.new_game()

func _test_logic_audit(game) -> void:
	game.new_game()
	var coach = load("res://scripts/ui/play_guide.gd").new()
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "food": game.menu[id]["enabled"] = false
	check(coach._food_disabled(), "mentor detects when every food dish is switched off")
	game.menu["sandwich"]["enabled"] = true
	check(not coach._food_disabled(), "mentor accepts an alternate food dish")
	var lesson := GuideJourney.fresh()
	lesson["step"] = GuideJourney.STEPS.find("stock")
	check(GuideJourney.reached(lesson, {"portions": 0, "foodReady": true}), "stock lesson accepts a cookable alternate dish when chicken tikka is off")
	coach.free()
	var was_persistent: bool = game.persist
	game.persist = false
	game.new_game()
	game.money = 100000.0
	game.popularity = 0.9
	game.rig["stage"] = "truck"
	game.plot()["stage"] = "restaurant"
	game.plot()["stations"] = {"doner": 1, "fryer": 1}
	for ing in Data.INGREDIENTS: game.inventory[ing] = 100
	check(game.unlock_item("shawarma") and game.unlock_item("fries"), "audit fixture owns its specialty equipment and dishes")
	check(game.set_location("creek"), "audit fixture can leave its fixed restaurant")
	var cash: float = game.money
	var stock: Dictionary = game.inventory.duplicate()
	check(not game.is_on_sale("shawarma") and not game.is_on_sale("fries"), "moving away cannot sell dishes without their local equipment")
	check(not game.sell("shawarma", 15.0) and game.money == cash and game.inventory == stock, "missing equipment cannot produce an instant paid meal")
	check(not game.enhance_item("shawarma"), "unavailable dishes cannot consume enhancement money")
	game.new_game()
	game.day = 5
	game.plots["creek"] = {"stage": "restaurant", "stations": {}, "reputation": 0.8, "last_visit": 1}
	game.prepare_day()
	var rep: float = game.plots["creek"]["reputation"]
	game.prepare_day()
	check(is_equal_approx(rep, game.plots["creek"]["reputation"]), "reopening preparation cannot repeatedly decay another district's reputation")
	game.money = -125.0
	game._validate()
	check(game.money == -125.0, "reload validation cannot forgive unpaid bills")
	game.new_game()
	cash = game.money
	check(not game._spend(-25.0) and not game._spend(NAN) and not game._spend(INF) and game.money == cash, "invalid transaction amounts cannot mint or poison money")
	game.new_game()
	var ledger := {"served": 0, "revenue": 0.0, "cogs": 0.0, "satisfaction_sum": 0.0, "sold": {}, "util": {}}
	game.end_day(ledger)
	cash = game.money
	var after_day: int = game.day
	game.end_day(ledger)
	check(game.day == after_day and game.money == cash and game.history.size() == 1, "a repeated close callback cannot settle the same day twice")
	game.new_game()
	for ing in Data.INGREDIENTS: game.inventory[ing] = 200
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	var sim := DaySim.new()
	add_child(sim)
	sim.start(game.sim_context(), world)
	sim._rng.seed = 12
	for i in range(12):
		var buyer := world.spawn_guest(-1, world.pickup_slot(0))
		buyer.wants = "food"
		buyer.order_shown = true
		sim._on_served(buyer, "chicken_tikka", 0.0, false)
		buyer._finish()
	var dishes := 0
	for n in sim.stats["sold"].values(): dishes += int(n)
	check(dishes > sim.stats["served"], "audit fixture includes actual add-on purchases")
	check(game.total_served == sim.stats["served"], "add-ons cannot inflate lifetime customer goals")
	sim.free()
	world.free()
	game.new_game()
	game.rig["stage"] = "truck"
	game.plot()["stage"] = "restaurant"
	game.plot()["stations"] = {"counter": 7, "grill": 7, "seating": 4, "majlis": 1}
	game.popularity = 0.9
	for ing in Data.INGREDIENTS: game.inventory[ing] = 1000
	cash = game.money
	var fixed_rng := RandomNumberGenerator.new()
	fixed_rng.seed = 27
	var fast := FastSim.run(game.sim_context(), fixed_rng)
	check(is_equal_approx(game.money - cash, float(fast["revenue"])), "headless balance revenue agrees with the actual cash credited")
	check(game.total_served == fast["served"], "headless balance counts customers once")
	game.new_game()
	var main := get_parent()
	var previous_phase: int = main.phase
	var before_day: int = game.day
	main.phase = main.Phase.PREP
	main._on_day_finished({"_day": game.day})
	check(game.day == before_day and main.phase == main.Phase.PREP, "close callbacks outside live service cannot advance the calendar")
	main.phase = main.Phase.REPORT
	main.start_day()
	check(not main.sim.running and main.phase == main.Phase.REPORT, "a stale Open button cannot restart a finished day")
	main.phase = main.Phase.DAY
	main._on_day_finished({"_day": game.day - 1})
	check(main.phase == main.Phase.DAY and game.day == before_day, "a previous day's callback cannot close a new session")
	main.phase = previous_phase
	game.persist = was_persistent

func _test_guide_journey() -> void:
	check(GuideJourney.station_for({"bottleneck": "arrivals"}) == "signage", "quiet streets need visibility rather than extra kitchen capacity")
	check(GuideJourney.station_for({"bottleneck": "grill"}) == "grill", "kitchen delays lead the mentor to the actual bottleneck")
	check(GuideJourney.clean({"station": "signage"})["station"] == "signage", "an attraction recommendation survives save validation")
	check(GuideJourney.clean(null) == GuideJourney.fresh(), "old saves do not force onboarding on existing players")
	var bad := GuideJourney.clean({"active": true, "step": 999, "price": NAN, "station": "bogus", "started_day": -5})
	check(bad["step"] == GuideJourney.STEPS.size() - 1 and bad["price"] == 0.0 and bad["station"] == "counter" and bad["started_day"] == 1, "malformed tutorial progress stays inside valid bounds")
	check(not GuideJourney.clean({"active": true, "completed": true})["active"], "completed lessons do not reopen automatically")
	var state := GuideJourney.fresh()
	var view := {"panel": "menu", "dish": "chicken_tikka", "sauce": 1, "price": 10.0, "portions": 0,
		"phase": "prep", "ordered": false, "served": 0, "day": 1, "level": 0, "campaign": false, "claimed": 0}
	for topic in ["recipe", "stock", "order", "sale", "finish", "report", "upgrade", "campaign", "goals"]:
		state["step"] = GuideJourney.STEPS.find(topic)
		check(not GuideJourney.reached(state, view), "%s requires a real outcome; opening a window is insufficient" % topic)
	state["step"] = GuideJourney.STEPS.find("price")
	state["price"] = 10.0
	check(not GuideJourney.reached(state, view), "price lesson waits for a real edit")
	view["price"] = 11.0
	check(GuideJourney.reached(state, view), "price change completes the price objective")
	view["sauce"] = 2
	state["step"] = GuideJourney.STEPS.find("recipe")
	check(GuideJourney.reached(state, view), "the balanced recipe completes its objective")
	view["served"] = 1
	state["step"] = GuideJourney.STEPS.find("sale")
	check(GuideJourney.reached(state, view), "an actual sale completes the service objective")
	state["step"] = GuideJourney.STEPS.find("report")
	view["day"] = 2
	view["phase"] = "report"
	check(not GuideJourney.reached(state, view), "report lesson waits for the player's Next day action")
	view["phase"] = "prep"
	check(GuideJourney.reached(state, view), "returning from the report completes the full-day loop")

## The day a player watches scores satisfaction like the statistical day: walking to the
## pickup spot and giving your own order are not "waiting too long".
func _test_played_day_reputation(game) -> void:
	var averages := {}
	var deltas := {}
	for mode in ["played", "fast"]:
		game.new_game()
		for id in Data.INGREDIENTS:
			game.inventory[id] = 60
		game.weather = "sunny"
		game.forecast = "sunny"
		game.day_seed = 4242
		var stats: Dictionary
		if mode == "played":
			var world := World.new()
			add_child(world)
			world.set_location(game.location)
			var sim := DaySim.new()
			add_child(sim)
			stats = DayRunner.play(sim, world, game.sim_context())
			check(not stats["_unfinished"], "a headless played day closes on its own (%d ticks)" % int(stats["_ticks"]))
			check(int(stats["served"]) >= 8, "the played first day serves customers (%d)" % int(stats["served"]))
			sim.free()
			world.free()
		else:
			var day_rng := RandomNumberGenerator.new()
			day_rng.seed = 4242
			stats = FastSim.run(game.sim_context(), day_rng)
		averages[mode] = float(stats["satisfaction_sum"]) / maxi(1, int(stats["served"]))
		deltas[mode] = Economy.popularity_delta(stats, game.popularity)
		# an un-upgraded cart at base prices: some faces green, some amber, almost none red
		var faces := int(stats["mood_great"]) + int(stats["mood_ok"]) + int(stats["mood_bad"])
		var green := float(stats["mood_great"]) / maxf(1.0, faces)
		check(faces > 0 and green >= 0.3 and green <= 0.9 and float(stats["mood_bad"]) <= 0.1 * faces,
			"a default %s first day leaves a mix of green and amber faces (%d green, %d amber, %d red)" % [mode, stats["mood_great"], stats["mood_ok"], stats["mood_bad"]])
	check(absf(averages["played"] - averages["fast"]) < 0.06,
		"an uncrowded played day satisfies like the statistical day (%.2f vs %.2f)" % [averages["played"], averages["fast"]])
	check(deltas["played"] > 0.0 and deltas["fast"] > 0.0,
		"a decent first day raises reputation in the day the player watches (%.3f played, %.3f fast)" % [deltas["played"], deltas["fast"]])
	game.new_game()

## One visible buyer carries a party: stock is held per portion, every portion is sold and
## paid for (with its own add-on chances), the kitchen cooks every portion, the buyer counts
## once as a lifetime customer, and a full street turns walkers away as a counted crowd.
func _test_group_orders(game) -> void:
	game.new_game()
	for id in Data.INGREDIENTS:
		game.inventory[id] = 0
	game.inventory["bread"] = 40
	game.inventory["chicken"] = 40
	game.inventory["veg"] = 40
	game.inventory["sauce"] = 40
	game.inventory["charcoal"] = 40
	var per: int = game.portions_possible("chicken_tikka")
	var ledger := StockLedger.new()
	var a := RefCounted.new()
	var b := RefCounted.new()
	check(ledger.hold(a, "chicken_tikka", 6) == 6 and ledger.portions_free("chicken_tikka") == per - 6,
		"a party of six holds six portions of stock (%d of %d left)" % [ledger.portions_free("chicken_tikka"), per])
	check(ledger.hold(b, "chicken_tikka", per) == per - 6, "the next party can only hold what is left")
	ledger.release(b)
	check(ledger.portions_free("chicken_tikka") == per - 6 and game.inventory["chicken"] == 40, "a buyer who walks off gives the held stock back; nothing left the store")
	var money: float = game.money
	var chicken: int = game.inventory["chicken"]
	var price: float = float(game.menu["chicken_tikka"]["price"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var sale := ledger.settle(a, "chicken_tikka", 6, 1.0, "drink", false, "sunny", rng)
	var needs: Dictionary = Economy.portion_ingredients("chicken_tikka", game.menu["chicken_tikka"])
	check(int(sale["sold"]) == 6 and is_equal_approx(float(sale["total"]), price * 6.0) and is_equal_approx(game.money - money, price * 6.0),
		"the party pays for all six portions (%s)" % str(sale))
	check(chicken - int(game.inventory["chicken"]) == int(needs["chicken"]) * 6 and ledger.is_empty(), "six portions of chicken leave the store and the hold is cleared")
	# Add-ons are offered per food portion: a party of 30 brings many more extras than one.
	for id in ["salad", "laban", "soda"]:
		game.menu[id]["unlocked"] = true
		game.menu[id]["enabled"] = true
	for id in Data.INGREDIENTS:
		game.inventory[id] = 5000
	var extras := {"one": 0, "party": 0}
	for i in range(20):
		var s1 := ledger.settle(RefCounted.new(), "chicken_tikka", 1, 1.0, "food", false, "sunny", rng)
		var s30 := ledger.settle(RefCounted.new(), "chicken_tikka", 30, 1.0, "food", false, "sunny", rng)
		for id in s1["extras"]:
			extras["one"] += int(s1["extras"][id])
		for id in s30["extras"]:
			extras["party"] += int(s30["extras"][id])
	check(extras["party"] > extras["one"] * 10, "add-ons are rolled for every portion of a party (%s)" % str(extras))
	# The kitchen cooks every portion; the buyer's own cooking is not "waiting".
	var tp := Throughput.new()
	tp.setup({"kitchen": {"grill": 1.0}, "station_of_kind": {"grill": "grill"}, "queue_cap": 6, "seats": 4, "dine_in_share": 1.0}, rng)
	var served := []
	tp.on_served = func(payload, item: String, wait_s: float, dine_in: bool, portions: int) -> void:
		served.append([payload, wait_s, dine_in, portions])
	var big_party := int(Data.SERVICE["dine_max_party"]) + 1
	tp.enqueue("party", "chicken_tikka", big_party)
	var t := 0.0
	while served.is_empty() and t < 20.0:
		tp.tick(0.05)
		t += 0.05
	check(served.size() == 1 and t >= big_party - 0.1 and int(served[0][3]) == big_party,
		"a grill at one portion a second takes %d seconds for a party of %d (%.2f s)" % [big_party, big_party, t])
	check(served.size() == 1 and float(served[0][1]) < 0.2, "a party waiting only for its own food is not kept waiting (%s)" % str(served))
	check(served.size() == 1 and not bool(served[0][2]), "a party bigger than a table takes away even with free seats")
	# A whole day: lifetime customers count buyers, portions count the parties' food.
	game.new_game()
	for id in Data.INGREDIENTS:
		game.inventory[id] = 5000
	game.rig["stage"] = "truck"
	game.plots["fahidi"] = {"stage": "restaurant", "stations": {"counter": 10, "grill": 14, "karak": 8, "seating": 8}, "reputation": 0.7, "last_visit": game.day}
	game.popularity = 0.7
	game.weather = "sunny"
	game.forecast = "sunny"
	game.weather_day = game.day
	var before: int = game.total_served
	var day_rng := RandomNumberGenerator.new()
	day_rng.seed = 77
	var day: Dictionary = FastSim.run(game.sim_context(), day_rng)
	var primary := 0
	for id in day["sold"]:
		if Data.MENU_ITEMS[id]["kind"] in ["food", "drink"]:
			primary += int(day["sold"][id])
	check(game.total_served - before == int(day["served"]) and int(day["portions"]) > int(day["served"]) * 3,
		"lifetime customers count one per order, not per portion (%d buyers, %d portions)" % [int(day["served"]), int(day["portions"])])
	check(primary >= int(day["portions"]), "every portion of every party was sold (%d sold, %d portions)" % [primary, int(day["portions"])])
	# A busy stall on a level-1 grill: the grill is the played day's bottleneck, and levelling
	# it sells more.
	var stall_days := {}
	for grill in [1, 6]:
		game.new_game()
		game.day = int(Data.OPENING["days"]) + 1 # a steady day, after the opening buzz
		for id in Data.INGREDIENTS:
			game.inventory[id] = 5000
		game.rig = {"stage": "stall", "stations": {"grill": grill, "karak": 2, "doner": 1}}
		game.location = "metro"
		game.popularity = 0.9
		game.plot()["reputation"] = 0.9
		for id in Data.MENU_ITEMS:
			game.menu[id]["unlocked"] = game.item_available(id)
			game.menu[id]["enabled"] = game.item_available(id)
		game.weather = "sunny"
		game.forecast = "sunny"
		game.weather_day = game.day
		game.day_seed = 31
		var street := World.new()
		add_child(street)
		street.set_location(game.location)
		var stall_sim := DaySim.new()
		add_child(stall_sim)
		stall_days[grill] = DayRunner.play(stall_sim, street, game.sim_context())
		stall_sim.free()
		street.free()
	var slow: Dictionary = stall_days[1]
	var fast_grill: Dictionary = stall_days[6]
	check(Economy.bottleneck(slow["util"]) == "grill", "a level-1 grill holds up a busy stall (%s)" % str(slow["util"]))
	check(int(fast_grill["portions"]) > int(slow["portions"]) * 1.15,
		"levelling the grill sells more at the stall (%d -> %d portions)" % [int(slow["portions"]), int(fast_grill["portions"])])
	# A street with one buyer place turns most would-be buyers away, and says so.
	var ctx: Dictionary = game.sim_context()
	ctx["buyers"] = 1
	day_rng.seed = 77
	var crowded: Dictionary = FastSim.run(ctx, day_rng)
	check(int(crowded["crowd"]) > 20 and int(crowded["served"]) < int(day["served"]),
		"a full street turns would-be buyers away as a counted crowd (%d)" % int(crowded["crowd"]))
	game.new_game()

## A tier purchase holds the street for its reveal; opening the shop must build it first.
func _test_reveal_before_open(game) -> void:
	var main := get_parent()
	check(main.hud != null, "the test run has a HUD to drive")
	var hud = main.hud
	game.new_game()
	game.money = 100000.0
	var phase_before = main.phase
	main.phase = main.Phase.PREP
	main.world.set_location(game.location)
	main.world.apply_visual()
	check(main.world.cart != null, "the street is built for the reveal test")
	var tier_before: int = Data.station_tier(game.station_level("grill"))
	while Data.station_tier(game.station_level("grill")) == tier_before:
		hud._confirm_purchase(null, func(): return game.buy_station_level("grill"), "tier")
		if Data.station_tier(game.station_level("grill")) == tier_before:
			hud.flush_reveal()
	check(hud.holds_world_visual(), "a new station tier holds the street for its reveal")
	hud.flush_reveal()
	check(not hud.holds_world_visual(), "opening the shop releases the held reveal")
	check(not main.world.visual_needs_reload(), "the stand is built before the day starts, not during it")
	var guest := ModelLib.spawn_guest("creek-abaya", self)
	var player := ModelLib.animation_player(guest)
	ModelLib.set_manual_pose(guest, true)
	ModelLib.ambient_variety = false
	if player.has_animation("glance"):
		ModelLib.play_once(guest, "glance")
		ModelLib.sim_speed = 12.0
		for tick in 12:
			ModelLib.step_pose(guest, 1.0 / 60.0)
		ModelLib.render_pose(guest)
		check(player.current_animation_position < 0.03, "a queue glance keeps its natural pace at Skip (%.3f s in one frame)" % player.current_animation_position)
	else:
		check(false, "the cast ships the glance clip")
	ModelLib.sim_speed = 1.0
	ModelLib.ambient_variety = true
	guest.free()
	main.phase = phase_before
	game.new_game()

## The numbers a player reads on a station card are the numbers the formulas use.
func _test_station_copy() -> void:
	var st: Dictionary = Data.STATIONS
	var expected := {
		"signage": [st["signage"]["attract_per_level"]],
		"lights": [st["lights"]["evening_traffic_per_level"]],
		"music": [st["music"]["satisfaction_per_level"], st["music"]["attract_per_level"]],
		"shade": [st["shade"]["hot_traffic_per_level"], st["shade"]["hot_satisfaction_per_level"]],
		"majlis": [st["majlis"]["satisfaction_per_level"], st["majlis"]["spend_per_level"]],
	}
	var previous := TranslationServer.get_locale()
	for locale in ["en", "ar"]:
		TranslationServer.set_locale(locale)
		for id in expected:
			var text := tr(String(st[id]["effect"]))
			for share in expected[id]:
				var shown := "+%d%%" % roundi(float(share) * 100.0)
				check(text.contains(shown), "%s card (%s) states %s per level" % [id, locale, shown])
	TranslationServer.set_locale(previous)
	var hot := {"shade_level": 3, "lights_level": 2}
	var loc: Dictionary = Data.LOCATIONS["creek"]
	var plain := Economy.arrival_rate(loc, "hot", 12.0, {})
	check(is_equal_approx(Economy.arrival_rate(loc, "hot", 12.0, hot) / plain, 1.0 + 3.0 * float(st["shade"]["hot_traffic_per_level"])),
		"shade lifts hot-day traffic by its data value")
	var evening := Economy.arrival_rate(loc, "sunny", 19.0, {})
	check(is_equal_approx(Economy.arrival_rate(loc, "sunny", 19.0, hot) / evening, 1.0 + 2.0 * float(st["lights"]["evening_traffic_per_level"])),
		"lights lift evening traffic by their data value")
	check(is_equal_approx(Economy.arrival_rate(loc, "sunny", 12.0, hot), Economy.arrival_rate(loc, "sunny", 12.0, {})),
		"lights and shade do nothing at a sunny midday")

## Standing loops keep a natural pace: not sped up by Skip, not left fast by a gesture,
## and not in step with the neighbours.
func _test_ambient_animation() -> void:
	var stage := Node3D.new()
	add_child(stage)
	var vendor := ModelLib.spawn_crew(true, stage, Vector3.ZERO, 0, 0.66)
	var vendor_player := ModelLib.animation_player(vendor)
	ModelLib.set_manual_pose(vendor, true)
	ModelLib.play_loop(vendor, "idle")
	ModelLib.play_once(vendor, "interact-right", "idle", 1.6)
	check(is_equal_approx(vendor_player.speed_scale, 1.6), "the handoff gesture plays at its requested speed")
	for i in 60:
		vendor_player.advance(0.05)
	check(ModelLib.is_playing_loop(vendor_player, "idle"), "the vendor returns to idle after a handoff")
	check(vendor_player.speed_scale >= 0.93 and vendor_player.speed_scale <= 1.07,
		"the vendor's idle returns to a natural pace after a fast handoff (%.2f)" % vendor_player.speed_scale)
	ModelLib.ambient_variety = false
	var positions := {}
	for clip in ["idle", "walk"]:
		for speed in [1.0, 12.0]:
			var guest := ModelLib.spawn_guest("creek-abaya", stage)
			var player := ModelLib.animation_player(guest)
			ModelLib.set_manual_pose(guest, true)
			ModelLib.play_loop(guest, clip)
			ModelLib.sim_speed = speed
			# One rendered frame: Skip consumes twelve ticks where 1x consumes one.
			for tick in int(speed):
				ModelLib.step_pose(guest, 1.0 / 60.0)
			ModelLib.render_pose(guest)
			positions["%s@%d" % [clip, int(speed)]] = player.current_animation_position
	check(absf(positions["idle@12"] - positions["idle@1"]) < 0.002,
		"idle advances at the same pace at 1x and at Skip (%.3f vs %.3f)" % [positions["idle@1"], positions["idle@12"]])
	check(positions["walk@12"] > positions["walk@1"] * 6.0, "walking still follows the simulation clock at Skip")
	ModelLib.sim_speed = 1.0
	ModelLib.ambient_variety = true
	var phases := {}
	for i in 6:
		var guest := ModelLib.spawn_guest("creek-abaya", stage)
		ModelLib.play_loop(guest, "idle")
		phases[snappedf(ModelLib.animation_player(guest).current_animation_position, 0.05)] = true
	check(phases.size() >= 3, "people standing together do not idle in step (%d distinct phases of 6)" % phases.size())
	for model in World.DISTRICT_CAST["fahidi"]:
		var guest := ModelLib.spawn_guest(model, stage)
		check(guest != null and ModelLib.animation_player(guest).has_animation("idle") and ModelLib.animation_player(guest).has_animation("sit"),
			"%s keeps its standing and seated loops" % model)
	stage.free()

func _test_cast_appearances() -> void:
	var stage := Node3D.new()
	add_child(stage)
	for location in World.DISTRICT_CAST:
		for id in World.DISTRICT_CAST[location]:
			check(id != "souq-woman" and ModelLib.GUEST_HEIGHTS.has(id), "%s uses reviewed cast %s" % [location, id])
			check(not World.RETIRED_CAST.has(id), "%s keeps modest dress: %s is not on the street" % [location, id])
	var original := ModelLib.spawn_guest("creek-abaya", stage)
	var guest := ModelLib.spawn_guest("souq-abaya", stage)
	var woman := ModelLib.spawn_crew(true, stage, Vector3.ZERO, 0, 0.66)
	var man := ModelLib.spawn_crew(false, stage, Vector3.ZERO, 0, 0.66)
	for actor in [guest, woman, man]:
		check(actor != null and ModelLib.animation_player(actor).has_animation("walk"), "shared sculpt appearance keeps its rig")
	for actor in [woman, man]:
		check(ModelLib.animation_player(actor).has_animation("interact-right"), "crew appearance keeps a serving animation")
	var collect := ModelLib.animation_player(original).get_animation("collect")
	var loop_mode := collect.loop_mode
	ModelLib.play_loop(woman, "interact-right")
	check(collect.loop_mode == loop_mode, "looping crew service cannot change customer collection")
	var original_player := ModelLib.animation_player(original)
	var guest_player := ModelLib.animation_player(guest)
	ModelLib.play_loop(original, "idle")
	ModelLib.play_once(guest, "idle", "")
	var loop_clip := original_player.get_animation(original_player.current_animation)
	var once_clip := guest_player.get_animation(guest_player.current_animation)
	check(loop_clip.loop_mode == Animation.LOOP_LINEAR and once_clip.loop_mode == Animation.LOOP_NONE,
		"a one-shot idle does not change another actor's idle loop")
	var base_mesh: MeshInstance3D = original.find_children("*", "MeshInstance3D", true, false)[0]
	var crew_mesh: MeshInstance3D = woman.find_children("*", "MeshInstance3D", true, false)[0]
	check(base_mesh.mesh == crew_mesh.mesh, "female appearances share the approved geometry")
	check(base_mesh.get_active_material(0) != crew_mesh.get_active_material(0), "a colorway cannot recolor the original customer")
	var another := ModelLib.spawn_crew(true, stage, Vector3.ZERO, 0, 0.66)
	var another_mesh: MeshInstance3D = another.find_children("*", "MeshInstance3D", true, false)[0]
	check(another_mesh.get_active_material(0) == crew_mesh.get_active_material(0), "repeated appearances reuse their material and texture")
	stage.free()
	var main := get_parent()
	var before: float = get_viewport().scaling_3d_scale
	main.set_graphics_open(true)
	main.set_guide_open()
	check(get_viewport().scaling_3d_scale <= 0.5, "guide background uses a bounded rendering budget")
	main.set_graphics_open(false)
	check(is_equal_approx(get_viewport().scaling_3d_scale, before), "closing the guide restores the player's 3D quality")

func _test_terrace_clearance(game) -> void:
	# All districts use the same furnishing and routing contract at every fixed stage.
	var world := World.new()
	add_child(world)
	for location in Data.LOCATIONS:
		for tier in range(Plot.FIXED, Data.PLOT_STAGES.size()):
			for lounge in [0, 10]:
				if tier == Plot.FIXED and lounge > 0:
					continue
				game.new_game()
				game.location = location
				game.rig["stage"] = "truck"
				game.plot()["stage"] = Data.PLOT_STAGES[tier]["id"]
				game.plot()["stations"] = {"seating": 25, "majlis": lounge}
				if world.location_id == location:
					world.reload()
				else:
					world.set_location(location)
				var site: Plot = world.plot
				var tag := "%s/%s/majlis:%d" % [location, game.plot()["stage"], lounge]
				check(site.seats.size() == Plot.SEAT_CAP[tier], tag + " retains full dining capacity")
				var clear_routes := true
				var clear_furniture := true
				for i in site.tables.size():
					var center: Vector3 = site.tables[i]["pos"]
					for j in range(i):
						var other: Vector3 = site.tables[j]["pos"]
						if is_equal_approx(center.z, other.z) and absf(center.x - other.x) < 1.0:
							clear_furniture = false
					var route := site.staff_table_route(i)
					for k in range(route.size() - 1):
						var start := Vector2(route[k].x, route[k].z)
						var end := Vector2(route[k + 1].x, route[k + 1].z)
						for chair in site.seats:
							var p: Vector3 = chair["pos"]
							var point := Vector2(p.x, p.z)
							# 10 cm furniture radius + 12 cm worker clearance.
							if point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, end)) < 0.22:
								clear_routes = false
				check(clear_furniture, tag + " leaves walking space between table sets")
				check(clear_routes, tag + " worker routes clear every chair")
	world.free()
	game.new_game()

func _test_mobile_stages_and_lighting(game) -> void:
	game.new_game()
	game.money = 10000.0
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	check(world.cart._body.is_visible_in_tree() and world.cart._roof.is_visible_in_tree(), "starter cart has a visible body and roof")
	check(world.cart._wheels[0].is_visible_in_tree(), "starter cart has visible wheels")
	check(game.buy_stage(), "cart can be upgraded to the stall")
	world.apply_visual()
	check(world.cart._body.is_visible_in_tree() and not world.cart._roof.is_visible_in_tree(), "stall retains the counter and uses its own canopy")
	check(not world.cart._wheels[0].is_visible_in_tree(), "stall removes the cart wheels")
	check(game.buy_stage(), "stall can be upgraded to the truck")
	world.apply_visual()
	check(not world.cart._body.is_visible_in_tree() and world.plot.has_node("stage_2/ExtractorRotor"), "truck replaces the body with its own fitted geometry")
	var sim := DaySim.new()
	add_child(sim)
	sim.start(game.sim_context(), world)
	sim.hour = 18.6
	check(sim.finish_quickly(), "Skip starts while the stand is still open")
	sim._process(0.26)
	check(world.plot._night and world.plot._lights[0].visible, "Skip carries the truck into its lit evening")
	sim._close()
	check(world.env.environment.background_color.is_equal_approx(Color("242d50")), "closing retains the location's night lighting")
	world.set_time(10.0, "sunny")
	check(not world.plot._lights[0].visible, "opening the next morning switches the service lights off")
	game.money = 200000.0
	game.plot()["reputation"] = 1.0
	check(game.buy_stage() and game.buy_stage(), "truck can advance to the restaurant")
	world.apply_visual()
	check(game.buy_station_level("majlis"), "restaurant can install a Majlis")
	world.apply_visual()
	check(world.plot.seats.size() == 4 and world.plot.has_node("seating_2_2_4"), "Majlis adds four furnished seats without a Seating upgrade")
	check(game.buy_station_level("seating"), "standard seating can be installed alongside Majlis")
	world.apply_visual()
	check(world.plot.seats.size() == 6 and world.plot.has_node("seating_3_2_4"), "standard tables and Majlis furniture share the terrace")
	sim.queue_free()
	world.queue_free()
	game.new_game()

func _test_later_item_handoff(game) -> void:
	game.new_game()
	game.money = 100000.0
	game.buy_stage()
	game.buy_stage()
	for id in ["doner", "fryer", "sweets"]:
		game.buy_station_level(id)
	for id in Data.INGREDIENTS:
		game.inventory[id] = 30
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	var sim := DaySim.new()
	add_child(sim)
	var receipts: Array[Array] = []
	sim.sale_completed.connect(func(items: Array[String], _total: float): receipts.append(items))
	sim.start(game.sim_context(), world)
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["start"]:
			continue
		check(game.unlock_item(id), "unlock %s for handoff test" % id)
		var guest := world.spawn_guest(-1, world.pickup_slot(0))
		guest.wants = "side" # keep the order deterministic and omit random add-ons
		sim._on_served(guest, id, 0.0, false)
		check(not receipts.is_empty() and receipts.back() == [id], "%s sale reaches the animated receipt" % id)
		check(world.find_child("Served_" + id, true, false) != null, "%s has a visible handoff prop" % id)
		guest._finish()
	var rendered_guest := world.spawn_guest(-1, world.pickup_slot(0))
	sim.finish_quickly()
	check(Engine.time_scale == 1.0, "Skip leaves the engine and UI clock at normal speed")
	var player := ModelLib.animation_player(rendered_guest.model)
	var walk_rate := rendered_guest.speed / Customer.WALK_SPEED * Customer.WALK_ANIMATION_SPEED
	check(is_equal_approx(player.speed_scale, walk_rate), "Skip keeps existing footsteps in sync with movement")
	rendered_guest.slot = 100
	rendered_guest.position.z = World.PROMENADE_Z
	rendered_guest.leave()
	check(is_equal_approx(player.speed_scale, walk_rate), "takeaway footsteps stay in sync while walking away")
	sim.queue_free()
	world.queue_free()
	game.new_game()

func _test_skip_pickup(game) -> void:
	game.new_game()
	game.money = 100000.0
	game.buy_stage()
	game.buy_stage()
	game.buy_station_level("fryer")
	check(game.unlock_item("fries"), "unlock fries for the Skip pickup test")
	for id in Data.INGREDIENTS:
		game.inventory[id] = 30
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	var sim := DaySim.new()
	add_child(sim)
	sim.start(game.sim_context(), world)
	var receipts: Array[Array] = []
	var reports: Array[Dictionary] = []
	sim.sale_completed.connect(func(items: Array[String], _total: float): receipts.append(items))
	sim.finished.connect(func(stats: Dictionary): reports.append(stats))
	sim.finish_quickly()
	var invisible := world.spawn_walker(-1, true, false)
	sim._on_served(invisible, "fries", 0.0, false)
	check(sim.stats["served"] == 0 and receipts.is_empty() and game.inventory["fries"] == 30,
		"Skip cannot charge an invisible customer")
	var buyer := world.spawn_guest(-1, world.pickup_slot(0))
	buyer.wants = "side"
	buyer.slot = 100
	buyer.state = Customer.State.QUEUED
	check(sim._pickup_ready(buyer), "the actual Skip buyer reaches the pickup point")
	sim._on_served(buyer, "fries", 0.0, false)
	check(buyer.state == Customer.State.REACT and buyer.purchase_shown and receipts == [["fries"]],
		"each Skip receipt belongs to the actual buyer's animated collection")
	check(world.find_child("Served_fries", true, false) != null and game.inventory["fries"] == 29,
		"Skip hands over the purchased dish and consumes one portion")
	sim._on_served(buyer, "fries", 0.0, false)
	check(receipts.size() == 1 and game.inventory["fries"] == 29, "a repeated service callback cannot charge the buyer twice")
	check(not sim._pickup_ready(buyer), "an active handoff holds the pickup counter")
	sim._process(0.05)
	check(world._handoff_elapsed > 0.0 and world._handoff_elapsed <= 0.10 + 0.001 and buyer._bag == null,
		"Skip advances the pose and prop transfer no faster than the readable service speed")
	# Speed changes glide: a 4x day eases down to 2x for a handoff instead of snapping.
	sim.finishing = false
	sim.set_playback_speed(4.0)
	sim._speed_now = 4.0
	sim._process(0.05)
	var eased: float = sim._speed_now
	check(eased < 4.0 and eased > 2.0, "a handoff at 4x starts easing towards 2x (%.2f)" % eased)
	for frame in range(8):
		sim._process(0.05)
		if sim._handoff_left <= 0.0:
			break
	check(sim._handoff_left <= 0.0 or is_equal_approx(sim._speed_now, 2.0), "the eased speed settles at the readable 2x")
	sim.finishing = true
	sim._close()
	check(reports.is_empty(), "the closing curtain waits for the active handoff")
	for tick in range(45):
		sim._process(DaySim.STEP)
	check(is_instance_valid(buyer._bag) and buyer._bag.get_parent() == buyer,
		"the prop reaches the buyer before the report")
	check(reports.size() == 1 and sim.stats["served"] == 1, "Skip settles the actual purchase exactly once")
	sim.queue_free()
	world.queue_free()
	game.new_game()

func _test_reopen_same_district(game) -> void:
	game.new_game()
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	var sim := DaySim.new()
	add_child(sim)
	sim.start(game.sim_context(), world)
	var old_guest := world.spawn_walker(1)
	sim._publish_close()
	check(old_guest.is_processing(), "departing guests can finish walking after the report")
	world.set_location(game.location)
	sim.start(game.sim_context(), world)
	check(world.active_guests.is_empty() and world.walkers == 0 and old_guest.is_queued_for_deletion()
		and not old_guest.is_processing() and not old_guest.visible, "reopening retires guests from the prior day")
	var new_guest := world.spawn_walker(1)
	check(world.active_guests == [new_guest] and world.walkers == 1 and not new_guest.is_processing()
		and new_guest.model.scene_file_path == old_guest.model.scene_file_path, "reopening resets the cast and keeps the day as the sole guest driver")
	sim.free()
	world.free()

func _test_restaurant_service(game) -> void:
	game.new_game()
	game.money = 100000.0
	game.rig["stage"] = "truck"
	game.plot()["stage"] = "restaurant"
	game.plot()["stations"] = {"counter": 6, "grill": 6, "seating": 3}
	for id in Data.INGREDIENTS:
		game.inventory[id] = 30
	var needs := Economy.portion_ingredients("chicken_tikka", game.menu["chicken_tikka"])
	game.inventory["chicken"] = int(needs["chicken"])
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	var sim := DaySim.new()
	add_child(sim)
	sim.start(game.sim_context(), world)
	check(world.plot.dining_staff.size() == 2, "restaurant seating brings two service workers")
	var diner := world.spawn_guest(-1, world.queue_slot(0))
	diner.wants = "side"
	check(sim._choose_dining(diner, "chicken_tikka"), "a diner reserves a clean chair before cooking")
	var table := int(diner.seat["table"])
	var seat := int(diner.seat["idx"])
	sim._on_ordered(diner, "grill")
	check(diner.state == Customer.State.TO_SEAT, "dine-in customers walk to their booked table")
	diner._sit_down()
	sim.tp.seated.append({"payload": diner, "left": 1.0, "active": false})
	var receipts: Array[Array] = []
	var reports: Array[Dictionary] = []
	sim.sale_completed.connect(func(items: Array[String], _total: float): receipts.append(items))
	sim.finished.connect(func(stats: Dictionary): reports.append(stats))
	var starting_money: float = game.money
	sim._on_served(diner, "chicken_tikka", 0.0, true)
	check(sim.stats["served"] == 0 and game.money == starting_money and not sim.tp.seated[0]["active"],
		"food in transit creates no receipt and the diner waits to eat")
	check(not sim._stock_available("chicken_tikka"), "food on the server's tray is reserved against competing sales")
	check(not world.plot.tables[table]["node"].visible, "a waiting table starts without a meal")
	sim.finish_quickly()
	sim._close()
	var saw_delivery := false
	var saw_dirty := false
	var saw_cleaning := false
	var dirty_blocked := true
	for i in range(1000):
		for worker in world.plot.dining_staff:
			if worker.state == DiningStaff.State.CLEAN:
				saw_cleaning = true
		sim._process(0.05)
		if diner.purchase_shown:
			saw_delivery = true
		if world.plot.tables[table]["dirty"]:
			saw_dirty = true
			var free := world.plot.free_seat()
			dirty_blocked = dirty_blocked and (free.is_empty() or int(free["table"]) != table)
		if not sim.running:
			break
	check(saw_delivery and receipts == [["chicken_tikka"]] and sim.stats["served"] == 1,
		"the server visibly delivers before recording a single sale")
	check(saw_dirty and saw_cleaning and world.plot.service_stats["cleaned"] == 1,
		"a real worker clears the used table after the diner leaves")
	check(dirty_blocked, "a dirty table stays unavailable for the whole clearing job")
	check(not world.plot.tables[table]["dirty"] and not world.plot.seats[seat]["needs_clean"],
		"the table becomes available after clearing finishes")
	check(sim.tp.seated.is_empty() and sim._pending_deliveries.is_empty() and reports.size() == 1,
		"closing drains deliveries, diners, and cleaning before settling once")
	check(is_equal_approx(game.money - starting_money, float(sim.stats["revenue"])) and game.inventory["chicken"] == 0,
		"dine-in payment matches revenue and consumes the reserved portion once")
	sim.queue_free()
	world.queue_free()
	game.new_game()

## The closing render used to read the position of a plate the table had already cleared
## (headless days never drew the hand-over, so the reference outlived the plate).
func _test_closing_meal_handoff(game) -> void:
	game.new_game()
	game.money = 100000.0
	game.rig["stage"] = "truck"
	game.plot()["stage"] = "restaurant"
	game.plot()["stations"] = {"counter": 6, "grill": 6, "seating": 4}
	for id in Data.INGREDIENTS:
		game.inventory[id] = 400
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	var worker: DiningStaff = world.plot.dining_staff[0]
	var cleared := Node3D.new()
	world.plot.add_child(cleared)
	worker._meal = cleared
	worker._meal_target = cleared.global_position + Vector3(0.3, 0.0, 0.0)
	worker._meal_elapsed = 0.0
	world.plot.remove_child(cleared)
	worker.step(1.0 / 60.0)
	worker.render_service()
	check(worker.meal_in_hand() == null, "a plate cleared off its table mid hand-over is let go before the closing render")
	cleared.free()
	var plate := Node3D.new()
	world.plot.add_child(plate)
	var target := plate.global_position + Vector3(0.3, 0.0, 0.0)
	worker._meal = plate
	worker._meal_target = target
	worker._meal_elapsed = 0.0
	for i in range(6):
		worker.step(1.0 / 60.0)
	check(worker.meal_in_hand() == plate, "the plate is still in the server's hands a few ticks in")
	for i in range(20):
		worker.step(1.0 / 60.0)
	check(worker.meal_in_hand() == null and plate.global_position.is_equal_approx(target), "undrawn ticks set the plate down on its spot")
	plate.queue_free()
	game.weather = "sunny"
	game.forecast = "sunny"
	game.weather_day = game.day
	game.day_seed = 104729
	var sim := DaySim.new()
	add_child(sim)
	var stats := DayRunner.play(sim, world, game.sim_context())
	var held := 0
	for w in world.plot.dining_staff:
		if w.meal_in_hand() != null:
			held += 1
	check(not stats["_unfinished"] and int(stats["dine_in"]) > 0 and held == 0,
		"a played restaurant day closes with every plate set down (%d diners)" % int(stats["dine_in"]))
	sim.queue_free()
	world.queue_free()
	game.new_game()

## A fixed stage at the parity run's mid levels: the full menu, ample stock, the
## autoplayer's prices. Same setup as tests/balance_curve.gd's location matrix. A rig tier
## (cart, stall, truck) puts the same levels on the rig.
func _setup_fixed(game, tier: int, location: String, pop: float) -> void:
	var levels: Dictionary = load("res://tests/sim_parity.gd").get_script_constant_map()["LEVELS"][tier]["mid"]
	game.new_game()
	game.day = int(Data.OPENING["days"]) + 1 # a steady-state day, after the opening buzz
	game.money = 1e7
	game.popularity = pop
	game.weather = "sunny"
	game.forecast = "sunny"
	game.weather_day = game.day
	var def: Dictionary = Data.stage_def(tier)
	var stations := {}
	for id in levels:
		if id in def["stations"]:
			stations[id] = mini(int(levels[id]), Economy.station_level_cap(Data.STATIONS[id], def))
	game.rig["stage"] = "truck" if tier >= 3 else def["id"]
	game.rig["stations"] = {} if tier >= 3 else stations
	game.location = location
	game.plots[location] = {"stage": def["id"] if tier >= 3 else "", "stations": stations if tier >= 3 else {}, "reputation": pop, "last_visit": game.day}
	for id in Data.MENU_ITEMS:
		var on: bool = game.item_available(id)
		game.menu[id]["unlocked"] = on
		game.menu[id]["enabled"] = on
		game.menu[id]["recipe"] = {"meat": 3, "veg": 3, "sauce": 2}
		game.menu[id]["level"] = mini(tier, Data.MENU_ITEMS[id]["enhance"].size())
	for id in Data.INGREDIENTS:
		game.inventory[id] = 5000
	game.clamp_prices()
	Autoplayer.prices()

## With the terrace at mid levels, a visible share of buyers sit down: at least a fifth of
## kiosk buyers and three in ten restaurant buyers (each one a seated, served guest).
func _test_dine_in_share(game) -> void:
	for tier in [3, 4]:
		var want := 0.20 if tier == 3 else 0.30
		var diners := 0
		var buyers := 0
		var est_diners := 0.0
		var est_buyers := 0.0
		for location in ["creek", "downtown"]:
			_setup_fixed(game, tier, location, 0.8)
			var world := World.new()
			add_child(world)
			world.set_location(location)
			var est := Economy.throughput_estimate(game.sim_context())
			est_diners += float(est["dine_in"])
			est_buyers += float(est["served"])
			for i in range(3):
				_setup_fixed(game, tier, location, 0.8)
				game.day_seed = 224737 + 7919 * i
				var sim := DaySim.new()
				add_child(sim)
				var stats := DayRunner.play(sim, world, game.sim_context())
				diners += int(stats["dine_in"])
				buyers += int(stats["served"])
				sim.free()
			world.free()
		var name: String = Data.stage_def(tier)["id"]
		check(float(diners) / maxf(1.0, float(buyers)) >= want,
			"%s at mid seating: %d of %d played buyers ate in (>= %.0f%%)" % [name, diners, buyers, 100.0 * want])
		check(est_diners / maxf(1.0, est_buyers) >= want,
			"%s at mid seating: the estimate seats %.0f%% of buyers too" % [name, 100.0 * est_diners / maxf(1.0, est_buyers)])
	game.new_game()

func _test_daily_stock(game) -> void:
	game.new_game()
	game.weather = "sunny"
	game.forecast = "sunny"
	var before: Dictionary = game.inventory.duplicate(true)
	var plan: Dictionary = game.daily_stock_plan()
	check(float(plan["cost"]) > 0 and game.inventory == before and game.money == Data.START_MONEY, "daily quote does not change stock or money")
	game.money = 1.0
	check(not game.stock_for_today() and game.inventory == before and game.money == 1.0, "unaffordable daily order buys nothing")
	game.money = Data.START_MONEY
	check(game.stock_for_today() and game.food_on_sale(), "daily stock makes a fresh game playable in one tap")
	check(is_equal_approx(game.money, Data.START_MONEY - float(plan["cost"])), "daily order charges exactly the displayed quote")
	var stocked_money: float = game.money
	check(not game.stock_for_today() and game.money == stocked_money, "repeated daily stock tap cannot buy surplus")
	game.new_game()
	game.location = "creek"
	plan = game.daily_stock_plan()
	game.money = float(plan["cost"]) + float(game.loc()["rent"]) - 1.0
	check(not game.stock_for_today(), "daily stock keeps rent aside")
	game.new_game()
	game.plot()["stage"] = "flagship"
	for id in Data.STATIONS:
		game.plot()["stations"][id] = 4
	for id in game.menu:
		game.menu[id]["unlocked"] = true
		game.menu[id]["enabled"] = true
	game.money = 1000000.0
	check(game.stock_for_today() and game.inventory["cake"] > 0 and game.inventory["fries"] > 0, "daily stock covers unlocked sides and sweets at a large restaurant")
	game.new_game()

func _test_economy() -> void:
	var entry := {"recipe": {"meat": 2, "veg": 2, "sauce": 1}, "level": 0}
	var q := Economy.item_quality("chicken_tikka", entry)
	check(q > 0.8 and q < 0.9, "default chicken tikka quality is 'good' (%f)" % q)
	entry["recipe"] = {"meat": 1, "veg": 0, "sauce": 0}
	check(Economy.item_quality("chicken_tikka", entry) < 0.5, "stingy recipe is poor")
	entry["recipe"] = {"meat": 3, "veg": 3, "sauce": 2}
	entry["level"] = 3
	check(Economy.item_quality("chicken_tikka", entry) > 1.15, "maxed chicken tikka is legendary")
	var loc: Dictionary = Data.LOCATIONS["fahidi"]
	var w: Dictionary = Data.WEATHER["sunny"]
	var v_fair := Economy.item_value("chicken_tikka", 0.85, 10.0, loc, w)
	var v_pricey := Economy.item_value("chicken_tikka", 0.85, 25.0, loc, w)
	check(v_pricey < v_fair * 0.4, "doubling price slashes value")
	check(Economy.stop_probability(0.2, 0.9, 0.0, 4, 4) == 0.0, "full queue means nobody joins")
	var quiet := Economy.stop_probability(0.4, 0.9, 0.0, 0, 4, 0.0, 1.0)
	var rivals := Economy.stop_probability(0.4, 0.9, 0.0, 0, 4, 0.6, 1.8)
	var promoted := Economy.stop_probability(0.4, 0.9, 0.3, 0, 4, 0.6, 1.8)
	check(rivals < quiet * 0.5, "rivals halve stops without promotion")
	check(promoted > quiet, "promotion drowns out rivals and then some")
	check(is_zero_approx(Economy.competition_loss(0.6, 0.3, 1.8)), "a +30% campaign at x1.8 covers competition fully")
	check(Economy.stop_probability(1.0, 1.2, 0.3, 0, 4) > Economy.stop_probability(0.2, 0.9, 0.0, 0, 4), "popular + marketed stand attracts more")
	var t_sun := Economy.traffic_per_hour(loc, "sunny", 13.0, false)
	var t_rain := Economy.traffic_per_hour(loc, "sandstorm", 13.0, false)
	check(t_rain < t_sun * 0.6, "sandstorm cuts traffic")
	check(Economy.traffic_per_hour(loc, "sandstorm", 13.0, true) > t_rain, "shade sail helps in a sandstorm")
	check(Economy.arrival_rate(loc, "sandstorm", 13.0, {"shade_level": 1}) > Economy.arrival_rate(loc, "sandstorm", 13.0, {}), "shade station halves the storm loss")
	check(Economy.arrival_rate(loc, "sunny", 20.0, {"lights_level": 5}) > Economy.arrival_rate(loc, "sunny", 20.0, {}), "lights draw an evening crowd")
	check(is_equal_approx(Economy.arrival_rate(loc, "sunny", 12.0, {"lights_level": 5}), Economy.arrival_rate(loc, "sunny", 12.0, {})), "lights do nothing at noon")
	check(Economy.satisfaction(1.1, 1.0, 0.0, loc, 0.0) > Economy.satisfaction(0.6, 1.0, 0.0, loc, 0.0), "quality raises satisfaction")
	check(Economy.unit_cost("chicken_tikka", {"recipe": {"meat": 2, "veg": 2, "sauce": 1}}) < 8.0, "chicken tikka costs under AED 8 to make")
	check(is_equal_approx(Economy.reputation_decay(0.5, 10), 0.46) and Economy.reputation_decay(0.12, 50) == 0.1, "reputation decays slowly with a floor")
	check(is_equal_approx(Economy.effective_popularity(0.5, 1.0), 0.7), "effective popularity mixes global and local")

func _test_stations() -> void:
	var counter: Dictionary = Data.STATIONS["counter"]
	check(Economy.station_cost(counter, 0) == 250.0, "counter level 1 costs the base price")
	var c10 := Economy.station_cost(counter, 10)
	check(c10 > 250.0 * 7.0 and c10 < 250.0 * 7.6 and fmod(c10, 50.0) == 0.0, "counter level 11 costs base x 1.22^10 rounded (%s)" % c10)
	check(is_equal_approx(Economy.order_seconds(1, 0), float(Data.SERVICE["order_s"])) and Economy.queue_cap(0, Data.stage_def(0)) == 4,
		"day-1 parity: a single order takes the service table's beat, 4 in line")
	check(Economy.order_seconds(4, 0) > Economy.order_seconds(1, 0) and Economy.handoff_seconds(4, 0) > Economy.handoff_seconds(1, 0),
		"a family's order and bag take longer than a single portion")
	check(Economy.counter_capacity(10) >= Economy.counter_capacity(0) * 1.9 and Economy.order_seconds(4, 10) < Economy.order_seconds(4, 0) * 0.55,
		"ten counter levels about double order and handoff speed")
	check(Economy.queue_cap(3, Data.stage_def(2)) == 4 + 3 + 2, "queue cap adds counter levels and the stage bonus")
	check(Economy.kitchen_capacity("doner", 0) == 0.0 and Economy.kitchen_capacity("doner", 1) > 0.0, "doner spit does nothing until installed")
	check(is_equal_approx(Economy.kitchen_capacity("grill", 0), 1.0 / float(Data.SERVICE["cook_s"]["grill"])),
		"a level-0 grill cooks one portion per cook_s seconds of the played day")
	check(is_equal_approx(Economy.kitchen_capacity("grill", 3) / Economy.kitchen_capacity("grill", 0), 1.0 + 3.0 * float(Data.STATIONS["grill"]["per_level"])),
		"grill levels add their per-level speed")
	check(Economy.buyer_budget(5, 20) + Economy.ambient_budget(5) <= int(Data.GUEST_BUDGET["total_max"]) and Economy.buyer_budget(0, 0) < Economy.buyer_budget(4, 0),
		"bigger stages put more rigged buyers on the street, never past the frame-time cap")
	check(Economy.buyer_budget(3, 10) > Economy.buyer_budget(3, 0), "counter tiers add buyer places")
	var party := Economy.party_weights(5, "downtown")
	check(Economy.party_mean(party) > Economy.party_mean(Economy.party_weights(0, "fahidi")) * 2.0, "flagship parties are far larger than at the cart")
	var draw := RandomNumberGenerator.new()
	draw.seed = 9
	var sizes := {}
	for i in range(400):
		sizes[Economy.pick_party(Economy.party_weights(0, "fahidi"), draw)] = true
	check(sizes.keys().all(func(n): return int(n) >= 1 and int(n) <= 2), "the cart sells to singles and pairs")
	var mix := Economy.kitchen_capacity_mix({"grill": 1.0, "karak": 2.0}, {"grill": 0.78, "karak": 0.22})
	check(mix > 1.0 and mix < 2.0 and mix < 1.0 / 0.78, "harmonic mix sits between the slowest and fastest station (%f)" % mix)
	check(Economy.kitchen_capacity_mix({"grill": 1.0}, {"": 1.0}) == INF, "counter-only items need no kitchen")
	check(Data.station_tier(0) == 0 and Data.station_tier(1) == 1 and Data.station_tier(3) == 1 and Data.station_tier(4) == 2 and Data.station_tier(10) == 4, "station visual tiers at 1/4/7/10")
	check(Economy.dine_in_share(Data.stage_def(0), 0) == 0.0 and Economy.dine_in_share(Data.stage_def(3), 12) > 0.2, "dine-in needs the kiosk and seats")
	check(Economy.bottleneck({"counter": 0.95, "grill": 0.4}) == "counter", "bottleneck names the saturated stage")
	check(Economy.bottleneck({"counter": 0.2, "grill": 0.3}) == "arrivals", "idle everywhere means you need customers")
	check(Economy.bottleneck({"counter": 0.6, "grill": 0.7}) == "", "comfortable load has no bottleneck")

func _ctx_for(game, stations: Dictionary, stage: int, location: String = "fahidi") -> Dictionary:
	return game.what_if({"stations": stations, "stage": stage, "location": location})

func _test_game_flow(game) -> void:
	game.new_game()
	check(game.money == Data.START_MONEY, "start money")
	check(game.stage_tier() == 0 and not game.is_fixed(), "start at the cart")
	check(game.portions_possible("chicken_tikka") == 0, "no stock at start")
	check(game.buy_pack("bread", 0) and game.buy_pack("chicken", 0) and game.buy_pack("veg", 0) and game.buy_pack("sauce", 0) and game.buy_pack("charcoal", 0), "buying packs")
	check(game.portions_possible("chicken_tikka") == 5, "10 chicken / 2 per chicken tikka = 5 portions (%d)" % game.portions_possible("chicken_tikka"))
	var before: float = game.money
	check(game.sell("chicken_tikka", 10.0), "sell one")
	check(game.money == before + 10.0, "money after sale")
	check(game.inventory["chicken"] == 8, "chicken consumed")
	check(not game.unlock_item("chicken_tikka"), "cannot re-unlock")
	game.money = 10.0
	check(not game.unlock_item("mutton_tikka"), "cannot afford mutton tikka")
	check(not game.buy_station_level("counter"), "cannot afford a counter level")
	game.money = 5000.0
	check(game.unlock_item("mutton_tikka") and game.menu["mutton_tikka"]["unlocked"], "unlock mutton tikka")
	check(game.buy_station_level("coldbox") and game.station_level("coldbox") == 1, "buy cold storage")
	check(is_equal_approx(game.spoil_rate("chicken"), 0.1) and is_zero_approx(game.spoil_rate("drink")) and is_equal_approx(game.spoil_rate("veg"), 0.2), "spoil_rate with a fridge")
	check(not game.buy_station_level("doner"), "doner spit needs the stall")
	check(not game.item_available("fries") and not game.unlock_item("fries"), "fries need a fryer")
	check(not game.set_location("metro"), "metro needs the stall")
	check(not game.set_location("mall"), "mall needs the truck")
	check(game.buy_station_level("counter") and game.queue_capacity() == 5 and game.counter_capacity() > 0.5, "a counter level adds a place in line and speed")
	game.money = 20000.0
	var money_before: float = game.money
	check(game.buy_stage() and game.stage_tier() == 1 and game.rig["stage"] == "stall", "build the stall")
	check(is_equal_approx(money_before - game.money, float(Data.PLOT_STAGES[1]["cost"])), "the stall costs its listed price")
	check(game.location_stage_ok("metro") and not game.location_stage_ok("mall"), "stall reaches metro, not the mall")
	check(game.buy_station_level("doner") and game.item_available("shawarma"), "doner spit unlocks shawarma")
	check(game.unlock_item("shawarma") and game.menu["shawarma"]["unlocked"], "add shawarma to the menu")
	check(game.buy_station_level("fryer") and game.unlock_item("fries"), "fryer then fries")
	game.money = 20000.0
	check(game.buy_stage() and game.rig["stage"] == "truck", "build the food truck")
	check(game.station_available("sweets") and game.buy_station_level("sweets") and game.item_available("saffron_cake") and game.unlock_item("saffron_cake"), "sweets counter then a sweet")
	game.popularity = 0.9
	check(game.set_location("mall") and game.competition() > 0.0, "mall reachable with the truck")
	check(game.queue_capacity() == 4 + 1 + 2, "queue at the mall: base + counter level + truck bonus")
	for ing in Data.INGREDIENTS:
		game.inventory[ing] = 300
	var fast := FastSim.run(game.sim_context(), game.rng)
	check(int(fast["passers"]) > 50 and int(fast["served"]) > 0 and float(fast["revenue"]) > 0.0, "FastSim produces a day (%s passers, %s served)" % [fast["passers"], fast["served"]])
	check(int(fast["lost_rival"]) > 0, "FastSim counts customers lost to rivals at the mall")
	check(fast.has("util") and fast["util"].has("counter"), "FastSim reports utilisation")
	game.inventory["chicken"] = 100
	var r: Dictionary = game.end_day({"served": 20, "revenue": 240.0, "cogs": 120.0, "satisfaction_sum": 14.0, "sold": {"chicken_tikka": 20}, "util": {"counter": 0.9}})
	check(game.inventory["chicken"] == 90, "fridge keeps 90%% of chicken (%d)" % game.inventory["chicken"])
	check(r["profit"] < 120.0, "profit accounts for spoilage")
	check(r["bottleneck"] == "counter", "report names the bottleneck")
	check(game.day == 2, "day advanced")
	check(game.popularity > Data.START_POPULARITY, "good day raises popularity")
	check(game.local_reputation() > Data.START_POPULARITY, "good day raises local reputation too")
	check(game.stats["days_played"] == 1 and game.stats["best_day_served"] == 20, "stats track the day")

func _test_stages(game) -> void:
	game.new_game()
	game.money = 200000.0
	check(game.stage_lock_reason() == "", "stall is buildable at once")
	game.buy_stage()
	game.buy_stage()
	check(game.stage_tier() == 2, "two builds reach the truck")
	game.buy_station_level("grill")
	game.buy_station_level("grill")
	game.buy_station_level("counter")
	check(game.stage_lock_reason() != "", "kiosk needs local reputation")
	check(game.stage_lock_reason().contains(game.fame_name(1)), "the kiosk lock names the local fame level (%s)" % game.stage_lock_reason())
	game.plot()["reputation"] = 0.35 # Known on the street here, not yet a Local favourite
	check(game.stage_lock_reason() == "", "kiosk unlocks with local reputation (%s)" % game.stage_lock_reason())
	check(game.buy_stage() and game.is_fixed() and game.plot()["stage"] == "kiosk", "build a kiosk at fahidi")
	check(game.station_level("grill") == 2 and game.station_level("counter") == 1 and game.rig["stations"].is_empty(), "rig station levels move into the kiosk")
	check(game.rig["stage"] == "truck", "the truck is still yours")
	check(game.station_available("seating") and game.buy_station_level("seating") and game.seats() == 2, "seating gives 2 seats per level")
	check(game.sim_context()["dine_in_share"] > 0.0, "kiosk serves dine-in")
	check(game.stage_lock_reason() != "", "restaurant needs more local reputation (%s)" % game.stage_lock_reason())
	check(game.levels_owned() == 4, "levels owned counts rig and plots (%d)" % game.levels_owned())
	check(game.set_location("creek") and not game.is_fixed() and game.stage_tier() == 2 and game.station_level("grill") == 0, "at creek you are back on the truck with an empty rig")
	check(game.set_location("fahidi") and game.is_fixed() and game.station_level("grill") == 2, "back at fahidi the kiosk is waiting")
	var est := Economy.throughput_estimate(game.sim_context())
	check(float(est["served"]) > 0.0 and est["util"].has("seating"), "estimate covers seating at the kiosk")
	# capacity saturates: a maxed kiosk serves a lot, and an empty one much less
	game.weather = "sunny"
	game.weather_day = game.day # the day has opened on this weather
	game.popularity = 0.9
	var big := Economy.throughput_estimate(_ctx_for(game, {"counter": 15, "grill": 15, "karak": 10, "seating": 10}, 3, "downtown"))
	var small := Economy.throughput_estimate(_ctx_for(game, {"counter": 0, "grill": 0}, 3, "downtown"))
	check(float(big["served"]) > float(small["served"]) * 1.2, "more station levels, more customers served downtown (%s vs %s)" % [big["served"], small["served"]])
	check(small["bottleneck"] == "grill" and float(big["util"]["grill"]) < float(small["util"]["grill"]),
		"an empty kiosk downtown is held up by its level-0 grill; levels relieve it (%s)" % str(small["util"]))
	check(game.station_level("grill") == 2 and game.location == "fahidi", "what_if leaves the state alone")
	# a maxed kiosk day in FastSim
	for id in ["counter", "grill", "karak", "seating"]:
		game._station_store()[id] = 12
	game.popularity = 0.9
	game.plot()["reputation"] = 0.9
	for ing in Data.INGREDIENTS:
		game.inventory[ing] = 1000
	game.weather = "sunny"
	game.rng.seed = 2026 # a fixed day
	var fast := FastSim.run(game.sim_context(), game.rng)
	# the free souk is the quiet place (Release 2b): fewer passers-by, smaller groups
	check(int(fast["portions"]) > 70 and int(fast["portions"]) > int(fast["served"]) * 2 and int(fast["dine_in"]) > 5,
		"maxed kiosk day at the quiet souk still sells group portions, with diners (%s portions, %s buyers, %s dined)" % [fast["portions"], fast["served"], fast["dine_in"]])

func _test_goals(game) -> void:
	game.new_game()
	check(game.current_goal()["id"] == "first_30" and not game.goal_ready(), "first goal waits for 8 customers")
	check(not game.claim_goal(), "cannot claim early")
	game.inventory["chicken"] = 500
	game.end_day({"served": 7, "revenue": 70.0, "cogs": 25.0, "satisfaction_sum": 5.0, "sold": {}})
	check(not game.goal_ready(), "seven served in a day is one short")
	game.end_day({"served": 12, "revenue": 120.0, "cogs": 40.0, "satisfaction_sum": 8.0, "sold": {}})
	check(game.goal_ready(), "8 served in a day completes the first goal")
	var m: float = game.money
	check(game.claim_goal() and game.money == m + float(Data.GOALS[0]["reward"]["money"]) and game.goal_index == 1 and game.goals_claimed == ["first_30"], "claim pays once and advances")
	check(not game.claim_goal(), "next goal not ready yet")
	game.money = 1000.0
	game.buy_station_level("counter")
	check(game.goal_ready() and game.claim_goal() and game.current_goal()["id"] == "stars15", "counter goal, then stars")
	check(game.goal_progress() > 0.5 and game.goal_progress() < 1.0, "progress toward 1.5 stars is partial")

## Every rung of the ladder is a goal type the game measures, met by a played-day-sized day
## (Release 2b thresholds: portions where "plates" are meant, diners a kiosk terrace seats).
func _test_goal_ladder(game) -> void:
	var known := ["day_served", "day_portions", "day_profit", "day_dine_in", "total_served", "fame", "dish_level", "levels_owned",
		"stage", "station_level", "location", "location_any", "item_unlocked"]
	var ids := {}
	for goal in Data.GOALS:
		var req: Dictionary = goal["req"]
		check(String(req["type"]) in known, "goal %s has a measured type (%s)" % [goal["id"], req["type"]])
		check(not ids.has(goal["id"]) and float(goal["reward"].get("money", 0.0)) > 0.0, "goal %s is unique and pays" % goal["id"])
		ids[goal["id"]] = true
		check(Economy.goal_progress(goal, {}) < 1.0, "goal %s is not met by an empty snapshot" % goal["id"])
	var played := {"day_served": 25, "day_portions": 320, "day_profit": 450.0, "day_dine_in": 9, "total_served": 250, "fame": 4.0, "dish_level": 1,
		"levels_owned": 60, "stage": 5, "stations": {"counter": 1, "grill": 3, "coldbox": 1}, "visited": ["creek", "downtown"], "unlocked": ["shawarma"]}
	for goal in Data.GOALS:
		check(is_equal_approx(Economy.goal_progress(goal, played), 1.0), "goal %s is reachable by a strong played day" % goal["id"])
	var plates := {}
	var buyers := {}
	for goal in Data.GOALS:
		if goal["id"] == "served300":
			plates = goal
		if goal["id"] == "first_30":
			buyers = goal
	check(String(plates["req"]["type"]) == "day_portions" and int(plates["req"]["n"]) == 300, "three hundred plates count portions, not buyers")
	check(Economy.goal_progress(plates, {"day_served": 300, "day_portions": 120}) < 0.5, "300 buyers' worth of headcount is not 300 plates")
	check(int(buyers["req"]["n"]) <= 15, "the first goal fits a cart day of 5-15 buyers")
	# The goal snapshot reads portions from the report (older reports only have buyers).
	game.new_game()
	game.end_day({"served": 30, "portions": 140, "revenue": 900.0, "cogs": 200.0, "satisfaction_sum": 20.0, "sold": {}})
	check(int(game.goal_snapshot()["day_portions"]) == 140, "goal snapshot carries the day's portions")
	game.history.back().erase("portions")
	check(int(game.goal_snapshot()["day_portions"]) == 30, "a report without portions counts its buyers")
	# A place counts once a day opens there, not when the prep screen passes through it.
	game.new_game()
	game.money = 5000.0
	check(game.set_location("creek") and game.set_location("fahidi"), "prep can pass through the Creek")
	check(not "creek" in game.goal_snapshot()["visited"], "passing through on the prep screen is not a day at the Creek")
	game.set_location("creek")
	game.begin_day()
	check("creek" in game.goal_snapshot()["visited"], "opening a day at the Creek visits it")
	game.new_game()

func _test_save_load(game) -> void:
	game.new_game()
	game.set_price("chicken_tikka", 15.0)
	game.set_recipe("chicken_tikka", "meat", 3)
	game.money = 200000.0
	game.buy_station_level("shade")
	game.buy_stage()
	game.buy_stage()
	game.plot()["reputation"] = 0.6
	game.buy_stage()
	game.buy_station_level("seating")
	game.goal_index = 2
	game.goals_claimed = ["first_30", "counter1"]
	game.money = 777.0
	game.tutorial = GuideJourney.clean({"active": true, "step": 4, "done": true, "price": 14.0})
	game.save()
	game.new_game()
	check(game.load_game(), "load ok")
	check(game.money == 777.0, "money restored")
	check(game.tutorial["active"] and game.tutorial["step"] == 4 and game.tutorial["done"] and game.tutorial["price"] == 14.0, "mentor progress and action baselines survive reload")
	check(game.menu["chicken_tikka"]["price"] == 15.0, "price restored")
	check(game.menu["chicken_tikka"]["recipe"]["meat"] == 3, "recipe restored")
	check(game.rig["stage"] == "truck" and game.plot()["stage"] == "kiosk", "stages restored")
	check(game.station_level("shade") == 1 and game.station_level("seating") == 1, "station levels restored")
	check(game.goal_index == 2 and game.goals_claimed.size() == 2, "goals restored")
	game.delete_save()
	check(not game.has_save(), "save deleted")
	game.new_game()
	game.money = 5.0
	game.prepare_day()
	check(game.money == 5.0 + Data.BAILOUT_AMOUNT and game.bailouts == 1, "bailout when broke")
	game.prepare_day()
	check(game.bailouts == 1, "no bailout when solvent")
	game.money = 5.0
	game.prepare_day()
	check(game.bailouts == 1 and game.money == 5.0, "reopening prep on the same day lends nothing more")
	game.day += 1
	game.prepare_day()
	check(game.bailouts == 2, "the next day's prep can lend again")
	check(game.expected_customers() > 5, "expected customers estimate (%d)" % game.expected_customers())

func _test_pricing(game) -> void:
	var fahidi: Dictionary = Data.LOCATIONS["fahidi"]
	var gv: Dictionary = Data.LOCATIONS["gv"]
	var r_f := Economy.price_range("chicken_tikka", fahidi)
	var r_gv := Economy.price_range("chicken_tikka", gv)
	check(r_f[0] == 5.0 and r_f[1] == 15.0, "fahidi chicken tikka range is 5-15 (%s)" % str(r_f))
	check(r_gv[1] > r_f[1], "global village allows higher prices than fahidi (%s)" % str(r_gv))
	check(Economy.price_range("chicken_tikka", fahidi, Data.stage_def(3))[1] > r_f[1], "a kiosk raises the price cap")
	check(Economy.price_range("karak", fahidi)[0] >= 1.0, "cheapest item never drops below 1 AED")
	for id in Data.LOCATIONS:
		var r := Economy.price_range("mixed", Data.LOCATIONS[id])
		check(r[1] <= 45.0 * 2.5 and r[1] >= 45.0, "%s platter cap stays sane (%s)" % [id, str(r)])
	game.new_game()
	game.set_price("chicken_tikka", 200.0)
	check(game.menu["chicken_tikka"]["price"] == 15.0, "set_price clamps to the location cap")
	game.set_price("chicken_tikka", 0.0)
	check(game.menu["chicken_tikka"]["price"] == 5.0, "set_price clamps to the floor")
	game.money = 50000.0
	game.popularity = 1.0
	game.buy_stage()
	game.buy_stage()
	check(game.set_location("gv"), "move to global village")
	game.set_price("chicken_tikka", 20.0)
	check(game.menu["chicken_tikka"]["price"] == 20.0, "20 AED allowed at global village")
	check(game.set_location("fahidi") and game.menu["chicken_tikka"]["price"] == 17.0, "moving back clamps the price again (truck cap 1.7x)")
	# overpricing must not pay: compare expected AED per passer at base vs max vs 3x price
	var w: Dictionary = Data.WEATHER["sunny"]
	var q := 0.85
	var per_passer := func(price: float, loc: Dictionary) -> float:
		var v := Economy.item_value("chicken_tikka", q, price, loc, w)
		return Economy.stop_probability(0.5, v, 0.0, 0, 4) * price
	var fair: float = per_passer.call(10.0, fahidi)
	var maxed: float = per_passer.call(15.0, fahidi)
	var greedy: float = per_passer.call(30.0, fahidi)
	check(maxed < fair, "max allowed price earns less per passer than the fair price (%.2f vs %.2f)" % [maxed, fair])
	check(greedy < fair * 0.6, "3x price earns well under the fair price per passer (%.2f vs %.2f)" % [greedy, fair])
	var v3 := Economy.item_value("chicken_tikka", q, 30.0, fahidi, w)
	var v1 := Economy.item_value("chicken_tikka", q, 10.0, fahidi, w)
	check(Economy.stop_probability(0.5, v3, 0.0, 0, 4) < Economy.stop_probability(0.5, v1, 0.0, 0, 4) * 0.25, "3x price cuts stops to under a quarter")
	check(Economy.stop_probability(0.5, 0.0, 0.0, 0, 4) == 0.0, "worthless menu stops nobody")

func _write_save(game, d: Dictionary) -> void:
	var f := FileAccess.open(game.save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()

func _test_save_validation(game) -> void:
	game.new_game()
	# a version-3 save written by hand with out-of-range values everywhere
	var bad := {
		"version": 3, "money": 1234.0, "day": 7, "popularity": 4.0, "location": "mall",
		"rig": {"stage": "kiosk", "stations": {"grill": 99, "seating": 3, "ghost": 2}},
		"plots": {"creek": {"stage": "cart", "stations": {"grill": 1}, "reputation": 7.0, "last_visit": 99},
			"nowhere": {"stage": "kiosk"}, "jbr": {"stage": "kiosk", "stations": {"seating": 50, "office": 1}, "reputation": 0.5, "last_visit": 3}},
		"goal_index": 99, "goals_claimed": ["first_30", "bogus"], "stats": {"days_played": -4, "best_day_profit": "x"},
		"menu": {"chicken_tikka": {"unlocked": true, "enabled": true, "price": 200.0, "level": 9, "recipe": {"meat": 7, "veg": -1, "sauce": 1}},
			"soda": {"unlocked": true, "enabled": true, "price": 0.0, "level": 0, "recipe": {}}},
		"inventory": {"bread": -5}, "history": [1, "x", {"location": "nowhere"}, {"location": "creek", "weather": "sunny", "served": 3}],
		"marketing": {"fliers": 0},
	}
	_write_save(game, bad)
	var summary: Dictionary = game.save_summary()
	check(summary.get("day", 0) == 7 and summary.get("money", 0.0) == 1234.0, "save summary reads day and money")
	check(game.load_game(), "bad save loads")
	check(game.rig["stage"] == "cart", "a kiosk rig is reset to the cart")
	check(game.rig["stations"].get("grill", 0) == 25 and not game.rig["stations"].has("seating") and not game.rig["stations"].has("ghost"), "rig stations clamped and filtered (%s)" % str(game.rig["stations"]))
	check(not game.plots.has("nowhere") and game.plots["creek"]["stage"] == "" and game.plots["creek"]["stations"].is_empty(), "unknown plots dropped, cart plot stage cleared")
	check(game.plots["jbr"]["stations"]["seating"] == 25 and not game.plots["jbr"]["stations"].has("office"), "plot station levels clamped to the kiosk's caps")
	check(game.plots["creek"]["reputation"] == 1.0 and game.plots["creek"]["last_visit"] == 7, "plot reputation and visit clamped")
	check(game.location == "fahidi", "mall needs a truck: location reset")
	check(game.menu["chicken_tikka"]["price"] == 15.0, "200 AED price clamped to today's range (%s)" % str(game.menu["chicken_tikka"]["price"]))
	check(game.menu["soda"]["price"] == 2.0, "zero price raised to the floor")
	check(game.menu["chicken_tikka"]["level"] == 3, "enhance level clamped")
	check(game.menu["chicken_tikka"]["recipe"]["meat"] == 3 and game.menu["chicken_tikka"]["recipe"]["veg"] == 0, "recipe clamped")
	check(game.popularity == 1.0, "popularity clamped")
	check(game.inventory["bread"] == 0, "negative stock zeroed")
	check(game.history.size() == 1, "junk history rows dropped (%d)" % game.history.size())
	check(not game.marketing.has("fliers"), "expired marketing dropped")
	check(game.goal_index == 1 and game.goals_claimed == ["first_30"], "an older save's goal index follows its claimed goals, unknown goals dropped (%d)" % game.goal_index)
	check(game.stats["days_played"] == 0 and game.stats["best_day_profit"] == 0.0, "stats sanitised")
	check(game.money == 1234.0 and game.day == 7, "money and day kept")
	game.delete_save()

func _test_migration(game) -> void:
	game.new_game()
	var old := {
		"version": 2, "money": 1000.0, "day": 20, "popularity": 0.5, "location": "metro", "vehicle": "truck2",
		"upgrades": {"cart2": true, "grill2": true, "fridge": true, "helper": true, "neon": true, "seating": true, "awning": true},
		"menu": {"fries": {"unlocked": true, "enabled": true, "price": 7.0, "level": 0, "recipe": {}}},
		"total_served": 500, "history": [{"location": "metro", "weather": "sunny", "served": 40, "profit": 100.0}],
	}
	_write_save(game, old)
	check(game.load_game(), "v2 save loads")
	check(game.rig["stage"] == "truck", "truck2 becomes the truck stage")
	check(game.station_level("counter") == 2 and game.station_level("grill") == 3 and game.station_level("coldbox") == 1, "upgrades became station levels")
	check(game.station_level("lights") == 2 and game.station_level("shade") == 1, "neon and awning became lights and shade")
	check(game.station_level("fryer") == 1 and game.menu["fries"]["unlocked"], "unlocked fries bring a fryer")
	check(game.money == 1000.0 + 300.0 + 800.0, "helper and seating refunded (%s)" % game.money)
	check(game.location == "metro", "metro stays reachable with the truck")
	check(game.goal_index == 3 and game.goals_claimed == ["first_30", "counter1", "stars15"],
		"already-achieved goals are skipped up to the first one not done (%d, %s)" % [game.goal_index, str(game.goals_claimed)])
	game.delete_save()
	# a cart player with the neon sign gets signage instead of lights
	_write_save(game, {"version": 2, "money": 100.0, "day": 3, "popularity": 0.3, "location": "fahidi", "vehicle": "cart", "upgrades": {"neon": true, "sweets": true}})
	check(game.load_game() and game.station_level("signage") == 2 and game.station_level("lights") == 0, "neon on a cart becomes signage")
	check(game.money == 100.0 + 2500.0, "sweets counter without a truck is refunded")
	game.delete_save()

func _test_economy_audit(game) -> void:
	# prep plans on the forecast; the opened day runs on its committed weather
	game.new_game()
	game.weather = "sandstorm"
	game.forecast = "sunny"
	game.weather_day = 0
	check(game.sim_context()["weather"] == "sunny", "prep estimates use the forecast, not yesterday's weather")
	game.rng.seed = 5
	game.begin_day()
	check(game.sim_context()["weather"] == game.weather and game.weather_day == game.day, "an opened day estimates on its real weather")
	# goals count what is owned anywhere
	game.new_game()
	game.money = 200000.0
	game.set_location("creek")
	game.buy_stage()
	game.buy_stage()
	game.plot()["reputation"] = 0.6
	game.buy_stage()
	for i in range(3):
		game.buy_station_level("grill")
	game.goal_index = Data.GOALS.size() - 1
	for i in range(Data.GOALS.size()):
		if Data.GOALS[i]["id"] == "kiosk":
			game.goal_index = i
	check(game.goal_ready(), "kiosk goal is ready where the kiosk stands")
	game.set_location("fahidi")
	check(game.goal_ready(), "kiosk goal stays ready after moving the rig elsewhere")
	for i in range(Data.GOALS.size()):
		if Data.GOALS[i]["id"] == "grill3":
			game.goal_index = i
	check(game.goal_ready(), "station goals count levels left in a plot")
	# a save with malformed menu flags still loads everything else
	game.new_game()
	game.money = 200000.0
	game.buy_stage()
	game.buy_stage()
	for i in range(5):
		game.buy_station_level("counter")
	game.money = 4321.0
	game.marketing["social"] = 999
	game.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	raw["menu"]["chicken_tikka"]["unlocked"] = null
	raw["menu"]["soda"]["enabled"] = "yes"
	_write_save(game, raw)
	game.new_game()
	check(game.load_game() and game.rig["stage"] == "truck" and game.station_level("counter") == 5 and game.money == 4321.0,
		"malformed menu flags do not wipe rig and stations on load")
	check(game.menu["chicken_tikka"]["unlocked"] and not game.menu["soda"]["enabled"], "menu flags recover to safe values")
	check(int(game.marketing.get("social", 0)) == int(Data.MARKETING["social"]["days"]), "loaded promotions cannot outlast their campaign")
	game.delete_save()
	# the headless day seats only meals, as the visible day does
	game.new_game()
	game.money = 300000.0
	game.set_location("creek")
	for i in range(4):
		game.buy_stage()
	game.plot()["reputation"] = 0.9
	game.buy_stage()
	for i in range(6):
		game.buy_station_level("seating")
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "food":
			game.menu[id]["enabled"] = false
	game.inventory["drink"] = 2000
	game.inventory["yogurt"] = 2000
	game.begin_day()
	var ctx: Dictionary = game.sim_context()
	check(float(ctx.get("dine_in_share", 0.0)) > 0.0 and int(ctx.get("seats", 0)) > 0, "drinks-only restaurant day has seats to offer")
	var est: Dictionary = Economy.throughput_estimate(ctx)
	check(float(est["dine_in"]) == 0.0 and float(est["served"]) > 0.0, "the estimate seats no drink orders")
	var stats: Dictionary = FastSim.run(ctx, game.rng)
	check(int(stats["served"]) > 0 and int(stats["dine_in"]) == 0, "FastSim seats no drink orders (%d served)" % int(stats["served"]))

## Losses and moods: both sims count would-be buyers nobody could serve (no drink on the menu,
## no sweet at a stage that could sell one), guests sent home at closing, and every sale's
## mood; the books keep them with the day's average wait, prices and campaigns.
func _test_loss_stats(game) -> void:
	var was_persistent: bool = game.persist
	game.persist = false
	# a busy cart with every drink switched off, at a level-0 counter
	var busy := func() -> void:
		game.new_game()
		game.day = 30
		game.popularity = 1.0
		game.location = "creek"
		game.plot()["reputation"] = 1.0
		game.weather = "hot"
		game.forecast = "hot"
		game.weather_day = game.day
		for ing in Data.INGREDIENTS:
			game.inventory[ing] = 500
		for id in Data.MENU_ITEMS:
			if Data.MENU_ITEMS[id]["kind"] == "drink":
				game.menu[id]["enabled"] = false
	var fast_sum := {"no_item": 0, "drink": 0, "closing": 0, "moods": 0, "served": 0}
	for i in range(4):
		busy.call()
		var rng := RandomNumberGenerator.new()
		rng.seed = 4401 + i
		var s := FastSim.run(game.sim_context(), rng)
		for k in ["no_item", "closing", "mood_great", "mood_ok", "mood_bad", "no_item_kinds"]:
			check(s.has(k), "FastSim reports %s" % k)
		fast_sum["no_item"] += int(s["no_item"])
		fast_sum["drink"] += int(s["no_item_kinds"].get("drink", 0))
		fast_sum["closing"] += int(s["closing"])
		fast_sum["moods"] += int(s["mood_great"]) + int(s["mood_ok"]) + int(s["mood_bad"])
		fast_sum["served"] += int(s["served"])
	check(int(fast_sum["drink"]) > 0 and int(fast_sum["no_item"]) >= int(fast_sum["drink"]), "FastSim counts thirsty passers with no drink on the menu (%s)" % str(fast_sum))
	check(int(fast_sum["moods"]) == int(fast_sum["served"]), "every FastSim sale has one mood (%s)" % str(fast_sum))
	# Global Village peaks at 23:00 and closes at midnight: a level-0 truck still has a line
	var closing := 0
	for i in range(4):
		game.new_game()
		game.popularity = 1.0
		game.rig["stage"] = "truck"
		game.location = "gv"
		game.plot()["reputation"] = 1.0
		game.weather = "breeze"
		game.weather_day = game.day
		for ing in Data.INGREDIENTS:
			game.inventory[ing] = 500
		var rng := RandomNumberGenerator.new()
		rng.seed = 5501 + i
		closing += int(FastSim.run(game.sim_context(), rng)["closing"])
	check(closing > 0, "FastSim counts buyers still in line at closing (%d)" % closing)
	# the played day: the same keys, the same rules
	busy.call()
	var world := World.new()
	add_child(world)
	world.set_location(game.location)
	game.day_seed = 4401
	var sim := DaySim.new()
	add_child(sim)
	var played := DayRunner.play(sim, world, game.sim_context())
	for k in ["no_item", "closing", "mood_great", "mood_ok", "mood_bad", "no_item_kinds"]:
		check(played.has(k), "the played day reports %s" % k)
	check(int(played["no_item_kinds"].get("drink", 0)) > 0, "the played day counts thirsty passers with no drink on the menu (%d)" % int(played["no_item"]))
	check(int(played["mood_great"]) + int(played["mood_ok"]) + int(played["mood_bad"]) == int(played["served"]), "every played sale has one mood")
	sim.free()
	# a guest still in line at closing is counted once
	busy.call()
	game.day_seed = 4402
	sim = DaySim.new()
	add_child(sim)
	sim.start(game.sim_context(), world)
	var guest := world.spawn_guest(-1, world.queue_slot(0))
	sim._on_gave_up(guest, "closing")
	check(int(sim.stats["closing"]) == 1 and int(sim.stats["left_wait"]) == 0, "closing time sends the line home as 'closing', not 'left waiting'")
	sim.free()
	world.free()
	# sweets wished for at a truck that has no sweets counter yet, none at a cart
	game.new_game()
	check(not game.kind_possible("sweet") and game.kind_possible("side") and game.kind_on_sale("side"), "a cart cannot sell sweets; salad is on")
	game.rig["stage"] = "truck"
	check(game.kind_possible("sweet") and not game.kind_on_sale("sweet"), "a truck could sell sweets once it has the counter")
	for ing in Data.INGREDIENTS:
		game.inventory[ing] = 100
	var ledger := StockLedger.new()
	var draw := RandomNumberGenerator.new()
	draw.seed = 3
	var wished := 0
	for i in range(40):
		var sale := ledger.settle(i, "chicken_tikka", 1, 1.0, "food", false, "sunny", draw)
		wished += int(sale["wished"].get("sweet", 0))
		check(not sale["wished"].has("side") and not sale["wished"].has("drink"), "kinds on the menu are never 'wished for'")
	check(wished > 5 and wished < 30, "about a third of food portions wish for a sweet the truck does not sell (%d of 40)" % wished)
	# the books: average wait, moods, losses, prices and campaigns of the day
	game.new_game()
	game.menu["soda"]["enabled"] = false
	game.marketing = {Data.MARKETING.keys()[0]: 1}
	var r: Dictionary = game.end_day({"served": 4, "portions": 5, "revenue": 50.0, "cogs": 20.0, "satisfaction_sum": 2.4, "wait_sum": 6.0,
		"no_item": 3, "no_item_kinds": {"drink": 2, "sweet": 1}, "closing": 2, "mood_great": 1, "mood_ok": 2, "mood_bad": 1, "sold": {}})
	check(is_equal_approx(float(r["wait"]), 1.5) and int(r["no_item"]) == 3 and int(r["closing"]) == 2, "the report keeps the average wait and the losses")
	check(int(r["mood_great"]) == 1 and int(r["mood_ok"]) == 2 and int(r["mood_bad"]) == 1, "the report keeps the moods")
	check(r["prices"].has("chicken_tikka") and not r["prices"].has("soda") and float(r["prices"]["chicken_tikka"]) == float(game.menu["chicken_tikka"]["price"]), "the report keeps the prices of the dishes on sale")
	check(r["promos"] == [Data.MARKETING.keys()[0]] and game.marketing.is_empty(), "the report names the campaign that ran, which then ends")
	# old or malformed history rows are cleaned on load
	game.history = [{"location": "creek", "weather": "sunny", "served": 3},
		{"location": "creek", "weather": "sunny", "served": 3, "no_item": -4, "wait": "x", "prices": {"chicken_tikka": 12, "ghost": 3, "soda": NAN},
			"promos": ["ghost", 7, Data.MARKETING.keys()[0], Data.MARKETING.keys()[0]], "no_item_kinds": {"drink": 2, "rocket": 9}, "mood_bad": 1.0}]
	game._validate()
	var a: Dictionary = game.history[0]
	var b: Dictionary = game.history[1]
	check(int(a["no_item"]) == 0 and float(a["wait"]) == 0.0 and a["prices"].is_empty() and a["promos"].is_empty() and int(a["mood_great"]) == 0,
		"a version-4 history row gains empty loss, mood, price and campaign fields")
	check(int(b["no_item"]) == 0 and float(b["wait"]) == 0.0 and b["prices"].keys() == ["chicken_tikka"] and b["promos"] == [Data.MARKETING.keys()[0]]
		and b["no_item_kinds"].keys() == ["drink"] and int(b["mood_bad"]) == 1, "malformed history fields are cleaned (%s)" % str(b))
	game.persist = was_persistent
	game.new_game()

## The opening buzz (Data.OPENING): a new stand draws extra passers-by on day 1, fading in a
## straight line to none, through the same traffic_mult every sim and the estimate read.
func _test_opening_buzz(game) -> void:
	var days := int(Data.OPENING["days"])
	var start := float(Data.OPENING["traffic"])
	check(start > 1.0 and days >= 7, "the opening buzz starts above normal traffic and lasts at least a week")
	check(is_equal_approx(Economy.opening_boost(1), start) and is_equal_approx(Economy.opening_boost(days + 1), 1.0) and Economy.opening_boost(500) == 1.0,
		"the buzz is x%.1f on day 1 and over after day %d" % [start, days])
	var falling := true
	for d in range(1, days + 1):
		falling = falling and Economy.opening_boost(d) > Economy.opening_boost(d + 1)
	check(falling and is_equal_approx(Economy.opening_boost(2) - Economy.opening_boost(3), Economy.opening_boost(days - 1) - Economy.opening_boost(days)), "the buzz fades in a straight line")
	game.new_game()
	check(is_equal_approx(game.opening_boost(), start) and is_equal_approx(float(game.sim_context()["traffic_mult"]), start), "day 1's context carries the buzz")
	check(is_equal_approx(float(game.what_if({"stations": {"grill": 2}})["traffic_mult"]), start), "previews see today's buzz")
	var loc: Dictionary = Data.LOCATIONS["fahidi"]
	check(is_equal_approx(Economy.arrival_rate(loc, "sunny", 13.0, {"traffic_mult": start}), start * Economy.arrival_rate(loc, "sunny", 13.0, {})), "the buzz multiplies passers-by")
	var busy := Economy.throughput_estimate(game.sim_context())
	game.day = days + 1
	check(game.opening_boost() == 1.0 and float(game.sim_context()["traffic_mult"]) == 1.0, "after the buzz the street is back to normal")
	var quiet := Economy.throughput_estimate(game.sim_context())
	check(float(busy["want"]) > float(quiet["want"]) * 2.0 and float(busy["served"]) > float(quiet["served"]), "the estimate sees the opening crowd (%.0f vs %.0f buyers)" % [float(busy["served"]), float(quiet["served"])])
	var passers := {}
	for d in [1, days + 1]:
		game.new_game()
		game.day = d
		for ing in Data.INGREDIENTS:
			game.inventory[ing] = 300
		var rng := RandomNumberGenerator.new()
		rng.seed = 77
		passers[d] = int(FastSim.run(game.sim_context(), rng)["passers"])
	check(float(passers[1]) > float(passers[days + 1]) * 2.0, "FastSim's day 1 is busier than a steady day (%s)" % str(passers))
	game.new_game()

## Promotions (Data.MARKETING): five campaigns priced by the stand's stage, each scaled as
## Economy.campaign_boost, locked by Game.marketing_lock_reason and previewed without side
## effects by Game.promo_preview; the blogger's review moves stars; version-4 saves get the
## days left of removed campaigns refunded once.
func _test_promotions(game) -> void:
	var was_persistent: bool = game.persist
	game.persist = false
	var ids: Array = Data.MARKETING.keys()
	ids.sort()
	check(ids == ["blogger", "chat", "maps", "samples", "social"], "the five campaigns (%s)" % str(ids))
	check(Data.MARKETING.has(Data.STARTER_PROMO) and int(Data.MARKETING[Data.STARTER_PROMO]["days"]) == 1, "the guide's starter campaign is a one-day trial")
	var previous := TranslationServer.get_locale()
	for locale in ["en", "ar"]:
		TranslationServer.set_locale(locale)
		for id in Data.MARKETING:
			var def: Dictionary = Data.MARKETING[id]
			var text := tr(String(def["desc"]))
			check(tr(String(def["name"])) != String(def["name"]) and text.contains("+%d%%" % roundi(float(def["boost"]) * 100.0))
				and (int(def["days"]) == 1 or text.contains(str(int(def["days"])))), "%s card (%s) states its boost and days" % [id, locale])
		check(tr("ui.a_needs_stars") != "ui.a_needs_stars" and tr("ui.promo_refund").contains("%s") and tr("mk.review_good") != "mk.review_good",
			"lock, refund and review lines exist (%s)" % locale)
	TranslationServer.set_locale(previous)
	for id in Data.MARKETING:
		check(ResourceLoader.exists("res://assets/models/%s.glb" % Data.MARKETING[id]["icon"]), "campaign %s shows an existing icon" % id)
	# prices grow with the stand
	var samples: Dictionary = Data.MARKETING["samples"]
	check(Economy.campaign_cost(samples, 0) == float(samples["cost"]) and is_equal_approx(Economy.campaign_cost(samples, 4), float(samples["cost"]) * float(Data.PROMO_SCALE[4])),
		"a restaurant's tasting tray costs PROMO_SCALE times the cart's")
	# offers to regulars grow with the guests served, the blogger's word with their mood
	var chat: Dictionary = Data.MARKETING["chat"]
	var full := int(chat["regulars_full"])
	check(Economy.campaign_boost(chat, 0, 0.8) == 0.0 and is_equal_approx(Economy.campaign_boost(chat, full / 2, 0.8), float(chat["boost"]) * 0.5)
		and is_equal_approx(Economy.campaign_boost(chat, full * 3, 0.8), float(chat["boost"])), "offers to regulars grow with the guests served, capped")
	var blog: Dictionary = Data.MARKETING["blogger"]
	var mid_mood := Economy.campaign_boost(blog, 0, 0.55)
	check(Economy.campaign_boost(blog, 0, float(blog["sat_floor"])) == 0.0 and is_equal_approx(Economy.campaign_boost(blog, 0, 1.0), float(blog["boost"]))
		and mid_mood > 0.0 and mid_mood < float(blog["boost"]), "the blogger's word follows the guests' mood")
	check(is_equal_approx(Economy.campaign_boost(samples, 0, 0.0), float(samples["boost"])), "a plain campaign gives its boost")
	check(Economy.campaign_review(blog, 0.9) > 0.0 and Economy.campaign_review(blog, 0.3) < 0.0 and Economy.campaign_review(blog, 0.6) == 0.0
		and Economy.campaign_review(samples, 0.9) == 0.0, "only the blogger's review moves stars")
	# locks and prices
	game.new_game()
	game.money = 10000.0
	game.popularity = float(blog["min_popularity"]) - 0.05
	var why: String = game.marketing_lock_reason("blogger")
	var blog_level := Economy.fame_level_for(float(blog["min_popularity"]))
	check(why != "" and why.contains(tr(String(Data.FAME_LEVELS[blog_level]["name"]))) and not why.contains("2.0") and not why.contains("%"),
		"the blogger names the fame level she needs (%s)" % why)
	check(not game.start_marketing("blogger") and game.money == 10000.0 and game.marketing.is_empty(), "a locked campaign cannot start")
	check(game.marketing_lock_reason("ghost") != "" and not game.start_marketing("ghost"), "an unknown campaign is refused")
	game.popularity = float(blog["min_popularity"])
	check(game.marketing_lock_reason("blogger") == "", "at that level the blogger can come")
	check(game.start_marketing("samples") and is_equal_approx(game.money, 10000.0 - float(samples["cost"])) and int(game.marketing["samples"]) == 1,
		"starting a campaign at the cart charges the cart's price")
	check(game.marketing_lock_reason("samples") != "" and not game.start_marketing("samples"), "a running campaign cannot start twice")
	game.marketing = {"chat": 3}
	game.total_served = full / 2
	check(is_equal_approx(game.marketing_boost(), float(chat["boost"]) * 0.5) and is_equal_approx(float(game.sim_context()["boost"]), game.marketing_boost() + game.attract_bonus()),
		"the running campaigns' scaled boost reaches the day")
	game.marketing = {"ghost": 2, "maps": 99}
	game._validate()
	check(game.marketing.keys() == ["maps"] and int(game.marketing["maps"]) == int(Data.MARKETING["maps"]["days"]), "unknown campaigns are dropped, lengths clamped")
	game.new_game()
	game.money = 10000.0
	game.rig["stage"] = Data.stage_def(2)["id"]
	check(game.start_marketing("social") and is_equal_approx(game.money, 10000.0 - Economy.campaign_cost(Data.MARKETING["social"], 2)), "a truck's campaign costs the truck's price")
	# the preview: no side effects, no RNG; pays where the stand has room, flags a full one
	_setup_fixed(game, 3, "creek", 0.6)
	game.total_served = 2000
	var money_before: float = game.money
	var rng_before: int = game.rng.state
	var pv: Dictionary = game.promo_preview("maps")
	check(game.money == money_before and game.marketing.is_empty() and game.rng.state == rng_before, "a preview changes nothing")
	check(pv.has_all(["cost", "days", "extra_buyers_per_day", "extra_profit_total", "net", "capped"])
		and is_equal_approx(float(pv["net"]), float(pv["extra_profit_total"]) - float(pv["cost"])) and is_equal_approx(float(pv["cost"]), game.campaign_cost("maps")),
		"the preview's fields")
	var best := {}
	for setup in [[0, "fahidi"], [1, "fahidi"], [2, "creek"], [3, "creek"], [4, "creek"], [5, "creek"]]:
		_setup_fixed(game, setup[0], setup[1], 0.6)
		game.total_served = 600 * (int(setup[0]) + 1)
		game.history = [{"served": 30, "satisfaction": 0.75, "promos": []}]
		var top := 0.0
		for id in Data.MARKETING:
			var p: Dictionary = game.promo_preview(id)
			top = maxf(top, float(p["extra_profit_total"]) / float(p["cost"]))
		best[Data.stage_def(setup[0])["id"]] = snappedf(top, 0.01)
	var all_pay := true
	for k in best:
		all_pay = all_pay and float(best[k]) >= 1.3
	check(all_pay, "with room to serve, the best campaign returns 1.3x its price or more at every stage (%s)" % str(best))
	_setup_fixed(game, 3, "creek", 0.6)
	var room: Dictionary = game.promo_preview("samples")
	_setup_fixed(game, 3, "downtown", 0.6)
	var full_day: Dictionary = game.promo_preview("samples")
	check(not room["capped"] and full_day["capped"] and float(full_day["extra_profit_total"]) < float(room["extra_profit_total"]),
		"a full stand is flagged and earns less from the same campaign")
	_setup_fixed(game, 3, "mall", 0.6)
	var mall: Dictionary = game.promo_preview("samples")
	check(float(mall["extra_profit_total"]) > 2.0 * float(mall["cost"]), "at the Mall a campaign wins the crowd back from rivals (x%.1f)" % (float(mall["extra_profit_total"]) / float(mall["cost"])))
	game.new_game()
	check(game.promo_preview("samples")["capped"], "during the opening buzz the cart is already full")
	# the blogger's review when the visit ends: the campaign days' guests decide
	game.new_game()
	game.popularity = 0.6
	game.marketing = {"blogger": 1}
	game.history = [{"location": "fahidi", "weather": "sunny", "served": 10, "satisfaction": 0.9, "promos": ["blogger"]},
		{"location": "fahidi", "weather": "sunny", "served": 10, "satisfaction": 0.9, "promos": ["blogger"]}]
	var happy := {"_day": game.day, "served": 10, "satisfaction_sum": 4.0}
	var expect := clampf(0.6 + Economy.popularity_delta(happy, 0.6) + float(blog["review"]), 0.05, 1.0)
	var r: Dictionary = game.end_day(happy)
	check(is_equal_approx(game.popularity, expect) and is_equal_approx(float(r["review"]), float(blog["review"])) and game.marketing.is_empty(),
		"a visit whose days averaged happy guests lifts fame")
	# inside a level (Local favourite, 0.45-0.60): an unhappy visit takes a little, never the level
	game.popularity = 0.55
	game.fame_best = 2
	game.marketing = {"blogger": 1}
	game.history = []
	var sad := {"_day": game.day, "served": 10, "satisfaction_sum": 3.0}
	expect = maxf(0.55 + Economy.popularity_delta(sad, 0.55) - float(blog["review"]), Economy.fame_floor(2))
	r = game.end_day(sad)
	check(is_equal_approx(game.popularity, expect) and float(r["review"]) < 0.0 and game.popularity < 0.55, "an unhappy visit lowers it (%.3f)" % game.popularity)
	game.popularity = 0.46
	game.marketing = {"blogger": 1}
	r = game.end_day({"_day": game.day, "served": 10, "satisfaction_sum": 3.0})
	check(is_equal_approx(game.popularity, Economy.fame_floor(2)) and game.fame_level() == 2, "the review never takes a level away (%.3f)" % game.popularity)
	# a version-4 save: removed campaigns refunded once for their days left, the video carries on
	game.persist = true
	game.new_game()
	game.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	raw["version"] = 4
	raw["money"] = 1000.0
	raw["marketing"] = {"fliers": 1, "radio": 3, "posters": 0, "social": 6, "ghost": 2}
	_write_save(game, raw)
	var notes := []
	var grab := func(text: String, _kind: String) -> void: notes.append(text)
	game.notify.connect(grab)
	check(game.load_game(), "a version-4 save with old campaigns loads")
	game.notify.disconnect(grab)
	var refund: float = float(Data.LEGACY_MARKETING["fliers"]["cost"]) + float(Data.LEGACY_MARKETING["radio"]["cost"]) * 3.0 / float(Data.LEGACY_MARKETING["radio"]["days"])
	check(is_equal_approx(game.money, 1000.0 + refund), "removed campaigns are refunded for their days left (%.0f)" % game.money)
	check(game.marketing.keys() == ["social"] and int(game.marketing["social"]) == int(Data.MARKETING["social"]["days"]), "the short video carries on, clamped to its new length")
	check(notes.size() == 1, "the player is told once (%s)" % str(notes))
	check(game.load_game() and is_equal_approx(game.money, 1000.0 + refund), "the refund is paid only once")
	raw = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	check(int(raw["version"]) == game.SAVE_VERSION, "the refunded save is rewritten in the current version")
	raw["marketing"] = {"fliers": 1}
	_write_save(game, raw)
	check(game.load_game() and is_equal_approx(game.money, 1000.0 + refund) and game.marketing.is_empty(), "a version-5 save never refunds an unknown campaign")
	game.delete_save()
	game.persist = was_persistent
	game.new_game()

## Wages (Data.WAGES): nothing at the cart and stall, one helper on the truck, then a wage per
## role the fixed stand has, growing with the stage; previews, the estimate, the closing books
## and the Stock-today reserve all use the same bill.
func _test_wages(game) -> void:
	var was_persistent: bool = game.persist
	game.persist = false
	var w: Dictionary = Data.WAGES
	game.new_game()
	check(game.daily_wages() == 0.0 and float(game.sim_context()["wages"]) == 0.0, "you run the cart alone: no wages")
	game.rig["stage"] = Data.stage_def(1)["id"]
	check(game.daily_wages() == 0.0, "the stall is still a one-person stand")
	game.rig["stage"] = Data.stage_def(2)["id"]
	check(is_equal_approx(game.daily_wages(), float(w["helper"])) and is_equal_approx(float(game.sim_context()["wages"]), float(w["helper"])),
		"the truck pays one helper (%.0f AED)" % float(w["helper"]))
	game.rig["stage"] = Data.stage_def(0)["id"]
	check(is_equal_approx(float(game.what_if({"stage": 2})["wages"]), float(w["helper"])) and game.daily_wages() == 0.0,
		"a truck preview carries the helper's wage without hiring anyone")
	var bills := []
	for tier in [3, 4, 5]:
		_setup_fixed(game, tier, "creek", 0.6)
		var bill: float = game.daily_wages()
		bills.append(bill)
		check(is_equal_approx(bill, Economy.daily_wages(tier, game.active_stations(), game.terrace_seats())) and is_equal_approx(float(game.sim_context()["wages"]), bill),
			"the %s's wage bill reaches the context (%.0f AED)" % [Data.stage_def(tier)["id"], bill])
		if tier < 5:
			var next: Dictionary = game.what_if({"stage": tier + 1})
			check(float(next["wages"]) > bill and is_equal_approx(game.daily_wages(), bill), "a preview of the next stage pays its bigger crew, today's bill is unchanged")
	check(bills[0] > float(w["helper"]) and bills[1] > bills[0] and bills[2] > bills[1], "wages grow from the truck to the flagship (%s)" % str(bills))
	# each role costs its own wage: a running kitchen station adds a cook, the terrace a server
	var crew_table: Array = Data.SERVICE["kitchen_crew"]
	var grade := float(w["grade"][3])
	var base := Economy.daily_wages(3, {"counter": 1, "grill": 1}, 0)
	var with_doner := Economy.daily_wages(3, {"counter": 1, "grill": 1, "doner": 1}, 0)
	check(absf(with_doner - base - float(w["roles"]["cook"]) * float(crew_table[3]) * grade) <= 5.0,
		"a second kitchen station hires its cook (%.0f AED more)" % (with_doner - base))
	check(Economy.daily_wages(3, {"counter": 1, "grill": 1, "seating": 3}, 6) == base, "a kiosk's counter crew clears its few tables: no extra wage")
	check(Economy.daily_wages(4, {"counter": 1, "grill": 1, "seating": 3}, 6) > Economy.daily_wages(4, {"counter": 1, "grill": 1}, 0), "a restaurant terrace pays its servers")
	check(Economy.daily_wages(3, {"counter": 1, "grill": 1, "shade": 4}, 0) == base, "a station with no crew costs no wage")
	# the closing books pay rent and wages; Stock today keeps both in the till
	_setup_fixed(game, 4, "creek", 0.6)
	var bill4: float = game.daily_wages()
	var rent := float(game.loc()["rent"])
	var before: float = game.money
	var r: Dictionary = game.end_day({"_day": game.day})
	check(is_equal_approx(float(r["wages"]), bill4) and is_equal_approx(before - game.money, rent + bill4), "closing pays the rent and the wage bill (%.0f + %.0f)" % [rent, bill4])
	for ing in Data.INGREDIENTS:
		game.inventory[ing] = 0
	var cost := float(game.daily_stock_plan()["cost"])
	game.money = rent + bill4 + cost - 1.0
	check(cost > 0.0 and not game.stock_for_today(), "Stock today will not spend the rent and wages")
	game.money = rent + bill4 + cost + 1.0
	check(game.stock_for_today() and game.money < rent + bill4 + 2.0, "Stock today buys when rent and wages stay covered")
	game.persist = was_persistent
	game.new_game()

## The built-in advisor: specific, priced, pointed at a real menu, and never touching the game.
func _test_advisor(game) -> void:
	game.new_game()
	var panels := ["", "supplies", "menu", "place", "build", "promote", "goals"]
	var first := Advisor.for_prep()
	check(not first.is_empty(), "the advisor has something to say on day one")
	for day in range(6):
		Autoplayer.play_day(false, null, null)
	var money: float = game.money
	var rng_state: int = game.rng.state
	var levels: int = game.levels_owned()
	var menu_before := JSON.stringify(game.menu)
	var prep := Advisor.for_prep()
	check(is_equal_approx(game.money, money) and game.rng.state == rng_state and game.levels_owned() == levels and JSON.stringify(game.menu) == menu_before,
		"asking the advisor spends nothing, buys nothing and rolls no dice")
	check(prep.size() >= 1 and prep.size() <= Advisor.SHEET_TOP, "the planning sheet lists one to six things (%d)" % prep.size())
	var ids := {}
	# a filled-in "35%" is fine; a placeholder left over is not
	var placeholder := RegEx.create_from_string("%[+]?[.0-9]*[dsf]")
	for it in prep:
		check(not String(it["text"]).begins_with("adv.") and placeholder.search(String(it["text"])) == null, "advice '%s' is a finished sentence (%s)" % [it["id"], it["text"]])
		check(panels.has(String(it["panel"])), "advice '%s' points at a real menu (%s)" % [it["id"], it["panel"]])
		check(not ids.has(it["id"]), "advice '%s' appears once" % it["id"])
		ids[it["id"]] = true
		if String(it["panel"]) == "build" and String(it["detail"]) != "" and String(it["detail"]) != "stage":
			check(Data.STATIONS.has(String(it["detail"])), "advice '%s' names a real station" % it["id"])
		if String(it["dish"]) != "":
			check(Data.MENU_ITEMS.has(String(it["dish"])), "advice '%s' names a real dish" % it["id"])
	# A day with every kind of loss: the report names the costliest and keeps room for a purchase.
	game.money = 5000.0
	var bad: Dictionary = (game.history.back() as Dictionary).duplicate(true)
	bad.merge({"served": 12, "revenue": 120.0, "cogs": 50.0, "sold_out": 6, "left_wait": 5, "queue_full": 2, "crowd": 8,
		"too_pricey": 4, "no_item": 5, "spoil_cost": 40.0, "bottleneck": "grill", "satisfaction": 0.45}, true)
	game.set_price("chicken_tikka", float(game.price_range("chicken_tikka")[1]))
	var report := Advisor.for_report(bad)
	check(report.size() == Advisor.REPORT_TOP, "a bad day gets exactly three next steps (%d)" % report.size())
	var kinds := report.map(func(it: Dictionary) -> String: return String(it["id"]))
	check(kinds.has("sold_out") or kinds.has("line"), "the costliest losses lead the list (%s)" % [kinds])
	check(report.any(func(it: Dictionary) -> bool: return int(it["prio"]) == 2), "one of the three is something to buy or save for (%s)" % [kinds])
	check(Advisor._priciest_dish() == "chicken_tikka", "price complaints point at the dish furthest above its usual price")
	var line := Advisor._day_insights(bad).filter(func(it: Dictionary) -> bool: return it["id"] == "line")
	check(line.size() == 1 and line[0]["panel"] == "build" and line[0]["detail"] == "grill" and String(line[0]["text"]).contains("7"),
		"a slow line names the station that held it back and how many left")
	# A clean day has no loss lines.
	var clean: Dictionary = bad.duplicate(true)
	clean.merge({"sold_out": 0, "left_wait": 0, "queue_full": 0, "crowd": 0, "too_pricey": 0, "no_item": 0, "spoil_cost": 0.0,
		"lost_rival": 0, "bottleneck": "", "satisfaction": 0.6}, true)
	var losses := Advisor._day_insights(clean).filter(func(it: Dictionary) -> bool: return it["id"] in ["sold_out", "line", "crowd", "pricey", "no_item", "spoil", "rival"])
	check(losses.is_empty(), "a clean day lists no lost guests")
	# Weather and the opening crowd.
	game.forecast = "hot"
	check(Advisor._forecast_insights().size() == 1 and Advisor._forecast_insights()[0]["id"] == "hot", "a heatwave forecast gets a drinks tip")
	game.forecast = "sunny"
	check(Advisor._forecast_insights().is_empty(), "plain weather gets no weather tip")
	game.day = int(Data.OPENING["days"]) - 1
	check(Advisor._opening_insights().size() == 1, "the advisor warns before the opening crowd fades")
	game.day = int(Data.OPENING["days"]) + 10
	check(Advisor._opening_insights().is_empty(), "no opening warning once it is over")
	var t := Advisor.trends()
	check(int(t["days"]) == mini(14, game.history.size()) and (t["served"] as Array).size() == int(t["days"]) and Data.MENU_ITEMS.has(String(t["best_dish"])),
		"trends cover the recorded days and name the best seller")
	check((game.stage_def()["stations"] as Array).has(Advisor.best_station("counter")), "the guide's suggested upgrade exists at this stand")
	_test_advisor_review(game)
	game.new_game()

## Cases from the independent review: each of these was wrong once.
func _test_advisor_review(game) -> void:
	game.new_game()
	game.money = 100000.0
	for day in range(3):
		Autoplayer.play_day(false, null, null)
	game.money = 100000.0
	# The same answer is reused until the stand, menu or money changes.
	var first: Array = Advisor.for_prep()
	check(is_same(first, Advisor.for_prep()), "the advisor answers once per planning state")
	var levels := JSON.stringify([game.rig, game.plots, game.menu, game.marketing])
	var ranked: Dictionary = Autoplayer.rank([], null, true)
	check(JSON.stringify([game.rig, game.plots, game.menu, game.marketing]) == levels and not (ranked["cands"] as Array).is_empty(),
		"ranking at the player's own prices changes nothing")
	game.set_price("chicken_tikka", float(game.menu["chicken_tikka"]["price"]) + 1.0)
	check(not is_same(first, Advisor.for_prep()), "a price edit gets fresh advice")
	# Extras guests asked for: named from the day's own count, pointed where they can be fixed.
	var row: Dictionary = (game.history.back() as Dictionary).duplicate(true)
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "drink":
			game.set_enabled(id, false)
	row["no_item_kinds"] = {"drink": 7, "side": 1}
	var drinks := Advisor._missing_extras(row)
	check(not drinks.is_empty() and drinks["panel"] == "menu" and Data.MENU_ITEMS[drinks["dish"]]["kind"] == "drink" and String(drinks["text"]).contains("7"),
		"missing drinks point at a drink to switch on (%s)" % [drinks])
	check(float(drinks["gain"]) < 7 * 6.0, "a missed extra is valued as an add-on, not a whole order (%.0f)" % float(drinks.get("gain", 0.0)))
	for id in Data.MENU_ITEMS:
		if Data.MENU_ITEMS[id]["kind"] == "drink" and game.menu[id]["unlocked"]:
			game.set_enabled(id, true)
	check(Advisor._missing_extras(row).is_empty(), "no line once a drink is back on sale")
	game.buy_stage()
	game.buy_stage()
	row["no_item_kinds"] = {"sweet": 9}
	var sweets := Advisor._missing_extras(row)
	check(game.station_available("sweets") and game.station_level("sweets") == 0 and not sweets.is_empty() and sweets["panel"] == "build" and sweets["detail"] == "sweets",
		"missing sweets on a truck point at the sweets counter in Build (%s)" % [sweets])
	row["no_item_kinds"] = {"sweet": 2}
	check(Advisor._missing_extras(row).is_empty(), "a couple of wishes are not worth a line")
	# A price rise is judged against today's prices, on that one dish.
	for id in game.menu:
		game.menu[id]["price"] = float(Data.MENU_ITEMS[id]["base_price"]) * 1.35
	game.clamp_prices()
	var before := JSON.stringify(game.menu)
	var now := float(Economy.throughput_estimate(game.sim_context())["profit"])
	var raise := Advisor._raise_candidate()
	if not raise.is_empty():
		var up := float(Economy.throughput_estimate(game.what_if({"prices": {raise["dish"]: raise["price"]}}))["profit"])
		check(up > now and is_equal_approx(float(raise["gain"]), up - now) and is_equal_approx(float(raise["price"]), float(game.menu[raise["dish"]]["price"]) + 1.0),
			"a suggested rise is +1 on that dish and earns more than today's prices")
	var one: Dictionary = game.what_if({"prices": {"chicken_tikka": 9.0}})
	var offered: Array = (one["offer"] as Array).filter(func(o: Dictionary) -> bool: return o["id"] == "chicken_tikka")
	check(JSON.stringify(game.menu) == before and offered.size() == 1 and is_equal_approx(float(offered[0]["price"]), 9.0),
		"what_if can price one dish and puts the menu back")
	# One multiplier on the whole menu: complaints are about the food that sells most.
	check(Data.MENU_ITEMS[Advisor._priciest_dish()]["kind"] == "food", "equal price ratios name a food dish, not a drink (%s)" % Advisor._priciest_dish())
	# A plot that pays best elsewhere says where, and sends the player to Place.
	var other: String = "creek" if game.location != "creek" else "metro"
	var elsewhere := Advisor._purchase({"kind": "stage", "id": "kiosk", "where": other, "cost": 9000.0, "net": 9000.0, "gain": 120.0, "payback": 75.0, "score": 0.01}, true, 300.0)
	check(elsewhere["id"] == "stage_at" and elsewhere["panel"] == "place" and String(elsewhere["text"]).contains(tr(Data.LOCATIONS[other]["name"])),
		"a stage that pays best at another place names the place (%s)" % [elsewhere])
	var here := Advisor._purchase({"kind": "stage", "id": "kiosk", "where": game.location, "cost": 9000.0, "net": 9000.0, "gain": 120.0, "payback": 75.0, "score": 0.01}, true, 300.0)
	check(here["id"] == "buy" and here["panel"] == "build" and here["detail"] == "stage", "a stage that pays best here opens its Build card")
	# A dish counts as unsold only on days it was on sale.
	game.history.clear()
	for i in range(5):
		game.history.append({"day": i + 1, "location": game.location, "served": 10, "profit": 50.0, "sold": {"chicken_tikka": 10}, "prices": {"chicken_tikka": 10.0}})
	check(not Advisor._trend_insights(game.history.back()).any(func(it: Dictionary) -> bool: return it["id"] == "dead_dish"),
		"a dish that was not on sale those days is not called unsold")
	for r in game.history:
		r["prices"]["sandwich"] = 7.0
	game.set_enabled("sandwich", true)
	var dead := Advisor._trend_insights(game.history.back()).filter(func(it: Dictionary) -> bool: return it["id"] == "dead_dish")
	check(dead.size() == 1 and dead[0]["dish"] == "sandwich", "five days on sale without an order is called out")
	# The quick campaign preview agrees with the full one when every day is alike.
	game.day = int(Data.OPENING["days"]) + 5
	game.forecast = "sunny"
	var full: Dictionary = game.promo_preview("social")
	var quick: Dictionary = game.promo_preview("social", true)
	check(is_equal_approx(float(full["extra_profit_total"]), float(quick["extra_profit_total"])) and is_equal_approx(float(full["cost"]), float(quick["cost"])),
		"the advisor's quick campaign preview matches the full one on level days")
	# The guide may point its upgrade lesson at any station, and that survives a reload.
	check(GuideJourney.clean({"station": "shade"})["station"] == "shade" and GuideJourney.clean({"station": "seating"})["station"] == "seating"
		and GuideJourney.clean({"station": "nonsense"})["station"] == "counter", "the guide remembers any real station across a reload")

## The advice is not "a bigger stand" every morning: two purchases of different kinds, a
## full stand is an observation, and the cold box gets one line, not two.
func _test_advisor_variety(game) -> void:
	game.new_game()
	for day in range(8):
		Autoplayer.play_day(false, null, null)
	game.money = 6000.0
	var buys := Advisor._buy_insights({})
	check(buys.size() >= 1 and buys.size() <= 2, "one or two purchases are advised (%d)" % buys.size())
	if buys.size() == 2:
		check(buys[0]["category"] != buys[1]["category"], "the two purchases are different kinds of upgrade (%s, %s)" % [buys[0]["category"], buys[1]["category"]])
		check(int(buys[1]["prio"]) == 2 and float(buys[1]["gain"]) <= float(buys[0]["gain"]) + 0.001, "the second purchase sorts after the best one")
	for c in Autoplayer.rank([], null, true)["cands"]:
		check(Advisor.category(c) in ["capacity", "quality", "freshness", "reach"], "candidate %s:%s has a category" % [c["kind"], c["id"]])
	# The second suggestion turns through the other kinds day by day.
	var seen := {}
	var day0: int = game.day
	for d in range(6):
		game.day = day0 + d
		var pair := Advisor._buy_insights({})
		if pair.size() == 2:
			seen[pair[1]["category"]] = true
	game.day = day0
	var kinds := {}
	for c in Autoplayer.rank([], null, true)["cands"]:
		if bool(c["ok"]) and float(c["gain"]) > 0.5 and float(c["net"]) > 0.0:
			kinds[Advisor.category(c)] = true
	check(seen.size() >= mini(2, kinds.size() - 1), "the second suggestion rotates through the kinds on offer (%s of %s)" % [seen.keys(), kinds.keys()])
	# A full stand: not a line on an ordinary day, an observation on a swamped one, never first.
	var row: Dictionary = (game.history.back() as Dictionary).duplicate(true)
	row.merge({"served": 16, "crowd": 9, "left_wait": 0, "queue_full": 0, "sold_out": 0, "too_pricey": 0, "no_item_kinds": {}, "spoil_cost": 0.0, "bottleneck": ""}, true)
	check(not Advisor._day_insights(row).any(func(it: Dictionary) -> bool: return it["id"] == "crowd"), "a stand that turned a few away is not told to grow")
	row["crowd"] = 30
	var busy := Advisor._day_insights(row).filter(func(it: Dictionary) -> bool: return it["id"] == "crowd")
	check(busy.size() == 1 and int(busy[0]["prio"]) > 2, "a swamped stand gets the line as an observation, after the purchases")
	var report := Advisor.for_report(row)
	check(report.is_empty() or report[0]["id"] != "crowd", "the report never opens with 'the stand was full' (%s)" % [report.map(func(it: Dictionary) -> String: return it["id"])])
	# One line about the cold box.
	var spoil := Advisor._insight("spoil", "bad", "x", 20.0, "build", "coldbox")
	var fridge := Advisor._insight("buy", "great", "y", 30.0, "build", "coldbox")
	check(Advisor._one_coldbox_line([spoil, fridge]).size() == 1 and Advisor._one_coldbox_line([spoil]).size() == 1, "the cold box is advised once, not as a loss and a purchase")
	game.new_game()

## Mood faces, the two day speeds and the reason faces the sim uses.
func _test_feedback_ui() -> void:
	var seen := {}
	for kind in ["great", "ok", "bad", "pricey", "slow", "sold_out", "full", "rival"]:
		var tex: Texture2D = Icons.mood_icon(kind)
		check(tex != null and tex.get_width() == 48 and tex == Icons.mood_icon(kind), "mood face '%s' is drawn once and cached" % kind)
		var img := tex.get_image()
		seen[kind] = img.get_pixel(24, 8)
		check(img.get_pixel(1, 1).a < 0.01 and img.get_pixel(24, 8).a > 0.9, "mood face '%s' is a disc on a clear background" % kind)
	check(seen["great"].g > seen["great"].r and seen["bad"].r > seen["bad"].g, "a happy face is green and an unhappy one red")
	var great := Icons.mood_icon("great").get_image()
	var bad := Icons.mood_icon("bad").get_image()
	# The mouth differs as well as the colour: a smile is dark low in the face, a frown is not.
	check(great.get_pixel(24, 34).r < 0.3 and bad.get_pixel(24, 34).r > 0.5, "smile and frown differ in shape, not only colour")
	for reason in DaySim.LEAVE_MOOD.values():
		check(Icons.mood_icon(reason) != null, "the sim's leave reason '%s' has a face" % reason)
	# A chip can carry a face with words, or a face alone (the buyer walking away).
	var layer := FloatLayer.new()
	add_child(layer)
	var speaker := Node3D.new()
	add_child(speaker)
	layer.say(speaker, "Chicken Tikka", Color.WHITE, 0.5, 0.8, "great")
	check(layer.live_moods() == ["great"] and layer.live_count() == 1, "a sale chip carries the buyer's mood")
	layer.say(speaker, "", Color.WHITE, 1.3, 0.9, "bad")
	var chip_label: Label = layer._live[0]["label"]
	var chip_face: TextureRect = layer._live[0]["face"]
	check(layer.live_count() == 1 and layer.live_moods() == ["bad"] and not chip_label.visible and chip_face.visible and chip_face.texture == Icons.mood_icon("bad"),
		"the same speaker's chip turns into a face on its own")
	layer.say(speaker, "12:00", Color.WHITE, 0.5, 0.8)
	check(layer.live_moods().is_empty() and chip_label.visible and not chip_face.visible, "a plain line shows no face")
	layer.queue_free()
	speaker.queue_free()
	var hud_script: Script = load("res://scripts/ui/hud.gd")
	var consts := hud_script.get_script_constant_map()
	check(consts["DAY_SPEEDS"] == [2.0, 4.0], "players choose between 2x and 4x only")
	check(float(consts["HEAD_BUTTON"]) >= 60.0, "header controls are at least 60 logical px tall")
	var roll: Control = load("res://scripts/ui/card_roll.gd").new()
	add_child(roll)
	roll.size = Vector2(900, 240)
	var made := []
	roll.configure(5, 0, func(i: int) -> Control:
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 150)
		made.append(i)
		return card)
	roll._layout_cards()
	var opened := []
	roll.choose(0, func(): opened.append(0))
	check(opened == [0], "a tap on the focused card opens it at once")
	var view: Dictionary = roll.test_view()
	check(is_equal_approx(float(view["fit"]), 1.0) and bool(view["arrows"]) and bool(view["arrowsInside"]), "roll cards keep full size with arrows at the sides (%s)" % [view])
	roll.tight = true
	roll.size = Vector2(900, 150)
	roll._layout_cards()
	check(float(roll.test_view()["fit"]) >= 0.9, "a short roll in tight mode still shows cards at 90%% or more (%.2f)" % float(roll.test_view()["fit"]))
	roll.queue_free()

## Every string added for the tester feedback exists in both languages with matching
## placeholders, and uses only glyphs the web font can draw.
func _test_release3_strings() -> void:
	var file := FileAccess.open("res://assets/i18n/strings.csv", FileAccess.READ)
	var placeholders := RegEx.create_from_string("%[+]?[.0-9]*[dsf]")
	var rows := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < 3:
			continue
		var key := row[0]
		if not (key.begins_with("adv.") or key.begins_with("rep.") or key.begins_with("rpt.") or key.begins_with("ui.mood_") or key.begins_with("mk.") or key.begins_with("fame.")
				or key in ["ui.a_gain", "ui.a_loss", "ui.a_capped", "ui.p_needs_stage", "coach.finish.say", "guide.day.say"]):
			continue
		rows += 1
		check(row[1].strip_edges() != "" and row[2].strip_edges() != "", "%s has English and Arabic text" % key)
		var en := placeholders.search_all(row[1]).map(func(m: RegExMatch) -> String: return m.get_string().right(1))
		var ar := placeholders.search_all(row[2]).map(func(m: RegExMatch) -> String: return m.get_string().right(1))
		check(en == ar, "%s takes the same values in both languages (%s / %s)" % [key, en, ar])
		for bad in ["✓", "✕", "●", "○", "★", "☺", "☹", "Skip", "radio", "Radio", "WhatsApp", "Instagram"]:
			check(not row[1].contains(bad) and not row[2].contains(bad), "%s avoids '%s'" % [key, bad])
	check(rows >= 60, "the release 3 strings are present (%d)" % rows)

## Fame levels (Data.FAME_LEVELS): five named levels with a bar between thresholds; every
## requirement is a level's threshold; a level once reached is never lost (city-wide, local,
## the away-decay, an old save) and is announced once.
func _test_fame_levels(game) -> void:
	var was_persistent: bool = game.persist
	var lv: Array = Data.FAME_LEVELS
	var ids := lv.map(func(l: Dictionary) -> String: return String(l["id"]))
	check(ids == ["new", "known", "favourite", "talk", "legend"], "five fame levels in order (%s)" % str(ids))
	var froms := lv.map(func(l: Dictionary) -> float: return float(l["from"]))
	check(froms == [0.0, 0.30, 0.45, 0.60, 0.80], "fame thresholds 0 / 0.30 / 0.45 / 0.60 / 0.80 (%s)" % str(froms))
	var previous := TranslationServer.get_locale()
	for locale in ["en", "ar"]:
		TranslationServer.set_locale(locale)
		for l in lv:
			check(tr(String(l["name"])) != String(l["name"]) and tr(String(l["desc"])) != String(l["desc"]) and String(l["name"]) == "fame." + String(l["id"]),
				"fame level %s has a name and a line in %s" % [l["id"], locale])
	TranslationServer.set_locale("en")
	check(tr("fame.new") == "New in town" and tr("fame.legend") == "Dubai legend", "the English level names")
	TranslationServer.set_locale(previous)
	# level, bar and climb at the thresholds
	var levels := [[0.0, 0], [0.299, 0], [0.30, 1], [0.449, 1], [0.45, 2], [0.599, 2], [0.60, 3], [0.799, 3], [0.80, 4], [1.0, 4]]
	for pair in levels:
		check(Economy.fame_level(float(pair[0])) == int(pair[1]), "popularity %.3f is fame level %d (%d)" % [pair[0], pair[1], Economy.fame_level(float(pair[0]))])
	check(is_zero_approx(Economy.fame_progress(0.0)) and is_equal_approx(Economy.fame_progress(0.15), 0.5) and is_zero_approx(Economy.fame_progress(0.30))
		and is_equal_approx(Economy.fame_progress(0.375), 0.5) and is_equal_approx(Economy.fame_progress(0.70), 0.5), "the bar runs from a level's threshold to the next")
	check(Economy.fame_progress(0.80) == 1.0 and Economy.fame_progress(0.95) == 1.0, "the top level's bar is full")
	check(is_equal_approx(Economy.fame_value(0.375), 1.5) and Economy.fame_value(0.95) == 4.0, "fame value = level + bar")
	check(Economy.fame_level_for(0.0) == 0 and Economy.fame_level_for(0.30) == 1 and Economy.fame_level_for(0.45) == 2 and Economy.fame_level_for(0.60) == 3
		and Economy.fame_level_for(0.80) == 4 and Economy.fame_level_for(0.2) == 1, "a requirement names the lowest level that meets it")
	# every requirement is exactly a level's threshold
	var reqs := {}
	for id in Data.LOCATIONS:
		reqs["place " + id] = float(Data.LOCATIONS[id].get("unlock_pop", 0.0))
	for def in Data.PLOT_STAGES:
		if def.has("requires_local_rep"):
			reqs["stage " + String(def["id"])] = float(def["requires_local_rep"])
	reqs["blogger"] = float(Data.MARKETING["blogger"]["min_popularity"])
	for k in reqs:
		check(is_equal_approx(Economy.fame_floor(Economy.fame_level_for(float(reqs[k]))), float(reqs[k])), "%s asks for a fame level's threshold (%.2f)" % [k, reqs[k]])
	var want := {"place metro": 0.0, "place jbr": 0.30, "place downtown": 0.45, "place mall": 0.45, "place gv": 0.60,
		"stage kiosk": 0.30, "stage restaurant": 0.45, "stage flagship": 0.60, "blogger": 0.45}
	for k in want:
		check(is_equal_approx(float(reqs[k]), float(want[k])), "%s needs %.2f (%.2f)" % [k, want[k], reqs[k]])
	# the game's view
	game.persist = false
	game.new_game()
	check(game.fame_level() == 0 and is_equal_approx(game.fame_progress(), Data.START_POPULARITY / 0.30) and game.local_fame_level() == 0
		and is_equal_approx(game.local_fame_progress(), game.fame_progress()), "a new stand is New in town, its bar partly filled")
	check(game.fame_name(2) == tr("fame.favourite"), "level names are translated")
	game.popularity = 0.2999
	check(not game.location_unlocked("jbr") and game.location_unlocked("metro"), "JBR waits for Known on the street, the Metro does not")
	game.popularity = 0.30
	check(game.location_unlocked("jbr"), "Known on the street opens JBR")
	game.new_game()
	var events := []
	var grab := func(level: int, local: bool) -> void: events.append([level, local])
	game.fame_level_up.connect(grab)
	check(game.set_popularity(0.62) and game.fame_best == 3 and events == [[3, false]], "reaching a level is remembered and announced once (%s)" % str(events))
	check(not game.set_popularity(0.65) and events.size() == 1, "climbing inside a level announces nothing")
	game.set_popularity(0.2)
	check(is_equal_approx(game.popularity, 0.60) and game.fame_level() == 3, "city-wide fame never falls below a reached level (%.3f)" % game.popularity)
	var p: Dictionary = game.plot()
	check(game.set_local_fame(p, 0.47) and int(p["fame_best"]) == 2 and events.back() == [2, true], "a local level is remembered and announced as local")
	game.set_local_fame(p, 0.1)
	check(is_equal_approx(float(p["reputation"]), 0.45) and game.local_fame_level() == 2, "local fame never falls below its level")
	# a terrible day keeps the level
	game.popularity = 0.605
	var r: Dictionary = game.end_day({"_day": game.day, "served": 30, "mood_bad": 30, "satisfaction_sum": 3.0, "left_wait": 20, "sold_out": 40, "sold": {}})
	check(game.popularity >= 0.60 - 0.000001 and float(r["pop_delta"]) <= 0.0 and int(r["fame_level"]) == 3 and not r["fame_up"],
		"a terrible day keeps the level (%.3f)" % game.popularity)
	game.fame_level_up.disconnect(grab)
	# the away-decay of a fixed plot stops at its local level
	game.new_game()
	game.plots["creek"] = {"stage": "kiosk", "stations": {}, "reputation": 0.458, "last_visit": 1, "fame_best": 2}
	for i in range(6):
		game.day += 1
		game.prepare_day()
	check(is_equal_approx(float(game.plots["creek"]["reputation"]), 0.45), "a place you are away from fades no lower than its level (%.3f)" % float(game.plots["creek"]["reputation"]))
	game.plots["jbr"] = {"stage": "kiosk", "stations": {}, "reputation": 0.13, "last_visit": 1}
	for i in range(10):
		game.day += 1
		game.prepare_day()
	check(is_equal_approx(float(game.plots["jbr"]["reputation"]), 0.1), "below the first level the fading still stops at 0.1")
	# saves: version 6 keeps the best levels; an older save derives them; a stored best floors the value
	game.persist = true
	game.new_game()
	game.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	check(int(raw["version"]) == 6 and int(raw["fame_best"]) == 0 and raw["plots"]["fahidi"].has("fame_best"), "a version-6 save stores the fame levels")
	raw["version"] = 5
	raw.erase("fame_best")
	raw["popularity"] = 0.62
	raw["plots"] = {"fahidi": {"stage": "", "stations": {}, "reputation": 0.47, "last_visit": 1}}
	raw["history"] = [{"location": "fahidi", "weather": "sunny", "served": 12, "popularity": 0.62, "local_rep": 0.47}]
	_write_save(game, raw)
	check(game.load_game() and game.fame_best == 3 and int(game.plots["fahidi"]["fame_best"]) == 2, "a version-5 save gets its levels from its values")
	check(int(game.history[0]["fame_level"]) == 3 and int(game.history[0]["local_fame_level"]) == 2 and not game.history[0]["fame_up"], "an older day's row gains its levels")
	game.set_popularity(0.3)
	check(is_equal_approx(game.popularity, 0.60), "a loaded old save keeps the level it had reached")
	raw["version"] = 6
	raw["fame_best"] = 4
	raw["popularity"] = 0.5
	raw["plots"] = {"fahidi": {"stage": "", "stations": {}, "reputation": 0.2, "last_visit": 1, "fame_best": 3}}
	_write_save(game, raw)
	check(game.load_game() and is_equal_approx(game.popularity, 0.80) and is_equal_approx(float(game.plots["fahidi"]["reputation"]), 0.60),
		"a stored best level lifts a lower stored value to its threshold")
	raw["fame_best"] = 99
	raw["plots"] = {"fahidi": {"stage": "", "stations": {}, "reputation": 0.2, "last_visit": 1, "fame_best": -4}}
	_write_save(game, raw)
	check(game.load_game() and game.fame_best == 4 and int(game.plots["fahidi"]["fame_best"]) == 0, "malformed best levels are clamped")
	game.delete_save()
	# fame goals measure the climb, not a jump
	game.persist = false
	game.new_game()
	game.popularity = 0.375
	var climb := {}
	for g in Data.GOALS:
		if String(g["req"]["type"]) == "fame":
			climb[g["id"]] = Economy.goal_progress(g, game.goal_snapshot())
	check(climb.keys() == ["stars15", "stars25", "stars45"], "the three fame goals keep their ids (%s)" % str(climb.keys()))
	check(climb.get("stars15", 0.0) == 1.0 and is_equal_approx(float(climb.get("stars25", 0.0)), 1.5 / 3.0) and is_equal_approx(float(climb.get("stars45", 0.0)), 1.5 / 4.0),
		"fame goals fill with the climb (%s)" % str(climb))
	game.persist = was_persistent
	game.new_game()

## Fame is earned guest by guest: a green face fills the bar by one guest, an amber one by a
## quarter; a red face or a guest lost to the line or a sold-out dish takes one back. A day
## without red faces or lost guests never lowers fame, a bad day takes at most
## FAME_DAY_LOSS_MAX and never a level, and every level needs more guests than the one before.
func _test_fame_guests(game) -> void:
	check(Economy.mood(Data.MOOD_GREAT) == "great" and Economy.mood(Data.MOOD_GREAT - 0.001) == "ok"
		and Economy.mood(Data.MOOD_OK) == "ok" and Economy.mood(Data.MOOD_OK - 0.001) == "bad", "mood thresholds")
	for s in [0.1, 0.45, 0.6, 0.9]:
		var b := Economy.bubble_for_satisfaction(s)
		var m := Economy.mood(s)
		check(b == m or (m == "bad" and b == "bad_quality"), "the face over a guest matches the mood counted (%.2f: %s / %s)" % [s, b, m])
	var pts := Economy.fame_points({"served": 10, "mood_great": 4, "mood_ok": 4, "mood_bad": 2, "left_wait": 3, "sold_out": 1})
	check(is_equal_approx(float(pts["up"]), 5.0) and is_equal_approx(float(pts["down"]), 6.0) and int(pts["happy"]) == 4 and int(pts["content"]) == 4
		and int(pts["unhappy"]) == 2 and int(pts["lost"]) == 4, "fame points: green 1, amber 1/4, red and lost -1 (%s)" % str(pts))
	var old := Economy.fame_points({"served": 5, "satisfaction_sum": 5 * (Data.MOOD_GREAT + 0.01)})
	check(int(old["happy"]) == 5 and float(old["down"]) == 0.0, "a book without faces counts its buyers by the average satisfaction")
	# every level needs more guests than the one before
	var need := []
	for i in range(Data.FAME_LEVELS.size() - 1):
		var a := float(Data.FAME_LEVELS[i]["from"])
		var b := float(Data.FAME_LEVELS[i + 1]["from"])
		need.append((b - a) / Economy.fame_step(i))
	for i in range(1, need.size()):
		check(need[i] > need[i - 1], "level %d needs more guests than level %d (%.0f vs %.0f)" % [i + 1, i, need[i], need[i - 1]])
	check(Economy.fame_step(4) < Economy.fame_step(3) and Economy.fame_after(0.95, 1e6) == 1.0, "Dubai legend still creeps on, slowly, to 1.0")
	var cross := Economy.fame_after(0.44, (0.01 / Economy.fame_step(1)) + 10.0)
	check(is_equal_approx(cross, 0.45 + 10.0 * Economy.fame_step(2)), "points left after a level are spent at the next level's rate (%.4f)" % cross)
	# a clean day never lowers fame, at any level
	for pop in [0.22, 0.31, 0.5, 0.61, 0.85]:
		for st in [{"served": 0}, {"served": 6, "mood_ok": 6}, {"served": 20, "mood_great": 3, "mood_ok": 17, "left_full": 40, "crowd": 30}]:
			var c := Economy.fame_change(st, pop)
			check(float(c["delta"]) >= 0.0 and float(c["loss"]) == 0.0, "a day without red faces or lost guests never lowers fame (%.2f, %s)" % [pop, str(st)])
	# a terrible day is capped and keeps the level
	for pop in [0.25, 0.47, 0.62, 0.83]:
		var c := Economy.fame_change({"served": 40, "mood_bad": 40, "left_wait": 30, "sold_out": 30}, pop)
		check(float(c["loss"]) <= Data.FAME_DAY_LOSS_MAX + 1e-9 and float(c["after"]) >= Economy.fame_floor(Economy.fame_level(pop)) - 1e-9,
			"a terrible day takes at most %.2f and never the level (%.3f -> %.3f)" % [Data.FAME_DAY_LOSS_MAX, pop, c["after"]])
	var mixed := Economy.fame_change({"served": 20, "mood_great": 12, "mood_ok": 6, "mood_bad": 2, "left_wait": 1}, 0.5)
	check(is_equal_approx(float(mixed["delta"]), float(mixed["gain"]) - float(mixed["loss"])) and float(mixed["gain"]) > 0.0 and float(mixed["loss"]) > 0.0,
		"a mixed day shows its gain and its loss apart")
	# the day's row and the level-up signal
	var was_persistent: bool = game.persist
	game.persist = false
	game.new_game()
	var events := []
	var grab := func(level: int, local: bool) -> void: events.append([level, local])
	game.fame_level_up.connect(grab)
	game.popularity = 0.299
	game.plot()["reputation"] = 0.299
	var r: Dictionary = game.end_day({"_day": game.day, "served": 30, "mood_great": 30, "satisfaction_sum": 21.0, "sold": {}})
	check(r["fame_up"] and int(r["fame_level"]) == 1 and float(r["fame_gain"]) > 0.0 and float(r["fame_loss"]) == 0.0
		and r["local_fame_up"] and int(r["local_fame_level"]) == 1 and int(r["fame_happy"]) == 30,
		"a good day's row carries the gain, the new level and the level-up (%s)" % str([r["fame_gain"], r["fame_loss"], r["fame_level"], r["fame_up"]]))
	check(events.has([1, false]) and events.has([1, true]), "reaching a level emits fame_level_up for the city and the place (%s)" % str(events))
	events.clear()
	game.day += 1
	var r2: Dictionary = game.end_day({"_day": game.day, "served": 10, "mood_great": 2, "mood_bad": 8, "left_wait": 6, "satisfaction_sum": 3.0, "sold": {}})
	check(not r2["fame_up"] and float(r2["fame_loss"]) > 0.0 and float(r2["fame_gain"]) > 0.0 and int(r2["fame_unhappy"]) == 14 and events.is_empty()
		and is_equal_approx(float(r2["pop_delta"]), float(r2["fame_gain"]) - float(r2["fame_loss"])), "a bad day's row shows the loss (%s)" % str([r2["fame_gain"], r2["fame_loss"]]))
	game.fame_level_up.disconnect(grab)
	# a dish upgrade turns faces green, a high price turns them amber (the statistical day)
	var shares := {}
	for setup in ["base", "dish", "price"]:
		game.new_game()
		for id in Data.INGREDIENTS:
			game.inventory[id] = 200
		game.weather = "sunny"
		game.forecast = "sunny"
		for id in game.menu:
			if setup == "dish" and game.menu[id]["unlocked"]:
				game.menu[id]["level"] = 1
			if setup == "price":
				game.menu[id]["price"] = float(Data.MENU_ITEMS[id]["base_price"]) * 1.25
		var great := 0
		var faces_n := 0
		for s in range(6):
			var rng := RandomNumberGenerator.new()
			rng.seed = 900 + s
			var st := FastSim.run(game.sim_context(), rng)
			great += int(st["mood_great"])
			faces_n += int(st["mood_great"]) + int(st["mood_ok"]) + int(st["mood_bad"])
		shares[setup] = float(great) / maxf(1.0, faces_n)
	check(shares["dish"] > shares["base"] + 0.15 and shares["price"] < shares["base"] - 0.15,
		"an upgrade turns faces green, a high price turns them amber (%s)" % str(shares))
	game.persist = was_persistent
	game.new_game()

## Every upgrade has a job the scoring sees: a cold box buys ahead and saves spoilage, quality
## earns fame, every candidate says what it is for, and two goals walk the player through them.
func _test_upgrade_jobs(game) -> void:
	var was_persistent: bool = game.persist
	game.persist = false
	# categories
	var cats := ["capacity", "quality", "freshness", "reach"]
	for id in Data.STATIONS.keys() + ["seating"]:
		check(cats.has(String(Data.STATION_CATEGORY.get(id, ""))), "station %s has a category (%s)" % [id, Data.STATION_CATEGORY.get(id, "none")])
	var want := {"counter": "capacity", "grill": "capacity", "seating": "capacity", "valet": "capacity", "music": "quality", "shade": "quality",
		"majlis": "quality", "washroom": "quality", "lights": "quality", "coldbox": "freshness", "signage": "reach"}
	for id in want:
		check(Data.STATION_CATEGORY[id] == want[id], "%s is %s" % [id, want[id]])
	check(Autoplayer.category("stage", "stall") == "capacity" and Autoplayer.category("enhance", "chicken_tikka") == "quality"
		and Autoplayer.category("item", "shawarma") == "quality" and Autoplayer.category("promo", "fliers") == "reach" and Autoplayer.category("move", "creek") == "reach",
		"stages are capacity, dishes quality, campaigns and moves reach")
	# packs bought ahead: cheaper bulk only when the night keeps it
	var chicken: Array = Data.INGREDIENTS["chicken"]["packs"]
	var warm := Economy.supply_packs_ahead(chicken, 60, 60, 0.65)
	var cold := Economy.supply_packs_ahead(chicken, 60, 60, 0.9)
	check(int(warm["qty"]) == 60 and float(warm["cost"]) == float(Economy.supply_packs(chicken, 60)["cost"]) and float(warm["two_day"]) == float(warm["plain_two_day"]),
		"without a cold box a day's chicken is bought for the day (%d)" % int(warm["qty"]))
	check(int(cold["qty"]) > 60 and float(cold["two_day"]) < float(cold["plain_two_day"]) and int(cold["carry"]) > 0,
		"with a cold box the bigger pack wins over two days (%d units, %.0f vs %.0f)" % [cold["qty"], cold["two_day"], cold["plain_two_day"]])
	check(Economy.supply_packs_ahead(chicken, 0, 60, 1.0)["counts"].is_empty() and float(Economy.supply_packs(chicken, 30)["cost"]) == 54.0,
		"nothing to buy buys nothing; today's cheapest whole packs stay as they were")
	# the stock plan at a busy stand
	var busy := func() -> void:
		game.new_game()
		game.weather = "sunny"
		game.forecast = "sunny"
		game.plot()["stage"] = "restaurant"
		for id in ["counter", "grill", "doner", "fryer", "karak", "seating"]:
			game.plot()["stations"][id] = 6
		for id in game.menu:
			if game.item_available(id):
				game.menu[id]["unlocked"] = true
				game.menu[id]["enabled"] = true
		game.money = 1000000.0
	busy.call()
	var plain: Dictionary = game.daily_stock_plan()
	check(not plain["ahead"] and float(plain["saving"]) == 0.0, "without a cold box Stock today buys for today")
	game.plot()["stations"]["coldbox"] = 3
	var ahead: Dictionary = game.daily_stock_plan()
	check(ahead["ahead"] and float(ahead["saving"]) > 0.0 and float(ahead["cost"]) > float(plain["cost"]),
		"with a cold box Stock today buys ahead when two days cost less (%.0f now, saves %.0f)" % [ahead["cost"], ahead["saving"]])
	game.money = float(plain["cost"]) + float(game.loc()["rent"]) + game.daily_wages() + 1.0
	var tight: Dictionary = game.daily_stock_plan()
	check(not tight["ahead"] and is_equal_approx(float(tight["cost"]), float(plain["cost"])), "short of cash, the plan falls back to today's packs")
	var before: Dictionary = game.inventory.duplicate()
	check(game.stock_for_today() and game.money >= float(game.loc()["rent"]) + game.daily_wages(), "Stock today never touches the rent and wages")
	var left: float = game.money
	check(not game.stock_for_today() and game.money == left, "a repeat tap buys nothing")
	game.money = 1000000.0
	game.inventory = before
	check(game.stock_for_today() and not game.stock_for_today(), "a repeat tap after buying ahead buys nothing either")
	# the cold box's saving
	busy.call()
	check(game.coldbox_saving() > 0.0, "at a busy stand the first cold box saves money (%.0f a day)" % game.coldbox_saving())
	game.history = [{"spoiled": {"chicken": 30}}, {"spoiled": {"chicken": 30}}]
	var with_spoil: float = game.coldbox_saving()
	game.history = []
	var without: float = game.coldbox_saving()
	var meat: float = 30.0 * (1.0 - float(Data.STATIONS["coldbox"]["spoil_meat"][1]) / float(Data.STATIONS["coldbox"]["spoil_meat"][0])) * game.ingredient_cost("chicken")
	check(is_equal_approx(with_spoil - without, meat), "the spoilage a cold box stops counts from the books (%.1f vs %.1f)" % [with_spoil - without, meat])
	game.plot()["stations"]["coldbox"] = 3
	check(game.coldbox_saving() == 0.0, "a full cold box saves nothing more")
	# quality earns fame: the estimate's faces, the helpers and the scoring
	game.new_game()
	game.weather = "sunny"
	game.forecast = "sunny"
	game.money = 5000.0
	for day in range(4):
		Autoplayer.play_day(false, null, null)
	game.money = 5000.0
	var base := Economy.throughput_estimate(game.sim_context())
	var faces: Dictionary = base["moods"]
	check(is_equal_approx(float(faces["great"]) + float(faces["ok"]) + float(faces["bad"]), float(base["served"])) and float(base["wait"]) >= 0.0,
		"the estimate gives every buyer a face (%s of %.1f)" % [str(faces), float(base["served"])])
	var better := Economy.throughput_estimate(game.what_if({"enhance": "chicken_tikka"}))
	check(float(better["moods"]["great"]) > float(faces["great"]) and float(better["fame_points"]) > float(base["fame_points"]), "a dish upgrade shows as more green faces in the estimate")
	var q: Dictionary = game.quality_gain({"enhance": "chicken_tikka"})
	check(float(q["happy"]) > 0.0 and float(q["points"]) > 0.0 and float(q["fame"]) > 0.0 and float(q["value"]) >= 0.0,
		"quality_gain quotes the happy guests and the fame (%s)" % str(q))
	check(Economy.fame_worth(10.0, 0.4, 100.0) > Economy.fame_worth(5.0, 0.4, 100.0) and Economy.fame_worth(10.0, 0.4, 0.0) == 0.0
		and Economy.fame_worth(-10.0, 0.45, 100.0) == 0.0, "fame is worth more points times its price, and nothing below a level")
	var snapshot := JSON.stringify([game.money, game.inventory, game.rig, game.plots, game.menu, game.marketing, game.popularity, game.location, game.goal_index])
	Economy.estimate_calls = 0
	var ranked: Dictionary = Autoplayer.rank([], null, true)
	var calls := Economy.estimate_calls
	check(JSON.stringify([game.money, game.inventory, game.rig, game.plots, game.menu, game.marketing, game.popularity, game.location, game.goal_index]) == snapshot,
		"rank changes nothing")
	check(calls <= 60, "the advisor's ranking stays cheap (%d estimates)" % calls)
	var by := {}
	for c in ranked["cands"]:
		check(cats.has(String(c.get("category", ""))) and c.has("happy") and c.has("fame_value") and c.has("saving"), "candidate %s:%s says what it is for" % [c["kind"], c["id"]])
		by["%s:%s" % [c["kind"], c["id"]]] = c
	var e: Dictionary = by.get("enhance:chicken_tikka", {})
	check(not e.is_empty() and float(e["fame_value"]) > 0.0 and float(e["happy"]) > 0.0 and String(e["category"]) == "quality",
		"a dish upgrade is worth the fame it earns (%s)" % str(e))
	var ctr: Dictionary = by.get("station:counter", {})
	check(not ctr.is_empty() and float(ctr["fame_value"]) == 0.0 and String(ctr["category"]) == "capacity", "a counter level is scored on the day alone")
	# the advisor's budget at a large restaurant
	busy.call()
	game.plot()["stations"]["music"] = 1
	game.plot()["stations"]["majlis"] = 1
	Economy.estimate_calls = 0
	Autoplayer.rank([], null, true)
	check(Economy.estimate_calls <= 60, "ranking a large restaurant stays cheap (%d estimates)" % Economy.estimate_calls)
	# shade cools a hot day
	game.new_game()
	game.rig["stations"]["shade"] = 2
	check(is_equal_approx(game.satisfaction_bonus("hot") - game.satisfaction_bonus(), 2.0 * float(Data.STATIONS["shade"]["hot_satisfaction_per_level"])),
		"shade adds satisfaction on a hot day")
	game.forecast = "hot"
	check(is_equal_approx(float(game.sim_context()["satisfaction_bonus"]), game.satisfaction_bonus("hot")), "a hot forecast plans with the shade's cooling")
	# the two new goals
	check(Data.GOALS.size() == 20, "the goal ladder has 20 goals (%d)" % Data.GOALS.size())
	var idx := {}
	for i in range(Data.GOALS.size()):
		idx[Data.GOALS[i]["id"]] = i
	check(idx.has("dish1") and idx.has("coldbox1") and Data.GOALS[idx["dish1"]]["req"] == {"type": "dish_level", "n": 1}
		and Data.GOALS[idx["coldbox1"]]["req"] == {"type": "station_level", "station": "coldbox", "n": 1}, "a dish upgrade goal and a cold box goal")
	check(int(idx["dish1"]) < int(idx["stall"]) and int(idx["coldbox1"]) < int(idx["truck"]) and int(idx["coldbox1"]) > int(idx["stall"]), "they sit early in the ladder")
	var previous := TranslationServer.get_locale()
	for locale in ["en", "ar"]:
		TranslationServer.set_locale(locale)
		for id in ["dish1", "coldbox1"]:
			for suffix in ["", ".desc", ".say"]:
				var key: String = "goal." + String(id) + String(suffix)
				check(tr(key) != key, "%s has %s text" % [key, locale])
	TranslationServer.set_locale(previous)
	game.new_game()
	var dish_goal: Dictionary = Data.GOALS[idx["dish1"]]
	check(Economy.goal_progress(dish_goal, game.goal_snapshot()) == 0.0, "no dish upgraded yet")
	game.menu["chicken_tikka"]["level"] = 1
	check(Economy.goal_progress(dish_goal, game.goal_snapshot()) == 1.0, "one dish upgrade completes the goal")
	game.menu["chicken_tikka"]["level"] = 0
	# the bot chases them
	game.money = 3000.0
	for day in range(3):
		Autoplayer.play_day(false, null, null)
	game.money = 3000.0
	for id in game.menu:
		game.menu[id]["level"] = 0
	game.rig["stations"]["coldbox"] = 0
	game.goal_index = idx["dish1"]
	var chase: Dictionary = Autoplayer.rank([], null, true)
	check(chase["cands"].any(func(c: Dictionary) -> bool: return c["kind"] == "enhance" and float(c["net"]) < float(c["cost"])), "the bot weighs a dish upgrade for the goal's reward")
	game.goal_index = idx["coldbox1"]
	chase = Autoplayer.rank([], null, true)
	check(chase["cands"].any(func(c: Dictionary) -> bool: return c["kind"] == "station" and c["id"] == "coldbox" and float(c["net"]) < float(c["cost"]) and float(c["gain"]) > 0.0),
		"the bot weighs a cold box for the goal's reward")
	# an older save steps back to the new goals, then skips what it had done
	game.persist = true
	game.new_game()
	game.save()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(game.save_path))
	var old_ladder := []
	for g in Data.GOALS:
		if not g["id"] in ["dish1", "coldbox1"]:
			old_ladder.append(g["id"])
	raw["version"] = 5
	raw["goal_index"] = 13
	raw["goals_claimed"] = old_ladder.slice(0, 13)
	_write_save(game, raw)
	check(game.load_game() and game.goal_index == idx["dish1"], "a release 3 save is offered the new dish goal first (%d)" % game.goal_index)
	game.menu["chicken_tikka"]["level"] = 1
	check(game.claim_goal() and game.goal_index == idx["coldbox1"], "then the cold box goal (%d)" % game.goal_index)
	game.rig["stations"]["coldbox"] = 1
	check(game.claim_goal() and String(game.current_goal()["id"]) == String(old_ladder[13]), "then where it left off (%s)" % str(game.current_goal().get("id", "")))
	game.delete_save()
	game.persist = was_persistent
	game.new_game()
