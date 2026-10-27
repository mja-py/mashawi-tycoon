extends Node
## Tiny sound helper: Sfx.play("click").

const SOUNDS := {
	"click": "click_001", "confirm": "confirmation_001", "buy": "confirmation_002",
	"error": "error_004", "coin": "drop_002", "open": "open_001", "close": "close_001",
	"switch": "switch_001", "tick": "tick_001", "toggle": "toggle_001",
	"bong": "bong_001", "question": "question_001",
}
var _players: Array[AudioStreamPlayer] = []
var _streams := {}

func _ready() -> void:
	for i in range(6):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)

func play(name: String, volume_db: float = -6.0, pitch: float = 1.0) -> void:
	if not SOUNDS.has(name):
		return
	if not _streams.has(name):
		var path := "res://assets/sfx/%s.ogg" % SOUNDS[name]
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	var stream: AudioStream = _streams[name]
	if stream == null:
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.pitch_scale = pitch
			p.play()
			return
