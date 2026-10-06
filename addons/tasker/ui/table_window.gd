@tool
extends Window
## Der Tisch als eigenes Fenster des Editors – vorerst ein Prototyp.
##
## Er klärt, ob Karten in einem Editor-Fenster flüssig laufen: Austeilen,
## Auffächern der Hand, Anheben unter dem Zeiger. Die Zonen sind schon die des
## Tischs (Hand unten, Gespieltes in der Mitte, Erledigt rechts, Gesperrt
## links), gezogen und geändert wird hier noch nichts.

const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Demo := preload("demo.gd")
const Tisch := preload("../rules/tisch.gd")
const Workspace := preload("../rules/workspace.gd")
const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")

## Der Datenbestand (`core/store.gd`) und der Bild-Zwischenspeicher – ohne
## sie oder ohne Verbindung liegen ausgedachte Karten auf dem Tisch.
var store: Store
var images: Images

var _felt: ColorRect
var _cards: Control
var _head: Label
var _fps: Label
var _zones := {}
## Karte → wo sie ruht: `{ position, rotation, z }`.
var _rest := {}
var _hover: Control


func _init() -> void:
	title = "Tasker – Tisch (Prototyp)"
	size = Vector2i(1180, 760)
	min_size = Vector2i(760, 560)
	wrap_controls = false
	close_requested.connect(hide)
	size_changed.connect(_place_all)

	_felt = ColorRect.new()
	_felt.color = Palette.FELT
	_felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_felt)

	_cards = Control.new()
	_cards.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_felt.add_child(_cards)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 10
	bar.add_theme_constant_override("separation", 12)
	_felt.add_child(bar)

	_head = Label.new()
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.add_theme_font_override("font", Palette.title_font())
	_head.add_theme_font_size_override("font_size", 18)
	bar.add_child(_head)

	_fps = Label.new()
	_fps.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	bar.add_child(_fps)

	var deal := Button.new()
	deal.text = "Neu austeilen"
	deal.pressed.connect(deal_cards)
	bar.add_child(deal)


func _ready() -> void:
	if store != null:
		store.changed.connect(deal_cards)
	deal_cards()


func _process(_delta: float) -> void:
	if visible:
		_fps.text = "%d Bilder/s" % Engine.get_frames_per_second()


## Räumt ab und teilt den aktiven Milestone neu aus.
func deal_cards() -> void:
	for c in _cards.get_children():
		c.queue_free()
	_rest.clear()
	_hover = null

	var ws: Workspace
	var project := ""
	var demo := store == null or store.state != "ready"
	if demo:
		ws = Workspace.new(Demo.data())
		project = Demo.PROJECT
	else:
		ws = store.ws
		project = store.project_id

	var m = Tisch.active_milestone(ws, project)
	if m == null:
		_head.text = "Kein aktiver Milestone – aktiv ist, was in Tasker auf „In Progress“ steht."
		_zones = {}
		return
	_head.text = "%s%s" % [m["title"], "   (Beispieldaten, keine Verbindung)" if demo else ""]

	var layout := Tisch.layout(ws, m)
	_zones = {"locked": [], "open": [], "play": [], "pile": []}
	for zone in _zones:
		var list: Array = layout[zone]
		# Der Erledigt-Stapel zeigt nur seine obersten Karten.
		if zone == "pile":
			list = list.slice(0, 3)
			list.reverse()
		for task in list:
			var card := Card.new()
			_cards.add_child(card)
			card.show_task(ws, task, null if demo else images, zone == "play")
			card.mouse_entered.connect(_lift.bind(card))
			card.mouse_exited.connect(_drop.bind(card))
			_zones[zone].append(card)

	# Alle Karten starten als Stapel links oben und fliegen an ihren Platz.
	for zone in _zones:
		for card in _zones[zone]:
			card.position = Vector2(32, 64)
			card.rotation = 0.0
			card.modulate.a = 0.0
	_place_all(true)


## Rechnet die Plätze neu aus und lässt die Karten hingleiten.
func _place_all(dealing := false) -> void:
	if _zones.is_empty():
		return
	var area := Vector2(size)
	var card := Card.SIZE
	var n := 0

	var open: Array = _zones["open"]
	# Die Hand: unten aufgefächert, die Mitte am höchsten.
	var step := minf(card.x * 0.78, (area.x - 160.0 - card.x) / maxf(open.size() - 1, 1))
	for i in open.size():
		var t := i - (open.size() - 1) / 2.0
		var spot := Vector2(area.x / 2.0 + t * step - card.x / 2.0, area.y - card.y - 40.0 + t * t * 3.0)
		_move(open[i], spot, deg_to_rad(t * 3.5), 10 + i, dealing, n)
		n += 1

	var play: Array = _zones["play"]
	for i in play.size():
		var t := i - (play.size() - 1) / 2.0
		var spot := Vector2(area.x / 2.0 + t * (card.x + 18.0) - card.x / 2.0, area.y * 0.36 - card.y / 2.0)
		_move(play[i], spot, 0.0, 5 + i, dealing, n)
		n += 1

	var locked: Array = _zones["locked"]
	for i in locked.size():
		_move(locked[i], Vector2(36.0 + i * 22.0, 96.0 + i * 14.0), deg_to_rad(-3.0 + i * 3.0), 1 + i, dealing, n)
		n += 1

	var pile: Array = _zones["pile"]
	for i in pile.size():
		var tilt: float = [-6.0, 4.0, -1.5][i % 3]
		_move(pile[i], Vector2(area.x - card.x - 48.0, area.y * 0.36 - card.y / 2.0), deg_to_rad(tilt), 1 + i, dealing, n)
		n += 1


func _move(card: Control, spot: Vector2, angle: float, z: int, dealing: bool, index: int) -> void:
	_rest[card] = {"position": spot, "rotation": angle, "z": z}
	card.z_index = z
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var delay := index * 0.045 if dealing else 0.0
	var time := 0.42 if dealing else 0.22
	tween.tween_property(card, "position", spot, time).set_delay(delay)
	tween.tween_property(card, "rotation", angle, time).set_delay(delay)
	if dealing:
		# Auf dem Stapel liegen die Karten deckend – durchscheinend übereinander wird es Brei.
		var alpha := 1.0
		tween.tween_property(card, "modulate:a", alpha, 0.15).set_delay(delay)


## Die Karte unter dem Zeiger hebt sich aus der Hand.
func _lift(card: Control) -> void:
	if not _rest.has(card) or not _zones["open"].has(card):
		return
	_hover = card
	card.z_index = 100
	var rest: Dictionary = _rest[card]
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", rest["position"] + Vector2(0, -34), 0.14)
	tween.tween_property(card, "rotation", 0.0, 0.14)
	tween.tween_property(card, "scale", Vector2(1.12, 1.12), 0.14)


func _drop(card: Control) -> void:
	if not _rest.has(card) or not _zones["open"].has(card):
		return
	if _hover == card:
		_hover = null
	var rest: Dictionary = _rest[card]
	card.z_index = rest["z"]
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", rest["position"], 0.18)
	tween.tween_property(card, "rotation", rest["rotation"], 0.18)
	tween.tween_property(card, "scale", Vector2.ONE, 0.18)
