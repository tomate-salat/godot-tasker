@tool
extends Control
## Hineingezoomt in eine Stellung der Nebenquests (Nutzer, 2026-10-24): in der
## Mitte das Gerät im jetzigen Baustand, im Ring darum seine Teile.
##
## - Ohne Unteraufgaben sind die Teile die Kästchen der Aufgabe, als Bautrupps:
##   ein Klick hakt ab oder wieder auf, und das Gerät wächst sofort.
## - Mit Unteraufgaben ist jede ein eigenes Gerät: ein Klick tappt sie (in
##   Arbeit oder zurück), ein Doppelklick öffnet sie. Was schon in einem
##   früheren Release erledigt wurde, steht blass mit dessen Version.
##
## Ein Doppelklick auf die Mitte öffnet die Aufgabe, ein Rechtsklick bietet
## „Erledigen“ an. Herauszoomen (Mausrad) oder Escape führt zurück zur Karte.

signal task_requested(task_id: String)
signal change_requested(task_id: String, changes: Dictionary)
## Das n-te Kästchen der Aufgabe soll umgeschaltet werden.
signal box_toggled(task_id: String, index: int)
signal refused(text: String)
## Zurück zur Feldzugskarte.
signal left

const Sidequest := preload("../rules/sidequest.gd")
const Release := preload("../rules/release.gd")
const Field := preload("../rules/field.gd")
const Model := preload("../rules/model.gd")
const Tisch := preload("../rules/tisch.gd")
const Workspace := preload("../rules/workspace.gd")
const Emplacement := preload("emplacement.gd")
const Palette := preload("palette.gd")

const TOP := 62.0
const GOLD := Color("e8b04a")
const OWN := Color("7fa3d8")
const OWN_LIGHT := Color("a7c2ee")
const DARK := Color("15181b")
## Die Baustelle: Erde, Pfade, Paletten und Kisten.
const DIRT := Color(0.29, 0.25, 0.17, 0.55)
const DIRT_DARK := Color(0.25, 0.21, 0.14, 0.45)
const DIRT_PATH := Color(0.29, 0.25, 0.17, 0.4)
const PLANK := Color("8a6a3e")
const CRATE := Color("6e5634")
const CRATE_DARK := Color("3d2f1c")
## So viel größer als gezeichnet stehen Arbeiter, Säcke und Paletten da.
const WORK := 1.7
const CLICK_WAIT := 0.25
## So weit reicht ein Teil im Ring für Zeiger und Klick.
const ITEM := 34.0

var _ws: Workspace
var _release: Variant
var _post := {}
## Die Teile im Ring: je `{ kind: "box" | "unit", index, id, text, done, unit }`.
var _items: Array = []
var _hovered := -2
var _time := 0.0
var _click_ticket := 0
var _menu: PopupMenu
var _menu_task := ""
var _note: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_note = Label.new()
	_note.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_note.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_note.offset_bottom = -16
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.add_theme_color_override("font_color", Palette.MUTED)
	_note.add_theme_font_size_override("font_size", 12)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_note)


## Zeigt die Stellung `task_id` des Releases. Gibt false zurück, wenn es sie
## nicht (mehr) gibt – etwa weil sie zurückgezogen wurde.
func show_position(ws: Workspace, release: Variant, task_id: String) -> bool:
	_ws = ws
	_release = release
	_post = {}
	if release == null:
		return false
	for p in Sidequest.positions(ws, release):
		if p["id"] == task_id:
			_post = p
	if _post.is_empty():
		return false
	_items = []
	var t: Dictionary = _post["task"]
	if _post["units"].is_empty():
		var boxes := Sidequest.boxes(t)
		for i in boxes.size():
			_items.append({"kind": "box", "index": i, "id": t["id"], "text": boxes[i]["text"], "done": boxes[i]["done"]})
		_note.text = "Jede Station ist ein Kästchen: Klick hakt ab, der Arbeiter liefert und das Gerät wächst · Doppelklick auf die Mitte: Aufgabe öffnen · Rechtsklick: erledigen · Mausrad zurück: Karte"
	else:
		for u in _post["units"]:
			_items.append({"kind": "unit", "id": u["id"], "text": str(u["task"].get("title", "")), "done": u["done"], "unit": u})
		_note.text = "Klick: in Arbeit nehmen oder zurück · Doppelklick: öffnen · Rechtsklick: erledigen · Mausrad zurück: Karte"
	queue_redraw()
	return true


## Die Aufgabe, in deren Stellung gerade hineingezoomt ist.
func shown_task() -> Variant:
	return _post.get("task")


func _process(delta: float) -> void:
	if is_visible_in_tree() and not _post.is_empty():
		_time += delta
		queue_redraw()


# -------------------------------------------------------------- Anordnung

func _center() -> Vector2:
	return Vector2(size.x / 2.0, TOP + (size.y - TOP) / 2.0 - 8.0)


func _ring() -> Vector2:
	var room := Vector2(size.x, size.y - TOP - 60.0)
	return Vector2(minf(room.x * 0.36, 440.0), minf(room.y * 0.36, 280.0))


func _spot(i: int) -> Vector2:
	var n := maxi(_items.size(), 1)
	var a := -PI / 2.0 + TAU * i / n
	var r := _ring()
	return _center() + Vector2(cos(a) * r.x, sin(a) * r.y)


## Der Maßstab des Geräts in der Mitte.
func _scale() -> float:
	return 2.2 if _post.get("kind") == Sidequest.BATTERY or _post.get("kind") == Sidequest.AIRFIELD else 3.4


## Das Teil unter dem Punkt: sein Index, -1 für die Mitte, -2 für nichts.
func _hit(point: Vector2) -> int:
	for i in _items.size():
		if point.distance_to(_spot(i)) <= ITEM:
			return i
	if not _post.is_empty() and point.distance_to(_center()) <= Emplacement.reach(_post["kind"]) * _scale():
		return -1
	return -2


# -------------------------------------------------------------- Bedienen

func _gui_input(event: InputEvent) -> void:
	if _post.is_empty():
		return
	if event is InputEventMouseMotion:
		var over := _hit(event.position)
		if over != _hovered:
			_hovered = over
			queue_redraw()
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over != -2 else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			left.emit()
			accept_event()
			return
		var over := _hit(event.position)
		if event.button_index == MOUSE_BUTTON_RIGHT and over != -2:
			_open_menu(_post["id"] if over == -1 or _items[over]["kind"] == "box" else _items[over]["id"])
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		_click_ticket += 1
		if event.double_click:
			if over == -1:
				task_requested.emit(_post["id"])
			elif over >= 0 and _items[over]["kind"] == "unit":
				task_requested.emit(_items[over]["id"])
			return
		if over < 0:
			return
		# Erst wenn feststeht, dass kein Doppelklick folgt – wie im Feld.
		var ticket := _click_ticket
		await get_tree().create_timer(CLICK_WAIT).timeout
		if ticket != _click_ticket or not is_inside_tree() or over >= _items.size():
			return
		var item: Dictionary = _items[over]
		if item["kind"] == "box":
			if Model.is_done(_post["task"]):
				refused.emit("Die Aufgabe ist schon erledigt")
			else:
				box_toggled.emit(item["id"], item["index"])
		else:
			_toggle(item["id"])


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		left.emit()
		get_viewport().set_input_as_handled()


## Tappen und zurück, wie im Feld.
func _toggle(id: String) -> void:
	var task = _ws.task(id)
	if task == null:
		return
	var refusal := Field.untap_refusal(_ws, task) if Field.is_tapped(task) else Field.tap_refusal(_ws, task)
	if refusal != "":
		refused.emit(refusal)
	else:
		change_requested.emit(id, {"status": "ready" if Field.is_tapped(task) else "progress"})


func _open_menu(id: String) -> void:
	var task = _ws.task(id)
	if task == null:
		return
	_menu_task = id
	_menu.clear()
	_menu.add_item("Aufgabe öffnen", 0)
	if not Model.is_done(task):
		_menu.add_item("Erledigen", 1)
		var why := Tisch.done_refusal(_ws, task)
		if why != "":
			_menu.set_item_disabled(1, true)
			_menu.set_item_tooltip(1, why)
	_menu.position = Vector2i(get_screen_position() + get_local_mouse_position())
	_menu.reset_size()
	_menu.popup()


func _on_menu(choice: int) -> void:
	if choice == 0:
		task_requested.emit(_menu_task)
	elif choice == 1:
		change_requested.emit(_menu_task, {"status": "done"})


# -------------------------------------------------------------- Zeichnen

## Die Baustelle (Nutzer, 2026-10-24 – die erste Fassung mit Figuren auf
## einem gestrichelten Ring sah nach Stecknadeln aus): in der Mitte ein Platz
## aus Erde mit dem Gerät, von jeder Station führt ein Trampelpfad hin. An
## einer offenen Station liegt Material, und ein Arbeiter schleppt Sandsäcke
## zum Gerät und kommt leer zurück. Ist das Kästchen abgehakt, ist der Stapel
## weg, der Arbeiter sitzt an seiner Station, ein Haken steht daneben.
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.FELT)
	if _post.is_empty():
		return
	var mid := _center()
	var site := Emplacement.reach(_post["kind"]) * _scale() + 34.0
	# Die Trampelpfade unter allem.
	for i in _items.size():
		var path := _path(i)
		draw_polyline(path, DIRT_PATH, 16.0, true)
	draw_colored_polygon(_blob(mid, site, 7), DIRT)
	draw_colored_polygon(_blob(mid, site * 0.82, 11), DIRT_DARK)
	# Reifenspuren und ein paar Kisten am Rand des Platzes.
	for k in 3:
		var a := 0.7 + k * 2.1
		var at := mid + Vector2.from_angle(a) * site * 0.9
		draw_rect(Rect2(at - Vector2(7, 6), Vector2(14, 12)), CRATE)
		draw_rect(Rect2(at - Vector2(7, 6), Vector2(14, 12)), CRATE_DARK, false, 1.0)
	var turn := -PI / 2.0
	Emplacement.draw_position(self, _post, mid, _scale(), turn, _time, 1.0, false)
	if _hovered == -1:
		draw_arc(mid, Emplacement.reach(_post["kind"]) * _scale() + 10.0, 0.0, TAU, 64, Color(GOLD, 0.8), 2.0, true)
	for i in _items.size():
		_draw_item(i)
	var steps: Dictionary = _post["steps"]
	var state := "feuert" if _post["done"] else "im Bau"
	_plate(mid + Vector2(0, site + 22.0), str(_post["task"].get("title", "")),
		"%s · %d/%d" % [state, steps["done"], steps["total"]] if steps["total"] > 0 else state, GOLD if _post["done"] else Palette.P2, _hovered == -1)
	if _items.is_empty():
		draw_string(Palette.sharp_body_font(), mid + Vector2(-220, site + 70.0), "Keine Teile – Doppelklick auf die Mitte öffnet die Aufgabe", HORIZONTAL_ALIGNMENT_CENTER, 440, 13, Palette.MUTED)


## Der Pfad von einer Station zum Rand des Platzes, leicht geschwungen.
func _path(i: int) -> PackedVector2Array:
	var from := _spot(i)
	var mid := _center()
	var to := mid + (from - mid).normalized() * (Emplacement.reach(_post["kind"]) * _scale() + 14.0)
	var bow := (from - to).orthogonal().normalized() * (14.0 if i % 2 == 0 else -14.0)
	var out := PackedVector2Array()
	for k in 13:
		var t := k / 12.0
		out.append(from.lerp(to, t) + bow * sin(PI * t))
	return out


## Ein Fleck mit unruhigem Rand, aus der Nummer immer gleich.
func _blob(mid: Vector2, r: float, seed_value: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in 40:
		var a := TAU * k / 40.0
		var wobble := 1.0 + 0.07 * sin(a * 3.0 + seed_value) + 0.04 * sin(a * 7.0 + seed_value * 2.0)
		out.append(mid + Vector2(cos(a), sin(a) * 0.86) * r * wobble)
	return out


func _draw_item(i: int) -> void:
	var item: Dictionary = _items[i]
	var at := _spot(i)
	var lit := i == _hovered
	if item["kind"] == "box":
		_station(i, at, item["done"])
		var text: String = item["text"]
		if text.length() > 30:
			text = text.substr(0, 29) + "…"
		_plate(at + Vector2(0, 50), ("✓ " if item["done"] else "") + text, "erledigt" if item["done"] else "Klick: abhaken", Palette.OK if item["done"] else OWN, lit)
	else:
		var u: Dictionary = item["unit"]
		var turn := (_center() - at).angle()
		Emplacement.draw_unit(self, u["kind"], at, 1.6, u["built"], turn, _time + i * 0.6, 0.45 if u["earlier"] != null else 1.0)
		var task: Dictionary = u["task"]
		# Wer an einer Unteraufgabe arbeitet, schleppt ebenfalls.
		if Field.is_tapped(task):
			_carrier(i, 0.0)
		var note := ""
		if u["earlier"] != null:
			var r = _ws.release(u["earlier"])
			note = "erledigt in %s" % (Release.label(r) if r != null else "früher")
		elif u["done"]:
			note = "feuert"
		else:
			var s := Sidequest.steps(_ws, task)
			note = ("in Arbeit" if Field.is_tapped(task) else "bereit" if task.get("status") == "ready" else str(task.get("status", ""))) \
				+ (" · %d/%d" % [s["done"], s["total"]] if s["total"] > 0 else "")
		_plate(at + Vector2(0, 46), item["text"], note, GOLD if u["done"] else OWN if Field.is_tapped(task) else Palette.MUTED, lit)
	if lit:
		draw_arc(at, ITEM + 6.0, 0.0, TAU, 40, Color(GOLD, 0.8), 1.5, true)


## Eine Station: offen ein Stapel Sandsäcke und ein Arbeiter, der sie zum
## Gerät trägt; erledigt eine leere Palette, der Arbeiter sitzt daneben.
func _station(i: int, at: Vector2, done: bool) -> void:
	# Die Palette.
	draw_set_transform(at, 0.0, Vector2(WORK, WORK))
	for k in 3:
		draw_rect(Rect2(Vector2(-16, -10 + k * 7), Vector2(32, 4)), PLANK)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if done:
		_worker(at + Vector2(22, 4) * WORK, Vector2.LEFT, false, 0.0, true)
		var tick := at + Vector2(-20, -14) * WORK
		draw_circle(tick, 11.0, Palette.OK)
		draw_polyline(PackedVector2Array([tick + Vector2(-5, 0), tick + Vector2(-1.5, 4), tick + Vector2(5, -4)]), DARK, 2.6, true)
		return
	# Der Stapel: zwei Lagen Säcke.
	for spot in [Vector2(-9, -2), Vector2(9, -2), Vector2(0, -9)]:
		_sandbag(at + spot * WORK, 0.0)
	_carrier(i, 0.0)


## Ein Arbeiter auf dem Pfad: hin mit einem Sack, zurück ohne. Jeder in seinem Takt.
func _carrier(i: int, _phase: float) -> void:
	var path := _path(i)
	var t := fposmod(_time * 0.18 + i * 0.29, 1.0)
	var going := t < 0.5
	var along := t * 2.0 if going else 2.0 - t * 2.0
	var at := _point_on(path, along)
	var ahead := _point_on(path, minf(along + 0.04, 1.0)) - _point_on(path, maxf(along - 0.04, 0.0))
	var dir := ahead.normalized() if going else -ahead.normalized()
	_worker(at, dir, going, _time * 9.0 + i, false)


func _point_on(path: PackedVector2Array, t: float) -> Vector2:
	var f := clampf(t, 0.0, 1.0) * (path.size() - 1)
	var k := mini(int(f), path.size() - 2)
	return path[k].lerp(path[k + 1], f - k)


## Ein Arbeiter von oben, größer als die Figuren der Karte: Schultern, Rucksack,
## Helm, Arme, die beim Gehen pendeln. `carrying`: ein Sack über dem Kopf.
## `resting`: er sitzt, grau-grün statt im Blau der Truppe.
func _worker(at: Vector2, dir: Vector2, carrying: bool, step: float, resting: bool) -> void:
	var t := Transform2D(dir.angle(), Vector2(WORK, WORK), 0.0, at)
	var body := Color("6f8a74") if resting else OWN
	var head := Color("9fb3a4") if resting else OWN_LIGHT
	draw_set_transform_matrix(t)
	# Schatten.
	draw_circle(Vector2(2, 3), 11.0, Color(0, 0, 0, 0.25))
	if not resting:
		# Die Beine schreiten.
		var stride := sin(step) * 4.0
		draw_circle(Vector2(stride, -4), 3.2, DARK)
		draw_circle(Vector2(-stride, 4), 3.2, DARK)
	# Rucksack hinten, Schultern, Arme.
	draw_rect(Rect2(-10, -5, 5, 10), Color(body.darkened(0.35)))
	draw_set_transform_matrix(t * Transform2D(0.0, Vector2(0.75, 1.0), 0.0, Vector2.ZERO))
	draw_circle(Vector2.ZERO, 9.5, DARK)
	draw_circle(Vector2.ZERO, 8.2, body)
	draw_set_transform_matrix(t)
	var swing := 0.0 if carrying or resting else sin(step) * 3.0
	draw_circle(Vector2(2 + swing, -8), 2.6, body.darkened(0.15))
	draw_circle(Vector2(2 - swing, 8), 2.6, body.darkened(0.15))
	# Helm.
	draw_circle(Vector2(1, 0), 5.6, DARK)
	draw_circle(Vector2(1, 0), 4.6, head)
	draw_circle(Vector2(2.2, -1.2), 1.4, Color(1, 1, 1, 0.35))
	draw_set_transform_matrix(Transform2D.IDENTITY)
	if carrying:
		_sandbag(at + dir * 4.0 * WORK, dir.angle() + PI / 2.0)


## Ein Sandsack: ein gefülltes Kissen mit Naht.
func _sandbag(at: Vector2, turn: float) -> void:
	draw_set_transform_matrix(Transform2D(turn, Vector2(WORK, WORK), 0.0, at))
	draw_rect(Rect2(-8, -4.5, 16, 9), Emplacement.SAND_DARK)
	draw_rect(Rect2(-7, -3.5, 14, 7), Emplacement.SAND)
	draw_line(Vector2(-7, 0), Vector2(7, 0), Color(Emplacement.SAND_DARK, 0.6), 1.0)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _plate(mid: Vector2, title: String, note: String, tone: Color, lit: bool) -> void:
	var font := Palette.sharp_title_font()
	var small := Palette.sharp_body_font()
	var wide := maxf(maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, small.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) + 24.0, 90.0)
	var tall := 40.0 if note != "" else 26.0
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.SURFACE
	box.border_color = Color(tone, 1.0 if lit else 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	var rect := Rect2(mid - Vector2(wide / 2.0, tall / 2.0), Vector2(wide, tall))
	draw_style_box(box, rect)
	draw_string(font, rect.position + Vector2(0, 17.0), title, HORIZONTAL_ALIGNMENT_CENTER, wide, 13, Palette.INK)
	if note != "":
		draw_string(small, rect.position + Vector2(0, 32.0), note, HORIZONTAL_ALIGNMENT_CENTER, wide, 10, tone)
