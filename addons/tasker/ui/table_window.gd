@tool
extends "card_window.gd"
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
const Demo := preload("demo.gd")
const Model := preload("../rules/model.gd")
const Tisch := preload("../rules/tisch.gd")
const Hand := preload("../rules/hand.gd")
const Progress := preload("../rules/progress.gd")
const Workspace := preload("../rules/workspace.gd")
const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Memory := preload("../core/memory.gd")
const Sounds := preload("sounds.gd")
const Shelf := preload("shelf.gd")
const Burnup := preload("../rules/burnup.gd")
const PlanView := preload("plan_view.gd")
const DepGraphView := preload("dep_graph_view.gd")

const HEADER := 60.0
const MARGIN := 28.0
## So breit ist der Umschalter „Spielen / Planen“ links oben.
const MODES_WIDTH := 188.0
## Plätze im Spiel, die leer angezeigt werden – ein Richtwert, begrenzt wird nicht.
const SLOTS := 7
## Ab so vielen Pixeln wird aus einem Klick ein Ziehen.
const DRAG_START := 6.0
const Z_DRAG := 500
const Z_BROWSE := 20
const Z_DIM := 8
const Z_SHELF := 400
## So klein ist die Ablage, wenn sie aus dem Erledigt-Stapel kommt.
const SHELF_SMALL := 0.08
## Kippen beim Ziehen, wie `cardTilt.ts` in Tasker: stärkste Neigung in Grad,
## das Tempo, bei dem drei Viertel davon erreicht sind, und wie träge die
## Karte folgt und sich wieder aufrichtet.
const MAX_TILT := 22.0
## Wie viel davon die Karte am Tisch zeigt. Mit der vollen Neigung aus Tasker
## kippte sie zu stark (Nutzer, 2026-10-07).
const TILT_STRENGTH := 0.5
const TILT_SPEED := 180.0
const TILT_RESPONSE_MS := 90.0
const TILT_STILL_MS := 60

## Der Datenbestand und der Bild-Zwischenspeicher – ohne sie oder ohne
## Verbindung liegen ausgedachte Karten auf dem Tisch.
var store: Store
var images: Images
var memory := Memory.new()
## Wie viele Karten die Hand höchstens hält (Addon-Einstellung).
var hand_size := 7
## Ob der Tisch Töne spielt (Addon-Einstellung).
var sound_enabled := true: set = set_sound_enabled

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
## Karten, deren Änderung noch beim Server ist. Sie liegen schon am neuen
## Platz, lassen sich aber erst wieder greifen, wenn die Antwort da ist –
## eine zweite Änderung nennte sonst eine veraltete Version.
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
## Der Erledigt-Stapel ist aufgedeckt: die Ablage zeigt je Woche, was erledigt wurde.
var _shelf := false
var _shelf_data := {"weeks": [], "streak": 0, "this_week": 0}
## Der Stand beim letzten Abgleich – daran erkennt der Tisch, was sich getan hat.
var _seen := {}
## Beim Öffnen fliegen die Karten nacheinander an ihren Platz.
var _dealing := false
var _deal_count := 0

var _week: Label
var _week_bar: ProgressBar
var _streak: Label
var _chain: Control
var _shelf_panel: Shelf
## Ob die Ablage gerade zu sehen ist oder aufgeht, und ob sie noch zuklappt.
var _shelf_shown := false
var _shelf_closing := false
var _shelf_tween: Tween
## Der Platz im Spiel, an dem die gezogene Karte landen würde – oder -1.
var _gap := -1
## Tempo des Zeigers beim Ziehen in Pixeln pro Sekunde, geglättet, und die
## Neigung der gezogenen Karte in Grad (x nach links/rechts, y nach oben/unten).
var _velocity := Vector2.ZERO
var _tilt := Vector2.ZERO
var _last_move := 0
var _sounds: Sounds

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
## „Planen“ liegt über dem Spieltisch; der Umschalter wechselt.
var _plan: PlanView
## Der Graph einer Karte und das Menü, das ihn öffnet.
var _graph: DepGraphView
var _card_menu: PopupMenu
var _menu_task := ""
var _mode_play: Button
var _mode_plan: Button
var planning := false: set = set_planning


func _init() -> void:
	super()
	# Der Tisch rechnet mit der ganzen Fensterfläche und bemalt sie bis an die Kante.
	shadow = false
	rim_on_top = true
	fill = Palette.FELT
	title = "Tasker – Tisch"
	size = Vector2i(1440, 900)
	min_size = Vector2i(1100, 800)
	close_requested.connect(shut)
	size_changed.connect(_place)
	_build()


func _ready() -> void:
	if store != null:
		store.changed.connect(_sync)
		store.state_changed.connect(_sync)
	memory.changed.connect(_sync)
	visibility_changed.connect(func() -> void:
		if visible and not reshowing:
			_dealing = true
			_place())
	_dealing = true
	_sync()


func set_sound_enabled(value: bool) -> void:
	sound_enabled = value
	if _sounds != null:
		_sounds.enabled = value


## Lässt die gezogene Karte in die Bewegungsrichtung kippen und richtet sie
## wieder auf, sobald der Zeiger steht.
func _process(delta: float) -> void:
	if not _dragging or _pressed == null or not is_instance_valid(_pressed):
		return
	var k := 1.0 - exp(-delta * 1000.0 / TILT_RESPONSE_MS)
	if Time.get_ticks_msec() - _last_move > TILT_STILL_MS:
		_velocity -= _velocity * k
	# Nach rechts gezogen weicht die rechte Kante zurück, nach unten die untere.
	var target := Vector2(tanh(_velocity.x / TILT_SPEED), tanh(_velocity.y / TILT_SPEED)) * MAX_TILT * TILT_STRENGTH
	_tilt += (target - _tilt) * k

	# Ohne echte Tiefe: die Karte wird in der Kipprichtung schmaler, lehnt sich
	# leicht mit, und Licht und Schatten auf ihr zeigen, welche Seite zurückweicht.
	var squash := Vector2(cos(deg_to_rad(_tilt.x * 1.7)), cos(deg_to_rad(_tilt.y * 1.7)))
	_pressed.scale = squash * 1.08
	_pressed.rotation = deg_to_rad(_tilt.x) * 0.22
	_pressed.set_tilt(-_tilt / MAX_TILT)


func _build() -> void:
	_board = Control.new()
	_board.set_anchors_preset(Control.PRESET_FULL_RECT)
	_board.draw.connect(_draw_board)
	# Am freien Filz greift man den Tisch und verschiebt ihn.
	_board.gui_input.connect(_on_face_input)
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
			_close_overlays())
	_layer.add_child(_dim)

	# Die Kette liegt über den gesperrten Karten.
	_chain = Control.new()
	_chain.z_index = Z_DIM - 1
	_chain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chain.draw.connect(_draw_chain)
	_layer.add_child(_chain)

	_sounds = Sounds.new()
	_sounds.enabled = sound_enabled
	add_child(_sounds)

	_shelf_panel = Shelf.new()
	_shelf_panel.z_index = Z_SHELF
	_shelf_panel.visible = false
	_shelf_panel.close_requested.connect(_close_overlays)
	_shelf_panel.task_requested.connect(func(id: String) -> void: task_requested.emit(id))
	# Als Letztes im Fenster: so fängt die Ablage alle Klicks ab.
	add_child(_shelf_panel)

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

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_streak = Label.new()
	_streak.add_theme_color_override("font_color", Palette.P2)
	_streak.tooltip_text = "Wochen in Folge mit mindestens einer erledigten Karte"
	bar.add_child(_streak)
	_week = Label.new()
	_week.tooltip_text = "Erledigte Karten ohne Unteraufgaben diese Woche, gegen das Tempo aus den Tasker-Einstellungen"
	bar.add_child(_week)
	_week_bar = ProgressBar.new()
	_week_bar.show_percentage = false
	_week_bar.custom_minimum_size = Vector2(120, 8)
	_week_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_week_bar)

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

	# Rechtsklick auf eine Karte: ihre Abhängigkeiten ansehen, wie in der Planung.
	_card_menu = PopupMenu.new()
	_card_menu.add_item("Abhängigkeiten zeigen", 0)
	_card_menu.add_item("Aufgabe öffnen", 1)
	_card_menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_open_graph(_menu_task)
		elif store != null and store.state == "ready":
			task_requested.emit(_menu_task))
	add_child(_card_menu)
	# Der Graph legt sich über den Tisch.
	_graph = DepGraphView.new()
	_graph.z_index = 700
	_graph.task_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	add_child(_graph)

	# Die Planung deckt den Spieltisch ganz ab; nur der Umschalter bleibt darüber.
	_plan = PlanView.new()
	_plan.visible = false
	_plan.store = store
	_plan.task_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	add_child(_plan)

	var modes := HBoxContainer.new()
	modes.position = Vector2(MARGIN, 14)
	modes.add_theme_constant_override("separation", 0)
	add_child(modes)
	_mode_play = _mode_button("Spielen", "Der laufende Milestone als Kartenspiel")
	_mode_play.pressed.connect(func() -> void: planning = false)
	modes.add_child(_mode_play)
	_mode_plan = _mode_button("Planen", "Die Decks ansehen: was in welchem Milestone liegt und was im Vorrat")
	_mode_plan.pressed.connect(func() -> void: planning = true)
	modes.add_child(_mode_plan)
	bar.offset_left = MARGIN + MODES_WIDTH

	# Was sonst die Titelleiste trägt, liegt oben rechts über allem.
	var frame_buttons := HBoxContainer.new()
	frame_buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame_buttons.offset_top = 10
	frame_buttons.offset_right = -14
	frame_buttons.add_theme_constant_override("separation", 0)
	frame_buttons.z_index = 800
	frame_buttons.add_child(pin_button())
	frame_buttons.add_child(max_button())
	frame_buttons.add_child(close_button())
	add_child(frame_buttons)
	bar.offset_right = -MARGIN - 92
	_plan.gui_input.connect(_on_face_input)
	for part in [bar, gap]:
		part.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_face_input)
	_show_mode()


func _mode_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.x = MODES_WIDTH / 2.0 - 8.0
	return b


## Wechselt zwischen Spielen und Planen.
func set_planning(value: bool) -> void:
	planning = value
	if _plan == null:
		return
	_close_overlays()
	_graph.close()
	_show_mode()
	_sync()


func _show_mode() -> void:
	_plan.visible = planning
	# Die Karten des Spieltischs liegen auf eigenen Ebenen und würden sonst durchscheinen.
	_board.visible = not planning
	_layer.visible = not planning
	_mode_play.set_pressed_no_signal(not planning)
	_mode_plan.set_pressed_no_signal(planning)


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

	if planning:
		_plan.store = store
		_plan.show_plan(_ws, _project, 8 if demo else store.velocity, images if not demo else null,
			Burnup.day_of(Time.get_unix_time_from_system(), Time.get_time_zone_from_system()["bias"]))

	_milestone = Tisch.active_milestone(_ws, _project)
	if _milestone == null:
		_layout = {"locked": [], "open": [], "play": [], "pile": []}
		_state = {"hand": [], "buried": [], "open": []}
		_title.text = "Kein aktiver Milestone"
		_progress.visible = false
		_count.text = ""
		_week.text = ""
		_streak.text = ""
		_week_bar.visible = false
		_shelf_data = {"weeks": [], "streak": 0, "this_week": 0}
		_seen = {}
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

	# Wochenziel und Serie: das Ziel ist das Tempo aus den Tasker-Einstellungen.
	_shelf_data = Tisch.done_shelf(_ws, _milestone, Time.get_unix_time_from_system(), Time.get_time_zone_from_system()["bias"])
	var goal := _goal()
	var reached: bool = _shelf_data["this_week"] >= goal
	_week.text = "%sWoche %d/%d" % ["★ " if reached else "", _shelf_data["this_week"], goal]
	_week.add_theme_color_override("font_color", Palette.OK if reached else Palette.INK)
	_week_bar.visible = true
	_week_bar.max_value = goal
	_week_bar.value = mini(_shelf_data["this_week"], goal)
	_streak.text = "Serie: %d Wochen" % _shelf_data["streak"] if _shelf_data["streak"] >= 2 else ""
	if _shelf and _shelf_data["weeks"].is_empty():
		_shelf = false

	_notice_changes()
	if _shelf:
		_shelf_panel.show_shelf(_ws, _shelf_data, goal, images if not demo else null, Time.get_time_zone_from_system()["bias"])

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


func _goal() -> int:
	return maxi(1, store.velocity if store != null and store.state == "ready" else Store.DEFAULT_VELOCITY)


## Vergleicht mit dem letzten Abgleich und feiert, was sich getan hat – egal
## ob am Tisch, im Dock oder in der Web-App.
func _notice_changes() -> void:
	var locked := {}
	for t in _layout["locked"]:
		locked[t["id"]] = true
	var now := {
		"milestone": _milestone["id"],
		"locked": locked,
		"pile": _layout["pile"].size(),
		"week": _shelf_data["this_week"],
		"complete": _layout["pile"].size() > 0 and _layout["open"].is_empty() and _layout["play"].is_empty() and _layout["locked"].is_empty(),
	}
	var before := _seen
	_seen = now
	if before.get("milestone") != now["milestone"]:
		return

	var g := _geometry()
	for id in before["locked"]:
		var t = _ws.task(id)
		if not locked.has(id) and t != null and not Model.is_done(t) and _ws.is_active(t):
			_say("Kette gelöst: %s" % (t["title"] if t.get("title") else "Ohne Titel"), Palette.OK)
			_sounds.play("unlock")
			_burst(g["locked"].position + Card.SIZE / 2.0, Color("c9d1cd"))

	var gained: int = now["pile"] - before["pile"]
	if gained > 0:
		var pile_center: Vector2 = g["pile"].get_center()
		_float_text(pile_center + Vector2(0, -70), "+%d" % gained, Palette.OK)
		var goal := _goal()
		if now["week"] >= goal and before["week"] < goal:
			_float_text(pile_center + Vector2(0, -110), "★ Wochenziel", Palette.P2)
			_burst(pile_center, Palette.P2)
			_sounds.play("goal")
		else:
			_sounds.play("done")
	if now["complete"] and not before["complete"]:
		_float_text(Vector2(size.x / 2.0, size.y * 0.36), "◆ Milestone geschafft", Palette.P2, 34)
		_burst(Vector2(size.x * 0.35, size.y * 0.4), Palette.P2)
		_burst(Vector2(size.x * 0.65, size.y * 0.4), Palette.OK)
		_sounds.play("complete")


func _show_cards(wanted: Dictionary) -> void:
	var g := _geometry()
	for id in _cards.keys():
		if wanted.has(id):
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
			var top: Array = _layout["pile"].slice(0, 3).map(func(t: Dictionary) -> String: return t["id"]).filter(func(id: String) -> bool: return _zone.get(id) == "pile")
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
	_deal_count = 0
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
	if _gap >= 0 and _pressed != null:
		# Die Reihe rückt auseinander und lässt der gezogenen Karte ihren Platz.
		var others := play.filter(func(id: String) -> bool: return id != _pressed.task_id)
		for i in others.size():
			_rest_at(others[i], _play_spot(g, i if i < _gap else i + 1, others.size() + 1), 0.0, 3)
	else:
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

	# Die Ablage legt sich über den ganzen Tisch. Sie wächst aus dem
	# Erledigt-Stapel heraus und zieht sich dorthin zurück.
	_shelf_panel.position = Vector2(20, 20)
	_shelf_panel.size = Vector2(size) - Vector2(40, 40)
	_shelf_panel.pivot_offset = g["pile"].get_center() - _shelf_panel.position
	if _shelf != _shelf_shown:
		_shelf_shown = _shelf
		_animate_shelf(_shelf)

	var over_all := _shelf or _shelf_closing
	_dim.visible = _browse or over_all
	_dim.position = Vector2.ZERO
	_dim.size = Vector2(size.x, size.y if over_all else g["hand"].position.y)
	_dim.z_index = Z_SHELF - 1 if over_all else Z_DIM
	_chain.position = g["locked"].position
	_chain.size = g["locked"].size
	_chain.queue_redraw()
	_place_labels(g)
	_board.queue_redraw()
	_dealing = false


func _play_spot(g: Dictionary, index: int, count: int) -> Vector2:
	var rect: Rect2 = g["play"]
	var c: Vector2 = g["card"]
	var slots := maxi(count, SLOTS)
	var step := minf(c.x + 16.0, (rect.size.x - c.x) / maxf(slots - 1, 1))
	var left := rect.get_center().x - (step * (slots - 1) + c.x) / 2.0
	return Vector2(left + index * step, rect.position.y + 12.0)


## Merkt sich den Ruheplatz der Karte und lässt sie hingleiten. `spot` ist die
## linke obere Ecke, wie die Karte dort zu sehen ist – auch verkleinert.
func _rest_at(id: String, spot: Vector2, angle: float, z: int, card_scale := 1.0) -> void:
	# Karten drehen und schrumpfen um ihre Mitte.
	var position := spot - Card.SIZE * (1.0 - card_scale) / 2.0
	_rest[id] = {"position": position, "rotation": angle, "z": z, "scale": card_scale}
	var card: Control = _cards.get(id)
	if card == null or (card == _pressed and _dragging):
		return
	card.z_index = z
	card.lift = 0.0
	var to_scale := Vector2(card_scale, card_scale)
	if card.position.distance_to(position) < 0.5 and is_equal_approx(card.rotation, angle) and card.scale.is_equal_approx(to_scale):
		return
	# Beim Öffnen des Tischs werden die Karten nacheinander ausgeteilt.
	var delay := 0.0
	if _dealing:
		delay = _deal_count * 0.035
		_deal_count += 1
	_glide(id, position, angle, to_scale, 0.3, Tween.TRANS_BACK, delay)


func _glide(id: String, spot: Vector2, angle: float, to_scale: Vector2, time: float, trans := Tween.TRANS_CUBIC, delay := 0.0) -> void:
	var card: Control = _cards.get(id)
	if card == null:
		return
	if _tweens.get(id) != null and _tweens[id].is_valid():
		_tweens[id].kill()
	var tween := card.create_tween().set_parallel().set_trans(trans).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", spot, time).set_delay(delay)
	tween.tween_property(card, "rotation", angle, time).set_delay(delay)
	tween.tween_property(card, "scale", to_scale, time).set_delay(delay)
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

	# Der Nachziehstapel: verdeckte Karten mit Rückseite, je mehr, desto höher.
	var deck := _deck().size()
	if deck == 0:
		_board.draw_style_box(slot, Rect2(g["deck"].position, c))
		var font := Palette.body_font()
		var text := "leer"
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		_board.draw_string(font, g["deck"].position + Vector2((c.x - width) / 2.0, c.y / 2.0 + 5.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.35))
	var layers := mini(deck, 5)
	for i in layers:
		var at: Vector2 = g["deck"].position + Vector2(8.0 - i * 2.0, 8.0 - i * 2.0)
		var top := i == layers - 1
		_draw_card_back(Rect2(at, c), top, i == 0)

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

	# Der Platz im Spiel, an dem die gezogene Karte landen würde.
	if _gap >= 0 and _pressed != null:
		var others := _ids_in("play").filter(func(id: String) -> bool: return id != _pressed.task_id).size()
		var landing := StyleBoxFlat.new()
		landing.bg_color = Color(Palette.ACCENT, 0.22)
		landing.border_color = Palette.ACCENT
		landing.set_border_width_all(3)
		landing.set_corner_radius_all(Card.RADIUS)
		_board.draw_style_box(landing, Rect2(_play_spot(g, _gap, others + 1), c))


# --------------------------------------------------------------- Maus

func _on_card_pressed(card: Control, event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and not _shelf and not _browse:
		_menu_task = card.task_id
		_card_menu.position = Vector2i(DisplayServer.mouse_get_position())
		_card_menu.popup()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	# Unter der Ablage und dem aufgedeckten Stapel liegt der Tisch still.
	var zone: String = _zone.get(card.task_id, "")
	if _shelf or (_browse and zone != "deck" and zone != "hand"):
		return
	if event.double_click:
		_pressed = null
		task_requested.emit(card.task_id)
		return
	_pressed = card
	_dragging = false
	_press_at = _layer.get_local_mouse_position()
	_grab = card.position - _press_at


## Zeigt, worauf die Karte wartet und was auf sie wartet.
func _open_graph(id: String) -> void:
	var item = _ws.task(id)
	if item != null:
		_graph.open(_ws, item, _project)


func _input(event: InputEvent) -> void:
	if _graph.visible and not planning:
		# Escape schließt den Graphen; darunter liegt der Tisch still.
		if event.is_action_pressed("ui_cancel"):
			_graph.close()
			set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") and (_browse or _shelf or _state["open"].size() > 0):
		set_input_as_handled()
		if _browse or _shelf:
			_close_overlays()
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
			_pressed.lift = 1.0
			_velocity = Vector2.ZERO
			_tilt = Vector2.ZERO
		if _dragging:
			_pressed.position = mouse + _grab
			# Die Karte kippt in die Bewegungsrichtung – das Tempo dazu wird hier
			# gemessen, die Neigung selbst folgt in `_process`.
			_velocity = _velocity.lerp(event.velocity, 0.5)
			_last_move = Time.get_ticks_msec()
			var hot := _zone_at(mouse)
			# Über dem Spiel zeigt eine Lücke, wo die Karte landen würde.
			var gap := -1
			var id: String = _pressed.task_id
			if hot == "play" and (_zone.get(id) == "play" or Tisch.play_refusal(_ws, _ws.task(id)) == ""):
				gap = _play_index(_pressed.position.x + Card.SIZE.x / 2.0, id)
			if hot != _hot or gap != _gap:
				_hot = hot
				_gap = gap
				_place()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var card := _pressed
		var was_dragging := _dragging
		var gap := _gap
		_pressed = null
		_dragging = false
		_hot = ""
		_gap = -1
		card.set_tilt(Vector2.ZERO)
		_board.queue_redraw()
		if was_dragging:
			_drop(card.task_id, mouse, gap)
		else:
			_click(card.task_id)


func _can_drag(id: String) -> bool:
	match _zone.get(id, ""):
		"hand", "play", "drawer":
			return not _busy.has(id)
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
	if _shelf or _zone.get(id) != "hand" or _busy.has(id) or _pressed != null or not _rest.has(id):
		return
	var rest: Dictionary = _rest[id]
	if inside:
		card.z_index = 100
		card.lift = 0.5
		_glide(id, rest["position"] + Vector2(0, -30), 0.0, Vector2(1.1, 1.1), 0.14)
	else:
		card.z_index = rest["z"]
		card.lift = 0.0
		_glide(id, rest["position"], rest["rotation"], Vector2(rest["scale"], rest["scale"]), 0.18)


# --------------------------------------------------------------- Züge

func _click(id: String) -> void:
	match _zone.get(id, ""):
		"pile":
			_set_shelf(not _shelf)
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


## Legt die Karte ab. `play_index` ist der Platz im Spiel aus der Vorschau;
## ohne ihn zählt die Stelle `at`.
func _drop(id: String, at: Vector2, play_index := -1) -> void:
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
				if from != "play":
					_sounds.play("play")
				await _play_at(id, play_index if play_index >= 0 else _play_index(at.x, id))
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
			elif from == "play":
				# Die Karte liegt sofort wieder auf der Hand; lehnt Tasker ab, ist
				# sie zurück im Spiel. Hand und Status ändern sich in einem Zug,
				# damit kein Zwischenstand die Karte kurz woanders zeigt.
				var top: bool = not task.get("parentId")
				var added: bool = top and not _state["hand"].has(id)
				if top:
					_batch = true
					if added:
						_state["hand"].append(id)
					_state["buried"].erase(id)
					_save_state()
					_batch = false
				if not await _change(id, {"status": "open"}) and added:
					_state["hand"].erase(id)
					_save_state()
	_sync()


## An welchen Platz im Spiel eine Karte käme, deren Mitte bei `x` liegt: der
## nächstgelegene Platz in der Reihe, wie sie mit der Karte aussähe.
func _play_index(x: float, dragged: String) -> int:
	var g := _geometry()
	var others := _ids_in("play").filter(func(id: String) -> bool: return id != dragged).size()
	var first := _play_spot(g, 0, others + 1).x + Card.SIZE.x / 2.0
	var step := _play_spot(g, 1, others + 1).x - _play_spot(g, 0, others + 1).x
	return clampi(roundi((x - first) / step), 0, others)


## Legt die Karte an diesen Platz im Spiel. Die Reihe wird durchgezählt; wer
## dabei erst ins Spiel kommt, bekommt den Status gleich mit. Alles liegt
## sofort so da; lehnt Tasker die Karte selbst ab, kommt sie zurück auf die Hand.
func _play_at(id: String, index: int) -> void:
	var row: Array = _layout["play"].map(func(t: Dictionary) -> String: return t["id"]).filter(func(x: String) -> bool: return x != id)
	row.insert(mini(index, row.size()), id)
	var was_in_hand: int = _state["hand"].find(id)
	_batch = true
	_state["hand"].erase(id)
	_save_state()
	# Alle Änderungen gehen zugleich hinaus – jede steht mit dem Abschicken im Stand.
	var moved: Array = []
	for i in row.size():
		var t = _ws.task(row[i])
		if t == null:
			continue
		var changes := {}
		if t["status"] != "progress":
			changes["status"] = "progress"
		if int(t.get("playOrder", 0)) != i + 1:
			changes["playOrder"] = i + 1
		if changes.is_empty():
			continue
		if row[i] == id:
			moved = [changes]
		else:
			_change(row[i], changes)
	_batch = false
	_sync_soon()
	if moved.is_empty():
		return
	if not await _change(id, moved[0]) and was_in_hand >= 0 and not _state["hand"].has(id):
		_state["hand"].insert(mini(was_in_hand, _state["hand"].size()), id)
		_save_state()


## Gleicht den Tisch im nächsten Leerlauf ab – nach Zügen, deren Antwort noch aussteht.
func _sync_soon() -> void:
	_sync.call_deferred()


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
	_sounds.play("draw")
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
	_shelf = false
	_swap = ""
	_sync()


## Deckt den Erledigt-Stapel auf oder sammelt ihn wieder ein.
func _set_shelf(on: bool) -> void:
	_shelf = on and _shelf_data["weeks"].size() > 0
	_browse = false
	_swap = ""
	_sync()


## Lässt die Ablage aus dem Erledigt-Stapel aufgehen oder dorthin zuklappen.
func _animate_shelf(open: bool) -> void:
	if _shelf_tween != null:
		_shelf_tween.kill()
	# Geht sie in den aufgedeckten Nachziehstapel über, bleibt der Schleier stehen.
	var fade_dim := not _browse
	_shelf_tween = _shelf_panel.create_tween().set_parallel()
	if open:
		if not _shelf_panel.visible:
			_shelf_panel.scale = Vector2(SHELF_SMALL, SHELF_SMALL)
			_shelf_panel.modulate.a = 0.0
			if fade_dim:
				_dim.modulate.a = 0.0
		_shelf_panel.visible = true
		_shelf_closing = false
		_shelf_tween.tween_property(_shelf_panel, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_shelf_tween.tween_property(_shelf_panel, "modulate:a", 1.0, 0.16)
		_shelf_tween.tween_property(_dim, "modulate:a", 1.0, 0.2)
	else:
		_shelf_closing = _shelf_panel.visible
		_shelf_tween.tween_property(_shelf_panel, "scale", Vector2(SHELF_SMALL, SHELF_SMALL), 0.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		_shelf_tween.tween_property(_shelf_panel, "modulate:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
		if fade_dim:
			_shelf_tween.tween_property(_dim, "modulate:a", 0.0, 0.2)
		_shelf_tween.chain().tween_callback(func() -> void:
			_shelf_panel.visible = false
			_shelf_closing = false
			_dim.modulate.a = 1.0
			_place())


func _close_overlays() -> void:
	_browse = false
	_shelf = false
	_swap = ""
	_sync()


func _save_state() -> void:
	if _milestone != null:
		# Löst über `changed` den Abgleich aus.
		memory.write(Hand.key(_milestone["id"]), _state.duplicate(true))


# ------------------------------------------------------------- Ändern

## Schickt eine Änderung an Tasker. Sie gilt sofort (`Store.patch`); die Karte
## lässt sich nur so lange nicht greifen, bis die Antwort da ist.
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
	_sounds.play("refuse")
	_say(text)


func _say(text: String, color := Palette.P2) -> void:
	_toast.add_theme_color_override("font_color", color)
	_toast.text = text
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast.modulate.a = 1.0
	_toast_tween = _toast.create_tween()
	_toast_tween.tween_interval(2.6)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.5)


# ------------------------------------------------------------ Effekte

## Ein Wort, das kurz aufsteigt und verblasst – „+1“ über dem Erledigt-Stapel.
func _float_text(at: Vector2, text: String, color: Color, font_size := 22) -> void:
	var l := Label.new()
	l.text = text
	l.z_index = 700
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", Palette.title_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_layer.add_child(l)
	l.position = at - Vector2(l.get_minimum_size().x / 2.0, 0)
	var tween := l.create_tween()
	tween.tween_property(l, "position:y", l.position.y - 46.0, 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tween.tween_callback(l.queue_free)


## Funken, die von einer Stelle aus aufstieben.
func _burst(at: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.z_index = 650
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 46
	p.lifetime = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 340.0
	p.gravity = Vector2(0, 520)
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.5
	var fade := Gradient.new()
	fade.colors = PackedColorArray([color, Color(color, 0.0)])
	p.color_ramp = fade
	_layer.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Die Ketten über den gesperrten Karten: zwei, über Kreuz, mit einem Schloss
## in der Mitte.
func _draw_chain() -> void:
	var count: int = _layout["locked"].size()
	if count == 0 or _milestone == null:
		return
	var shown := mini(count, 6)
	var c := Card.SIZE
	# Die Fläche, die der gesperrte Stapel einnimmt.
	var box := Rect2(Vector2(4.0, 2.0), Vector2(c.x + 14.0, c.y + (shown - 1) * 20.0))
	var center := box.get_center()
	var runs := [
		[box.position + Vector2(-8.0, box.size.y * 0.20), box.position + Vector2(box.size.x + 8.0, box.size.y * 0.80)],
		[box.position + Vector2(box.size.x + 8.0, box.size.y * 0.20), box.position + Vector2(-8.0, box.size.y * 0.80)],
	]
	# Erst der Schatten beider Ketten, dann die Ketten – so liegt keine im Schatten der anderen.
	for run in runs:
		_draw_chain_run(run[0] + Vector2(2, 4), run[1] + Vector2(2, 4), true)
	for run in runs:
		_draw_chain_run(run[0], run[1], false)
	_draw_padlock(center)


## Eine Kette aus Gliedern, abwechselnd von vorn und von der Seite gesehen.
func _draw_chain_run(from: Vector2, to: Vector2, shadow: bool) -> void:
	var steel_dark := Color("2f3634")
	var steel := Color("8f9a96")
	var steel_light := Color("e4ebe7")
	var angle := from.angle_to_point(to)
	var links := maxi(int(from.distance_to(to) / 13.0), 2)
	for i in links + 1:
		var at := from.lerp(to, float(i) / links)
		if shadow:
			_chain.draw_circle(at, 7.0, Color(0, 0, 0, 0.16), true, -1.0, true)
			continue
		if i % 2 == 0:
			# Von vorn: ein längliches Oval.
			_chain.draw_set_transform(at, angle, Vector2(1.0, 0.62))
			_chain.draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, steel_dark, 6.5, true)
			_chain.draw_arc(Vector2.ZERO, 8.5, 0.0, TAU, 20, steel, 3.8, true)
			_chain.draw_arc(Vector2.ZERO, 8.5, PI * 1.08, PI * 1.92, 10, steel_light, 1.6, true)
		else:
			# Von der Seite: nur die Kante des Glieds.
			_chain.draw_set_transform(at, angle)
			_chain.draw_line(Vector2(-7.5, 0), Vector2(7.5, 0), steel_dark, 6.5, true)
			_chain.draw_line(Vector2(-7.0, 0), Vector2(7.0, 0), steel, 3.6, true)
			_chain.draw_line(Vector2(-6.0, -1.0), Vector2(6.0, -1.0), steel_light, 1.2, true)
	_chain.draw_set_transform(Vector2.ZERO)


func _draw_padlock(at: Vector2) -> void:
	var brass := StyleBoxFlat.new()
	brass.bg_color = Color("c9a24a")
	brass.border_color = Color("6e561f")
	brass.set_border_width_all(2)
	brass.set_corner_radius_all(5)
	brass.shadow_color = Color(0, 0, 0, 0.35)
	brass.shadow_size = 5
	brass.shadow_offset = Vector2(1, 3)
	# Der Bügel aus Stahl, darunter der Körper aus Messing.
	_chain.draw_arc(at + Vector2(0, -8), 8.5, PI, TAU, 16, Color("2f3634"), 7.0, true)
	_chain.draw_arc(at + Vector2(0, -8), 8.5, PI, TAU, 16, Color("aab4b0"), 4.0, true)
	_chain.draw_style_box(brass, Rect2(at + Vector2(-14, -9), Vector2(28, 22)))
	_chain.draw_line(at + Vector2(-10, -5), at + Vector2(10, -5), Color("e9cf85"), 1.5, true)
	_chain.draw_circle(at + Vector2(0, 1), 3.2, Color("3a2d10"), true, -1.0, true)
	_chain.draw_rect(Rect2(at + Vector2(-1.3, 2), Vector2(2.6, 6)), Color("3a2d10"))


## Die Rückseite einer Karte: dunkelblau mit hellem Rahmen und Rautenmuster,
## damit sich der Nachziehstapel klar vom Filz abhebt.
func _draw_card_back(rect: Rect2, with_pattern: bool, with_shadow: bool) -> void:
	var back := StyleBoxFlat.new()
	back.bg_color = Color("24365c")
	back.border_color = Color("a9c1ee")
	back.set_border_width_all(2)
	back.set_corner_radius_all(Card.RADIUS)
	if with_shadow:
		back.shadow_color = Color(0, 0, 0, 0.35)
		back.shadow_size = 8
		back.shadow_offset = Vector2(0, 4)
	_board.draw_style_box(back, rect)
	if not with_pattern:
		return

	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("1c2a49")
	frame.border_color = Color("6f8fcf")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(6)
	var inner := rect.grow(-10.0)
	_board.draw_style_box(frame, inner)

	# Ein Gitter aus Rauten, in der Mitte eine große.
	var line := Color("6f8fcf", 0.55)
	var cell := 16.0
	var n := int((inner.size.x + inner.size.y) / cell) + 1
	for i in n:
		var d := i * cell
		var a := inner.position + Vector2(minf(d, inner.size.x), maxf(0.0, d - inner.size.x))
		var b := inner.position + Vector2(maxf(0.0, d - inner.size.y), minf(d, inner.size.y))
		_board.draw_line(a, b, line, 1.0, true)
		var a2 := inner.position + Vector2(inner.size.x - minf(d, inner.size.x), maxf(0.0, d - inner.size.x))
		var b2 := inner.position + Vector2(inner.size.x - maxf(0.0, d - inner.size.y), minf(d, inner.size.y))
		_board.draw_line(a2, b2, line, 1.0, true)
	var mid := rect.get_center()
	var diamond := PackedVector2Array([mid + Vector2(0, -24), mid + Vector2(17, 0), mid + Vector2(0, 24), mid + Vector2(-17, 0)])
	_board.draw_colored_polygon(diamond, Color("24365c"))
	diamond.append(diamond[0])
	_board.draw_polyline(diamond, Color("a9c1ee"), 2.0, true)


## Der Tisch wird nicht verworfen, nur weggelegt: beim nächsten Öffnen liegt
## alles, wo es lag.
func _gone() -> void:
	hide()
