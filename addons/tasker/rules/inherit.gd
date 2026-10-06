extends RefCounted
## Vererbung, aus Taskers `shared/inherit.ts`. Alles abgeleitet, nie gespeichert.

const Workspace := preload("workspace.gd")


## Ohne eigene Kategorie gilt die des nächsten übergeordneten Tasks.
static func effective_category(ws: Workspace, t: Dictionary) -> Variant:
	var seen := {}
	var x = t
	while x != null and not seen.has(x["id"]):
		seen[x["id"]] = true
		var category = ws.category(x.get("categoryId"))
		if category != null:
			return category
		x = ws.task(x.get("parentId"))
	return null


## Die Markierung eines Tasks, ohne eigene die des nächsten Vorfahren.
static func effective_mark(ws: Workspace, t: Dictionary) -> Variant:
	var seen := {}
	var x = t
	while x != null and not seen.has(x["id"]):
		seen[x["id"]] = true
		var mark = ws.mark(x.get("markId"))
		if mark != null:
			return mark
		x = ws.task(x.get("parentId"))
	return null


## Das Titelbild einer Karte: es gilt das spezifischste gesetzte Bild. Zuerst
## der Task und seine Vorfahren (der nächste gewinnt), dann seine Markierung,
## dann seine Kategorie, zuletzt das Projekt.
##
## `{ image_id, from }` mit `from` = "task", "mark", "category" oder "project" – oder null.
static func effective_cover(ws: Workspace, t: Dictionary) -> Variant:
	var seen := {}
	var x = t
	while x != null and not seen.has(x["id"]):
		seen[x["id"]] = true
		if x.get("coverImageId"):
			return {"image_id": x["coverImageId"], "from": "task"}
		x = ws.task(x.get("parentId"))

	var mark = effective_mark(ws, t)
	if mark != null and mark.get("coverImageId"):
		return {"image_id": mark["coverImageId"], "from": "mark"}

	var category = effective_category(ws, t)
	if category != null and category.get("coverImageId"):
		return {"image_id": category["coverImageId"], "from": "category"}

	var project = ws.project(t.get("projectId"))
	if project != null and project.get("coverImageId"):
		return {"image_id": project["coverImageId"], "from": "project"}

	return null
