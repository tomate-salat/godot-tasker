extends RefCounted
## Nebenquests auf der Feldzugskarte (Nutzer, 2026-10-24; PLAN.md, „Ausbau:
## Nebenquests“). Eine Nebenquest, die für das aktive Release läuft oder
## erledigt ist, steht als Stellung um die Festung: ein Gerät, das mit den
## Schritten der Aufgabe aufgebaut wird und feuert, sobald sie erledigt ist.
##
## - Welche Stellung, hängt an der Größe – Unteraufgaben plus alle Kästchen:
##   ohne Unteraufgaben ein Mörser (bis `SMALL`) oder ein Raketenwerfer, mit
##   Unteraufgaben eine Feuerstellung (unter `LARGE`) oder ein Flugplatz.
##   Größere Nebenquests sollen sich nach mehr Belohnung anfühlen.
## - Jedes Gerät hat eine feste Reihe Bauteile (`PARTS`). Zu sehen ist der
##   Anteil, der dem Anteil der erledigten Schritte entspricht; die Pflöcke
##   stehen ab „In Arbeit“, das letzte Teil kommt erst mit „Erledigt“.
## - In Feuerstellung und Flugplatz ist jede Unteraufgabe ein eigenes Gerät
##   (Geschütz oder Jet), gebaut nach ihren eigenen Schritten.
##
## Stempel und Bonus rechnet `release.gd` nach Tasker; hier steht nur, was die
## Karte daraus macht, und welche Statusänderung Ziehen und Zurückziehen sind.

const Model := preload("model.gd")
const Checklist := preload("checklist.gd")
const Release := preload("release.gd")
const Workspace := preload("workspace.gd")

const MORTAR := "mortar"
const ROCKET := "rocket"
const BATTERY := "battery"
const AIRFIELD := "airfield"
const JET := "jet"

## Bis zu dieser Größe ist eine Nebenquest ohne Unteraufgaben ein Mörser.
const SMALL := 3
## Ab dieser Größe wird eine Nebenquest mit Unteraufgaben zum Flugplatz.
## Ein Startwert – nachjustieren, wenn es sich falsch anfühlt.
const LARGE := 12

## So viele Bauteile hat jedes Gerät. Feuerstellung und Flugplatz bauen mit
## ihren eigenen Kästchen nur Wall bzw. Bahn; die Geräte darin bauen sich selbst.
const PARTS := {MORTAR: 5, ROCKET: 8, BATTERY: 4, AIRFIELD: 4, JET: 6}


## Wie groß eine Nebenquest ist: ihre Unteraufgaben (alle Ebenen) plus alle
## Kästchen, die eigenen und die darunter.
static func size_of(ws: Workspace, t: Dictionary) -> int:
	var n: int = Checklist.count(t.get("desc", ""))["total"]
	for k in ws.desc(t):
		n += 1 + int(Checklist.count(k.get("desc", ""))["total"])
	return n


## Welches Gerät eine Nebenquest ist.
static func kind_of(ws: Workspace, t: Dictionary) -> String:
	var size := size_of(ws, t)
	if ws.kids(t["id"]).is_empty():
		return MORTAR if size <= SMALL else ROCKET
	return BATTERY if size < LARGE else AIRFIELD


## Die Schritte einer Aufgabe: `{ total, done }`. Die Kästchen zählen, und
## jede Unteraufgabe mit ihren eigenen Schritten und einem für sich selbst.
## Was erledigt ist, zählt ganz.
static func steps(ws: Workspace, t: Dictionary) -> Dictionary:
	var boxes: Dictionary = Checklist.count(t.get("desc", ""))
	var total: int = boxes["total"]
	var done: int = boxes["done"]
	for k in ws.kids(t["id"]):
		var inner := steps(ws, k)
		total += 1 + int(inner["total"])
		done += (1 + int(inner["total"])) if Model.is_done(k) else int(inner["done"])
	if Model.is_done(t):
		done = total
	return {"total": total, "done": done}


## Wie viele der `parts` Bauteile stehen: die Pflöcke ab dem Beginn, dann der
## Anteil der Schritte, das letzte Teil erst, wenn die Aufgabe erledigt ist.
## Bei vielen Kästchen braucht ein Bauteil mehrere, bei wenigen bringt ein
## Kästchen mehrere.
static func built(done: int, total: int, parts: int, finished: bool) -> int:
	if finished:
		return parts
	if total <= 0:
		return 1
	return clampi(1 + int(floor(float(parts - 2) * done / total)), 1, parts - 1)


## Die Stellungen des Releases, in fester Reihenfolge (nach Nummer). Je
## Stellung `{ id, task, kind, size, steps, parts, built, done, units }`;
## `units` sind die Geräte darin – je Unteraufgabe `{ id, task, kind, parts,
## built, done, earlier }`, `earlier` das Release, in dem sie schon erledigt
## wurde, sonst null.
static func positions(ws: Workspace, release: Dictionary) -> Array:
	var id: String = release["id"]
	var stamped := ws.tasks.filter(func(t: Dictionary) -> bool:
		return t.get("releasedIn") == id and not Model.is_archived(t) and Release.is_bonus(ws, t))
	var mine := {}
	for t in stamped:
		mine[t["id"]] = true
	# Der Server stempelt die Vorfahren mit: die Stellung ist die oberste gestempelte Aufgabe.
	var roots := stamped.filter(func(t: Dictionary) -> bool: return not mine.has(t.get("parentId")))
	roots = Model.stable_sort(roots, func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("ref", 0)) < int(b.get("ref", 0)))
	var out := []
	for t in roots:
		var kind := kind_of(ws, t)
		var parts: int = PARTS[kind]
		var finished := Model.is_done(t)
		var all := steps(ws, t)
		var units := []
		var own: Dictionary = Checklist.count(t.get("desc", ""))
		if kind == BATTERY or kind == AIRFIELD:
			for k in ws.kids(t["id"]):
				var unit_kind := JET if kind == AIRFIELD else MORTAR if size_of(ws, k) <= SMALL else ROCKET
				var s := steps(ws, k)
				var earlier: Variant = k.get("releasedIn") if Model.is_done(k) and k.get("releasedIn") and k.get("releasedIn") != id else null
				units.append({"id": k["id"], "task": k, "kind": unit_kind, "parts": PARTS[unit_kind],
					"built": built(s["done"], s["total"], PARTS[unit_kind], Model.is_done(k)), "done": Model.is_done(k), "earlier": earlier})
		# Wall und Bahn bauen sich aus den eigenen Kästchen; ohne Kästchen stehen sie, sobald es losgeht.
		var frame: int = built(own["done"], own["total"], parts, finished) if kind == BATTERY or kind == AIRFIELD else built(all["done"], all["total"], parts, finished)
		if (kind == BATTERY or kind == AIRFIELD) and own["total"] == 0:
			frame = parts
		out.append({"id": t["id"], "task": t, "kind": kind, "size": size_of(ws, t), "steps": all, "parts": parts,
			"built": frame, "done": finished, "units": units})
	return out


## Die Nebenquests, die sich noch auf die Festung ziehen lassen: die
## Wurzelaufgaben der Nebenquest-Gruppe in Taskers Reihenfolge, ohne das, was
## schon für `release` läuft oder erledigt ist.
static func reserve(ws: Workspace, project_id: String, release: Variant) -> Array:
	var group = Release.sidequests(ws, project_id)
	if group == null:
		return []
	var list := ws.tasks.filter(func(t: Dictionary) -> bool:
		return t.get("groupId") == group["id"] and not t.get("parentId") and not t.get("milestoneId") \
			and not Model.is_archived(t) and not Model.is_done(t) \
			and not (release != null and t.get("releasedIn") == release["id"]))
	return Model.stable_sort(list, Model.by_order)


## Was das Ziehen auf die Festung ändert: `{ changes: { task_id: { status } },
## refusal }`. Eine Aufgabe ohne Unteraufgaben geht in Arbeit; bei einem
## Stapel die erste bereite Unteraufgabe ganz unten – den Stapel selbst stellt
## Tasker nach. Gestempelt wird am Server.
static func deploy(ws: Workspace, t: Dictionary) -> Dictionary:
	var leaves := _leaves(ws, t)
	if leaves.size() == 1 and leaves[0]["id"] == t["id"]:
		if t.get("status") == "ready" or t.get("status") == "unclear":
			return {"changes": {t["id"]: {"status": "progress"}}, "refusal": ""}
		if t.get("status") == "progress":
			return {"changes": {}, "refusal": ""}
		return {"changes": {}, "refusal": "„%s“ ist noch nicht fertig geplant – erst auf „Bereit“ setzen" % _title(t)}
	for leaf in leaves:
		if leaf.get("status") == "progress":
			return {"changes": {}, "refusal": ""}
	for leaf in leaves:
		if leaf.get("status") == "ready" or leaf.get("status") == "unclear":
			return {"changes": {leaf["id"]: {"status": "progress"}}, "refusal": ""}
	return {"changes": {}, "refusal": "In „%s“ ist keine Unteraufgabe bereit" % _title(t)}


## Was das Zurückziehen ändert: alles, was läuft, zurück auf „Bereit“ – dann
## nimmt der Server den Stempel. Ist schon etwas erledigt, gehört das zum
## Release; dann bleibt die Stellung stehen.
static func withdraw(ws: Workspace, t: Dictionary) -> Dictionary:
	if Model.is_done(t) or ws.desc(t).any(Model.is_done):
		return {"changes": {}, "refusal": "„%s“ ist schon teils erledigt und gehört damit zum Release" % _title(t)}
	var changes := {}
	for leaf in _leaves(ws, t):
		if leaf.get("status") == "progress":
			changes[leaf["id"]] = {"status": "ready"}
	return {"changes": changes, "refusal": ""}


## Die Aufgaben ganz unten, in Baumreihenfolge; ohne Unteraufgaben die Aufgabe selbst.
static func _leaves(ws: Workspace, t: Dictionary) -> Array:
	var kids := ws.kids(t["id"])
	if kids.is_empty():
		return [t]
	var out := []
	for k in kids:
		out.append_array(_leaves(ws, k))
	return out


## Die Kästchen einer Aufgabe als Texte, in Reihenfolge: `[{ text, done }]`.
static func boxes(t: Dictionary) -> Array:
	var cl := Checklist.lines_of(t.get("desc", ""))
	var out := []
	for i in cl["out"]:
		var line: String = cl["lines"][i]
		var at := line.find("]")
		out.append({"text": line.substr(at + 1).strip_edges() if at >= 0 else line.strip_edges(), "done": Checklist.line_done(line)})
	return out


static func _title(t: Dictionary) -> String:
	return t["title"] if t.get("title") else "Ohne Titel"
