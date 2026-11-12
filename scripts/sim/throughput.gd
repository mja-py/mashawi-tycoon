class_name Throughput
extends RefCounted
## The customer pipeline of one day, shared by DaySim (payload = Customer node) and FastSim
## (payload = a body id): counter line -> order -> kitchen station -> pickup hatch or table.
## Time is in sim-seconds (Data.SERVICE). One entry is one visible buyer and their party:
## the kitchen cooks every portion, the line and the chairs count the buyer once.
##
## The payload's own beats are played by the caller and reported back through callbacks:
## counter_ready says the order has been given, pickup_ready that the buyer stands at the
## hatch with the hatch free (or, for a diner, that they sit and a server is free).

var ctx: Dictionary
var rng: RandomNumberGenerator
var queue: Array = []            # [{payload, item, portions, wait}] in line, front first
var backlog: Dictionary = {}     # station -> entries still cooking, FIFO
var pickup: Array = []           # takeaway entries after ordering, in order, until handed over
var plates: Array = []           # dine-in entries after ordering, until the meal leaves the pass
var seated: Array = []           # [{payload, left, active}]
var dirty: Array = []            # [{table}], released by table_clean
var stats := {"served": 0, "portions": 0, "left_wait": 0, "max_queue": 0, "dine_in": 0, "wait_sum": 0.0}
var on_served: Callable          # (payload, item, wait_s, dine_in, portions)
var on_gave_up: Callable         # (payload, reason)
var on_ordered: Callable         # (payload, station)
var on_left_seat: Callable       # (payload) -> table
var take_order: Callable         # (payload, item, portions) -> portions held (0 = nothing left)
var counter_ready: Callable      # (payload, portions) -> bool, the order has been given
var pickup_ready: Callable       # (payload) -> bool
var waiting_in_line: Callable    # (payload) -> bool, false while walking up or giving the order
var waiting_for_food: Callable   # (payload) -> bool, false while still walking to the pickup spot
var dining_choice: Callable      # (payload, item) -> bool, reserves an actual seat
var table_clean: Callable        # (table) -> bool
var meal_finished: Callable      # (payload) -> bool
var _progress: Dictionary = {}
var _busy: Dictionary = {}
var _total := 0.0
var _seats := 0
var _station_of_kind: Dictionary = {}
var _kitchen: Dictionary = {}

func setup(context: Dictionary, r: RandomNumberGenerator) -> void:
	ctx = context
	rng = r
	_seats = int(ctx.get("seats", 0))
	_station_of_kind = ctx.get("station_of_kind", {})
	_kitchen = ctx.get("kitchen", {})
	_busy = {"counter": 0.0}
	for s in _kitchen:
		backlog[s] = []
		_progress[s] = 0.0
		_busy[s] = 0.0
	if _seats > 0:
		_busy["seating"] = 0.0

func queue_len() -> int:
	return queue.size()

func queue_cap() -> int:
	return int(ctx.get("queue_cap", Economy.BASE_QUEUE_CAP))

func is_full() -> bool:
	return queue.size() >= queue_cap()

func seats_free() -> int:
	return _seats - seated.size() - dirty.size()

func patience() -> float:
	return float(ctx.get("patience_s", Data.SERVICE["patience_s"]))

## Join the counter line. False when the line is full.
func enqueue(payload, item: String, portions: int = 1) -> bool:
	if is_full():
		return false
	queue.append({"payload": payload, "item": item, "portions": maxi(1, portions), "wait": 0.0})
	stats["max_queue"] = maxi(int(stats["max_queue"]), queue.size())
	return true

## Someone walked away (or a node vanished): drop them from wherever they are.
func remove(payload) -> void:
	for list in [queue, pickup, plates, seated]:
		for i in range(list.size() - 1, -1, -1):
			if list[i]["payload"] == payload:
				list.remove_at(i)
	for s in backlog:
		var b: Array = backlog[s]
		for i in range(b.size() - 1, -1, -1):
			if b[i]["payload"] == payload:
				b.remove_at(i)
				if i == 0:
					_progress[s] = 0.0

## Payloads standing in the counter line, front first (for the visual queue).
func queue_payloads() -> Array:
	var out := []
	for e in queue:
		out.append(e["payload"])
	return out

## Takeaway buyers waiting for their bag, in order: index 0 stands at the hatch.
func waiting_payloads() -> Array:
	var out := []
	for e in pickup:
		out.append(e["payload"])
	return out

## The entry of a payload that has ordered and not yet been served (or {}).
func order_of(payload) -> Dictionary:
	for list in [pickup, plates]:
		for e in list:
			if e["payload"] == payload:
				return e
	return {}

func tick(dt: float, _hour: float = 0.0) -> void:
	_total += dt
	# Counter: the front buyer gives the order (its beat), then it goes to the kitchen.
	if not queue.is_empty():
		_busy["counter"] += dt
		var front: Dictionary = queue[0]
		if not counter_ready.is_valid() or counter_ready.call(front["payload"], int(front["portions"])):
			queue.pop_front()
			_take(front)
	# Kitchen stations cook every portion of the orders in front of them, first come first.
	for s in backlog:
		var b: Array = backlog[s]
		if b.is_empty():
			_progress[s] = 0.0
			continue
		_busy[s] += dt
		_progress[s] += float(_kitchen.get(s, 0.0)) * dt
		while not b.is_empty() and float(_progress[s]) + 0.000001 >= float(b[0]["portions"]):
			_progress[s] = maxf(0.0, float(_progress[s]) - float(b[0]["portions"]))
			b[0]["cooked"] = true
			b.pop_front()
		if b.is_empty():
			_progress[s] = 0.0
	# The pickup hatch hands the next cooked bag to whoever stands first in the pickup line.
	if not pickup.is_empty() and bool(pickup[0].get("cooked", false)):
		if not pickup_ready.is_valid() or pickup_ready.call(pickup[0]["payload"]):
			_serve(pickup.pop_front())
	# Cooked meals leave the pass with a free server once the diner sits.
	var i := 0
	while i < plates.size():
		var e: Dictionary = plates[i]
		if bool(e.get("cooked", false)) and (not pickup_ready.is_valid() or pickup_ready.call(e["payload"])):
			plates.remove_at(i)
			_serve(e)
			continue
		i += 1
	# Waiting for food (once at the pickup spot or seated) counts against satisfaction.
	for list in [pickup, plates]:
		for e in list:
			if not waiting_for_food.is_valid() or waiting_for_food.call(e["payload"]):
				e["wait"] += dt
	# Standing behind someone in line is waiting; past their patience they walk.
	var limit := patience()
	for j in range(queue.size() - 1, 0, -1):
		var e: Dictionary = queue[j]
		if waiting_in_line.is_valid() and not waiting_in_line.call(e["payload"]):
			continue
		e["wait"] += dt
		if e["wait"] > limit:
			queue.remove_at(j)
			stats["left_wait"] = int(stats["left_wait"]) + 1
			if on_gave_up.is_valid():
				on_gave_up.call(e["payload"], "wait")
	# Seats: eat, leave, the table stays dirty until it is cleared.
	if _seats > 0 and not seated.is_empty():
		_busy["seating"] += dt * float(seated.size()) / float(_seats)
	for j in range(seated.size() - 1, -1, -1):
		if not bool(seated[j].get("active", true)):
			continue
		seated[j]["left"] -= dt
		var payload = seated[j]["payload"]
		if seated[j]["left"] <= 0.0 and (not meal_finished.is_valid() or meal_finished.call(payload)):
			seated.remove_at(j)
			var table := -1
			if on_left_seat.is_valid():
				table = int(on_left_seat.call(payload))
			dirty.append({"table": table, "left": 0.0})
	for j in range(dirty.size() - 1, -1, -1):
		var ready: bool = table_clean.call(int(dirty[j]["table"])) if table_clean.is_valid() else true
		if ready:
			dirty.remove_at(j)

## The counter took an order: hold the stock, choose a table, start cooking.
func _take(e: Dictionary) -> void:
	if take_order.is_valid():
		var held := int(take_order.call(e["payload"], e["item"], int(e["portions"])))
		if held <= 0:
			return
		e["portions"] = held
	# A party bigger than a table orders to take away; one diner holds one chair.
	var dine := int(e["portions"]) <= int(Data.SERVICE["dine_max_party"]) and seats_free() > 0 \
		and rng.randf() < float(ctx.get("dine_in_share", 0.0))
	if dine and dining_choice.is_valid():
		dine = dining_choice.call(e["payload"], e["item"])
	e["dine_in"] = dine
	if dine:
		seated.append({"payload": e["payload"], "left": float(ctx.get("dine_s", Data.SERVICE["dine_s"])), "active": false})
	var kind := String(Data.MENU_ITEMS[e["item"]].get("station_kind", ""))
	var station := String(_station_of_kind.get(kind, ""))
	if station != "" and backlog.has(station) and float(_kitchen.get(station, 0.0)) > 0.0:
		backlog[station].append(e)
		# Cooking your own party's food is expected; only the time beyond it is waiting.
		e["own_cook"] = float(e["portions"]) / float(_kitchen[station])
	else:
		e["cooked"] = true
		station = ""
	if dine:
		plates.append(e)
	else:
		pickup.append(e)
	if on_ordered.is_valid():
		on_ordered.call(e["payload"], station)

func _serve(e: Dictionary) -> void:
	var wait := maxf(0.0, float(e["wait"]) - float(e.get("own_cook", 0.0)))
	stats["served"] = int(stats["served"]) + 1
	stats["portions"] = int(stats["portions"]) + int(e["portions"])
	stats["wait_sum"] = float(stats["wait_sum"]) + wait
	var dine := bool(e.get("dine_in", false))
	if dine:
		stats["dine_in"] = int(stats["dine_in"]) + 1
	if on_served.is_valid():
		on_served.call(e["payload"], e["item"], wait, dine, int(e["portions"]))

## The guest has sat down with the meal: the eating timer starts now.
func seat_taken(payload) -> void:
	for e in seated:
		if e["payload"] == payload:
			e["active"] = true

## Closing time: everyone still in line goes home. Orders already taken are finished.
func close_queue() -> void:
	var line := queue
	queue = []
	for e in line:
		if on_gave_up.is_valid():
			on_gave_up.call(e["payload"], "closing")

func has_orders() -> bool:
	return not pickup.is_empty() or not plates.is_empty()

## Share of the day each stage was busy (seating = average occupancy).
func utilisation() -> Dictionary:
	var out := {}
	for s in _busy:
		out[s] = float(_busy[s]) / maxf(1.0, _total)
	return out
