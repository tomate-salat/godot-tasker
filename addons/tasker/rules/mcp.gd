@tool
extends RefCounted
## MCP (Model Context Protocol) für das Addon, so weit es ohne Editor und ohne
## Netz geht: eine HTTP-Anfrage lesen, eine JSON-RPC-Nachricht beantworten.
##
## Gesprochen wird die HTTP-Variante von MCP in ihrer einfachsten Form: jede
## Anfrage ist ein POST mit einer JSON-RPC-Nachricht, die Antwort kommt als
## JSON zurück. Kein Strom, keine Sitzung. Den Server dazu stellt
## `core/mcp_server.gd`, die Werkzeuge `core/scene_tools.gd`.

const NAME := "tasker-godot"
const LATEST := "2025-06-18"
const VERSIONS := ["2025-06-18", "2025-03-26", "2024-11-05"]

## Was das Gegenüber über diesen Server wissen soll, ehe es ein Werkzeug
## anfasst. Der Ablauf steht ausdrücklich da, weil er sich nicht von selbst
## ergibt: der Nutzer arbeitet im Editor weiter, während hier gelesen und
## geschrieben wird – wer mehrmals nacheinander hineinschaut, sieht jedes Mal
## etwas anderes (Nutzer, 2026-10-13).
const INSTRUCTIONS := "Der Godot-Editor des Nutzers mit dem Tasker-Addon: sehen, was dort offen und ausgewählt ist, Tasker-Aufgaben anlegen und an Nodes hängen." \
	+ "\n\nFällt dem Nutzer in seinem Godot-Projekt etwas auf und er will dafür einen Task, ein Ticket oder einen Bug:" \
	+ "\n1. Sofort und als Erstes context aufrufen – ein Aufruf, der alles liefert, was der Editor gerade weiß. Der Nutzer wechselt die Szene oft Sekunden später; danach nicht noch einmal im Editor nachsehen, sondern mit diesem Schnappschuss und den Dateien des Projekts arbeiten." \
	+ "\n2. Mit find_tasks nach Vorhandenem sehen, im Projekt nachlesen und mit create_task anlegen (`scene` und `paths` aus dem Schnappschuss)." \
	+ "\n3. Die Aufgabe wird in jedem Fall angelegt. Ist etwas unklar, die naheliegendste Annahme treffen, sie in die Aufgabe schreiben und dem Nutzer sagen – nicht stattdessen zurückfragen." \
	+ "\nAufgaben zu Dingen im Godot-Projekt laufen über diesen Server, nicht über einen anderen Tasker-Zugang: nur hier hängen sie danach an ihren Nodes."

const MORE := "more"
const BAD := "bad"
const DONE := "done"

## Mehr als das nimmt der Server nicht an – eine Anfrage ist ein paar hundert Bytes.
const MAX_BYTES := 1_000_000

const PARSE_ERROR := -32700
const INVALID_REQUEST := -32600
const METHOD_NOT_FOUND := -32601
const INVALID_PARAMS := -32602


## Liest eine HTTP-Anfrage aus dem, was bisher angekommen ist:
## `{ state, method, path, headers, body }`. `state` ist `MORE` (es fehlt noch
## etwas), `BAD` (so nicht) oder `DONE`. Die Namen der Kopfzeilen sind klein
## geschrieben.
static func parse_request(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() > MAX_BYTES:
		return {"state": BAD}
	var text := bytes.get_string_from_utf8()
	var cut := text.find("\r\n\r\n")
	if cut < 0:
		return {"state": MORE}
	var lines := text.substr(0, cut).split("\r\n")
	var first := lines[0].split(" ")
	if first.size() < 3 or not first[2].begins_with("HTTP/1."):
		return {"state": BAD}
	var headers := {}
	for i in range(1, lines.size()):
		var colon := lines[i].find(":")
		if colon <= 0:
			return {"state": BAD}
		headers[lines[i].substr(0, colon).strip_edges().to_lower()] = lines[i].substr(colon + 1).strip_edges()
	if headers.has("transfer-encoding"):
		return {"state": BAD}
	var length := str(headers.get("content-length", "0"))
	if not length.is_valid_int() or int(length) < 0 or int(length) > MAX_BYTES:
		return {"state": BAD}
	# Die Länge zählt Bytes, nicht Zeichen: darum am Rohen abmessen.
	var head_bytes := text.substr(0, cut + 4).to_utf8_buffer().size()
	if bytes.size() < head_bytes + int(length):
		return {"state": MORE}
	return {
		"state": DONE,
		"method": first[0],
		"path": first[1].get_slice("?", 0),
		"headers": headers,
		"body": bytes.slice(head_bytes, head_bytes + int(length)).get_string_from_utf8(),
	}


## Ob die Anfrage von diesem Rechner und mit dem richtigen Kennwort kommt.
## Gibt den HTTP-Status zurück, mit dem sie abzuweisen ist – 0, wenn sie darf.
##
## Eine Webseite im Browser könnte sonst an `localhost` schicken, was sie will:
## darum zählt nur das Kennwort, und eine fremde Herkunft wird gar nicht erst
## angehört.
static func refusal(headers: Dictionary, secret: String) -> int:
	var origin := str(headers.get("origin", ""))
	if origin != "" and origin != "null":
		var host := origin.get_slice("://", 1).get_slice("/", 0)
		if host.begins_with("["):
			host = host.get_slice("]", 0) + "]"
		else:
			host = host.get_slice(":", 0)
		if not host in ["localhost", "127.0.0.1", "[::1]"]:
			return 403
	if secret == "" or str(headers.get("authorization", "")) != "Bearer " + secret:
		return 401
	return 0


## Baut die HTTP-Antwort. Die Verbindung wird danach geschlossen.
static func response(status: int, body := "", extra := {}) -> PackedByteArray:
	var words := {200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 405: "Method Not Allowed"}
	var payload := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\n" % [status, words.get(status, "")]
	if body != "":
		head += "Content-Type: application/json\r\n"
	for key in extra:
		head += "%s: %s\r\n" % [key, extra[key]]
	head += "Content-Length: %d\r\nConnection: close\r\n\r\n" % payload.size()
	var out := head.to_utf8_buffer()
	out.append_array(payload)
	return out


## Beantwortet, was im Rumpf einer Anfrage stand. Gibt den Text der Antwort
## zurück – leer, wenn nichts zu antworten ist (eine Mitteilung ohne `id`).
##
## `tools` sind die Werkzeuge, wie `tools/list` sie nennt; `run` führt eines
## aus: `run(name, arguments) -> { text, failed }`.
static func answer(body: String, tools: Array, run: Callable, version := "") -> String:
	var json := JSON.new()
	if json.parse(body) != OK:
		return JSON.stringify(_error(null, PARSE_ERROR, "Kein gültiges JSON"))
	var data: Variant = json.data
	if data is Array:
		var out := []
		for message in data:
			var reply: Variant = await handle(message, tools, run, version)
			if reply != null:
				out.append(reply)
		return "" if out.is_empty() else JSON.stringify(out)
	var single: Variant = await handle(data, tools, run, version)
	return "" if single == null else JSON.stringify(single)




## Eine JSON-RPC-Nachricht: gibt die Antwort zurück, oder null, wenn keine
## erwartet wird.
static func handle(message: Variant, tools: Array, run: Callable, version := "") -> Variant:
	if not message is Dictionary or not message.has("method"):
		# Auch eine Antwort des Gegenübers landet hier – darauf folgt nichts.
		if message is Dictionary and (message.has("result") or message.has("error")):
			return null
		return _error(null, INVALID_REQUEST, "Keine JSON-RPC-Anfrage")
	if not message.has("id"):
		return null
	var id: Variant = message["id"]
	# JSON kennt nur eine Sorte Zahl; aus 1 soll nicht 1.0 werden.
	if id is float and id == floorf(id):
		id = int(id)
	var params: Variant = message.get("params", {})
	if not params is Dictionary:
		params = {}
	match str(message["method"]):
		"initialize":
			var asked := str(params.get("protocolVersion", ""))
			return _result(id, {
				"protocolVersion": asked if asked in VERSIONS else LATEST,
				"capabilities": {"tools": {}},
				"serverInfo": {"name": NAME, "version": version},
				"instructions": INSTRUCTIONS,
			})
		"ping":
			return _result(id, {})
		"tools/list":
			return _result(id, {"tools": tools})
		"tools/call":
			var name := str(params.get("name", ""))
			if not tools.any(func(t: Dictionary) -> bool: return t["name"] == name):
				return _error(id, INVALID_PARAMS, "Unbekanntes Werkzeug: %s" % name)
			var arguments: Variant = params.get("arguments", {})
			# Ein Werkzeug darf warten – etwa auf den Tasker-Server.
			var done: Dictionary = await run.call(name, arguments if arguments is Dictionary else {})
			return _result(id, {"content": [{"type": "text", "text": str(done.get("text", ""))}], "isError": bool(done.get("failed", false))})
	return _error(id, METHOD_NOT_FOUND, "Unbekannte Methode: %s" % message["method"])


static func _result(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


static func _error(id: Variant, code: int, text: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": text}}
