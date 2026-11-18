class_name Advisor
## The built-in advisor: reads the player's own history, forecast and stand and says, in
## plain numbers, what to do next. Pure and offline: it never buys, edits or rolls dice.
##
## An insight is {id, mood, text, gain, panel, detail, dish}:
##   mood   a face for `Icons.mood_icon` (great / ok / bad / pricey / slow / sold_out / full / rival)
##   text   the translated sentence, numbers filled in
##   gain   the estimated AED per day it is worth (0 when it cannot be priced); sorts the list
##   panel / detail / dish   where the "Show me" button goes in the prep menus

const REPORT_TOP := 3
const SHEET_TOP := 6
## A loss reason must cost at least this many guests before it is worth a line.
const MIN_LOST := 2
## Order of the list: a reward waiting, then yesterday's losses, then what to buy, then the
## weather, then observations. Within a group the larger estimated gain comes first.
const PRIORITY := {"goal_ready": 0,
	"sold_out": 1, "line": 1, "crowd": 1, "pricey": 1, "no_item": 1, "spoil": 1, "rival": 1, "raise": 1,
	"buy": 2, "save": 2, "move": 2, "promo": 2, "stage_at": 2,
	"hot": 3, "sandstorm": 3, "breeze": 3}
## Insights whose `gain` is a one-off or only a sorting weight: no "about +AED n a day" line.
const NO_DAILY := ["save", "stage_at", "goal_ready", "goal_near", "trend_down", "trend_up", "quiet", "opening", "dead_dish", "hot", "sandstorm", "breeze", "clean", "start"]

static func _t(key: String) -> String:
	return TranslationServer.translate(key)

static func _money(v: float) -> String:
	return Loc.money(roundf(v))

static func _insight(id: String, mood: String, text: String, gain: float = 0.0, panel: String = "", detail: String = "", dish: String = "") -> Dictionary:
	return {"id": id, "mood": mood, "text": text, "gain": gain, "panel": panel, "detail": detail, "dish": dish,
		"prio": int(PRIORITY.get(id, 4)), "daily": not NO_DAILY.has(id)}

## What one more served guest earned on the day `r` (falls back to a modest figure).
static func _margin(r: Dictionary) -> float:
	var served := int(r.get("served", 0))
	if served <= 0:
		return 5.0
	return maxf(1.0, (float(r.get("revenue", 0.0)) - float(r.get("cogs", 0.0))) / served)

## The three things most worth doing after the day `r` (a history row).
static func for_report(r: Dictionary) -> Array[Dictionary]:
	var out := _day_insights(r)
	out.append_array(_buy_insights(r))
	if out.is_empty():
		out.append(_insight("clean", "great", _t("adv.clean")))
	return _top(out, REPORT_TOP)

## Everything the advice depends on. The ranking behind it runs dozens of estimates, so the
## strip, the sheet and the report share one answer until this changes.
static var _memo := {}

static func _state_key() -> int:
	return [Game.day, Game.history.size(), Game.location, Game.forecast, Game.goal_index, roundi(Game.money),
		Game.rig, Game.plots, Game.menu, Game.marketing, TranslationServer.get_locale()].hash()

static func _ranked() -> Dictionary:
	var key := _state_key()
	if int(_memo.get("rank_key", 0)) != key or not _memo.has("rank"):
		_memo["rank_key"] = key
		_memo["rank"] = Autoplayer.rank([], null, true)
	return _memo["rank"]

## The planning sheet: yesterday's lessons, tomorrow's weather, goals and the best buy.
static func for_prep() -> Array[Dictionary]:
	var key := _state_key()
	if int(_memo.get("prep_key", 0)) == key and _memo.has("prep"):
		return _memo["prep"]
	var prep := _for_prep()
	_memo["prep_key"] = key
	_memo["prep"] = prep
	return prep

static func _for_prep() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var last: Dictionary = Game.history.back() if not Game.history.is_empty() else {}
	if not last.is_empty():
		out.append_array(_day_insights(last))
	out.append_array(_buy_insights(last))
	out.append_array(_forecast_insights())
	out.append_array(_goal_insights())
	out.append_array(_opening_insights())
	if out.is_empty():
		out.append(_insight("start", "great", _t("adv.start")))
	return _top(out, SHEET_TOP)

## One line for the strip above the planning screen.
static func headline() -> Dictionary:
	var all := for_prep()
	return all[0] if not all.is_empty() else {}

static func _top(list: Array[Dictionary], n: int) -> Array[Dictionary]:
	var seen := {}
	var unique: Array[Dictionary] = []
	for it in list:
		if not seen.has(it["id"]):
			seen[it["id"]] = true
			unique.append(it)
	unique.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["prio"]) != int(b["prio"]):
			return int(a["prio"]) < int(b["prio"])
		return float(a["gain"]) > float(b["gain"]))
	# Losses never crowd out the purchase advice: keep a place for one thing to buy.
	var buys := unique.filter(func(it: Dictionary) -> bool: return int(it["prio"]) == 2)
	var out: Array[Dictionary] = []
	for it in unique:
		var room_for_buy := 1 if not buys.is_empty() and not out.any(func(o: Dictionary) -> bool: return int(o["prio"]) == 2) else 0
		if int(it["prio"]) != 2 and out.size() >= n - room_for_buy:
			continue
		if out.size() < n:
			out.append(it)
	return out

# ------------------------------------------------------------------ the day's losses

static func _day_insights(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var served := int(r.get("served", 0))
	var margin := _margin(r)
	var sold_out := int(r.get("sold_out", 0))
	if sold_out >= MIN_LOST:
		out.append(_insight("sold_out", "sold_out", _t("adv.sold_out") % sold_out, sold_out * margin, "supplies"))
	var line := int(r.get("left_wait", 0)) + int(r.get("queue_full", 0))
	var bottleneck := String(r.get("bottleneck", ""))
	if line >= MIN_LOST or (bottleneck != "" and bottleneck != "arrivals"):
		# Yesterday's bottleneck may be a station this stand does not have (after a move).
		var station := bottleneck if Data.STATIONS.has(bottleneck) and (Game.stage_def()["stations"] as Array).has(bottleneck) else "counter"
		var text := (_t("adv.line") % [line, _t(Data.STATIONS[station]["name"])]) if line > 0 \
			else (_t("adv.busy") % _t(Data.STATIONS[station]["name"]))
		out.append(_insight("line", "slow", text, maxf(line, 2) * margin, "build", station))
	var crowd := int(r.get("crowd", 0))
	if crowd >= 3:
		var bigger := Game.next_stage_def()
		if bigger.is_empty() or bigger.get("later", false):
			# the largest stand already: the counter's tier is what makes room for more buyers
			out.append(_insight("crowd", "full", _t("adv.crowd_counter") % crowd, crowd * margin * 0.6, "build", "counter"))
		else:
			out.append(_insight("crowd", "full", _t("adv.crowd") % crowd, crowd * margin * 0.6, "build", "stage"))
	var pricey := int(r.get("too_pricey", 0))
	if pricey >= MIN_LOST:
		var dish := _priciest_dish()
		if dish != "":
			out.append(_insight("pricey", "pricey", _t("adv.pricey") % [pricey, _t(Data.MENU_ITEMS[dish]["name"])], pricey * margin * 0.7, "menu", "", dish))
	var extras := _missing_extras(r)
	if not extras.is_empty():
		out.append(extras)
	var spoiled := float(r.get("spoil_cost", 0.0))
	if spoiled >= 8.0 and spoiled >= 0.12 * float(r.get("cogs", 0.0)):
		var has_box := Game.station_level("coldbox") > 0
		out.append(_insight("spoil", "bad", _t("adv.spoil_box" if has_box else "adv.spoil") % _money(spoiled), spoiled * 0.6,
			"supplies" if has_box else "build", "" if has_box else "coldbox"))
	var rivals := int(r.get("lost_rival", 0))
	if rivals >= 3:
		out.append(_insight("rival", "rival", _t("adv.rival") % rivals, rivals * margin * 0.5, "promote"))
	# Demand is the limit: nobody was turned away, the stand was simply quiet.
	var passers := int(r.get("passers", 0))
	if bottleneck == "arrivals" and line + crowd + sold_out == 0 and passers > 0:
		out.append(_insight("quiet", "ok", _t("adv.quiet") % [served, passers], 0.5))
	# Room to charge more: guests were delighted, nobody complained about price.
	if served >= 6 and float(r.get("satisfaction", 0.0)) >= 0.75 and pricey == 0:
		var raise := _raise_candidate()
		if not raise.is_empty():
			out.append(_insight("raise", "great", _t("adv.raise") % [roundi(float(r["satisfaction"]) * 100.0), _t(Data.MENU_ITEMS[raise["dish"]]["name"]), _money(raise["price"])],
				float(raise["gain"]), "menu", "", raise["dish"]))
	out.append_array(_trend_insights(r))
	return out

## The dish on sale whose price is furthest above its base (the likeliest "too pricey").
## When several share the top ratio (one multiplier on the whole menu), the food dish that
## sells most is the one the complaints are about.
static func _priciest_dish() -> String:
	var last: Dictionary = Game.history.back() if not Game.history.is_empty() else {}
	var sold: Dictionary = last.get("sold", {})
	var best := ""
	var best_key := [1.001, 0, 0]
	for id in Data.MENU_ITEMS:
		if not Game.is_on_sale(id):
			continue
		var ratio := snappedf(float(Game.menu[id]["price"]) / float(Data.MENU_ITEMS[id]["base_price"]), 0.01)
		var key := [ratio, 1 if Data.MENU_ITEMS[id]["kind"] == "food" else 0, int(sold.get(id, 0))]
		if key > best_key:
			best_key = key
			best = id
	return best

## Extras guests asked for with their order (a side, a drink, a sweet) that the stand had none
## of on sale, from the day's own count by kind. One wish is one lost add-on, valued at that
## kind's usual margin; "Show me" goes to the dish to switch on, or the station that unlocks it.
static func _missing_extras(r: Dictionary) -> Dictionary:
	var kinds: Dictionary = r.get("no_item_kinds", {})
	var kind := ""
	for k in kinds:
		if int(kinds[k]) >= 3 and (kind == "" or int(kinds[k]) > int(kinds[kind])):
			kind = String(k)
	if kind == "":
		return {}
	var n := int(kinds[kind])
	var label := kind
	for group in Data.MENU_GROUPS:
		if String(group[0]) == kind:
			label = _t(group[1])
	var price := 0.0
	var count := 0
	var dish := ""
	var station := ""
	for id in Data.MENU_ITEMS:
		var def: Dictionary = Data.MENU_ITEMS[id]
		if String(def["kind"]) != kind:
			continue
		price += float(def["base_price"])
		count += 1
		if Game.is_on_sale(id):
			return {} # the menu has changed since: one is on sale now
		if dish == "" and Game.item_available(id):
			dish = id
		var need := Game.required_station(def)
		if station == "" and need != "" and (Game.stage_def()["stations"] as Array).has(need) and Game.station_level(need) == 0:
			station = need
	var worth := n * (price / maxi(count, 1)) * 0.55
	if dish != "":
		return _insight("no_item", "bad", _t("adv.no_item") % [n, label], worth, "menu", "", dish)
	if station != "":
		return _insight("no_item", "bad", _t("adv.no_item_station") % [n, label, _t(Data.STATIONS[station]["name"])], worth, "build", station)
	return {}

## The best-selling dish that can still go up one dirham, if the estimate agrees that this
## one dish at +1, the rest of the menu untouched, earns more than today's prices.
static func _raise_candidate() -> Dictionary:
	var last: Dictionary = Game.history.back() if not Game.history.is_empty() else {}
	var sold: Dictionary = last.get("sold", {})
	var dish := ""
	var most := 0
	for id in sold:
		if Data.MENU_ITEMS.has(id) and Game.is_on_sale(id) and int(sold[id]) > most:
			var top := float(Game.price_range(id)[1])
			if float(Game.menu[id]["price"]) + 0.99 <= top:
				most = int(sold[id])
				dish = id
	if dish == "":
		return {}
	var price := float(Game.menu[dish]["price"]) + 1.0
	var now := float(Economy.throughput_estimate(Game.sim_context())["profit"])
	var up := float(Economy.throughput_estimate(Game.what_if({"prices": {dish: price}}))["profit"])
	if up <= now + 1.0:
		return {}
	return {"dish": dish, "price": price, "gain": up - now}

# ------------------------------------------------------------------ trends

static func _trend_insights(r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var h: Array = Game.history
	if h.size() < 4:
		return out
	# Profit, last three days against the three before.
	if h.size() >= 6:
		var recent := 0.0
		var before := 0.0
		for i in range(3):
			recent += float(h[h.size() - 1 - i].get("profit", 0.0))
			before += float(h[h.size() - 4 - i].get("profit", 0.0))
		if absf(before) > 30.0:
			var change := (recent - before) / absf(before)
			if change <= -0.25:
				out.append(_insight("trend_down", "bad", _t("adv.trend_down") % roundi(-change * 100.0), absf(recent - before) / 3.0 * 0.3))
			elif change >= 0.25:
				out.append(_insight("trend_up", "great", _t("adv.trend_up") % roundi(change * 100.0), 0.2))
	# A dish on the menu that nobody has ordered for five days.
	var window := mini(5, h.size())
	var counts := {}
	for i in range(window):
		var sold: Dictionary = h[h.size() - 1 - i].get("sold", {})
		for id in sold:
			counts[id] = int(counts.get(id, 0)) + int(sold[id])
	if window >= 5:
		for id in Data.MENU_ITEMS:
			# on sale on each of those days (rows record the prices charged), not just today
			var offered := true
			for i in range(window):
				if not (h[h.size() - 1 - i].get("prices", {}) as Dictionary).has(id):
					offered = false
			if offered and Game.is_on_sale(id) and int(counts.get(id, 0)) == 0:
				out.append(_insight("dead_dish", "ok", _t("adv.dead_dish") % _t(Data.MENU_ITEMS[id]["name"]), 2.0, "menu", "", id))
				break
	# The best place so far (needs two days in at least two places).
	var by_place := {}
	for row in h:
		var loc := String(row.get("location", ""))
		if not by_place.has(loc):
			by_place[loc] = [0.0, 0]
		by_place[loc][0] += float(row.get("profit", 0.0))
		by_place[loc][1] += 1
	var here := String(r.get("location", Game.location))
	var best_loc := ""
	var best_avg := -INF
	for loc in by_place:
		if int(by_place[loc][1]) >= 2:
			var avg: float = by_place[loc][0] / by_place[loc][1]
			if avg > best_avg:
				best_avg = avg
				best_loc = loc
	if best_loc != "" and best_loc != here and by_place.has(here) and int(by_place[here][1]) >= 2:
		var here_avg: float = by_place[here][0] / by_place[here][1]
		if best_avg > here_avg * 1.2 + 10.0 and Data.LOCATIONS.has(best_loc):
			out.append(_insight("best_place", "ok", _t("adv.best_place") % [_t(Data.LOCATIONS[best_loc]["name"]), _money(best_avg), _money(here_avg)],
				best_avg - here_avg, "place"))
	return out

## Seven-day figures for the sheet's Trends block: {days, served[], profit[], happy[], best_dish, best_count, share}.
static func trends(days: int = 14) -> Dictionary:
	var h: Array = Game.history
	var from := maxi(0, h.size() - days)
	var served: Array[float] = []
	var profit: Array[float] = []
	var happy: Array[float] = []
	var counts := {}
	var plates := 0
	for i in range(from, h.size()):
		var row: Dictionary = h[i]
		served.append(float(row.get("served", 0)))
		profit.append(float(row.get("profit", 0.0)))
		happy.append(float(row.get("satisfaction", 0.0)))
		var sold: Dictionary = row.get("sold", {})
		for id in sold:
			counts[id] = int(counts.get(id, 0)) + int(sold[id])
			plates += int(sold[id])
	var best := ""
	for id in counts:
		if best == "" or int(counts[id]) > int(counts[best]):
			best = id
	return {"days": h.size() - from, "served": served, "profit": profit, "happy": happy, "best_dish": best,
		"best_count": int(counts.get(best, 0)), "share": (float(counts.get(best, 0)) / plates) if plates > 0 else 0.0}

# ------------------------------------------------------------------ what to buy, weather, goals

## The purchase that pays back fastest, priced by the same scoring the balance bot uses
## (`Autoplayer.rank` is side-effect free). One thing to buy now, and one worth saving for
## when it beats everything affordable.
static func _buy_insights(_r: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ranked := _ranked()
	var buy := {}
	var save := {}
	for c in ranked["cands"]:
		if not bool(c["ok"]) or float(c["gain"]) <= 0.5 or float(c["net"]) <= 0.0:
			continue
		if bool(c["affordable"]):
			if buy.is_empty() or float(c["score"]) > float(buy["score"]):
				buy = c
		elif save.is_empty() or float(c["score"]) > float(save["score"]):
			save = c
	if not buy.is_empty():
		out.append(_purchase(buy, true, float(ranked["buffer"])))
	if not save.is_empty() and (buy.is_empty() or float(save["score"]) > float(buy["score"])):
		out.append(_purchase(save, false, float(ranked["buffer"])))
	return out

static func _purchase(c: Dictionary, now: bool, buffer: float) -> Dictionary:
	var kind := String(c["kind"])
	var id := String(c["id"])
	var gain := float(c["gain"])
	var name := id
	var panel := "build"
	var detail := ""
	var dish := ""
	match kind:
		"station":
			name = "%s %d" % [_t(Data.STATIONS[id]["name"]) if Data.STATIONS.has(id) else _t("station.seating"), Game.station_level(id) + 1]
			detail = id
		"stage":
			name = _t(Data.stage_def(Data.stage_tier_of(id))["name"])
			detail = "stage"
			var where := String(c.get("where", ""))
			if where != "" and where != Game.location and Data.LOCATIONS.has(where):
				# the plot would pay best somewhere else: say where, and send the player there
				return _insight("stage_at", "ok", _t("adv.stage_at") % [name, _t(Data.LOCATIONS[where]["name"]), _money(gain)], gain * 0.5, "place")
		"item":
			name = _t(Data.MENU_ITEMS[id]["name"])
			panel = "menu"
			dish = id
		"enhance":
			name = _t(Data.MENU_ITEMS[id]["enhance"][int(Game.menu[id]["level"])]["name"])
			panel = "menu"
			dish = id
		"move":
			return _insight("move", "ok", _t("adv.move") % [_t(Data.LOCATIONS[id]["name"]), _money(gain)], gain, "place")
		"promo":
			var preview := Game.promo_preview(id)
			return _insight("promo", "great", _t("adv.promo") % [_t(Data.MARKETING[id]["name"]), maxi(1, roundi(float(preview["extra_buyers_per_day"]))), _money(float(preview["net"]))],
				float(preview["net"]) / maxf(1.0, float(preview["days"])), "promote", id)
	if now:
		return _insight("buy", "great", _t("adv.buy") % [name, _money(gain), maxi(1, ceili(float(c["payback"])))], gain, panel, detail, dish)
	# a stage's candidate price includes a few tables; the card shows the stage's own price
	var price := float(Game.next_stage_def().get("cost", c["cost"])) if kind == "stage" else float(c["cost"])
	var short := maxf(1.0, price - (Game.money - buffer))
	return _insight("save", "ok", _t("adv.save") % [name, _money(short), _money(gain)], gain * 0.5, panel, detail, dish)

## The station the guide points a new player at: the best-paying affordable level, or the
## one that held the day back.
static func best_station(fallback: String) -> String:
	var best := ""
	var score := 0.0
	for c in _ranked()["cands"]:
		if String(c["kind"]) == "station" and bool(c["affordable"]) and float(c["gain"]) > 0.0 and float(c["score"]) > score \
				and (Game.stage_def()["stations"] as Array).has(String(c["id"])):
			score = float(c["score"])
			best = String(c["id"])
	return best if best != "" else fallback

static func _forecast_insights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	match Game.forecast:
		"hot":
			var drinks := false
			for id in Data.MENU_ITEMS:
				if Data.MENU_ITEMS[id]["kind"] == "drink" and Game.is_on_sale(id):
					drinks = true
			out.append(_insight("hot", "ok", _t("adv.hot" if drinks else "adv.hot_none"), 6.0, "supplies" if drinks else "menu"))
		"sandstorm":
			out.append(_insight("sandstorm", "bad", _t("adv.sandstorm"), 5.0, "supplies"))
		"breeze":
			out.append(_insight("breeze", "great", _t("adv.breeze"), 4.0, "supplies"))
	return out

static func _goal_insights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var goal := Game.current_goal()
	if goal.is_empty():
		return out
	var reward := float(goal.get("reward", {}).get("money", 0.0))
	if Game.goal_ready():
		out.append(_insight("goal_ready", "great", _t("adv.goal_ready") % _money(reward), reward, "goals"))
	elif Game.goal_progress() >= 0.7:
		out.append(_insight("goal_near", "ok", _t("adv.goal_near") % [roundi(Game.goal_progress() * 100.0), _money(reward)], reward * 0.1, "goals"))
	return out

## The opening crowd is temporary: say so before it fades.
static func _opening_insights() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var left := int(Data.OPENING["days"]) - Game.day + 1
	if Game.opening_boost() > 1.05 and left <= 5 and left >= 1:
		out.append(_insight("opening", "ok", _t("adv.opening") % left, 3.0))
	return out
