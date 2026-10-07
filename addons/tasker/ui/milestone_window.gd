@tool
extends Window
## Ein Milestone in einem eigenen Fenster, nach dem Inspektor in Tasker:
## Status, Fortschritt, Zeitraum, die Beschreibung als gerendertes Markdown
## samt Zeichnungen, das Burnup-Diagramm und die Aufgaben.
##
## Alles ist Anzeige. Der Status eines Milestones wird hier bewusst nicht
## geändert: je Projekt ist nur einer aktiv, und ein Wechsel räumt den Tisch um.

## Eine Aufgabe oder ein anderer Milestone soll geöffnet werden.
signal task_requested(task_id: String)
## Ein Bild aus der Beschreibung soll groß gezeigt werden.
signal image_requested(key: String, title: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Description := preload("description.gd")
const BurnupChart := preload("burnup_chart.gd")
const Model := preload("../rules/model.gd")
const Progress := preload("../rules/progress.gd")
const Burnup := preload("../rules/burnup.gd")

var store: Store
var images: Images
## Die ID des Milestones – heißt wie beim Aufgabenfenster, damit beide gleich geöffnet werden.
var task_id := ""

var _segments: Array = []

var _crumb: Label
var _ref: Label
var _status: Label
var _status_icon: TextureRect
var _bar: Control
var _forecast: Label
var _period: Label
var _title: Label
var _desc: Description
var _burnup: VBoxContainer
var _burnup_count: Label
var _chart: BurnupChart
var _legend: RichTextLabel
var _burnup_notes: Label
var _tasks_head: Label
var _tasks: VBoxContainer


func _init() -> void:
	size = Vector2i(640, 900)
	min_size = Vector2i(420, 360)
	wrap_controls = false
	close_requested.connect(queue_free)
	_build()


func _ready() -> void:
	_desc.store = store
	_desc.images = images
	if store != null:
		store.changed.connect(refresh)
	refresh()


## Zeigt den aktuellen Stand. Gibt es den Milestone nicht mehr, schließt sich das Fenster.
func refresh() -> void:
	var m = store.ws.milestone(task_id) if store != null else null
	if m == null:
		queue_free()
		return
	var ws := store.ws
	var name: String = m["title"] if m.get("title") else "Ohne Titel"
	var project = ws.project(m.get("projectId"))
	title = "◆ $%d  %s" % [int(m.get("ref", 0)), name]
	_crumb.text = "%s › Plan › Milestone" % (project["name"] if project != null else "?")
	_ref.text = "$%d" % int(m.get("ref", 0))
	_title.text = name
	_status.text = Palette.STATUS_LABELS.get(m.get("status"), "?")
	_status_icon.texture = Palette.status_icon(m.get("status"))
	_segments = Card._sorted(Progress.status_segments(ws, m))
	_bar.queue_redraw()
	_period.text = "%s – %s" % [_date(m.get("startDate")), _date(m.get("endDate"))]
	_desc.show_text(m.get("desc"), "milestoneId", task_id)

	var stats := Progress.milestone_stats(ws, m)
	var stored: Array = store.data.get("milestoneLog", {}).get(task_id, [])
	var log := Burnup.with_now(stored if stored.size() > 0 else Burnup.backfill_log(ws, m),
		stats["total"], stats["done"], Time.get_datetime_string_from_system(true) + ".000Z")
	var d = Burnup.data(m, log, store.velocity, Time.get_unix_time_from_system(), Time.get_time_zone_from_system()["bias"])
	_show_burnup(d)

	var late: bool = d != null and d["fc_i"] != null and d["dead_i"] != null and d["fc_i"] > d["dead_i"] + 0.5
	_forecast.text = "Prognose %s" % Burnup.format_day(d["start_day"] + roundi(d["fc_i"])) if d != null and d["fc_i"] != null else ""
	_forecast.add_theme_color_override("font_color", Palette.P1 if late else Palette.MUTED)

	for c in _tasks.get_children():
		c.queue_free()
	var roots := ws.ms_counted(m)
	var done_roots := roots.filter(func(r: Dictionary) -> bool: return Progress.all_done(ws, r)).size()
	_tasks_head.text = "Tasks · %d/%d" % [done_roots, roots.size()]
	for r in roots:
		_tasks.add_child(_task_row(r))


func _show_burnup(d: Variant) -> void:
	_burnup.visible = d != null
	if d == null:
		return
	_chart.data = d
	_burnup_count.text = "%d von %d Aufgaben erledigt" % [d["dn"], d["s"]]
	var legend := "[color=#%s]━[/color] Committed    [color=#%s]━[/color] Erledigt" % [Palette.MUTED.to_html(false), Palette.ACCENT.to_html(false)]
	if d["fc_i"] != null:
		legend += "    [color=#%s]╌╌[/color] Prognose %s" % [Palette.ACCENT.to_html(false), Burnup.format_day(d["start_day"] + roundi(d["fc_i"]))]
	_legend.text = legend

	var notes := PackedStringArray()
	if d["added"] > 0 or d["removed"] > 0:
		var parts := PackedStringArray()
		if d["added"] > 0:
			parts.append("+%d %s hinzugekommen" % [d["added"], "Aufgabe" if d["added"] == 1 else "Aufgaben"])
		if d["removed"] > 0:
			parts.append("−%d %s entfernt" % [d["removed"], "Aufgabe" if d["removed"] == 1 else "Aufgaben"])
		notes.append("Seit Start %s." % ", ".join(parts))
	if d["fc_i"] != null and d["dead_i"] != null and d["fc_i"] > d["dead_i"] + 0.5:
		notes.append("Die Prognose liegt %d Tage nach dem Enddatum." % roundi(d["fc_i"] - d["dead_i"]))
	_burnup_notes.text = "\n".join(notes)
	_burnup_notes.visible = notes.size() > 0


func _task_row(t: Dictionary) -> Control:
	var ws := store.ws
	var done := Progress.all_done(ws, t)
	var row := HBoxContainer.new()
	var open := Button.new()
	open.flat = true
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.clip_text = true
	open.icon = Palette.status_icon(t.get("status"))
	var mark = ws.mark(t.get("markId"))
	open.text = ("%s " % mark["emoji"] if mark != null else "") + (t["title"] if t.get("title") else "Ohne Titel")
	if done:
		open.add_theme_color_override("font_color", Palette.FAINT)
	open.pressed.connect(func() -> void: task_requested.emit(t["id"]))
	row.add_child(open)
	if ws.counted_kids(t["id"]).size() > 0:
		var count := Label.new()
		count.text = "%d/%d" % [Progress.done_count(ws, t), Progress.total(ws, t)]
		count.add_theme_color_override("font_color", Palette.MUTED)
		row.add_child(count)
	return row


static func _date(iso: Variant) -> String:
	return Burnup.format_day(Burnup.day_of_date(iso), true) if iso else "offen"


# ------------------------------------------------------------- Aufbau

func _build() -> void:
	var back := PanelContainer.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	back.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	_crumb = Label.new()
	_crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumb.clip_text = true
	_crumb.add_theme_color_override("font_color", Palette.MUTED)
	top.add_child(_crumb)
	_ref = Label.new()
	_ref.add_theme_color_override("font_color", Palette.MUTED)
	top.add_child(_ref)
	var browser := Button.new()
	browser.text = "In Tasker öffnen"
	browser.tooltip_text = "Öffnet den Milestone in der Web-App im Browser"
	browser.pressed.connect(func() -> void:
		var m = store.ws.milestone(task_id)
		if m != null:
			OS.shell_open(store.web_url(m)))
	top.add_child(browser)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)

	var status_row := HBoxContainer.new()
	_status_icon = TextureRect.new()
	_status_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	status_row.add_child(_status_icon)
	_status = Label.new()
	status_row.add_child(_status)
	_prop(grid, "Status", status_row)

	var progress_row := HBoxContainer.new()
	progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.add_theme_constant_override("separation", 10)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(120, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	progress_row.add_child(_bar)
	_forecast = Label.new()
	progress_row.add_child(_forecast)
	_prop(grid, "Fortschritt", progress_row)

	_period = Label.new()
	_prop(grid, "Zeitraum", _period)

	box.add_child(HSeparator.new())

	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_override("font", Palette.title_font())
	_title.add_theme_font_size_override("font_size", 24)
	box.add_child(_title)

	_desc = Description.new()
	_desc.fit_content = true
	_desc.scroll_active = false
	_desc.target_requested.connect(func(id: String) -> void: task_requested.emit(id))
	_desc.image_requested.connect(func(key: String, name: String) -> void: image_requested.emit(key, name))
	box.add_child(_desc)

	_burnup = VBoxContainer.new()
	box.add_child(_burnup)
	_burnup.add_child(HSeparator.new())
	var burnup_head := HBoxContainer.new()
	_burnup.add_child(burnup_head)
	var burnup_title := _heading("Burnup")
	burnup_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	burnup_head.add_child(burnup_title)
	_burnup_count = Label.new()
	_burnup_count.add_theme_color_override("font_color", Palette.MUTED)
	burnup_head.add_child(_burnup_count)
	_chart = BurnupChart.new()
	_burnup.add_child(_chart)
	_legend = RichTextLabel.new()
	_legend.bbcode_enabled = true
	_legend.fit_content = true
	_legend.scroll_active = false
	_burnup.add_child(_legend)
	_burnup_notes = Label.new()
	_burnup_notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_burnup_notes.add_theme_color_override("font_color", Palette.MUTED)
	_burnup.add_child(_burnup_notes)

	box.add_child(HSeparator.new())
	_tasks_head = _heading("Tasks")
	box.add_child(_tasks_head)
	_tasks = VBoxContainer.new()
	_tasks.add_theme_constant_override("separation", 0)
	box.add_child(_tasks)


func _prop(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	l.add_theme_color_override("font_color", Palette.MUTED)
	grid.add_child(l)
	grid.add_child(control)


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", Palette.MUTED)
	l.add_theme_font_override("font", Palette.title_font())
	return l


## Der Fortschritt als Balken aus einem Segment je Aufgabe, wie an der Karte.
func _draw_bar() -> void:
	var n := _segments.size()
	var back := Color(Palette.INK, 0.12)
	if n == 0:
		_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), back)
		return
	var gap := 2.0 if n <= 40 else 0.0
	var w := (_bar.size.x - gap * (n - 1)) / n
	for i in n:
		var s: Dictionary = _segments[i]
		var color := back
		if s["kind"] == "checklist":
			if s["done"]:
				color = Palette.OK
		elif s["status"] != "open":
			color = Palette.status_color(s["status"])
		_bar.draw_rect(Rect2(i * (w + gap), 0.0, maxf(w, 1.0), _bar.size.y), color)


## Escape schließt das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
