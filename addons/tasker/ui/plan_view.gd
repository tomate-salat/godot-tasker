@tool
extends Control
## Planen am Tisch: zwei Sammelordner nebeneinander. Im linken
## steckt der Vorrat – „Ready“ oder „Backlog“ –, im rechten die Decks,
## die eingeplanten Milestones. Jede Gruppe und jeder Milestone hat sein
## Registerblatt und eigene Seiten. Geblättert
## wird in jedem Ordner für sich (`binder.gd`).
##
## Liegt über dem Spieltisch, solange im Tisch-Fenster „Planen“ gewählt ist.
## Vorerst wird nur angesehen: ein Klick fächert die Unteraufgaben einer Karte
## auf, ein Doppelklick öffnet sie. Was wo liegt und welche Karte ein Schloss
## trägt, steht in `rules/planning.gd`, die Prognose in `rules/schedule.gd`.

signal task_requested(task_id: String)

const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Planning := preload("../rules/planning.gd")
const Schedule := preload("../rules/schedule.gd")
const Progress := preload("../rules/progress.gd")
const Burnup := preload("../rules/burnup.gd")
const Model := preload("../rules/model.gd")
const Workspace := preload("../rules/workspace.gd")
const Binder := preload("binder.gd")
const DepGraphView := preload("dep_graph_view.gd")
const Store := preload("../core/store.gd")

const MARGIN := 28.0
const HEADER := 60.0
## Über dem Ordner stehen die Reiter, die den Vorrat wählen.
const TOP := 44.0
## Spalten je Seite.
const COLUMNS := 3
## Breiter als so werden die Registerblätter auch in einem breiten Fenster nicht.
const TAB_MAX := 170.0
## Zwischen den beiden Ordnern.
const BETWEEN := 18.0
## Kleiner als so werden die Ordner in einem schmalen Fenster nicht.
const MIN_SCALE := 0.6
## Ziehen wie am Spieltisch (`table_window.gd`): ab so vielen Pixeln wird aus
## einem Klick ein Ziehen, und so kippt die Karte in die Bewegungsrichtung.
const DRAG_START := 6.0
const MAX_TILT := 22.0
const TILT_STRENGTH := 0.5
const TILT_SPEED := 180.0
const TILT_RESPONSE_MS := 90.0
const TILT_STILL_MS := 60
## So lange fliegt eine losgelassene Karte an ihr Ziel.
const FLY_SECONDS := 0.16
## So lange braucht eine Karte zurück, wenn Tasker den Zug ablehnt.
const BACK_SECONDS := 0.36

## Der Datenbestand, über den Karten verschoben werden – fehlt er oder steht
## keine Verbindung, wird nur angesehen.
var store: Store

var _ws: Workspace
var _project := ""
var _velocity := 8
var _images: Node
var _today := 0
## Welcher Stapel des Vorrats auf der linken Seite steckt.
var _stock := Planning.READY
## Aufgefächerte Karten: ID → wahr.
var _fanned := {}
## Was gezeigt wird – bei gleichem Stand wird nicht neu aufgebaut.
var _shown := 0
var _resize_queued := false

var _tabs := {}
var _tab_box: HBoxContainer
var _left: Binder
var _right: Binder
var _info: Label
var _graph: DepGraphView
var _menu: PopupMenu
## Die Karte, zu der das Menü offen ist.
var _menu_task := ""
## Was in den Ordnern steckt, je Abschnitt mit seinem Ort – für das Ablegen.
var _stock_sections: Array = []
var _deck_sections: Array = []
var _note: Label
var _note_tween: Tween
var _moving := false
## Die Karte, auf der die Maustaste unten ist, und – sobald gezogen wird – ihre
## Kopie am Zeiger, der Ordner, aus dem sie kommt, und der, über dem sie schwebt.
var _pressed: Control
var _press_at := Vector2.ZERO
var _flying: Control
var _grab := Vector2.ZERO
var _source: Binder
var _over: Binder
## Wie groß die Karten im Ordner gerade sind (er wird in schmalen Fenstern kleiner).
var _size := 1.0
## Tempo des Zeigers beim Ziehen, geglättet, und die Neigung der Karte in Grad.
var _pointer_speed := Vector2.ZERO
var _tilt := Vector2.ZERO
var _last_move := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var felt := ColorRect.new()
	felt.color = Palette.FELT
	felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(felt)

	_left = Binder.new()
	add_child(_left)
	_right = Binder.new()
	_right.header_pressed.connect(func(id: String) -> void: task_requested.emit(id))
	add_child(_right)

	_tab_box = HBoxContainer.new()
	_tab_box.add_theme_constant_override("separation", 6)
	add_child(_tab_box)
	for which in [Planning.READY, Planning.BACKLOG]:
		var tab := Button.new()
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.pressed.connect(_show_stock.bind(which))
		_tab_box.add_child(tab)
		_tabs[which] = tab

	_info = Label.new()
	_info.position = Vector2(MARGIN + 204.0, 19.0)
	_info.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_info)


	# Hier steht, warum ein Zug nicht ging.
	_note = Label.new()
	_note.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_note.offset_left = -620.0
	_note.offset_right = -MARGIN
	_note.offset_top = HEADER + 6.0
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_note.clip_text = true
	_note.add_theme_color_override("font_color", Palette.P2)
	_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_note.modulate.a = 0.0
	add_child(_note)

	_menu = PopupMenu.new()
	_menu.add_item("Abhängigkeiten zeigen", 0)
	_menu.add_item("Aufgabe öffnen", 1)
	_menu.id_pressed.connect(func(id: int) -> void:
		if id == 0:
			_open_graph(_menu_task)
		else:
			task_requested.emit(_menu_task))
	add_child(_menu)

	# Der Graph einer Karte legt sich über den Ordner.
	_graph = DepGraphView.new()
	_graph.task_requested.connect(func(id: String) -> void: task_requested.emit(id))
	add_child(_graph)
	resized.connect(_on_resized)


## Zeigt den Stand. `today` ist die Tagesnummer von heute (`Burnup.day_of`).
func show_plan(ws: Workspace, project_id: String, velocity: int, images: Node, today: int) -> void:
	_ws = ws
	_project = project_id
	_velocity = velocity
	_images = images
	_today = today
	_info.text = "Tempo: %d Karten je Woche   ·   Karten ziehen verteilt sie, Klick fächert auf, Doppelklick öffnet" % velocity
	var stamp := hash([ws.tasks, ws.milestones, ws.groups, ws.marks, ws.categories, project_id, velocity, today, _stock, _fanned, size])
	if stamp == _shown:
		return
	_shown = stamp
	_rebuild()


func _show_stock(which: String) -> void:
	_stock = which
	_shown = 0
	_rebuild()


func _rebuild() -> void:
	if _ws == null:
		return
	# Zwei Ordner nebeneinander, einer für den Vorrat, einer für die Decks.
	var spread := Binder.binder_width(COLUMNS)
	var room := size.x - MARGIN * 2.0 - BETWEEN
	# Passt das nicht in die Breite, werden beide Ordner im Ganzen kleiner.
	var shrink := clampf(room / ((spread + Binder.TAB_OUT) * 2.0), MIN_SCALE, 1.0)
	# Was an Breite übrig ist, bekommen die Registerblätter, damit ihre Namen passen.
	var tab_out := clampf((room / shrink - spread * 2.0) / 2.0, Binder.TAB_OUT, TAB_MAX)
	var wide := spread + tab_out
	var top := HEADER + TOP
	var tall := (size.y - top - 14.0) / shrink
	var left_x := roundf(maxf((size.x - (wide * 2.0 * shrink + BETWEEN)) / 2.0, MARGIN - 12.0))

	for binder in [_left, _right]:
		binder.columns = COLUMNS
		binder.tab_out = tab_out
		binder.scale = Vector2(shrink, shrink)
		binder.size = Vector2(wide, tall)
	_left.position = Vector2(left_x, top)
	_right.position = Vector2(left_x + wide * shrink + BETWEEN, top)
	_tab_box.position = Vector2(_left.position.x, HEADER + 2.0)

	_build_stock()
	_build_decks()


## Das Fenster hat eine andere Größe: neu einteilen.
func _on_resized() -> void:
	if _ws != null and not _resize_queued:
		_resize_queued = true
		(func() -> void:
			_resize_queued = false
			_shown = 0
			_rebuild()).call_deferred()


# -------------------------------------------------------------- Seiten

## Der linke Ordner: der gewählte Stapel des Vorrats. Jede Gruppe hat ihr
## Registerblatt und ihre eigenen Seiten, wie ein Deck.
func _build_stock() -> void:
	for which in _tabs:
		_tabs[which].text = "%s  %d" % ["Ready" if which == Planning.READY else "Backlog", Planning.stock_count(_ws, _project, which)]
		_tabs[which].set_pressed_no_signal(which == _stock)
	var sections := []
	for section in Planning.stock(_ws, _project, _stock, true):
		var count: int = section["cards"].size()
		# Leere Gruppen zeigen sich nur beim Ziehen, als Ziel.
		sections.append({"title": section["title"], "items": _items(section["cards"]), "place": section["place"], "roots": _ids(section["cards"]), "hide_if_empty": true, "header": {
			"title": section["title"], "line": "%d %s in „%s“" % [count, "Karte" if count == 1 else "Karten", "Ready" if _stock == Planning.READY else "Backlog"]}})
	_left.card_maker = _card.bind(Planning.deck_order(Planning.decks(_ws, _project)))
	_stock_sections = sections
	_left.empty_title = "Dieser Stapel ist leer"
	_left.show_sections(_stock, sections)


## Der rechte Ordner: die Decks. Jeder Milestone hat sein Registerblatt und
## seine eigenen Seiten, mit Fortschritt und Prognose darüber.
func _build_decks() -> void:
	var decks := Planning.decks(_ws, _project)
	var forecast := {}
	for x in Schedule.schedule(_ws, _velocity, _today):
		forecast[x["milestone"]["id"]] = x
	var sections := []
	for m in decks:
		var f: Dictionary = forecast.get(m["id"], {})
		var done := Progress.milestone_done(_ws, m)
		var active: bool = m.get("status") == "progress"
		var name: String = m["title"] if m.get("title") else "Ohne Titel"
		var count := "%d/%d" % [f.get("done", 0), f.get("total", 0)]
		var line := count
		var tip := "Milestone öffnen"
		if done:
			line = "abgeschlossen · %s · verschwindet hier, sobald er in Tasker archiviert ist" % count
		elif not f.is_empty():
			var start := Schedule.day_from_weeks(maxf(f["start"], 0.0), _today)
			line = "%s · %s" % [count, "läuft · bis KW %d" % Schedule.iso_week(Schedule.day_from_weeks(f["end"], _today)) if active else "ab KW %d" % Schedule.iso_week(start)]
			tip = "Milestone öffnen\n%s%s, voraussichtlich fertig am %s%s" % [
				"läuft" if active else "geplant ab %s" % Burnup.format_day(start),
				" (Startdatum gesetzt)" if f["fixed"] else "",
				Burnup.format_day(Schedule.day_from_weeks(f["forecast_end"], _today)),
				"\nDas reißt das gesetzte Enddatum." if f["late"] else ""]
		sections.append({
			"title": "%s %s" % ["✓" if done else "▶" if active else "◆", name],
			"tip": "%s\n%s" % [name, line],
			# Ein abgeschlossenes Deck zeigt nur noch seine Kopfzeile.
			"items": [] if done else _items(_ws.ms_roots(m)),
			# In ein abgeschlossenes Deck wird nichts mehr gelegt.
			"drop": not done, "place": {"milestoneId": m["id"]}, "roots": _ids(_ws.ms_roots(m)),
			"header": {
				"id": m["id"], "title": "%s %s" % ["✓" if done else "◆", name], "line": line, "tip": tip,
				"late": f.get("late", false), "pct": Progress.milestone_progress_pct(_ws, m),
				"accent": Palette.OK if done else Palette.ACCENT if active else Palette.INK,
			},
		})
	if sections.is_empty():
		sections.append({"title": "Keine Decks", "items": [], "drop": false, "header": {
			"id": "", "title": "Noch kein Milestone eingeplant", "line": "Eingeplant wird in Tasker – hier erscheinen die Milestones dann als Decks.", "pct": 0}})
	# Aufgeschlagen wird zuerst das laufende Deck.
	for i in decks.size():
		if decks[i].get("status") == "progress":
			_right.start_section = i
			break
	_right.card_maker = _card.bind(Planning.deck_order(decks))
	_deck_sections = sections
	_right.show_sections("decks", sections)


## Die Karten für den Ordner: jede Wurzel und, ist sie aufgefächert, ihre
## Unteraufgaben in den Fächern danach.
func _items(roots: Array) -> Array:
	var out := []
	for t in roots:
		var rows := []
		_rows(t, 0, rows)
		for row in rows:
			var above = _ws.task(row["task"].get("parentId")) if row["depth"] > 0 else null
			out.append({"task": row["task"], "child_of": (str(above["title"]) if above.get("title") else "Ohne Titel") if above != null else ""})
	return out


## Die Karte und, ist sie aufgefächert, ihre Unteraufgaben danach.
func _rows(t: Dictionary, depth: int, out: Array) -> void:
	out.append({"task": t, "depth": depth})
	if _fanned.has(t["id"]):
		for k in _ws.kids(t["id"]):
			_rows(k, depth + 1, out)


# -------------------------------------------------------------- Karten

func _card(t: Dictionary, order: Dictionary) -> Control:
	var card := Card.new()
	card.show_task(_ws, t, _images)
	card.pressed.connect(_on_card)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var kids := _ws.kids(t["id"]).size()
	card.tooltip_text = "Doppelklick öffnet die Aufgabe" if kids == 0 else "Klick fächert die %d Unteraufgaben %s, Doppelklick öffnet die Aufgabe" % [kids, "ein" if _fanned.has(t["id"]) else "auf"]
	var lock := Planning.lock_of(_ws, t, order)
	if lock != "":
		var badge := Control.new()
		badge.set_meta("lock", lock)
		badge.position = Vector2(Card.SIZE.x - 34.0, 6.0)
		badge.size = Vector2(28.0, 28.0)
		badge.mouse_filter = Control.MOUSE_FILTER_STOP
		badge.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		badge.tooltip_text = "Abhängigkeiten zeigen"
		badge.gui_input.connect(func(event: InputEvent) -> void:
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
				badge.accept_event()
				_open_graph(t["id"]))
		badge.draw.connect(_draw_lock.bind(badge))
		card.add_child(badge)
		var names := Planning.card_blockers(_ws, t).map(func(b: Dictionary) -> String: return str(b["title"]) if b.get("title") else "Ohne Titel")
		card.tooltip_text += "\nWartet auf: %s" % ", ".join(names)
		if lock == Planning.MISPLACED:
			card.tooltip_text += "\nDavon liegt etwas in einem späteren Deck oder noch im Vorrat."
	return card


## Das Schloss an einer gesperrten Karte, oben rechts; ein Klick zeigt den Graphen:
## gelb, wenn sie wartet, rot, wenn das, worauf sie wartet, später oder gar
## nicht eingeplant ist.
func _draw_lock(badge: Control) -> void:
	var color: Color = Palette.P1 if badge.get_meta("lock") == Planning.MISPLACED else Palette.P2
	var at := badge.size / 2.0
	badge.draw_circle(at, 12.0, Palette.SURFACE)
	badge.draw_arc(at, 12.0, 0.0, TAU, 32, color, 1.5, true)
	badge.draw_arc(at + Vector2(0, -2.5), 4.0, PI, TAU, 12, color, 1.8, true)
	badge.draw_rect(Rect2(at + Vector2(-6, -2.5), Vector2(12, 9)), color)


func _on_card(card: Control, event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT:
		_menu_task = card.task_id
		_menu.position = Vector2i(DisplayServer.mouse_get_position())
		_menu.popup()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.double_click:
		_pressed = null
		task_requested.emit(card.task_id)
	else:
		# Ob daraus ein Klick oder ein Ziehen wird, zeigt sich in `_input`.
		_pressed = card
		_press_at = get_local_mouse_position()


## Baut nach dem Auf- oder Zufächern neu auf.
func _refan() -> void:
	_shown = 0
	_rebuild()


# ------------------------------------------------------- Abhängigkeiten

## Zeigt, worauf die Karte wartet und was auf sie wartet.
func _open_graph(id: String) -> void:
	var item = _ws.task(id)
	if item == null:
		item = _ws.milestone(id)
	if item != null:
		_graph.open(_ws, item, _project)




# ------------------------------------------------------------ Verteilen

static func _ids(tasks: Array) -> Array:
	return tasks.map(func(t: Dictionary) -> String: return t["id"])


## Gezogen wird wie am Spieltisch: die Karte selbst hängt am Zeiger und kippt
## in die Bewegungsrichtung. Ein Klick ohne Ziehen fächert auf.
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if _graph.visible:
		# Escape schließt den Graphen.
		if event.is_action_pressed("ui_cancel"):
			_graph.close()
			get_viewport().set_input_as_handled()
		return
	if _pressed != null and not is_instance_valid(_pressed):
		_pressed = null
	if _pressed == null and _flying == null:
		return

	# Escape bricht das Ziehen ab: ohne Ziel fliegt die Karte zurück in ihr Fach.
	if _flying != null and event.is_action_pressed("ui_cancel"):
		_pressed = null
		_over = null
		_drop()
		get_viewport().set_input_as_handled()
		return

	var mouse := get_local_mouse_position()
	if event is InputEventMouseMotion:
		if _flying == null and _pressed != null and mouse.distance_to(_press_at) > DRAG_START and _can_drag(_pressed.task_id):
			_start_drag(mouse)
		if _flying != null:
			_flying.position = mouse + _grab
			# Das Tempo des Zeigers bestimmt, wie weit die Karte kippt (`_process`).
			_pointer_speed = _pointer_speed.lerp(event.velocity, 0.5)
			_last_move = Time.get_ticks_msec()
			var at := get_global_mouse_position()
			# Nur ein Ordner auf einmal zeigt ein Ziel.
			_over = null
			for binder in [_left, _right]:
				if _over == null and binder.hover(at, _flying.task_id):
					_over = binder
				elif _over != binder:
					binder.end_hover()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var card := _pressed
		_pressed = null
		if _flying != null:
			_drop()
		elif card != null and not _ws.kids(card.task_id).is_empty():
			if _fanned.has(card.task_id):
				_fanned.erase(card.task_id)
			else:
				_fanned[card.task_id] = true
			_refan.call_deferred()


## Gezogen werden Karten der obersten Ebene; Unteraufgaben wandern mit ihrer Karte.
func _can_drag(id: String) -> bool:
	var t = _ws.task(id)
	return t != null and not t.get("parentId") and not _moving


## Die Karte hebt sich aus ihrem Fach: eine Kopie hängt am Zeiger, im Fach
## bleibt ein blasses Abbild.
func _start_drag(mouse: Vector2) -> void:
	_source = _left if _left.is_ancestor_of(_pressed) else _right
	var from: Rect2 = _pressed.get_global_rect()
	_flying = Card.new()
	add_child(_flying)
	_flying.show_task(_ws, _ws.task(_pressed.task_id), _images)
	_flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flying.z_index = 300
	_flying.lift = 1.0
	_size = from.size.x / Card.SIZE.x
	_flying.scale = Vector2(_size, _size)
	# Die Karte dreht und staucht sich um ihre Mitte; greifen tut man sie, wo man sie angefasst hat.
	_grab = from.get_center() - Card.SIZE / 2.0 - get_global_mouse_position()
	_flying.position = mouse + _grab
	_pointer_speed = Vector2.ZERO
	_tilt = Vector2.ZERO
	_source.ghost(_pressed.task_id, true)
	for binder in [_left, _right]:
		binder.set_dragging(true)


## Lässt die gezogene Karte in die Bewegungsrichtung kippen und richtet sie
## wieder auf, sobald der Zeiger steht – wie am Spieltisch.
func _process(delta: float) -> void:
	if _flying == null:
		return
	var k := 1.0 - exp(-delta * 1000.0 / TILT_RESPONSE_MS)
	if Time.get_ticks_msec() - _last_move > TILT_STILL_MS:
		_pointer_speed -= _pointer_speed * k
	var target := Vector2(tanh(_pointer_speed.x / TILT_SPEED), tanh(_pointer_speed.y / TILT_SPEED)) * MAX_TILT * TILT_STRENGTH
	_tilt += (target - _tilt) * k
	var squash := Vector2(cos(deg_to_rad(_tilt.x * 1.7)), cos(deg_to_rad(_tilt.y * 1.7)))
	_flying.scale = squash * 1.08 * _size
	_flying.rotation = deg_to_rad(_tilt.x) * 0.22
	_flying.set_tilt(-_tilt / MAX_TILT)


## Die Maustaste geht hoch: die Karte fliegt an ihr Ziel und liegt dort sofort;
## Tasker erfährt es gleichzeitig. Ohne Ziel fliegt sie zurück in ihr Fach.
func _drop() -> void:
	var card := _flying
	var id: String = card.task_id
	var source := _source
	var target: Dictionary = _over.drop_target() if _over != null else {}
	var in_stock := _over == _left
	_flying = null
	card.set_tilt(Vector2.ZERO)

	var move := {}
	if not target.is_empty():
		move = _move_for(id, target["section"], target["before"], in_stock)
	# Kein Ziel, oder die Karte läge dort, wo sie schon liegt: zurück ins Fach.
	if move.is_empty():
		var home = source.place_of(id)
		for binder in [_left, _right]:
			binder.end_hover()
		if home != null:
			await _fly(card, home, 1.0)
		else:
			# Ihr Fach ist nicht aufgeschlagen: sie löst sich einfach auf.
			await card.create_tween().tween_property(card, "modulate:a", 0.0, FLY_SECONDS).finished
		source.ghost(id, false)
		for binder in [_left, _right]:
			binder.clear_drag()
		card.queue_free()
		return

	# Erst fliegt die Karte in die Lücke, dann steht der Ordner schon im neuen Stand.
	# In ein Registerblatt schrumpft sie hinein.
	var small := 0.25 if target["into_tab"] else 1.0
	var spot: Vector2 = target["at"] - (Card.SIZE * _size * small / 2.0 if target["into_tab"] else Vector2.ZERO)
	await _fly(card, spot, small)
	# Der Ordner wird gleich im neuen Stand aufgebaut – ohne Abbild und ohne Marke.
	for binder in [_left, _right]:
		binder.clear_drag()
	_moving = true
	var landed := func() -> void:
		card.queue_free()
		(_left if in_stock else _right).land(id)
	store.changed.connect(landed, CONNECT_ONE_SHOT)
	var res := await store.move(id, move["body"], move["local"])
	if store.changed.is_connected(landed):
		store.changed.disconnect(landed)
	if is_instance_valid(card):
		card.queue_free()
	if not res["ok"]:
		# Der Stand ist wieder der alte: die Karte fliegt von dort zurück, wo sie lag.
		_say(str(res["error"]))
		await _fly_back(source, id, spot, small)
	_moving = false


## Ein Zug ging nicht: die Karte fliegt von dort, wo sie abgelegt wurde, zurück
## in ihr Fach. Sie fliegt über dem Fenster – im Ordner würde sie an dessen
## Rand abgeschnitten.
func _fly_back(source: Binder, id: String, from: Vector2, small: float) -> void:
	var home = source.place_of(id)
	if home == null or _ws.task(id) == null:
		return
	var card := Card.new()
	add_child(card)
	card.show_task(_ws, _ws.task(id), _images)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 300
	card.scale = Vector2(_size, _size) * small
	card.position = from - (Card.SIZE - Card.SIZE * _size * small) / 2.0
	source.ghost(id, true)
	var back: Tween = card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	back.tween_property(card, "position", home - (Card.SIZE - Card.SIZE * _size) / 2.0, BACK_SECONDS)
	back.tween_property(card, "scale", Vector2(_size, _size), BACK_SECONDS)
	await back.finished
	source.ghost(id, false)
	card.queue_free()


## Bewegt die fliegende Karte an eine Stelle des Fensters.
func _fly(card: Control, to: Vector2, shrink: float) -> void:
	for binder in [_left, _right]:
		if binder != _over:
			binder.end_hover()
	var tween := card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", to - (Card.SIZE - Card.SIZE * _size * shrink) / 2.0, FLY_SECONDS)
	tween.tween_property(card, "scale", Vector2(_size, _size) * shrink, FLY_SECONDS)
	tween.tween_property(card, "rotation", 0.0, FLY_SECONDS)
	tween.tween_property(card, "lift", 0.0, FLY_SECONDS)
	await tween.finished


## Was aus dem Ablegen wird: `{ body, local }` für `Store.move` – leer, wenn
## sich nichts ändern würde oder nichts verschoben werden kann.
func _move_for(task_id: String, section: int, before_id: String, in_stock: bool) -> Dictionary:
	var sections := _stock_sections if in_stock else _deck_sections
	if section < 0 or section >= sections.size() or not sections[section].has("place"):
		return {}
	# Im Fach kann eine aufgefächerte Unteraufgabe stecken – gemeint ist dann ihre Karte.
	var before = _ws.task(before_id) if before_id != "" else null
	var roots: Array = sections[section]["roots"]
	var index := Planning.drop_index(roots, task_id, _ws.root(before)["id"] if before != null else "")
	if Planning.stays(roots, task_id, index):
		return {}
	if store == null or store.state != "ready":
		_say("Das sind Beispieldaten – ohne Verbindung zu Tasker wird nichts verschoben.")
		return {}
	var place: Dictionary = sections[section]["place"]
	return {"body": Planning.move_body(place, index), "local": Planning.local_move(roots, task_id, place, index)}


## Zeigt kurz, warum etwas nicht ging.
func _say(text: String) -> void:
	_note.text = text
	if _note_tween != null:
		_note_tween.kill()
	_note.modulate.a = 1.0
	_note_tween = create_tween()
	_note_tween.tween_interval(4.0)
	_note_tween.tween_property(_note, "modulate:a", 0.0, 0.6)
