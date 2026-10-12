@tool
extends Control
## Das Abzeichen: eine Karte, die gespielt wurde. In der Stadt verliert die
## Karte ihre Form – ihr Titelbild bleibt als Wappenschild stehen, darunter
## ein Band mit dem Titel. Unter dem Zeiger zeigt das Feld wieder die Karte.
##
## Was die Karte zeigt, trägt der Schild: der Rand hat die Farbe des Zustands
## und ist nach der Checkliste geteilt, Winkel darüber stehen für die
## Priorität, Kette und Schloss für „gesperrt“, mehrere Schilde hintereinander
## für einen Stapel. Was in Arbeit ist, hebt sich und leuchtet.

const Model := preload("../rules/model.gd")
const Progress := preload("../rules/progress.gd")
const Blocking := preload("../rules/blocking.gd")
const Inherit := preload("../rules/inherit.gd")
const Workspace := preload("../rules/workspace.gd")
const Palette := preload("palette.gd")

## Die Fläche des Abzeichens samt Band, und darin der Schild.
const SIZE := Vector2(124, 96)
const TITLE := 12
const SHIELD := Vector2(58, 66)
const BAND := 19.0
## Ab so vielen Stücken ist der Rand nicht mehr geteilt, sondern ein Bogen.
const MANY := 12

signal pressed(badge: Control, event: InputEventMouseButton)

var task_id := ""
## In Arbeit: der Schild hebt sich und leuchtet.
var selected := false: set = set_selected
## Angehoben, 0 bis 1 – unter dem Zeiger und beim Ziehen.
var lift := 0.0: set = set_lift
## Die Karte kennt diese Einstellung; das Abzeichen zeichnet immer scharf.
var sharp := true

var _status: Variant = "open"
var _prio := 0
var _stack := 0
var _locked := false
var _done := false
var _segments: Array = []
var _title := ""
var _initials := ""
var _texture: Texture2D
var _outline := PackedVector2Array()


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	_outline = _shape()


## Zeigt `task`. `images` ist der Bild-Zwischenspeicher (`core/images.gd`) –
## ohne ihn oder ohne Titelbild trägt der Schild die Anfangsbuchstaben.
func show_task(ws: Workspace, task: Dictionary, images: Node = null, _crumb := false) -> void:
	task_id = task["id"]
	var doc := ws.is_doc(task)
	_done = Model.is_done(task)
	_status = null if doc else task.get("status")
	_prio = int(task.get("prio", 0))
	_stack = ws.kids(task_id).size()
	_locked = not doc and not _done and Blocking.is_blocked(ws, task)
	_segments = [] if doc else Progress.status_segments(ws, task)
	_title = task.get("title", "") if task.get("title") else "Ohne Titel"
	var mark = ws.mark(task.get("markId"))
	if mark != null and str(mark.get("emoji", "")) != "":
		_initials = str(mark["emoji"])
	else:
		_initials = ""
		for word in _title.split(" ", false).slice(0, 2):
			_initials += word.substr(0, 1).to_upper()
	tooltip_text = ""
	queue_redraw()

	var cover = Inherit.effective_cover(ws, task)
	if cover == null or images == null:
		_texture = null
		return
	var id := task_id
	var texture: Texture2D = await images.get_texture(cover["image_id"], true)
	# Inzwischen kann das Abzeichen eine andere Aufgabe zeigen oder weg sein.
	if is_instance_valid(self) and task_id == id:
		_texture = texture
		queue_redraw()


func set_selected(value: bool) -> void:
	if selected != value:
		selected = value
		queue_redraw()


## Neu gezeichnet wird nur, wenn sich wirklich etwas ändert – sonst zeichnete
## jede Bewegung des Feldes alle Abzeichen in jedem Bild neu.
func set_lift(value: float) -> void:
	if not is_equal_approx(lift, value):
		lift = value
		queue_redraw()


## Die Karte schimmert beim Kippen; das Abzeichen lehnt sich nur mit.
func set_tilt(_tilt: Vector2) -> void:
	pass


## Getroffen ist nur der Schild und sein Band, nicht die Ecken daneben.
func _has_point(point: Vector2) -> bool:
	var mid := _mid()
	if Rect2(mid - SHIELD / 2.0, SHIELD).grow(3.0).has_point(point):
		return true
	return Rect2(mid.x - _band_width() / 2.0, mid.y + SHIELD.y / 2.0 + 3.0, _band_width(), BAND).has_point(point)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		pressed.emit(self, event)


## Die Mitte des Schilds in der Fläche des Abzeichens.
func _mid() -> Vector2:
	return Vector2(SIZE.x / 2.0, 4.0 + SHIELD.y / 2.0)


## Der Umriss des Schilds um den Ursprung: oben gerade, unten spitz zulaufend.
static func _shape() -> PackedVector2Array:
	var w := SHIELD.x
	var h := SHIELD.y
	var points := PackedVector2Array([Vector2(-w / 2.0, -h / 2.0), Vector2(w / 2.0, -h / 2.0), Vector2(w / 2.0, h * 0.06)])
	var right := [Vector2(w / 2.0, h * 0.06), Vector2(w / 2.0, h * 0.3), Vector2(w * 0.22, h * 0.44), Vector2(0, h / 2.0)]
	for i in range(1, 9):
		points.append(_bezier(right, i / 8.0))
	for i in range(1, 8):
		var p := _bezier(right, 1.0 - i / 8.0)
		points.append(Vector2(-p.x, p.y))
	points.append(Vector2(-w / 2.0, h * 0.06))
	return points


static func _bezier(c: Array, t: float) -> Vector2:
	var a: Vector2 = c[0].lerp(c[1], t)
	var b: Vector2 = c[1].lerp(c[2], t)
	var d: Vector2 = c[2].lerp(c[3], t)
	return a.lerp(b, t).lerp(b.lerp(d, t), t)


func _moved(by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _outline:
		out.append(p + by)
	return out


func _band_width() -> float:
	return clampf(Palette.sharp_body_font().get_string_size(_title, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE).x + 16.0, 50.0, SIZE.x)


func _draw() -> void:
	var raised := maxf(lift, 1.0 if selected else 0.0)
	var mid := _mid() + Vector2(0, -4.0 * raised)
	var tone := Color("aab3ae") if _status == "open" or _status == null else Palette.status_color(_status)

	# Ein Stapel: weitere Schilde liegen versetzt dahinter.
	for k in range(mini(_stack, 2), 0, -1):
		var behind := _moved(mid + Vector2(5.0 * k, -4.0 * k))
		draw_colored_polygon(behind, Color("141917"))
		behind.append(behind[0])
		draw_polyline(behind, Palette.LINE_STRONG, 1.5, true)
	# Der Schatten: wer sich hebt, wirft ihn weiter.
	draw_colored_polygon(_moved(_mid() + Vector2(2.0 + 3.0 * raised, 3.0 + 6.0 * raised)), Color(0, 0, 0, 0.34))
	var shape := _moved(mid)
	var closed := shape.duplicate()
	closed.append(shape[0])
	if selected:
		draw_polyline(closed, Color(Palette.INFO, 0.28), 11.0, true)

	# Das Titelbild füllt den Schild, mittig beschnitten. Ohne Bild: die Anfangsbuchstaben.
	if _texture != null:
		var image := _texture.get_size()
		var fit := maxf(SHIELD.x / image.x, SHIELD.y / image.y)
		var seen := SHIELD / fit / image
		var uvs := PackedVector2Array()
		for p in _outline:
			uvs.append(Vector2(0.5, 0.5) + Vector2(p.x / SHIELD.x, p.y / SHIELD.y) * seen)
		draw_colored_polygon(shape, Color.WHITE, uvs, _texture)
	else:
		draw_colored_polygon(shape, Color("1b2422"))
		draw_string(Palette.sharp_title_font(), mid + Vector2(-SHIELD.x / 2.0, 3.0), _initials, HORIZONTAL_ALIGNMENT_CENTER, SHIELD.x, 20, Color(Palette.INK, 0.85))

	# Der Rand: dunkel unterlegt, darauf die Farbe des Zustands – nach
	# Checkliste und Unteraufgaben geteilt, Erledigtes grün.
	draw_polyline(closed, Color("0f1412"), 5.6, true)
	var n := _segments.size()
	if n == 0:
		draw_polyline(closed, tone, 3.2, true)
	else:
		var around := _length(closed)
		var gap := 2.4 if n <= MANY else 0.0
		for i in n:
			var s: Dictionary = _ordered(i)
			var color := Color(tone, 0.9)
			if s["kind"] == "checklist":
				if s["done"]:
					color = Palette.OK
			elif s["status"] != "open":
				color = Palette.status_color(s["status"])
			var piece := _stretch(closed, around * i / n + gap / 2.0, around * (i + 1) / n - gap / 2.0)
			if piece.size() >= 2:
				draw_polyline(piece, color, 3.2, true)

	# Die Priorität: Winkel über dem Schild, je dringender, desto mehr.
	var marks := 0 if _prio == 0 else 4 - _prio
	for k in marks:
		var at := mid + Vector2((k - (marks - 1) / 2.0) * 9.0, -SHIELD.y / 2.0 - 8.0)
		draw_polyline(PackedVector2Array([at + Vector2(-4, -2), at + Vector2(0, 2), at + Vector2(4, -2)]), Palette.prio_color(_prio), 2.2, true)
	if _status == "unclear":
		var corner := mid + Vector2(SHIELD.x / 2.0 - 3.0, -SHIELD.y / 2.0 + 3.0)
		draw_circle(corner, 8.5, Color("0f1412"))
		draw_arc(corner, 8.5, 0.0, TAU, 24, Palette.UNCLEAR, 1.2, true)
		draw_string(Palette.sharp_title_font(), corner + Vector2(-8.5, 4.5), "?", HORIZONTAL_ALIGNMENT_CENTER, 17.0, 12, Palette.UNCLEAR)
	if _done:
		# Eine Fahne: das Ziel ist genommen.
		var pole := mid + Vector2(0, -SHIELD.y / 2.0 + 2.0)
		draw_line(pole, pole + Vector2(0, -20), Color("cfd6d2"), 2.0, true)
		draw_colored_polygon(PackedVector2Array([pole + Vector2(0, -20), pole + Vector2(15, -20), pole + Vector2(11, -15), pole + Vector2(15, -10), pole + Vector2(0, -10)]), Palette.OK)
	if _stack > 0:
		var corner := mid + Vector2(SHIELD.x / 2.0 + 3.0, -SHIELD.y / 2.0 - 2.0)
		draw_circle(corner, 8.5, Color("0f1412"))
		draw_arc(corner, 8.5, 0.0, TAU, 24, Color(Palette.INK, 0.5), 1.0, true)
		draw_string(Palette.sharp_body_font(), corner + Vector2(-8.5, 3.8), str(_stack), HORIZONTAL_ALIGNMENT_CENTER, 17.0, 10, Palette.INK)
	if _locked:
		# Gesperrt: zwei Ketten über Kreuz, in der Mitte das Schloss.
		var chain := Color(0.79, 0.82, 0.8, 0.85)
		draw_dashed_line(mid + Vector2(-SHIELD.x / 2.0 - 5.0, -SHIELD.y / 2.0 + 4.0), mid + Vector2(SHIELD.x / 2.0 + 5.0, SHIELD.y * 0.3), chain, 3.4, 7.0, true, true)
		draw_dashed_line(mid + Vector2(SHIELD.x / 2.0 + 5.0, -SHIELD.y / 2.0 + 4.0), mid + Vector2(-SHIELD.x / 2.0 - 5.0, SHIELD.y * 0.3), chain, 3.4, 7.0, true, true)
		var lock := mid + Vector2(0, -SHIELD.y * 0.1)
		draw_arc(lock + Vector2(0, -3), 4.5, PI, TAU, 12, Palette.P2, 2.4, true)
		draw_rect(Rect2(lock + Vector2(-8.5, -3.5), Vector2(17, 13)), Color("15181b"))
		draw_rect(Rect2(lock + Vector2(-7.5, -2.5), Vector2(15, 11)), Palette.P2)

	# Das Band mit dem Titel; was nicht passt, wird gekürzt.
	var font := Palette.sharp_body_font()
	var wide := _band_width()
	var text := _title
	while text.length() > 3 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE).x > wide - 12.0:
		text = text.substr(0, text.length() - 2).strip_edges() + "…"
	var band := StyleBoxFlat.new()
	band.bg_color = Color(0.07, 0.094, 0.1, 0.94)
	band.border_color = Color(tone, 0.6)
	band.set_border_width_all(1)
	band.set_corner_radius_all(4)
	var rect := Rect2(_mid().x - wide / 2.0, _mid().y + SHIELD.y / 2.0 + 3.0, wide, BAND)
	draw_style_box(band, rect)
	draw_string(font, rect.position + Vector2(0, 14.0), text, HORIZONTAL_ALIGNMENT_CENTER, wide, TITLE, Palette.INK)


## Die Stücke des Rands in fester Folge: Erledigtes zuerst, dann was läuft,
## dann was hängt, zuletzt das Offene – wie der Balken der Karte.
func _ordered(index: int) -> Dictionary:
	var rank := func(s: Dictionary) -> int:
		if s["kind"] == "checklist":
			return 0 if s["done"] else 4
		match s["status"]:
			"done":
				return 0
			"progress":
				return 1
			"blocked":
				return 2
			"unclear":
				return 3
		return 4
	var sorted := Model.stable_sort(_segments, func(a: Dictionary, b: Dictionary) -> bool: return rank.call(a) < rank.call(b))
	return sorted[index]


static func _length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total


## Das Stück eines Linienzugs zwischen zwei Stellen, gemessen ab seinem Anfang.
static func _stretch(path: PackedVector2Array, from: float, to: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var done := 0.0
	for i in path.size() - 1:
		var piece := path[i].distance_to(path[i + 1])
		if piece < 0.001:
			continue
		var a := maxf(from, done)
		var b := minf(to, done + piece)
		if b > a:
			if out.is_empty():
				out.append(path[i].lerp(path[i + 1], (a - done) / piece))
			out.append(path[i].lerp(path[i + 1], (b - done) / piece))
		done += piece
	return out
