class_name StockLedger
extends RefCounted
## Ingredients promised to orders in flight during one day. A party's portions are held
## when the counter takes the order, so the kitchen only cooks what is really in stock
## and a later buyer, or an add-on, cannot sell the same chicken twice. Nothing leaves
## Game.inventory until Game.sell is called for an actual handoff or delivery.

var _held := {}       # ingredient -> units held
var _orders := {}     # holder -> {"item", "portions", "needs"}

## Ingredient units not promised to anyone.
func free_units(ingredient: String) -> int:
	return int(Game.inventory.get(ingredient, 0)) - int(_held.get(ingredient, 0))

## Whole portions of an item that can still be promised or sold.
func portions_free(item: String) -> int:
	var needs := Economy.portion_ingredients(item, Game.menu[item])
	var n := 999999
	for ing in needs:
		if int(needs[ing]) <= 0:
			continue
		n = mini(n, maxi(0, free_units(ing)) / int(needs[ing]))
	return n

func holds(holder) -> bool:
	return _orders.has(holder)

func held_portions(holder) -> int:
	return int(_orders.get(holder, {}).get("portions", 0))

## Hold up to `portions` of an item for a holder (a buyer). Returns how many were held.
func hold(holder, item: String, portions: int) -> int:
	release(holder)
	var n := mini(portions, portions_free(item))
	if n <= 0:
		return 0
	var needs := Economy.portion_ingredients(item, Game.menu[item])
	for ing in needs:
		_held[ing] = int(_held.get(ing, 0)) + int(needs[ing]) * n
	_orders[holder] = {"item": item, "portions": n, "needs": needs}
	return n

## Give a holder's ingredients back (the buyer left, or the sale is about to consume them).
func release(holder) -> void:
	if not _orders.has(holder):
		return
	var order: Dictionary = _orders[holder]
	_orders.erase(holder)
	var needs: Dictionary = order["needs"]
	for ing in needs:
		_held[ing] = int(_held[ing]) - int(needs[ing]) * int(order["portions"])
		if int(_held[ing]) <= 0:
			_held.erase(ing)

## Sell a holder's order (or, without a hold, up to `portions` of free stock), one
## Game.sell per portion. Returns the portions actually sold.
func sell(holder, item: String, portions: int, unit_price: float) -> int:
	var n := portions
	if _orders.has(holder):
		n = held_portions(holder)
		release(holder)
	else:
		n = mini(n, portions_free(item))
	var sold := 0
	for i in range(n):
		if not Game.sell(item, unit_price):
			break
		sold += 1
	return sold

## An add-on can be sold only from stock nobody is waiting for.
func can_sell(item: String) -> bool:
	return Game.is_on_sale(item) and portions_free(item) > 0

## One completed order: every portion of the party through Game.sell at price x spend,
## then per food portion a side, a drink and a sweet may be added (business RNG, in that
## order; the pick within a kind is uniform and a pricey add-on is refused more often).
## Returns {sold, total, cogs, items (distinct, primary first), extras {id: n}, sweet}.
func settle(holder, item: String, portions: int, spend: float, wants: String, dine_in: bool,
		weather_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var price := float(Game.menu[item]["price"])
	var unit := Game.unit_cost(item)
	var sold := sell(holder, item, portions, price * spend)
	var out := {"sold": sold, "total": price * spend * sold, "cogs": unit * sold, "items": [item], "extras": {}, "sweet": false}
	if sold <= 0 or wants != "food":
		return out
	var bonus := Economy.ADDON_DINE_BONUS if dine_in else 0.0
	var groups := [["side", Economy.ADDON_SIDE], ["drink", Economy.addon_drink_chance(weather_id)], ["sweet", Economy.ADDON_SWEET]]
	for n in range(sold):
		for group in groups:
			var pool := []
			for id in Data.MENU_ITEMS:
				if Data.MENU_ITEMS[id]["kind"] == group[0] and can_sell(id):
					pool.append(id)
			if pool.is_empty():
				continue
			var pick: String = pool[rng.randi_range(0, pool.size() - 1)]
			if rng.randf() >= (float(group[1]) + bonus) * addon_appeal(pick):
				continue
			var ep := float(Game.menu[pick]["price"])
			var ec := Game.unit_cost(pick)
			if Game.sell(pick, ep):
				out["total"] += ep
				out["cogs"] += ec
				out["extras"][pick] = int(out["extras"].get(pick, 0)) + 1
				if not out["items"].has(pick):
					out["items"].append(pick)
				if group[0] == "sweet":
					out["sweet"] = true
	return out

## 0..1 willingness to add an extra item, falling off as its price climbs above fair.
static func addon_appeal(id: String) -> float:
	var ratio := float(Game.menu[id]["price"]) / float(Data.MENU_ITEMS[id]["base_price"])
	return clampf(1.6 - ratio * 0.9, 0.0, 1.0)

func clear() -> void:
	_held.clear()
	_orders.clear()

func is_empty() -> bool:
	return _orders.is_empty()
