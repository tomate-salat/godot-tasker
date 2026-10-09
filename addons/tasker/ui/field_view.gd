@tool
extends Control
## Das Feld: der aktive Milestone als Kampf. In der Mitte sitzt der große
## Käfer, die Karten liegen in Ringen um ihn – was eine Karte braucht, einen
## Ring weiter außen. Was gilt, steht in `rules/field.gd`.
##
## Ein Klick tappt eine Karte (in Arbeit) oder nimmt das zurück. Wer eine Karte
## auf den großen Käfer zieht, erledigt sie. Ein Doppelklick öffnet sie.
##
## Die Ansicht ändert selbst nichts: sie meldet, was geschehen soll, und zeigt
## den Stand, den sie über `show_field` bekommt.

signal task_requested(task_id: String)
signal graph_requested(task_id: String)
## Der Status einer Karte soll sich ändern.
signal change_requested(task_id: String, changes: Dictionary)
## Ein Zug geht nicht – mit dem Grund.
signal refused(text: String)

const Model := preload("../rules/model.gd")
const Field := preload("../rules/field.gd")
const Tisch := preload("../rules/tisch.gd")
const Workspace := preload("../rules/workspace.gd")
const Palette := preload("palette.gd")
const Card := preload("card.gd")
const Bug := preload("field_bug.gd")
const City := preload("field_city.gd")

## Oben bleibt Platz für die Kopfzeile des Tischs.
const TOP := 62.0
const MARGIN := 22.0
## Die Karten liegen kleiner auf dem Feld; unter dem Zeiger werden sie groß.
const CARD_SCALE := 0.68
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
## So lange wartet ein Klick, ob ein zweiter folgt.
const CLICK_WAIT := 0.25
## Ab so vielen Pixeln wird aus dem Drücken ein Ziehen.
const DRAG_START := 8.0
## Eine getappte Karte liegt quer.
const TAP_TILT := PI / 2.0
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

var _canvas: Control
var _back: Control
## Die Stadt im Hintergrund und ob sie schon einmal gezeigt wurde.
var _city: City
## Ob die Verbindungen den Straßen folgen, und die schon gerechneten Wege.
static var street_ways := true
var _routes := {}
var _town: Control
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
var _held: Card
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
	_town = Control.new()
	_town.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_canvas = Control.new()
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	resized.connect(_fit)


## Zeigt den Stand. `milestone` ist der aktive Milestone oder null.
func show_field(ws: Workspace, milestone: Variant, images: Node) -> void:
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
	_show_city()
	_clear_bridges()
	_tell_city()
	_fit()
	_sync_cards()
	_sync_bugs()
	_back.queue_redraw()


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
func _show_city() -> void:
	_city.build(hash(str(_milestone["id"])), RING * _grow, STEP * _grow, MOAT, _rings, MOAT_AFTER)
	_routes.clear()
	# Die Grenze liegt zwischen diesem Ring und dem nächsten weiter außen.
	var ring_no: int = _field["front"]
	var target := ring_no - 0.5 if ring_no > 0 else -3.0
	if not _city_shown:
		_city_shown = true
		_city.front = target
	elif not is_equal_approx(_city.front, target):
		_city.create_tween().tween_property(_city, "front", target, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


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
	var card := Card.SIZE * CARD_SCALE
	var around := TAU * sqrt((RING.x * RING.x + RING.y * RING.y) / 2.0)
	var grow := maxf(1.0, weight[""] * (card.x + 18.0) / around)
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
	var card := Card.SIZE * CARD_SCALE
	var box := Rect2(-BOSS_RADIUS, -BOSS_RADIUS, BOSS_RADIUS * 2.0, BOSS_RADIUS * 2.0)
	for id in _centers:
		box = box.merge(Rect2(_centers[id] - card / 2.0, card))
	_bounds = box.grow(14.0)


## Auf einer Brücke und im Wasser liegt keine Karte: wer dort landen würde, rückt auf seinem
## Ring zur Seite – so wenig wie nötig, und nicht auf eine andere Karte.
func _clear_bridges() -> void:
	var card := Card.SIZE * CARD_SCALE
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
	_canvas.scale = Vector2(s, s)
	var middle := Vector2(size.x / 2.0, TOP + room.y / 2.0)
	# Verschieben geht nur, so weit die Stadt reicht: der Blick bleibt in ihr.
	# Ist das Fenster größer als sie, bleibt sie in der Mitte.
	var home := _bounds.get_center()
	var look := home - _pan / s
	var free := (City.EXTENT * CITY_EDGE - size / (2.0 * s)).max(Vector2.ZERO)
	look = look.clamp((-free).min(home), free.max(home))
	_pan = (home - look) * s
	_canvas.position = (middle - home * s + _pan).round()
	_town.position = _canvas.position
	_town.scale = _canvas.scale


## Vergrößert oder verkleinert um `factor`; was unter `at` liegt, bleibt dort.
func _zoom_by(factor: float, at: Vector2) -> void:
	var before := _zoom
	_zoom = clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	if is_equal_approx(before, _zoom):
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.double_click:
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
		var card: Card = _cards.get(id)
		if card == null:
			card = Card.new()
			card.sharp = true
			card.scale = Vector2(CARD_SCALE, CARD_SCALE)
			card.position = _centers[id] - Card.SIZE / 2.0
			card.pressed.connect(_on_card)
			card.mouse_entered.connect(_on_hover.bind(id, true))
			card.mouse_exited.connect(_on_hover.bind(id, false))
			_canvas.add_child(card)
			_cards[id] = card
		card.show_task(_ws, task, _images, false)
		card.selected = Field.is_tapped(task)
		# Erledigte Karten sind hier abgedunkelt statt durchscheinend: vor der Stadt bliebe sonst wenig von ihnen.
		card.modulate = Color(0.55, 0.6, 0.57, 1.0) if Model.is_done(task) else Color.WHITE
		if card != _held or not _dragging:
			_settle(card)


## Legt die Karte an ihren Platz – groß, wenn der Zeiger auf ihr ruht.
func _settle(card: Card) -> void:
	var id: String = card.task_id
	if not _centers.has(id):
		return
	var task = _ws.task(id)
	var tapped: bool = task != null and Field.is_tapped(task)
	var big := id == _hovered
	var s := maxf(1.0 / maxf(_canvas.scale.x, 0.01), CARD_SCALE) if big else CARD_SCALE
	card.z_index = 60 if big else 8 if tapped else 5
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", _centers[id] - Card.SIZE / 2.0, MOVE_SECONDS)
	tween.tween_property(card, "scale", Vector2(s, s), MOVE_SECONDS * 0.6)
	tween.tween_property(card, "rotation", TAP_TILT if tapped and not big else 0.0, MOVE_SECONDS)
	# Angehoben ist nur die Karte unter dem Zeiger; eine getappte liegt flach auf dem Tisch.
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


# --------------------------------------------------------------- Käfer

## Wie viel Platz die Karte auf dem Feld einnimmt – quer, wenn sie getappt ist.
func _card_box(id: String) -> Vector2:
	var box := Card.SIZE * CARD_SCALE
	var task = _ws.task(id) if _ws != null else null
	return Vector2(box.y, box.x) if task != null and Field.is_tapped(task) else box


## Wo der `index`-te von `count` Gegnern an einer Karte steht: am rechten
## Rand, untereinander. Wer ihn angreift, steht ihm am linken Rand gegenüber.
func _pest_spot(card_id: String, index: int, count: int) -> Variant:
	if not _centers.has(card_id):
		return null
	var card := _card_box(card_id)
	var apart := minf(34.0, (card.y - 30.0) / maxf(count - 1, 1.0))
	return _centers[card_id] + Vector2(card.x / 2.0 - 2.0, (index - (count - 1) / 2.0) * apart + 8.0)


func _sync_bugs() -> void:
	# Schädlinge
	var wanted := {}
	var at := {}
	for card_id in _field["pests"]:
		var list: Array = _field["pests"][card_id]
		for i in list.size():
			var p: Dictionary = list[i]
			var spot = _pest_spot(card_id, i, list.size())
			if spot == null:
				continue
			var key := "%s|%s" % [card_id, p["blocker_id"]]
			wanted[key] = true
			at[key] = spot
			var bug: Bug = _pests.get(key)
			if bug == null:
				bug = _new_bug(Bug.PEST, spot, 1.25)
				# Käfer sitzen, wie sie wollen; Soldaten schauen über die Karte zum Angreifer.
				bug.rotation = -PI / 2.0 if Bug.style == Bug.SOLDIERS else deg_to_rad(float(hash(key) % 50) - 25.0)
				_pests[key] = bug
				_pop_in(bug)
			elif p["damage"] > bug.hurt + 0.001:
				_bite(key)
			bug.wall = p["wall"]
			bug.hurt = p["damage"]
			bug.set_meta("home", spot)
			bug.create_tween().tween_property(bug, "position", spot, MOVE_SECONDS)
	for key in _pests.keys():
		if not wanted.has(key):
			_fall(_pests[key])
			_pests.erase(key)

	# Marienkäfer
	var keep := {}
	for card_id in _field["fronts"]:
		if not _centers.has(card_id):
			continue
		var fronts: Array = _field["fronts"][card_id]
		if fronts.is_empty():
			# Innerster Ring: der Marienkäfer geht auf den großen Käfer los, von seiner Karte her.
			var toward: Vector2 = _centers[card_id].normalized()
			_want_lady("%s|boss" % card_id, card_id, "", toward * (BOSS_RADIUS + 18.0 if Bug.style == Bug.SOLDIERS else BOSS_RADIUS - 22.0), Vector2.ZERO, keep)
		for f in fronts:
			var pest_key := "%s|%s" % [f["on"], f["blocker_id"]]
			if not at.has(pest_key):
				continue
			var pest_at: Vector2 = at[pest_key]
			# Von der eigenen Karte her an den Schädling heran.
			var across := Vector2(_card_box(f["on"]).x - 4.0, 0.0)
			_want_lady("%s|%s" % [card_id, pest_key], card_id, f["on"], pest_at - across, pest_at, keep)
	for key in _ladies.keys():
		if not keep.has(key):
			_leave(_ladies[key])
			_ladies.erase(key)

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
func _want_lady(key: String, card_id: String, to_id: String, spot: Vector2, target: Vector2, keep: Dictionary) -> void:
	keep[key] = true
	var bug: Bug = _ladies.get(key)
	var fresh := bug == null
	if fresh:
		bug = _new_bug(Bug.LADY, _centers[card_id], 1.1)
		_ladies[key] = bug
	bug.set_meta("home", spot)
	bug.set_meta("card", card_id)
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
		path.append_array(_route(card_id, to_id))
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
		var way := _route(card_id, to_id).duplicate()
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
	_held.scale = squash * CARD_SCALE * 1.25
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
	if Bug.style != Bug.SOLDIERS:
		return
	for key in _ladies:
		var own: Bug = _ladies[key]
		if own.get_meta("busy", false):
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
		if not _centers.has(way["from"]):
			continue
		var from: Vector2 = _centers[way["from"]]
		var to: Vector2 = _centers.get(way["to"], Vector2.ZERO)
		if way["to"] == "":
			to = from.normalized() * BOSS_RADIUS
		var color := Color(Palette.OK, 0.6) if done[way["from"]] else Color(1, 1, 1, 0.26)
		color.a *= _shown(way["from"], way["to"])
		# Gehört der Weg zur Karte unter dem Zeiger, wird er kräftiger und breiter.
		var raised := _focus if way["from"] == _focus_id or way["to"] == _focus_id else 0.0
		color.a = minf(color.a + FOCUS_RAISE * raised, 1.0)
		var width := 2.0 + raised
		var path := _route(way["from"], way["to"] if _centers.has(way["to"]) else "")
		_back.draw_polyline(path, color, width, false)
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
		slot.set_corner_radius_all(int(Card.RADIUS * CARD_SCALE))
		_back.draw_style_box(slot, Rect2(_centers[_held.task_id] - card / 2.0, card))

	# Die Angriffe: von jeder getappten Karte laufen Striche zu dem, was sie
	# angreift – zur Karte mit ihrem Schädling oder zum großen Käfer.
	for card_id in _field["fronts"]:
		if not _centers.has(card_id):
			continue
		for target in _targets_of(card_id):
			_draw_attack(_route(card_id, target), _shown(card_id, target))

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
	var card := Card.SIZE * CARD_SCALE
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
	if event.double_click:
		task_requested.emit(id)
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
	if event is InputEventMouseMotion:
		var mouse := get_local_mouse_position()
		if not _dragging and mouse.distance_to(_held_at) > DRAG_START:
			_dragging = true
			_back.queue_redraw()
			_hovered = ""
			_held.z_index = 80
			var tween := _held.create_tween().set_parallel()
			tween.tween_property(_held, "scale", Vector2(CARD_SCALE, CARD_SCALE) * 1.25, 0.12)
			tween.tween_property(_held, "rotation", 0.0, 0.12)
			tween.tween_property(_held, "lift", 1.0, 0.12)
		if _dragging:
			var at := (mouse - _canvas.position) / _canvas.scale.x
			_held.position = at - Card.SIZE / 2.0
			# Wie schnell es geht, bestimmt, wie weit die Karte kippt.
			_velocity = _velocity.lerp(event.velocity, 0.5)
			_last_move = Time.get_ticks_msec()
			var over := at.length() < BOSS_RADIUS + 10.0
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
		if dropped:
			_finish(id)
		elif clicked:
			# Erst wenn feststeht, dass kein Doppelklick folgt, wird getappt.
			var ticket := _click_ticket
			await get_tree().create_timer(CLICK_WAIT).timeout
			if ticket == _click_ticket and is_inside_tree():
				_toggle(id)


## Tappen und zurück: in Arbeit nehmen oder wieder offen.
func _toggle(id: String) -> void:
	var task = _ws.task(id) if _ws != null else null
	if task == null:
		return
	var refusal := Field.untap_refusal(_ws, task) if Field.is_tapped(task) else Field.tap_refusal(_ws, task)
	if refusal != "":
		refused.emit(refusal)
	else:
		change_requested.emit(id, {"status": "open" if Field.is_tapped(task) else "progress"})


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
	if Model.is_done(task):
		_menu.add_item("Wieder öffnen", 3)
	else:
		_menu.add_item("Zurück auf offen" if Field.is_tapped(task) else "Tappen: in Arbeit", 0)
		_menu.add_item("Erledigt", 1)
	_menu.add_separator()
	_menu.add_item("Aufgabe öffnen", 4)
	_menu.add_item("Abhängigkeiten zeigen", 5)
	_menu.position = Vector2i(DisplayServer.mouse_get_position())
	_menu.popup()


func _on_menu(item: int) -> void:
	match item:
		0:
			_toggle(_menu_task)
		1:
			_finish(_menu_task)
		3:
			change_requested.emit(_menu_task, {"status": "open"})
		4:
			task_requested.emit(_menu_task)
		5:
			graph_requested.emit(_menu_task)
