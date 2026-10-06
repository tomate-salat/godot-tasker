extends RefCounted
## Fortschritt, aus Taskers `shared/progress.ts`.
##
## Gezählt werden Aufgaben, nicht Punkte: jede Aufgabe ohne Unteraufgaben
## zählt 1, eine Sammel-Aufgabe zählt die Summe ihrer Unteraufgaben.

const Model := preload("model.gd")
const Checklist := preload("checklist.gd")
const Workspace := preload("workspace.gd")


static func total(ws: Workspace, t: Dictionary) -> int:
	var kids := ws.counted_kids(t["id"])
	if kids.is_empty():
		return 1
	var sum := 0
	for k in kids:
		sum += total(ws, k)
	return sum


## Erledigte Aufgaben darunter.
static func done_count(ws: Workspace, t: Dictionary) -> int:
	if Model.is_done(t):
		return total(ws, t)
	var sum := 0
	for k in ws.counted_kids(t["id"]):
		sum += done_count(ws, k)
	return sum


## Erledigt oder nur noch aus erledigten Unteraufgaben bestehend.
static func all_done(ws: Workspace, t: Dictionary) -> bool:
	if Model.is_done(t):
		return true
	var kids := ws.counted_kids(t["id"])
	if kids.is_empty():
		return false
	for k in kids:
		if not all_done(ws, k):
			return false
	return true


## Für die Balken: erledigte Aufgaben zählen voll, offene anteilig nach ihrer
## eigenen Checkliste.
static func progress_units(ws: Workspace, t: Dictionary) -> float:
	if Model.is_done(t):
		return float(total(ws, t))
	var kids := ws.counted_kids(t["id"])
	var own := Checklist.count(t.get("desc"))
	var units := 0.0
	if own["total"] > 0 and kids.is_empty():
		units = float(own["done"]) / own["total"]
	for k in kids:
		units += progress_units(ws, k)
	return units


## `{ total, done, open, count, is_done, tasks_done }`
static func milestone_stats(ws: Workspace, m: Dictionary) -> Dictionary:
	var roots := ws.ms_counted(m)
	var tot := 0
	var dn := 0
	var tasks_done := roots.size() > 0
	for r in roots:
		tot += total(ws, r)
		dn += done_count(ws, r)
		if not all_done(ws, r):
			tasks_done = false
	var done: bool = m.get("status") == "done"
	return {
		"total": tot,
		"done": dn,
		"open": 0 if done else tot - dn,
		"count": roots.size(),
		"is_done": done,
		"tasks_done": tasks_done,
	}


## Fertig im Sinne von Abhängigkeiten: ausdrücklich auf „erledigt“ gesetzt
## oder alle Aufgaben erledigt.
static func milestone_done(ws: Workspace, m: Dictionary) -> bool:
	var stats := milestone_stats(ws, m)
	return stats["is_done"] or stats["tasks_done"]


static func milestone_progress_pct(ws: Workspace, m: Dictionary) -> int:
	if m.get("status") == "done":
		return 100
	var roots := ws.ms_counted(m)
	var tot := 0
	var units := 0.0
	for r in roots:
		tot += total(ws, r)
		units += progress_units(ws, r)
	if tot > 0:
		return roundi(units / tot * 100.0)
	var own := Checklist.count(m.get("desc"))
	var parts: int = own["total"] + roots.size()
	if parts == 0:
		return 0
	var done: int = own["done"]
	for r in roots:
		if all_done(ws, r):
			done += 1
	return roundi(float(done) / parts * 100.0)


## Ein Segment je Checklisten-Punkt des Objekts und je Blatt-Aufgabe darunter:
## `{ kind = "checklist", done }` oder `{ kind = "task", status }`.
static func status_segments(ws: Workspace, x: Dictionary) -> Array:
	var segs := []
	var cl := Checklist.lines_of(x.get("desc"))
	for i in cl["out"]:
		segs.append({"kind": "checklist", "done": Checklist.line_done(cl["lines"][i])})
	var roots := ws.ms_counted(x) if Model.is_milestone(x) else ws.counted_kids(x["id"])
	for r in roots:
		_walk_segments(ws, r, segs)
	return segs


static func _walk_segments(ws: Workspace, t: Dictionary, segs: Array) -> void:
	var kids := ws.counted_kids(t["id"])
	if kids.is_empty():
		segs.append({"kind": "task", "status": t.get("status")})
		return
	for k in kids:
		_walk_segments(ws, k, segs)
