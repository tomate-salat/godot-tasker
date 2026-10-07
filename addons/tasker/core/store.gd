@tool
extends Node
## Der Datenbestand: der Stand vom Server, der Index darüber und alles, was
## ihn ändert. Dock, Suche und Tisch hängen an `changed`.
##
## `bootstrap` liefert alle Projekte. Der Index umfasst deshalb alles –
## Abhängigkeiten dürfen über Projekte hinweg zeigen –, und wer fragt, nennt
## das Projekt (`project_id`).

signal changed
## `state` hat gewechselt: "empty", "loading", "ready" oder "error".
signal state_changed

const Client := preload("client.gd")
const Workspace := preload("../rules/workspace.gd")

const LISTS := {
	"project": "projects",
	"category": "categories",
	"mark": "marks",
	"group": "groups",
	"milestone": "milestones",
	"task": "tasks",
}

## Tasker rechnet ohne Einstellung mit acht Aufgaben pro Woche.
const DEFAULT_VELOCITY := 8

var client: Client
var project_id := ""

var state := "empty"
var error := ""
var data := {}
var ws: Workspace = Workspace.new({})
## Aufgaben pro Woche – das Wochenziel am Tisch.
var velocity := DEFAULT_VELOCITY

var _loading := false
var _reload_again := false


## Holt den ganzen Stand neu. Falsch, wenn der Server nicht mitspielt – der
## Grund steht dann in `error`.
func reload() -> bool:
	if _loading:
		# Während des Ladens kann schon wieder etwas passiert sein – danach noch einmal.
		_reload_again = true
		await state_changed
		return state == "ready"
	_loading = true
	_set_state("loading" if state != "ready" else state)

	var res := await client.get_json("/api/bootstrap")
	_loading = false
	if not res["ok"] or not res["data"] is Dictionary:
		error = res["error"] if res["error"] != "" else "Der Server hat nichts Lesbares geschickt."
		_set_state("error")
		return false

	data = res["data"]
	error = ""
	_rebuild()
	_set_state("ready")
	_load_velocity()
	if _reload_again:
		_reload_again = false
		reload()
	return true


## Ändert ein Objekt. Antwort: `{ ok, conflict, error, object }`.
##
## Jede Änderung nennt die Version, auf der sie beruht. Hat inzwischen jemand
## anderes geändert, kommt 409 mit dem aktuellen Stand – der wird übernommen,
## und `conflict` sagt, dass die eigene Änderung nicht gegriffen hat.
func patch(kind: String, id: String, changes: Dictionary) -> Dictionary:
	var current = _find(kind, id)
	if current == null:
		return {"ok": false, "conflict": false, "error": "Nicht gefunden.", "object": null}

	var res := await client.patch("/api/kind/%s/%s" % [kind, id.uri_encode()], {
		"version": int(current["version"]),
		"changes": changes,
	})
	if res["status"] == 409 and res["data"] is Dictionary and res["data"].get("current") is Dictionary:
		_upsert(kind, res["data"]["current"])
		return {"ok": false, "conflict": true, "error": "Inzwischen woanders geändert – der neue Stand ist geladen.", "object": res["data"]["current"]}
	if not res["ok"] or not res["data"] is Dictionary:
		return {"ok": false, "conflict": false, "error": res["error"], "object": null}

	var object: Dictionary = res["data"]
	# Der Status einer Unteraufgabe kann den der Eltern-Aufgaben mitziehen –
	# Tasker meldet das seinen anderen Tabs auch nur als „neu laden“.
	if kind == "task" and changes.has("status") and object.get("parentId"):
		_upsert(kind, object)
		await reload()
	else:
		_upsert(kind, object)
	return {"ok": true, "conflict": false, "error": "", "object": object}


func set_status(task: Dictionary, status: String) -> Dictionary:
	return await patch("task", task["id"], {"status": status})


func _find(kind: String, id: String) -> Variant:
	for x in data.get(LISTS.get(kind, ""), []):
		if x["id"] == id:
			return x
	return null


func _upsert(kind: String, object: Dictionary) -> void:
	if not LISTS.has(kind):
		return
	var list: Array = data.get_or_add(LISTS[kind], [])
	var at := -1
	for i in list.size():
		if list[i]["id"] == object["id"]:
			at = i
			break
	if at < 0:
		list.append(object)
	else:
		list[at] = object
	_rebuild()


func _rebuild() -> void:
	ws = Workspace.new(data)
	changed.emit()


func _load_velocity() -> void:
	var res := await client.get_json("/api/settings")
	if res["ok"] and res["data"] is Dictionary and res["data"].get("velocity") != null:
		var v := int(res["data"]["velocity"])
		if v != velocity:
			velocity = v
			changed.emit()


func _set_state(next: String) -> void:
	state = next
	state_changed.emit()


## Die Adresse der Aufgabe in der Web-App: `/<projekt>/<id>`, wie Taskers
## `client/url.ts` sie liest.
func web_url(task: Dictionary) -> String:
	return "%s/%s/%s" % [client.base_url, str(task["projectId"]).uri_encode(), str(task["id"]).uri_encode()]


## Wendet eine Änderung aus dem Änderungs-Strom an (`core/events.gd`).
##
## Kleine Änderungen tragen das Objekt bei sich und werden eingesetzt. Was
## viele Zeilen auf einmal betrifft – Verschieben, Archivieren, Löschen –,
## meldet Tasker nur als „neu laden“; dann wird der ganze Stand geholt.
func apply_event(envelope: Dictionary) -> void:
	# Der eigene Hall: was dieses Addon selbst geändert hat, ist schon eingesetzt.
	if envelope.get("origin") == client.client_id:
		return
	if state != "ready":
		return
	var event: Dictionary = envelope.get("event", {})
	match event.get("type"):
		"upsert":
			if event.get("object") is Dictionary and LISTS.has(event.get("kind")):
				_upsert(event["kind"], event["object"])
		"delete":
			_remove(str(event.get("kind")), str(event.get("id")))
		"settings":
			var settings = event.get("settings")
			if settings is Dictionary and settings.get("velocity") != null:
				velocity = int(settings["velocity"])
				changed.emit()
		"reload", "drawings":
			# Die Liste der Zeichnungen kommt mit dem Stand.
			reload()


func _remove(kind: String, id: String) -> void:
	if not LISTS.has(kind):
		return
	var list: Array = data.get(LISTS[kind], [])
	for i in list.size():
		if list[i]["id"] == id:
			list.remove_at(i)
			_rebuild()
			return


## Verschiebt eine Aufgabe an einen anderen Ort oder Platz (`/api/move`).
## `target` nennt Ziel und Stelle, siehe `Planning.move_body`. Antwort wie bei
## `patch`: `{ ok, conflict, error }`.
##
## `local` (Aufgaben-ID → geänderte Felder, `Planning.local_move`) steht sofort
## im Stand, damit die Karte nicht auf die Antwort warten muss. Geht der Zug
## nicht, ist danach wieder alles, wie es war. Geht er, wird der ganze Stand
## geholt: Verschieben rührt an den Geschwistern und am ganzen Teilbaum.
func move(task_id: String, target: Dictionary, local := {}) -> Dictionary:
	var current = _find("task", task_id)
	if current == null:
		return {"ok": false, "conflict": false, "error": "Nicht gefunden."}
	var body := {"id": task_id, "version": int(current["version"])}
	body.merge(target)

	var tasks: Array = data.get("tasks", [])
	var before := {}
	for i in tasks.size():
		if local.has(tasks[i]["id"]):
			before[i] = tasks[i]
			var next: Dictionary = tasks[i].duplicate()
			next.merge(local[tasks[i]["id"]], true)
			tasks[i] = next
	if not before.is_empty():
		_rebuild()

	var res := await client.post("/api/move", body)
	if res["ok"]:
		await reload()
		return {"ok": true, "conflict": false, "error": ""}
	# Zurück auf den alten Stand – außer es wurde inzwischen ohnehin neu geladen.
	if not before.is_empty() and is_same(data.get("tasks"), tasks):
		for i in before:
			tasks[i] = before[i]
		_rebuild()
	if res["status"] == 409:
		await reload()
		return {"ok": false, "conflict": true, "error": "Inzwischen woanders geändert – der neue Stand ist geladen."}
	return {"ok": false, "conflict": false, "error": res["error"]}
