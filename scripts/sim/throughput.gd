class_name Throughput
extends RefCounted
## The customer pipeline of one day, shared by DaySim (payload = Customer node) and FastSim
## (payload = item id): counter queue -> kitchen station backlog -> served -> (seat) -> gone.
## Capacities come from the context built by Game.sim_context(); time is in game minutes.

var ctx: Dictionary
var rng: RandomNumberGenerator
var queue: Array = []            # [{payload, item, wait}]
var backlog: Dictionary = {}     # station -> [{payload, item, wait}]
var seated: Array = []           # [{payload, left}]
var dirty: Array = []            # minutes until each dirty table is clean again
var stats := {"served": 0, "left_wait": 0, "max_queue": 0, "dine_in": 0, "wait_sum": 0.0, "kitchen_wait_sum": 0.0}
var on_served: Callable          # (payload, item, wait_min, dine_in)
var on_gave_up: Callable         # (payload, reason)
var on_ordered: Callable         # (payload, station)
var on_left_seat: Callable       # (payload)
var counter_ready: Callable
var pickup_ready: Callable
var waiting_in_line: Callable
var _acc_counter := 0.0
var _acc: Dictionary = {}
var _busy: Dictionary = {}
var _total_min := 0.0
var _seats := 0
var _station_of_kind: Dictionary = {}

func setup(context: Dictionary, r: RandomNumberGenerator) -> void:
	ctx = context
	rng = r
	_seats = int(ctx.get("seats", 0))
	_station_of_kind = ctx.get("station_of_kind", {})
	_busy = {"counter": 0.0}
	for s in ctx.get("kitchen", {}):
		backlog[s] = []
		_acc[s] = 0.0
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

## Join the counter line. False when the line is full.
func enqueue(payload, item: String) -> bool:
	if is_full():
		return false
	queue.append({"payload": payload, "item": item, "wait": 0.0})
	stats["max_queue"] = maxi(int(stats["max_queue"]), queue.size())
	return true

## Someone walked away (or a node vanished): drop them from wherever they are.
func remove(payload) -> void:
	for i in range(queue.size() - 1, -1, -1):
		if queue[i]["payload"] == payload:
			queue.remove_at(i)
	for s in backlog:
		var b: Array = backlog[s]
		for i in range(b.size() - 1, -1, -1):
			if b[i]["payload"] == payload:
				b.remove_at(i)
	for i in range(seated.size() - 1, -1, -1):
		if seated[i]["payload"] == payload:
			seated.remove_at(i)

## Payloads standing in the counter line, front first (for the visual queue).
func queue_payloads() -> Array:
	var out := []
	for e in queue:
		out.append(e["payload"])
	return out

## Payloads waiting for their food, in order.
func waiting_payloads() -> Array:
	var out := []
	for s in backlog:
		for e in backlog[s]:
			out.append(e["payload"])
	return out

func tick(dt_min: float, _hour: float) -> void:
	_total_min += dt_min
	var patience := float(ctx.get("patience_min", Economy.BASE_PATIENCE_MIN))
	# Counter: takes orders at counter_cap per minute and hands them to the kitchen.
	_acc_counter += float(ctx.get("counter_cap", 0.5)) * dt_min
	while _acc_counter >= 1.0 and not queue.is_empty():
		if counter_ready.is_valid() and not counter_ready.call(queue[0]["payload"]):
			_acc_counter = minf(_acc_counter, 1.0)
			break
		_acc_counter -= 1.0
		var e: Dictionary = queue.pop_front()
		var kind := String(Data.MENU_ITEMS[e["item"]].get("station_kind", ""))
		var station := String(_station_of_kind.get(kind, ""))
		if station != "" and backlog.has(station):
			backlog[station].append(e)
			if on_ordered.is_valid():
				on_ordered.call(e["payload"], station)
		else:
			_serve(e)
	if queue.is_empty():
		_acc_counter = minf(_acc_counter, 1.0)
	else:
		_busy["counter"] += dt_min
	# Kitchen stations.
	var kitchen: Dictionary = ctx.get("kitchen", {})
	for s in backlog:
		var b: Array = backlog[s]
		_acc[s] += float(kitchen.get(s, 0.0)) * dt_min
		while _acc[s] >= 1.0 and not b.is_empty():
			if pickup_ready.is_valid() and not pickup_ready.call(b[0]["payload"]):
				_acc[s] = minf(_acc[s], 1.0)
				break
			_acc[s] -= 1.0
			_serve(b.pop_front())
		if b.is_empty():
			_acc[s] = minf(_acc[s], 1.0)
		else:
			_busy[s] += dt_min
			for e in b:
				e["wait"] += dt_min
	# Whoever is still in line has waited another minute; past their patience they walk.
	for i in range(queue.size() - 1, -1, -1):
		var e: Dictionary = queue[i]
		if waiting_in_line.is_valid() and not waiting_in_line.call(e["payload"]):
			continue
		e["wait"] += dt_min
		if i > 0 and e["wait"] > patience:
			queue.remove_at(i)
			stats["left_wait"] = int(stats["left_wait"]) + 1
			if on_gave_up.is_valid():
				on_gave_up.call(e["payload"], "wait")
	# Seats: eat, leave, table dirty for a while.
	if _seats > 0 and not seated.is_empty():
		_busy["seating"] += dt_min * float(seated.size()) / float(_seats)
	for i in range(seated.size() - 1, -1, -1):
		if not bool(seated[i].get("active", true)):
			continue
		seated[i]["left"] -= dt_min
		if seated[i]["left"] <= 0.0:
			var e: Dictionary = seated[i]
			seated.remove_at(i)
			dirty.append(float(ctx.get("clean_min", 3.0)))
			if on_left_seat.is_valid():
				on_left_seat.call(e["payload"])
	for i in range(dirty.size() - 1, -1, -1):
		dirty[i] -= dt_min
		if dirty[i] <= 0.0:
			dirty.remove_at(i)

func _serve(e: Dictionary) -> void:
	stats["served"] = int(stats["served"]) + 1
	stats["wait_sum"] = float(stats["wait_sum"]) + float(e["wait"])
	var dine := false
	if seats_free() > 0 and rng.randf() < float(ctx.get("dine_in_share", 0.0)):
		dine = true
		# a visual sim activates the seat once the guest has walked to the chair (seat_taken)
		seated.append({"payload": e["payload"], "left": float(ctx.get("dwell_min", 18.0)), "active": not bool(ctx.get("visual", false))})
		stats["dine_in"] = int(stats["dine_in"]) + 1
	if on_served.is_valid():
		on_served.call(e["payload"], e["item"], float(e["wait"]), dine)

## The guest has sat down: the meal (and the seat timer) starts now.
func seat_taken(payload) -> void:
	for e in seated:
		if e["payload"] == payload:
			e["active"] = true

## Share of the day each stage was busy (seating = average occupancy).
func utilisation() -> Dictionary:
	var out := {}
	for s in _busy:
		out[s] = float(_busy[s]) / maxf(1.0, _total_min)
	return out

## Closing time: everyone still waiting is sent home, diners finish up.
func flush() -> void:
	for e in queue:
		if on_gave_up.is_valid():
			on_gave_up.call(e["payload"], "closing")
	queue.clear()
	for s in backlog:
		for e in backlog[s]:
			_serve(e)
		backlog[s].clear()
	for e in seated:
		if on_left_seat.is_valid():
			on_left_seat.call(e["payload"])
	seated.clear()
