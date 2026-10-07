extends RefCounted
## Der Abhängigkeitsgraph einer Karte: worauf sie wartet und was auf sie
## wartet, über alle Stufen. Gezeichnet wird in `ui/dep_graph_view.gd`.
##
## Eine Karte steht für sich und alles darunter: wartet eine Unteraufgabe auf
## etwas außerhalb, wartet die Karte, und was für eine Aufgabe darüber gilt,
## gilt auch für sie. Worauf gewartet wird, kann eine Aufgabe oder ein ganzer
## Milestone sein.

const Model := preload("model.gd")
const Blocking := preload("blocking.gd")
const Planning := preload("planning.gd")
const Workspace := preload("workspace.gd")

## Mehr Knoten als so zeigt der Graph nicht.
const MAX_NODES := 60

## Wie eine Kante steht: die Voraussetzung ist erledigt, sie liegt richtig,
## oder sie liegt später oder gar nicht im Plan.
const DONE := "done"
const OK := "ok"
const MISPLACED := "misplaced"


## Worauf `x` unmittelbar wartet – auch schon Erledigtes: Aufgaben und
## Milestones.
static func waits_on(ws: Workspace, x: Dictionary) -> Array:
	var ids := []
	if Model.is_milestone(x):
		ids = x.get("deps", []).duplicate()
	else:
		var inside := _subtree(ws, x)
		for t in [x] + ws.desc(x) + ws.ancestors(x):
			for id in t.get("deps", []):
				if not inside.has(id) and not ids.has(id):
					ids.append(id)
	var out := []
	for id in ids:
		var d = ws.task(id)
		if d == null:
			d = ws.milestone(id)
		if d != null and d["id"] != x["id"]:
			out.append(d)
	return out


## Was unmittelbar auf `x` wartet: Aufgaben, die `x` oder etwas darunter als
## Voraussetzung nennen, und Milestones, die auf den Milestone `x` warten.
static func waited_by(ws: Workspace, x: Dictionary) -> Array:
	var out := []
	if Model.is_milestone(x):
		for m in ws.milestones:
			if m.get("deps", []).has(x["id"]) and not Model.is_archived(m):
				out.append(m)
	var inside := {x["id"]: true} if Model.is_milestone(x) else _subtree(ws, x)
	for t in ws.tasks:
		if inside.has(t["id"]) or not ws.is_active(t):
			continue
		for id in t.get("deps", []):
			if inside.has(id):
				out.append(t)
				break
	return out


## Der Graph um `focus`: `{ nodes, edges, cut }`.
##
## `nodes` sind `{ item, layer }` – `layer` ist die Stufe: 0 die Karte selbst,
## negativ das, worauf sie wartet, positiv das, was auf sie wartet. `edges`
## sind `{ from, to }` mit den IDs von Voraussetzung und Wartendem. `cut`
## ist wahr, wenn der Graph größer wäre als `MAX_NODES`.
static func build(ws: Workspace, focus: Dictionary) -> Dictionary:
	var layer := {focus["id"]: 0}
	var items := {focus["id"]: focus}
	var edges := []
	var cut := false
	for side in [-1, 1]:
		var queue := [focus]
		while not queue.is_empty():
			var x: Dictionary = queue.pop_front()
			for other in (waits_on(ws, x) if side < 0 else waited_by(ws, x)):
				var edge := {"from": other["id"], "to": x["id"]} if side < 0 else {"from": x["id"], "to": other["id"]}
				if not edges.has(edge):
					edges.append(edge)
				if layer.has(other["id"]):
					continue
				if items.size() >= MAX_NODES:
					cut = true
					continue
				layer[other["id"]] = layer[x["id"]] + side
				items[other["id"]] = other
				queue.append(other)
	# Kanten zu Knoten, die nicht mehr hineingepasst haben, fallen weg.
	edges = edges.filter(func(e: Dictionary) -> bool: return items.has(e["from"]) and items.has(e["to"]))

	# Die Stufe ist der längste Weg zur Karte, nicht der kürzeste: so zeigt
	# jeder Pfeil nach rechts, auch wenn eine Voraussetzung selbst wieder auf
	# eine andere derselben Karte wartet.
	var toward := {}
	for e in edges:
		# Auf der Wartet-auf-Seite führt der Weg zur Karte über das Wartende,
		# auf der anderen über die Voraussetzung.
		if layer[e["from"]] < 0 and layer[e["to"]] <= 0:
			toward.get_or_add(e["from"], []).append(e["to"])
		elif layer[e["to"]] > 0 and layer[e["from"]] >= 0:
			toward.get_or_add(e["to"], []).append(e["from"])
	var far := {focus["id"]: 0}
	for id in items:
		_far(id, toward, far, {})
	for id in items:
		layer[id] = far[id] * signi(layer[id])

	var nodes := []
	for id in items:
		nodes.append({"item": items[id], "layer": layer[id]})
	return {"nodes": nodes, "edges": edges, "cut": cut}


## Wie die Kante von der Voraussetzung `blocker` zum Wartenden `waiter` steht.
## `order` sagt zu jedem Deck seinen Platz (`Planning.deck_order`).
static func edge_state(ws: Workspace, blocker: Dictionary, waiter: Dictionary, order: Dictionary) -> String:
	if not Blocking._still_blocks(ws, blocker):
		return DONE
	var at := _place(ws, waiter, order)
	if at < 0:
		return OK
	var blocker_at := _place(ws, blocker, order)
	return MISPLACED if blocker_at < 0 or blocker_at > at else OK


## Wo etwas liegt, lesbar: der Milestone, sonst „Ready“ oder „Backlog“.
static func place_label(ws: Workspace, x: Dictionary) -> String:
	if Model.is_milestone(x):
		return "Milestone" if x.get("planned", false) else "Milestone, nicht eingeplant"
	var m = ws.milestone_of(x)
	if m != null:
		return "◆ %s%s" % [m["title"] if m.get("title") else "Ohne Titel", "" if m.get("planned", false) else " (nicht eingeplant)"]
	var root := ws.root(x)
	if root.get("doc", false):
		return "Dokumentation"
	return "Ready" if Planning.is_loose_root(root) and root.get("ready", false) else "Backlog"


static func _place(ws: Workspace, x: Dictionary, order: Dictionary) -> int:
	return order.get(x["id"], -1) if Model.is_milestone(x) else Planning.place(ws, x, order)


static func _subtree(ws: Workspace, t: Dictionary) -> Dictionary:
	var out := {t["id"]: true}
	for d in ws.desc(t):
		out[d["id"]] = true
	return out


## Der längste Weg von `id` zur Karte, über `toward`. Ein Kreis zählt nicht weiter.
static func _far(id: String, toward: Dictionary, far: Dictionary, walking: Dictionary) -> int:
	if far.has(id):
		return far[id]
	if walking.has(id):
		return 0
	walking[id] = true
	var longest := 0
	for next in toward.get(id, []):
		longest = maxi(longest, _far(next, toward, far, walking))
	walking.erase(id)
	far[id] = longest + 1
	return far[id]
