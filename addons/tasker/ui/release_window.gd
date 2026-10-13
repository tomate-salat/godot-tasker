@tool
extends "card_window.gd"
## Ein Release in einem eigenen Fenster: Stand, Fortschritt, die Kanäle, auf
## denen es veröffentlicht wird, die Einleitung fürs Changelog und seine
## Milestones.
##
## Alles ist Anzeige – Releases liest das Addon nur (`rules/release.gd`).

## Ein Milestone des Releases soll geöffnet werden.
signal task_requested(task_id: String)
## Ein Bild aus der Beschreibung soll groß gezeigt werden.
signal image_requested(key: String, title: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Description := preload("description.gd")
const Model := preload("../rules/model.gd")
const Progress := preload("../rules/progress.gd")
const Release := preload("../rules/release.gd")
const Burnup := preload("../rules/burnup.gd")

var store: Store
var images: Images
## Die ID des Releases – heißt wie bei den anderen Fenstern, damit alle gleich geöffnet werden.
var task_id := ""

var _done := 0
var _total := 0

var _crumb: Label
var _status: Label
var _bar: Control
var _count: Label
var _title: Label
var _stages_head: Label
var _stages: VBoxContainer
var _desc: Description
var _milestones_head: Label
var _milestones: VBoxContainer


func _init() -> void:
	super()
	size = Vector2i(600, 760)
	min_size = Vector2i(420, 320)
	close_requested.connect(shut)
	_build()


func _ready() -> void:
	_desc.store = store
	_desc.images = images
	if store != null:
		store.changed.connect(refresh)
	refresh()


## Zeigt den aktuellen Stand. Gibt es das Release nicht mehr, schließt sich das Fenster.
func refresh() -> void:
	var r = store.ws.release(task_id) if store != null else null
	if r == null:
		queue_free()
		return
	var ws := store.ws
	var project = ws.project(r.get("projectId"))
	var state := Release.status(ws, r)
	title = "★ %s" % Release.label(r)
	_crumb.text = "%s › Releases › Release" % (project["name"] if project != null else "?")
	_title.text = Release.label(r)
	_status.text = "%s%s" % [Release.LABEL[state], "  ·  archiviert" if Model.is_archived(r) else ""]
	_status.add_theme_color_override("font_color", Palette.OK if state == Release.RELEASED or state == Release.READY else Palette.P2 if state == Release.PROGRESS else Palette.MUTED)

	var milestones := ws.release_milestones(task_id)
	_done = 0
	_total = 0
	for m in milestones:
		var stats := Progress.milestone_stats(ws, m)
		_done += stats["done"]
		_total += stats["total"]
	_count.text = "%d/%d Aufgaben" % [_done, _total]
	_bar.queue_redraw()

	for c in _stages.get_children():
		c.queue_free()
	var stages := Model.stable_sort(ws.release_stages(task_id), func(a: Dictionary, b: Dictionary) -> bool: return a.get("order", 0) < b.get("order", 0))
	var out := stages.filter(func(s: Dictionary) -> bool: return s.get("doneAt") != null).size()
	_stages_head.text = "Kanäle · %d/%d veröffentlicht" % [out, stages.size()] if stages.size() > 0 else "Kanäle · keine"
	for s in stages:
		_stages.add_child(_stage_row(s))

	var text: String = str(r.get("desc", "")).strip_edges()
	_desc.visible = text != ""
	# Ohne Besitzer: die Einleitung wird hier nur gelesen, Kästchen darin nicht umgeschaltet.
	_desc.show_text(text, "releaseId", "")

	for c in _milestones.get_children():
		c.queue_free()
	var finished := milestones.filter(func(m: Dictionary) -> bool: return Progress.milestone_done(ws, m)).size()
	_milestones_head.text = "Milestones · %d/%d fertig" % [finished, milestones.size()]
	for m in milestones:
		_milestones.add_child(_milestone_row(m, r))
	if milestones.is_empty():
		var none := Label.new()
		none.text = "Diesem Release ist noch kein Milestone zugeordnet."
		none.add_theme_color_override("font_color", Palette.MUTED)
		_milestones.add_child(none)


func _stage_row(s: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var done: bool = s.get("doneAt") != null
	var mark := Label.new()
	mark.text = "✓" if done else "○"
	mark.add_theme_color_override("font_color", Palette.OK if done else Palette.MUTED)
	row.add_child(mark)
	var name := Label.new()
	name.text = str(s.get("name", "")) if str(s.get("name", "")) != "" else "Ohne Namen"
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name)
	var when := Label.new()
	when.text = "veröffentlicht am %s" % Burnup.format_day(Burnup.day_of_date(s["doneAt"]), true) if done else "offen"
	when.add_theme_color_override("font_color", Palette.MUTED)
	row.add_child(when)
	return row


func _milestone_row(m: Dictionary, r: Dictionary) -> Control:
	var ws := store.ws
	var stats := Progress.milestone_stats(ws, m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var open := Button.new()
	open.flat = true
	open.alignment = HORIZONTAL_ALIGNMENT_LEFT
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.clip_text = true
	open.icon = Palette.status_icon("done" if Progress.milestone_done(ws, m) else m.get("status"))
	open.text = "◆ %s" % (m["title"] if m.get("title") else "Ohne Titel")
	open.tooltip_text = "Milestone öffnen"
	if Progress.milestone_done(ws, m):
		open.add_theme_color_override("font_color", Palette.FAINT)
	open.pressed.connect(func() -> void: task_requested.emit(m["id"]))
	row.add_child(open)
	# Zum Release zählt auch, was es nur über Abhängigkeiten braucht.
	if m.get("releaseId") != r["id"]:
		var via := Label.new()
		via.text = "über Abhängigkeit"
		via.tooltip_text = "Dem Release nicht selbst zugeordnet – ein Milestone des Releases wartet auf ihn."
		via.add_theme_color_override("font_color", Palette.MUTED)
		row.add_child(via)
	var count := Label.new()
	count.text = "%d/%d" % [stats["done"], stats["total"]]
	count.add_theme_color_override("font_color", Palette.MUTED)
	row.add_child(count)
	return row


# ------------------------------------------------------------- Aufbau

func _build() -> void:
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 0)
	face.add_child(rows)

	# Der Kopf bleibt stehen, wenn der Rest rollt – an ihm greift man die Karte.
	var head_margin := MarginContainer.new()
	for side in ["left", "right", "top"]:
		head_margin.add_theme_constant_override("margin_" + side, 16)
	head_margin.add_theme_constant_override("margin_bottom", 0)
	rows.add_child(head_margin)
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	head_margin.add_child(head)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 10)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var top := HBoxContainer.new()
	head.add_child(top)
	_crumb = Label.new()
	_crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumb.clip_text = true
	_crumb.add_theme_color_override("font_color", Palette.MUTED)
	top.add_child(_crumb)
	var browser := Button.new()
	browser.text = "In Tasker öffnen"
	browser.tooltip_text = "Öffnet die Releases des Projekts in Tasker – im Browser oder in der installierten App, je nach Einstellung"
	browser.pressed.connect(func() -> void:
		var r = store.ws.release(task_id)
		if r != null:
			store.open_releases(r["projectId"]))
	top.add_child(browser)
	top.add_child(pin_button())
	top.add_child(close_button())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	head.add_child(grid)
	_status = Label.new()
	_prop(grid, "Stand", _status)
	var progress_row := HBoxContainer.new()
	progress_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	progress_row.add_theme_constant_override("separation", 10)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(120, 8)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	progress_row.add_child(_bar)
	_count = Label.new()
	_count.add_theme_color_override("font_color", Palette.MUTED)
	progress_row.add_child(_count)
	_prop(grid, "Fortschritt", progress_row)

	head.add_child(HSeparator.new())

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

	box.add_child(HSeparator.new())
	_milestones_head = _heading("Milestones")
	box.add_child(_milestones_head)
	_milestones = VBoxContainer.new()
	_milestones.add_theme_constant_override("separation", 0)
	box.add_child(_milestones)

	box.add_child(HSeparator.new())
	_stages_head = _heading("Kanäle")
	box.add_child(_stages_head)
	_stages = VBoxContainer.new()
	_stages.add_theme_constant_override("separation", 4)
	box.add_child(_stages)


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


func _draw_bar() -> void:
	_bar.draw_rect(Rect2(Vector2.ZERO, _bar.size), Color(Palette.INK, 0.12))
	if _total > 0:
		_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(_bar.size.x * _done / _total, _bar.size.y)), Palette.OK)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		shut()
