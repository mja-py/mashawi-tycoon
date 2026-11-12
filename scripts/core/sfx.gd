extends Node
## Sound helper: Sfx.play("click"), Sfx.stinger("goal_claimed"), Sfx.play_music("day"),
## Sfx.set_ambience(location_id), Sfx.set_loop("sizzle", true).
## Buses (default_bus_layout.tres): Master > Music, Ambience, SFX. Volumes and mute persist
## like the graphics settings: user://audio.cfg natively, a localStorage key on the web.
## Music, ambience and loops are optional files: a missing one is silently skipped.

const SOUNDS := {
	"click": "click_001", "confirm": "confirmation_001", "buy": "confirmation_002",
	"error": "error_004", "coin": "drop_002", "open": "open_001", "close": "close_001",
	"switch": "switch_001", "tick": "tick_001", "toggle": "toggle_001",
	"bong": "bong_001", "question": "question_001",
	# stinger parts (Kenney Interface Sounds, CC0)
	"rise_low": "maximize_006", "rise_bright": "maximize_009", "sparkle": "confirmation_003",
	"fanfare": "confirmation_004", "chime": "glass_001", "shimmer": "glass_004",
	"chime_hi": "glass_005", "chime_lo": "glass_006", "whoosh_up": "open_002", "cadence": "question_004",
}
## id -> [[sound, delay s, pitch, volume dB], ...]: short layered cues for the big moments.
const STINGERS := {
	"stage_up": [["rise_low", 0.0, 1.0, -4.0], ["confirm", 0.26, 1.0, -3.0], ["fanfare", 0.5, 1.0, -6.0], ["shimmer", 0.62, 1.0, -13.0]],
	"tier_up": [["rise_bright", 0.0, 1.0, -6.0], ["sparkle", 0.14, 1.0, -5.0], ["chime", 0.36, 1.0, -9.0]],
	"goal_claimed": [["fanfare", 0.0, 1.0, -4.0], ["chime_lo", 0.34, 1.0, -8.0], ["chime_hi", 0.44, 1.0, -8.0], ["shimmer", 0.5, 1.0, -14.0]],
	"best_day": [["confirm", 0.0, 1.0, -4.0], ["confirm", 0.2, 1.335, -5.0], ["confirm", 0.4, 1.5, -6.0], ["shimmer", 0.55, 1.0, -12.0]],
	"day_open": [["whoosh_up", 0.0, 1.0, -10.0], ["chime_lo", 0.16, 1.0, -6.0], ["chime_hi", 0.3, 1.0, -6.0]],
	"day_close": [["chime_hi", 0.0, 1.0, -7.0], ["chime_lo", 0.16, 1.0, -7.0], ["cadence", 0.34, 1.0, -8.0]],
}
## Optional audio that is not in the repository yet. Drop the files in and they play.
const MUSIC_PATH := "res://assets/music/%s.ogg"
const AMBIENCE_PATH := "res://assets/sfx/ambience/%s.ogg"
const AMBIENCE_FALLBACK := "street"
const LOOPS := {"sizzle": "res://assets/sfx/loops/grill_sizzle.ogg"}

const BUSES := ["Music", "Ambience", "SFX"]
const DEFAULT_VOLUME := {"Music": 0.6, "Ambience": 0.7, "SFX": 0.9}
const AUDIO_PATH := "user://audio.cfg"
const AUDIO_WEB_KEY := "mashawi_audio"
## The same cue within this many seconds is skipped (a 12x day can sell several times a frame).
const MIN_GAP := 0.05
const FADE := 0.8

var volume: Dictionary = DEFAULT_VOLUME.duplicate()
var muted := false
var music_id := ""
var ambience_id := ""
var _paused := false
var _players: Array[AudioStreamPlayer] = []
var _streams := {}
var _last := {}
var _music: AudioStreamPlayer
var _ambience: AudioStreamPlayer
var _loops := {}
var _fades := {}
var _save_timer: Timer
## Headless runs (tests, autoplayer) have no audio output; playing there only leaves
## playbacks alive at exit.
var _silent := DisplayServer.get_name() == "headless"

func _ready() -> void:
	_ensure_buses()
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_players.append(p)
	_music = _bed("Music")
	_ambience = _bed("Ambience")
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.4
	_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS # a change just before the app hides still saves
	_save_timer.timeout.connect(_save_settings)
	add_child(_save_timer)
	_load_settings()
	_apply()

## Missing layout (or an old one): create the three buses in code, all sending to Master.
func _ensure_buses() -> void:
	for bus in BUSES:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus)
			AudioServer.set_bus_send(idx, "Master")

func _bed(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p

# ---------------------------------------------------------------- one-shots

func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	var stream := _sound(name)
	if stream == null or _silent:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -1.0)) < MIN_GAP:
		return
	_last[name] = now
	var p := _free_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

## A short layered cue (stage built, tier reached, goal, best day, day open/close).
func stinger(id: String) -> void:
	if not STINGERS.has(id) or _silent:
		return
	for part in STINGERS[id]:
		var delay := float(part[1])
		if delay <= 0.0:
			_play_part(part)
		else:
			# Paused with the tree, so a stinger never finishes over a hidden app.
			get_tree().create_timer(delay, false).timeout.connect(_play_part.bind(part))

func _play_part(part: Array) -> void:
	var stream := _sound(part[0])
	if stream == null:
		return
	var p := _free_player(true)
	p.stream = stream
	p.pitch_scale = float(part[2])
	p.volume_db = float(part[3])
	p.play()

func _sound(name: String) -> AudioStream:
	if not SOUNDS.has(name):
		return null
	if not _streams.has(name):
		_streams[name] = _load("res://assets/sfx/%s.ogg" % SOUNDS[name])
	return _streams[name]

## A free player; `steal` takes the one closest to finishing when all are busy.
func _free_player(steal: bool = false) -> AudioStreamPlayer:
	var best: AudioStreamPlayer = null
	var best_left := INF
	for p in _players:
		if not p.playing:
			return p
		if steal and p.stream:
			var left := p.stream.get_length() - p.get_playback_position()
			if left < best_left:
				best_left = left
				best = p
	return best

func _load(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null

# ---------------------------------------------------------------- beds (music, ambience, loops)

## The game ships without music (a light street soundscape only); a track dropped into
## assets/music brings the Music volume control back.
func has_music() -> bool:
	for id in ["title", "prep", "day"]:
		if ResourceLoader.exists(MUSIC_PATH % id):
			return true
	return false

## Title / prep / day music. Does nothing (and fades the old track out) when the file is missing.
func play_music(id: String) -> void:
	if id == music_id:
		return
	music_id = id
	_crossfade(_music, _looping(MUSIC_PATH % id) if id != "" else null)

## District street sound for a location id; falls back to a shared street bed.
func set_ambience(location_id: String) -> void:
	if location_id == ambience_id:
		return
	ambience_id = location_id
	var stream: AudioStream = null
	if location_id != "":
		stream = _looping(AMBIENCE_PATH % location_id)
		if stream == null:
			stream = _looping(AMBIENCE_PATH % AMBIENCE_FALLBACK)
	_crossfade(_ambience, stream)

## Named loops (the grill sizzle) on the Ambience bus.
func set_loop(id: String, on: bool) -> void:
	if not LOOPS.has(id):
		return
	var p: AudioStreamPlayer = _loops.get(id)
	if not on:
		if p and p.playing:
			_crossfade(p, null)
		return
	if p == null:
		var stream := _looping(LOOPS[id])
		if stream == null:
			return
		p = _bed("Ambience")
		p.stream = stream
		_loops[id] = p
	if not p.playing:
		_crossfade(p, p.stream)

func _looping(path: String) -> AudioStream:
	var stream := _load(path)
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	return stream

func _crossfade(p: AudioStreamPlayer, stream: AudioStream) -> void:
	if (stream == null and not p.playing) or _silent:
		return
	var old: Tween = _fades.get(p)
	if old:
		old.kill()
	var tw := p.create_tween()
	_fades[p] = tw
	if p.playing:
		tw.tween_property(p, "volume_db", -40.0, FADE * 0.5)
		tw.tween_callback(p.stop)
	if stream == null:
		tw.tween_callback(_publish_beds)
		return
	tw.tween_callback(func():
		p.stream = stream
		p.volume_db = -40.0
		p.play()
		_publish_beds())
	tw.tween_property(p, "volume_db", 0.0, FADE)

## Web: which beds are really playing (window.godotAudio), for the browser tests.
func _publish_beds() -> void:
	if not OS.has_feature("web"):
		return
	var sizzle: AudioStreamPlayer = _loops.get("sizzle")
	JavaScriptBridge.eval("window.godotAudio = {music: '%s', ambience: '%s', sizzle: %s}" % [
		music_id if _music.playing else "", ambience_id if _ambience.playing else "",
		"true" if sizzle and sizzle.playing else "false"])

# ---------------------------------------------------------------- settings

func set_volume(bus: String, value: float) -> void:
	if not BUSES.has(bus):
		return
	volume[bus] = clampf(value, 0.0, 1.0)
	_apply()
	_save_timer.start()

func set_muted(on: bool) -> void:
	muted = on
	_apply()
	_save_timer.start()

func _apply() -> void:
	for bus in BUSES:
		var idx := AudioServer.get_bus_index(bus)
		if idx == -1:
			continue
		var v := float(volume.get(bus, 1.0))
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)
	# The web shell pauses the tree when the app is hidden or held in portrait.
	AudioServer.set_bus_mute(0, muted or _paused)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_paused = what == NOTIFICATION_PAUSED
		_apply()
	elif what == NOTIFICATION_EXIT_TREE:
		# Release live playbacks so quitting mid-sound does not leak them.
		for p in get_children():
			if p is AudioStreamPlayer:
				p.stop()
				p.stream = null

func _save_settings() -> void:
	var prefs := {"muted": muted}
	for bus in BUSES:
		prefs[bus.to_lower()] = snappedf(float(volume[bus]), 0.01)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("try { localStorage.setItem('%s', JSON.stringify(%s)); } catch (_) {}" % [AUDIO_WEB_KEY, JSON.stringify(prefs)])
	else:
		var config := ConfigFile.new()
		for key in prefs:
			config.set_value("audio", key, prefs[key])
		config.save(AUDIO_PATH)

func _load_settings() -> void:
	var prefs: Variant = {}
	if OS.has_feature("web"):
		var saved: Variant = JavaScriptBridge.eval("try { localStorage.getItem('%s') || ''; } catch (_) { ''; }" % AUDIO_WEB_KEY)
		if saved is String and not saved.is_empty():
			prefs = JSON.parse_string(saved)
	else:
		var config := ConfigFile.new()
		if config.load(AUDIO_PATH) == OK and config.has_section("audio"):
			prefs = {}
			for key in config.get_section_keys("audio"):
				prefs[key] = config.get_value("audio", key)
	if not prefs is Dictionary:
		return
	if prefs.get("muted") is bool:
		muted = prefs["muted"]
	for bus in BUSES:
		var v: Variant = prefs.get(bus.to_lower())
		if (v is float or v is int) and is_finite(float(v)):
			volume[bus] = clampf(float(v), 0.0, 1.0)
