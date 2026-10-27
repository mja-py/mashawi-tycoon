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
	_test_game_flow(game)
	_test_save_load(game)
	print("tests: %d passed, %d failed" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

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
	check(Economy.satisfaction(1.1, 1.0, 0.0, loc, 0.0) > Economy.satisfaction(0.6, 1.0, 0.0, loc, 0.0), "quality raises satisfaction")
	check(Economy.unit_cost("chicken_tikka", {"recipe": {"meat": 2, "veg": 2, "sauce": 1}}) < 8.0, "chicken tikka costs under AED 8 to make")

func _test_game_flow(game) -> void:
	game.new_game()
	check(game.money == Data.START_MONEY, "start money")
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
	game.money = 5000.0
	check(game.unlock_item("mutton_tikka") and game.menu["mutton_tikka"]["unlocked"], "unlock mutton tikka")
	check(game.buy_upgrade("fridge") and game.has_upgrade("fridge"), "buy fridge")
	check(not game.set_location("mall"), "mall needs the big truck")
	check(not game.buy_upgrade("sweets"), "sweets counter needs the food truck")
	check(not game.buy_vehicle("truck2"), "cannot skip to the big truck")
	game.money = 20000.0
	check(game.buy_vehicle("truck") and game.vehicle == "truck", "buy food truck")
	check(game.location_vehicle_ok("metro") and not game.location_vehicle_ok("mall"), "truck reaches metro, not mall")
	check(game.buy_upgrade("sweets"), "sweets counter after truck")
	check(game.item_available("saffron_cake") and game.unlock_item("saffron_cake"), "unlock a sweet")
	check(game.buy_vehicle("truck2") and game.queue_capacity() >= Economy.BASE_QUEUE_CAP + 4, "big truck adds queue")
	game.popularity = 0.9
	check(game.set_location("mall") and game.competition() > 0.0, "mall reachable with big truck")
	check(Data.vehicle_for_tier(0) == "cart" and Data.vehicle_for_tier(2) == "truck2", "vehicle_for_tier")
	check(is_equal_approx(game.spoil_rate("chicken"), 0.1) and is_zero_approx(game.spoil_rate("drink")), "spoil_rate with fridge")
	for ing in Data.INGREDIENTS:
		game.inventory[ing] = 200
	var fast := FastSim.run(game.sim_context(), game.rng)
	check(int(fast["passers"]) > 50 and int(fast["served"]) > 0 and float(fast["revenue"]) > 0.0, "FastSim produces a day (%s passers, %s served)" % [fast["passers"], fast["served"]])
	check(int(fast["lost_rival"]) > 0, "FastSim counts customers lost to rivals at the mall")
	check(not game.buy_upgrade("fridge"), "cannot buy twice")
	game.inventory["chicken"] = 100
	var r: Dictionary = game.end_day({"served": 20, "revenue": 240.0, "cogs": 120.0, "satisfaction_sum": 14.0, "sold": {"chicken_tikka": 20}})
	check(game.inventory["chicken"] == 90, "fridge keeps 90%% of chicken (%d)" % game.inventory["chicken"])
	check(r["profit"] < 120.0, "profit accounts for spoilage")
	check(game.day == 2, "day advanced")
	check(game.popularity > Data.START_POPULARITY, "good day raises popularity")

func _test_save_load(game) -> void:
	game.new_game()
	game.set_price("chicken_tikka", 15.0)
	game.set_recipe("chicken_tikka", "meat", 3)
	game.buy_upgrade("awning")
	game.money = 777.0
	game.save()
	game.new_game()
	check(game.load_game(), "load ok")
	check(game.money == 777.0, "money restored")
	check(game.menu["chicken_tikka"]["price"] == 15.0, "price restored")
	check(game.menu["chicken_tikka"]["recipe"]["meat"] == 3, "recipe restored")
	check(game.has_upgrade("awning"), "upgrade restored")
	game.delete_save()
	check(not game.has_save(), "save deleted")
	game.new_game()
	game.money = 5.0
	game.prepare_day()
	check(game.money == 5.0 + Data.BAILOUT_AMOUNT and game.bailouts == 1, "bailout when broke")
	game.prepare_day()
	check(game.bailouts == 1, "no bailout when solvent")
	check(game.expected_customers() > 5, "expected customers estimate (%d)" % game.expected_customers())
