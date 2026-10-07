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
const SceneView := preload("../rules/scene_view.gd")
const Hand := preload("../rules/hand.gd")

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
const MENU_HOME := 103

## Was in `_hits` steht: eine Karte, ein Pin, ein zugeklappter Stapel oder
## der Knopf, der einen aufgefächerten wieder zuklappt.
const CARD := "card"
const PIN := "pin"
const STACK := "stack"
const CLOSE := "close"

## Unter dieser Zoomstufe des 2D-Editors wird die Karte zum Pin …
const PIN_ZOOM := 0.35
## … in 3D ab diesem Abstand in Metern, ohne Perspektive ab dieser Bildhöhe.
const PIN_FAR := 30.0
const PIN_SIZE := 60.0
## Pins, die näher als so beieinander liegen, werden einer; so groß ist auch
## ihre Klickfläche.
const PIN_REACH := 20.0
## Karten werden zum Stapel, wenn ihre Mitten näher als dieser Teil einer
## Kartenbreite beieinander liegen.
const STACK_REACH := 0.5
## So groß sind die Karten eines Fächers aus Pins und die Karte, die ein Pin
## unter dem Zeiger zeigt.
const SPREAD_SCALE := 0.8
const SPREAD_GAP := 6.0
## Ab so vielen Pixeln wird aus einem Klick ein Ziehen.
const DRAG_START := 5.0

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
## Der Filter aus der Viewport-Leiste (`SceneView.MODES`).
var mode := SceneView.ALL: set = set_mode

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
var _plate: StyleBoxFlat
## Der aufgefächerte Stapel (`_key` seiner obersten Karte), leer wenn keiner.
var _open := ""
## Die Karte, die gerade vom Node weggezogen wird: `{ ref, view, from, start,
## home, scale, offset, moved }` – leer, wenn keine gegriffen ist.
var _grab := {}
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
	_plate = StyleBoxFlat.new()
	_plate.bg_color = Palette.SURFACE.darkened(0.15)
	_plate.border_color = Palette.LINE_STRONG
	_plate.set_border_width_all(1)
	_plate.set_corner_radius_all(int(Card.RADIUS * SCALE))
	mode = SceneView.mode_of(links.memory.read(SceneView.KEY))

	_menu = PopupMenu.new()
	for i in Model.STATUS.size():
		_menu.add_icon_item(Palette.status_icon(Model.STATUS[i]), Palette.STATUS_LABELS[Model.STATUS[i]], i)
	_menu.add_separator()
	_menu.add_item("Aufgabe öffnen", MENU_OPEN)
	_menu.add_item("In Tasker öffnen (Browser)", MENU_BROWSER)
	_menu.add_separator()
	_menu.add_item("Karte zurück an den Node", MENU_HOME)
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


## Stellt den Filter um und merkt ihn sich.
func set_mode(value: String) -> void:
	if value == mode:
		return
	mode = value
	if is_inside_tree() and links.memory.read(SceneView.KEY) != mode:
		links.memory.write(SceneView.KEY, mode)


## Welche Aufgaben der Filter durchlässt – null heißt alle.
func _allowed() -> Variant:
	var m = Tisch.active_milestone(store.ws, store.project_id)
	var hand = links.memory.read(Hand.key(m["id"]), null) if m != null else null
	return SceneView.allowed(store.ws, store.project_id, mode, hand)


# -------------------------------------------------------------- Bilder

func _refresh() -> void:
	_here = []
	if store.state == "ready":
		var allowed = _allowed()
		_here = links.here().filter(func(r: Dictionary) -> bool:
			return store.ws.task(r["taskId"]) != null and (allowed == null or allowed.has(r["taskId"])))
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
	# Weit herausgezoomt bleibt von der Karte nur ein Pin.
	var pin := to_screen.get_scale().x < PIN_ZOOM
	var placed := []
	for ref in _here:
		var node := _placed_node(ref, false)
		if node is Control:
			placed.append({"ref": ref, "at": to_screen * (node.get_global_transform_with_canvas() * Vector2(node.size.x / 2.0, 0.0)), "scale": 1.0, "depth": 0.0, "pin": pin})
		elif node is CanvasItem:
			placed.append({"ref": ref, "at": to_screen * node.get_global_transform_with_canvas().origin, "scale": 1.0, "depth": 0.0, "pin": pin})
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
	var flat := camera.projection == Camera3D.PROJECTION_ORTHOGONAL
	var placed := []
	for ref in _here:
		var node := _placed_node(ref, true)
		if node is Node3D:
			var at: Vector3 = node.global_position
			if camera.is_position_behind(at):
				continue
			var far := camera.global_position.distance_to(at)
			var scale := 1.0 if flat else clampf(NEAR / maxf(far, 0.01), MIN_SCALE, 1.0)
			var pin := camera.size > PIN_SIZE if flat else far > PIN_FAR
			placed.append({"ref": ref, "at": camera.unproject_position(at) * stretch, "scale": scale, "depth": far, "pin": pin})
		elif node == null and _has_no_place(ref):
			placed.append({"ref": ref, "scale": 1.0, "depth": 0.0})
	# Fernes zuerst, damit Nahes darüber liegt.
	placed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["depth"] > b["depth"])
	_draw(overlay, camera.get_instance_id(), placed)


## Zeichnet, was in dieser Ansicht liegt, und merkt sich in `_hits`, wo.
func _draw(overlay: Control, view: int, placed: Array) -> void:
	var hits := []
	var cards := []
	var pins := []
	var grabbed := []
	var in_corner := 0
	for p in placed:
		var size: Vector2 = Card.SIZE * SCALE * p["scale"]
		if not p.has("at"):
			# Ohne Ort: nebeneinander in der Ecke.
			var rect := Rect2(CORNER + Vector2(in_corner * (size.x + 10.0), 0.0), size)
			in_corner += 1
			_draw_card(overlay, p["ref"], rect)
			hits.append({"kind": CARD, "rect": rect, "ref": p["ref"]})
			continue
		var mine := _is_grabbed(p["ref"], view)
		var offset: Vector2 = (_grab["offset"] if mine else p["ref"]["offset"]) * p["scale"]
		p["home"] = p["at"] - Vector2(size.x / 2.0, size.y + RISE * p["scale"])
		p["rect"] = Rect2(p["home"] + offset, size)
		if mine:
			grabbed.append(p)
		elif p["pin"]:
			pins.append(p)
		else:
			cards.append(p)

	var late := []
	for group in _groups(cards, false):
		if group.size() == 1:
			_draw_single(overlay, group[0], hits)
		elif _open == _key(group[0]["ref"]):
			_draw_spread(overlay, group, hits, false)
		else:
			_draw_stack(overlay, group, hits)
	for group in _groups(pins, true):
		var first: Dictionary = group[0]
		if group.size() > 1 and _open == _key(first["ref"]):
			_draw_spread(overlay, group, hits, true)
			continue
		var t = store.ws.task(first["ref"]["taskId"])
		_draw_pin(overlay, first["at"], Palette.status_color(t.get("status") if t != null else null), group.size())
		var spot := Rect2(first["at"] - Vector2(PIN_REACH, PIN_REACH) / 2.0, Vector2(PIN_REACH, PIN_REACH))
		if group.size() > 1:
			hits.append({"kind": STACK, "rect": spot, "key": _key(first["ref"])})
		else:
			hits.append({"kind": PIN, "rect": spot, "ref": first["ref"]})
			if first["ref"]["taskId"] == _hover:
				late.append(first)
	# Die Karte, die gerade gezogen wird, liegt über allem.
	for p in grabbed:
		_draw_single(overlay, p, hits)
	# Unter dem Zeiger zeigt ein Pin seine Karte.
	for p in late:
		var size: Vector2 = Card.SIZE * SCALE * SPREAD_SCALE
		var rect := Rect2(p["at"] - Vector2(size.x / 2.0, size.y + PIN_REACH), size)
		rect.position = rect.position.clamp(Vector2(4, 4), overlay.size - size - Vector2(4, 4))
		_draw_card(overlay, p["ref"], rect)

	_hits[view] = hits
	_overlays[view] = overlay
	if view == VIEW_2D and not _pads_queued:
		_pads_queued = true
		_sync_pads.call_deferred()


## Fasst zusammen, was so nah beieinander liegt, dass es sich verdecken würde.
func _groups(items: Array, as_pins: bool) -> Array:
	if items.is_empty():
		return []
	var reach := PIN_REACH
	if not as_pins:
		var smallest := 1.0
		for p in items:
			smallest = minf(smallest, p["scale"])
		reach = Card.SIZE.x * SCALE * smallest * STACK_REACH
	var points := items.map(func(p: Dictionary) -> Vector2: return p["at"] if as_pins else p["rect"].get_center())
	return SceneView.clusters(points, reach).map(func(group: Array) -> Array:
		return group.map(func(i: int) -> Dictionary: return items[i]))


## Eine Karte für sich: Faden zum Node, die Karte, und sie lässt sich wegziehen.
func _draw_single(overlay: Control, p: Dictionary, hits: Array) -> void:
	_draw_thread(overlay, p["at"], p["rect"])
	_draw_card(overlay, p["ref"], p["rect"])
	hits.append({"kind": CARD, "rect": p["rect"], "ref": p["ref"], "home": p["home"], "scale": p["scale"]})


## Ein zugeklappter Stapel: die oberste Karte, dahinter angedeutet der Rest
## und die Anzahl. Ein Klick fächert ihn auf.
func _draw_stack(overlay: Control, group: Array, hits: Array) -> void:
	var rect: Rect2 = group[0]["rect"]
	for p in group:
		_draw_thread(overlay, p["at"], rect)
	for k in [2, 1]:
		overlay.draw_style_box(_plate, Rect2(rect.position + Vector2(5, -5) * k, rect.size))
	_draw_card(overlay, group[0]["ref"], rect)
	_draw_badge(overlay, Vector2(rect.end.x - 2.0, rect.position.y + 2.0), str(group.size()))
	hits.append({"kind": STACK, "rect": rect.grow(4.0), "key": _key(group[0]["ref"])})


## Ein aufgefächerter Stapel: seine Karten nebeneinander, daneben der Knopf
## zum Zuklappen.
func _draw_spread(overlay: Control, group: Array, hits: Array, from_pins: bool) -> void:
	var scale: float = SPREAD_SCALE if from_pins else group[0]["scale"]
	var size: Vector2 = Card.SIZE * SCALE * scale
	var middle := Vector2.ZERO
	for p in group:
		middle += p["at"] if from_pins else p["rect"].get_center()
	middle /= group.size()
	var width := group.size() * size.x + (group.size() - 1) * SPREAD_GAP
	var start := middle - Vector2(width / 2.0, size.y + PIN_REACH if from_pins else size.y / 2.0)
	start = start.clamp(Vector2(28, 4), (overlay.size - Vector2(width + 4.0, size.y + 4.0)).max(Vector2(28, 4)))
	var rects := []
	for i in group.size():
		rects.append(Rect2(start + Vector2(i * (size.x + SPREAD_GAP), 0.0), size))
		_draw_thread(overlay, group[i]["at"], rects[i])
	for i in group.size():
		_draw_card(overlay, group[i]["ref"], rects[i])
		var hit := {"kind": CARD, "rect": rects[i], "ref": group[i]["ref"]}
		# Aus dem Fächer lässt sich eine Karte herausziehen – so trennt man einen Stapel.
		if not from_pins:
			hit["home"] = group[i]["home"]
			hit["scale"] = group[i]["scale"]
		hits.append(hit)
	var close := start + Vector2(-14.0, 10.0)
	_draw_badge(overlay, close, "×")
	hits.append({"kind": CLOSE, "rect": Rect2(close - Vector2(11, 11), Vector2(22, 22))})


func _draw_card(overlay: Control, ref: Dictionary, rect: Rect2) -> void:
	var face = _faces.get(ref["taskId"])
	if face == null:
		return
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


## Der Faden vom Node zur Karte – zur nächsten Stelle an ihrem Rand.
func _draw_thread(overlay: Control, at: Vector2, rect: Rect2) -> void:
	var to := at.clamp(rect.position, rect.end)
	if to != at:
		overlay.draw_line(at, to, Color(Palette.ACCENT, 0.8), 1.5, true)
	overlay.draw_circle(at, 3.5, Palette.ACCENT)


## Ein Pin in der Farbe des Status; stehen mehrere Karten dahinter, mit Anzahl.
func _draw_pin(overlay: Control, at: Vector2, color: Color, count: int) -> void:
	if count > 1:
		_draw_badge(overlay, at, str(count))
		return
	overlay.draw_circle(at, 8.0, Color(0.05, 0.08, 0.07, 0.9))
	overlay.draw_circle(at, 6.0, color)


func _draw_badge(overlay: Control, at: Vector2, text: String) -> void:
	var font := overlay.get_theme_default_font()
	overlay.draw_circle(at, 11.0, Color(0.05, 0.08, 0.07))
	overlay.draw_circle(at, 9.5, Palette.ACCENT)
	var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	overlay.draw_string(font, at + Vector2(-wide / 2.0, 4.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.05, 0.08, 0.07))


static func _key(ref: Dictionary) -> String:
	return "%s|%s" % [ref["taskId"], ref["nodePath"]]


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

## Maus und Tasten über einem 3D-Viewport (die Instanz-ID seiner Kamera).
## Wahr, wenn eine Karte das Ereignis genommen hat – dann bekommt der Editor
## es nicht. Im 2D-Editor kommen die Klicks über die Klickflächen (`_sync_pads`).
func input(view: int, event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if _drag(event):
			return true
		var id: String = _hit(view, event.position).get("ref", {}).get("taskId", "")
		if id != _hover:
			_hover = id
			redraw_requested.emit()
		return false
	if not event is InputEventMouseButton:
		return false
	if not event.pressed:
		return _release(event)
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return false
	var hit := _hit(view, event.position)
	if hit.is_empty():
		return false
	_press(hit, view, event)
	return true


## Ein Klick auf etwas Gezeichnetes: einen Stapel auf- oder zuklappen, sonst
## gilt er der Karte – und mit ihm kann ein Wegziehen beginnen.
func _press(hit: Dictionary, view: int, event: InputEventMouseButton) -> void:
	var left := event.button_index == MOUSE_BUTTON_LEFT
	_held = left
	match hit["kind"]:
		STACK:
			if left:
				_open = hit["key"]
				redraw_requested.emit()
		CLOSE:
			_open = ""
			redraw_requested.emit()
		_:
			_click(hit["ref"], event)
			if left and hit.has("home") and not event.double_click:
				_grab = {
					"ref": hit["ref"], "view": view, "from": event.global_position,
					"start": hit["rect"].position, "home": hit["home"], "scale": hit["scale"],
					"offset": hit["ref"]["offset"], "moved": false,
				}


## Markieren, öffnen oder das Menü.
func _click(ref: Dictionary, event: InputEventMouseButton) -> void:
	select(ref["taskId"])
	task_selected.emit(ref["taskId"])
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_menu_ref = ref
		_menu.set_item_disabled(_menu.get_item_index(MENU_HOME), ref["offset"] == Vector2.ZERO)
		_menu.position = Vector2i(DisplayServer.mouse_get_position())
		_menu.popup()
	elif event.double_click:
		task_requested.emit(ref["taskId"])


## Zieht die gegriffene Karte mit dem Zeiger. Wahr, solange eine gegriffen ist.
func _drag(event: InputEventMouseMotion) -> bool:
	if _grab.is_empty():
		return false
	var delta: Vector2 = event.global_position - _grab["from"]
	# Ein Klick, bei dem die Hand etwas zittert, ist noch kein Ziehen.
	if _grab["moved"] or delta.length() >= DRAG_START:
		_grab["moved"] = true
		_grab["offset"] = (_grab["start"] + delta - _grab["home"]) / _grab["scale"]
		redraw_requested.emit()
	return true


## Lässt die Maustaste los: eine weggezogene Karte merkt sich, wo sie liegt.
func _release(event: InputEventMouseButton) -> bool:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return false
	var was := _held
	_held = false
	if not _grab.is_empty():
		var grab := _grab
		_grab = {}
		if grab["moved"]:
			links.place(grab["ref"], grab["offset"])
	return was


func _is_grabbed(ref: Dictionary, view: int) -> bool:
	return not _grab.is_empty() and _grab["moved"] and _grab["view"] == view and Refs.same(ref, _grab["ref"])


## Was an dieser Stelle zuoberst gezeichnet ist – leer, wenn dort nichts ist.
func _hit(view: int, at: Vector2) -> Dictionary:
	var hits: Array = _hits.get(view, [])
	for i in range(hits.size() - 1, -1, -1):
		if hits[i]["rect"].has_point(at):
			return hits[i]
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
		MENU_HOME:
			links.place(_menu_ref, Vector2.ZERO)
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
## ausgewählt ist, den das Plugin bearbeitet. Deshalb liegt dort über allem
## Gezeichneten eine unsichtbare Fläche, die Klicks selbst annimmt. Mausrad
## und mittlere Taste gehen durch sie hindurch an den Editor.
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
			pad.set_meta("hit", hits[i])


func _on_pad_input(event: InputEvent, pad: Control) -> void:
	if event is InputEventMouseMotion:
		if _drag(event):
			pad.accept_event()
	elif event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT):
		if event.pressed:
			_press(pad.get_meta("hit"), VIEW_2D, event)
		else:
			_release(event)
		pad.accept_event()


func _on_pad_hover(pad: Control, inside: bool) -> void:
	var id: String = pad.get_meta("hit", {}).get("ref", {}).get("taskId", "")
	if (inside and id != _hover) or (not inside and _hover == id and id != ""):
		_hover = id if inside else ""
		redraw_requested.emit()


func _exit_tree() -> void:
	for control in _pads + _catchers:
		if is_instance_valid(control):
			control.queue_free()
	_pads = []
	_catchers = []
