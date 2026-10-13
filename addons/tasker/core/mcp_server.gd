@tool
extends Node
## Der MCP-Server des Addons: hört auf diesem Rechner auf einem Port und reicht
## jede Anfrage an `handler` weiter. Was gesprochen wird, steht in `rules/mcp.gd`.
##
## Er hört nur auf 127.0.0.1 und nur mit Kennwort. Gearbeitet wird im
## Hauptfaden, Bild für Bild – die Werkzeuge fassen den Editor an.

const Mcp := preload("../rules/mcp.gd")

## Eine Verbindung, die so lange nichts Ganzes schickt, wird geschlossen.
const PATIENCE_MSEC := 10_000
const ROUTE := "/mcp"

## `handler(body: String) -> String`: beantwortet den Rumpf einer Anfrage.
var handler: Callable
var secret := ""
## Warum er nicht läuft – leer, wenn er läuft oder gar nicht laufen soll.
var problem := ""

var _server: TCPServer
var _port := 0
## Die offenen Verbindungen: `{ peer, bytes, since, out }`.
var _open: Array = []


func is_running() -> bool:
	return _server != null and _server.is_listening()


func port() -> int:
	return _port if is_running() else 0


## Fängt an zu hören. Gibt zurück, ob es geklappt hat.
func start(on_port: int) -> bool:
	stop()
	problem = ""
	if secret == "":
		problem = "Ohne Kennwort läuft der MCP-Server nicht."
		return false
	_server = TCPServer.new()
	var error := _server.listen(on_port, "127.0.0.1")
	if error != OK:
		_server = null
		problem = "Port %d ist nicht frei (%s)." % [on_port, error_string(error)]
		return false
	_port = on_port
	set_process(true)
	return true


func stop() -> void:
	for entry in _open:
		entry["peer"].disconnect_from_host()
	_open.clear()
	if _server != null:
		_server.stop()
		_server = null
	set_process(false)


func _ready() -> void:
	set_process(is_running())


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _server == null:
		return
	while _server.is_connection_available():
		var peer := _server.take_connection()
		peer.set_no_delay(true)
		_open.append({"peer": peer, "bytes": PackedByteArray(), "since": Time.get_ticks_msec(), "out": false})
	for entry in _open.duplicate():
		if not _serve(entry):
			entry["peer"].disconnect_from_host()
			_open.erase(entry)


## Kümmert sich um eine Verbindung. Gibt zurück, ob sie offen bleiben soll.
func _serve(entry: Dictionary) -> bool:
	var peer: StreamPeerTCP = entry["peer"]
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	if entry["out"]:
		# Die Antwort ist unterwegs; das Gegenüber schließt, sobald es sie hat.
		return Time.get_ticks_msec() - entry["since"] < PATIENCE_MSEC
	var waiting := peer.get_available_bytes()
	if waiting > 0:
		var got := peer.get_partial_data(waiting)
		if got[0] != OK:
			return false
		entry["bytes"].append_array(got[1])
	var request := Mcp.parse_request(entry["bytes"])
	if request["state"] == Mcp.MORE:
		return Time.get_ticks_msec() - entry["since"] < PATIENCE_MSEC
	peer.put_data(_reply(request))
	entry["out"] = true
	entry["since"] = Time.get_ticks_msec()
	return true


func _reply(request: Dictionary) -> PackedByteArray:
	if request["state"] == Mcp.BAD:
		return Mcp.response(400)
	if request["path"] != ROUTE:
		return Mcp.response(404)
	var refused := Mcp.refusal(request["headers"], secret)
	if refused != 0:
		return Mcp.response(refused)
	if request["method"] != "POST":
		# Kein Strom vom Server aus, keine Sitzung zum Beenden.
		return Mcp.response(405, "", {"Allow": "POST"})
	var text: String = handler.call(request["body"])
	return Mcp.response(202) if text == "" else Mcp.response(200, text)
