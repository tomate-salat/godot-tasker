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
## hat – ein Milestone oder schon ein Kanal.
static func status(ws: Workspace, r: Dictionary) -> String:
	var stages := ws.release_stages(r["id"])
	var milestones := ws.release_milestones(r["id"])
	if stages.size() > 0 and stages.all(func(s: Dictionary) -> bool: return s.get("doneAt") != null):
		return RELEASED
	if milestones.size() > 0 and milestones.all(func(m: Dictionary) -> bool: return Progress.milestone_done(ws, m)):
		return READY
	var begun := stages.any(func(s: Dictionary) -> bool: return s.get("doneAt") != null) \
		or milestones.any(func(m: Dictionary) -> bool: return m.get("status") == "progress" or Progress.milestone_done(ws, m))
	return PROGRESS if begun else PLANNED


## Das Release, an dem im Projekt gerade gearbeitet wird: das erste in der
## Reihenfolge, das nicht veröffentlicht ist und einen aktiven Milestone hat.
## Gibt es das nicht, das erste unveröffentlichte mit Milestones. Sonst null.
static func active(ws: Workspace, project_id: String) -> Variant:
	var open := ws.releases.filter(func(r: Dictionary) -> bool:
		return r.get("projectId") == project_id and not Model.is_archived(r) \
			and status(ws, r) != RELEASED and ws.release_milestones(r["id"]).size() > 0)
	open = Model.stable_sort(open, func(a: Dictionary, b: Dictionary) -> bool: return a.get("order", 0) < b.get("order", 0))
	for r in open:
		if ws.release_milestones(r["id"]).any(func(m: Dictionary) -> bool: return m.get("status") == "progress"):
			return r
	return open[0] if open.size() > 0 else null


## Wie ein Release heißt: Version und Titel, soweit vorhanden.
static func label(r: Dictionary) -> String:
	var name: String = str(r.get("name", "")).strip_edges()
	var title: String = str(r.get("title", "")).strip_edges()
	if name != "" and title != "":
		return "%s · %s" % [name, title]
	return name if name != "" else title if title != "" else "Release"
