@tool
extends EditorDebuggerPlugin
## Die Leitung vom Editor ins laufende Spiel: fragt dort das Skript
## `runtime/probe.gd`, was gerade geladen ist. Der Editor allein weiß nur,
## womit das Spiel gestartet wurde.

const CHANNEL := "tasker"
## So lange wird auf das Spiel gewartet. Steht es an einem Haltepunkt, kommt nichts.
const PATIENCE_MSEC := 1500

var _asked := 0
var _replies := {}


func _has_capture(capture: String) -> bool:
	return capture == CHANNEL


func _capture(message: String, data: Array, _session_id: int) -> bool:
	if message != CHANNEL + ":snapshot" or data.size() < 2:
		return false
	_replies[int(data[0])] = str(data[1])
	return true


## Die Sitzung des Spiels, das gerade läuft – oder null.
func _running() -> EditorDebuggerSession:
	for session in get_sessions():
		if session.is_active():
			return session
	return null


## Was im laufenden Spiel geladen ist, als Text (`Probe.describe`). Leer, wenn
## kein Spiel läuft, es nicht antwortet (Haltepunkt, hängt) oder das Skript
## dort nicht mitläuft.
func snapshot() -> String:
	var session := _running()
	if session == null:
		return ""
	_asked += 1
	var id := _asked
	session.send_message(CHANNEL + ":snapshot", [id])
	var until := Time.get_ticks_msec() + PATIENCE_MSEC
	while not _replies.has(id) and Time.get_ticks_msec() < until:
		await Engine.get_main_loop().process_frame
	var text: String = _replies.get(id, "")
	_replies.erase(id)
	return text


## Ob das laufende Spiel an einem Haltepunkt steht.
func is_breaked() -> bool:
	var session := _running()
	return session != null and session.is_breaked()
