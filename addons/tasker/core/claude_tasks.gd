@tool
extends Node
## Aufgaben aus dem Addon anlegen und von Claude überarbeiten lassen
## (Nutzer, 2026-10-19; Regeln und Aufträge in `rules/quick.gd`).
##
## Angelegt wird über Taskers Eingang `POST /api/intake/task`, wie beim
## MCP-Werkzeug `create_task`. Ein Claude-Auftrag läuft im Hintergrund:
## der Schnappschuss des Editors ist da schon gemacht, der Nutzer kann
## weiterarbeiten. Was zurückkommt, trägt das Addon selbst ein – Titel und
## Beschreibung nur, wenn inzwischen niemand daran geändert hat.

## Ein Auftrag hat angefangen oder ist fertig (`running`).
signal changed
## Was Claude für diese Aufgabe gerade tut, als Zeile („liest cell.tscn“).
signal progress(task_id: String, line: String)
## Der Auftrag ist durch – eingetragen (`ok`) oder nicht; `message` sagt, was war.
## `show`: die Aufgabe soll danach im Editor aufgehen (nicht bei Aufträgen aus
## der Web-App – dort sitzt der Nutzer gerade).
signal finished(task_id: String, ok: bool, message: String, show: bool)

const Store := preload("store.gd")
const Links := preload("links.gd")
const SceneTools := preload("scene_tools.gd")
const ClaudeCli := preload("claude_cli.gd")
const Config := preload("config.gd")
const Quick := preload("../rules/quick.gd")

## Hier liegen die Aufträge, solange Claude sie liest.
const JOB_DIR := "res://.godot/tasker/claude"
## Aufträge aus der Web-App: Tasker gibt nach 5 Minuten auf, das Addon vorher.
const WEB_PATIENCE_MSEC := 270_000
## Zwischenmeldungen an Tasker höchstens so oft.
const STATUS_EVERY_MSEC := 2000

var store: Store
var links: Links
var scene_tools: SceneTools
var cli: ClaudeCli
## Aufgabe → der Auftrag, der für sie gerade läuft.
var running := {}
## Aufgabe → der Griff, mit dem sich ihr Auftrag abbrechen lässt.
var _handles := {}
## Aufgaben, deren Auftrag aus der Web-App kam.
var _from_web := {}


## Legt eine Aufgabe an und hängt sie an die Nodes (`{ scene, path }`).
## Antwort: `{ ok, error, task_id, problems }` – `problems` nennt, was sich
## nicht anhängen ließ; angelegt ist die Aufgabe dann trotzdem.
func create(title: String, desc: String, refs: Array, ai_created := true) -> Dictionary:
	var out := {"ok": false, "error": "", "task_id": "", "problems": []}
	if store == null or store.state != "ready":
		out["error"] = "Das Addon ist gerade nicht mit Tasker verbunden."
		return out
	var fields := {"projectId": Config.project_id(), "title": title.strip_edges()}
	if desc.strip_edges() != "":
		fields["desc"] = desc
	# Tasker markiert Eingänge sonst als von einer KI angelegt (`ai-created`).
	if not ai_created:
		fields["aiCreated"] = false
	var made: Dictionary = await store.intake(fields)
	if not made["ok"]:
		out["error"] = "Tasker hat die Aufgabe nicht angelegt: %s" % made["error"]
		return out
	out["ok"] = true
	out["task_id"] = made["object"]["id"]
	out["problems"] = hang(out["task_id"], _grouped(refs))
	return out


## Hängt die Aufgabe an Nodes, je Szene `{ scene, paths }`. Gibt zurück, was
## nicht ging.
func hang(task_id: String, groups: Array) -> Array:
	var problems := []
	for g in groups:
		var res := scene_tools.hang(task_id, g["scene"], g["paths"])
		if res["failed"]:
			problems.append(res["text"])
	return problems


## Ein Auftrag aus der Web-App (`godot-refine`): sofort annehmen, dann den
## Schnappschuss machen und Claude losschicken; Tasker erfährt über
## `POST /api/godot/status`, wie es steht.
func refine(request_id: String, task_id: String, mode: String) -> void:
	_report(request_id, "accepted", "")
	if not Quick.MODES.has(mode):
		_report(request_id, "failed", "Diesen Auftrag („%s“) kennt das Addon nicht." % mode)
		return
	if store.ws.task(task_id) == null:
		# Gerade erst in der Web-App angelegt: vielleicht ist sie noch nicht angekommen.
		await store.reload()
	var task: Variant = store.ws.task(task_id)
	if task == null:
		_report(request_id, "failed", "Die Aufgabe kennt das Addon nicht – ist Godot mit diesem Projekt verbunden?")
		return
	if running.has(task_id):
		_report(request_id, "failed", "Für diese Aufgabe arbeitet Claude in Godot schon.")
		return
	var label := "$%d" % int(task.get("ref", 0))
	_say("%s wird aus Tasker heraus verfeinert …" % label)
	var snapshot := await scene_tools.snapshot()
	_report(request_id, "working", "Schnappschuss gemacht, Claude arbeitet")
	var last := [Time.get_ticks_msec()]
	var tell := func(id: String, line: String) -> void:
		if id == task_id and Time.get_ticks_msec() - last[0] >= STATUS_EVERY_MSEC:
			last[0] = Time.get_ticks_msec()
			_report(request_id, "working", line)
	progress.connect(tell)
	_from_web[task_id] = true
	var res: Dictionary = await improve(task_id, mode, snapshot, WEB_PATIENCE_MSEC)
	progress.disconnect(tell)
	_report(request_id, "done" if res["ok"] else "failed", res["message"])


func _report(request_id: String, state: String, message: String) -> void:
	var body := {"requestId": request_id, "state": state}
	if message != "":
		body["message"] = message.left(300)
	store.client.post("/api/godot/status", body)


## Schickt Claude an die Aufgabe. `snapshot` ist beim Klick gemacht worden.
## Läuft schon ein Auftrag für sie, wird keiner dazugestartet. Antwort:
## `{ ok, message }`.
func improve(task_id: String, mode: String, snapshot: String, patience := ClaudeCli.PATIENCE_MSEC) -> Dictionary:
	var task: Variant = store.ws.task(task_id) if store != null else null
	if task == null or running.has(task_id):
		return {"ok": false, "message": "Für diese Aufgabe läuft schon ein Auftrag." if task != null else "Die Aufgabe gibt es nicht."}
	var label := "$%d" % int(task.get("ref", 0))
	var base_title := str(task.get("title", ""))
	var base_desc := str(task.get("desc", "")) if task.get("desc") != null else ""
	var linked := links.of_task(task_id)

	var project_dir := ProjectSettings.globalize_path("res://").trim_suffix("/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(JOB_DIR))
	var file := ProjectSettings.globalize_path(JOB_DIR.path_join("%s-%s.md" % [task_id, mode]))
	var lines := linked.map(func(ref: Dictionary) -> String: return "- scene: %s   path: %s" % [ref["scenePath"], ref["nodePath"]])
	var job := FileAccess.open(file, FileAccess.WRITE)
	if job == null:
		return _end(task_id, false, "%s: Der Auftrag für Claude ließ sich nicht schreiben (%s)." % [label, file])
	job.store_string(Quick.prompt(mode, task, lines, snapshot, project_dir))
	job.close()

	running[task_id] = mode
	var handle := {}
	_handles[task_id] = handle
	changed.emit()
	var listen := func(tool: String, input: Dictionary) -> void:
		var line := Quick.activity(tool, input)
		if line != "":
			progress.emit(task_id, line)
	var res: Dictionary = await cli.run(file, Quick.schema(mode), project_dir, listen, handle, patience)
	DirAccess.remove_absolute(file)
	if not res["ok"]:
		return _end(task_id, false, "%s: %s" % [label, res["error"]])
	var answer := Quick.parse(mode, res["data"])
	if not answer["ok"]:
		return _end(task_id, false, "%s: %s" % [label, answer["error"]])
	progress.emit(task_id, "trägt ein")

	var said := [Quick.DONE[mode] % label]
	if mode != Quick.LINKS:
		var now: Variant = store.ws.task(task_id)
		if now == null:
			return _end(task_id, false, "%s gibt es nicht mehr." % label)
		var now_desc := str(now.get("desc", "")) if now.get("desc") != null else ""
		if str(now.get("title", "")) != base_title or now_desc != base_desc:
			said = ["%s ist inzwischen geändert worden – Claudes Text ist nicht eingetragen." % label]
		else:
			var saved: Dictionary = await store.patch("task", task_id, {"title": answer["title"], "desc": answer["desc"]})
			if not saved["ok"]:
				said = ["%s: Claudes Text ließ sich nicht speichern: %s" % [label, saved["error"]]]
	var fresh := Quick.without_linked(answer["links"], links.of_task(task_id))
	var problems := hang(task_id, fresh)
	var count := 0
	for g in fresh:
		count += g["paths"].size()
	if count > 0 and problems.is_empty():
		said.append("Hängt jetzt auch an %s." % ("1 Node" if count == 1 else "%d Nodes" % count))
	elif not problems.is_empty():
		said.append("Nicht alles ließ sich anhängen: %s" % "; ".join(problems))
	if answer["note"] != "":
		said.append(answer["note"])
	return _end(task_id, problems.is_empty(), " ".join(said))


## Bricht den Auftrag für diese Aufgabe ab. Angelegt bleibt sie.
func cancel(task_id: String) -> void:
	if _handles.has(task_id):
		cli.stop(_handles[task_id])


func _end(task_id: String, ok: bool, message: String) -> Dictionary:
	running.erase(task_id)
	_handles.erase(task_id)
	var show := not _from_web.has(task_id)
	_from_web.erase(task_id)
	changed.emit()
	_say(message, not ok)
	finished.emit(task_id, ok, message, show)
	return {"ok": ok, "message": message}


## Fasst `{ scene, path }` nach Szene zusammen.
static func _grouped(refs: Array) -> Array:
	var by_scene := {}
	var order := []
	for r in refs:
		if not by_scene.has(r["scene"]):
			by_scene[r["scene"]] = []
			order.append(r["scene"])
		if not by_scene[r["scene"]].has(r["path"]):
			by_scene[r["scene"]].append(r["path"])
	return order.map(func(scene: String) -> Dictionary: return {"scene": scene, "paths": by_scene[scene]})


func _say(text: String, warn := false) -> void:
	EditorInterface.get_editor_toaster().push_toast("Tasker: " + text, EditorToaster.SEVERITY_WARNING if warn else EditorToaster.SEVERITY_INFO)
