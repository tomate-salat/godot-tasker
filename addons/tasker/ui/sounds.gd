@tool
extends Node
## Die Töne des Tischs. Sie werden beim ersten Gebrauch errechnet – das Addon
## bringt keine Tondateien mit.

const RATE := 22050
const VOLUME_DB := -14.0

## Abschaltbar in den Editor-Einstellungen (`tasker/sound`).
var enabled := true

var _streams := {}
var _players: Array = []
var _next := 0


func _ready() -> void:
	for i in 4:
		var player := AudioStreamPlayer.new()
		player.volume_db = VOLUME_DB
		add_child(player)
		_players.append(player)


## Spielt einen Ton: "draw", "play", "done", "refuse", "unlock", "goal" oder "complete".
func play(name: String) -> void:
	if not enabled or _players.is_empty():
		return
	if not _streams.has(name):
		_streams[name] = _make(name)
	var stream: AudioStream = _streams[name]
	if stream == null:
		return
	var player: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.play()


func _make(name: String) -> AudioStream:
	match name:
		"draw":
			# Eine Karte gleitet vom Stapel: ein kurzes Rauschen, das ausklingt.
			return _wav(_noise(0.09, 0.5, 9.0))
		"play":
			# Die Karte landet: ein dumpfer Schlag mit einem Hauch Rauschen.
			return _wav(_mix(_tone(120.0, 0.13, 0.9, 22.0), _noise(0.05, 0.25, 30.0)))
		"done":
			return _wav(_sequence([[660.0, 0.09], [880.0, 0.22]], 0.5, 9.0))
		"refuse":
			return _wav(_mix(_tone(150.0, 0.14, 0.5, 14.0), _tone(157.0, 0.14, 0.4, 14.0)))
		"unlock":
			# Die Kette springt: zwei helle, verstimmte Schläge.
			return _wav(_mix(_tone(1320.0, 0.3, 0.35, 10.0), _mix(_tone(1975.0, 0.3, 0.25, 12.0), _noise(0.04, 0.3, 40.0))))
		"goal":
			return _wav(_sequence([[523.0, 0.09], [659.0, 0.09], [784.0, 0.09], [1047.0, 0.3]], 0.5, 6.0))
		"complete":
			return _wav(_sequence([[392.0, 0.11], [523.0, 0.11], [659.0, 0.11], [784.0, 0.11], [1047.0, 0.5]], 0.55, 4.0))
	return null


## Ein Sinuston, der ausklingt.
func _tone(freq: float, seconds: float, gain: float, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(seconds * RATE)
	out.resize(n)
	for i in n:
		var t := float(i) / RATE
		out[i] = sin(TAU * freq * t) * gain * exp(-decay * t) * minf(1.0, i / 60.0)
	return out


func _noise(seconds: float, gain: float, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := int(seconds * RATE)
	out.resize(n)
	var last := 0.0
	for i in n:
		var t := float(i) / RATE
		# Leicht geglättet, damit es nach Papier klingt und nicht nach Zischen.
		last = lerpf(last, randf_range(-1.0, 1.0), 0.45)
		out[i] = last * gain * exp(-decay * t)
	return out


## Mehrere Töne nacheinander: `[[Frequenz, Dauer], …]`.
func _sequence(notes: Array, gain: float, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for note in notes:
		out.append_array(_tone(note[0], note[1], gain, decay))
	return out


func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i in out.size():
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	return wav
