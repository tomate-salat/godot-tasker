@tool
extends Window
## Der Tisch: der aktive Milestone als Kartenspiel, in einem eigenen Fenster
## des Editors.
##
## Die Zonen: unten die Hand (offene Karten, die gezogen wurden), links unten
## der Nachziehstapel (der Rest der offenen), in der Mitte das Gespielte („In
## Progress“), links oben das Gesperrte, rechts der Erledigt-Stapel. Ein
## Stapel – eine Aufgabe mit Unteraufgaben – fächert sich in der Schublade
## zwischen Tisch und Hand auf.
##
## Ziehen zwischen den Zonen setzt den Status in Tasker. Hand, Nachziehstapel
## und Schublade sind lokaler Zustand (`rules/hand.gd`, `core/memory.gd`).
## Welche Karte wohin gehört, steht in `rules/tisch.gd`.

## Die Aufgabe soll in ihrem Fenster gezeigt werden.
signal task_requested(task_id: String)

const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Demo := preload("demo.gd")
const Model := preload("../rules/model.gd")
const Tisch := preload("../rules/tisch.gd")
const Hand := preload("../rules/hand.gd")
const Progress := preload("../rules/progress.gd")
const Workspace := preload("../rules/workspace.gd")
const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Memory := preload("../core/memory.gd")

const HEADER := 60.0
const MARGIN := 28.0
## Plätze im Spiel, die leer angezeigt werden – ein Richtwert, begrenzt wird nicht.
const SLOTS := 7
## Ab so vielen Pixeln wird aus einem Klick ein Ziehen.
const DRAG_START := 6.0
const Z_DRAG := 500
const Z_BROWSE := 20
const Z_DIM := 8

## Der Datenbestand und der Bild-Zwischenspeicher – ohne sie oder ohne
## Verbindung liegen ausgedachte Karten auf dem Tisch.
var store: Store
var images: Images
var memory := Memory.new()
## Wie viele Karten die Hand höchstens hält (Addon-Einstellung).
var hand_size := 7

var _demo_data := {}
var _ws: Workspace
var _project := ""
var _milestone: Variant
var _layout := {"locked": [], "open": [], "play": [], "pile": []}
var _state := {"hand": [], "buried": [], "open": []}

## Die Karten auf dem Tisch: ID → Karte, dazu ihre Zone und ihr Ruheplatz.
var _cards := {}
var _zone := {}
var _rest := {}
var _tweens := {}
## Karten, deren Änderung noch beim Server ist – sie bleiben liegen, wo sie sind.
var _busy := {}
var _batch := false

var _pressed: Control
var _press_at := Vector2.ZERO
var _grab := Vector2.ZERO
var _dragging := false
var _hot := ""
## Der Nachziehstapel ist aufgedeckt.
var _browse := false
## Die Stapelkarte, die gegen eine Handkarte getauscht werden soll.
var _swap := ""

var _board: Control
var _layer: Control
var _dim: ColorRect
var _title: Button
var _progress: ProgressBar
var _count: Label
var _labels := {}
var _deck_area: Button
var _browse_button: Button
var _toast: Label
var _toast_tween: Tween


func _init() -> void:
	title = "Tasker – Tisch"
	size = Vector2i(1440, 900)
	min_size = Vector2i(1100, 800)
	wrap_controls = false
	close_requested.connect(hide)
	size_changed.connect(_place)
	_build()


func _ready() -> void:
	if store != null:
		store.changed.connect(_sync)
		store.state_changed.connect(_sync)
	memory.changed.connect(_sync)
	_sync()


# ------------------------------------------------------------- Aufbau

func _build() -> void:
	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.draw.connect(_draw_board)
	add_child(_board)

	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)

	# Deckt Tisch und Schublade ab, solange der Nachziehstapel aufgedeckt ist.
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.07, 0.06, 0.86)
	_dim.z_index = Z_DIM
	_dim.visible = false
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_set_browse(false))
	_layer.add_child(_dim)

	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = MARGIN
	bar.offset_right = -MARGIN
	bar.offset_top = 14
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)

	# Der Milestone selbst: ein Klick öffnet sein Fenster.
	_title = Button.new()
	_title.flat = true
	_title.focus_mode = Control.FOCUS_NONE
	_title.pressed.connect(func() -> void:
		if _milestone != null and store != null and store.state == "ready":
			task_requested.emit(_milestone["id"]))
	_title.add_theme_font_override("font", Palette.title_font())
	_title.add_theme_font_size_override("font_size", 18)
	bar.add_child(_title)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(220, 8)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_progress)
	_count = Label.new()
	_count.tooltip_text = "Erledigte von allen Aufgaben"
	bar.add_child(_count)

	for key in ["locked", "play", "pile", "deck", "hand", "drawer", "empty"]:
		var l := Label.new()
		l.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_board.add_child(l)
		_labels[key] = l
	_labels["empty"].autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_labels["empty"].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_deck_area = Button.new()
	_deck_area.flat = true
	_deck_area.focus_mode = Control.FOCUS_NONE
	_deck_area.tooltip_text = "Eine Karte ziehen"
	_deck_area.pressed.connect(_draw_from_deck)
	_board.add_child(_deck_area)

	_browse_button = Button.new()
	_browse_button.text = "Ansehen"
	_browse_button.tooltip_text = "Den Nachziehstapel aufdecken und gezielt ziehen oder tauschen"
	_browse_button.pressed.connect(func() -> void: _set_browse(not _browse))
	add_child(_browse_button)

	_toast = Label.new()
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_color_override("font_color", Palette.P2)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	_toast.add_theme_font_size_override("font_size", 16)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.z_index = 600
	_toast.modulate.a = 0.0
	_layer.add_child(_toast)


# --------------------------------------------------------------- Maße

## Wo die Zonen liegen, abhängig von der Fenstergröße.
func _geometry() -> Dictionary:
	var w := float(size.x)
	var h := float(size.y)
	var c := Card.SIZE
	var side := c.x + MARGIN * 2.0 + 12.0
	var play := Rect2(side, HEADER + 30.0, w - side * 2.0, c.y + 24.0)
	var drawer := Rect2(side, play.end.y + 34.0, w - side * 2.0, c.y + 24.0)
	var hand_top := h - c.y - 44.0
	return {
		"card": c,
		"play": play,
		"drawer": drawer,
		"hand": Rect2(side, hand_top - 26.0, w - side * 2.0, h - hand_top + 26.0),
		"locked": Rect2(MARGIN, HEADER + 42.0, c.x + 24.0, c.y + 110.0),
		"deck": Rect2(MARGIN + 4.0, h - c.y - 64.0, c.x + 8.0, c.y + 8.0),
		"pile": Rect2(w - MARGIN - c.x - 24.0, HEADER + 30.0, c.x + 24.0, c.y + 24.0),
	}


# ----------------------------------------------------------- Abgleich

## Bringt den Tisch auf den Stand der Daten: welche Karte in welcher Zone liegt.
func _sync() -> void:
	if _batch or not is_inside_tree():
		return
	var demo := store == null or store.state != "ready"
	if demo:
		if _demo_data.is_empty():
			_demo_data = Demo.data()
			_ws = Workspace.new(_demo_data)
		_project = Demo.PROJECT
	else:
		_ws = store.ws
		_project = store.project_id

	_milestone = Tisch.active_milestone(_ws, _project)
	if _milestone == null:
		_layout = {"locked": [], "open": [], "play": [], "pile": []}
		_state = {"hand": [], "buried": [], "open": []}
		_title.text = "Kein aktiver Milestone"
		_progress.visible = false
		_count.text = ""
		_show_cards({})
		_place()
		return

	_layout = Tisch.layout(_ws, _milestone)
	var key := Hand.key(_milestone["id"])
	var saved = memory.read(key, null)
	_state = Hand.sanitize(saved, _layout["open"], _ws)
	if saved != null and saved != _state:
		_save_state()

	var stats := Progress.milestone_stats(_ws, _milestone)
	_title.text = "◆ %s%s" % [_milestone["title"], "   (Beispieldaten, keine Verbindung)" if demo else ""]
	_progress.visible = true
	_progress.value = Progress.milestone_progress_pct(_ws, _milestone)
	_count.text = "%d/%d" % [stats["done"], stats["total"]]

	# Wer liegt wo – jede Karte liegt genau einmal.
	var wanted := {}
	for t in _layout["play"]:
		wanted[t["id"]] = "play"
	for id in _state["hand"]:
		wanted[id] = "hand"
	for t in _layout["locked"].slice(0, 6):
		wanted[t["id"]] = "locked"
	# Vom Erledigt-Stapel sind nur die obersten Karten zu sehen.
	for t in _layout["pile"].slice(0, 3):
		wanted[t["id"]] = "pile"
	for t in _drawer_tasks():
		if not wanted.has(t["id"]):
			wanted[t["id"]] = "drawer"
	if _browse:
		for t in _deck():
			wanted[t["id"]] = "deck"
	_show_cards(wanted)
	_place()


func _show_cards(wanted: Dictionary) -> void:
	var g := _geometry()
	for id in _cards.keys():
		# Was noch beim Server ist, bleibt liegen, auch wenn der Zwischenstand es nicht mehr zeigt.
		if wanted.has(id) or _busy.has(id):
			continue
		var gone: Control = _cards[id]
		_cards.erase(id)
		_zone.erase(id)
		_rest.erase(id)
		_tweens.erase(id)
		if gone == _pressed:
			_pressed = null
			_dragging = false
		gone.queue_free()

	for id in wanted:
		var task = _ws.task(id)
		if task == null:
			continue
		var card: Control = _cards.get(id)
		if card == null:
			card = Card.new()
			_layer.add_child(card)
			# Neue Karten kommen vom Nachziehstapel.
			card.position = g["deck"].position
			card.pressed.connect(_on_card_pressed)
			card.mouse_entered.connect(_on_hover.bind(card, true))
			card.mouse_exited.connect(_on_hover.bind(card, false))
			_cards[id] = card
		if not _busy.has(id):
			_zone[id] = wanted[id]
		# Im Spiel und in der Schublade steht über einer Unteraufgabe, wozu sie gehört.
		card.show_task(_ws, task, images if store != null else null, _zone.get(id) == "play")
		# Auf dem Stapel liegen die Karten deckend – durchscheinend übereinander wird es Brei.
		card.modulate.a = 1.0
		card.selected = id == _swap or (_zone.get(id) == "hand" and _state["open"].has(id))


## Die Unteraufgaben des zuletzt aufgefächerten Stapels, ohne Gespieltes und Erledigtes.
func _drawer_tasks() -> Array:
	var path: Array = _state["open"]
	if path.is_empty():
		return []
	return _ws.kids(path[path.size() - 1]).filter(func(k: Dictionary) -> bool:
		return not Model.is_done(k) and not (k["status"] == "progress" and _ws.kids(k["id"]).is_empty()))


func _deck() -> Array:
	return Hand.deck_of(_layout.get("open", []), _state["hand"])


func _ids_in(zone: String) -> Array:
	match zone:
		"hand":
			return _state["hand"].filter(func(id: String) -> bool: return _cards.has(id))
		"play":
			return _layout["play"].map(func(t: Dictionary) -> String: return t["id"]).filter(func(id: String) -> bool: return _zone.get(id) == "play")
		"locked":
			return _layout["locked"].slice(0, 6).map(func(t: Dictionary) -> String: return t["id"])
		"pile":
			var top: Array = _layout["pile"].slice(0, 3).map(func(t: Dictionary) -> String: return t["id"])
			top.reverse()
			return top
		"drawer":
			return _drawer_tasks().map(func(t: Dictionary) -> String: return t["id"]).filter(func(id: String) -> bool: return _zone.get(id) == "drawer")
		"deck":
			return _deck().map(func(t: Dictionary) -> String: return t["id"]) if _browse else []
	return []


# ------------------------------------------------------------- Plätze

## Rechnet die Ruheplätze aus und lässt die Karten hingleiten.
func _place() -> void:
	if not is_inside_tree():
		return
	var g := _geometry()
	var c: Vector2 = g["card"]

	# Die Hand: unten aufgefächert, die Mitte am höchsten.
	var hand := _ids_in("hand")
	var hand_rect: Rect2 = g["hand"]
	var step := minf(c.x * 0.86, (hand_rect.size.x - c.x) / maxf(hand.size() - 1, 1))
	for i in hand.size():
		var t := i - (hand.size() - 1) / 2.0
		var spot := Vector2(hand_rect.get_center().x + t * step - c.x / 2.0, size.y - c.y - 44.0 + t * t * 3.0)
		_rest_at(hand[i], spot, deg_to_rad(t * 3.0), 10 + i)

	var play := _ids_in("play")
	for i in play.size():
		_rest_at(play[i], _play_spot(g, i, play.size()), 0.0, 3)

	var locked := _ids_in("locked")
	for i in locked.size():
		_rest_at(locked[i], g["locked"].position + Vector2(8.0 + (i % 2) * 6.0, i * 20.0), deg_to_rad(-2.0 + (i % 3) * 2.0), 1)

	var pile := _ids_in("pile")
	for i in pile.size():
		var tilt: float = [-6.0, 4.0, -1.5][(pile.size() - 1 - i) % 3]
		_rest_at(pile[i], g["pile"].position + Vector2(12, 12), deg_to_rad(tilt), 1 + i)

	var drawer := _ids_in("drawer")
	var drawer_rect: Rect2 = g["drawer"]
	var drawer_step := minf(c.x + 14.0, (drawer_rect.size.x - c.x - 32.0) / maxf(drawer.size() - 1, 1))
	for i in drawer.size():
		_rest_at(drawer[i], drawer_rect.position + Vector2(16.0 + i * drawer_step, 12.0), 0.0, 3)

	# Der aufgedeckte Nachziehstapel: ein Raster über Tisch und Schublade.
	var deck := _ids_in("deck")
	var area := Rect2(g["play"].position, Vector2(g["play"].size.x, g["drawer"].end.y - g["play"].position.y))
	var cols := maxi(int((area.size.x - 16.0) / (c.x + 12.0)), 1)
	var rows := ceili(float(deck.size()) / cols)
	var row_step := minf(c.y + 12.0, (area.size.y - c.y - 16.0) / maxf(rows - 1, 1))
	for i in deck.size():
		_rest_at(deck[i], area.position + Vector2(8.0 + (i % cols) * (c.x + 12.0), 8.0 + (i / cols) * row_step), 0.0, Z_BROWSE + i)

	_dim.visible = _browse
	_dim.position = Vector2.ZERO
	_dim.size = Vector2(size.x, g["hand"].position.y)
	_place_labels(g)
	_board.queue_redraw()


func _play_spot(g: Dictionary, index: int, count: int) -> Vector2:
	var rect: Rect2 = g["play"]
	var c: Vector2 = g["card"]
	var slots := maxi(count, SLOTS)
	var step := minf(c.x + 16.0, (rect.size.x - c.x) / maxf(slots - 1, 1))
	var left := rect.get_center().x - (step * (slots - 1) + c.x) / 2.0
	return Vector2(left + index * step, rect.position.y + 12.0)


func _rest_at(id: String, spot: Vector2, angle: float, z: int) -> void:
	_rest[id] = {"position": spot, "rotation": angle, "z": z}
	var card: Control = _cards.get(id)
	if card == null or _busy.has(id) or (card == _pressed and _dragging):
		return
	card.z_index = z
	if card.position.distance_to(spot) < 0.5 and is_equal_approx(card.rotation, angle) and card.scale == Vector2.ONE:
		return
	_glide(id, spot, angle, Vector2.ONE, 0.3, Tween.TRANS_BACK)


func _glide(id: String, spot: Vector2, angle: float, to_scale: Vector2, time: float, trans := Tween.TRANS_CUBIC) -> void:
	var card: Control = _cards.get(id)
	if card == null:
		return
	if _tweens.get(id) != null and _tweens[id].is_valid():
		_tweens[id].kill()
	var tween := card.create_tween().set_parallel().set_trans(trans).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", spot, time)
	tween.tween_property(card, "rotation", angle, time)
	tween.tween_property(card, "scale", to_scale, time)
	_tweens[id] = tween


func _place_labels(g: Dictionary) -> void:
	var deck_count := _deck().size()
	_label("locked", g["locked"].position + Vector2(0, -26), "Gesperrt  %d" % _layout["locked"].size() if _layout["locked"].size() else "")
	_label("play", g["play"].position + Vector2(0, -26), "Im Spiel  %d" % _layout["play"].size())
	_label("pile", g["pile"].position + Vector2(0, -26), "Erledigt  %d" % _layout["pile"].size())
	_label("deck", g["deck"].position + Vector2(0, -28), "Nachziehstapel  %d" % deck_count)
	_label("hand", g["hand"].position + Vector2(0, 0), "Hand  %d/%d" % [_state["hand"].size(), hand_size])

	var path: Array = _state["open"]
	var crumbs := path.map(func(id: String) -> String:
		var t = _ws.task(id)
		return t["title"] if t != null and t.get("title") else "Ohne Titel")
	_label("drawer", g["drawer"].position + Vector2(0, -26), "Aufgefächert:  %s" % " › ".join(PackedStringArray(crumbs)) if path.size() else "")

	var hint := ""
	if _milestone == null:
		hint = "Aktiv ist, was in Tasker auf „In Progress“ steht."
	elif _state["hand"].is_empty() and _layout["play"].is_empty() and not _browse:
		hint = "Die Hand ist leer – ein Klick auf den Nachziehstapel zieht eine Karte." if deck_count > 0 else "Keine offenen Karten in diesem Milestone."
	_labels["empty"].size = Vector2(g["play"].size.x, 60)
	_label("empty", g["drawer"].position + Vector2(0, 40), hint)

	_deck_area.position = g["deck"].position
	_deck_area.size = g["deck"].size
	_deck_area.visible = _milestone != null
	_browse_button.visible = _milestone != null and deck_count > 0
	_browse_button.text = "Zudecken" if _browse else "Ansehen"
	_browse_button.position = g["deck"].position + Vector2(g["deck"].size.x + 10.0, g["deck"].size.y - 36.0)
	_toast.size = Vector2(size.x, 28)
	_toast.position = Vector2(0, g["hand"].position.y - 6.0)


func _label(key: String, at: Vector2, text: String) -> void:
	_labels[key].position = at
	_labels[key].text = text


# ---------------------------------------------------------------- Brett

## Der Filz und was darauf gemalt ist: Plätze, Stapel, Schublade.
func _draw_board() -> void:
	var g := _geometry()
	var c: Vector2 = g["card"]
	_board.draw_rect(Rect2(Vector2.ZERO, Vector2(size)), Palette.FELT)
	if _milestone == null:
		return

	var slot := StyleBoxFlat.new()
	slot.bg_color = Color(0, 0, 0, 0.10)
	slot.border_color = Color(1, 1, 1, 0.14)
	slot.set_border_width_all(1)
	slot.set_corner_radius_all(Card.RADIUS)
	var count: int = maxi(_layout["play"].size(), SLOTS)
	for i in count:
		_board.draw_style_box(slot, Rect2(_play_spot(g, i, count), c))

	# Der Erledigt-Stapel hat auch leer einen Platz.
	_board.draw_style_box(slot, Rect2(g["pile"].position + Vector2(12, 12), c))

	# Der Nachziehstapel: verdeckte Karten, je mehr, desto höher.
	var deck := _deck().size()
	var back := StyleBoxFlat.new()
	back.bg_color = Palette.SURFACE.lerp(Palette.ACCENT, 0.22)
	back.border_color = Palette.ACCENT.darkened(0.25)
	back.set_border_width_all(2)
	back.set_corner_radius_all(Card.RADIUS)
	if deck == 0:
		_board.draw_style_box(slot, Rect2(g["deck"].position, c))
	for i in mini(deck, 4):
		var at: Vector2 = g["deck"].position + Vector2(6.0 - i * 2.0, 6.0 - i * 2.0)
		_board.draw_style_box(back, Rect2(at, c))
		if i == mini(deck, 4) - 1:
			var inner := StyleBoxFlat.new()
			inner.bg_color = Color(0, 0, 0, 0)
			inner.border_color = Color(Palette.ACCENT, 0.55)
			inner.set_border_width_all(1)
			inner.set_corner_radius_all(7)
			_board.draw_style_box(inner, Rect2(at + Vector2(10, 10), c - Vector2(20, 20)))

	if _state["open"].size() > 0:
		var tray := StyleBoxFlat.new()
		tray.bg_color = Color(0, 0, 0, 0.16)
		tray.border_color = Color(Palette.ACCENT, 0.5)
		tray.set_border_width_all(1)
		tray.set_corner_radius_all(12)
		_board.draw_style_box(tray, g["drawer"])

	# Wohin die gezogene Karte gerade fallen würde.
	if _hot != "" and g.has(_hot):
		var glow := StyleBoxFlat.new()
		glow.bg_color = Color(Palette.ACCENT, 0.08)
		glow.border_color = Palette.ACCENT
		glow.set_border_width_all(2)
		glow.set_corner_radius_all(12)
		_board.draw_style_box(glow, g[_hot])


# --------------------------------------------------------------- Maus

func _on_card_pressed(card: Control, event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.double_click:
		_pressed = null
		task_requested.emit(card.task_id)
		return
	_pressed = card
	_dragging = false
	_press_at = _layer.get_local_mouse_position()
	_grab = card.position - _press_at


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and (_browse or _state["open"].size() > 0):
		set_input_as_handled()
		if _browse:
			_set_browse(false)
		else:
			_open_stack([])
		return
	if _pressed == null or not is_instance_valid(_pressed):
		_pressed = null
		return

	var mouse := _layer.get_local_mouse_position()
	if event is InputEventMouseMotion:
		if not _dragging and mouse.distance_to(_press_at) > DRAG_START and _can_drag(_pressed.task_id):
			_dragging = true
			var id: String = _pressed.task_id
			if _tweens.get(id) != null and _tweens[id].is_valid():
				_tweens[id].kill()
			_pressed.z_index = Z_DRAG
			_pressed.scale = Vector2(1.08, 1.08)
		if _dragging:
			_pressed.position = mouse + _grab
			# Die Karte kippt in die Bewegungsrichtung.
			_pressed.rotation = lerpf(_pressed.rotation, clampf(event.relative.x * 0.02, -0.3, 0.3), 0.3)
			var hot := _zone_at(mouse)
			if hot != _hot:
				_hot = hot
				_board.queue_redraw()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var card := _pressed
		var was_dragging := _dragging
		_pressed = null
		_dragging = false
		_hot = ""
		_board.queue_redraw()
		if was_dragging:
			_drop(card.task_id, mouse)
		else:
			_click(card.task_id)


func _can_drag(id: String) -> bool:
	match _zone.get(id, ""):
		"hand", "play", "drawer":
			return not _busy.has(id)
		"pile":
			# Nur die oberste Karte lässt sich wieder herausziehen.
			return not _busy.has(id) and _layout["pile"].size() > 0 and _layout["pile"][0]["id"] == id
	return false


## Die Zone unter dem Zeiger, in die sich etwas ablegen lässt.
func _zone_at(at: Vector2) -> String:
	var g := _geometry()
	for zone in ["pile", "deck", "play", "hand"]:
		if g[zone].grow(10.0).has_point(at):
			return zone
	# Die Schublade gehört beim Ablegen zur Hand: zurück zu den offenen Karten.
	if g["drawer"].has_point(at):
		return "hand"
	return ""


func _on_hover(card: Control, inside: bool) -> void:
	var id: String = card.task_id
	if _zone.get(id) != "hand" or _busy.has(id) or _pressed != null or not _rest.has(id):
		return
	var rest: Dictionary = _rest[id]
	if inside:
		card.z_index = 100
		_glide(id, rest["position"] + Vector2(0, -30), 0.0, Vector2(1.1, 1.1), 0.14)
	else:
		card.z_index = rest["z"]
		_glide(id, rest["position"], rest["rotation"], Vector2.ONE, 0.18)


# --------------------------------------------------------------- Züge

func _click(id: String) -> void:
	match _zone.get(id, ""):
		"deck":
			_take_from_deck(id)
		"hand":
			if _swap != "":
				_swap_with(id)
			elif _ws.kids(id).size() > 0:
				_open_stack([] if _state["open"] == [id] else [id])
		"drawer":
			if _ws.kids(id).size() > 0:
				var path: Array = _state["open"].duplicate()
				path.append(id)
				_open_stack(path)


func _drop(id: String, at: Vector2) -> void:
	var from: String = _zone.get(id, "")
	var to := _zone_at(at)
	var task = _ws.task(id)
	if task == null or to == "" or (to == from and to != "play" and to != "hand"):
		_place()
		return

	match to:
		"play":
			var refusal := "" if from == "play" else Tisch.play_refusal(_ws, task)
			if refusal != "":
				_refuse(refusal)
			else:
				await _play_at(id, _play_index(at, id))
		"pile":
			var refusal := Tisch.done_refusal(_ws, task)
			if refusal != "":
				_refuse(refusal)
			elif from != "pile":
				await _change(id, {"status": "done"})
		"deck":
			if from == "hand":
				_state["hand"].erase(id)
				_state["buried"].append(id)
				if _state["open"].has(id):
					_state["open"] = []
				_save_state()
			else:
				_refuse("Nur Karten von der Hand gehen zurück unter den Stapel")
		"hand":
			if from == "hand":
				_move_in_hand(id, at)
			elif from == "play" or from == "pile":
				# Erst der Status, dann die Hand: vorher ist die Karte noch nicht offen.
				if await _change(id, {"status": "open"}) and not task.get("parentId"):
					if not _state["hand"].has(id):
						_state["hand"].append(id)
					_state["buried"].erase(id)
					_save_state()
	_sync()


func _play_index(at: Vector2, dragged: String) -> int:
	var g := _geometry()
	var others := _ids_in("play").filter(func(id: String) -> bool: return id != dragged)
	for i in others.size():
		if at.x < _play_spot(g, i, others.size() + 1).x + Card.SIZE.x / 2.0:
			return i
	return others.size()


## Legt die Karte an diesen Platz im Spiel. Die Reihe wird durchgezählt; wer
## dabei erst ins Spiel kommt, bekommt den Status gleich mit.
func _play_at(id: String, index: int) -> void:
	var row: Array = _layout["play"].map(func(t: Dictionary) -> String: return t["id"]).filter(func(x: String) -> bool: return x != id)
	row.insert(mini(index, row.size()), id)
	_batch = true
	for i in row.size():
		var t = _ws.task(row[i])
		if t == null:
			continue
		var changes := {}
		if t["status"] != "progress":
			changes["status"] = "progress"
		if int(t.get("playOrder", 0)) != i + 1:
			changes["playOrder"] = i + 1
		if not changes.is_empty():
			if not await _change(row[i], changes):
				break
	_batch = false
	_state["hand"].erase(id)
	_save_state()


func _move_in_hand(id: String, at: Vector2) -> void:
	var hand: Array = _state["hand"]
	hand.erase(id)
	var index := hand.size()
	for i in hand.size():
		var rest = _rest.get(hand[i])
		if rest != null and at.x < rest["position"].x + Card.SIZE.x / 2.0:
			index = i
			break
	hand.insert(index, id)
	_save_state()


## Klick auf den Nachziehstapel: eine Karte kommt auf die Hand.
func _draw_from_deck() -> void:
	if _milestone == null:
		return
	if _state["hand"].size() >= hand_size:
		_refuse("Die Hand ist voll – spiel eine Karte aus oder leg eine zurück")
		return
	var card = Hand.pick(_deck(), _state["buried"], randf())
	if card == null:
		_refuse("Der Nachziehstapel ist leer")
		return
	_state["hand"].append(card["id"])
	_state["buried"].erase(card["id"])
	_save_state()


## Im aufgedeckten Stapel: die Karte gezielt nehmen – bei voller Hand zum Tausch vormerken.
func _take_from_deck(id: String) -> void:
	if _state["hand"].size() < hand_size:
		_state["hand"].append(id)
		_state["buried"].erase(id)
		_swap = ""
		_save_state()
		return
	_swap = "" if _swap == id else id
	if _swap != "":
		_say("Die Hand ist voll – klick die Handkarte an, die dafür zurückgeht")
	_sync()


func _swap_with(hand_id: String) -> void:
	var at: int = _state["hand"].find(hand_id)
	if at < 0 or _swap == "":
		return
	_state["hand"][at] = _swap
	_state["buried"].erase(_swap)
	_state["buried"].append(hand_id)
	if _state["open"].has(hand_id):
		_state["open"] = []
	_swap = ""
	_save_state()


func _open_stack(path: Array) -> void:
	_state["open"] = path
	_save_state()


func _set_browse(on: bool) -> void:
	_browse = on
	_swap = ""
	_sync()


func _save_state() -> void:
	if _milestone != null:
		# Löst über `changed` den Abgleich aus.
		memory.write(Hand.key(_milestone["id"]), _state.duplicate(true))


# ------------------------------------------------------------- Ändern

## Schickt eine Änderung an Tasker. Die Karte bleibt so lange liegen, wo sie ist.
func _change(id: String, changes: Dictionary) -> bool:
	_busy[id] = true
	var ok := true
	if store == null or store.state != "ready":
		_change_demo(id, changes)
	else:
		var res := await store.patch("task", id, changes)
		ok = res["ok"]
		if not ok:
			_say(str(res["error"]))
	_busy.erase(id)
	return ok


## Ohne Verbindung ändert sich nur das Beispiel.
func _change_demo(id: String, changes: Dictionary) -> void:
	for t in _demo_data["tasks"]:
		if t["id"] == id:
			t.merge(changes, true)
			if changes.has("status"):
				t["doneAt"] = Time.get_datetime_string_from_system(true) + ".000Z" if changes["status"] == "done" else null
	_ws = Workspace.new(_demo_data)


## Ein abgelehnter Zug: die Karte geht zurück, und der Tisch sagt, warum.
func _refuse(text: String) -> void:
	_say(text)


func _say(text: String) -> void:
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = _toast.create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)
