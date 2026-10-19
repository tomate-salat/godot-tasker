@tool
extends EditorContextMenuPlugin
## Der Eintrag „Tasker“ im Kontextmenü des Szenenbaums: eine Aufgabe für die
## ausgewählten Nodes anlegen oder an sie hängen, und je Aufgabe, die schon dran hängt, ein
## Untermenü zum Öffnen und Lösen.

## Für die ausgewählten Nodes soll eine Aufgabe ausgesucht werden.
signal attach_requested(nodes: Array)
## Für die ausgewählten Nodes soll eine neue Aufgabe angelegt werden.
signal create_requested
signal task_requested(task_id: String)
## Die ausgewählten Nodes sollen für Claude vorgemerkt werden (`core/scene_tools.gd`).
signal mark_requested(nodes: Array)

const Store := preload("../core/store.gd")
const Links := preload("../core/links.gd")
const Palette := preload("palette.gd")

const ATTACH := 0
const OPEN := 1
const BROWSER := 2
const UNLINK := 3
const MARK := 4
const CREATE := 5

var store: Store
var links: Links


func _popup_menu(_paths: PackedStringArray) -> void:
	if store == null or store.state != "ready":
		return
	# Der Editor räumt das Menü mit seinem Kontextmenü wieder weg.
	var menu := PopupMenu.new()
	menu.add_item("Neue Aufgabe …", CREATE)
	menu.set_item_tooltip(menu.item_count - 1, "Legt eine Aufgabe an, die an den ausgewählten Nodes hängt")
	menu.add_item("Aufgabe anhängen …", ATTACH)
	menu.add_item("Für Claude vormerken", MARK)
	menu.set_item_tooltip(menu.item_count - 1, "Hält fest, was hier gerade steht. Claude Code holt es sich über den MCP-Server des Addons –\nauch wenn inzwischen eine andere Szene offen ist.")
	menu.id_pressed.connect(func(id: int) -> void:
		if id == CREATE:
			create_requested.emit()
		elif id == ATTACH:
			attach_requested.emit(links.selection())
		elif id == MARK:
			mark_requested.emit(links.selection()))

	var listed := {}
	for node in links.selection():
		for ref in links.of_node(node):
			var t = store.ws.task(ref["taskId"])
			if t == null or listed.has(ref["taskId"]):
				continue
			if listed.is_empty():
				menu.add_separator("Hängt hier")
			listed[ref["taskId"]] = true
			var sub := PopupMenu.new()
			sub.add_item("Aufgabe öffnen", OPEN)
			sub.add_item("In Tasker öffnen", BROWSER)
			sub.add_separator()
			sub.add_item("Vom Node lösen", UNLINK)
			sub.id_pressed.connect(_on_task.bind(t["id"]))
			menu.add_submenu_node_item("$%d  %s" % [int(t.get("ref", 0)), _short(t["title"] if t.get("title") else "Ohne Titel")], sub)
			menu.set_item_icon(menu.item_count - 1, Palette.status_icon(t.get("status")))
	add_context_submenu_item("Tasker", menu)


func _on_task(id: int, task_id: String) -> void:
	match id:
		OPEN:
			task_requested.emit(task_id)
		BROWSER:
			var t = store.ws.task(task_id)
			if t != null:
				store.open_in_tasker(t)
		UNLINK:
			# Von allen ausgewählten Nodes.
			for node in links.selection():
				for ref in links.of_node(node):
					if ref["taskId"] == task_id:
						links.unlink(ref)


static func _short(title: String) -> String:
	return title if title.length() <= 40 else title.substr(0, 39) + "…"
