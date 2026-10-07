@tool
extends Node
## Die Karten im 2D- und 3D-Editor: was an den Nodes der offenen Szene hängt,
## wird dort als Karte eingeblendet.
##
## Die Karten sind Bilder derselben Karte wie in Dock und Tisch, über den
## Viewport gezeichnet. In der Szene entsteht dafür nichts. In 3D wird die
## Stelle des Nodes auf den Bildschirm gerechnet; die Karte liegt deshalb
## immer über der Geometrie.
##
## Gezeichnet und bedient wird über das Plugin, das der Editor dafür aufruft
## (`_forward_…_draw_over_viewport`, `_forward_…_gui_input`).

## Die Einblendungen sollen neu gezeichnet werden (`EditorPlugin.update_overlays`).
signal redraw_requested
signal task_requested(task_id: String)
## Die Karte wurde angeklickt.
signal task_selected(task_id: String)
## Etwas ging nicht – der Text sagt, warum.
signal problem(text: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Links := preload("../core/links.gd")
const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Refs := preload("../rules/refs.gd")
const Model := preload("../rules/model.gd")
const Tisch := preload("../rules/tisch.gd")
const DropCatcher := preload("drop_catcher.gd")

## So groß erscheint eine Karte im Viewport, gemessen an der im Dock.
const SCALE := 0.62
## In 3D schrumpft die Karte mit dem Abstand: volle Größe bis hier (in Metern) …
const NEAR := 6.0
## … und nie kleiner als so.
const MIN_SCALE := 0.38
## Abstand der Karte über ihrem Node, in Pixeln.
const RISE := 18.0
## Mehrere Karten am selben Node liegen so weit versetzt.
const FAN := Vector2(20, -8)
## Was keinen Ort hat – die Szene selbst oder ein Node ohne Lage –, liegt in
## dieser Ecke des Viewports.
const CORNER := Vector2(18, 52)
const DONE_ALPHA := 0.5
## Das Bild einer Karte wird doppelt so groß gerechnet, wie sie im Dock ist.
const FACE_FACTOR := 2

const MENU_OPEN := 100
const MENU_BROWSER := 101
const MENU_UNLINK := 102

## Der Schlüssel der 2D-Einblendung in `_hits`; die der 3D-Viewports stehen
## unter der Instanz-ID ihrer Kamera.
const VIEW_2D := 0
## Der Szenenbaum als Ziel einer gezogenen Karte.
const VIEW_TREE := -1
## So nah (in Pixeln) muss eine gezogene Karte an der Stelle eines Nodes sein,
## der keine eigene Fläche hat.
const DROP_REACH := 48.0

var store: Store
var images: Images
var links: Links

## Die Referenzen in die offene Szene, deren Aufgabe es gibt.
var _here: Array = []
## Die Kartenbilder: Aufgaben-ID → `{ viewport, card, stamp }`.
var _faces := {}
## Wo zuletzt Karten gezeichnet wurden: Ansicht → Liste von `{ rect, ref }`,
## die oberste zuletzt.
var _hits := {}
var _hover := ""
var _selected := ""
## Der Klick, der auf einer Karte begann, gehört bis zum Loslassen ihr.
var _held := false
var _signature := 0
var _menu: PopupMenu
var _menu_ref := {}
var _shadow: StyleBoxFlat
## Die Einblendungen, über die zuletzt gezeichnet wurde: Ansicht → Control.
var _overlays := {}
## Solange eine Karte aus dem Dock gezogen wird: die Fangfelder und worauf
## die Karte gerade fallen würde.
var _catchers: Array = []
var _drop_view := VIEW_TREE
var _drop_at := Vector2.ZERO
var _drop_node: Node
## Die Klickflächen über den Karten im 2D-Editor.
var _pads: Array = []
var _pads_queued := false


func _ready() -> void:
	_shadow = StyleBoxFlat.new()
	_shadow.bg_color = Color(0, 0, 0, 0.35)
	_shadow.set_corner_radius_all(int(Card.RADIUS * SCALE))
	_shadow.shadow_color = Color(0, 0, 0, 0.4)
	_shadow.shadow_size = 8
	_shadow.shadow_offset = Vector2(0, 3)

	_menu = PopupMenu.new()
	for i in Model.STATUS.size():
		_menu.add_icon_item(Palette.status_icon(Model.STATUS[i]), Palette.STATUS_LABELS[Model.STATUS[i]], i)
	_menu.add_separator()
	_menu.add_item("Aufgabe öffnen", MENU_OPEN)
	_menu.add_item("In Tasker öffnen (Browser)", MENU_BROWSER)
	_menu.add_separator()
	_menu.add_item("Vom Node lösen", MENU_UNLINK)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)

	store.changed.connect(_refresh)
	links.memory.changed.connect(_refresh)
	links.scene_changed.connect(_refresh)
	_refresh()


## Hebt die Karte dieser Aufgabe hervor.
func select(task_id: String) -> void:
	if _selected != task_id:
		_selected = task_id
		redraw_requested.emit()


# -------------------------------------------------------------- Bilder

func _refresh() -> void:
	_here = []
	if store.state == "ready":
		_here = links.here().filter(func(r: Dictionary) -> bool: return store.ws.task(r["taskId"]) != null)
	var wanted := {}
	for ref in _here:
		wanted[ref["taskId"]] = true
	for id in _faces.keys():
		if not wanted.has(id):
			_faces[id]["viewport"].queue_free()
			_faces.erase(id)
	for id in wanted:
		_show_face(id)
	redraw_requested.emit()


## Rechnet das Bild der Karte neu, wenn sich die Aufgabe geändert hat.
func _show_face(task_id: String) -> void:
	var t: Dictionary = store.ws.task(task_id)
	# Der Stand im Ganzen, weil auch Unteraufgaben und Labels auf der Karte stehen.
	var stamp := hash([t, store.ws.kids(task_id)])
	if not _faces.has(task_id):
		var viewport := SubViewport.new()
		viewport.size = Vector2i(Card.SIZE) * FACE_FACTOR
		viewport.size_2d_override = Vector2i(Card.SIZE)
		viewport.size_2d_override_stretch = true
		viewport.transparent_bg = true
		viewport.disable_3d = true
		viewport.gui_disable_input = true
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var frame := Control.new()
		frame.theme = EditorInterface.get_editor_theme()
		frame.size = Card.SIZE
		viewport.add_child(frame)
		var card := Card.new()
		frame.add_child(card)
		add_child(viewport)
		_faces[task_id] = {"viewport": viewport, "card": card, "stamp": 0}
	var face: Dictionary = _faces[task_id]
	if face["stamp"] == stamp:
		return
	face["stamp"] = stamp
	face["card"].show_task(store.ws, t, images, true)
	# Erledigtes verblasst erst beim Einblenden, nicht schon im Bild.
	face["card"].modulate.a = 1.0
	_render(task_id)
	# Das Titelbild der Karte kommt nach – dann noch einmal.
	for wait in [0.4, 2.0]:
		get_tree().create_timer(wait).timeout.connect(_render.bind(task_id))


func _render(task_id: String) -> void:
	if _faces.has(task_id):
		_faces[task_id]["viewport"].render_target_update_mode = SubViewport.UPDATE_ONCE
		# Das Bild steht erst nach dem nächsten Zeichnen.
		await RenderingServer.frame_post_draw
		redraw_requested.emit()


## Bewegt sich ein Node mit Karte oder eine Kamera, müssen die Karten mit.
func _process(_delta: float) -> void:
	if _here.is_empty():
		return
	var state := []
	for i in 4:
		var camera := EditorInterface.get_editor_viewport_3d(i).get_camera_3d()
		if camera != null:
			state.append_array([camera.global_transform, camera.fov, camera.size, camera.projection])
	for ref in _here:
		var node := links.node_of(ref)
		if node is Node3D:
			state.append(node.global_transform)
		elif node is CanvasItem:
			state.append(node.get_global_transform_with_canvas())
		else:
			state.append(node != null)
	var signature := hash(state)
	if signature != _signature:
		_signature = signature
		redraw_requested.emit()


# ------------------------------------------------------------ Zeichnen

## Zeichnet die Karten über den 2D-Editor.
func draw_2d(overlay: Control) -> void:
	var to_screen := EditorInterface.get_editor_viewport_2d().global_canvas_transform
	var placed := []
	for ref in _here:
		var node := _placed_node(ref, false)
		if node is Control:
			placed.append({"ref": ref, "at": to_screen * (node.get_global_transform_with_canvas() * Vector2(node.size.x / 2.0, 0.0)), "scale": 1.0, "depth": 0.0})
		elif node is CanvasItem:
			placed.append({"ref": ref, "at": to_screen * node.get_global_transform_with_canvas().origin, "scale": 1.0, "depth": 0.0})
		elif node == null and _has_no_place(ref):
			placed.append({"ref": ref, "scale": 1.0, "depth": 0.0})
	_draw(overlay, VIEW_2D, placed)


## Zeichnet die Karten über einen 3D-Viewport des Editors.
func draw_3d(overlay: Control) -> void:
	var viewport := _viewport_3d(overlay)
	var camera := viewport.get_camera_3d()
	if camera == null:
		return
	# Der Viewport kann gröber gerechnet sein, als er angezeigt wird.
	var stretch := overlay.size / Vector2(viewport.size)
	var placed := []
	for ref in _here:
		var node := _placed_node(ref, true)
		if node is Node3D:
			var at: Vector3 = node.global_position
			if camera.is_position_behind(at):
				continue
			var far := camera.global_position.distance_to(at)
			var scale := 1.0 if camera.projection == Camera3D.PROJECTION_ORTHOGONAL else clampf(NEAR / maxf(far, 0.01), MIN_SCALE, 1.0)
			placed.append({"ref": ref, "at": camera.unproject_position(at) * stretch, "scale": scale, "depth": far})
		elif node == null and _has_no_place(ref):
			placed.append({"ref": ref, "scale": 1.0, "depth": 0.0})
	# Fernes zuerst, damit Nahes darüber liegt.
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] > b["depth"])
	_draw(overlay, camera.get_instance_id(), placed)


func _draw(overlay: Control, view: int, placed: Array) -> void:
	var hits := []
	var at_node := {}
	var in_corner := 0
	for p in placed:
		var ref: Dictionary = p["ref"]
		var face = _faces.get(ref["taskId"])
		if face == null:
			continue
		var size: Vector2 = Card.SIZE * SCALE * p["scale"]
		var rect: Rect2
		if p.has("at"):
			var nth: int = at_node.get(ref["nodePath"], 0)
			at_node[ref["nodePath"]] = nth + 1
			var foot: Vector2 = p["at"] + FAN * nth * p["scale"]
			rect = Rect2(foot - Vector2(size.x / 2.0, size.y + RISE * p["scale"]), size)
			# Der Faden von der Karte zum Node.
			overlay.draw_line(p["at"], Vector2(rect.get_center().x, rect.end.y), Color(Palette.ACCENT, 0.8), 1.5, true)
			overlay.draw_circle(p["at"], 3.5, Palette.ACCENT)
		else:
			rect = Rect2(CORNER + Vector2(in_corner * (size.x + 10.0), 0.0), size)
			in_corner += 1

		var t = store.ws.task(ref["taskId"])
		var alpha := DONE_ALPHA if t != null and t.get("status") == "done" else 1.0
		var marked: bool = ref["taskId"] == _selected or ref["taskId"] == _hover
		if marked:
			alpha = maxf(alpha, 0.9)
		if alpha == 1.0:
			overlay.draw_style_box(_shadow, rect)
		overlay.draw_texture_rect(face["viewport"].get_texture(), rect, false, Color(1, 1, 1, alpha))
		if marked:
			overlay.draw_rect(rect.grow(2.0), Palette.ACCENT if ref["taskId"] == _selected else Color(Palette.ACCENT, 0.6), false, 2.0)
		hits.append({"rect": rect, "ref": ref})
	_hits[view] = hits
	_overlays[view] = overlay
	if view == VIEW_2D and not _pads_queued:
		_pads_queued = true
		_sync_pads.call_deferred()


## Der Node, an dessen Stelle die Karte in dieser Ansicht liegt: der Node der
## Referenz oder, hat er selbst keine Lage, der nächste darüber, der eine hat.
func _placed_node(ref: Dictionary, in_3d: bool) -> Node:
	var node := links.node_of(ref)
	var root := EditorInterface.get_edited_scene_root()
	while node != null:
		if (in_3d and node is Node3D) or (not in_3d and node is CanvasItem):
			return node
		if node is Node3D or node is CanvasItem or node == root:
			return null
		node = node.get_parent()
	return null


## Ob die Referenz gar keinen Ort hat – dann liegt ihre Karte in der Ecke,
## in 2D wie in 3D.
func _has_no_place(ref: Dictionary) -> bool:
	var node := links.node_of(ref)
	if node == null:
		return false
	return _placed_node(ref, true) == null and _placed_node(ref, false) == null


## Der 3D-Viewport, über dem diese Einblendung liegt.
static func _viewport_3d(overlay: Control) -> SubViewport:
	for i in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(i)
		if overlay.get_parent() != null and overlay.get_parent().is_ancestor_of(viewport):
			return viewport
	return EditorInterface.get_editor_viewport_3d(0)


# ------------------------------------------------------------- Bedienen

## Maus und Tasten über dem 2D-Editor (`VIEW_2D`) oder einem 3D-Viewport (die
## Instanz-ID seiner Kamera). Wahr, wenn eine Karte das Ereignis genommen hat –
## dann bekommt der Editor es nicht.
func input(view: int, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		var over := _hit(view, event.position)
		var id: String = over.get("taskId", "")
		if id != _hover:
			_hover = id
			redraw_requested.emit()
		return false
	if not event is InputEventMouseButton:
		return false
	if not event.pressed:
		var was := _held
		if event.button_index == MOUSE_BUTTON_LEFT:
			_held = false
		return was and event.button_index == MOUSE_BUTTON_LEFT
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	var ref := _hit(view, event.position)
	if ref.is_empty():
		return false

	_click(ref, event)
	_held = event.button_index == MOUSE_BUTTON_LEFT
	return true


## Ein Klick auf die Karte dieser Referenz: markieren, öffnen oder das Menü.
func _click(ref: Dictionary, event: InputEventMouseButton) -> void:
	select(ref["taskId"])
	task_selected.emit(ref["taskId"])
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_menu_ref = ref
		_menu.position = Vector2i(DisplayServer.mouse_get_position())
		_menu.popup()
	elif event.double_click:
		task_requested.emit(ref["taskId"])


## Die Referenz der obersten Karte an dieser Stelle – leer, wenn dort keine ist.
func _hit(view: int, at: Vector2) -> Dictionary:
	var hits: Array = _hits.get(view, [])
	for i in range(hits.size() - 1, -1, -1):
		if hits[i]["rect"].has_point(at):
			return hits[i]["ref"]
	return {}


func _on_menu(id: int) -> void:
	var task_id: String = _menu_ref.get("taskId", "")
	var t = store.ws.task(task_id)
	if t == null:
		return
	match id:
		MENU_OPEN:
			task_requested.emit(task_id)
		MENU_BROWSER:
			OS.shell_open(store.web_url(t))
		MENU_UNLINK:
			links.unlink(_menu_ref)
		_:
			if id < Model.STATUS.size():
				_set_status(t, Model.STATUS[id])


func _set_status(t: Dictionary, status: String) -> void:
	if t.get("status") == status:
		return
	# Dieselbe Regel wie in Tasker: erledigt erst, wenn alles darunter erledigt ist.
	var refusal := Tisch.done_refusal(store.ws, t) if status == "done" else ""
	if refusal != "":
		problem.emit(refusal)
		return
	var res := await store.patch("task", t["id"], {"status": status})
	if not res["ok"]:
		problem.emit(str(res["error"]))


# ------------------------------------------------- Karte hierher ziehen

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_BEGIN:
		if DropCatcher.is_card(get_viewport().gui_get_drag_data()):
			_begin_drag()
	elif what == NOTIFICATION_DRAG_END:
		for catcher in _catchers:
			if is_instance_valid(catcher):
				catcher.queue_free()
		_catchers = []
		_drop_node = null


## Legt über Szenenbaum und Viewports je ein Fangfeld.
func _begin_drag() -> void:
	if EditorInterface.get_edited_scene_root() == null:
		return
	var targets := {VIEW_TREE: _scene_tree()}
	targets.merge(_overlays)
	for view in targets:
		var target = targets[view]
		if not is_instance_valid(target) or not target.is_visible_in_tree():
			continue
		var catcher := DropCatcher.new()
		catcher.painter = _paint_drop.bind(view)
		catcher.hovered.connect(_on_hover.bind(view, catcher))
		catcher.dropped.connect(_on_drop.bind(view, catcher))
		target.add_child(catcher)
		_catchers.append(catcher)


func _on_hover(at: Vector2, view: int, catcher: Control) -> void:
	_drop_view = view
	_drop_at = at
	_drop_node = _pick(view, at, catcher)


func _on_drop(at: Vector2, task_id: String, view: int, catcher: Control) -> void:
	var node := _pick(view, at, catcher)
	if node == null:
		problem.emit("An dieser Stelle ist kein Node, an den die Aufgabe könnte.")
		return
	var refusal := links.link(task_id, [node])
	if refusal != "":
		problem.emit(refusal)


## Zeigt an der gezogenen Karte, an welchen Node sie fallen würde.
func _paint_drop(catcher: Control, view: int) -> void:
	if view != _drop_view:
		return
	if view == VIEW_TREE:
		var item: TreeItem = catcher.get_parent().get_item_at_position(_drop_at)
		if item != null and _drop_node != null:
			var row: Rect2 = catcher.get_parent().get_item_area_rect(item)
			var band := Rect2(0.0, row.position.y, catcher.size.x, row.size.y)
			catcher.draw_rect(band, Color(Palette.ACCENT, 0.25))
			catcher.draw_rect(band, Palette.ACCENT, false, 1.5)
		return
	var text := "Anhängen an: %s" % _drop_node.name if _drop_node != null else "Hier ist kein Node"
	var font := catcher.get_theme_default_font()
	var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
	var at := _drop_at + Vector2(18, 26)
	catcher.draw_rect(Rect2(at - Vector2(6, 4), size + Vector2(12, 8)), Color(0.05, 0.08, 0.07, 0.9))
	catcher.draw_string(font, at + Vector2(0, font.get_ascent(14)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Palette.ACCENT if _drop_node != null else Palette.MUTED)


## Der Node der offenen Szene an dieser Stelle der Ansicht.
func _pick(view: int, at: Vector2, catcher: Control) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var node: Node = null
	if view == VIEW_TREE:
		# Der Szenenbaum merkt sich an jeder Zeile den Pfad ihres Nodes.
		var item: TreeItem = catcher.get_parent().get_item_at_position(at)
		var path = item.get_metadata(0) if item != null else null
		if path is NodePath:
			node = get_tree().root.get_node_or_null(path)
		return node if node != null and (node == root or root.is_ancestor_of(node)) else null
	if view == VIEW_2D:
		node = _pick_2d(root, at)
	else:
		node = _pick_3d(root, catcher.get_parent(), at)
	# Wie beim Klicken im Editor: aus einer eingebetteten Szene wird ihr Kopf.
	while node != null and node != root and node.owner != root:
		node = node.get_parent()
	return node


## Das oberste 2D-Element unter der Stelle, sonst der Node, dessen Ursprung am
## nächsten liegt.
func _pick_2d(root: Node, at: Vector2) -> Node:
	var to_screen := EditorInterface.get_editor_viewport_2d().global_canvas_transform
	var over: Node = null
	var near: Node = null
	var reach := DROP_REACH
	for node in _all(root):
		if not node is CanvasItem or not node.is_visible_in_tree():
			continue
		var xf: Transform2D = to_screen * node.get_global_transform_with_canvas()
		var rect = null
		if node is Control:
			rect = Rect2(Vector2.ZERO, node.size)
		elif node.has_method("get_rect"):
			rect = node.get_rect()
		if rect is Rect2 and rect.has_point(xf.affine_inverse() * at):
			over = node
		var far := xf.origin.distance_to(at)
		if far < reach:
			reach = far
			near = node
	return over if over != null else near


## Das vorderste 3D-Objekt, dessen Hülle der Blick durch die Stelle trifft,
## sonst der Node, dessen Ursprung am nächsten liegt.
func _pick_3d(root: Node, overlay: Control, at: Vector2) -> Node:
	var viewport := _viewport_3d(overlay)
	var camera := viewport.get_camera_3d()
	if camera == null:
		return null
	var stretch := overlay.size / Vector2(viewport.size)
	var from := camera.project_ray_origin(at / stretch)
	var dir := camera.project_ray_normal(at / stretch)
	var over: Node = null
	var depth := INF
	var near: Node = null
	var reach := DROP_REACH
	for node in _all(root):
		if not node is Node3D or not node.is_visible_in_tree():
			continue
		if node is VisualInstance3D:
			var inverse: Transform3D = node.global_transform.affine_inverse()
			var hit = node.get_aabb().intersects_ray(inverse * from, inverse.basis * dir)
			if hit is Vector3:
				var far: float = from.distance_to(node.global_transform * hit)
				if far < depth:
					depth = far
					over = node
		if not camera.is_position_behind(node.global_position):
			var off: float = (camera.unproject_position(node.global_position) * stretch).distance_to(at)
			if off < reach:
				reach = off
				near = node
	return over if over != null else near


static func _all(root: Node) -> Array:
	var out := [root]
	var i := 0
	while i < out.size():
		out.append_array(out[i].get_children())
		i += 1
	return out


## Der Baum des Szenen-Docks – null, wenn er nicht zu finden ist.
static func _scene_tree() -> Tree:
	for editor in EditorInterface.get_base_control().find_children("*", "SceneTreeEditor", true, false):
		if editor.is_visible_in_tree():
			var trees: Array = editor.find_children("*", "Tree", true, false)
			if not trees.is_empty():
				return trees[0]
	return null


# --------------------------------------------- Klickflächen im 2D-Editor

## Der 2D-Editor reicht Maus und Tasten nur weiter, solange ein Node
## ausgewählt ist, den das Plugin bearbeitet. Deshalb liegt dort über jeder
## Karte eine unsichtbare Fläche, die Klicks selbst annimmt. Mausrad und
## mittlere Taste gehen durch sie hindurch an den Editor.
func _sync_pads() -> void:
	_pads_queued = false
	var overlay = _overlays.get(VIEW_2D)
	if not is_instance_valid(overlay):
		return
	_pads = _pads.filter(is_instance_valid)
	var hits: Array = _hits.get(VIEW_2D, [])
	while _pads.size() < hits.size():
		var pad := Control.new()
		pad.mouse_filter = Control.MOUSE_FILTER_PASS
		pad.gui_input.connect(_on_pad_input.bind(pad))
		pad.mouse_entered.connect(_on_pad_hover.bind(pad, true))
		pad.mouse_exited.connect(_on_pad_hover.bind(pad, false))
		overlay.add_child(pad)
		_pads.append(pad)
	for i in _pads.size():
		var pad: Control = _pads[i]
		pad.visible = i < hits.size()
		if pad.visible:
			var rect: Rect2 = hits[i]["rect"]
			if pad.position != rect.position or pad.size != rect.size:
				pad.position = rect.position
				pad.size = rect.size
			pad.set_meta("ref", hits[i]["ref"])


func _on_pad_input(event: InputEvent, pad: Control) -> void:
	if event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			_click(pad.get_meta("ref"), event)
		pad.accept_event()


func _on_pad_hover(pad: Control, inside: bool) -> void:
	var id: String = pad.get_meta("ref", {}).get("taskId", "")
	if inside or _hover == id:
		_hover = id if inside else ""
		redraw_requested.emit()


func _exit_tree() -> void:
	for control in _pads + _catchers:
		if is_instance_valid(control):
			control.queue_free()
	_pads = []
	_catchers = []
