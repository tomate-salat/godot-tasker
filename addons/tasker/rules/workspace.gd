extends RefCounted
## Ein Index über die Daten – die Entsprechung zu Taskers `shared/workspace.ts`.
##
## Eine Momentaufnahme: nach einer Änderung an den Daten wird er neu gebaut,
## nicht fortgeschrieben.

const Model := preload("model.gd")

var projects: Array
var categories: Array
var marks: Array
var groups: Array
var milestones: Array
var tasks: Array

var _task_by_id := {}
var _milestone_by_id := {}
var _group_by_id := {}
var _project_by_id := {}
var _category_by_id := {}
var _mark_by_id := {}
## Nur aktive Kinder, nach order sortiert.
var _kids_of := {}
## Auch archivierte Kinder.
var _all_kids_of := {}
## Wurzelaufgaben je Milestone, nach order sortiert.
var _roots_of_milestone := {}
## Auch archivierte Wurzelaufgaben.
var _all_roots_of_milestone := {}
## Wer hängt von diesem Task oder Milestone ab.
var _blocks_of := {}
var _finished_of := {}


func _init(data: Dictionary) -> void:
	projects = data.get("projects", [])
	categories = data.get("categories", [])
	marks = data.get("marks", [])
	groups = data.get("groups", [])
	milestones = data.get("milestones", [])
	tasks = data.get("tasks", [])

	for p in projects:
		_project_by_id[p["id"]] = p
	for c in categories:
		_category_by_id[c["id"]] = c
	for k in marks:
		_mark_by_id[k["id"]] = k
	for g in groups:
		_group_by_id[g["id"]] = g
	for m in milestones:
		_milestone_by_id[m["id"]] = m
	for t in tasks:
		_task_by_id[t["id"]] = t

	for t in tasks:
		if t.get("parentId"):
			_push(_all_kids_of, t["parentId"], t)
			if not Model.is_archived(t):
				_push(_kids_of, t["parentId"], t)
		elif t.get("milestoneId"):
			_push(_all_roots_of_milestone, t["milestoneId"], t)
			if not Model.is_archived(t):
				_push(_roots_of_milestone, t["milestoneId"], t)
		for d in t.get("deps", []):
			_push(_blocks_of, d, t)

	# Archiviertes an aktivem Ort steht nur unter seinem Ort, nicht in `tasks`.
	var archived = data.get("archivedTasks")
	if archived:
		for t in archived:
			if _task_by_id.has(t["id"]):
				continue
			if t.get("parentId"):
				_push(_all_kids_of, t["parentId"], t)
			elif t.get("milestoneId"):
				_push(_all_roots_of_milestone, t["milestoneId"], t)

	for map in [_kids_of, _all_kids_of, _roots_of_milestone, _all_roots_of_milestone]:
		for key in map:
			map[key] = Model.stable_sort(map[key], Model.by_order)


func task(id: Variant) -> Variant:
	return _task_by_id.get(id) if id else null


func milestone(id: Variant) -> Variant:
	return _milestone_by_id.get(id) if id else null


func group(id: Variant) -> Variant:
	return _group_by_id.get(id) if id else null


func project(id: Variant) -> Variant:
	return _project_by_id.get(id) if id else null


func category(id: Variant) -> Variant:
	return _category_by_id.get(id) if id else null


func mark(id: Variant) -> Variant:
	return _mark_by_id.get(id) if id else null


## Aktive Unteraufgaben in Reihenfolge.
func kids(id: String) -> Array:
	return _kids_of.get(id, [])


## Unteraufgaben einschließlich archivierter.
func all_kids(id: String) -> Array:
	return _all_kids_of.get(id, [])


## Aktive Wurzelaufgaben eines Milestones.
func ms_roots(m: Dictionary) -> Array:
	return _roots_of_milestone.get(m["id"], [])


## Wurzelaufgaben eines Milestones einschließlich archivierter.
func ms_all_roots(m: Dictionary) -> Array:
	return _all_roots_of_milestone.get(m["id"], [])


## Was zählt: aktive Unteraufgaben und erledigt Archiviertes – Archivieren
## räumt nur auf, es nimmt nichts weg. Offen Archiviertes gilt als verworfen.
func counted_kids(id: String) -> Array:
	return all_kids(id).filter(_counted)


## Wie `counted_kids`, für die Wurzelaufgaben eines Milestones.
func ms_counted(m: Dictionary) -> Array:
	return ms_all_roots(m).filter(_counted)


func _counted(t: Dictionary) -> bool:
	return not Model.is_archived(t) or _finished(t)


## Erledigt oder nur noch aus erledigten (gezählten) Unteraufgaben bestehend.
func _finished(t: Dictionary) -> bool:
	if _finished_of.has(t["id"]):
		return _finished_of[t["id"]]
	var v := Model.is_done(t)
	if not v:
		var ks := counted_kids(t["id"])
		v = ks.size() > 0 and ks.all(_finished)
	_finished_of[t["id"]] = v
	return v


## Tasks, die von diesem Task oder Milestone abhängen.
func blocks(x: Dictionary) -> Array:
	return _blocks_of.get(x["id"], [])


## Von der Wurzel abwärts bis zum direkten Elternteil.
func ancestors(t: Dictionary) -> Array:
	var out := []
	var seen := {t["id"]: true}
	var p = task(t.get("parentId"))
	while p != null and not seen.has(p["id"]):
		out.push_front(p)
		seen[p["id"]] = true
		p = task(p.get("parentId"))
	return out


func root(t: Dictionary) -> Dictionary:
	var up := ancestors(t)
	return up[0] if up.size() else t


## Alle Nachfahren in Baumreihenfolge, ohne archivierte.
func desc(t: Dictionary) -> Array:
	var out := []
	_walk_desc(t, out)
	return out


func _walk_desc(x: Dictionary, out: Array) -> void:
	for k in kids(x["id"]):
		out.append(k)
		_walk_desc(k, out)


## Sichtbar in den Arbeitsansichten: weder selbst noch über einen Elternteil
## archiviert, und der Milestone der Wurzel ist nicht archiviert.
func is_active(t: Dictionary) -> bool:
	if Model.is_archived(t):
		return false
	if ancestors(t).any(Model.is_archived):
		return false
	var ms = milestone(root(t).get("milestoneId"))
	return not (ms != null and Model.is_archived(ms))


## Der Milestone, unter dem dieser Task hängt – über die Wurzel bestimmt.
func milestone_of(t: Dictionary) -> Variant:
	return milestone(root(t).get("milestoneId"))


## Dokumente erkennt man an der Wurzel, Unterseiten erben es.
func is_doc(t: Dictionary) -> bool:
	return bool(root(t).get("doc", false))


## Eingeplante Milestones in Planungsreihenfolge.
func planned_milestones() -> Array:
	var list := milestones.filter(func(m: Dictionary) -> bool:
		return m.get("planned", false) and not Model.is_archived(m))
	return Model.stable_sort(list, func(a: Dictionary, b: Dictionary) -> bool:
		return a["qorder"] < b["qorder"])


static func _push(map: Dictionary, key: Variant, value: Variant) -> void:
	if map.has(key):
		map[key].append(value)
	else:
		map[key] = [value]
