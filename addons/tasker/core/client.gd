@tool
extends Node
## Spricht mit dem Tasker-Server.
##
## Angemeldet wird mit einem Zugangs-Token aus dem Tasker-Profil. Per Token
## sind nur einzelne Routen freigegeben, siehe `TOKEN_ROUTES` in Taskers
## `src/server/index.ts` – alles andere antwortet mit 401.

## Der Header, mit dem sich ein Client in Tasker nennt; der Änderungs-Strom
## schickt ihn als `origin` zurück, damit man den eigenen Hall übergehen kann.
const CLIENT_HEADER := "x-tasker-client"

var base_url := ""
var token := ""
var client_id := "godot-%08x" % (randi() & 0xffffffff)
var timeout := 20.0


func get_json(path: String) -> Dictionary:
	return await request(HTTPClient.METHOD_GET, path)


func post(path: String, body: Variant = {}) -> Dictionary:
	return await request(HTTPClient.METHOD_POST, path, body)


func patch(path: String, body: Variant) -> Dictionary:
	return await request(HTTPClient.METHOD_PATCH, path, body)


## Eine Anfrage. Antwort: `{ ok, status, data, error, body }` – `data` ist das
## gelesene JSON, `body` sind die rohen Bytes (für Bilder), `error` ein Satz
## für den Nutzer.
func request(method: int, path: String, body: Variant = null) -> Dictionary:
	if base_url == "":
		return _failed(0, "Keine Server-Adresse eingestellt.")

	var headers := PackedStringArray(["%s: %s" % [CLIENT_HEADER, client_id]])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := ""
	if body != null:
		headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)

	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)
	var err := http.request(base_url + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return _failed(0, "Die Anfrage ließ sich nicht starten (%s)." % error_string(err))

	var res: Array = await http.request_completed
	http.queue_free()
	var result: int = res[0]
	var status: int = res[1]
	var bytes: PackedByteArray = res[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _failed(0, "Der Server ist nicht erreichbar." if result != HTTPRequest.RESULT_TIMEOUT else "Der Server antwortet nicht.")

	var data = null
	if _is_json(res[2]):
		data = JSON.parse_string(bytes.get_string_from_utf8())
	var ok := status >= 200 and status < 300
	var error := ""
	if not ok:
		if status == 401:
			error = "Nicht angemeldet – das Token fehlt, ist ungültig oder gilt für diese Route nicht."
		elif data is Dictionary and data.get("error") is String:
			error = data["error"]
		else:
			error = "Der Server meldet einen Fehler (%d)." % status
	return {"ok": ok, "status": status, "data": data, "error": error, "body": bytes}


static func _is_json(headers: PackedStringArray) -> bool:
	for h in headers:
		var line := h.to_lower()
		if line.begins_with("content-type:"):
			return line.contains("json")
	return false


static func _failed(status: int, message: String) -> Dictionary:
	return {"ok": false, "status": status, "data": null, "error": message, "body": PackedByteArray()}
