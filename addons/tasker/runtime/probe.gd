extends Node
## Läuft im Spiel mit (Autoload „TaskerProbe“), aber nur, wenn es aus dem
## Editor heraus gestartet wurde: dann beantwortet es dem Addon die Frage, was
## im Spiel gerade geladen ist. In einem exportierten Spiel tut es nichts.
##
## Es liest nur. Gefragt wird über den Debugger (`core/game_link.gd`); die
## Antwort ist Text, wie ihn die Werkzeuge des MCP-Servers auch sonst liefern.

const CHANNEL := "tasker"
const MAX_LINES := 220
const MAX_DEPTH := 9


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not EngineDebugger.is_active():
		return
	EngineDebugger.register_message_capture(CHANNEL, _on_message)


func _exit_tree() -> void:
	if EngineDebugger.is_active() and EngineDebugger.has_capture(CHANNEL):
		EngineDebugger.unregister_message_capture(CHANNEL)


func _on_message(message: String, data: Array) -> bool:
	if message.trim_prefix(CHANNEL + ":") != "snapshot":
		return false
	EngineDebugger.send_message(CHANNEL + ":snapshot", [data[0] if data.size() > 0 else 0, describe(get_tree(), self)])
	return true


## Was im Spiel gerade geladen ist, als Text: die Szene, Kamera und Zeiger,
## dann der Baum. Bei jedem Node steht, aus welcher Szenendatei er stammt –
## daran lässt sich eine Aufgabe auch dann festmachen, wenn die Szene im
## Editor gar nicht offen ist.
static func describe(tree: SceneTree, skip: Node = null) -> String:
	var lines := []
	var scene := tree.current_scene
	if scene == null:
		lines.append("Geladene Szene: keine (current_scene ist leer)")
	else:
		lines.append("Geladene Szene: %s  (Wurzel „%s“)" % [scene.scene_file_path if scene.scene_file_path != "" else "zur Laufzeit gebaut", scene.name])
	if tree.paused:
		lines.append("Das Spiel ist pausiert.")

	var viewport := tree.root
	var camera_3d := viewport.get_camera_3d()
	if camera_3d != null:
		lines.append("Kamera (3D): %s  bei %s, Blick %s" % [_where(tree, camera_3d), _short(camera_3d.global_position), _short(-camera_3d.global_transform.basis.z)])
	var camera_2d := viewport.get_camera_2d()
	if camera_2d != null:
		lines.append("Kamera (2D): %s  bei %s" % [_where(tree, camera_2d), _short(camera_2d.global_position)])
	var hovered := viewport.gui_get_hovered_control()
	if hovered != null:
		lines.append("Unter dem Mauszeiger (UI): %s" % _where(tree, hovered))
	var focused := viewport.gui_get_focus_owner()
	if focused != null:
		lines.append("Tastaturfokus (UI): %s" % _where(tree, focused))

	lines.append("")
	lines.append("# Baum zur Laufzeit")
	lines.append("Eckige Klammern: Skript, „Instanz“ = aus dieser Szenendatei instanziert (die Kinder darunter stehen in ihr), „Laufzeit“ = per Code erzeugt, steht in keiner Szenendatei.")
	var todo := []
	var tops := tree.root.get_children()
	tops.reverse()
	for top in tops:
		todo.append([top, 0])
	var hidden := 0
	while not todo.is_empty():
		var entry: Array = todo.pop_back()
		var node: Node = entry[0]
		var depth: int = entry[1]
		if node == skip:
			continue
		if lines.size() >= MAX_LINES:
			hidden += 1
			continue
		var kids := node.get_children()
		var line := "%s%s" % ["  ".repeat(depth), _line(node)]
		if depth >= MAX_DEPTH and not kids.is_empty():
			lines.append("%s  [+%d Kinder]" % [line, kids.size()])
			continue
		lines.append(line)
		kids.reverse()
		for kid in kids:
			todo.append([kid, depth + 1])
	if hidden > 0:
		lines.append("… %d weitere Nodes nicht gezeigt." % hidden)
	return "\n".join(lines)


## Ein Node als Zeile: Name, Klasse, Skript und woher er stammt.
static func _line(node: Node) -> String:
	var text := "%s (%s)" % [node.name, node.get_class()]
	var script: Script = node.get_script()
	if script != null and script.resource_path != "":
		text += "  [%s]" % script.resource_path
	if node.scene_file_path != "":
		text += "  [Instanz: %s]" % node.scene_file_path
	elif node.owner == null and node.get_parent() != null and node.get_parent() != node.get_tree().root:
		text += "  [Laufzeit]"
	if node is CanvasItem and not node.visible:
		text += "  [unsichtbar]"
	elif node is Node3D and not node.visible:
		text += "  [unsichtbar]"
	return text


## Wo ein Node steht: sein Pfad im Baum und, wenn er aus einer Szenendatei
## stammt, die Datei und sein Pfad darin.
static func _where(tree: SceneTree, node: Node) -> String:
	var text := str(tree.root.get_path_to(node))
	var home := node if node.scene_file_path != "" else node.owner
	if home != null and home.scene_file_path != "":
		text += "  (in %s als „%s“)" % [home.scene_file_path, home.get_path_to(node)]
	return text


static func _short(v: Variant) -> String:
	if v is Vector3:
		return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]
	return "(%.1f, %.1f)" % [v.x, v.y]
