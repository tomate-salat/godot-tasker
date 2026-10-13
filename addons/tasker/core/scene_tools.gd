@tool
extends RefCounted
## Die Werkzeuge, die das Addon über MCP anbietet: die offene Szene lesen und
## Tasker-Aufgaben an ihre Nodes hängen.
##
## Gelesen wird, was der Editor gerade zeigt – auch Ungespeichertes. Geändert
## wird an der Szene nichts; das einzige, was hier schreibt, ist `link_task`,
## und das merkt sich nur eine Verknüpfung (`core/links.gd`). Aufgaben anlegen
## kann das Addon weiterhin nicht.

const Links := preload("links.gd")
const Store := preload("store.gd")

## Mehr Zeilen gibt der Baum nicht her; große Szenen liest man in Stücken.
const MAX_LINES := 400
const MAX_VALUE := 160
const MAX_HITS := 60

const TOOLS := [
	{
		"name": "scene_tree",
		"description": "Der Baum der im Godot-Editor offenen Szene: je Node Pfad-Name, Klasse, Skript, instanzierte Szene und angehängte Tasker-Aufgaben. Mit `path` nur der Teilbaum unter einem Node, mit `max_depth` nur so viele Ebenen.",
		"inputSchema": {"type": "object", "properties": {
			"path": {"type": "string", "description": "Node-Pfad relativ zur Wurzel der Szene; leer oder \".\" ist die Wurzel."},
			"max_depth": {"type": "integer", "description": "Wie viele Ebenen unter dem Start gezeigt werden. Ohne Angabe alle."},
		}},
	},
	{
		"name": "find_nodes",
		"description": "Sucht in der offenen Szene Nodes, deren Name oder Klasse den Text enthält (Groß- und Kleinschreibung egal). Gibt ihre Pfade zurück.",
		"inputSchema": {"type": "object", "properties": {
			"query": {"type": "string", "description": "Teil des Namens oder der Klasse."},
		}, "required": ["query"]},
	},
	{
		"name": "node_info",
		"description": "Alles über einen Node der offenen Szene: Klasse, Skript, instanzierte Szene, Gruppen, Kinder, die vom Standard abweichenden Eigenschaften, verbundene Signale und angehängte Tasker-Aufgaben.",
		"inputSchema": {"type": "object", "properties": {
			"path": {"type": "string", "description": "Node-Pfad relativ zur Wurzel der Szene; \".\" ist die Wurzel."},
		}, "required": ["path"]},
	},
	{
		"name": "selection",
		"description": "Die im Szenenbaum des Editors gerade ausgewählten Nodes, als Pfade relativ zur Wurzel der offenen Szene.",
		"inputSchema": {"type": "object", "properties": {}},
	},
	{
		"name": "linked_tasks",
		"description": "Die Tasker-Aufgaben, die an Nodes der offenen Szene hängen: je Verknüpfung Nummer, Titel, Status und Node-Pfad.",
		"inputSchema": {"type": "object", "properties": {}},
	},
	{
		"name": "link_task",
		"description": "Hängt eine bestehende Tasker-Aufgabe an Nodes der offenen Szene. Im Editor erscheint sie dort als Karte. Die Szene muss gespeichert sein. Die Aufgabe muss es in Tasker schon geben – anlegen kann dieses Werkzeug sie nicht.",
		"inputSchema": {"type": "object", "properties": {
			"task": {"type": "string", "description": "Die Nummer der Aufgabe (\"$142\" oder \"142\") oder ihre ID."},
			"paths": {"type": "array", "items": {"type": "string"}, "description": "Node-Pfade relativ zur Wurzel der Szene; \".\" ist die Wurzel."},
		}, "required": ["task", "paths"]},
	},
]

var links: Links
var store: Store


## Führt ein Werkzeug aus: `{ text, failed }`.
func run(name: String, arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return _fail("Im Editor ist keine Szene offen.")
	match name:
		"scene_tree":
			return _scene_tree(root, str(arguments.get("path", "")), int(arguments.get("max_depth", -1)))
		"find_nodes":
			return _find_nodes(root, str(arguments.get("query", "")))
		"node_info":
			return _node_info(root, str(arguments.get("path", "")))
		"selection":
			return _selection(root)
		"linked_tasks":
			return _linked_tasks()
		"link_task":
			var paths: Variant = arguments.get("paths", [])
			return _link_task(root, str(arguments.get("task", "")), paths if paths is Array else [])
	return _fail("Unbekanntes Werkzeug: %s" % name)


# ------------------------------------------------------------- Lesen

func _scene_tree(root: Node, path: String, max_depth: int) -> Dictionary:
	var start := _node(root, path)
	if start == null:
		return _fail(_missing(path))
	var tasks := _tasks_by_path()
	var lines := [_head(root)]
	var cut := false
	# Tiefe zuerst, in der Reihenfolge des Baums.
	var todo := [[start, 0]]
	while not todo.is_empty():
		var entry: Array = todo.pop_back()
		var node: Node = entry[0]
		var depth: int = entry[1]
		if lines.size() > MAX_LINES:
			cut = true
			break
		lines.append("%s%s" % ["  ".repeat(depth), _line(root, node, tasks)])
		if max_depth >= 0 and depth >= max_depth:
			if _children(root, node).size() > 0:
				lines[-1] += "  [+%d Kinder]" % _children(root, node).size()
			continue
		var kids := _children(root, node)
		kids.reverse()
		for kid in kids:
			todo.append([kid, depth + 1])
	if cut:
		lines.append("… abgeschnitten nach %d Zeilen. Mit `path` einen Teilbaum lesen." % MAX_LINES)
	return _ok("\n".join(lines))


func _find_nodes(root: Node, query: String) -> Dictionary:
	query = query.strip_edges().to_lower()
	if query == "":
		return _fail("Wonach soll gesucht werden?")
	var tasks := _tasks_by_path()
	var hits := []
	var todo := [root]
	while not todo.is_empty() and hits.size() < MAX_HITS:
		var node: Node = todo.pop_back()
		if str(node.name).to_lower().contains(query) or node.get_class().to_lower().contains(query):
			hits.append("%s  —  %s" % [_path(root, node), _line(root, node, tasks)])
		var kids := _children(root, node)
		kids.reverse()
		todo.append_array(kids)
	if hits.is_empty():
		return _ok("%s\nNichts gefunden für „%s“." % [_head(root), query])
	return _ok("%s\n%s" % [_head(root), "\n".join(hits)])


func _node_info(root: Node, path: String) -> Dictionary:
	var node := _node(root, path)
	if node == null:
		return _fail(_missing(path))
	var lines := [_head(root), "Pfad: %s" % _path(root, node), "Klasse: %s" % node.get_class()]
	var script: Script = node.get_script()
	if script != null:
		lines.append("Skript: %s" % (script.resource_path if script.resource_path != "" else "(eingebettet)"))
	if node != root and node.scene_file_path != "":
		lines.append("Instanz von: %s" % node.scene_file_path)
	if node.owner != null and node.owner != root:
		lines.append("Gehört zur instanzierten Szene unter: %s" % _path(root, node.owner))
	var groups := []
	for g in node.get_groups():
		if not str(g).begins_with("_"):
			groups.append(str(g))
	if not groups.is_empty():
		lines.append("Gruppen: %s" % ", ".join(groups))
	var kids := []
	for kid in _children(root, node):
		kids.append("%s (%s)" % [kid.name, kid.get_class()])
	lines.append("Kinder: %s" % (", ".join(kids) if not kids.is_empty() else "keine"))

	lines.append("")
	lines.append("Eigenschaften, die vom Standard abweichen:")
	var changed := _changed_properties(node)
	lines.append_array(changed if not changed.is_empty() else ["  keine"])

	var wired := _connections(root, node)
	if not wired.is_empty():
		lines.append("")
		lines.append("Signale (in der Szene verbunden):")
		lines.append_array(wired)

	var tasks: Array = _tasks_by_path().get(_path(root, node), [])
	if not tasks.is_empty():
		lines.append("")
		lines.append("Angehängte Aufgaben: %s" % ", ".join(tasks))
	return _ok("\n".join(lines))


func _selection(root: Node) -> Dictionary:
	var lines := [_head(root)]
	var tasks := _tasks_by_path()
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node == root or root.is_ancestor_of(node):
			lines.append("%s  —  %s" % [_path(root, node), _line(root, node, tasks)])
	if lines.size() == 1:
		lines.append("Nichts ausgewählt.")
	return _ok("\n".join(lines))


func _linked_tasks() -> Dictionary:
	var lines := []
	for ref in links.here():
		lines.append("%s  an  %s%s" % [_task_label(ref["taskId"]), ref["nodePath"], "" if links.node_of(ref) != null else "  (Node nicht mehr zu finden)"])
	return _ok("\n".join(lines) if not lines.is_empty() else "An dieser Szene hängt keine Aufgabe.")


# -------------------------------------------------------- Verknüpfen

func _link_task(root: Node, wanted: String, paths: Array) -> Dictionary:
	if store == null or store.state != "ready":
		return _fail("Das Addon ist gerade nicht mit Tasker verbunden – die Aufgabe lässt sich nicht nachschlagen.")
	var task: Variant = _find_task(wanted)
	if task == null:
		return _fail("Die Aufgabe %s gibt es im verbundenen Tasker-Projekt nicht (oder das Addon hat sie noch nicht geladen – kurz warten und noch einmal versuchen)." % wanted)
	if paths.is_empty():
		return _fail("Ohne Node-Pfade hängt nichts.")
	var nodes := []
	for p in paths:
		var node := _node(root, str(p))
		if node == null:
			return _fail(_missing(str(p)))
		nodes.append(node)
	var problem := links.link(task["id"], nodes)
	if problem != "":
		return _fail(problem)
	var names := []
	for node in nodes:
		names.append(_path(root, node))
	return _ok("%s hängt jetzt an: %s" % [_task_label(task["id"]), ", ".join(names)])


## Die Aufgabe zu einer Nummer (`$142`, `142`) oder ID.
func _find_task(wanted: String) -> Variant:
	wanted = wanted.strip_edges()
	var by_id: Variant = store.ws.task(wanted)
	if by_id != null:
		return by_id
	var number := wanted.trim_prefix("$")
	if not number.is_valid_int():
		return null
	for t in store.ws.tasks:
		if int(t.get("ref", 0)) == int(number):
			return t
	return null


func _task_label(id: String) -> String:
	var task: Variant = store.ws.task(id) if store != null and store.state == "ready" else null
	if task == null:
		return "Aufgabe %s" % id
	return "$%d „%s“ (%s)" % [int(task.get("ref", 0)), task.get("title", ""), task.get("status", "")]


# ------------------------------------------------------------ Helfer

func _node(root: Node, path: String) -> Node:
	path = path.strip_edges()
	if path == "" or path == "." or path == str(root.name):
		return root
	return root.get_node_or_null(NodePath(path.trim_prefix("./").trim_prefix(str(root.name) + "/")))


static func _path(root: Node, node: Node) -> String:
	return str(root.get_path_to(node))


static func _missing(path: String) -> String:
	return "Den Node „%s“ gibt es in der offenen Szene nicht. Pfade sind relativ zur Wurzel; `find_nodes` hilft beim Suchen." % path


static func _head(root: Node) -> String:
	var file := root.scene_file_path
	var unsaved := file == "" or EditorInterface.get_unsaved_scenes().has(file)
	return "Szene: %s%s" % [file if file != "" else "(noch nie gespeichert)", "  (ungespeicherte Änderungen)" if unsaved and file != "" else ""]


## Die Kinder, die zur Szene gehören – nicht, was der Editor oder ein
## Werkzeug-Skript nur zur Anzeige hineinhängt.
static func _children(root: Node, node: Node) -> Array:
	var out := []
	for kid in node.get_children():
		if kid.owner != null and (kid.owner == root or root.is_ancestor_of(kid.owner)):
			out.append(kid)
	return out


func _line(root: Node, node: Node, tasks: Dictionary) -> String:
	var text := "%s (%s)" % [node.name, node.get_class()]
	var script: Script = node.get_script()
	if script != null and script.resource_path != "":
		text += "  [%s]" % script.resource_path
	if node != root and node.scene_file_path != "":
		text += "  [Instanz: %s]" % node.scene_file_path
	var here: Array = tasks.get(_path(root, node), [])
	if not here.is_empty():
		text += "  [Aufgaben: %s]" % ", ".join(here)
	return text


## Node-Pfad → die Nummern der Aufgaben, die dort hängen.
func _tasks_by_path() -> Dictionary:
	var out := {}
	for ref in links.here():
		var task: Variant = store.ws.task(ref["taskId"]) if store != null and store.state == "ready" else null
		var label := "$%d" % int(task.get("ref", 0)) if task != null else str(ref["taskId"])
		if not out.has(ref["nodePath"]):
			out[ref["nodePath"]] = []
		out[ref["nodePath"]].append(label)
	return out


## Die gespeicherten Eigenschaften, deren Wert nicht der Standard ist.
static func _changed_properties(node: Node) -> Array:
	var out := []
	var script: Script = node.get_script()
	# Nicht jede Eigenschaft nennt der Editor mit Standardwert; ein frischer
	# Node derselben Klasse weiß ihn immer.
	var fresh: Object = ClassDB.instantiate(node.get_class()) if ClassDB.can_instantiate(node.get_class()) else null
	for info in node.get_property_list():
		var usage: int = info["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0 or usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var name: String = info["name"]
		if name == "script":
			continue
		var value: Variant = node.get(name)
		var standard: Variant
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE != 0:
			standard = script.get_property_default_value(name) if script != null else null
		else:
			standard = fresh.get(name) if fresh != null else ClassDB.class_get_property_default_value(node.get_class(), name)
		if typeof(value) == typeof(standard) and value == standard:
			continue
		if standard == null and (value == null or (value is Array and value.is_empty()) or (value is Dictionary and value.is_empty())):
			continue
		out.append("  %s = %s" % [name, _show(value)])
	if fresh is Node:
		fresh.free()
	return out


static func _show(value: Variant) -> String:
	var text := ""
	if value is Node:
		text = "Node %s" % value.name
	elif value is Resource:
		text = value.resource_path if value.resource_path != "" and not value.resource_path.contains("::") else "%s (eingebettet)" % value.get_class()
	elif value is Object:
		text = value.get_class()
	else:
		text = var_to_str(value).replace("\n", " ")
	return text if text.length() <= MAX_VALUE else text.substr(0, MAX_VALUE) + " …"


## Die Verbindungen, die in der Szene stehen und von diesem Node ausgehen.
static func _connections(root: Node, node: Node) -> Array:
	var out := []
	for sig in node.get_signal_list():
		for c in node.get_signal_connection_list(sig["name"]):
			if int(c["flags"]) & CONNECT_PERSIST == 0:
				continue
			var callable: Callable = c["callable"]
			var target := callable.get_object() as Node
			var where := _path(root, target) if target != null and (target == root or root.is_ancestor_of(target)) else "(außerhalb)"
			out.append("  %s → %s :: %s" % [sig["name"], where, callable.get_method()])
	return out


static func _ok(text: String) -> Dictionary:
	return {"text": text, "failed": false}


static func _fail(text: String) -> Dictionary:
	return {"text": text, "failed": true}
