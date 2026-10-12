extends RefCounted
## Abhängigkeiten zwischen Aufgaben anlegen und lösen – im Lageplan, indem
## man ein Abzeichen auf ein anderes fallen lässt. „A wartet auf B“ heißt:
## B steht in `A.deps`.

const Workspace := preload("workspace.gd")


## Warum `a` nicht auf `b` warten kann – leer, wenn es geht.
static func link_refusal(ws: Workspace, a: Dictionary, b: Dictionary) -> String:
	if a["id"] == b["id"]:
		return "Eine Aufgabe wartet nicht auf sich selbst"
	if a.get("deps", []).has(b["id"]):
		return "Wartet schon darauf"
	var above_a := ws.ancestors(a).map(func(t: Dictionary) -> String: return t["id"])
	var above_b := ws.ancestors(b).map(func(t: Dictionary) -> String: return t["id"])
	if above_a.has(b["id"]) or above_b.has(a["id"]):
		return "Stapel und Unteraufgabe hängen ohnehin zusammen"
	if _waits_on(ws, b, a["id"], {}):
		return "Das ergäbe einen Kreis: „%s“ wartet schon auf „%s“" % [_name(b), _name(a)]
	return ""


## Die Abhängigkeiten von `a`, wenn es zusätzlich auf `b_id` wartet.
static func with_dep(a: Dictionary, b_id: String) -> Array:
	var deps: Array = a.get("deps", []).duplicate()
	if not deps.has(b_id):
		deps.append(b_id)
	return deps


## Die Abhängigkeiten von `a`, wenn es nicht mehr auf `b_id` wartet.
static func without_dep(a: Dictionary, b_id: String) -> Array:
	return a.get("deps", []).filter(func(id: String) -> bool: return id != b_id)


## Wartet `t` – direkt oder über andere – auf die Aufgabe `target_id`?
static func _waits_on(ws: Workspace, t: Dictionary, target_id: String, seen: Dictionary) -> bool:
	if seen.has(t["id"]):
		return false
	seen[t["id"]] = true
	for dep_id in t.get("deps", []):
		if dep_id == target_id:
			return true
		var dep = ws.task(dep_id)
		if dep != null and _waits_on(ws, dep, target_id, seen):
			return true
	return false


static func _name(t: Dictionary) -> String:
	return t["title"] if t.get("title") else "Ohne Titel"
