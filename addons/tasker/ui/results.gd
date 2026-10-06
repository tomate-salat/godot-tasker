@tool
extends RefCounted
## Suchtreffer als Zeilen einer `ItemList` – im Dock und im Such-Popup gleich.

const Palette := preload("palette.gd")
const Workspace := preload("../rules/workspace.gd")


## Füllt die Liste; die ID der Aufgabe steht als Metadatum an der Zeile.
static func fill(list: ItemList, ws: Workspace, tasks: Array) -> void:
	list.clear()
	for t in tasks:
		var title: String = t["title"] if t.get("title") else "Ohne Titel"
		var i := list.add_item("$%d  %s" % [int(t.get("ref", 0)), title], Palette.status_icon(t.get("status")))
		list.set_item_metadata(i, t["id"])
		list.set_item_tooltip(i, where(ws, t))


## Wo die Aufgabe hängt: Milestone und Eltern-Tasks.
static func where(ws: Workspace, t: Dictionary) -> String:
	var parts := []
	var m = ws.milestone_of(t)
	if m != null:
		parts.append("◆ %s" % m["title"])
	for a in ws.ancestors(t):
		parts.append(a["title"] if a.get("title") else "Ohne Titel")
	return " › ".join(PackedStringArray(parts)) if parts.size() else "Ohne Milestone"
