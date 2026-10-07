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
	_graph.jump_requested.connect(_jump)
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
	_info.text = "Tempo: %d Karten je Woche   ·   Klick fächert auf, Doppelklick öffnet, Klick aufs Schloss zeigt die Abhängigkeiten" % velocity
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
	for section in Planning.stock(_ws, _project, _stock):
		var count: int = section["cards"].size()
		sections.append({"title": section["title"], "items": _items(section["cards"]), "header": {
			"title": section["title"], "line": "%d %s in „%s“" % [count, "Karte" if count == 1 else "Karten", "Ready" if _stock == Planning.READY else "Backlog"]}})
	if sections.is_empty():
		sections.append({"title": "Leer", "items": [], "header": {"title": "Dieser Stapel ist leer", "line": ""}})
	_left.card_maker = _card.bind(Planning.deck_order(Planning.decks(_ws, _project)))
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
			"header": {
				"id": m["id"], "title": "%s %s" % ["✓" if done else "◆", name], "line": line, "tip": tip,
				"late": f.get("late", false), "pct": Progress.milestone_progress_pct(_ws, m),
				"accent": Palette.OK if done else Palette.ACCENT if active else Palette.INK,
			},
		})
	if sections.is_empty():
		sections.append({"title": "Keine Decks", "items": [], "header": {
			"id": "", "title": "Noch kein Milestone eingeplant", "line": "Eingeplant wird in Tasker – hier erscheinen die Milestones dann als Decks.", "pct": 0}})
	# Aufgeschlagen wird zuerst das laufende Deck.
	for i in decks.size():
		if decks[i].get("status") == "progress":
			_right.start_section = i
			break
	_right.card_maker = _card.bind(Planning.deck_order(decks))
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
		task_requested.emit(card.task_id)
	elif not _ws.kids(card.task_id).is_empty():
		if _fanned.has(card.task_id):
			_fanned.erase(card.task_id)
		else:
			_fanned[card.task_id] = true
		_refan.call_deferred()


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


## Aus dem Graphen zur Karte: der Ordner blättert zu ihr, ihr Fach leuchtet auf.
func _jump(id: String) -> void:
	_graph.close()
	var decks := Planning.decks(_ws, _project)
	var order := Planning.deck_order(decks)
	if order.has(id):
		_right.reveal_section(order[id])
		return
	var t = _ws.task(id)
	if t == null:
		return
	# Im Ordner steckt die Karte der obersten Ebene; Unteraufgaben nur aufgefächert.
	var root := _ws.root(t)
	var at := Planning.place(_ws, t, order)
	if at >= 0:
		if not _right.reveal(id) and not _right.reveal(root["id"]):
			_right.reveal_section(at)
		return
	var which := Planning.READY if Planning.is_loose_root(root) and root.get("ready", false) else Planning.BACKLOG
	if which != _stock:
		_stock = which
		_shown = 0
		_rebuild()
	if not _left.reveal(id):
		_left.reveal(root["id"])


## Escape schließt den Graphen.
func _input(event: InputEvent) -> void:
	if is_visible_in_tree() and _graph.visible and event.is_action_pressed("ui_cancel"):
		_graph.close()
		get_viewport().set_input_as_handled()
