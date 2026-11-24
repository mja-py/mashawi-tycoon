class_name FoodDisplay
extends RefCounted
## The food on show at the stand follows the stock: skewers lose their meat, the bread
## stack sinks, cans leave the counter, the roast thins, the coals go dark. Presentation
## only: it reads levels it is given, never the business RNG, and changes nothing a sale
## depends on. Keys are ingredient ids plus "meat" (the best-stocked grill meat on sale).

const STEPS := 4
## Ingredients the grill skewers stand for.
const GRILL_MEATS := ["chicken", "mutton", "mince"]

var _entries: Array = []      # {key, mode, nodes, base, lift, marker}
var _levels := {}             # key -> 0..STEPS
var _wanted := {}             # keys an on-sale dish needs (only these get a "finished" tag)
## Shrink a piece as it leaves instead of blinking it off. Off without a screen.
var animate := DisplayServer.get_name() != "headless"

## 0..STEPS for `units` left of a `reference` amount; any stock at all shows at least 1.
static func step(units: int, reference: int) -> int:
	if units <= 0:
		return 0
	if reference <= 0:
		return STEPS
	return clampi(ceili(float(STEPS) * float(units) / float(reference)), 1, STEPS)

## Levels for every ingredient from a `units(ingredient) -> int` callable and reference
## amounts, plus the derived "meat" level over the grill meats in `wanted`.
static func levels_for(units: Callable, reference: Dictionary, wanted: Dictionary) -> Dictionary:
	var out := {}
	for ing in reference:
		out[ing] = step(int(units.call(ing)), int(reference[ing]))
	var meat := -1
	for ing in GRILL_MEATS:
		if wanted.has(ing):
			meat = maxi(meat, int(out.get(ing, 0)))
	if meat < 0:
		# nothing grilled is on sale: the skewers show whatever meat there is
		for ing in GRILL_MEATS:
			meat = maxi(meat, int(out.get(ing, 0)))
	out["meat"] = maxi(meat, 0)
	return out

## Ingredients (and "meat") a dish on sale needs today: only these earn a "finished" tag.
static func wanted_today() -> Dictionary:
	var out := {}
	for id in Data.MENU_ITEMS:
		if not Game.is_on_sale(id):
			continue
		var needs := Economy.portion_ingredients(id, Game.menu[id])
		for ing in needs:
			if int(needs[ing]) > 0:
				out[ing] = true
				if ing in GRILL_MEATS and String(Data.MENU_ITEMS[id].get("station_kind", "")) == "grill":
					out["meat"] = true
	return out

## Pieces that leave one by one (meat on a skewer, cans, cups). `anchor` + `lift` place the
## "finished" tag; without an anchor the group gets none.
func add_parts(key: String, nodes: Array, anchor: Node3D = null, lift: float = 0.0) -> void:
	var alive: Array = []
	var base: Array = []
	for n in nodes:
		if n is Node3D:
			alive.append(n)
			base.append((n as Node3D).scale)
	if alive.is_empty():
		return
	_add({"key": key, "mode": "parts", "nodes": alive, "base": base, "anchor": anchor, "lift": lift})

## One prop that sinks as it empties (a bread stack) and is gone at zero.
func add_stack(key: String, node: Node3D, lift: float = -1.0) -> void:
	if node:
		_add({"key": key, "mode": "stack", "nodes": [node], "base": [node.scale], "anchor": node if lift >= 0.0 else null, "lift": maxf(lift, 0.0)})

## One prop that thins around its upright axis (the roast on the spit); `keep` stays (the shaft).
func add_roast(key: String, node: Node3D, anchor: Node3D = null, lift: float = 0.0) -> void:
	if node:
		_add({"key": key, "mode": "roast", "nodes": [node], "base": [node.scale], "anchor": anchor, "lift": lift})

## One prop that is simply there or not (a sauce bottle, a charcoal bag).
func add_single(key: String, node: Node3D, lift: float = -1.0) -> void:
	if node:
		_add({"key": key, "mode": "single", "nodes": [node], "base": [node.scale], "anchor": node if lift >= 0.0 else null, "lift": maxf(lift, 0.0)})

## Glowing coals: a material of its own (never a shared cached one) dims with the charcoal.
func add_glow(key: String, mat: StandardMaterial3D) -> void:
	if mat:
		_add({"key": key, "mode": "glow", "nodes": [], "base": [mat.emission_energy_multiplier], "mat": mat, "lit": mat.albedo_color, "anchor": null, "lift": 0.0})

func _add(entry: Dictionary) -> void:
	entry["marker"] = null
	entry["shown"] = -1
	_entries.append(entry)
	_apply(entry, false)

func keys() -> Dictionary:
	var out := {}
	for e in _entries:
		out[e["key"]] = true
	return out

func level(key: String) -> int:
	return int(_levels.get(key, STEPS))

## Visible pieces of a key (tests): parts still shown, or 1/0 for a whole prop.
func shown(key: String) -> int:
	var n := 0
	for e in _entries:
		if e["key"] != key:
			continue
		for node in e["nodes"]:
			if is_instance_valid(node) and (node as Node3D).visible:
				n += 1
	return n

func marked(key: String) -> bool:
	for e in _entries:
		if e["key"] == key and e["marker"] != null and is_instance_valid(e["marker"]) and (e["marker"] as Node3D).visible:
			return true
	return false

## Drop entries whose props were freed by a rebuild.
func prune() -> void:
	for i in range(_entries.size() - 1, -1, -1):
		var e: Dictionary = _entries[i]
		var dead := false
		for node in e["nodes"]:
			if not is_instance_valid(node) or (node as Node).is_queued_for_deletion():
				dead = true
		if dead:
			if e["marker"] != null and is_instance_valid(e["marker"]):
				(e["marker"] as Node).queue_free()
			_entries.remove_at(i)

## New levels (key -> 0..STEPS) and the keys today's menu needs. Unlisted keys stay as they are.
func set_levels(levels: Dictionary, wanted: Dictionary = {}) -> void:
	_wanted = wanted
	for key in levels:
		_levels[key] = clampi(int(levels[key]), 0, STEPS)
	for e in _entries:
		_apply(e, animate)

func _apply(e: Dictionary, moving: bool) -> void:
	var lv := level(e["key"])
	var was := int(e["shown"])
	e["shown"] = lv
	var nodes: Array = e["nodes"]
	match e["mode"]:
		"parts":
			var keep := ceili(float(nodes.size()) * float(lv) / float(STEPS))
			for i in range(nodes.size()):
				_show(nodes[i], e["base"][i], i < keep, moving and was >= 0)
		"stack":
			var n := nodes[0] as Node3D
			if is_instance_valid(n):
				n.visible = lv > 0
				var b: Vector3 = e["base"][0]
				n.scale = Vector3(b.x, b.y * (0.25 + 0.75 * float(lv) / float(STEPS)), b.z)
		"roast":
			var r := nodes[0] as Node3D
			if is_instance_valid(r):
				r.visible = lv > 0
				var rb: Vector3 = e["base"][0]
				var thin := 0.45 + 0.55 * float(lv) / float(STEPS)
				r.scale = Vector3(rb.x * thin, rb.y, rb.z * thin)
		"single":
			_show(nodes[0], e["base"][0], lv > 0, moving and was >= 0)
		"glow":
			var mat: StandardMaterial3D = e["mat"]
			var heat := float(lv) / float(STEPS)
			mat.emission_energy_multiplier = float(e["base"][0]) * heat
			mat.albedo_color = Color(0.13, 0.11, 0.10).lerp(e["lit"], heat)
	_mark(e, lv == 0 and _wanted.has(e["key"]))

## Show or hide one piece; a piece that leaves shrinks away first.
func _show(node, base: Vector3, on: bool, moving: bool) -> void:
	var n := node as Node3D
	if not is_instance_valid(n):
		return
	if n.has_meta("_food_tween"):
		var old = n.get_meta("_food_tween")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
		n.remove_meta("_food_tween")
	if on or not moving or not n.visible or not n.is_inside_tree():
		n.scale = base
		n.visible = on
		return
	var tw := n.create_tween()
	tw.tween_property(n, "scale", base * 0.05, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		n.visible = false
		n.scale = base)
	n.set_meta("_food_tween", tw)

## The small "finished" tag over an empty prop a dish on the menu needs.
func _mark(e: Dictionary, on: bool) -> void:
	var anchor := e["anchor"] as Node3D
	if anchor == null or not is_instance_valid(anchor):
		return
	var marker := e["marker"] as Sprite3D
	if not on:
		if marker != null and is_instance_valid(marker):
			marker.visible = false
		return
	if marker == null or not is_instance_valid(marker):
		var host := anchor.get_parent() as Node3D
		if host == null:
			return
		# the painted "sold out" tag; the drawn face stands in if the art is missing
		marker = PlotBuilders.painted(host, Vector3.ZERO, "tag", 0.26)
		if marker == null:
			marker = Sprite3D.new()
			marker.texture = Icons.mood_icon("sold_out", 64)
			marker.pixel_size = 0.0021
			marker.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			host.add_child(marker)
		marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		marker.shaded = false
		marker.position = anchor.position + Vector3.UP * float(e["lift"])
		e["marker"] = marker
	marker.visible = true
