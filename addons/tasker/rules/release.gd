extends RefCounted
## Releases: mehrere Milestones, die zusammen veröffentlicht werden. Das Addon
## liest sie nur. Der Stand eines Releases ist nicht gespeichert, er ergibt
## sich aus seinen Milestones und Kanälen – nach Taskers `shared/release.ts`.

const Model := preload("model.gd")
const Progress := preload("progress.gd")
const Workspace := preload("workspace.gd")

const PLANNED := "planned"
const PROGRESS := "progress"
const READY := "ready"
const RELEASED := "released"

const LABEL := {
	PLANNED: "Geplant",
	PROGRESS: "In Arbeit",
	READY: "Bereit",
	RELEASED: "Veröffentlicht",
}


## Veröffentlicht ist ein Release, wenn alle Kanäle abgehakt sind; bereit, wenn
## alle Milestones fertig sind. In Arbeit ist es, sobald irgendetwas begonnen
## hat – ein Milestone, ein Kanal oder eine gestempelte Aufgabe. Ein Release
## ganz ohne Milestones wird nie bereit.
static func status(ws: Workspace, r: Dictionary) -> String:
	var stages := ws.release_stages(r["id"])
	var milestones := ws.release_milestones(r["id"])
	# Archivierte Milestones gelten als fertig, wie in Tasker.
	var archived := archived_milestones(r).size()
	if _released(ws, r):
		return RELEASED
	if milestones.size() + archived > 0 and milestones.all(func(m: Dictionary) -> bool: return Progress.milestone_done(ws, m)):
		return READY
	var begun := archived > 0 or archived_bonus(r) > 0 \
		or ws.tasks.any(func(t: Dictionary) -> bool: return t.get("releasedIn") == r["id"]) \
		or stages.any(func(s: Dictionary) -> bool: return s.get("doneAt") != null) \
		or milestones.any(func(m: Dictionary) -> bool: return m.get("status") == "progress" or Progress.milestone_done(ws, m))
	return PROGRESS if begun else PLANNED


static func _released(ws: Workspace, r: Dictionary) -> bool:
	var stages := ws.release_stages(r["id"])
	return stages.size() > 0 and stages.all(func(s: Dictionary) -> bool: return s.get("doneAt") != null)


## Das aktive Release eines Projekts. Dafür stempelt der Server, also folgt es
## genau Taskers `pickActiveRelease`: unter den nicht archivierten, nicht
## veröffentlichten Releases nach `order`, bei Gleichstand nach ID, das erste
## mit laufendem Milestone – sonst das erste überhaupt, auch ohne Milestones.
static func active(ws: Workspace, project_id: String) -> Variant:
	var open := ws.releases.filter(func(r: Dictionary) -> bool:
		return r.get("projectId") == project_id and not Model.is_archived(r) and not _released(ws, r))
	open = Model.stable_sort(open, func(a: Dictionary, b: Dictionary) -> bool:
		if a.get("order", 0) != b.get("order", 0):
			return a.get("order", 0) < b.get("order", 0)
		return str(a["id"]) < str(b["id"]))
	for r in open:
		if ws.release_milestones(r["id"]).any(func(m: Dictionary) -> bool: return m.get("status") == "progress"):
			return r
	return open[0] if open.size() > 0 else null


## Mit welchem Release eine Aufgabe rausgeht: liegt sie in einem Milestone mit
## Release, mit dessen; sonst mit dem, das sie gestempelt hat (`releasedIn`,
## setzt allein der Server). Taskers `taskRelease`.
static func task_release(ws: Workspace, t: Dictionary) -> Variant:
	var m = ws.milestone_of(t)
	var r = ws.release_of(m) if m != null else null
	return r["id"] if r != null else t.get("releasedIn")


## Bonus: gestempelt, aber in keinem Release-Milestone – zählt nicht dafür,
## dass das Release bereit ist (Nebenquests und andere lose Aufgaben).
static func is_bonus(ws: Workspace, t: Dictionary) -> bool:
	if not t.get("releasedIn"):
		return false
	var m = ws.milestone_of(t)
	return not (m != null and ws.release_of(m) != null)


## Die Bonus-Aufgaben eines Releases im aktiven Bestand, gezählt wie der
## Fortschritt: nur Blätter, also Aufgaben ohne gestempelte Unteraufgaben.
## Archiviertes bringt das Release mit (`archived_bonus`). Taskers `releaseBonus`.
static func bonus(ws: Workspace, r: Dictionary) -> Dictionary:
	var tasks := ws.tasks.filter(func(t: Dictionary) -> bool:
		return t.get("releasedIn") == r["id"] and not Model.is_archived(t) and is_bonus(ws, t))
	var stamped := {}
	for t in tasks:
		stamped[t["id"]] = true
	var leaves := tasks.filter(func(t: Dictionary) -> bool:
		return not ws.kids(t["id"]).any(func(k: Dictionary) -> bool: return stamped.has(k["id"])))
	var done := leaves.filter(Model.is_done).size()
	return {"done": done, "open": leaves.size() - done, "tasks": tasks}


## Erledigte Bonus-Aufgaben, die nicht mehr im aktiven Bestand sind.
static func archived_bonus(r: Dictionary) -> int:
	return int(r.get("archivedBonus", 0))


## Die Nebenquests eines Projekts: die eine Gruppe mit `kind: "sidequest"`.
## Der Server legt sie an; null, solange er das nicht getan hat.
static func sidequests(ws: Workspace, project_id: String) -> Variant:
	for g in ws.groups:
		if g.get("projectId") == project_id and g.get("kind") == "sidequest":
			return g
	return null


## Die archivierten Milestones, die zum Release zählen – Tasker liefert sie am
## Release mit, weil der übrige Stand nur Aktives kennt: je `{ id, ref, title,
## done, total, deps, dependents, inherited }`, ohne Aufgaben.
static func archived_milestones(r: Dictionary) -> Array:
	var list: Variant = r.get("archivedMilestones", [])
	return list if list is Array else []


## Wie ein Release heißt: Version und Titel, soweit vorhanden.
static func label(r: Dictionary) -> String:
	var name: String = str(r.get("name", "")).strip_edges()
	var title: String = str(r.get("title", "")).strip_edges()
	if name != "" and title != "":
		return "%s · %s" % [name, title]
	return name if name != "" else title if title != "" else "Release"
