@tool
extends Node
## Die Verknüpfungen von Aufgaben mit Szenen und Nodes, wie der Editor sie
## sieht: anhängen, lösen, hinspringen – und mitziehen, wenn ein Node
## umbenannt oder umgehängt wird.
##
## Die Regeln stehen in `rules/refs.gd`, gemerkt wird lokal (`core/memory.gd`).
## Szenendateien werden nur gelesen, nie geschrieben.

## Die offene Szene hat gewechselt. Ändern sich die Referenzen selbst, meldet
## das `memory.changed`.
signal scene_changed

const Refs := preload("../rules/refs.gd")
const Memory := preload("memory.gd")

var memory: Memory

## Die Nodes der offenen Szene, an denen etwas hängt: `{ node, path }` mit der
## Instanz-ID und dem Pfad, unter dem die Referenz sie kennt.
var _tracked: Array = []
var _sync_queued := false


func _ready() -> void:
	get_tree().node_renamed.connect(_on_node_moved)
	get_tree().node_added.connect(_on_node_moved)
	memory.changed.connect(_track)
	on_scene_changed()


func all() -> Array:
	return Refs.sanitize(memory.read(Refs.KEY, []))


func of_task(task_id: String) -> Array:
	return Refs.of_task(all(), task_id)


## Die Referenzen in die offene Szene.
func here() -> Array:
	var scene := _scene()
	return [] if scene.is_empty() else Refs.of_scene(all(), scene["uid"], scene["path"])


## Die Referenzen an diesem Node der offenen Szene.
func of_node(node: Node) -> Array:
	var scene := _scene()
	if scene.is_empty() or not _inside(scene["root"], node):
		return []
	return Refs.of_node(all(), scene["uid"], scene["path"], str(scene["root"].get_path_to(node)))


## Die im Szenenbaum ausgewählten Nodes.
func selection() -> Array:
	return EditorInterface.get_selection().get_selected_nodes()


## Hängt die Aufgabe an die Nodes. Gibt zurück, warum es nicht ging – leer,
## wenn es ging.
func link(task_id: String, nodes: Array) -> String:
	var scene := _scene()
	if scene.is_empty():
		return "Die Szene muss erst gespeichert sein, bevor etwas an ihr hängen kann."
	nodes = nodes.filter(func(n: Node) -> bool: return _inside(scene["root"], n))
	if nodes.is_empty():
		return "Erst einen Node im Szenenbaum auswählen."
	var ids := _ids(scene["path"])
	var refs := all()
	for node in nodes:
		var path := str(scene["root"].get_path_to(node))
		refs = Refs.add(refs, Refs.make(task_id, scene["uid"], scene["path"], path, node.get_class(), int(ids.get(path, 0))))
	memory.write(Refs.KEY, refs)
	return ""


func unlink(ref: Dictionary) -> void:
	memory.write(Refs.KEY, Refs.remove(all(), ref))


## Der Node, auf den die Referenz zeigt – wenn sie in die offene Szene zeigt
## und er dort zu finden ist.
func node_of(ref: Dictionary) -> Node:
	var scene := _scene()
	if scene.is_empty() or not Refs.in_scene(ref, scene["uid"], scene["path"]):
		return null
	return scene["root"].get_node_or_null(NodePath(ref["nodePath"]))


## „Zeig mir, wo“: öffnet die Szene und wählt den Node aus. Gibt zurück, warum
## es nicht ging – leer, wenn es ging.
func reveal(ref: Dictionary) -> String:
	var path := _current_path(ref)
	if not ResourceLoader.exists(path):
		return "Die Szene %s gibt es nicht mehr." % path
	var scene := _scene()
	if scene.is_empty() or not Refs.in_scene(ref, scene["uid"], scene["path"]):
		EditorInterface.open_scene_from_path(path)
		await get_tree().process_frame
	# Nach dem Öffnen kann der Abgleich den Pfad berichtigt haben.
	for r in of_task(ref["taskId"]):
		if r["nodeId"] != 0 and r["nodeId"] == ref["nodeId"] and Refs.in_scene(r, ref["sceneUid"], ref["scenePath"]):
			ref = r
	var node := node_of(ref)
	if node == null:
		return "%s ist in der Szene nicht mehr zu finden." % ref["nodePath"]
	var chosen := EditorInterface.get_selection()
	chosen.clear()
	chosen.add_node(node)
	EditorInterface.edit_node(node)
	if node is Node3D:
		EditorInterface.set_main_screen_editor("3D")
	elif node is CanvasItem:
		EditorInterface.set_main_screen_editor("2D")
	return ""


# ------------------------------------------------------------ Mitziehen

## Die offene Szene hat gewechselt (`EditorPlugin.scene_changed`).
func on_scene_changed() -> void:
	var scene := _scene()
	if not scene.is_empty():
		var refs := Refs.rename_scene(all(), scene["uid"], scene["path"])
		# Was im Editor nicht zu finden ist, wurde vielleicht umbenannt, als das
		# Addon nicht lief – die Node-Nummer aus der Datei weiß, wohin.
		var lost := []
		for r in Refs.of_scene(refs, scene["uid"], scene["path"]):
			if r["nodeId"] != 0 and scene["root"].get_node_or_null(NodePath(r["nodePath"])) == null:
				lost.append(r["nodePath"])
		if not lost.is_empty():
			refs = Refs.reconcile(refs, scene["uid"], scene["path"], _ids(scene["path"], true), lost)
		_write_if_changed(refs)
	_track()
	scene_changed.emit()


## Eine Szene wurde gespeichert: Datei und Editor stimmen überein, also lassen
## sich Pfade und Node-Nummern abgleichen.
func on_scene_saved(path: String) -> void:
	var uid := _uid(path)
	var refs := all()
	if Refs.of_scene(refs, uid, path).is_empty():
		return
	_write_if_changed(Refs.reconcile(Refs.rename_scene(refs, uid, path), uid, path, _ids(path, true)))


func _on_node_moved(node: Node) -> void:
	if _tracked.is_empty() or _sync_queued:
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or not _inside(root, node):
		return
	_sync_queued = true
	_sync.call_deferred()


## Sieht nach, ob die Nodes mit Referenzen noch dort sind, wo die Referenz sie
## vermutet, und zieht die Referenz nach.
func _sync() -> void:
	_sync_queued = false
	var scene := _scene()
	if scene.is_empty():
		return
	var refs := all()
	for entry in _tracked:
		var node := instance_from_id(entry["node"]) as Node
		# Ein gelöschter Node bleibt vermerkt: „Rückgängig“ bringt ihn wieder.
		if node == null or not _inside(scene["root"], node):
			continue
		var path := str(scene["root"].get_path_to(node))
		if path != entry["path"]:
			refs = Refs.move(refs, scene["uid"], scene["path"], entry["path"], path, node.get_class())
	_write_if_changed(refs)


## Merkt sich, welche Nodes der offenen Szene Referenzen tragen.
func _track() -> void:
	_tracked = []
	var scene := _scene()
	if scene.is_empty():
		return
	var seen := {}
	for r in Refs.of_scene(all(), scene["uid"], scene["path"]):
		var node: Node = scene["root"].get_node_or_null(NodePath(r["nodePath"]))
		if node != null and not seen.has(r["nodePath"]):
			seen[r["nodePath"]] = true
			_tracked.append({"node": node.get_instance_id(), "path": r["nodePath"]})


func _write_if_changed(refs: Array) -> void:
	if refs != all():
		memory.write(Refs.KEY, refs)


# --------------------------------------------------------------- Szene

## Die offene Szene: `{ root, path, uid }` – leer, wenn keine offen oder sie
## noch nie gespeichert ist.
func _scene() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path == "":
		return {}
	return {"root": root, "path": root.scene_file_path, "uid": _uid(root.scene_file_path)}


static func _uid(path: String) -> String:
	var uid := ResourceUID.path_to_uid(path)
	return uid if uid.begins_with("uid://") else ""


## Wo die Szene der Referenz heute liegt.
static func _current_path(ref: Dictionary) -> String:
	if ref["sceneUid"] != "":
		var id := ResourceUID.text_to_id(ref["sceneUid"])
		if ResourceUID.has_id(id):
			return ResourceUID.get_id_path(id)
	return ref["scenePath"]


static func _inside(root: Node, node: Node) -> bool:
	return node == root or root.is_ancestor_of(node)


## Die Node-Nummern aus der Szenendatei. Hat die Szene ungespeicherte
## Änderungen, passen die Pfade der Datei nicht zum Editor – dann nur mit
## `even_unsaved`.
func _ids(path: String, even_unsaved := false) -> Dictionary:
	if path.get_extension() != "tscn":
		return {}
	if not even_unsaved and EditorInterface.get_unsaved_scenes().has(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	return Refs.scene_ids(text)
