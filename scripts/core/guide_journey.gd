class_name GuideJourney
extends RefCounted
## Saveable learning objectives. The mentor observes; only normal game controls act.
const STEPS := ["welcome", "menu", "dish", "recipe", "price", "supplies", "stock", "open", "order", "sale", "finish", "report", "upgrade", "campaign", "goals", "graduate"]

static func fresh() -> Dictionary:
	return {"active": false, "step": 0, "done": false, "completed": false, "started_day": 1, "price": 0.0, "level": 0, "claimed": 0, "station": "counter"}

static func station_for(report: Dictionary) -> String:
	var bottleneck: String = report.get("bottleneck", "counter")
	if bottleneck == "arrivals": return "signage"
	return bottleneck if bottleneck in ["counter", "grill", "karak"] else "counter"

static func clean(value: Variant) -> Dictionary:
	var out := fresh()
	if not value is Dictionary:
		return out
	for key in ["active", "done", "completed"]:
		out[key] = value.get(key, false) == true
	for key in ["step", "started_day", "level", "claimed"]:
		var n: Variant = value.get(key, out[key])
		if (n is int or n is float) and is_finite(float(n)):
			out[key] = clampi(int(n), 0, 100000)
	out["step"] = mini(out["step"], STEPS.size() - 1)
	out["started_day"] = maxi(out["started_day"], 1)
	var price: Variant = value.get("price", 0.0)
	if (price is int or price is float) and is_finite(float(price)):
		out["price"] = clampf(float(price), 0.0, 100000.0)
	var station: Variant = value.get("station", "counter")
	if station in ["counter", "grill", "karak", "signage"]:
		out["station"] = station
	if out["completed"]:
		out["active"] = false
	return out

static func reached(state: Dictionary, view: Dictionary) -> bool:
	var topic: String = STEPS[int(state["step"])]
	match topic:
		"menu": return view["panel"] == "menu"
		"dish": return view["panel"] == "menu" and view["dish"] == "chicken_tikka"
		"recipe": return view["sauce"] == 2
		"price": return not is_equal_approx(float(view["price"]), float(state["price"]))
		"supplies": return view["panel"] == "supplies"
		"stock": return bool(view.get("foodReady", int(view["portions"]) > 0))
		"open": return view["phase"] == "day"
		"order": return view["ordered"] or int(view["served"]) > 0
		"sale": return int(view["served"]) > 0
		"finish": return int(view["day"]) > int(state["started_day"])
		"report": return view["phase"] == "prep" and int(view["day"]) > int(state["started_day"])
		"upgrade": return int(view["level"]) > int(state["level"])
		"campaign": return view["campaign"]
		"goals": return int(view["claimed"]) > int(state["claimed"])
	return false
