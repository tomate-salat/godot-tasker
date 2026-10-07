extends RefCounted
## Planen am Tisch: was in welchem Deck liegt, was im Vorrat, und welche Karte
## ein Schloss trägt. Gezeichnet wird in `ui/plan_view.gd`.
##
## Decks sind die eingeplanten Milestones in Plan-Reihenfolge. Der Vorrat ist
## alles Uneingeplante, geteilt wie in Tasker (`shared/outline.ts`): „Ready“
## sind lose Wurzeln mit `ready`, gegliedert nach Markierung, sonst nach
## Kategorie. Alles andere ist Backlog: Gruppen, nicht eingeplante Milestones
## und „Unsortiert“.

const Model := preload("model.gd")
const Blocking := preload("blocking.gd")
const Workspace := preload("workspace.gd")

const READY := "ready"
const BACKLOG := "backlog"

## Die Karte wartet auf etwas …
const WAITS := "waits"
## … das in einem späteren Deck oder noch im Vorrat liegt.
const MISPLACED := "misplaced"


## Die Decks eines Projekts in Plan-Reihenfolge.
static func decks(ws: Workspace, project_id: String) -> Array:
	return ws.planned_milestones().filter(func(m: Dictionary) -> bool: return m["projectId"] == project_id)


## Lose Wurzel: hängt an nichts und ist kein Dokument.
static func is_loose_root(t: Dictionary) -> bool:
	return not t.get("parentId") and not t.get("milestoneId") and not t.get("groupId") and not t.get("doc", false)


## Ein Stapel des Vorrats als Abschnitte in Reihenfolge: `{ title, cards }`.
## Leere Abschnitte fehlen.
static func stock(ws: Workspace, project_id: String, which: String) -> Array:
	var loose := _sorted(ws.tasks.filter(func(t: Dictionary) -> bool:
		return t["projectId"] == project_id and is_loose_root(t) and ws.is_active(t)))
	var out := []
	if which == READY:
		var ready := loose.filter(func(t: Dictionary) -> bool: return t.get("ready", false))
		for k in _sorted(ws.marks.filter(func(x: Dictionary) -> bool: return x["projectId"] == project_id)):
			_section(out, "%s %s" % [k.get("emoji", ""), k.get("name", "")],
				ready.filter(func(t: Dictionary) -> bool: return t.get("markId") == k["id"]))
		var plain := ready.filter(func(t: Dictionary) -> bool: return not t.get("markId"))
		for c in _sorted(ws.categories.filter(func(x: Dictionary) -> bool: return x["projectId"] == project_id)):
			_section(out, str(c.get("name", "")), plain.filter(func(t: Dictionary) -> bool: return t.get("categoryId") == c["id"]))
		# Eine Kategorie aus einem anderen Projekt zählt wie keine.
		_section(out, "Ohne Kategorie", plain.filter(func(t: Dictionary) -> bool:
			var c = ws.category(t.get("categoryId"))
			return c == null or c["projectId"] != project_id))
		return out

	for g in _sorted(ws.groups.filter(func(x: Dictionary) -> bool: return x["projectId"] == project_id and not Model.is_archived(x))):
		_section(out, str(g.get("title", "")) if g.get("title") else "Neue Gruppe", _sorted(ws.tasks.filter(func(t: Dictionary) -> bool:
			return t.get("groupId") == g["id"] and not t.get("parentId") and ws.is_active(t))))
	for m in _sorted(ws.milestones.filter(func(x: Dictionary) -> bool:
			return x["projectId"] == project_id and not x.get("planned", false) and not Model.is_archived(x))):
		_section(out, "◆ %s" % (m["title"] if m.get("title") else "Ohne Titel"), ws.ms_roots(m))
	_section(out, "Unsortiert", loose.filter(func(t: Dictionary) -> bool: return not t.get("ready", false)))
	return out


## Wie viele Karten in einem Stapel des Vorrats liegen.
static func stock_count(ws: Workspace, project_id: String, which: String) -> int:
	var n := 0
	for section in stock(ws, project_id, which):
		n += section["cards"].size()
	return n


## Worauf die Karte samt allem darunter noch wartet – ohne das, was in ihr
## selbst liegt: Aufgaben und Milestones.
static func card_blockers(ws: Workspace, t: Dictionary) -> Array:
	var inside := {t["id"]: true}
	var all := [t] + ws.desc(t)
	for x in all:
		inside[x["id"]] = true
	var out := []
	for x in all:
		for b in Blocking.blockers(ws, x):
			if not inside.has(b["id"]) and not out.any(func(o: Dictionary) -> bool: return o["id"] == b["id"]):
				out.append(b)
	return out


## Das Schloss der Karte: leer, `WAITS` oder `MISPLACED`. `order` sagt zu
## jedem Deck seinen Platz in der Reihe (Milestone-ID → Zahl).
##
## Rot (`MISPLACED`) wird es nur an Karten, die schon in einem Deck liegen
## und auf etwas warten, das später oder gar nicht eingeplant ist.
static func lock_of(ws: Workspace, t: Dictionary, order: Dictionary) -> String:
	var blockers := card_blockers(ws, t)
	if blockers.is_empty():
		return ""
	var own := place(ws, t, order)
	if own < 0:
		return WAITS
	for b in blockers:
		var at: int = order.get(b["id"], -1) if Model.is_milestone(b) else place(ws, b, order)
		if at < 0 or at > own:
			return MISPLACED
	return WAITS


## Der Platz des Decks, in dem die Aufgabe liegt – -1 für den Vorrat.
static func place(ws: Workspace, t: Dictionary, order: Dictionary) -> int:
	var m = ws.milestone_of(t)
	return order.get(m["id"], -1) if m != null else -1


## Milestone-ID → Platz in der Reihe, für `lock_of`.
static func deck_order(list: Array) -> Dictionary:
	var out := {}
	for i in list.size():
		out[list[i]["id"]] = i
	return out


static func _section(out: Array, title: String, cards: Array) -> void:
	if not cards.is_empty():
		out.append({"title": title.strip_edges(), "cards": cards})


static func _sorted(list: Array) -> Array:
	return Model.stable_sort(list, Model.by_order)
