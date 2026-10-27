extends Node
## Command line switches for automated runs, e.g.
##   godot --path . -- --phase=day --location=creek --weather=sandstorm --screenshot=/tmp/day.png --delay=4
##   godot --headless --path . -- --autodays=30
var flags: Dictionary = {}

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg).trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			flags[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			flags[a] = "1"

func has(flag: String) -> bool:
	return flags.has(flag)

func get_flag(flag: String, default: String = "") -> String:
	return String(flags.get(flag, default))

func screenshot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[DevTools] screenshot saved to ", path)
