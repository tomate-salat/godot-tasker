extends RefCounted
## Das Feld: der aktive Milestone als Kampf. In der Mitte sitzt der große
## Käfer des Milestones, die Karten liegen in Ringen um ihn.
##
## - Was eine Karte braucht, liegt einen Ring weiter außen: ihre
##   Voraussetzungen und, bei einem Stapel, ihre Unteraufgaben – auch die
##   müssen ja erledigt sein, bevor er es ist. Im innersten Ring liegt, woran
##   nichts mehr hängt. So führt von jeder Karte ein Weg zur Mitte.
## - Auf einer Karte sitzt für alles, was sie noch braucht, ein Schädling.
## - Eine Karte in Arbeit („getappt“) schickt einen Marienkäfer zu jedem
##   Schädling, den sie stellt – im innersten Ring zum großen Käfer.
## - Ist sie erledigt, sind ihre Schädlinge besiegt.
##
## Nichts davon wird gespeichert: alles ergibt sich aus Status, Unteraufgaben,
## Abhängigkeiten und Kästchen. Tasker selbst kennt das Feld nicht.

const Model := preload("model.gd")
const Checklist := preload("checklist.gd")
const Blocking := preload("blocking.gd")
const Progress := preload("progress.gd")
const ParentStatus := preload("parent_status.gd")
const Workspace := preload("workspace.gd")


## Das ganze Feld eines Milestones:
##
## - `nodes`: je Karte `{ id, task, ring, inner }`. `ring` zählt von innen,
##   ab 1. `inner` ist die Karte, zu der sie nach innen gehört – die auf sie
##   wartet oder deren Unteraufgabe sie ist –, leer für die Mitte.
## - `ways`: die Verbindungen nach innen, `{ from, to }`; `to` ist leer für
##   die Mitte. Umwege fehlen: führt A zu B und B zu C, steht A zu C nicht da.
## - `pests`: je Karte die Schädlinge darauf, siehe `pests_on`.
## - `fronts`: je Karte in Arbeit, wohin ihr Marienkäfer geht, siehe `fronts_of`.
## - `boss`: `{ total, done }` – der große Käfer.
## - `front`: der äußerste Ring, auf dem noch eine Karte offen ist – bis dorthin
##   ist das Feld von außen her eingenommen. 0, wenn alles erledigt ist.
static func build(ws: Workspace, m: Dictionary) -> Dictionary:
	var tasks := []
	for r in ws.ms_roots(m):
		if ws.is_doc(r):
			continue
		tasks.append(r)
		tasks.append_array(ws.desc(r))
	var here := {}
	for t in tasks:
		here[t["id"]] = t

	# Wohin jede Karte nach innen führt: zu ihrem Stapel und zu allem, was auf sie wartet.
	var inward := {}
	for t in tasks:
		inward[t["id"]] = []
	for t in tasks:
		var parent = t.get("parentId")
		if parent and here.has(parent):
			inward[t["id"]].append(parent)
		for dep_id in t.get("deps", []):
			if here.has(dep_id) and dep_id != t["id"] and not inward[dep_id].has(t["id"]):
				inward[dep_id].append(t["id"])

	var rings := {}
	for t in tasks:
		_ring_of(t["id"], inward, rings, {})

	var nodes := []
	var ways := []
	var pests := {}
	for t in tasks:
		var id: String = t["id"]
		# Nach innen gehört die Karte zu dem, was am weitesten außen auf sie wartet.
		var inner := ""
		for other in inward[id]:
			if inner == "" or rings[other] > rings[inner]:
				inner = other
		nodes.append({"id": id, "task": t, "ring": rings[id], "inner": inner})
		if inward[id].is_empty():
			ways.append({"from": id, "to": ""})
		for other in inward[id]:
			var around := false
			for via in inward[id]:
				if via != other and _leads(via, other, inward, {}):
					around = true
			if not around:
				ways.append({"from": id, "to": other})
		var on := pests_on(ws, t)
		if on.size() > 0:
			pests[id] = on

	var fronts := {}
	for t in tasks:
		if is_tapped(t):
			fronts[t["id"]] = fronts_of(t, pests)

	var stats := Progress.milestone_stats(ws, m)
	var front := 0
	for n in nodes:
		if not Model.is_done(n["task"]):
			front = maxi(front, n["ring"])
	return {"nodes": nodes, "ways": ways, "pests": pests, "fronts": fronts, "front": front, "boss": {"total": stats["total"], "done": stats["done"]}}


## An der Karte wird gearbeitet.
static func is_tapped(t: Dictionary) -> bool:
	return t.get("status") == "progress" and not Model.is_done(t)


## Die Schädlinge auf einer Karte: einer für alles, was sie noch braucht,
## `{ blocker_id, title, engaged, damage, wall }`.
##
## - Je offener Voraussetzung einer, und bei einem Stapel je offener
##   Unteraufgabe einer.
## - `engaged`: an dem, was fehlt, wird gerade gearbeitet.
## - `damage`: wie weit es ist, 0 bis 1.
## - `wall`: die Karte selbst steht auf „Blockiert“; daran ändert keine andere
##   Karte etwas.
static func pests_on(ws: Workspace, t: Dictionary) -> Array:
	var out := []
	if Model.is_done(t):
		return out
	var missing := Blocking.own_blockers(ws, t)
	for k in ws.kids(t["id"]):
		if not Model.is_done(k):
			missing.append(k)
	for x in missing:
		out.append({
			"blocker_id": x["id"],
			"title": x["title"] if x.get("title") else "Ohne Titel",
			"engaged": engaged(ws, x),
			"damage": damage(ws, x),
			"wall": false,
		})
	if t.get("status") == "blocked":
		out.append({"blocker_id": "", "title": "Blockiert", "engaged": false, "damage": 0.0, "wall": true})
	return out


## Wird an `x` gearbeitet? Bei einem Stapel reicht eine Karte darunter.
static func engaged(ws: Workspace, x: Dictionary) -> bool:
	if Model.is_milestone(x) or Model.is_done(x):
		return false
	if is_tapped(x):
		return true
	return ws.desc(x).any(is_tapped)


## Wie weit `x` ist, 0 bis 1: abgehakte Kästchen und erledigte Unteraufgaben.
static func damage(ws: Workspace, x: Dictionary) -> float:
	if Model.is_milestone(x):
		var stats := Progress.milestone_stats(ws, x)
		return float(stats["done"]) / maxi(stats["total"], 1)
	if Model.is_done(x):
		return 1.0
	if ws.counted_kids(x["id"]).is_empty():
		# Ohne Kästchen gibt es nur den einen Schlag: das Erledigen.
		var own := Checklist.count(x.get("desc"))
		return float(own["done"]) / own["total"] if own["total"] > 0 else 0.0
	return Progress.progress_units(ws, x) / maxi(Progress.total(ws, x), 1)


## Wohin der Marienkäfer einer Karte in Arbeit geht: zu jedem Schädling, den
## sie stellt – `[{ on, blocker_id }]`. Leer heißt: zum großen Käfer.
static func fronts_of(t: Dictionary, pests: Dictionary) -> Array:
	var out := []
	for card_id in pests:
		for p in pests[card_id]:
			if p["blocker_id"] == t["id"]:
				out.append({"on": card_id, "blocker_id": t["id"]})
	return out


## Warum sich eine Karte nicht tappen lässt – leer heißt: sie lässt sich.
static func tap_refusal(ws: Workspace, t: Dictionary) -> String:
	if Model.is_done(t):
		return "Die Karte ist schon erledigt"
	if ws.kids(t["id"]).size() > 0:
		return "An einem Stapel arbeitet man über seine Unteraufgaben – die liegen einen Ring weiter außen"
	if Blocking.is_blocked(ws, t):
		return "Erst die Schädlinge: die Karte ist noch gesperrt"
	return ""


## Warum sich das Tappen einer Karte nicht zurücknehmen lässt – leer heißt:
## es geht. Ein Stapel ist in Arbeit, weil darunter etwas läuft oder erledigt
## ist; das stellt Tasker selbst so ein, und es lässt sich nur über die
## Unteraufgaben ändern.
static func untap_refusal(ws: Workspace, t: Dictionary) -> String:
	if ws.kids(t["id"]).is_empty():
		return ""
	return ParentStatus.open_refusal(ws, t)


## Der Ring einer Karte: einer weiter außen als alles, wohin sie führt.
static func _ring_of(id: String, inward: Dictionary, rings: Dictionary, seen: Dictionary) -> int:
	if rings.has(id):
		return rings[id]
	# Ein Kreis darf nicht endlos laufen.
	if seen.has(id):
		return 1
	seen[id] = true
	var ring := 1
	for other in inward.get(id, []):
		ring = maxi(ring, _ring_of(other, inward, rings, seen) + 1)
	rings[id] = ring
	return ring


## Führt von `id` – direkt oder über Umwege – ein Weg nach innen zu `target`?
static func _leads(id: String, target: String, inward: Dictionary, seen: Dictionary) -> bool:
	if seen.has(id):
		return false
	seen[id] = true
	for other in inward.get(id, []):
		if other == target or _leads(other, target, inward, seen):
			return true
	return false
