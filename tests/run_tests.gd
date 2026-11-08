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
	_test_save_load(game)
	_test_pricing(game)
	_test_save_validation(game)
	_test_migration(game)
	_test_daily_stock(game)
	_test_mobile_stages_and_lighting(game)
	_test_later_item_handoff(game)
	_test_skip_pickup(game)
	_test_restaurant_service(game)
	_test_terrace_clearance(game)
	print("tests: %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

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
	check(rendered_guest.simulation_speed == 1.0, "Skip keeps the visible cast moving at its normal pace")
	var player := ModelLib.animation_player(rendered_guest.model)
	var walk_rate := rendered_guest.speed / Customer.WALK_SPEED * Customer.WALK_ANIMATION_SPEED * 2.0
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
	sim._close()
	check(reports.is_empty(), "the closing curtain waits for the active handoff")
	buyer._process(DaySim.HANDOFF_SECONDS)
	sim._process(DaySim.HANDOFF_SECONDS)
	check(reports.size() == 1 and sim.stats["served"] == 1, "Skip settles the actual purchase exactly once")
	sim.queue_free()
	world.queue_free()
	game.new_game()

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
			worker._process(0.05)
			if worker.state == DiningStaff.State.CLEAN:
				saw_cleaning = true
		if diner.state != Customer.State.DONE:
			diner._process(0.05)
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
	check(is_zero_approx(Economy.competition_loss(0.6, 0.3, 1.8)), "radio at x1.8 covers competition fully")
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
	check(is_equal_approx(Economy.counter_capacity(0), 0.5) and Economy.queue_cap(0, Data.stage_def(0)) == 4, "day-1 parity: 2 min per order, 4 in line")
	check(Economy.counter_capacity(10) > Economy.counter_capacity(0) * 4.0, "ten counter levels quadruple order speed")
	check(Economy.queue_cap(3, Data.stage_def(2)) == 4 + 3 + 2, "queue cap adds counter levels and the stage bonus")
	check(Economy.kitchen_capacity(Data.STATIONS["doner"], 0) == 0.0 and Economy.kitchen_capacity(Data.STATIONS["doner"], 1) > 0.0, "doner spit does nothing until installed")
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
	check(is_equal_approx(money_before - game.money, 2000.0), "stall costs 2000")
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
	game.plot()["reputation"] = 0.5
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
	game.popularity = 0.9
	var big := Economy.throughput_estimate(_ctx_for(game, {"counter": 15, "grill": 15, "karak": 10, "seating": 10}, 3, "downtown"))
	var small := Economy.throughput_estimate(_ctx_for(game, {"counter": 0, "grill": 0}, 3, "downtown"))
	check(float(big["served"]) > float(small["served"]) * 1.2, "more station levels, more customers served downtown (%s vs %s)" % [big["served"], small["served"]])
	check(float(small["util"]["counter"]) > 0.5 and float(big["util"]["counter"]) < float(small["util"]["counter"]), "an empty kiosk downtown works its counter hard; levels relieve it (%s)" % str(small["util"]))
	check(game.station_level("grill") == 2 and game.location == "fahidi", "what_if leaves the state alone")
	# a maxed kiosk day in FastSim
	for id in ["counter", "grill", "karak", "seating"]:
		game._station_store()[id] = 12
	game.popularity = 0.9
	game.plot()["reputation"] = 0.9
	for ing in Data.INGREDIENTS:
		game.inventory[ing] = 1000
	game.weather = "sunny"
	game.rng.seed = 2026 # a fixed day: the unseeded run lands at 73-90 served
	var fast := FastSim.run(game.sim_context(), game.rng)
	check(int(fast["served"]) > 80 and int(fast["dine_in"]) > 10, "maxed kiosk day at fahidi serves plenty with diners (%s served, %s dined)" % [fast["served"], fast["dine_in"]])

func _test_goals(game) -> void:
	game.new_game()
	check(game.current_goal()["id"] == "first_30" and not game.goal_ready(), "first goal waits for 30 customers")
	check(not game.claim_goal(), "cannot claim early")
	game.inventory["chicken"] = 500
	game.end_day({"served": 35, "revenue": 350.0, "cogs": 100.0, "satisfaction_sum": 25.0, "sold": {}})
	check(game.goal_ready(), "30 served in a day completes the first goal")
	var m: float = game.money
	check(game.claim_goal() and game.money == m + 150.0 and game.goal_index == 1 and game.goals_claimed == ["first_30"], "claim pays once and advances")
	check(not game.claim_goal(), "next goal not ready yet")
	game.money = 1000.0
	game.buy_station_level("counter")
	check(game.goal_ready() and game.claim_goal() and game.current_goal()["id"] == "stars15", "counter goal, then stars")
	check(game.goal_progress() > 0.5 and game.goal_progress() < 1.0, "progress toward 1.5 stars is partial")

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
	game.save()
	game.new_game()
	check(game.load_game(), "load ok")
	check(game.money == 777.0, "money restored")
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
	check(game.goal_index == Data.GOALS.size() and game.goals_claimed == ["first_30"], "goal index clamped, unknown goals dropped")
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
	check(game.goal_index >= 4 and game.goals_claimed.has("served200"), "already-achieved goals are skipped (%d)" % game.goal_index)
	game.delete_save()
	# a cart player with the neon sign gets signage instead of lights
	_write_save(game, {"version": 2, "money": 100.0, "day": 3, "popularity": 0.3, "location": "fahidi", "vehicle": "cart", "upgrades": {"neon": true, "sweets": true}})
	check(game.load_game() and game.station_level("signage") == 2 and game.station_level("lights") == 0, "neon on a cart becomes signage")
	check(game.money == 100.0 + 2500.0, "sweets counter without a truck is refunded")
	game.delete_save()
