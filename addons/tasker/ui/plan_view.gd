@tool
extends Control
## Planen am Tisch: ein aufgeschlagener Sammelordner. Auf der linken Seite
## steckt der Vorrat – „Ready“ oder „Backlog“ –, auf der rechten die Decks,
## die eingeplanten Milestones, je Milestone eigene Seiten. Dazwischen die
## Ringe. Geblättert wird auf jeder Seite für sich (`binder.gd`).
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

const MARGIN := 28.0
const HEADER := 60.0
## Über dem Ordner stehen die Reiter, die den Vorrat wählen.
const TOP := 44.0
## Zwischen den beiden Seiten liegt die Mechanik mit den Ringen.
const SPINE := 22.0
## Breiter als so werden die Registerblätter auch in einem breiten Fenster nicht.
const TAB_MAX := 190.0
const COVER := Color("101614")
const METAL := Color("59645f")
const SHINE := Color("c3cdc8")

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

var _cover: Control
var _tabs := {}
var _tab_box: HBoxContainer
var _left: Binder
var _right: Binder
var _rings: Control
var _info: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var felt := ColorRect.new()
	felt.color = Palette.FELT
	felt.set_anchors_preset(Control.PRESET_FULL_RECT)
	felt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(felt)

	# Der Deckel liegt unter beiden Seiten.
	_cover = Control.new()
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.draw.connect(_draw_cover)
	add_child(_cover)

	_left = Binder.new()
	_left.left_side = true
	add_child(_left)
	_right = Binder.new()
	_right.break_pages = true
	_right.header_pressed.connect(func(id: String) -> void: task_requested.emit(id))
	add_child(_right)

	# Die Ringe gehen durch beide Seiten und liegen deshalb über ihnen.
	_rings = Control.new()
	_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rings.draw.connect(_draw_rings)
	add_child(_rings)

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

	resized.connect(_on_resized)


## Zeigt den Stand. `today` ist die Tagesnummer von heute (`Burnup.day_of`).
func show_plan(ws: Workspace, project_id: String, velocity: int, images: Node, today: int) -> void:
	_ws = ws
	_project = project_id
	_velocity = velocity
	_images = images
	_today = today
	_info.text = "Tempo: %d Karten je Woche   ·   Klick fächert Unteraufgaben auf, Doppelklick öffnet" % velocity
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
	# Beide Seiten sind gleich breit; in ein schmales Fenster passen nur zwei Spalten.
	var room := size.x - MARGIN * 2.0 - SPINE
	var columns := 3 if room >= (Binder.sheet_width(3) + Binder.TAB_OUT) * 2.0 else 2
	var sheet := Binder.sheet_width(columns)
	# Was an Breite übrig ist, bekommen die Registerblätter, damit ihre Namen passen.
	var tab_out := clampf((room - sheet * 2.0) / 2.0, Binder.TAB_OUT, TAB_MAX)
	var tall := size.y - HEADER - TOP - 14.0
	var left_x := roundf((size.x - (sheet * 2.0 + SPINE + tab_out * 2.0)) / 2.0)
	var top := HEADER + TOP

	for binder in [_left, _right]:
		binder.columns = columns
		binder.tab_out = tab_out
		binder.size = Vector2(sheet + tab_out, tall)
	_left.position = Vector2(left_x, top)
	_right.position = Vector2(left_x + tab_out + sheet + SPINE, top)
	_cover.position = Vector2(_left.position.x + tab_out - 10.0, top - 8.0)
	_cover.size = Vector2(sheet * 2.0 + SPINE + 20.0, tall - Binder.FOOT + 16.0)
	_cover.queue_redraw()
	_rings.position = Vector2(_left.position.x + tab_out + sheet, top)
	_rings.size = Vector2(SPINE, tall)
	_rings.queue_redraw()
	_tab_box.position = Vector2(_left.position.x + tab_out, HEADER + 2.0)

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

## Die linke Seite: der gewählte Stapel des Vorrats, die Karten laufen durch.
func _build_stock() -> void:
	for which in _tabs:
		_tabs[which].text = "%s  %d" % ["Ready" if which == Planning.READY else "Backlog", Planning.stock_count(_ws, _project, which)]
		_tabs[which].set_pressed_no_signal(which == _stock)
	var sections := []
	for section in Planning.stock(_ws, _project, _stock):
		sections.append({"title": section["title"], "items": _items(section["cards"])})
	_left.card_maker = _card.bind(Planning.deck_order(Planning.decks(_ws, _project)))
	_left.show_sections(_stock, sections)


## Die rechte Seite: die Decks. Jeder Milestone hat sein Registerblatt und
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


# ------------------------------------------------------------ Zeichnen

## Der Deckel des Ordners, unter beiden Seiten.
func _draw_cover() -> void:
	var cover := StyleBoxFlat.new()
	cover.bg_color = COVER
	cover.border_color = Color(1, 1, 1, 0.06)
	cover.set_border_width_all(1)
	cover.set_corner_radius_all(14)
	cover.shadow_color = Color(0, 0, 0, 0.4)
	cover.shadow_size = 10
	cover.shadow_offset = Vector2(0, 4)
	_cover.draw_style_box(cover, Rect2(Vector2.ZERO, _cover.size))


## Die Mechanik in der Mitte: eine Schiene, und die Ringe, die im Bogen von
## einer Seite durch die Löcher der anderen gehen.
func _draw_rings() -> void:
	var middle := SPINE / 2.0
	var bottom := _rings.size.y - Binder.FOOT
	_rings.draw_rect(Rect2(middle - 6.0, 10.0, 12.0, bottom - 20.0), Color("2b3431"))
	_rings.draw_rect(Rect2(middle - 6.0, 10.0, 3.0, bottom - 20.0), Color(1, 1, 1, 0.08))
	_rings.draw_rect(Rect2(middle + 4.0, 10.0, 2.0, bottom - 20.0), Color(0, 0, 0, 0.35))
	for y in Binder.ring_heights(_rings.size.y):
		# Ein Ring von oben gesehen: ein flacher Bogen über die Mitte, bis in die Löcher.
		var reach := middle + 14.0
		var arc := PackedVector2Array()
		for i in 17:
			var a := PI * i / 16.0
			arc.append(Vector2(middle - cos(a) * reach, y - sin(a) * 9.0))
		_rings.draw_polyline(arc, Color(0, 0, 0, 0.45), 8.0, true)
		_rings.draw_polyline(arc, METAL, 5.0, true)
		_rings.draw_polyline(arc.slice(3, 10), SHINE, 1.5, true)
		for rivet in [-18.0, 18.0]:
			_rings.draw_circle(Vector2(middle, y + rivet), 2.5, Color("8d9a95"))


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
		badge.set_anchors_preset(Control.PRESET_FULL_RECT)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.draw.connect(_draw_lock.bind(badge))
		card.add_child(badge)
		var names := Planning.card_blockers(_ws, t).map(func(b: Dictionary) -> String: return str(b["title"]) if b.get("title") else "Ohne Titel")
		card.tooltip_text += "\nWartet auf: %s" % ", ".join(names)
		if lock == Planning.MISPLACED:
			card.tooltip_text += "\nDavon liegt etwas in einem späteren Deck oder noch im Vorrat."
	return card


## Das Schloss an einer gesperrten Karte, rechts in ihrem sichtbaren Streifen:
## gelb, wenn sie wartet, rot, wenn das, worauf sie wartet, später oder gar
## nicht eingeplant ist.
func _draw_lock(badge: Control) -> void:
	var color: Color = Palette.P1 if badge.get_meta("lock") == Planning.MISPLACED else Palette.P2
	var at := Vector2(badge.size.x - 20.0, 20.0)
	badge.draw_circle(at, 12.0, Palette.SURFACE)
	badge.draw_arc(at, 12.0, 0.0, TAU, 32, color, 1.5, true)
	badge.draw_arc(at + Vector2(0, -2.5), 4.0, PI, TAU, 12, color, 1.8, true)
	badge.draw_rect(Rect2(at + Vector2(-6, -2.5), Vector2(12, 9)), color)


func _on_card(card: Control, event: InputEventMouseButton) -> void:
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
