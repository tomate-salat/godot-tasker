@tool
extends Control
## Das Feld: der aktive Milestone als Kampf. In der Mitte sitzt der große
## Käfer, die Karten liegen in Ringen um ihn – was eine Karte braucht, einen
## Ring weiter außen. Was gilt, steht in `rules/field.gd`.
##
## Ein Doppelklick tappt eine Karte (in Arbeit) oder nimmt das zurück. Wer eine
## Karte auf den großen Käfer zieht, erledigt sie. Ein Klick öffnet sie.
##
## Die Ansicht ändert selbst nichts: sie meldet, was geschehen soll, und zeigt
## den Stand, den sie über `show_field` bekommt.

signal task_requested(task_id: String)
signal graph_requested(task_id: String)
## Der Status einer Karte soll sich ändern.
signal change_requested(task_id: String, changes: Dictionary)
## Ein Zug geht nicht – mit dem Grund.
signal refused(text: String)
## Es wurde weiter herausgezoomt, als das Feld reicht: eine Ebene höher, zur Feldzugskarte.
signal left
## Im Lageplan wurde ein Abzeichen losgelassen, an dieser Stelle der Ansicht.
signal released(task_id: String, at: Vector2)
## Im Lageplan: die Aufgabe soll aus dem Milestone heraus (Menü).
signal removal_requested(task_id: String)
## Im Lageplan: ein Abzeichen wurde auf ein anderes gelegt. Das gezogene
## blockiert das, worauf es liegt: `task_id` (das Ziel) soll auf `on_id` (das gezogene) warten.
signal link_requested(task_id: String, on_id: String)
## Im Lageplan: `task_id` soll nicht mehr auf `on_id` warten (Kreuz auf dem Weg).
signal unlink_requested(task_id: String, on_id: String)

const Model := preload("../rules/model.gd")
const Field := preload("../rules/field.gd")
const Dependency := preload("../rules/dependency.gd")
const Tisch := preload("../rules/tisch.gd")
const Workspace := preload("../rules/workspace.gd")
const Palette := preload("palette.gd")
const Card := preload("card.gd")
const Badge := preload("badge.gd")
const Bug := preload("field_bug.gd")
const City := preload("field_city.gd")

## Oben bleibt Platz für die Kopfzeile des Tischs.
const TOP := 62.0
const MARGIN := 22.0
## Die Karten liegen kleiner auf dem Feld; unter dem Zeiger werden sie groß.
## So weit neben der Mitte eines Abzeichens stehen die Figuren.
const BESIDE := 44.0
## Gekämpft wird auf der Straße vor der Karte: so weit vor ihrem Rand steht der
## Gegner, und so weit davor sein Angreifer.
const STREET_BACK := 34.0
const DUEL := 64.0
## Das Kreuz auf einem Weg: so groß, und so lange bleibt es stehen, nachdem der Zeiger das Abzeichen verlassen hat.
const KNOB := 11.0
## So viel Platz braucht ein Abzeichen auf dem Feld: der Schild mit seinem Band.
const BOX := Vector2(74, 92)
## Der innerste Ring und der Abstand von Ring zu Ring – in der Breite mehr
## als in der Höhe, weil das Fenster breiter ist als hoch.
const RING := Vector2(214.0, 172.0)
const STEP := Vector2(215.0, 178.0)
## Hinter diesem Ring liegt der Fluss der Stadt – nicht gleich hinter dem
## ersten, sonst müsste fast jeder Weg über eine Brücke. Die Lücke dort ist um
## so viel weiter, damit er samt Ufer zwischen die Karten passt.
const MOAT_AFTER := 2
const MOAT := Vector2(14.0, 50.0)
const BOSS_RADIUS := 84.0
const MIN_SCALE := 0.4
## So weit reicht die Fläche, auf der Wege und Ringe gezeichnet werden, von der Mitte aus.
const REACH := Vector2(20000, 20000)
## Bis zu diesem Anteil der Stadt lässt sich der Bildrand schieben – dahinter läuft sie nur noch aus.
const CITY_EDGE := 0.9
## Die Ringe: wie deckend sie in Ruhe und an der Front sind, wie viel der
## wandernde Schimmer dazugibt und wie schnell er umläuft (Bogenmaß je Sekunde).
const RING_QUIET := 0.16
const RING_FRONT := 0.34
const RING_GLINT := 0.62
const RING_TURN := 0.5
const RING_POINTS := 144
## Auf den Wegen wandern helle Striche nach innen: so schnell, so weit
## auseinander, so lang und um so viel deckender als der Weg selbst.
const WAY_SPEED := 26.0
const WAY_GAP := 64.0
const WAY_DASH := 12.0
const WAY_GLOW := 0.3
## Soldaten gehen ihren Weg in diesem Schritt (Pixel je Sekunde); kurze Wege
## dauern trotzdem mindestens, lange höchstens so viele Sekunden.
const MARCH_SPEED := 150.0
const MARCH_MIN := 0.7
const MARCH_MAX := 4.0
## Liegt der Zeiger auf einer Karte, bleiben fremde Verbindungen nur so deckend, und so lange dauert der Übergang.
const FOCUS_DIM := 0.14
const FOCUS_SECONDS := 0.18
## Um so viel deckender werden dabei die Wege der Karte selbst.
const FOCUS_RAISE := 0.4
## Vor einer Pfeilspitze läuft der Weg so weit gerade.
const ARROW_RUN := 30.0
## So viel Abstand halten Wege zu fremden Karten.
const CARD_ROOM := 7.0
## Karten halten so viel Abstand zu Brücken, und so weit rücken sie je Versuch zur Seite.
const BRIDGE_ROOM := 6.0
const BRIDGE_STEP := 12.0
## So hoch ist die Kopfzeile des Tischs; unter ihr verschwinden Karten und Figuren.
const HEAD := 58.0
## Wie weit das Mausrad über die eingepasste Größe hinaus vergrößert und verkleinert.
const ZOOM_MIN := 0.5
const ZOOM_MAX := 4.0
const ZOOM_STEP := 1.12
const MOVE_SECONDS := 0.3
## Ordnet sich das Feld neu – etwa weil eine Abhängigkeit dazukam –, gleiten
## Abzeichen und Blick in dieser Zeit an ihren neuen Platz; die Wege blenden
## danach wieder ein.
const SHIFT_SECONDS := 0.5
## So lange wartet ein Klick, ob ein zweiter folgt.
const CLICK_WAIT := 0.25
## Ab so vielen Pixeln wird aus dem Drücken ein Ziehen.
const DRAG_START := 8.0
## Das Kippen beim Ziehen – dieselben Werte wie am Spieltisch.
const MAX_TILT := 22.0
const TILT_STRENGTH := 0.5
const TILT_SPEED := 180.0
const TILT_RESPONSE_MS := 90.0
const TILT_STILL_MS := 60
## Die Striche eines Angriffs: Farbe, Länge, Abstand und wie schnell sie wandern.
const ATTACK := Color("f0604f")
const ATTACK_DASH := 12.0
const ATTACK_GAP := 30.0
const ATTACK_SPEED := 70.0
## Soldaten: wie oft einer eine Salve schießt, wie viele Schüsse sie hat, in
## welchem Abstand, und wie lange man einen Schuss sieht.
const SHOT_EVERY := 1.7
const BURST := 3
const BURST_GAP := 0.1
const SHOT_SECONDS := 0.13

var _ws: Workspace
var _milestone: Variant
var _images: Node
var _field := {}

var _canvas: Node2D
var _back: Control
## Die Stadt im Hintergrund und ob sie schon einmal gezeigt wurde.
var _city: City
## Ob die Verbindungen den Straßen folgen, und die schon gerechneten Wege.
static var street_ways := true
var _routes := {}
var _town: Node2D
var _city_shown := false
var _message: Label
var _toast: Label
var _toast_tween: Tween
var _menu: PopupMenu
var _menu_task := ""

## Wo die Mitte jeder Karte liegt – von der Mitte des Feldes aus gemessen.
var _centers := {}
## Was das Feld einnimmt, um die Mitte herum.
var _bounds := Rect2(-200, -200, 400, 400)
## Wie viele Ringe es gibt und um wie viel sie gewachsen sind, damit alles Platz hat.
var _rings := 0
var _grow := 1.0

var _cards := {}
var _pests := {}
var _ladies := {}
var _boss: Bug
## Die Schüsse der Soldaten, über allem anderen.
var _fx: Node2D
var _boss_done := -1
var _time := 0.0

var _click_ticket := 0
## Als Lageplan: dieselbe Stadt, aber ruhig – ohne Kampf, ohne Tappen und
## Erledigen. Hier wird nur verteilt (`ui/plan_map.gd`).
var plan := false
## Im Lageplan: eine Karte aus der Reserve schwebt über der Stadt.
var drop_hint := false:
	set(value):
		if drop_hint != value:
			drop_hint = value
			_back.queue_redraw()
## Die Suche des Lageplans: nur diese Abzeichen bleiben voll sichtbar.
var _spotlight := {}
var _spotlit := false
## Im Lageplan: das Abzeichen, auf dem das gezogene gerade liegt, und warum
## es dort nicht abgelegt werden kann (leer: es kann).
var _link_target := ""
var _link_refusal := ""
## Beim Neuordnen: wie lange Bewegungen gerade dauern, ob der Blick gleitet
## statt springt und wohin, und wie deckend die Wege sind.
var _move_time := MOVE_SECONDS
var _glide := false
var _fit_tween: Tween
var _fit_goal := Transform2D()
var _ways_fade := 1.0
var _ways_tween: Tween
## Beim Neuordnen wird erst gerechnet (Stadt, Wege) – das kostet ein, zwei
## Bilder. Bewegungen, die dabei entstehen, warten hier, bis es wieder flüssig
## läuft; sonst spränge ihr Anfang.
var _stalled := false
var _waiting: Array = []
## Woran die gesuchten Wege hängen – ändert es sich, werden sie neu gesucht.
var _routes_stamp := 0
## Die Wege müssen noch gesucht werden – sobald die Abzeichen angekommen sind.
var _routes_due := false
var _held: Badge
## Die Karte zum Abzeichen unter dem Zeiger – seine Akte.
var _peek: Card
var _peek_tween: Tween
var _held_at := Vector2.ZERO
var _dragging := false
var _over_boss := false
var _hovered := ""
## Die Karte, deren Verbindungen gerade hervorgehoben sind, und wie sehr (0 bis 1).
var _focus_id := ""
var _focus := 0.0
## Tempo und Neigung der gezogenen Karte.
var _velocity := Vector2.ZERO
var _tilt := Vector2.ZERO
var _last_move := 0
## Vergrößerung über das Einpassen hinaus und die Verschiebung des Feldes.
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

	var felt := ColorRect.new()
	felt.color = Palette.FELT
	felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(felt)

	# Die Stadt liegt für sich: sie scheint durch die Kopfzeile des Tischs.
	# Kein Bedienelement: die rasten auf ganze Pixel ein, und beim Gleiten des
	# Blicks zitterte dadurch die Stadt gegen die Abzeichen.
	_town = Node2D.new()
	add_child(_town)
	_city = City.new()
	_town.add_child(_city)
	# Alles andere – Karten, Wege, Figuren – verschwindet hinter der Kopfzeile:
	# es wird unter ihr abgeschnitten. Die Zwischenstufe schiebt zurück, damit
	# `_canvas` weiter vom Feld aus rechnet.
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.offset_top = HEAD
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)
	var shift := Control.new()
	shift.position = Vector2(0, -HEAD)
	shift.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(shift)
	# Die Mitte des Feldes ist der Ursprung von `_canvas`.
	_canvas = Node2D.new()
	shift.add_child(_canvas)
	_back = Control.new()
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.draw.connect(_draw_back)
	# Wege und Ringe reichen weit über die Mitte hinaus. Godot zeichnet ein
	# Bedienelement nur, solange seine Fläche im Bild ist – darum ist diese hier
	# riesig, und gezeichnet wird von ihrer Mitte aus.
	_back.position = -REACH
	_back.size = REACH * 2.0
	_canvas.add_child(_back)

	_boss = Bug.new()
	_boss.kind = Bug.BOSS
	_boss.girth = 2.5
	_boss.position = Vector2(0, 6)
	_boss.z_index = 20
	_canvas.add_child(_boss)

	_fx = Node2D.new()
	_fx.z_index = 40
	_fx.draw.connect(_draw_fx)
	_canvas.add_child(_fx)

	# Hinter der Kopfzeile des Tischs wird die Stadt dunkler, damit man sie lesen kann.
	var head := TextureRect.new()
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(0.04, 0.09, 0.08, 0.88), Color(0.04, 0.09, 0.08, 0.7), Color(0.04, 0.09, 0.08, 0.0)])
	var shade := GradientTexture2D.new()
	shade.gradient = fade
	shade.fill_from = Vector2(0, 0)
	shade.fill_to = Vector2(0, 1)
	shade.width = 4
	shade.height = 64
	head.texture = shade
	head.stretch_mode = TextureRect.STRETCH_SCALE
	head.set_anchors_preset(Control.PRESET_TOP_WIDE)
	head.offset_bottom = TOP + 14.0
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(head)

	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_FULL_RECT)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_message.visible = false
	add_child(_message)

	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -52
	_toast.offset_bottom = -22
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0
	add_child(_toast)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	_peek = Card.new()
	_peek.visible = false
	_peek.modulate.a = 0.0
	_peek.z_index = 90
	add_child(_peek)
	_no_mouse(_peek)
	resized.connect(_fit)


## Zeigt den Stand. `milestone` ist der aktive Milestone oder null.
func show_field(ws: Workspace, milestone: Variant, images: Node) -> void:
	# Ein anderer Milestone ist ein anderes Feld: was vom alten noch liegt,
	# verschwindet ohne Abgang – sonst fielen dessen Figuren im neuen um.
	var same: bool = milestone != null and _milestone != null and milestone["id"] == _milestone["id"]
	if milestone != null and _milestone != null and not same:
		_clear_field()
	var before := _centers.duplicate() if same else {}
	_ws = ws
	_milestone = milestone
	_images = images
	_message.visible = milestone == null
	_canvas.visible = milestone != null
	_town.visible = _canvas.visible
	if milestone == null:
		_message.text = "Kein aktiver Milestone – in der Planung lässt sich einer starten"
		return
	_field = Field.build(ws, milestone)
	_layout()
	_stalled = same
	_show_city(same)
	_clear_bridges()
	# Die Wege zu suchen ist das Teuerste am ganzen Abgleich. Neu gesucht wird
	# nur, wenn sich an Plätzen, Verbindungen oder Stadt etwas geändert hat –
	# sonst ruckte jede Antwort des Servers mitten in eine Bewegung.
	var attacks := []
	for card_id in _field["fronts"]:
		if _centers.has(card_id):
			attacks.append([card_id, _targets_of(card_id)])
	var stamp := [_centers, _field["ways"], attacks, _city.get_instance_id(), _city.built].hash()
	# Hat sich an den Plätzen etwas geändert, springt nichts: Abzeichen und
	# Blick gleiten hin. Die Wege verschwinden so lange und werden erst
	# gesucht und gezeigt, wenn alles angekommen ist – vorher lägen sie falsch,
	# und die Suche fiele mitten in die Bewegung.
	var moved := false
	for id in before:
		if _centers.has(id) and not _centers[id].is_equal_approx(before[id]):
			moved = true
			break
	if moved:
		_glide = true
		_move_time = SHIFT_SECONDS
		if _ways_tween != null and _ways_tween.is_valid():
			_ways_tween.kill()
		_ways_fade = 0.0
		_routes_due = _routes_due or stamp != _routes_stamp
		_routes_stamp = stamp
		_ways_tween = create_tween()
		_ways_tween.tween_interval(SHIFT_SECONDS + 0.08)
		_ways_tween.tween_callback(_routes_now)
		_ways_tween.tween_property(self, "_ways_fade", 1.0, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_wait(_ways_tween)
	elif stamp != _routes_stamp:
		_routes_stamp = stamp
		# Läuft gerade ein Neuordnen, kommt die Suche an dessen Ende.
		if _ways_fade <= 0.001:
			_routes_due = true
		else:
			_tell_city()
	_fit()
	_sync_cards()
	_move_time = MOVE_SECONDS
	_stalled = false
	_go_on()
	_boss.visible = not plan
	if plan:
		# Auf dem Lageplan steht niemand.
		for group in [_pests, _ladies]:
			for key in group:
				if is_instance_valid(group[key]):
					group[key].queue_free()
			group.clear()
	else:
		_sync_bugs()
	_back.queue_redraw()


## Sucht die Wege, falls das noch aussteht – am Ende eines Neuordnens.
func _routes_now() -> void:
	if _routes_due:
		_routes_due = false
		_tell_city()
		# Jetzt gibt es die Straßen wieder: die Figuren gehen von ihren Karten dorthin.
		if not plan and not _field.is_empty():
			_sync_bugs()


## Hält eine Bewegung an, die beim Neuordnen entsteht, bis `_go_on` sie loslässt.
func _wait(tween: Tween) -> void:
	if _stalled and tween != null and tween.is_valid():
		tween.pause()
		_waiting.append(tween)


## Lässt die angehaltenen Bewegungen laufen – zwei Bilder später, wenn das
## Rechnen vorbei ist und die Bilder wieder gleichmäßig kommen.
func _go_on() -> void:
	if _waiting.is_empty() or not is_inside_tree():
		return
	var held := _waiting
	_waiting = []
	await get_tree().process_frame
	await get_tree().process_frame
	for tween in held:
		if tween != null and tween.is_valid():
			tween.play()


## Nimmt einem Bedienelement und allem darin die Maus – es ist nur zum Ansehen.
static func _no_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_no_mouse(child)


## Hebt hervor, was eine Suche gefunden hat: `ids` bleiben voll sichtbar, alle
## anderen Abzeichen treten zurück. Mit `on` false ist wieder alles da.
func set_spotlight(ids: Dictionary, on: bool) -> void:
	_spotlight = ids
	_spotlit = on
	for id in _cards:
		var task = _ws.task(id) if _ws != null else null
		var dim: bool = task != null and Model.is_done(task)
		_cards[id].modulate = Color(0.55, 0.6, 0.57, 1.0) if dim else Color.WHITE
		if on and not ids.has(id):
			_cards[id].modulate.a = 0.22


# ------------------------------------------------- Abhängigkeiten im Lageplan

## Welches Abzeichen unter dem gezogenen liegt, und ob es auf das gezogene warten kann.
func _aim_link(at: Vector2) -> void:
	var target := ""
	for id in _centers:
		if _held != null and id == _held.task_id:
			continue
		var away: Vector2 = at - (_centers[id] + Vector2(0, -8))
		if absf(away.x) < Badge.SHIELD.x / 2.0 + 6.0 and absf(away.y) < Badge.SHIELD.y / 2.0 + 6.0:
			target = id
			break
	if target == _link_target:
		return
	_link_target = target
	_link_refusal = ""
	if target != "" and _held != null:
		var a = _ws.task(_held.task_id)
		var b = _ws.task(target)
		_link_refusal = Dependency.link_refusal(_ws, b, a) if a != null and b != null else "Das geht hier nicht"
		if _link_refusal == "Wartet schon darauf":
			_link_refusal = "Blockiert es schon"


## Die Kreuze auf den Wegen, an denen sich eine Abhängigkeit lösen lässt: je
## `{ at, task, on }` – `task` wartet auf `on`. Sie stehen im Lageplan immer
## da (Nutzer, 2026-10-12: sie sollen nicht verschwinden).
func _knobs() -> Array:
	var out := []
	if not plan or _dragging or _field.is_empty() or _ways_fade < 0.99:
		return out
	for way in _field["ways"]:
		if way["to"] == "" or not _centers.has(way["from"]) or not _centers.has(way["to"]):
			continue
		# Nur echte Abhängigkeiten lassen sich lösen, nicht der Weg einer Unteraufgabe zu ihrem Stapel.
		var waiting = _ws.task(way["to"])
		if waiting == null or not waiting.get("deps", []).has(way["from"]):
			continue
		out.append({"at": _middle(_route(way["from"], way["to"])), "task": way["to"], "on": way["from"]})
	return out


## Die Mitte eines Wegs, entlang seiner Länge gemessen.
static func _middle(path: PackedVector2Array) -> Vector2:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	var left := total / 2.0
	for i in path.size() - 1:
		var piece := path[i].distance_to(path[i + 1])
		if left <= piece and piece > 0.0:
			return path[i].lerp(path[i + 1], left / piece)
		left -= piece
	return path[path.size() - 1] if path.size() > 0 else Vector2.ZERO


## Was der Lageplan über den Abzeichen zeichnet: beim Ziehen das Ziel mit dem,
## was gleich geschieht, sonst die Kreuze auf den Wegen.
func _draw_links() -> void:
	if _dragging and _held != null and _link_target != "" and _centers.has(_link_target):
		var mid: Vector2 = _centers[_link_target] + Vector2(0, -8)
		var bad := _link_refusal != ""
		var tone := Palette.P1 if bad else Palette.OK
		_fx.draw_arc(mid, 44.0, 0.0, TAU, 48, tone, 2.5, false)
		_fx.draw_circle(mid, 44.0, Color(tone, 0.14), true, -1.0, false)
		var a = _ws.task(_held.task_id)
		var b = _ws.task(_link_target)
		var text := _link_refusal if bad else "„%s“ blockiert dann „%s“" % [_short(a), _short(b)]
		var font := Palette.sharp_body_font()
		var wide := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 20.0
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0.06, 0.13, 0.11, 0.95)
		box.border_color = tone
		box.set_border_width_all(1)
		box.set_corner_radius_all(7)
		var rect := Rect2(mid.x - wide / 2.0, mid.y - 84.0, wide, 24.0)
		_fx.draw_style_box(box, rect)
		_fx.draw_string(font, rect.position + Vector2(0, 16.5), text, HORIZONTAL_ALIGNMENT_CENTER, wide, 12, Palette.INK)
		return
	var mouse := (get_local_mouse_position() - _canvas.position) / _canvas.scale.x
	for knob in _knobs():
		var at: Vector2 = knob["at"]
		var hot := mouse.distance_to(at) <= KNOB + 3.0
		# Dezent, solange nichts darauf zeigt; kräftig unter dem Zeiger und an
		# den Wegen des Abzeichens, auf dem er liegt.
		var near: bool = hot or knob["task"] == _hovered or knob["on"] == _hovered
		var size := KNOB if near else KNOB * 0.72
		_fx.draw_circle(at, size + 1.5, Color(0.06, 0.08, 0.07, 1.0 if near else 0.8), true, -1.0, false)
		_fx.draw_circle(at, size, Color(Palette.P1, 0.95 if hot else 0.7 if near else 0.38), true, -1.0, false)
		var arm := size * 0.38
		var ink := Color(1, 1, 1, 1.0 if near else 0.7)
		_fx.draw_line(at + Vector2(-arm, -arm), at + Vector2(arm, arm), ink, 2.0, false)
		_fx.draw_line(at + Vector2(arm, -arm), at + Vector2(-arm, arm), ink, 2.0, false)


static func _short(task: Variant) -> String:
	if task == null:
		return "?"
	var title: String = task["title"] if task.get("title") else "Ohne Titel"
	return title if title.length() <= 22 else title.substr(0, 21) + "…"


## Wo das Abzeichen der Aufgabe in dieser Ansicht liegt – oder null.
func spot_of(id: String) -> Variant:
	if not _centers.has(id):
		return null
	return _canvas.position + _centers[id] * _canvas.scale.x


## Ein Abzeichen ist eben erst entstanden: es bleibt unsichtbar, bis `land` es zeigt.
func hold_back(id: String) -> void:
	if _cards.has(id):
		_cards[id].modulate.a = 0.0


## Lässt das Abzeichen aufsetzen: es wächst aus dem Bild der Karte, federt
## kurz nach, und ein Lichtkreis läuft von ihm weg.
func land(id: String) -> void:
	var badge: Badge = _cards.get(id)
	if badge == null:
		return
	badge.scale = Vector2(1.5, 1.5)
	var tween := badge.create_tween()
	tween.tween_property(badge, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(badge, "scale", Vector2(0.92, 0.92), 0.16).set_ease(Tween.EASE_IN)
	tween.tween_property(badge, "scale", Vector2(1.06, 1.06), 0.1)
	tween.tween_property(badge, "scale", Vector2.ONE, 0.1)
	var ring := Node2D.new()
	ring.position = _centers[id]
	ring.z_index = 4
	ring.set_meta("r", 30.0)
	ring.draw.connect(func() -> void:
		ring.draw_arc(Vector2.ZERO, ring.get_meta("r"), 0.0, TAU, 64, Palette.OK, 2.0, false))
	_canvas.add_child(ring)
	var wave := ring.create_tween()
	wave.tween_method(func(r: float) -> void:
		ring.set_meta("r", r)
		ring.queue_redraw(), 30.0, 80.0, 0.45).set_ease(Tween.EASE_OUT)
	wave.parallel().tween_property(ring, "modulate:a", 0.0, 0.45)
	wave.tween_callback(ring.queue_free)


func _clear_field() -> void:
	for group in [_cards, _pests, _ladies]:
		for key in group:
			if is_instance_valid(group[key]):
				group[key].queue_free()
		group.clear()
	_held = null
	_dragging = false
	_hovered = ""
	_focus = 0.0
	_boss_done = -1
	_city_shown = false
	reset_view()


## Ein kurzer Hinweis am unteren Rand, etwa warum ein Zug nicht geht.
func say(text: String, color := Palette.P2) -> void:
	_toast.add_theme_color_override("font_color", color)
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = _toast.create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ------------------------------------------------------------ Anordnung

## Die Stadt hinter den Karten: eingenommen ist sie von außen bis zu dem Ring,
## auf dem noch etwas offen ist.
func _show_city(blend := false) -> void:
	var seed_value := hash(str(_milestone["id"]))
	# Ändert sich die Stadt beim Neuordnen (der Fluss liegt an den Ringen),
	# entsteht die neue unter der alten, und die alte blendet weg.
	if blend and _city_shown and not _city.same_as(seed_value, RING * _grow, STEP * _grow, MOAT, _rings, MOAT_AFTER):
		var old := _city
		_city = City.new()
		_city.front = old.front
		_town.add_child(_city)
		_town.move_child(_city, old.get_index())
		var fade := old.create_tween()
		fade.tween_property(old, "modulate:a", 0.0, SHIFT_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		fade.tween_callback(old.queue_free)
		_wait(fade)
	_city.calm = plan
	_city.build(seed_value, RING * _grow, STEP * _grow, MOAT, _rings, MOAT_AFTER)
	# Die Grenze liegt zwischen diesem Ring und dem nächsten weiter außen.
	var ring_no: int = _field["front"]
	var target := ring_no - 0.5 if ring_no > 0 else -3.0
	if not _city_shown:
		_city_shown = true
		_city.front = target
	elif plan:
		# Der Lageplan zeigt die Front nicht; sie wandert dort nicht sichtbar.
		_city.front = target
	elif not is_equal_approx(_city.front, target):
		var march := _city.create_tween()
		march.tween_property(_city, "front", target, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		march.tween_callback(_city.settle_front)


## Verteilt die Karten auf ihre Ringe. Jede Karte bekommt einen Winkelbereich,
## so breit wie das, was hinter ihr nach außen hängt; sie selbst liegt in
## dessen Mitte. So bleibt zusammen, was zusammengehört.
func _layout() -> void:
	_centers = {}
	var outer := {}
	var ring := {}
	for n in _field["nodes"]:
		outer.get_or_add(n["inner"], []).append(n["id"])
		ring[n["id"]] = n["ring"]
	var weight := {}
	_weigh("", outer, weight)

	# Viele Enden brauchen einen größeren innersten Ring, sonst liegen die Karten übereinander.
	var card := BOX
	var around := TAU * sqrt((RING.x * RING.x + RING.y * RING.y) / 2.0)
	# Die Bänder mit den Titeln sind breiter als die Schilde; dafür bleibt Luft.
	var grow := maxf(1.0, weight[""] * (card.x + 34.0) / around)
	_grow = grow
	_rings = 0
	for id in ring:
		_rings = maxi(_rings, ring[id])
	# Die längste Kette zeigt zur Seite – dort ist im Fenster am meisten Platz.
	var deepest := ""
	for n in _field["nodes"]:
		if deepest == "" or n["ring"] > ring[deepest]:
			deepest = n["id"]
	var start := -PI
	if deepest != "":
		_spread("", 0.0, TAU, outer, weight, ring, grow)
		start = PI - _centers[deepest].angle()
		_centers = {}
	_spread("", start, TAU, outer, weight, ring, grow)

	_measure()


## Wie viel Platz das Feld braucht: alle Karten und die Mitte.
func _measure() -> void:
	var card := BOX
	var box := Rect2(-BOSS_RADIUS, -BOSS_RADIUS, BOSS_RADIUS * 2.0, BOSS_RADIUS * 2.0)
	for id in _centers:
		box = box.merge(Rect2(_centers[id] - card / 2.0, card))
	_bounds = box.grow(14.0)


## Auf einer Brücke und im Wasser liegt keine Karte: wer dort landen würde, rückt auf seinem
## Ring zur Seite – so wenig wie nötig, und nicht auf eine andere Karte.
func _clear_bridges() -> void:
	var card := BOX
	# Getappt liegt die Karte quer; frei bleiben muss die Brücke in beiden Lagen.
	var half := Vector2.ONE * (maxf(card.x, card.y) / 2.0 + BRIDGE_ROOM)
	var moved := false
	for n in _field["nodes"]:
		var id: String = n["id"]
		if not _centers.has(id) or not _city.in_the_way(_centers[id], half):
			continue
		var reach := _reach(n["ring"], _grow)
		var here: Vector2 = _centers[id]
		var angle := atan2(here.y / reach.y, here.x / reach.x)
		# Abwechselnd nach beiden Seiten, immer ein Stück weiter.
		var step := BRIDGE_STEP / maxf(reach.x, 1.0)
		for k in range(1, 120):
			var turn := step * ((k + 1) / 2) * (1.0 if k % 2 == 1 else -1.0)
			var spot := Vector2(cos(angle + turn) * reach.x, sin(angle + turn) * reach.y)
			if _city.in_the_way(spot, half):
				continue
			var free := true
			for other in _centers:
				var apart: Vector2 = (_centers[other] - spot).abs()
				if other != id and apart.x < card.x + 8.0 and apart.y < card.y + 8.0:
					free = false
					break
			if free:
				_centers[id] = spot
				moved = true
				break
	if moved:
		_measure()


## Die Halbachsen eines Rings; der innerste ist der erste.
func _reach(ring_no: int, grow: float) -> Vector2:
	return (RING + STEP * (ring_no - 1.0)) * grow + (MOAT if ring_no > MOAT_AFTER else Vector2.ZERO)


func _weigh(id: String, outer: Dictionary, weight: Dictionary) -> float:
	var sum := 0.0
	for other in outer.get(id, []):
		sum += _weigh(other, outer, weight)
	weight[id] = maxf(sum, 1.0)
	return weight[id]


func _spread(id: String, from: float, span: float, outer: Dictionary, weight: Dictionary, ring: Dictionary, grow: float) -> void:
	if id != "":
		var angle := from + span / 2.0
		var reach := _reach(ring[id], grow)
		_centers[id] = Vector2(cos(angle) * reach.x, sin(angle) * reach.y)
	var list: Array = outer.get(id, [])
	var total := 0.0
	for other in list:
		total += sqrt(weight[other])
	var at := from
	for other in list:
		# Die Wurzel dämpft: ein Ast mit viel dahinter bekommt mehr Platz, drängt die anderen aber nicht an den Rand.
		var part: float = span * sqrt(weight[other]) / maxf(total, 1.0)
		_spread(other, at, part, outer, weight, ring, grow)
		at += part


## Ohne Zutun passt das Feld ganz ins Fenster; dafür wird es notfalls
## kleiner. Mit dem Mausrad lässt es sich darüber hinaus vergrößern und
## verkleinern, mit gedrückter mittlerer Taste verschieben.
func _fit() -> void:
	var room := size - Vector2(MARGIN * 2.0, TOP + MARGIN)
	if room.x <= 0.0 or room.y <= 0.0:
		return
	var s := clampf(minf(room.x / _bounds.size.x, room.y / _bounds.size.y), MIN_SCALE, 1.0) * _zoom
	var middle := Vector2(size.x / 2.0, TOP + room.y / 2.0)
	# Verschieben geht nur, so weit die Stadt reicht: der Blick bleibt in ihr.
	# Ist das Fenster größer als sie, bleibt sie in der Mitte.
	var home := _bounds.get_center()
	var look := home - _pan / s
	var free := (City.EXTENT * CITY_EDGE - size / (2.0 * s)).max(Vector2.ZERO)
	look = look.clamp((-free).min(home), free.max(home))
	_pan = (home - look) * s
	var goal := Transform2D(Vector2(s, 0), Vector2(0, s), (middle - home * s + _pan).round())
	var gliding := _fit_tween != null and _fit_tween.is_valid()
	# Läuft schon ein Gleiten genau dorthin, bleibt es ungestört.
	if gliding and not _glide and goal.is_equal_approx(_fit_goal):
		return
	if gliding:
		_fit_tween.kill()
	_fit_goal = goal
	if _glide:
		_glide = false
		_fit_tween = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		for node in [_canvas, _town]:
			_fit_tween.tween_property(node, "position", goal.origin, SHIFT_SECONDS)
			_fit_tween.tween_property(node, "scale", Vector2(s, s), SHIFT_SECONDS)
		_wait(_fit_tween)
		return
	for node in [_canvas, _town]:
		node.position = goal.origin
		node.scale = Vector2(s, s)


## Vergrößert oder verkleinert um `factor`; was unter `at` liegt, bleibt dort.
func _zoom_by(factor: float, at: Vector2) -> void:
	var before := _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(before, _zoom):
		if factor < 1.0:
			left.emit()
		return
	var ratio := _zoom / before
	# Verschoben wird gegenüber der Mitte des Fensters – von dort aus rechnet auch der Zeiger.
	var middle := Vector2(size.x / 2.0, TOP + (size.y - TOP - MARGIN) / 2.0)
	_pan += (at - middle - _pan) * (1.0 - ratio)
	_fit()
	# Die Karte unter dem Zeiger soll ihre Lesegröße behalten.
	if _hovered != "" and _cards.has(_hovered):
		_settle(_cards[_hovered])


## Zurück zur Ansicht, in der alles zu sehen ist.
func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	_fit()


## Auf dem freien Filz zeigt ein Doppelklick wieder alles. Verschoben wird
## nur mit der mittleren Taste (siehe `_input`): mit der linken greift man
## Karten, und wer knapp daneben greift, soll nicht das Feld wegziehen.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Im Lageplan: ein Klick auf das Kreuz eines Wegs löst die Abhängigkeit.
		if plan:
			var at: Vector2 = (event.position - _canvas.position) / _canvas.scale.x
			for knob in _knobs():
				if at.distance_to(knob["at"]) <= KNOB + 3.0:
					unlink_requested.emit(knob["task"], knob["on"])
					accept_event()
					return
		if event.double_click:
			reset_view()


# -------------------------------------------------------------- Karten

func _sync_cards() -> void:
	for id in _cards.keys():
		if not _centers.has(id):
			if _cards[id] == _held:
				_held = null
				_dragging = false
			_cards[id].queue_free()
			_cards.erase(id)

	for id in _centers:
		var task = _ws.task(id)
		if task == null:
			continue
		var card: Badge = _cards.get(id)
		if card == null:
			card = Badge.new()
			card.position = _centers[id] - Badge.SIZE / 2.0
			card.pressed.connect(_on_card)
			card.mouse_entered.connect(_on_hover.bind(id, true))
			card.mouse_exited.connect(_on_hover.bind(id, false))
			_canvas.add_child(card)
			_cards[id] = card
		card.show_task(_ws, task, _images, false)
		card.selected = Field.is_tapped(task) and not plan
		# Erledigte Karten sind hier abgedunkelt statt durchscheinend: vor der Stadt bliebe sonst wenig von ihnen.
		card.modulate = Color(0.55, 0.6, 0.57, 1.0) if Model.is_done(task) else Color.WHITE
		if _spotlit and not _spotlight.has(id):
			card.modulate.a = 0.22
		if card != _held or not _dragging:
			_settle(card)


## Legt das Abzeichen an seinen Platz – etwas größer, wenn der Zeiger auf ihm ruht.
func _settle(card: Badge) -> void:
	var id: String = card.task_id
	if not _centers.has(id):
		return
	var task = _ws.task(id)
	var tapped: bool = task != null and Field.is_tapped(task)
	var big := id == _hovered
	var s := 1.12 if big else 1.0
	card.z_index = 60 if big else 8 if tapped else 5
	# Der Weg an den Platz: je Abzeichen nur eine Bewegung. Läuft schon eine
	# dorthin, bleibt sie ungestört – sonst risse jeder neue Stand an ihr.
	var goal: Vector2 = _centers[id] - Badge.SIZE / 2.0
	var going: Variant = card.get_meta("going") if card.has_meta("going") else null
	var running: bool = going is Tween and going.is_valid() and going.is_running() or _waiting.has(going)
	if not (running and card.get_meta("goal", Vector2.INF).is_equal_approx(goal)):
		if going is Tween and going.is_valid():
			going.kill()
		if card.position.distance_to(goal) < 0.5:
			card.position = goal
		else:
			var slow := _move_time > MOVE_SECONDS
			var move := card.create_tween()
			move.tween_property(card, "position", goal, _move_time).set_trans(Tween.TRANS_SINE if slow else Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT if slow else Tween.EASE_OUT)
			card.set_meta("going", move)
			card.set_meta("goal", goal)
			_wait(move)
	# Größe und Anheben für sich, damit ein Überfahren die Reise nicht stört.
	var look: Variant = card.get_meta("look") if card.has_meta("look") else null
	if look is Tween and look.is_valid():
		look.kill()
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	card.set_meta("look", tween)
	tween.tween_property(card, "scale", Vector2(s, s), MOVE_SECONDS * 0.6)
	tween.tween_property(card, "rotation", 0.0, MOVE_SECONDS)
	# Was in Arbeit ist, hebt sich von selbst (`selected`); sonst nur, was unter dem Zeiger liegt.
	tween.tween_property(card, "lift", 1.0 if big else 0.0, MOVE_SECONDS)


func _on_hover(id: String, on: bool) -> void:
	if _dragging:
		return
	if on:
		var before := _hovered
		_hovered = id
		if before != "" and before != id and _cards.has(before):
			_settle(_cards[before])
	elif _hovered == id:
		_hovered = ""
	if _cards.has(id):
		_settle(_cards[id])
	_show_peek()


## Zeigt neben dem Abzeichen unter dem Zeiger seine Karte – in voller Größe,
## gleich wie weit das Feld verkleinert ist.
func _show_peek() -> void:
	if _peek_tween != null and _peek_tween.is_valid():
		_peek_tween.kill()
	var task = _ws.task(_hovered) if _ws != null and _hovered != "" else null
	if task == null or not _centers.has(_hovered) or _dragging:
		_peek_tween = _peek.create_tween()
		_peek_tween.tween_property(_peek, "modulate:a", 0.0, 0.1)
		_peek_tween.tween_callback(_peek.hide)
		return
	_peek.show_task(_ws, task, _images, true)
	# Rechts vom Abzeichen, wenn dort Platz ist, sonst links; nie unter der Kopfzeile, nie über den Rand.
	var s := _canvas.scale.x
	var at: Vector2 = _canvas.position + _centers[_hovered] * s
	var reach := BOX.x / 2.0 * s + 16.0
	var left := at.x + reach + Card.SIZE.x > size.x - 8.0
	var spot := Vector2(at.x - reach - Card.SIZE.x if left else at.x + reach, at.y - Card.SIZE.y / 2.0)
	spot.y = clampf(spot.y, HEAD + 6.0, maxf(size.y - Card.SIZE.y - 8.0, HEAD + 6.0))
	_peek.position = spot.round()
	_peek.visible = true
	_peek_tween = _peek.create_tween()
	_peek_tween.tween_property(_peek, "modulate:a", 1.0, 0.12)


# --------------------------------------------------------------- Käfer

## Wie viel Platz das Abzeichen auf dem Feld einnimmt. Anders als früher die
## Karte liegt es nie quer.
func _card_box(_id: String) -> Vector2:
	return BOX


## Ein Platz auf der Straße: auf dem Weg von `from_id` zu `to_id` (leer: zur
## Mitte), `back` Pixel vor dessen Ende. Gibt `[Ort, Richtung, Strecke bis
## dorthin]` zurück – oder null, wenn es den Weg (noch) nicht gibt oder er zu kurz ist.
func _street_spot(from_id: String, to_id: String, back: float) -> Variant:
	if not street_ways or _routes_due or not _centers.has(from_id) or (to_id != "" and not _centers.has(to_id)):
		return null
	var path := _route(from_id, to_id)
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	if total < back + 24.0:
		return null
	var left := total - back
	for i in path.size() - 1:
		var piece := path[i].distance_to(path[i + 1])
		if left <= piece and piece > 0.0:
			return [path[i].lerp(path[i + 1], left / piece), (path[i + 1] - path[i]) / piece, total - back]
		left -= piece
	return null


## Wo der `index`-te von `count` Gegnern steht, wenn es zu ihm keinen Weg
## gibt: neben dem Schild, untereinander.
func _pest_spot(card_id: String, index: int, count: int) -> Variant:
	if not _centers.has(card_id):
		return null
	var card := _card_box(card_id)
	var apart := minf(30.0, (card.y - 30.0) / maxf(count - 1, 1.0))
	# Neben dem Schild, nicht darauf – und auf seiner Höhe, nicht auf der des Bands.
	return _centers[card_id] + Vector2(BESIDE, (index - (count - 1) / 2.0) * apart - 8.0)


func _sync_bugs() -> void:
	# Schädlinge
	var wanted := {}
	var at := {}
	var on_street := {}
	# Wohin jeder Gegner schaut, und welche gerade erst aufgetaucht sind.
	var face := {}
	var born := {}
	var beaten := {}
	for card_id in _field["pests"]:
		var list: Array = _field["pests"][card_id]
		for i in list.size():
			var p: Dictionary = list[i]
			var spot = _pest_spot(card_id, i, list.size())
			if spot == null:
				continue
			var key := "%s|%s" % [card_id, p["blocker_id"]]
			# Der Gegner steht auf der Straße vor der Karte – dort, wo der
			# herankommt, der ihn stellt. Ohne Weg bleibt er neben dem Schild.
			var street = _street_spot(str(p["blocker_id"]), card_id, STREET_BACK)
			var facing := -PI / 2.0
			if street != null:
				spot = street[0]
				facing = (-street[1]).angle() + PI / 2.0
				on_street[key] = true
			wanted[key] = true
			at[key] = spot
			var bug: Bug = _pests.get(key)
			if bug == null:
				bug = _new_bug(Bug.PEST, spot, 1.25)
				# Käfer sitzen, wie sie wollen; Soldaten schauen dem Angreifer entgegen (siehe unten).
				bug.rotation = deg_to_rad(float(hash(key) % 50) - 25.0)
				_pests[key] = bug
				born[key] = true
				_pop_in(bug)
			elif p["damage"] > bug.hurt + 0.001:
				_bite(key)
			face[key] = facing
			bug.wall = p["wall"]
			bug.hurt = p["damage"]
			# Hält er nichts mehr aus – alle Kästchen und Unteraufgaben sind durch,
			# nur der Haken an der Aufgabe fehlt noch –, liegt er schon am Boden
			# (Nutzer, 2026-10-12). Weg ist er erst, wenn sie erledigt ist.
			bug.dead = not p["wall"] and p["damage"] >= 0.999
			if bug.dead:
				beaten[key] = true
			bug.set_meta("home", spot)
			bug.create_tween().tween_property(bug, "position", spot, _move_time)
	for key in _pests.keys():
		if not wanted.has(key):
			_fall(_pests[key])
			_pests.erase(key)

	# Marienkäfer
	var keep := {}
	var stood := {}
	for card_id in _field["fronts"]:
		if not _centers.has(card_id):
			continue
		var fronts: Array = _field["fronts"][card_id]
		if fronts.is_empty():
			# Innerster Ring: der Marienkäfer geht auf den großen Käfer los, von seiner Karte her –
			# auf der Straße, die zur Mitte führt.
			var toward: Vector2 = _centers[card_id].normalized()
			var gate = _street_spot(card_id, "", 14.0) if Bug.style == Bug.SOLDIERS else null
			if gate != null:
				_want_lady("%s|boss" % card_id, card_id, "", gate[0], Vector2.ZERO, keep, gate[2])
			else:
				_want_lady("%s|boss" % card_id, card_id, "", toward * (BOSS_RADIUS + 18.0 if Bug.style == Bug.SOLDIERS else BOSS_RADIUS - 22.0), Vector2.ZERO, keep)
		for f in fronts:
			var pest_key := "%s|%s" % [f["on"], f["blocker_id"]]
			if not at.has(pest_key):
				continue
			var pest_at: Vector2 = at[pest_key]
			# Von der eigenen Karte her an den Schädling heran.
			var across := Vector2(BESIDE * 2.0, 0.0)
			# Steht der Gegner auf der Straße, hält der eigene ein Stück vor ihm auf demselben Weg.
			var stand = _street_spot(card_id, f["on"], STREET_BACK + DUEL) if on_street.has(pest_key) and f["blocker_id"] == card_id else null
			var lady_at: Vector2 = stand[0] if stand != null else pest_at - across
			if stand != null:
				_want_lady("%s|%s" % [card_id, pest_key], card_id, f["on"], lady_at, pest_at, keep, stand[2])
			else:
				_want_lady("%s|%s" % [card_id, pest_key], card_id, f["on"], lady_at, pest_at, keep)
			# Auf einen, der schon liegt, wird nicht mehr geschossen.
			_ladies["%s|%s" % [card_id, pest_key]].set_meta("won", beaten.has(pest_key))
			# Der Gegner schaut den an, der ihn stellt – nicht bloß die Straße
			# hinunter, die bis zu ihm noch eine Kurve machen kann.
			if not stood.has(pest_key):
				stood[pest_key] = true
				face[pest_key] = (lady_at - pest_at).angle() + PI / 2.0
	for key in _ladies.keys():
		if not keep.has(key):
			_leave(_ladies[key])
			_ladies.erase(key)
	if Bug.style == Bug.SOLDIERS:
		for key in face:
			var pest: Bug = _pests[key]
			var turning: Variant = pest.get_meta("turn") if pest.has_meta("turn") else null
			if turning is Tween and turning.is_valid():
				turning.kill()
			if born.has(key):
				pest.rotation = face[key]
			elif absf(angle_difference(pest.rotation, face[key])) > 0.01:
				var turn := pest.create_tween()
				turn.tween_property(pest, "rotation", pest.rotation + angle_difference(pest.rotation, face[key]), _move_time)
				pest.set_meta("turn", turn)

	# Der große Käfer
	var done: int = _field["boss"]["done"]
	if _boss_done >= 0 and done > _boss_done:
		_shake(_boss)
		for key in _ladies:
			if key.ends_with("|boss"):
				_lunge(_ladies[key])
	_boss_done = done


func _new_bug(kind: String, at: Vector2, girth: float) -> Bug:
	var bug := Bug.new()
	bug.kind = kind
	bug.girth = girth
	bug.position = at
	bug.z_index = 12 if kind == Bug.PEST else 24
	_canvas.add_child(bug)
	return bug


## Ein Marienkäfer für diese Front: gibt es ihn schon, rückt er nur nach;
## sonst kommt er von seiner Karte herüber – auf dem Weg, den auch die Linie
## nimmt. `to_id` ist die Karte, an der er kämpft, leer für die Mitte.
func _want_lady(key: String, card_id: String, to_id: String, spot: Vector2, target: Vector2, keep: Dictionary, along := -1.0) -> void:
	keep[key] = true
	var bug: Bug = _ladies.get(key)
	var fresh := bug == null
	if fresh:
		bug = _new_bug(Bug.LADY, _centers[card_id], 1.1)
		_ladies[key] = bug
	bug.set_meta("home", spot)
	bug.set_meta("card", card_id)
	bug.set_meta("along", along)
	bug.set_meta("to", to_id)
	bug.set_meta("target", target)
	bug.set_meta("busy", true)
	# Ist er noch auf dem Marsch, geht er ihn zu Ende – der Stand wird öfter
	# gezeigt, als sich etwas ändert, und zwei Bewegungen zugleich rissen ihn
	# hin und her. Wohin er am Ende gehört, liest er dann selbst nach.
	if bug.get_meta("marching", false):
		return
	if fresh:
		var path := PackedVector2Array([_centers[card_id]])
		# Steht er auf der Straße, geht er den Weg nur bis dorthin – nicht bis zur Karte und zurück.
		path.append_array(Badge._stretch(_route(card_id, to_id), 0.0, along) if along >= 0.0 else _route(card_id, to_id))
		path.append(spot)
		bug.set_meta("marching", true)
		_march(bug, path).tween_callback(func() -> void:
			bug.set_meta("marching", false)
			_settle_lady(bug))
		return
	_settle_lady(bug)


## Stellt einen Marienkäfer auf seinen Platz, den Blick zum Gegner. Eine
## Bewegung, die dafür schon läuft, wird abgelöst.
func _settle_lady(bug: Bug) -> void:
	var spot: Vector2 = bug.get_meta("home", bug.position)
	var target: Vector2 = bug.get_meta("target", spot)
	var old: Variant = bug.get_meta("move") if bug.has_meta("move") else null
	if old is Tween and old.is_valid():
		old.kill()
	var arrived := func() -> void:
		bug.rotation = (target - spot).angle() + PI / 2.0
		bug.set_meta("busy", false)
	if bug.position.distance_to(spot) <= 2.0:
		bug.position = spot
		arrived.call()
		return
	bug.rotation = (spot - bug.position).angle() + PI / 2.0
	var tween := bug.create_tween()
	bug.set_meta("move", tween)
	tween.tween_property(bug, "position", spot, MOVE_SECONDS).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(arrived)


## Lässt eine Figur einen Weg entlanggehen, in gleichmäßigem Schritt und mit
## dem Blick nach vorn. Gibt den Tween zurück, damit danach noch etwas folgen kann.
func _march(bug: Bug, path: PackedVector2Array) -> Tween:
	var marks := PackedFloat32Array([0.0])
	for i in path.size() - 1:
		marks.append(marks[i] + path[i].distance_to(path[i + 1]))
	var total := marks[marks.size() - 1]
	var tween := bug.create_tween()
	if total < 1.0:
		return tween
	tween.tween_method(func(way: float) -> void:
		var i := 0
		while i < path.size() - 2 and marks[i + 1] < way:
			i += 1
		var piece := marks[i + 1] - marks[i]
		bug.position = path[i].lerp(path[i + 1], (way - marks[i]) / piece if piece > 0.01 else 1.0)
		if piece > 0.01:
			# Um die Ecken dreht sich die Figur weich mit.
			bug.rotation = lerp_angle(bug.rotation, (path[i + 1] - path[i]).angle() + PI / 2.0, 0.3),
		0.0, total, clampf(total / MARCH_SPEED, MARCH_MIN, MARCH_MAX)).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


func _pop_in(bug: Bug) -> void:
	var full := bug.girth
	bug.girth = 0.1
	bug.create_tween().tween_property(bug, "girth", full, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Der Schädling ist besiegt: er kippt auf den Rücken und verblasst.
func _fall(bug: Bug) -> void:
	bug.dead = true
	var tween := bug.create_tween()
	tween.tween_property(bug, "rotation", bug.rotation + PI * 0.9, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.1)
	tween.tween_property(bug, "modulate:a", 0.0, 0.5)
	tween.tween_callback(bug.queue_free)


## Der Marienkäfer hat hier nichts mehr zu tun: zurück zu seiner Karte.
func _leave(bug: Bug) -> void:
	bug.set_meta("busy", true)
	var card_id: String = bug.get_meta("card", "")
	var to_id: String = bug.get_meta("to", "")
	# Zurück geht es denselben Weg, den er gekommen ist.
	var path := PackedVector2Array([bug.position])
	if _centers.has(card_id) and (to_id == "" or _centers.has(to_id)):
		var along: float = bug.get_meta("along", -1.0)
		var way := Badge._stretch(_route(card_id, to_id), 0.0, along) if along >= 0.0 else _route(card_id, to_id).duplicate()
		way.reverse()
		path.append_array(way)
		path.append(_centers[card_id])
	else:
		path.append(bug.position + Vector2(0, 60))
	var tween := _march(bug, path)
	# Kurz vor der eigenen Karte verblasst er.
	tween.tween_property(bug, "modulate:a", 0.0, 0.3)
	tween.tween_callback(bug.queue_free)


## Ein Kästchen ist abgehakt: jeder Marienkäfer an diesem Schädling beißt zu.
func _bite(pest_key: String) -> void:
	var pest: Bug = _pests.get(pest_key)
	if pest != null:
		_shake(pest)
	for key in _ladies:
		if key.ends_with("|" + pest_key):
			_lunge(_ladies[key])


func _lunge(bug: Bug) -> void:
	if bug.get_meta("busy", false):
		return
	var home: Vector2 = bug.get_meta("home", bug.position)
	var target: Vector2 = bug.get_meta("target", home)
	bug.set_meta("busy", true)
	var tween := bug.create_tween()
	tween.tween_property(bug, "position", home.lerp(target, 0.55), 0.09).set_ease(Tween.EASE_OUT)
	tween.tween_property(bug, "position", home, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(func() -> void: bug.set_meta("busy", false))


func _shake(bug: Bug) -> void:
	var rest := bug.rotation
	var tween := bug.create_tween()
	for turn in [0.35, -0.3, 0.2, -0.1, 0.0]:
		tween.tween_property(bug, "rotation", rest + turn, 0.06)


## Die gezogene Karte kippt in die Bewegungsrichtung, wie am Spieltisch: sie
## wird in der Kipprichtung schmaler, lehnt sich leicht mit, und Licht und
## Folienschimmer wandern über sie.
func _tilt_held(delta: float) -> void:
	if not _dragging or _held == null or not is_instance_valid(_held):
		return
	var k := 1.0 - exp(-delta * 1000.0 / TILT_RESPONSE_MS)
	if Time.get_ticks_msec() - _last_move > TILT_STILL_MS:
		_velocity -= _velocity * k
	var target := Vector2(tanh(_velocity.x / TILT_SPEED), tanh(_velocity.y / TILT_SPEED)) * MAX_TILT * TILT_STRENGTH
	_tilt += (target - _tilt) * k
	var squash := Vector2(cos(deg_to_rad(_tilt.x * 1.7)), cos(deg_to_rad(_tilt.y * 1.7)))
	_held.scale = squash * 1.2
	_held.rotation = deg_to_rad(_tilt.x) * 0.22
	_held.set_tilt(-_tilt / MAX_TILT)


## Die Marienkäfer stehen nicht still: sie tänzeln an ihrem Platz.
func _process(delta: float) -> void:
	_tilt_held(delta)
	if not is_visible_in_tree():
		return
	_time += delta
	# Unter dem Zeiger: die Verbindungen dieser Karte bleiben, die übrigen treten zurück.
	if _hovered != "":
		_focus_id = _hovered
	_focus = move_toward(_focus, 1.0 if _hovered != "" else 0.0, delta / FOCUS_SECONDS)
	# Über die Ringe wandert ein Schimmer, auch wenn niemand kämpft.
	_back.queue_redraw()
	if plan:
		_fx.queue_redraw()
	if _ladies.is_empty():
		return
	# Die Striche der Angriffe wandern, und geschossen wird auch.
	_fx.queue_redraw()
	for key in _ladies:
		var bug: Bug = _ladies[key]
		if bug.get_meta("busy", false):
			continue
		var home: Vector2 = bug.get_meta("home", bug.position)
		var phase := float(hash(key) % 100) / 10.0
		# Käfer tänzeln; Soldaten stehen still.
		if Bug.style != Bug.SOLDIERS:
			bug.position = home + Vector2(sin(_time * 5.0 + phase) * 1.4, cos(_time * 3.7 + phase) * 1.1)


# ------------------------------------------------------------- Schüsse

## Welche Figuren kämpfen: Käfer oder Soldaten (`Bug.BUGS`, `Bug.SOLDIERS`).
func set_style(value: String) -> void:
	if Bug.style == value:
		return
	Bug.style = value
	_boss.queue_redraw()
	for key in _pests:
		_pests[key].queue_redraw()
	for key in _ladies:
		_ladies[key].queue_redraw()
	_fx.queue_redraw()


## Soldaten schießen: jeder eigene in seinem Takt auf sein Ziel, und der
## Gegner, auf den er schießt, zurück. Alles ergibt sich aus der Zeit – es gibt
## keine Geschosse, die man verwalten müsste.
func _draw_fx() -> void:
	if plan:
		_draw_links()
		return
	if Bug.style != Bug.SOLDIERS:
		return
	for key in _ladies:
		var own: Bug = _ladies[key]
		if own.get_meta("busy", false) or own.get_meta("won", false):
			continue
		var target: Vector2 = own.get_meta("target", own.position)
		var phase := float(hash(key) % 1000) / 1000.0 * SHOT_EVERY
		var round_no := int((_time + phase) / SHOT_EVERY) + hash(key)
		_draw_burst(own.position, target, own.girth, round_no, fmod(_time + phase, SHOT_EVERY))
		# Der Gegner antwortet im Gegentakt – der Panzer nicht, der hat Besseres zu tun.
		if not key.ends_with("|boss"):
			_draw_burst(target, own.position, own.girth, round_no + 7, fmod(_time + phase + SHOT_EVERY * 0.5, SHOT_EVERY))


## Eine Salve: mehrere Schüsse kurz hintereinander, `since` Sekunden nach ihrem Beginn.
func _draw_burst(from: Vector2, to: Vector2, girth: float, seed_value: int, since: float) -> void:
	for i in BURST:
		var shot := since - i * BURST_GAP
		if shot >= 0.0 and shot < SHOT_SECONDS:
			_draw_shot(from, to, girth, seed_value + i * 3, shot / SHOT_SECONDS)


## Ein Schuss, dezent: ein kleines Mündungsfeuer im ersten Moment und ein
## kurzer heller Strich, der vom Gewehr auf den Gegner zufliegt und vor ihm
## erlischt. `progress` läuft während des Schusses von 0 bis 1.
func _draw_shot(from: Vector2, to: Vector2, girth: float, seed_value: int, progress: float) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	var muzzle := from + dir * 26.0 * girth + side * 7.0 * girth
	var miss := (float(seed_value % 7) - 3.0) * 1.2
	# Die Spur endet am Rand der Figur, nicht in ihrem Helm.
	var end := to + side * (7.0 * girth + miss) - dir * 15.0 * girth
	var way := end - muzzle
	if way.dot(dir) <= 0.0:
		return
	if progress < 0.3:
		_fx.draw_circle(muzzle, 1.7 * girth, Color(1.0, 0.9, 0.6, 0.85), true, -1.0, false)
	var head := progress
	var tail := maxf(progress - 0.28, 0.0)
	_fx.draw_line(muzzle + way * tail, muzzle + way * head, Color(1.0, 0.94, 0.7, 0.6), 1.1, false)


# ------------------------------------------------------------- Zeichnen

func _draw_back() -> void:
	_back.draw_set_transform(REACH)
	if _field.is_empty():
		return
	var done := {}
	for n in _field["nodes"]:
		done[n["id"]] = Model.is_done(n["task"])

	# Die Ringe sind die Stufen der Einnahme und tragen deren Farbe: grün, was
	# eingenommen ist, rot, was dem Gegner gehört, und dazwischen die Front.
	# Über jeden wandert langsam ein Schimmer; die Front atmet dazu.
	var front_ring: int = _field["front"]
	for k in _rings:
		var reach := _reach(k + 1, _grow)
		if plan:
			for i in 72:
				var a0 := TAU * i / 72.0
				var a1 := TAU * (i + 0.6) / 72.0
				_back.draw_line(Vector2(cos(a0) * reach.x, sin(a0) * reach.y), Vector2(cos(a1) * reach.x, sin(a1) * reach.y), Color(1, 1, 1, 0.3), 1.4, false)
			_back.draw_string(Palette.sharp_body_font(), Vector2(8.0, -reach.y - 7.0), "Ring %d" % (k + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
			continue
		var at_front := k + 1 == front_ring
		var tone := Palette.OK if k + 1 > front_ring else Palette.P2 if at_front else Palette.P1
		var base := RING_FRONT + 0.14 * sin(_time * 1.8) if at_front else RING_QUIET
		# Benachbarte Ringe laufen gegeneinander, jeder in seinem Tempo.
		var turn := _time * RING_TURN * (1.0 if k % 2 == 0 else -1.0) / (1.0 + 0.35 * k) + k * 1.7
		var loop := PackedVector2Array()
		var tones := PackedColorArray()
		var glow := PackedColorArray()
		for i in RING_POINTS + 1:
			var a := TAU * i / float(RING_POINTS)
			loop.append(Vector2(cos(a) * reach.x, sin(a) * reach.y))
			# Zwei Schimmer liegen sich gegenüber und laufen weich aus.
			var glint := pow(maxf(cos(a - turn), 0.0), 6.0) + pow(maxf(cos(a - turn - PI), 0.0), 6.0)
			tones.append(Color(tone.lightened(0.35 * glint), base + RING_GLINT * glint))
			glow.append(Color(tone, 0.2 * glint))
		# Unter dem Schimmer liegt ein breiter, weicher Schein.
		_back.draw_polyline_colors(loop, glow, 7.0, false)
		_back.draw_polyline_colors(loop, tones, 2.0 if at_front else 1.5, false)

	# Die Wege nach innen: grün, wo die Karte erledigt ist, sonst blass.
	for way in _field["ways"]:
		if not _centers.has(way["from"]) or _ways_fade <= 0.001:
			continue
		var from: Vector2 = _centers[way["from"]]
		var to: Vector2 = _centers.get(way["to"], Vector2.ZERO)
		if way["to"] == "":
			to = from.normalized() * BOSS_RADIUS
		var color := Color(Palette.OK, 0.6) if done[way["from"]] and not plan else Color(1, 1, 1, 0.26)
		color.a *= _shown(way["from"], way["to"]) * _ways_fade
		# Gehört der Weg zur Karte unter dem Zeiger, wird er kräftiger und breiter.
		var raised := _focus if way["from"] == _focus_id or way["to"] == _focus_id else 0.0
		color.a = minf(color.a + FOCUS_RAISE * raised, 1.0)
		var width := 2.0 + raised
		var path := _route(way["from"], way["to"] if _centers.has(way["to"]) else "")
		_back.draw_polyline(path, color, width, false)
		if plan:
			continue
		# Helle Striche wandern nach innen – dezenter als bei den Angriffen.
		_draw_flow(path, Color(color.lightened(0.45 + 0.3 * raised), minf(color.a + WAY_GLOW, 1.0)), width, WAY_SPEED, WAY_GAP, WAY_DASH)

	# Wird eine Karte gerade gezogen, bleibt an ihrem Platz ihr Umriss liegen –
	# sonst stünden die Soldaten, die an ihr kämpfen, im Nichts.
	if _dragging and _held != null and is_instance_valid(_held) and _centers.has(_held.task_id):
		var card := _card_box(_held.task_id)
		var slot := StyleBoxFlat.new()
		slot.bg_color = Color(0, 0, 0, 0.28)
		slot.border_color = Color(1, 1, 1, 0.3)
		slot.set_border_width_all(1)
		slot.set_corner_radius_all(8)
		_back.draw_style_box(slot, Rect2(_centers[_held.task_id] - card / 2.0, card))

	# Die Angriffe: von jeder getappten Karte laufen Striche zu dem, was sie
	# angreift – zur Karte mit ihrem Schädling oder zum großen Käfer.
	for card_id in _field["fronts"]:
		if not _centers.has(card_id) or plan or _ways_fade <= 0.001:
			continue
		for target in _targets_of(card_id):
			_draw_attack(_route(card_id, target), _shown(card_id, target) * _ways_fade)

	if plan:
		# Die Mitte des Lageplans: das Ziel mit Fahne und Stand. Schwebt eine
		# Karte aus der Reserve über der Stadt, leuchtet es grün: hierher.
		_back.draw_circle(Vector2.ZERO, BOSS_RADIUS, Color(0.06, 0.12, 0.12, 0.9), true, -1.0, false)
		_back.draw_arc(Vector2.ZERO, BOSS_RADIUS, 0.0, TAU, 96, Color(Palette.OK, 0.9) if drop_hint else Color(1, 1, 1, 0.35), 3.0 if drop_hint else 2.0, false)
		if drop_hint:
			_back.draw_circle(Vector2.ZERO, BOSS_RADIUS, Color(Palette.OK, 0.14), true, -1.0, false)
		_back.draw_line(Vector2(-16, 2), Vector2(16, 2), Color(1, 1, 1, 0.7), 2.4, false)
		_back.draw_line(Vector2(0, 2), Vector2(0, -36), Color(1, 1, 1, 0.7), 2.4, false)
		_back.draw_colored_polygon(PackedVector2Array([Vector2(0, -36), Vector2(19, -36), Vector2(14, -30), Vector2(19, -24), Vector2(0, -24)]), Palette.P1)
		var name: String = str(_milestone.get("title", "")) if _milestone != null else ""
		_back.draw_string(Palette.sharp_title_font(), Vector2(-BOSS_RADIUS, 24.0), name, HORIZONTAL_ALIGNMENT_CENTER, BOSS_RADIUS * 2.0, 13, Palette.INK)
		_back.draw_string(Palette.sharp_body_font(), Vector2(-BOSS_RADIUS, 40.0), "%d Karten · %d fertig" % [_field["boss"]["total"], _field["boss"]["done"]], HORIZONTAL_ALIGNMENT_CENTER, BOSS_RADIUS * 2.0, 10, Color(1, 1, 1, 0.6))
		return

	# Die Mitte: der Bau des großen Käfers, außen herum sein Leben.
	_back.draw_circle(Vector2.ZERO, BOSS_RADIUS, Color(0, 0, 0, 0.3), true, -1.0, false)
	if _over_boss:
		_back.draw_circle(Vector2.ZERO, BOSS_RADIUS, Color(Palette.OK, 0.25), true, -1.0, false)
	var total: int = maxi(_field["boss"]["total"], 1)
	var left: int = total - _field["boss"]["done"]
	_back.draw_arc(Vector2.ZERO, BOSS_RADIUS, 0.0, TAU, 96, Color(1, 1, 1, 0.16), 5.0, false)
	if left > 0:
		_back.draw_arc(Vector2.ZERO, BOSS_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * left / total, 96, Palette.P1, 5.0, false)
	var text := "noch %d von %d" % [left, total] if left > 0 else "besiegt"
	_back.draw_string(Palette.sharp_body_font(), Vector2(-BOSS_RADIUS, BOSS_RADIUS - 16.0), text, HORIZONTAL_ALIGNMENT_CENTER, BOSS_RADIUS * 2.0, 12, Color(1, 1, 1, 0.7))


## Ein Angriff als Linie: ein roter Grund und darauf helle Striche, die zum
## Ziel wandern.
func _draw_attack(path: PackedVector2Array, shown := 1.0) -> void:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	if total < 4.0:
		return
	path = _straight_end(path, ARROW_RUN)
	var tone := Color(ATTACK, ATTACK.a * shown)
	_back.draw_polyline(path, Color(ATTACK, 0.35 * shown), 3.0, false)
	var dir := _draw_flow(path, tone, 3.0, ATTACK_SPEED, ATTACK_GAP, ATTACK_DASH)
	# Eine Spitze am Ziel.
	var to := path[path.size() - 1]
	var side := Vector2(-dir.y, dir.x)
	_back.draw_colored_polygon(PackedVector2Array([to, to - dir * 11.0 + side * 6.0, to - dir * 11.0 - side * 6.0]), tone)


## Der Weg von der Karte `from_id` zur Karte `to_id` – oder zum Punkt `to`,
## wenn `to_id` leer ist –, an beiden Enden bis an den Rand der Karte gekürzt.
## Jede Karte zählt mit der Fläche, die sie gerade einnimmt: quer, wenn sie
## getappt ist.
func _between_cards(from_id: String, to_id: String, to: Vector2) -> PackedVector2Array:
	var from: Vector2 = _centers[from_id]
	if to_id != "":
		to = _centers[to_id]
	var dir := to - from
	if dir.length() < 1.0:
		return PackedVector2Array([from, to])
	var start := from + dir * minf(_to_edge(_card_box(from_id), dir), 0.45)
	var end := to - dir * minf(_to_edge(_card_box(to_id), dir), 0.45) if to_id != "" else to
	return PackedVector2Array([start, end])


## Macht das Ende eines Wegs gerade: die letzten `run` Pixel werden zu einem
## einzigen Stück. Sonst säße die Pfeilspitze mitten in einer Kurve und sähe
## geknickt aus.
func _straight_end(path: PackedVector2Array, run: float) -> PackedVector2Array:
	var left := run
	var i := path.size() - 1
	while i > 0:
		var piece := path[i].distance_to(path[i - 1])
		if piece >= left:
			var out := path.slice(0, i)
			var from := path[i].move_toward(path[i - 1], left)
			if from.distance_to(path[i - 1]) > 0.5:
				out.append(from)
			out.append(path[path.size() - 1])
			return out
		left -= piece
		i -= 1
	return PackedVector2Array([path[0], path[path.size() - 1]])


## Wie deckend eine Verbindung zwischen diesen beiden Karten gerade ist: voll,
## solange keine Karte unter dem Zeiger liegt oder sie zu dieser gehört.
func _shown(from_id: String, to_id: String) -> float:
	if _focus <= 0.0 or from_id == _focus_id or to_id == _focus_id:
		return 1.0
	return lerpf(1.0, FOCUS_DIM, _focus)


## Striche, die einen Weg entlangwandern, auch um die Ecken: alle `gap` einer,
## `dash` lang. Gibt die Richtung des letzten Stücks zurück.
func _draw_flow(path: PackedVector2Array, color: Color, width: float, speed: float, gap: float, dash: float) -> Vector2:
	var done := 0.0
	var dir := Vector2.RIGHT
	for i in path.size() - 1:
		var from := path[i]
		var length := from.distance_to(path[i + 1])
		if length < 0.01:
			continue
		dir = (path[i + 1] - from) / length
		var at := fmod(_time * speed - done, gap)
		if at < 0.0:
			at += gap
		at -= gap
		while at < length:
			var start := maxf(at, 0.0)
			var end := minf(at + dash, length)
			if end > start:
				_back.draw_line(from + dir * start, from + dir * end, color, width, false)
			at += gap
		done += length
	return dir


## Der Weg von der Karte `from_id` zur Karte `to_id` – oder zur Mitte, wenn
## `to_id` leer ist: den Straßen der Stadt entlang, oder gerade, wenn
## `street_ways` aus ist. Gesucht wird von Kartenmitte zu Kartenmitte; so
## verlässt der Weg die Karte an der Seite, die ihm am besten liegt. Zu sehen
## ist er erst ab dem Kartenrand. Gerechnet wird jeder Weg nur einmal.
func _route(from_id: String, to_id: String) -> PackedVector2Array:
	var key := from_id + ">" + to_id
	if _routes.has(key):
		return _routes[key]
	var from: Vector2 = _centers[from_id]
	var straight := _between_cards(from_id, to_id, from.normalized() * BOSS_RADIUS)
	var path := straight
	if street_ways:
		var from_box := Rect2(from - _card_box(from_id) / 2.0, _card_box(from_id)).grow(4.0)
		path = _trim(_city.route(from, _centers[to_id] if to_id != "" else Vector2.ZERO),
			func(p: Vector2) -> bool: return from_box.has_point(p))
		path.reverse()
		if to_id == "":
			path = _trim(path, func(p: Vector2) -> bool: return p.length() < BOSS_RADIUS + 3.0)
		else:
			var to_box := Rect2(_centers[to_id] - _card_box(to_id) / 2.0, _card_box(to_id)).grow(4.0)
			path = _trim(path, func(p: Vector2) -> bool: return to_box.has_point(p))
		path.reverse()
		if path.size() < 2:
			path = straight
	_routes[key] = path
	return path


## Schneidet von einem Weg den Anfang ab, so weit er in einer Fläche liegt:
## er beginnt dann dort, wo er sie zum letzten Mal verlässt.
func _trim(path: PackedVector2Array, inside: Callable) -> PackedVector2Array:
	var last := -1
	for i in path.size():
		if inside.call(path[i]):
			last = i
	if last < 0:
		return path
	if last >= path.size() - 1:
		return PackedVector2Array()
	var a := path[last]
	var b := path[last + 1]
	for k in 12:
		var mid := (a + b) / 2.0
		if inside.call(mid):
			a = mid
		else:
			b = mid
	var out := PackedVector2Array([b])
	out.append_array(path.slice(last + 1))
	return out


## Sagt der Stadt, wo Karten und Mitte liegen, damit die Wege sie meiden.
func _tell_city() -> void:
	var boxes := [Rect2(-BOSS_RADIUS, -BOSS_RADIUS, BOSS_RADIUS * 2.0, BOSS_RADIUS * 2.0)]
	# Jede Karte zählt mit der Fläche beider Lagen, hochkant und quer: sonst
	# änderten sich die Wege, sobald man eine tappt.
	var card := BOX
	var both := Vector2.ONE * maxf(card.x, card.y)
	for id in _centers:
		boxes.append(Rect2(_centers[id] - both / 2.0, both).grow(CARD_ROOM))
	_city.set_cards(boxes)
	_routes.clear()
	# Jeder gefundene Weg macht seine Straße für die folgenden teurer. Darum
	# hier in fester Reihenfolge, die nicht davon abhängt, was getappt ist:
	# erst alle Wege, dann die Angriffe, die keinem Weg folgen. So bleibt ein
	# Weg derselbe, wenn aus ihm ein Angriff wird.
	for way in _field["ways"]:
		if _centers.has(way["from"]):
			_route(way["from"], way["to"] if _centers.has(way["to"]) else "")
	for card_id in _field["fronts"]:
		if _centers.has(card_id):
			for target in _targets_of(card_id):
				_route(card_id, target)


## Wohin die Angriffe einer getappten Karte gehen: zu jeder Karte, an der sie
## kämpft, oder – leer – zur Mitte.
func _targets_of(card_id: String) -> Array:
	var targets := []
	var fronts: Array = _field["fronts"][card_id]
	if fronts.is_empty():
		targets.append("")
	for front in fronts:
		if not targets.has(front["on"]) and _centers.has(front["on"]):
			targets.append(front["on"])
	return targets


## Welcher Anteil von `dir` von der Mitte einer Karte der Größe `box` bis zu
## ihrem Rand reicht – mit etwas Luft.
func _to_edge(box: Vector2, dir: Vector2) -> float:
	var half := box / 2.0 + Vector2(4, 4)
	return minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))


# -------------------------------------------------------------- Bedienen

func _on_card(card: Control, event: InputEventMouseButton) -> void:
	var id: String = card.task_id
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_open_menu(id)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	_click_ticket += 1
	# Getappt wird mit dem Doppelklick: ein einzelner Klick soll nichts ändern,
	# er rutscht zu leicht heraus.
	if event.double_click:
		if not plan:
			_toggle(id)
		return
	# Ob daraus ein Klick oder ein Ziehen wird, zeigt sich in `_input`.
	_held = card
	_held_at = get_local_mouse_position()
	_dragging = false


func _input(event: InputEvent) -> void:
	# Das Mausrad gilt überall über dem Feld, auch über Karten.
	if event is InputEventMouseButton and event.pressed and is_visible_in_tree() \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var mouse := get_local_mouse_position()
		if Rect2(Vector2.ZERO, size).has_point(mouse):
			_zoom_by(ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP, mouse)
			get_viewport().set_input_as_handled()
		return
	# Die mittlere Taste verschiebt das Feld, auch wenn der Zeiger über einer Karte steht.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if not event.pressed:
			_panning = false
		elif is_visible_in_tree() and Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
			_panning = true
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _panning:
		_pan += event.relative
		_fit()
		get_viewport().set_input_as_handled()
		return
	if _held == null or not is_instance_valid(_held) or not is_visible_in_tree():
		return
	# Escape bricht das Ziehen ab: das Abzeichen geht an seinen Platz zurück, nichts ändert sich.
	if _dragging and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var back := _held
		_velocity = Vector2.ZERO
		_tilt = Vector2.ZERO
		_held = null
		_dragging = false
		_over_boss = false
		_link_target = ""
		_link_refusal = ""
		_back.queue_redraw()
		_settle(back)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mouse := get_local_mouse_position()
		if not _dragging and mouse.distance_to(_held_at) > DRAG_START:
			_dragging = true
			_back.queue_redraw()
			_hovered = ""
			_held.z_index = 80
			var tween := _held.create_tween().set_parallel()
			tween.tween_property(_held, "scale", Vector2(1.2, 1.2), 0.12)
			_show_peek()
			tween.tween_property(_held, "rotation", 0.0, 0.12)
			tween.tween_property(_held, "lift", 1.0, 0.12)
		if _dragging:
			var at := (mouse - _canvas.position) / _canvas.scale.x
			_held.position = at - Badge.SIZE / 2.0
			# Wie schnell es geht, bestimmt, wie weit die Karte kippt.
			_velocity = _velocity.lerp(event.velocity, 0.5)
			_last_move = Time.get_ticks_msec()
			if plan:
				_aim_link(at)
			var over := at.length() < BOSS_RADIUS + 10.0 and not plan
			if over != _over_boss:
				_over_boss = over
				_back.queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var card := _held
		var id: String = card.task_id
		var dropped := _dragging and _over_boss
		var clicked := not _dragging
		_velocity = Vector2.ZERO
		_tilt = Vector2.ZERO
		card.set_tilt(Vector2.ZERO)
		_held = null
		_dragging = false
		_over_boss = false
		_back.queue_redraw()
		_settle(card)
		var target := _link_target
		var why := _link_refusal
		_link_target = ""
		_link_refusal = ""
		if plan and not clicked:
			# Auf einem anderen Abzeichen losgelassen: das gezogene blockiert nun
			# jenes – das Ziel wartet auf das gezogene, das einen Ring nach außen rückt.
			if target == "":
				released.emit(id, get_local_mouse_position())
			elif why != "":
				refused.emit(why)
			else:
				link_requested.emit(target, id)
		if dropped:
			_finish(id)
		elif clicked:
			# Erst wenn feststeht, dass kein Doppelklick folgt, geht die Aufgabe auf.
			var ticket := _click_ticket
			await get_tree().create_timer(CLICK_WAIT).timeout
			if ticket == _click_ticket and is_inside_tree():
				task_requested.emit(id)


## Tappen und zurück: in Arbeit nehmen oder wieder bereit.
func _toggle(id: String) -> void:
	var task = _ws.task(id) if _ws != null else null
	if task == null:
		return
	var refusal := Field.untap_refusal(_ws, task) if Field.is_tapped(task) else Field.tap_refusal(_ws, task)
	if refusal != "":
		refused.emit(refusal)
	else:
		change_requested.emit(id, {"status": "ready" if Field.is_tapped(task) else "progress"})


## Der letzte Schlag: die Karte ist erledigt.
func _finish(id: String) -> void:
	var task = _ws.task(id) if _ws != null else null
	if task == null or Model.is_done(task):
		return
	var refusal := Tisch.done_refusal(_ws, task)
	if refusal != "":
		refused.emit(refusal)
	else:
		change_requested.emit(id, {"status": "done"})


func _open_menu(id: String) -> void:
	var task = _ws.task(id)
	if task == null:
		return
	_menu_task = id
	_menu.clear()
	if plan:
		# Auf dem Lageplan wird verteilt, nicht gespielt.
		_menu.add_item("Aus dem Milestone nehmen (zurück in die Reserve)", 6)
	elif Model.is_done(task):
		_menu.add_item("Wieder öffnen", 3)
	else:
		_menu.add_item("Zurück auf bereit" if Field.is_tapped(task) else "Tappen: in Arbeit", 0)
		_menu.add_item("Erledigt", 1)
	_menu.add_separator()
	_menu.add_item("Aufgabe öffnen", 4)
	_menu.add_item("Abhängigkeiten zeigen", 5)
	_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_menu.popup()


func _on_menu(item: int) -> void:
	match item:
		6:
			removal_requested.emit(_menu_task)
		0:
			_toggle(_menu_task)
		1:
			_finish(_menu_task)
		3:
			# Was schon einmal erledigt war, war auch fertig geplant.
			change_requested.emit(_menu_task, {"status": "ready"})
		4:
			task_requested.emit(_menu_task)
		5:
			graph_requested.emit(_menu_task)
