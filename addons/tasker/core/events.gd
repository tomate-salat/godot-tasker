@tool
extends Node
## Der Änderungs-Strom von Tasker (`GET /api/events`, Server-Sent Events):
## jede Änderung in der Web-App oder von einem anderen Gerät kommt sofort an,
## statt erst beim nächsten Neuladen.
##
## Der Strom bleibt offen. Der Server schickt alle 25 Sekunden ein
## Lebenszeichen; bleibt es aus oder reißt die Verbindung, wird neu verbunden.
## Was in der Lücke passiert ist, holt der Datenbestand dann am Stück nach.

## Eine Änderung: `{ id, origin, event }`, siehe Taskers `shared/events.ts`.
signal received(envelope: Dictionary)
## Der Strom steht (wieder). `again` ist wahr nach einer Unterbrechung.
signal connected(again: bool)
signal disconnected

const Client := preload("client.gd")

## Ohne Lebenszeichen so lange gilt die Verbindung als tot.
const SILENCE_SECONDS := 70.0
const RETRY_SECONDS := [3.0, 5.0, 10.0, 30.0]

var client: Client
## Ob der Strom gerade steht.
var live := false

var _http: HTTPClient
var _active := false
var _requested := false
var _streaming := false
var _was_connected := false
var _silence := 0.0
var _wait := 0.0
var _retries := 0
var _buffer := ""
var _event_name := ""
var _data: PackedStringArray = []


## Verbindet und hält den Strom offen, bis `stop` ihn beendet.
func start() -> void:
	stop()
	if client == null or client.base_url == "" or client.token == "":
		return
	_active = true
	_retries = 0
	_was_connected = false
	_open()


func stop() -> void:
	_active = false
	_close()


func _open() -> void:
	_close()
	var target := parse_url(client.base_url)
	if target.is_empty():
		_active = false
		return
	_http = HTTPClient.new()
	_requested = false
	_streaming = false
	_silence = 0.0
	_buffer = ""
	_event_name = ""
	_data = PackedStringArray()
	if _http.connect_to_host(target["host"], target["port"], TLSOptions.client() if target["tls"] else null) != OK:
		_retry()


func _close() -> void:
	if _http != null:
		_http.close()
		_http = null
	if live:
		live = false
		disconnected.emit()


func _retry() -> void:
	_close()
	_wait = RETRY_SECONDS[mini(_retries, RETRY_SECONDS.size() - 1)]
	_retries += 1


func _process(delta: float) -> void:
	if not _active:
		return
	if _http == null:
		_wait -= delta
		if _wait <= 0.0:
			_open()
		return

	_http.poll()
	match _http.get_status():
		HTTPClient.STATUS_CONNECTED:
			if not _requested:
				_requested = true
				var headers := PackedStringArray([
					"Accept: text/event-stream",
					"Cache-Control: no-cache",
					"Authorization: Bearer " + client.token,
					"%s: %s" % [Client.CLIENT_HEADER, client.client_id],
				])
				var path: String = parse_url(client.base_url)["prefix"] + "/api/events"
				if _http.request(HTTPClient.METHOD_GET, path, headers) != OK:
					_retry()
			elif _streaming:
				# Der Server hat den Strom beendet.
				_retry()
		HTTPClient.STATUS_BODY:
			if not _streaming:
				if _http.get_response_code() != 200:
					# Ohne gültiges Token hilft kein neuer Versuch.
					if _http.get_response_code() == 401:
						_active = false
						_close()
					else:
						_retry()
					return
				_streaming = true
				_retries = 0
				live = true
				connected.emit(_was_connected)
				_was_connected = true
			var chunk := _http.read_response_body_chunk()
			if chunk.size() > 0:
				_silence = 0.0
				for envelope in feed(chunk.get_string_from_utf8()):
					received.emit(envelope)
			else:
				_silence += delta
				if _silence > SILENCE_SECONDS:
					_retry()
		HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_REQUESTING:
			_silence += delta
			if _silence > SILENCE_SECONDS:
				_retry()
		_:
			_retry()


## Nimmt ein Stück des Stroms entgegen und gibt die vollständigen Änderungen
## darin zurück. Ein Ereignis endet mit einer Leerzeile und kann über mehrere
## Stücke verteilt ankommen. `ready` und `ping` sind nur Lebenszeichen.
func feed(text: String) -> Array:
	var out := []
	_buffer += text
	while true:
		var end := _buffer.find("\n")
		if end < 0:
			break
		var line := _buffer.substr(0, end).trim_suffix("\r")
		_buffer = _buffer.substr(end + 1)
		if line == "":
			if _data.size() > 0 and (_event_name == "" or _event_name == "message"):
				# Über `JSON.new()`, damit Unlesbares keinen Fehler ins Log schreibt.
				var json := JSON.new()
				var envelope = json.data if json.parse("\n".join(_data)) == OK else null
				if envelope is Dictionary and envelope.get("event") is Dictionary:
					out.append(envelope)
			_event_name = ""
			_data = PackedStringArray()
		elif line.begins_with("event:"):
			_event_name = line.substr(6).strip_edges()
		elif line.begins_with("data:"):
			_data.append(line.substr(5).trim_prefix(" "))
	return out


## Zerlegt die Server-Adresse: `{ host, port, tls, prefix }` – leer, wenn sie
## keine ist.
static func parse_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	if not tls and not url.begins_with("http://"):
		return {}
	var rest := url.substr(8 if tls else 7)
	var slash := rest.find("/")
	var host_port := rest if slash < 0 else rest.substr(0, slash)
	var prefix := "" if slash < 0 else rest.substr(slash).trim_suffix("/")
	var port := 443 if tls else 80
	var colon := host_port.rfind(":")
	if colon > 0 and host_port.substr(colon + 1).is_valid_int():
		port = host_port.substr(colon + 1).to_int()
		host_port = host_port.substr(0, colon)
	if host_port == "":
		return {}
	return {"host": host_port, "port": port, "tls": tls, "prefix": prefix}
