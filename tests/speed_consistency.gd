extends SceneTree
## Godot --headless --path . --script tests/speed_consistency.gd
## Replay identical business days at 1x, 2x, 4x and Skip, at both phone frame caps.
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var game := root.get_node("Game")
	var data := root.get_node("Data")
	game.persist = false
	root.get_node("DevTools").flags["uitest"] = "1"
	var results := []
	var references := {}
	var failures := 0
	for tier in [0, 4]:
		for sample in [27, 42, 73]:
			for mode in [[1,60],[2,60],[4,60],[12,60],[1,30],[2,30],[4,30],[12,30]]:
				var speed: int = mode[0]
				var fps: int = mode[1]
				seed(sample)
				game.new_game()
				game.money = 100000.0
				game.popularity = 0.9
				game.weather = "sunny"
				game.forecast = "sunny"
				if tier == 4:
					game.rig["stage"] = "truck"
					game.plot()["stage"] = "restaurant"
					game.plot()["stations"] = {"counter": 7, "grill": 7, "karak": 4, "seating": 4, "staffroom": 1}
				else:
					game.rig["stations"] = {"counter": 7, "grill": 7, "karak": 4}
				for id in data.INGREDIENTS:
					game.inventory[id] = 120
				for id in data.MENU_ITEMS:
					game.menu[id]["enabled"] = id in ["chicken_tikka", "soda"]
				game.menu["chicken_tikka"]["level"] = 3
				var world: Node3D = load("res://scripts/world/world.gd").new()
				root.add_child(world)
				world.process_mode = Node.PROCESS_MODE_DISABLED
				world.set_location(game.location)
				var sim: Node = load("res://scripts/sim/day_sim.gd").new()
				root.add_child(sim)
				sim.process_mode = Node.PROCESS_MODE_DISABLED
				sim.start(game.sim_context(), world)
				sim._rng.seed = sample
				if speed == 12:
					sim.finish_quickly()
				var frame := 0
				sim.set_playback_speed(float(speed))
				while sim.running and frame < 36000:
					sim._process(1.0 / float(fps))
					for child in world._level.get_children():
						if child.has_method("go_to_slot") and child.state == 7:
							child.free()
					frame += 1
				var report: Dictionary = game.end_day(sim.stats)
				var row := {"stage":tier,"fps":fps,"seed":sample,"speed":"skip" if speed == 12 else str(speed),"seconds":snappedf(frame / float(fps),0.01),"served":sim.stats["served"],"passers":sim.stats["passers"],"profit":report["profit"],"dineIn":sim.stats["dine_in"]}
				var signature := {"served": sim.stats["served"], "passers": sim.stats["passers"], "profit": report["profit"],
					"dineIn": sim.stats["dine_in"], "revenue": sim.stats["revenue"], "sold": sim.stats["sold"],
					"inventory": game.inventory.duplicate()}
				var key := str(tier) + ":" + str(sample)
				if not references.has(key):
					references[key] = signature
				if sim.running or signature != references[key] or sim.purchase_log.size() != int(sim.stats["served"]):
					failures += 1
					printerr("FAIL speed consistency ", row)
				for purchase in sim.purchase_log:
					if not purchase["visible"] or not purchase["ordered"]:
						failures += 1
						printerr("FAIL invisible purchase ", row)
				results.append(row)
				print(JSON.stringify(row))
				sim.free()
				world.free()
	var file := FileAccess.open("user://speed-consistency.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(results,"\t"))
	print("speed consistency: ", results.size(), " replays, ", failures, " failed")
	quit(1 if failures else 0)
