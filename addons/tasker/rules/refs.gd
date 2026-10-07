extends RefCounted
## Referenzen: welche Aufgabe an welcher Szene oder welchem Node hängt.
##
## Die Referenz steht an der Aufgabe, die Szenendatei bleibt unberührt. Vorerst
## ist das lokaler Zustand des Addons – hier sind nur die Regeln dazu,
## gespeichert wird woanders (`core/memory.gd`, im Editor `core/links.gd`).
##
## Eine Referenz:
## `{ taskId, kind, sceneUid, scenePath, nodePath, nodeId, nodeType, offset }`.
## `kind` ist "scene" für die Szene als Ganzes (ihre Wurzel) und sonst "node".
## `nodePath` zählt von der Wurzel der Szene, die Wurzel selbst ist ".".
## `nodeId` ist Godots feste Nummer des Nodes aus der Szenendatei, 0 solange
## unbekannt. Eine Aufgabe darf an mehreren Nodes hängen, ein Node mehrere
## Aufgaben tragen.

## Unter diesem Schlüssel liegen alle Referenzen des Projekts.
const KEY := "refs"

const ROOT := "."


static func make(task_id: String, scene_uid: String, scene_path: String, node_path: String, node_type: String, node_id := 0) -> Dictionary:
	return {
		"taskId": task_id,
		"kind": "scene" if node_path == ROOT else "node",
		"sceneUid": scene_uid,
		"scenePath": scene_path,
		"nodePath": node_path,
		"nodeId": node_id,
		"nodeType": node_type,
		"offset": Vector2.ZERO,
	}


## Liest den gespeicherten Zustand: was keine Referenz ist, fällt weg.
static func sanitize(saved: Variant) -> Array:
	var out := []
	if not saved is Array:
		return out
	for r in saved:
		if not r is Dictionary or str(r.get("taskId", "")) == "" or str(r.get("scenePath", "")) == "":
			continue
		var ref := make(str(r["taskId"]), str(r.get("sceneUid", "")), str(r["scenePath"]),
			str(r.get("nodePath", ROOT)), str(r.get("nodeType", "")), int(r.get("nodeId", 0)))
		if r.get("offset") is Vector2:
			ref["offset"] = r["offset"]
		if _find(out, ref) < 0:
			out.append(ref)
	return out


## Ob die Referenz in diese Szene zeigt. Die UID gilt, wo beide eine haben –
## sie übersteht das Umbenennen und Verschieben der Datei.
static func in_scene(ref: Dictionary, scene_uid: String, scene_path: String) -> bool:
	if scene_uid != "" and ref["sceneUid"] != "":
		return ref["sceneUid"] == scene_uid
	return ref["scenePath"] == scene_path


static func same(a: Dictionary, b: Dictionary) -> bool:
	return a["taskId"] == b["taskId"] and a["nodePath"] == b["nodePath"] and in_scene(a, b["sceneUid"], b["scenePath"])


## Hängt die Referenz an. Was es schon gibt, kommt nicht doppelt hinein.
static func add(refs: Array, ref: Dictionary) -> Array:
	var out := refs.duplicate()
	if _find(out, ref) < 0:
		out.append(ref)
	return out


static func remove(refs: Array, ref: Dictionary) -> Array:
	return refs.filter(func(r: Dictionary) -> bool: return not same(r, ref))


static func of_scene(refs: Array, scene_uid: String, scene_path: String) -> Array:
	return refs.filter(func(r: Dictionary) -> bool: return in_scene(r, scene_uid, scene_path))


static func of_task(refs: Array, task_id: String) -> Array:
	return refs.filter(func(r: Dictionary) -> bool: return r["taskId"] == task_id)


static func of_node(refs: Array, scene_uid: String, scene_path: String, node_path: String) -> Array:
	return refs.filter(func(r: Dictionary) -> bool: return r["nodePath"] == node_path and in_scene(r, scene_uid, scene_path))


## Ein Node der Szene heißt jetzt anders oder hängt woanders: seine Referenzen
## ziehen mit.
static func move(refs: Array, scene_uid: String, scene_path: String, from: String, to: String, node_type := "") -> Array:
	var out := []
	for r in refs:
		if r["nodePath"] == from and in_scene(r, scene_uid, scene_path):
			r = _at(r, to)
			if node_type != "":
				r["nodeType"] = node_type
		if _find(out, r) < 0:
			out.append(r)
	return out


## Die Datei der Szene liegt jetzt woanders.
static func rename_scene(refs: Array, scene_uid: String, scene_path: String) -> Array:
	var out := []
	for r in refs:
		if scene_uid != "" and r["sceneUid"] == scene_uid and r["scenePath"] != scene_path:
			r = r.duplicate()
			r["scenePath"] = scene_path
		out.append(r)
	return out


## Liest Godots feste Node-Nummern aus dem Text einer `.tscn`: Pfad → Nummer.
## Nodes ohne Nummer (etwa aus einer eingebetteten Szene) fehlen.
static func scene_ids(tscn: String) -> Dictionary:
	var out := {}
	var name_re := RegEx.create_from_string(" name=\"((?:[^\"\\\\]|\\\\.)*)\"")
	var parent_re := RegEx.create_from_string(" parent=\"((?:[^\"\\\\]|\\\\.)*)\"")
	var id_re := RegEx.create_from_string(" unique_id=(\\d+)")
	for line in tscn.split("\n"):
		if not line.begins_with("[node "):
			continue
		var name := name_re.search(line)
		var id := id_re.search(line)
		if name == null or id == null:
			continue
		var parent := parent_re.search(line)
		var path := ROOT
		if parent != null:
			var base := parent.get_string(1).c_unescape()
			path = name.get_string(1).c_unescape() if base == ROOT else base + "/" + name.get_string(1).c_unescape()
		out[path] = id.get_string(1).to_int()
	return out


## Gleicht die Referenzen einer Szene mit ihren Node-Nummern ab (`scene_ids`).
##
## Wer eine Nummer hat, folgt ihr an den Pfad, an dem sie jetzt steht – so
## übersteht die Referenz ein Umbenennen, auch wenn das Addon nicht lief. Wer
## noch keine hat, bekommt die seines Pfads.
##
## Mit `only` (Liste von Pfaden) werden nur diese Referenzen angefasst und nur
## verschoben: für Szenen, deren Datei gerade nicht dem Stand im Editor
## entspricht.
static func reconcile(refs: Array, scene_uid: String, scene_path: String, ids: Dictionary, only: Variant = null) -> Array:
	var by_id := {}
	for path in ids:
		by_id[ids[path]] = path
	var out := []
	for r in refs:
		if in_scene(r, scene_uid, scene_path) and (only == null or only.has(r["nodePath"])):
			if r["nodeId"] != 0 and by_id.has(r["nodeId"]):
				if by_id[r["nodeId"]] != r["nodePath"]:
					r = _at(r, by_id[r["nodeId"]])
			elif only == null and ids.has(r["nodePath"]):
				r = r.duplicate()
				r["nodeId"] = ids[r["nodePath"]]
		if _find(out, r) < 0:
			out.append(r)
	return out


## Lesbar, wohin die Referenz zeigt – etwa „level2.tscn › Enemies/Boss“.
static func label(ref: Dictionary) -> String:
	var file: String = ref["scenePath"].get_file()
	return file if ref["nodePath"] == ROOT else "%s › %s" % [file, ref["nodePath"]]


static func _at(ref: Dictionary, node_path: String) -> Dictionary:
	var r := ref.duplicate()
	r["nodePath"] = node_path
	r["kind"] = "scene" if node_path == ROOT else "node"
	return r


static func _find(refs: Array, ref: Dictionary) -> int:
	for i in refs.size():
		if same(refs[i], ref):
			return i
	return -1
