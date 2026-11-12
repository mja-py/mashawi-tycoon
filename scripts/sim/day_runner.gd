class_name DayRunner
extends RefCounted
## Plays one real business day (DaySim: the walkers, queue, counter, kitchen, seats and
## staff a player watches) without drawing it, for balance runs and tests. The ticks are
## the same ones the visible day consumes, so the result is the day a player would get.

## A day is 7,200 ticks; closing service adds a little. This only stops a broken day.
const MAX_TICKS := 60 * 60 * 10
const PRUNE_EVERY := 120

## The caller builds the street first (`world.set_location`) and gives finished guests a
## frame to leave the tree between days (`await get_tree().process_frame`).
static func play(sim: DaySim, world: World, ctx: Dictionary) -> Dictionary:
	sim.process_mode = Node.PROCESS_MODE_DISABLED
	world.process_mode = Node.PROCESS_MODE_DISABLED
	sim.start(ctx, world)
	var ticks := 0
	while sim.running and ticks < MAX_TICKS:
		sim.advance_tick()
		ticks += 1
		if ticks % PRUNE_EVERY == 0:
			world.prune_guests()
	world.prune_guests()
	var stats := sim.stats.duplicate(true)
	stats["_ticks"] = ticks
	stats["_unfinished"] = sim.running
	return stats
