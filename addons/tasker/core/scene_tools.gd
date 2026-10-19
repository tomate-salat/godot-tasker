@tool
extends RefCounted
## Die Werkzeuge, die das Addon über MCP anbietet: die offene Szene lesen und
## Tasker-Aufgaben an ihre Nodes hängen.
##
## Gelesen wird, was der Editor gerade zeigt – auch Ungespeichertes. Geändert
## wird an der Szene nichts. `link_task` merkt sich eine Verknüpfung
## (`core/links.gd`); `create_task` legt eine Aufgabe an und hängt sie gleich
## an. Seit 2026-10-19 legt auch die Oberfläche an (Schnellanlegen,
## `core/claude_tasks.gd`) und nutzt dafür `snapshot` und `hang` von hier.

const Links := preload("links.gd")
const Store := preload("store.gd")
const GameLink := preload("game_link.gd")
const Config := preload("config.gd")
const Search := preload("../rules/search.gd")
const Model := preload("../rules/model.gd")

## Mehr Zeilen gibt der Baum nicht her; große Szenen liest man in Stücken.
const MAX_LINES := 400
const MAX_VALUE := 160
const MAX_HITS := 60
const MAX_MARKS := 20
## Im Schnappschuss: so viele ausgewählte Nodes mit allem, so viele Zeilen Baum.
const CONTEXT_NODES := 6
const CONTEXT_LINES := 120
const MAX_TASKS := 15

const TOOLS := [
	{
		"name": "context",
		"description": "Der Schnappschuss des Editors in einem Aufruf: die offene Szene, die ausgewählten Nodes mit allen Einstellungen, was der Nutzer vorgemerkt hat, der Szenenbaum und die schon angehängten Aufgaben. Als Erstes und nur einmal aufrufen, wenn der Nutzer etwas im Godot-Projekt meint – er arbeitet weiter, und Sekunden später ist etwas anderes offen. Danach mit dieser Ausgabe und den Dateien des Projekts arbeiten.",
		"inputSchema": {"type": "object", "properties": {}},
	},
	{
		"name": "game_state",
		"description": "Was im laufenden Spiel gerade geladen ist (nur wenn es aus dem Editor gestartet wurde): die geladene Szene, Kamera, das UI-Element unter dem Mauszeiger und der Baum zur Laufzeit – bei jedem Node mit der Szenendatei, aus der er stammt. Steckt schon in context; einzeln nur aufrufen, um später noch einmal nachzusehen.",
		"inputSchema": {"type": "object", "properties": {}},
	},
	{
		"name": "find_tasks",
		"description": "Sucht im verbundenen Tasker-Projekt nach Aufgaben: in Titel, Labels, Beschreibung und Nummer. Mehrere Wörter müssen alle vorkommen – lieber ein, zwei Stichwörter als ein Satz. Zum Nachsehen, ob es eine Aufgabe schon gibt, und um Verwandtes zu nennen.",
		"inputSchema": {"type": "object", "properties": {
			"query": {"type": "string", "description": "Ein oder zwei Stichwörter, oder eine Nummer (\"$142\")."},
			"include_done": {"type": "boolean", "description": "Auch Erledigtes zeigen. Ohne Angabe nur Offenes."},
		}, "required": ["query"]},
	},
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
		"name": "marked",
		"description": "Was der Nutzer im Godot-Editor eigens für Claude vorgemerkt hat (Kontextmenü im Szenenbaum, „Für Claude vormerken“): je Node die Szene, der Pfad und die Auskunft, wie er beim Vormerken eingestellt war. Das gilt auch, wenn inzwischen eine andere Szene offen ist. Zuerst hier nachsehen, wenn der Nutzer von „dem Vorgemerkten“ spricht oder keinen Node nennt. Was an eine Aufgabe gehängt wird, verschwindet von selbst aus der Liste.",
		"inputSchema": {"type": "object", "properties": {
			"clear": {"type": "boolean", "description": "Die Liste nach dem Lesen leeren."},
		}},
	},
	{
		"name": "linked_tasks",
		"description": "Die Tasker-Aufgaben, die an Nodes der offenen Szene hängen: je Verknüpfung Nummer, Titel, Status und Node-Pfad.",
		"inputSchema": {"type": "object", "properties": {}},
	},
	{
		"name": "create_task",
		"description": "Legt im Tasker-Projekt, mit dem das Addon verbunden ist, eine Aufgabe an und hängt sie im selben Schritt an Nodes der offenen Szene. Das ist der Weg für Bugs und Wünsche, die etwas in der Szene betreffen. Die Aufgabe landet im Backlog unter „Unsortiert“; Ort, Status und Milestone vergibt der Nutzer selbst. Vorher mit node_info nachsehen und das Gefundene in die Beschreibung schreiben.",
		"inputSchema": {"type": "object", "properties": {
			"title": {"type": "string", "description": "Kurzer Titel."},
			"desc": {"type": "string", "description": "Beschreibung in Markdown: was falsch ist oder gewünscht wird, und was die Szene dazu hergibt."},
			"mark": {"type": "string", "description": "Markierung, als Name (etwa \"Bug\") oder ID. Weglassen, wenn keine passt."},
			"category": {"type": "string", "description": "Kategorie des Projekts, als Name oder ID. Weglassen, wenn unklar."},
			"prio": {"type": "integer", "description": "0 = keine, 1 = hoch, 2 = mittel, 3 = niedrig."},
			"scene": {"type": "string", "description": "Die Szene der Nodes, als res://-Pfad – so wie die gelesene Auskunft sie in ihrer ersten Zeile nennt. Pflicht, sobald `paths` genannt sind: geraten wird nicht, denn der Nutzer hat inzwischen vielleicht eine andere Szene offen."},
			"paths": {"type": "array", "items": {"type": "string"}, "description": "Die betroffenen Nodes, als Pfade relativ zur Wurzel der Szene; \".\" ist die Wurzel. Leer nur, wenn die Aufgabe keinen Node betrifft."},
		}, "required": ["title"]},
	},
	{
		"name": "link_task",
		"description": "Hängt eine bestehende Tasker-Aufgabe an Nodes einer Szene. Im Editor erscheint sie dort als Karte. Die Szene muss gespeichert sein. Für eine neue Aufgabe create_task nehmen – das legt an und hängt an.",
		"inputSchema": {"type": "object", "properties": {
			"task": {"type": "string", "description": "Die Nummer der Aufgabe (\"$142\" oder \"142\") oder ihre ID."},
			"scene": {"type": "string", "description": "Die Szene der Nodes, als res://-Pfad – so wie die gelesene Auskunft sie in ihrer ersten Zeile nennt."},
			"paths": {"type": "array", "items": {"type": "string"}, "description": "Node-Pfade relativ zur Wurzel der Szene; \".\" ist die Wurzel."},
		}, "required": ["task", "scene", "paths"]},
	},
]

var links: Links
var store: Store
## Die Leitung ins laufende Spiel – fehlt sie, weiß der Schnappschuss nur, womit es gestartet wurde.
var game: GameLink

## Was der Nutzer vorgemerkt hat: `{ scene, path, info, at }`. Nur für
## diese Sitzung des Editors.
var _marks: Array = []


## Führt ein Werkzeug aus: `{ text, failed }`.
func run(name: String, arguments: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if name == "create_task":
		return await _create_task(root, arguments)
	if name == "marked":
		return _marked(bool(arguments.get("clear", false)))
	if name == "context":
		return await _context(root)
	if name == "game_state":
		return await _game_state()
	if name == "find_tasks":
		return _find_tasks(str(arguments.get("query", "")), bool(arguments.get("include_done", false)))
	if name == "link_task":
		var wanted: Variant = arguments.get("paths", [])
		return _link_task(root, str(arguments.get("task", "")), wanted if wanted is Array else [], str(arguments.get("scene", "")))
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
	return _fail("Unbekanntes Werkzeug: %s" % name)


# ----------------------------------------------------- Schnappschuss

## Der Schnappschuss als Text – für Claude-Aufträge aus der Oberfläche.
func snapshot() -> String:
	return (await _context(EditorInterface.get_edited_scene_root()))["text"]


## Alles, was der Editor gerade weiß, in einer Antwort. Danach muss niemand
## mehr hineinschauen – und der Nutzer nicht in der Szene bleiben.
func _context(root: Node) -> Dictionary:
	# Zuerst das Spiel fragen: die Antwort braucht ein paar Bilder, und in der
	# Zeit soll sich am Rest nichts mehr ändern können.
	var playing := EditorInterface.is_playing_scene()
	var live := await game.snapshot() if playing and game != null else ""
	root = EditorInterface.get_edited_scene_root()
	var lines := []
	if root == null:
		lines.append("Im Editor ist keine Szene offen.")
	else:
		lines.append(_head(root))
		lines.append("Beim Anlegen als `scene` mitgeben: %s" % (root.scene_file_path if root.scene_file_path != "" else "(geht nicht – die Szene ist noch nie gespeichert)"))
	var others := []
	for path in EditorInterface.get_open_scenes():
		if root == null or path != root.scene_file_path:
			others.append(path)
	if not others.is_empty():
		lines.append("Außerdem in Tabs offen: %s" % ", ".join(others))
	# Läuft das Spiel, meint der Nutzer meist, was er dort sieht – nicht die
	# Szene, die im Editor zufällig offen ist (Nutzer, 2026-10-13).
	if playing:
		lines.append("")
		lines.append("# Das Spiel läuft gerade")
		lines.append(_started_with())
		lines.append("Was der Nutzer meldet, sieht er sehr wahrscheinlich im laufenden Spiel. Die im Editor offene Szene und die Auswahl sind dann nur ein Hinweis, kein Beleg.")
		if live != "":
			lines.append("Beim Anlegen `scene` und `paths` aus den Szenendateien nehmen, die der Baum unten nennt („Instanz: …“), nicht aus dem Pfad zur Laufzeit.")
			lines.append("")
			lines.append(live)
		else:
			lines.append(_no_answer())

	if root != null:
		var chosen := []
		for node in EditorInterface.get_selection().get_selected_nodes():
			if node == root or root.is_ancestor_of(node):
				chosen.append(node)
		lines.append("")
		lines.append("# Ausgewählt: %s" % ("nichts" if chosen.is_empty() else str(chosen.size())))
		for node in chosen.slice(0, CONTEXT_NODES):
			lines.append("")
			lines.append("\n".join(_node_info(root, _path(root, node))["text"].split("\n").slice(1)))
		if chosen.size() > CONTEXT_NODES:
			lines.append("… und %d weitere." % (chosen.size() - CONTEXT_NODES))

	if not _marks.is_empty():
		lines.append("")
		lines.append("# Vom Nutzer vorgemerkt: %d (das ist ausdrücklich gemeint)" % _marks.size())
		lines.append("\n".join(_marked(false)["text"].split("\n").slice(1)))

	if root != null:
		lines.append("")
		lines.append("# Szenenbaum")
		var tree: PackedStringArray = _scene_tree(root, "", -1)["text"].split("\n").slice(1)
		lines.append("\n".join(tree.slice(0, CONTEXT_LINES)))
		if tree.size() > CONTEXT_LINES:
			lines.append("… %d weitere Zeilen; die Szenendatei hat alles." % (tree.size() - CONTEXT_LINES))
		var hanging := links.here()
		if not hanging.is_empty():
			lines.append("")
			lines.append("# Schon angehängte Aufgaben")
			lines.append(_linked_tasks()["text"])
	return _ok("\n".join(lines))


func _game_state() -> Dictionary:
	if not EditorInterface.is_playing_scene():
		return _ok("Das Spiel läuft gerade nicht.")
	var live := await game.snapshot() if game != null else ""
	return _ok("%s\n\n%s" % [_started_with(), live if live != "" else _no_answer()])


static func _started_with() -> String:
	var played := EditorInterface.get_playing_scene()
	var main := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	return "Gestartet mit: %s" % (played if played != "" else "%s (die Hauptszene des Projekts)" % main if main != "" else "unbekannt")


## Was zu sagen ist, wenn das Spiel läuft, aber nicht antwortet.
func _no_answer() -> String:
	if game != null and game.is_breaked():
		return "Das Spiel steht an einem Haltepunkt und antwortet nicht. Welche Szene es geladen hat, lässt sich nur von der Startszene aus in den Dateien nachlesen."
	return "Das Spiel antwortet nicht auf die Frage nach seinem Stand (läuft es ohne den Autoload „TaskerProbe“, oder hängt es?). Von der Startszene aus in den Dateien nachlesen, welche Szenen sie lädt und instanziert."


func _find_tasks(query: String, include_done: bool) -> Dictionary:
	if store == null or store.state != "ready":
		return _fail("Das Addon ist gerade nicht mit Tasker verbunden.")
	query = query.strip_edges()
	if query == "":
		return _fail("Wonach soll gesucht werden?")
	var lines := []
	for t in Search.find(store.ws, Config.project_id(), query.trim_prefix("$"), 60):
		if Model.is_done(t) and not include_done:
			continue
		var milestone: Variant = store.ws.milestone_of(t)
		lines.append("$%d  [%s]  %s%s" % [int(t.get("ref", 0)), t.get("status", ""), t.get("title", ""), "  —  Milestone: %s" % milestone["title"] if milestone != null else ""])
		if lines.size() >= MAX_TASKS:
			lines.append("… es gibt mehr Treffer; enger suchen.")
			break
	if lines.is_empty():
		return _ok("Keine %sAufgabe gefunden für „%s“." % ["" if include_done else "offene ", query])
	return _ok("\n".join(lines))


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

## Hängt die Aufgabe an Nodes einer Szene, offen oder nicht: `{ text, failed }`.
func hang(task_id: String, scene: String, paths: Array) -> Dictionary:
	return _hang(EditorInterface.get_edited_scene_root(), task_id, scene, paths, true)


func _link_task(root: Node, wanted: String, paths: Array, scene: String) -> Dictionary:
	if store == null or store.state != "ready":
		return _fail("Das Addon ist gerade nicht mit Tasker verbunden – die Aufgabe lässt sich nicht nachschlagen.")
	var task: Variant = _find_task(wanted)
	if task == null:
		return _fail("Die Aufgabe %s gibt es im verbundenen Tasker-Projekt nicht (oder das Addon hat sie noch nicht geladen – kurz warten und noch einmal versuchen)." % wanted)
	if paths.is_empty():
		return _fail("Ohne Node-Pfade hängt nichts.")
	var hung := _hang(root, task["id"], scene, paths, true)
	if hung["failed"]:
		return hung
	return _ok("%s hängt jetzt an: %s" % [_task_label(task["id"]), hung["text"]])


## Hängt eine Aufgabe an Nodes – in der offenen Szene an das, was der Editor
## zeigt, in jeder anderen an das, was in ihrer Datei steht. Mit `really`
## false wird nur geprüft. `text` nennt, woran sie hängt.
func _hang(root: Node, task_id: String, scene: String, paths: Array, really: bool) -> Dictionary:
	scene = scene.strip_edges()
	# Ohne Szene wird nicht geraten: die offene kann längst eine andere sein als
	# die, in der nachgesehen wurde. Abgelehnt wird, bevor etwas angelegt ist.
	if scene == "":
		return _fail("`scene` fehlt. Jede Auskunft nennt die Szene in ihrer ersten Zeile („Szene: res://…“) – genau diesen Pfad mitgeben und noch einmal aufrufen.")
	if (root == null or scene != root.scene_file_path):
		var clean := []
		for p in paths:
			var path := str(p).strip_edges().trim_prefix("./")
			clean.append(path if path != "" else ".")
		var found := links.file_paths(scene, clean)
		if found["problem"] != "":
			return _fail(found["problem"])
		var places: Array = found["paths"]
		if really:
			var refused := links.link_file(task_id, scene, places)
			if refused != "":
				return _fail(refused)
			_unmark(scene, clean)
			_unmark(scene, places)
		var note := ""
		if places != clean:
			note = " – statt %s: die Szene ist nicht mehr offen, und was im Inneren einer instanzierten Szene liegt, lässt sich dann nur an der Instanz festmachen" % ", ".join(clean.filter(func(c: String) -> bool: return not places.has(c)))
		return _ok("%s (in %s)%s" % [", ".join(places), scene, note])
	if root.scene_file_path == "":
		return _fail("Die Szene muss erst gespeichert sein, bevor etwas an ihr hängen kann.")
	var nodes := []
	var names := []
	for p in paths:
		var node := _node(root, str(p))
		if node == null:
			return _fail(_missing(str(p)))
		nodes.append(node)
		names.append(_path(root, node))
	if really:
		var problem := links.link(task_id, nodes)
		if problem != "":
			return _fail(problem)
		_unmark(root.scene_file_path, names)
	return _ok(", ".join(names))


# -------------------------------------------------------- Vormerken

## Merkt die Nodes vor, mit allem, was `node_info` jetzt über sie sagt. Gibt
## zurück, was dem Nutzer dazu zu sagen ist.
func mark(nodes: Array) -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path == "":
		return "Die Szene muss erst gespeichert sein, bevor sich etwas vormerken lässt."
	var count := 0
	for node in nodes:
		if node != root and not root.is_ancestor_of(node):
			continue
		var path := _path(root, node)
		_unmark(root.scene_file_path, [path])
		_marks.append({"scene": root.scene_file_path, "path": path, "info": _node_info(root, path)["text"], "at": Time.get_ticks_msec()})
		count += 1
	while _marks.size() > MAX_MARKS:
		_marks.pop_front()
	if count == 0:
		return "Erst einen Node im Szenenbaum auswählen."
	return "%s für Claude vorgemerkt (insgesamt %d)." % ["1 Node" if count == 1 else "%d Nodes" % count, _marks.size()]


func _unmark(scene: String, paths: Array) -> void:
	_marks = _marks.filter(func(m: Dictionary) -> bool: return m["scene"] != scene or not paths.has(m["path"]))


func _marked(clear: bool) -> Dictionary:
	if _marks.is_empty():
		return _ok("Nichts vorgemerkt. (Im Szenenbaum: Rechtsklick → Tasker → „Für Claude vormerken“.)")
	var lines := ["Vorgemerkt: %d. Beim Anlegen `scene` und `paths` so übergeben, wie sie hier stehen." % _marks.size()]
	for m in _marks:
		var minutes := int((Time.get_ticks_msec() - int(m["at"])) / 60000.0)
		lines.append("")
		lines.append("── scene: %s   path: %s   (%s)" % [m["scene"], m["path"], "gerade eben" if minutes < 1 else "vor %d min" % minutes])
		lines.append(m["info"])
	if clear:
		_marks.clear()
	return _ok("\n".join(lines))


## Legt an und hängt an. Was am Anhängen scheitern kann, wird vorher geprüft –
## sonst läge die Aufgabe schon in Tasker und hinge nirgends.
func _create_task(root: Node, arguments: Dictionary) -> Dictionary:
	if store == null or store.state != "ready":
		return _fail("Das Addon ist gerade nicht mit Tasker verbunden.")
	var title := str(arguments.get("title", "")).strip_edges()
	if title == "":
		return _fail("Ohne Titel wird nichts angelegt.")
	var wanted: Variant = arguments.get("paths", [])
	var paths: Array = wanted if wanted is Array else []
	var scene := str(arguments.get("scene", ""))
	if not paths.is_empty():
		var checked := _hang(root, "", scene, paths, false)
		if checked["failed"]:
			return checked

	var project := Config.project_id()
	var fields := {"projectId": project, "title": title}
	if str(arguments.get("desc", "")).strip_edges() != "":
		fields["desc"] = str(arguments["desc"])
	if arguments.has("prio"):
		fields["prio"] = clampi(int(arguments["prio"]), 0, 3)
	for part in [["mark", "markId", store.ws.marks, "Markierung"], ["category", "categoryId", store.ws.categories, "Kategorie"]]:
		var asked := str(arguments.get(part[0], "")).strip_edges()
		if asked == "":
			continue
		var found := _named(part[2], asked, project)
		if found.is_empty():
			return _fail("Die %s „%s“ gibt es nicht. Zur Wahl: %s" % [part[3], asked, ", ".join(_names(part[2], project))])
		fields[part[1]] = found["id"]

	var made: Dictionary = await store.intake(fields)
	if not made["ok"]:
		return _fail("Tasker hat die Aufgabe nicht angelegt: %s" % made["error"])
	var task: Dictionary = made["object"]
	var label := "$%d „%s“" % [int(task.get("ref", 0)), task.get("title", "")]
	if paths.is_empty():
		return _ok("%s ist angelegt (Backlog, „Unsortiert“). An einem Node hängt sie nicht." % label)
	# Inzwischen kann der Nutzer die Szene gewechselt haben: dann geht es über die Datei.
	var hung := _hang(EditorInterface.get_edited_scene_root(), task["id"], scene, paths, true)
	if hung["failed"]:
		return _fail("%s ist angelegt, ließ sich aber nicht anhängen: %s" % [label, hung["text"]])
	return _ok("%s ist angelegt (Backlog, „Unsortiert“) und hängt an: %s" % [label, hung["text"]])


## Der Eintrag einer Liste (Markierungen, Kategorien) zu einem Namen oder
## einer ID – wenn die Liste Projekte kennt, nur aus diesem. Leer, wenn keiner passt.
static func _named(list: Array, asked: String, project: String) -> Dictionary:
	for exact in [true, false]:
		for x in list:
			if x.get("projectId", project) != project:
				continue
			if x["id"] == asked or (not exact and str(x.get("name", "")).to_lower() == asked.to_lower()):
				return x
	return {}


static func _names(list: Array, project: String) -> Array:
	var out := []
	for x in list:
		if x.get("projectId", project) == project:
			out.append(str(x.get("name", "")))
	return out


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
