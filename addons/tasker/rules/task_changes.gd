@tool
extends RefCounted
## Was eine Anweisung an Claude außer Text und Verknüpfungen an einer Aufgabe
## ändern darf – so, wie man es in der Web-App täte (Nutzer, 2026-10-20):
## Status, Priorität, Markierung, Kategorie, Tags, Ort (Milestone, Gruppe,
## Backlog), Abhängigkeiten und neue Unteraufgaben.
##
## Claude nennt alles beim Namen („Bug“, „Milestone Kampf“, „$142“); hier wird
## daraus, was Tasker erwartet, und nach Taskers Regeln geprüft. Was nicht
## geht, landet in `problems` statt still wegzufallen.

const Workspace := preload("workspace.gd")
const Model := preload("model.gd")
const Tisch := preload("tisch.gd")
const Dependency := preload("dependency.gd")
const Planning := preload("planning.gd")

## Prioritäten, wie Claude sie nennt, und wie Tasker sie zählt.
const PRIOS := {"none": 0, "high": 1, "medium": 2, "low": 3}
const BACKLOG := "Backlog"

## Die Form von `changes` und `subtasks` in der Antwort.
const SCHEMA := {
	"changes": {
		"type": "object",
		"properties": {
			"status": {"type": "string", "enum": Model.STATUS},
			"prio": {"type": "string", "enum": ["none", "high", "medium", "low"]},
			"mark": {"type": "string"},
			"category": {"type": "string"},
			"tags": {"type": "array", "items": {"type": "string"}},
			"place": {"type": "string"},
			"deps": {"type": "array", "items": {"type": "string"}},
		},
	},
	"subtasks": {
		"type": "array",
		"items": {
			"type": "object",
			"properties": {"title": {"type": "string"}, "desc": {"type": "string"}},
			"required": ["title"],
		},
	},
}


## Was Claude über die Aufgabe wissen muss, um sie wie in der Web-App zu
## ändern: ihre Felder und was zur Wahl steht.
static func facts(ws: Workspace, project_id: String, task: Dictionary) -> String:
	var lines := [
		"- Status: %s (zur Wahl: %s)" % [task.get("status", "open"), ", ".join(Model.STATUS)],
		"- Priorität: %s (zur Wahl: none, high, medium, low)" % PRIOS.find_key(int(task.get("prio", 0))),
		"- Markierung: %s (zur Wahl: %s; \"\" entfernt sie)" % [_name_of(ws.mark(task.get("markId"))), _choices(_in_project(ws.marks, project_id))],
		"- Kategorie: %s (zur Wahl: %s; \"\" entfernt sie)" % [_name_of(ws.category(task.get("categoryId"))), _choices(_in_project(ws.categories, project_id))],
		"- Tags: %s" % (", ".join(task.get("tags", [])) if not task.get("tags", []).is_empty() else "keine"),
		"- Ort: %s (zur Wahl: %s)" % [place_of(ws, task), ", ".join(places(ws, project_id))],
		"- Wartet auf: %s" % (", ".join(task.get("deps", []).map(func(id: String) -> String: return _label(ws.task(id)))) if not task.get("deps", []).is_empty() else "nichts"),
		"- Unteraufgaben: %s" % (", ".join(ws.kids(task["id"]).map(func(k: Dictionary) -> String: return "%s [%s]" % [_label(k), k.get("status", "")])) if not ws.kids(task["id"]).is_empty() else "keine"),
	]
	return "\n".join(lines)


## Die Orte, an die eine Aufgabe dieses Projekts kann: Milestones, Gruppen, das Backlog.
static func places(ws: Workspace, project_id: String) -> Array:
	var out := [BACKLOG]
	for m in _in_project(ws.milestones, project_id):
		if m.get("archivedAt") == null:
			out.append(str(m.get("title", "")))
	for g in _in_project(ws.groups, project_id):
		out.append(str(g.get("title", "")))
	return out


static func place_of(ws: Workspace, task: Dictionary) -> String:
	if task.get("parentId"):
		return "unter %s" % _label(ws.task(task["parentId"]))
	var m: Variant = ws.milestone(task.get("milestoneId"))
	if m != null:
		return str(m.get("title", ""))
	var g: Variant = ws.group(task.get("groupId"))
	return str(g.get("title", "")) if g != null else BACKLOG


## Prüft `changes` und `subtasks` aus Claudes Antwort: `{ changes, subtasks }`,
## nur mit dem, was der Form entspricht.
static func parse(answer: Dictionary) -> Dictionary:
	var given: Variant = answer.get("changes", {})
	var changes := {}
	if given is Dictionary:
		for key in ["status", "prio", "mark", "category", "place"]:
			if given.get(key) is String:
				changes[key] = given[key].strip_edges()
		for key in ["tags", "deps"]:
			if given.get(key) is Array:
				changes[key] = given[key].map(func(x: Variant) -> String: return str(x).strip_edges()).filter(func(x: String) -> bool: return x != "")
	var subtasks := []
	var list: Variant = answer.get("subtasks", [])
	for s in list if list is Array else []:
		if s is Dictionary and str(s.get("title", "")).strip_edges() != "":
			subtasks.append({"title": str(s["title"]).strip_edges(), "desc": str(s.get("desc", "")).strip_edges()})
	return {"changes": changes, "subtasks": subtasks}


## Übersetzt `changes` in Taskers Felder: `{ patch, place, problems }`.
## `patch` geht an `PATCH /api/kind/task`, `place` (oder null) an `/api/move`.
## Was dem Stand schon entspricht, fehlt.
static func resolve(ws: Workspace, project_id: String, task: Dictionary, changes: Dictionary) -> Dictionary:
	var patch := {}
	var problems := []
	var place: Variant = null

	if changes.has("status") and changes["status"] != task.get("status"):
		var refusal := Tisch.done_refusal(ws, task) if changes["status"] == "done" else ""
		if refusal != "":
			problems.append("Status: %s" % refusal)
		elif Model.STATUS.has(changes["status"]):
			patch["status"] = changes["status"]
	if changes.has("prio") and PRIOS.has(changes["prio"]) and PRIOS[changes["prio"]] != int(task.get("prio", 0)):
		patch["prio"] = PRIOS[changes["prio"]]
	for part in [["mark", "markId", ws.marks, "Markierung"], ["category", "categoryId", ws.categories, "Kategorie"]]:
		if not changes.has(part[0]):
			continue
		var wanted: String = changes[part[0]]
		var id: Variant = null
		if wanted != "":
			var found := named(_in_project(part[2], project_id), wanted)
			if found.is_empty():
				problems.append("%s „%s“ gibt es nicht" % [part[3], wanted])
				continue
			id = found["id"]
		if id != task.get(part[1]):
			patch[part[1]] = id
	if changes.has("tags"):
		var tags: Array = []
		for t in changes["tags"]:
			if not tags.has(t):
				tags.append(t)
		if tags != task.get("tags", []):
			patch["tags"] = tags
	if changes.has("deps"):
		var deps := []
		for wanted in changes["deps"]:
			var other: Variant = by_ref(ws, wanted)
			if other == null:
				problems.append("Abhängigkeit %s gibt es nicht" % wanted)
				continue
			if task.get("deps", []).has(other["id"]):
				deps.append(other["id"])
				continue
			var refusal := Dependency.link_refusal(ws, task, other)
			if refusal != "":
				problems.append("Abhängigkeit %s: %s" % [wanted, refusal])
			elif not deps.has(other["id"]):
				deps.append(other["id"])
		if deps != task.get("deps", []):
			patch["deps"] = deps
	if changes.has("place") and changes["place"] != "" and changes["place"] != place_of(ws, task):
		var wanted: String = changes["place"]
		if wanted.to_lower() == BACKLOG.to_lower():
			place = Planning.LOOSE.duplicate()
		else:
			var m := named(_in_project(ws.milestones, project_id).filter(func(x: Dictionary) -> bool: return x.get("archivedAt") == null), wanted, "title")
			var g := named(_in_project(ws.groups, project_id), wanted, "title")
			if not m.is_empty():
				place = {"milestoneId": m["id"], "groupId": null}
			elif not g.is_empty():
				place = {"milestoneId": null, "groupId": g["id"]}
			else:
				problems.append("Ort „%s“ gibt es nicht" % wanted)
		if place != null:
			place["parentId"] = null
	return {"patch": patch, "place": place, "problems": problems}


## Wo die Aufgabe gerade liegt – als Ziel für `/api/move`, zum Zurückstellen.
static func place_body(task: Dictionary) -> Dictionary:
	return {"parentId": task.get("parentId"), "milestoneId": task.get("milestoneId"), "groupId": task.get("groupId")}


## Der Eintrag zu einem Namen oder einer ID, ohne Rücksicht auf Groß- und Kleinschreibung.
static func named(list: Array, wanted: String, key := "name") -> Dictionary:
	for exact in [true, false]:
		for x in list:
			if x["id"] == wanted or (not exact and str(x.get(key, "")).to_lower() == wanted.to_lower()):
				return x
	return {}


## Eine Aufgabe zu „$142“ oder „142“.
static func by_ref(ws: Workspace, wanted: String) -> Variant:
	var number := wanted.strip_edges().trim_prefix("$")
	if not number.is_valid_int():
		return ws.task(wanted)
	for t in ws.tasks:
		if int(t.get("ref", 0)) == int(number):
			return t
	return null


static func _in_project(list: Array, project_id: String) -> Array:
	return list.filter(func(x: Dictionary) -> bool: return x.get("projectId", project_id) == project_id)


static func _choices(list: Array) -> String:
	return ", ".join(list.map(func(x: Dictionary) -> String: return "„%s“" % x.get("name", ""))) if not list.is_empty() else "keine"


static func _name_of(x: Variant) -> String:
	return "„%s“" % x.get("name", "") if x != null else "keine"


static func _label(t: Variant) -> String:
	return "$%d %s" % [int(t.get("ref", 0)), t.get("title", "")] if t != null else "?"
