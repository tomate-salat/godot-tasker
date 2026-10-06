extends RefCounted
## Sperren, aus Taskers `shared/blocking.ts`.
##
## Worauf ein Task warten kann: ein anderer Task oder ein ganzer Milestone.

const Model := preload("model.gd")
const Progress := preload("progress.gd")
const Workspace := preload("workspace.gd")


## Ein Blocker zählt, solange er weder erledigt noch weggeräumt ist.
static func _still_blocks(ws: Workspace, x: Dictionary) -> bool:
	if not Model.is_milestone(x):
		return not Model.is_done(x) and ws.is_active(x)
	return not Model.is_archived(x) and not Progress.milestone_done(ws, x)


## Eigene Abhängigkeiten, die tatsächlich noch blockieren.
static func own_blockers(ws: Workspace, t: Dictionary) -> Array:
	var out := []
	for id in t.get("deps", []):
		var d = ws.task(id)
		if d == null:
			d = ws.milestone(id)
		if d != null and _still_blocks(ws, d):
			out.append(d)
	return out


## Blockierungen der Eltern-Tasks gelten für alle Unteraufgaben mit –
## abgeleitet, nicht gespeichert. `{ deps = [{ blocker, via }], status_via }`
static func inherited_block(ws: Workspace, t: Dictionary) -> Dictionary:
	var deps := []
	var status_via = null
	var up := ws.ancestors(t)
	up.reverse()
	for a in up:
		for blocker in own_blockers(ws, a):
			if blocker["id"] == t["id"]:
				continue
			if t.get("deps", []).has(blocker["id"]):
				continue
			if deps.any(func(x: Dictionary) -> bool: return x["blocker"]["id"] == blocker["id"]):
				continue
			deps.append({"blocker": blocker, "via": a})
		if status_via == null and a.get("status") == "blocked":
			status_via = a
	return {"deps": deps, "status_via": status_via}


static func blockers(ws: Workspace, t: Dictionary) -> Array:
	var out := own_blockers(ws, t)
	for x in inherited_block(ws, t)["deps"]:
		out.append(x["blocker"])
	return out


static func is_blocked(ws: Workspace, t: Dictionary) -> bool:
	if t.get("status") == "blocked":
		return true
	if blockers(ws, t).size() > 0:
		return true
	return inherited_block(ws, t)["status_via"] != null


## Hängt `a` direkt oder über Umwege von `target_id` ab? Wird gebraucht, um
## beim Setzen einer Abhängigkeit Kreise zu verhindern.
static func depends_on(ws: Workspace, a: Dictionary, target_id: String, seen := {}) -> bool:
	var deps: Array = a.get("deps", [])
	if deps.has(target_id):
		return true
	for id in deps:
		if seen.has(id):
			continue
		seen[id] = true
		var next = ws.task(id)
		if next == null:
			next = ws.milestone(id)
		if next != null and depends_on(ws, next, target_id, seen):
			return true
	return false
