@tool
extends Control
## Planen als Lageplan: dieselbe Stadt wie im Feld, aber ruhig, und links die
## Reserve – alles, was noch keinem Milestone zugeteilt ist.
##
## In der Reserve stehen die Aufgaben als Zeilen mit Bild und Titel: oben die
## Bereitschaft („Ready“), darunter das Hinterland („Backlog“), gegliedert
## wie in Tasker. In der Stadt stehen Abzeichen. Wer eine Zeile greift, hält
## ihre Karte; wer sie in die Stadt zieht, teilt sie dem Milestone zu
## (der Marschbefehl): sie fliegt hinein, ihr Rahmen zerfällt, und ihr Bild
## setzt als Abzeichen auf. Ein Abzeichen zurück in die Reserve gezogen nimmt
## die Aufgabe wieder heraus.
##
## Welche Stadt zu sehen ist, wählt die Liste unten rechts.

signal task_requested(task_id: String)
signal graph_requested(task_id: String)
## Eine andere Stadt soll gezeigt werden.
signal milestone_chosen(milestone_id: String)
signal refused(text: String)

const Model := preload("../rules/model.gd")
const Planning := preload("../rules/planning.gd")
const Dependency := preload("../rules/dependency.gd")
const Progress := preload("../rules/progress.gd")
const Workspace := preload("../rules/workspace.gd")
const Palette := preload("palette.gd")
const Card := preload("card.gd")
const Inherit := preload("../rules/inherit.gd")
const FieldView := preload("field_view.gd")

const RESERVE_WIDTH := 312.0
const TOP := 58.0
## So groß ist das Titelbild in einer Zeile der Reserve, und so groß die gezogene Karte.
const THUMB := Vector2(34, 44)
const HELD := 0.62
const DRAG_START := 6.0
const FLY_SECONDS := 0.32
## So weit rollt die Reserve je Raste des Mausrads, und so schnell von selbst,
## wenn beim Ziehen der Zeiger an ihrem oberen oder unteren Rand steht.
const WHEEL := 70
## So lange dauert es, bis die Zeilen der Reserve ein- oder ausgeklappt sind.
const FOLD_SECONDS := 0.42
## So lange muss der Zeiger beim Ziehen auf einem Abschnitt ruhen, bis er aufklappt.
const HOVER_MSEC := 220
const EDGE := 46.0
const EDGE_SPEED := 520.0

## Führt einen Zug aus: `mover.call(task_id, body, local)` – was Taskers
## `/api/move` bekommt und was sich sofort am Stand ändert. Gibt `{ ok, error }`.
var mover: Callable
## Ändert Felder einer Aufgabe: `patcher.call(task_id, changes)`. Gibt `{ ok, error }`.
var patcher: Callable

var _ws: Workspace
var _project := ""
var _milestone: Variant
var _images: Node
var _field: FieldView
var _list: VBoxContainer
var _switch: VBoxContainer
var _switch_panel: PanelContainer
var _peek: Card
var _ghost: Card
var _shown_stock := ""
var _press_id := ""
var _press_at := Vector2.ZERO
var _dragging := false
## Die Aufgabe, deren Karte gerade in die Stadt fliegt.
var _pending := ""
var _search: LineEdit
var _scroll: ScrollContainer
var _undo_button: Button
## Was sich zurücknehmen lässt: je Zug `{ id, place, index, title }` – wo die Aufgabe vorher lag.
var _undo: Array = []
## Die Reserve als Ziel, solange ein Abzeichen gezogen wird, und dessen Karte am Zeiger.
var _zone: Panel
var _zone_label: Label
var _carried: Card
var _carried_id := ""
## Solange etwas gezogen wird, sind die Abschnitte der Reserve Ziele – auch
## die leeren. `_blocks` sind ihre Flächen, `_hot` die unter dem Zeiger.
var _targets := false
var _blocks: Array = []
## Der Abschnitt, der beim Ziehen aufgeklappt ist, und seit wann der Zeiger auf dem jetzigen liegt.
var _opened: PanelContainer
var _hot_since := 0
var _hot: PanelContainer


## Ein Fach, das seinen Inhalt ein- und ausklappt: `open` von 0 (zu) bis 1
## (offen). Es ist so hoch wie der gezeigte Teil des Inhalts und schneidet
## den Rest ab.
class Fold extends Container:
	var open := 1.0:
		set(value):
			open = value
			modulate.a = value
			update_minimum_size()
			queue_sort()

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _get_minimum_size() -> Vector2:
		var most := Vector2.ZERO
		for child in get_children():
			if child is Control and child.visible:
				most = most.max(child.get_combined_minimum_size())
		return Vector2(most.x, most.y * open)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_SORT_CHILDREN:
			for child in get_children():
				if child is Control:
					fit_child_in_rect(child, Rect2(0, 0, size.x, child.get_combined_minimum_size().y))


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_field = FieldView.new()
	_field.plan = true
	_field.offset_left = RESERVE_WIDTH
	_field.task_requested.connect(func(id: String) -> void: task_requested.emit(id))
	_field.graph_requested.connect(func(id: String) -> void: graph_requested.emit(id))
	_field.refused.connect(func(text: String) -> void: refused.emit(text))
	_field.released.connect(_on_badge_released)
	_field.removal_requested.connect(_unassign)
	_field.link_requested.connect(_link)
	_field.unlink_requested.connect(_unlink)
	add_child(_field)

	# Die Reserve: eine Leiste links, mit Rollbalken, wenn sie nicht reicht.
	var panel := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color("101a18")
	back.border_color = Palette.LINE_STRONG
	back.border_width_right = 1
	back.content_margin_left = 22
	back.content_margin_right = 12
	back.content_margin_top = TOP + 14.0
	back.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", back)
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_right = RESERVE_WIDTH
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	# Die Suche: filtert die Reserve und hebt in der Stadt hervor, was passt.
	_search = LineEdit.new()
	_search.placeholder_text = "Suchen …  (Strg+F)"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_text: String) -> void: _apply_search())
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 6)
	column.add_child(top_row)
	top_row.add_child(_search)
	_undo_button = Button.new()
	_undo_button.text = "↶"
	_undo_button.focus_mode = Control.FOCUS_NONE
	_undo_button.disabled = true
	_undo_button.tooltip_text = "Nichts zurückzunehmen"
	_undo_button.pressed.connect(undo)
	top_row.add_child(_undo_button)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_scroll = scroll
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)

	# Unten rechts: die Städte, zum Wechseln.
	_switch_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.06, 0.13, 0.11, 0.94)
	box.border_color = Palette.LINE_STRONG
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.set_content_margin_all(12)
	_switch_panel.add_theme_stylebox_override("panel", box)
	_switch_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_switch_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_switch_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_switch_panel.offset_right = -24
	_switch_panel.offset_bottom = -24
	# Über den Abzeichen der Stadt – die liegen sonst darauf.
	_switch_panel.z_index = 85
	add_child(_switch_panel)
	_switch = VBoxContainer.new()
	_switch.add_theme_constant_override("separation", 2)
	_switch_panel.add_child(_switch)

	_peek = Card.new()
	_peek.visible = false
	_peek.z_index = 90
	add_child(_peek)
	FieldView._no_mouse(_peek)

	# Wird ein Abzeichen gezogen, leuchtet die Reserve als Ziel.
	_zone = Panel.new()
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(0, 0, 0, 0)
	glow.border_color = Color(Palette.OK, 0.9)
	glow.set_border_width_all(2)
	_zone.add_theme_stylebox_override("panel", glow)
	_zone.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_zone.offset_right = RESERVE_WIDTH
	_zone.offset_top = TOP
	_zone.z_index = 80
	_zone.visible = false
	_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_zone)
	_zone_label = Label.new()
	_zone_label.text = "Auf einen Abschnitt ziehen"
	_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zone_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_zone_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_zone_label.offset_bottom = -6
	_zone_label.add_theme_font_override("font", Palette.title_font())
	_zone_label.add_theme_font_size_override("font_size", 13)
	_zone_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_zone_label.add_theme_constant_override("outline_size", 6)
	_zone.add_child(_zone_label)
	_carried = Card.new()
	_carried.pivot_offset = Card.SIZE / 2.0
	_carried.scale = Vector2(HELD, HELD)
	_carried.z_index = 95
	_carried.visible = false
	add_child(_carried)
	FieldView._no_mouse(_carried)


## Solange ein Abzeichen gezogen wird, zeigt die Reserve, dass man es dort
## ablegen kann. Über ihr wird aus dem Abzeichen wieder die Karte – das Feld
## schneidet an seinem Rand ab, das Abzeichen selbst wäre dort nicht zu sehen.
func _process(delta: float) -> void:
	# Am Rand der Reserve rollt sie beim Ziehen von selbst weiter.
	if _targets and is_visible_in_tree():
		var point := get_local_mouse_position()
		if point.x < RESERVE_WIDTH:
			var top := _scroll.global_position.y - global_position.y
			var bottom := top + _scroll.size.y
			if point.y < top + EDGE:
				_scroll.scroll_vertical -= int(EDGE_SPEED * delta)
			elif point.y > bottom - EDGE:
				_scroll.scroll_vertical += int(EDGE_SPEED * delta)
	var held = _field._held if _field._dragging else null
	var on := held != null and is_instance_valid(held) and is_visible_in_tree()
	# Ziele sind die Abschnitte, ob ein Abzeichen gezogen wird oder eine Zeile der Reserve.
	var any := on or (_dragging and _press_id != "")
	_zone.visible = any
	_aim(any)
	if not on:
		_carried.visible = false
		_carried_id = ""
		return
	var mouse := get_local_mouse_position()
	var over := mouse.x < RESERVE_WIDTH
	if over and _carried_id != held.task_id:
		var task = _ws.task(held.task_id)
		if task != null:
			_carried_id = held.task_id
			_carried.show_task(_ws, task, _images, false)
	_carried.visible = over and _carried_id == held.task_id
	_carried.position = mouse - Card.SIZE / 2.0


## Zeigt den Lageplan dieses Milestones (oder null) und die Reserve des Projekts.
func show_plan(ws: Workspace, project_id: String, milestone: Variant, images: Node) -> void:
	_ws = ws
	_project = project_id
	_milestone = milestone
	_images = images
	_field.show_field(ws, milestone, images)
	_apply_search()
	_show_switch()
	# Die Karte, die gerade unterwegs ist, hat jetzt ihren Platz in der Stadt.
	if _pending != "" and _field.spot_of(_pending) != null:
		_materialise()


func say(text: String, color := Palette.P2) -> void:
	_field.say(text, color)


# -------------------------------------------------------------- Reserve

## Baut die Reserve neu, wenn sich an ihr etwas geändert hat.
func _show_reserve() -> void:
	var stock := {}
	var query := _search.text.strip_edges().to_lower()
	var stamp := query
	for which in [Planning.READY, Planning.BACKLOG]:
		stock[which] = []
		# Auch leere Abschnitte: beim Ziehen sind sie Ziele, sonst bleiben sie versteckt.
		for section in Planning.stock(_ws, _project, which, true):
			# Gesucht wird im Titel, im Zeichen der Markierung und im Namen des Abschnitts.
			var hits: Array = section["cards"].filter(func(t: Dictionary) -> bool: return _matches(t, query, str(section["title"])))
			stock[which].append({"title": section["title"], "cards": hits, "place": section["place"],
				"all": section["cards"].map(func(t: Dictionary) -> String: return t["id"])})
		for section in stock[which]:
			stamp += "|" + str(section["title"])
			for t in section["cards"]:
				stamp += ",%s:%s" % [t["id"], t.get("version", 0)]
	if stamp == _shown_stock:
		return
	_shown_stock = stamp
	for child in _list.get_children():
		child.queue_free()
	_blocks = []
	_hot = null
	_peek.visible = false
	for which in [Planning.READY, Planning.BACKLOG]:
		var count := 0
		for section in stock[which]:
			count += section["cards"].size()
		_heading("Bereitschaft" if which == Planning.READY else "Hinterland", "%s · %d" % ["Ready" if which == Planning.READY else "Backlog", count], 13)
		if count == 0:
			var none := Label.new()
			none.text = "leer" if query == "" else "nichts gefunden"
			none.add_theme_color_override("font_color", Palette.FAINT)
			none.visible = not _targets
			none.set_meta("none", true)
			_list.add_child(none)
		for section in stock[which]:
			var block := PanelContainer.new()
			block.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.set_meta("place", section["place"])
			block.set_meta("ids", section["all"])
			block.set_meta("empty", section["cards"].is_empty())
			_list.add_child(block)
			_blocks.append(block)
			var column := VBoxContainer.new()
			column.add_theme_constant_override("separation", 5)
			column.mouse_filter = Control.MOUSE_FILTER_IGNORE
			block.add_child(column)
			var name := Label.new()
			name.set_meta("title", str(section["title"]).strip_edges())
			name.set_meta("count", section["all"].size())
			column.add_child(name)
			# Die Zeilen des Abschnitts liegen in einem Fach, das ein- und ausklappt.
			var fold := Fold.new()
			var rows := VBoxContainer.new()
			rows.add_theme_constant_override("separation", 5)
			rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
			fold.add_child(rows)
			column.add_child(fold)
			for t in section["cards"]:
				rows.add_child(_mini(t))
			block.set_meta("name", name)
			block.set_meta("fold", fold)
			_dress(block)
			_fold_to(block, 0.0 if _targets else 1.0, true)


## Die Fläche eines Abschnitts; unter dem Zeiger leuchtet sie beim Ziehen.
func _block_style(hot: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(Palette.OK, 0.14) if hot else Color(0, 0, 0, 0)
	box.border_color = Color(Palette.OK, 0.9) if hot else Color(Palette.OK, 0.35) if _targets else Color(0, 0, 0, 0)
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.set_content_margin_all(4)
	return box


## Der Abschnitt der Reserve unter dem Zeiger – oder null.
func _block_at(global_point: Vector2) -> PanelContainer:
	for block in _blocks:
		if is_instance_valid(block) and block.get_global_rect().has_point(global_point):
			return block
	return null


## Gibt einem Abschnitt das Aussehen für den Zustand der Reserve: sonst mit
## seinen Zeilen, beim Ziehen als Ziel mit Name und Anzahl.
func _dress(block: PanelContainer) -> void:
	var name: Label = block.get_meta("name")
	var empty: bool = block.get_meta("empty")
	name.text = "%s  ·  %d" % [name.get_meta("title"), name.get_meta("count")] if _targets else str(name.get_meta("title"))
	name.add_theme_font_size_override("font_size", 13 if _targets else 11)
	name.add_theme_color_override("font_color", Palette.INK if _targets else Palette.MUTED)
	block.add_theme_stylebox_override("panel", _block_style(block == _hot))
	block.custom_minimum_size.y = 34.0 if _targets else 0.0
	# Leere Abschnitte gibt es nur als Ziel.
	block.visible = _targets or not empty


## Klappt die Zeilen eines Abschnitts weich auf (1) oder zu (0); dabei werden
## sie durchsichtig. `now` setzt es ohne Bewegung.
func _fold_to(block: PanelContainer, want: float, now := false) -> void:
	var fold: Fold = block.get_meta("fold")
	var old: Variant = block.get_meta("tween") if block.has_meta("tween") else null
	if old is Tween and old.is_valid():
		old.kill()
	if now:
		fold.open = want
		return
	var tween := fold.create_tween()
	tween.tween_property(fold, "open", want, FOLD_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	block.set_meta("tween", tween)


## Schaltet die Ziele der Reserve ein oder aus und hebt das unter dem Zeiger
## hervor. Beim Ziehen klappen alle Abschnitte ein; nur der unter dem Zeiger
## geht wieder auf, sobald der Zeiger einen Moment auf ihm ruht.
func _aim(on: bool) -> void:
	if on != _targets:
		_targets = on
		# Der Abschnitt, in dem das Ziehen beginnt, bleibt offen: er klappt erst
		# ein, wenn die Karte ihn verlässt.
		_opened = _block_at(get_global_mouse_position()) if on and get_local_mouse_position().x < RESERVE_WIDTH else null
		for block in _blocks:
			if is_instance_valid(block):
				_dress(block)
				_fold_to(block, 0.0 if on and block != _opened else 1.0)
		for child in _list.get_children():
			if child.has_meta("none"):
				child.visible = not on
		_peek.visible = false
	var hot := _block_at(get_global_mouse_position()) if on and get_local_mouse_position().x < RESERVE_WIDTH else null
	if hot != _hot:
		if _hot != null and is_instance_valid(_hot):
			_hot.add_theme_stylebox_override("panel", _block_style(false))
		_hot = hot
		_hot_since = Time.get_ticks_msec()
		if _hot != null:
			_hot.add_theme_stylebox_override("panel", _block_style(true))
	if on and _hot != _opened and Time.get_ticks_msec() - _hot_since > HOVER_MSEC:
		if _opened != null and is_instance_valid(_opened):
			_fold_to(_opened, 0.0)
		_opened = _hot
		if _opened != null:
			_fold_to(_opened, 1.0)


## Legt die Aufgabe in den Abschnitt der Reserve unter dem Zeiger – ans Ende.
## Ohne Abschnitt unter dem Zeiger: in die Bereitschaft. Gibt zurück, ob es
## etwas zu tun gab.
func _drop_in_reserve(id: String) -> bool:
	var task = _ws.task(id)
	if task == null:
		return false
	if task.get("parentId"):
		refused.emit("Eine Unteraufgabe bleibt bei ihrem Stapel")
		return false
	var block := _block_at(get_global_mouse_position())
	var place: Dictionary = block.get_meta("place") if block != null else _loose_place(task)
	if _roots_at(place).has(id):
		return false
	var res: Dictionary = await _go(id, place, -1)
	if not res.get("ok", false):
		refused.emit(str(res.get("error", "Das ging nicht.")))
	else:
		say("Verlegt: %s" % (task["title"] if task.get("title") else "Ohne Titel"), Palette.OK)
	return true


## Ob die Aufgabe zur Suche passt – jedes Wort der Suche muss vorkommen.
func _matches(task: Dictionary, query: String, section := "") -> bool:
	if query == "":
		return true
	var mark = _ws.mark(task.get("markId"))
	var hay := ("%s %s %s" % [task.get("title", ""), section, mark.get("name", "") if mark != null else ""]).to_lower()
	for word in query.split(" ", false):
		if not hay.contains(word):
			return false
	return true


## Wendet die Suche an: die Reserve zeigt nur Treffer, in der Stadt treten die
## Abzeichen zurück, die nicht passen.
func _apply_search() -> void:
	if _ws == null:
		return
	_show_reserve()
	var query := _search.text.strip_edges().to_lower()
	var hits := {}
	if query != "":
		for id in _field._cards:
			var task = _ws.task(id)
			if task != null and _matches(task, query):
				hits[id] = true
	_field.set_spotlight(hits, query != "")


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_F and event.ctrl_pressed:
		_search.grab_focus()
		_search.select_all()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_Z and event.ctrl_pressed and not _search.has_focus():
		undo()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _search.has_focus():
		_search.text = ""
		_search.release_focus()
		_apply_search()
		get_viewport().set_input_as_handled()


func _heading(text: String, note: String, font_size: int) -> void:
	var row := HBoxContainer.new()
	var gap := Control.new()
	gap.custom_minimum_size.y = 10.0 if font_size < 17 else 0.0
	_list.add_child(gap)
	var title := Label.new()
	title.text = text
	title.add_theme_font_override("font", Palette.title_font())
	title.add_theme_font_size_override("font_size", font_size)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	var side := Label.new()
	side.text = note
	side.add_theme_font_size_override("font_size", 11)
	side.add_theme_color_override("font_color", Palette.MUTED)
	row.add_child(side)
	_list.add_child(row)
	_list.add_child(HSeparator.new())


## Eine Aufgabe der Reserve als Zeile: links ihr Titelbild klein, daneben der
## Titel in lesbarer Größe. Verkleinerte Karten waren hier nicht zu lesen
## (Nutzer, 2026-10-12); die ganze Karte zeigt sich unter dem Zeiger.
func _mini(task: Dictionary) -> Control:
	var id: String = task["id"]
	var row := PanelContainer.new()
	var status: Variant = task.get("status")
	for state in ["panel"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("18211f")
		box.border_color = Palette.LINE_STRONG if status == "open" else Color(Palette.status_color(status), 0.7)
		box.set_border_width_all(1)
		box.border_width_left = 3
		box.set_corner_radius_all(6)
		box.content_margin_left = 6
		box.content_margin_right = 8
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		row.add_theme_stylebox_override(state, box)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)

	# Das Titelbild, beschnitten; ohne Bild ein leeres Feld in der Farbe der Fläche.
	var thumb := TextureRect.new()
	thumb.custom_minimum_size = THUMB
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	thumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumb.clip_contents = true
	line.add_child(thumb)
	var cover = Inherit.effective_cover(_ws, task)
	if cover != null and _images != null:
		_load_thumb(thumb, cover["image_id"])

	var mark = _ws.mark(task.get("markId"))
	var title := Label.new()
	title.text = "%s%s" % [str(mark["emoji"]) + " " if mark != null else "", task["title"] if task.get("title") else "Ohne Titel"]
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(title)

	# Rechts: Unteraufgaben als Zahl, wie der Stapel auf der Karte.
	var kids := _ws.kids(id).size()
	if kids > 0:
		var count := Label.new()
		count.text = "▤ %d" % kids
		count.tooltip_text = "%d Unteraufgaben" % kids
		count.add_theme_font_size_override("font_size", 11)
		count.add_theme_color_override("font_color", Palette.MUTED)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(count)

	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_press_id = id
			_press_at = get_local_mouse_position()
			_dragging = false)
	row.mouse_entered.connect(_peek_at.bind(id, row))
	row.mouse_exited.connect(func() -> void: _peek.visible = false)
	return row


func _load_thumb(thumb: TextureRect, image_id: String) -> void:
	var texture: Texture2D = await _images.get_texture(image_id, true)
	if is_instance_valid(thumb):
		thumb.texture = texture


## Zeigt die Karte unter dem Zeiger groß, rechts neben der Reserve.
func _peek_at(id: String, slot: Control) -> void:
	var task = _ws.task(id) if _ws != null else null
	if task == null or _dragging or _targets:
		return
	_peek.show_task(_ws, task, _images, true)
	var y := slot.global_position.y - global_position.y + slot.size.y / 2.0 - Card.SIZE.y / 2.0
	_peek.position = Vector2(RESERVE_WIDTH + 14.0, clampf(y, TOP + 8.0, maxf(size.y - Card.SIZE.y - 8.0, TOP + 8.0)))
	_peek.modulate.a = 1.0
	_peek.visible = true


# ------------------------------------------------------- Die Städte

func _show_switch() -> void:
	for child in _switch.get_children():
		child.queue_free()
	var decks := Planning.decks(_ws, _project)
	var rest := _ws.milestones.filter(func(m: Dictionary) -> bool:
		return m["projectId"] == _project and not m.get("planned", false) and not Model.is_archived(m))
	var all := decks + rest
	_switch_panel.visible = all.size() > 1
	var head := Label.new()
	head.text = "Stadt wechseln"
	head.add_theme_font_size_override("font_size", 11)
	head.add_theme_color_override("font_color", Palette.MUTED)
	_switch.add_child(head)
	for m in all:
		var stats := Progress.milestone_stats(_ws, m)
		var done := Progress.milestone_done(_ws, m)
		var b := Button.new()
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s %s   %d/%d" % ["✓" if done else "▶" if m.get("status") == "progress" else "◆", m["title"] if m.get("title") else "Ohne Titel", stats["done"], stats["total"]]
		b.add_theme_font_size_override("font_size", 12)
		var here: bool = _milestone != null and m["id"] == _milestone["id"]
		b.add_theme_color_override("font_color", Color.WHITE if here else Palette.OK if done else Palette.P2 if m.get("status") == "progress" else Palette.MUTED)
		if here:
			b.add_theme_font_override("font", Palette.title_font())
		var id: String = m["id"]
		b.pressed.connect(func() -> void: milestone_chosen.emit(id))
		_switch.add_child(b)


# ---------------------------------------------------------------- Züge

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	# Solange gezogen wird, hält die gegriffene Karte die Maus fest – die Liste
	# bekäme das Mausrad nicht. Darum rollt die Reserve hier von Hand.
	if _targets and event is InputEventMouseButton and event.pressed and get_local_mouse_position().x < RESERVE_WIDTH \
			and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		_scroll.scroll_vertical += -WHEEL if event.button_index == MOUSE_BUTTON_WHEEL_UP else WHEEL
		get_viewport().set_input_as_handled()
		return
	if _press_id == "":
		return
	# Escape bricht das Ziehen ab: die Karte geht zurück, nichts ändert sich.
	if _dragging and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_press_id = ""
		_dragging = false
		_field.drop_hint = false
		_drop_ghost()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mouse := get_local_mouse_position()
		if not _dragging and mouse.distance_to(_press_at) > DRAG_START:
			_start_drag()
		if _dragging and _ghost != null:
			_ghost.position = mouse - Card.SIZE / 2.0
			_ghost.rotation = clampf(event.velocity.x / 2400.0, -0.22, 0.22)
			_field.drop_hint = _milestone != null and mouse.x > RESERVE_WIDTH
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var id := _press_id
		var was_drag := _dragging
		_press_id = ""
		_dragging = false
		_field.drop_hint = false
		if not was_drag:
			task_requested.emit(id)
		elif _milestone != null and get_local_mouse_position().x > RESERVE_WIDTH:
			_assign(id)
		else:
			# Innerhalb der Reserve: in einen anderen Abschnitt verlegen.
			_drop_ghost()
			if get_local_mouse_position().x < RESERVE_WIDTH:
				_drop_in_reserve(id)


func _start_drag() -> void:
	var task = _ws.task(_press_id)
	if task == null:
		_press_id = ""
		return
	_dragging = true
	_peek.visible = false
	_ghost = Card.new()
	_ghost.pivot_offset = Card.SIZE / 2.0
	_ghost.scale = Vector2(HELD, HELD)
	_ghost.z_index = 95
	add_child(_ghost)
	FieldView._no_mouse(_ghost)
	_ghost.show_task(_ws, task, _images, false)
	_ghost.lift = 1.0


func _drop_ghost() -> void:
	if _ghost == null:
		return
	var gone := _ghost
	_ghost = null
	var tween := gone.create_tween()
	tween.tween_property(gone, "modulate:a", 0.0, 0.15)
	tween.tween_callback(gone.queue_free)


## Wo eine Wurzel-Aufgabe gerade liegt: der Ort, wie `Planning` ihn nennt.
func _place_of(task: Dictionary) -> Dictionary:
	if task.get("milestoneId"):
		return {"milestoneId": task["milestoneId"]}
	if task.get("groupId"):
		return {"groupId": task["groupId"]}
	if not task.get("ready", false):
		return {"ready": false}
	if task.get("markId"):
		return {"ready": true, "markId": task["markId"]}
	var category = _ws.category(task.get("categoryId"))
	return {"ready": true, "markId": null, "categoryId": category["id"] if category != null and category["projectId"] == _project else null}


## Die Aufgaben an einem Ort, in Reihenfolge.
func _roots_at(place: Dictionary) -> Array:
	if place.get("milestoneId"):
		var m = _ws.milestone(place["milestoneId"])
		return _ws.ms_roots(m).map(func(t: Dictionary) -> String: return t["id"]) if m != null else []
	for which in [Planning.READY, Planning.BACKLOG]:
		for section in Planning.stock(_ws, _project, which, true):
			if section["place"] == place:
				return section["cards"].map(func(t: Dictionary) -> String: return t["id"])
	return []


## Führt einen Zug aus und merkt sich, wo die Aufgabe vorher lag – für `undo`.
func _go(id: String, place: Dictionary, index: int, remember := true) -> Dictionary:
	var task = _ws.task(id)
	if task == null:
		return {"ok": false, "error": "Nicht gefunden."}
	var before := _place_of(task)
	var was_at := _roots_at(before).find(id)
	var roots := _roots_at(place).filter(func(other: String) -> bool: return other != id)
	index = clampi(index, 0, roots.size()) if index >= 0 else roots.size()
	var res: Dictionary = await mover.call(id, Planning.move_body(place, index), Planning.local_move(roots, id, place, index))
	if res.get("ok", false) and remember:
		_undo.append({"id": id, "place": before, "index": maxi(was_at, 0), "title": task["title"] if task.get("title") else "Ohne Titel"})
		if _undo.size() > 50:
			_undo.pop_front()
		_show_undo()
	return res


## Ein Abzeichen wurde auf ein anderes gelegt: das gezogene (`on_id`) blockiert
## nun das, worauf es liegt (`id`) – `id` wartet auf `on_id`.
func _link(id: String, on_id: String) -> void:
	var task = _ws.task(id)
	var on = _ws.task(on_id)
	if task == null or on == null:
		return
	var refusal := Dependency.link_refusal(_ws, task, on)
	if refusal != "":
		refused.emit(refusal)
		return
	if await _set_deps(task, Dependency.with_dep(task, on_id)):
		say("„%s“ blockiert jetzt „%s“" % [FieldView._short(on), FieldView._short(task)], Palette.OK)


## Das Kreuz auf einem Weg: `id` wartet nicht mehr auf `on_id`.
func _unlink(id: String, on_id: String) -> void:
	var task = _ws.task(id)
	if task == null:
		return
	if await _set_deps(task, Dependency.without_dep(task, on_id)):
		say("Gelöst: „%s“ blockiert „%s“ nicht mehr" % [FieldView._short(_ws.task(on_id)), FieldView._short(task)], Palette.OK)


## Setzt die Abhängigkeiten einer Aufgabe und merkt sich die alten für `undo`.
func _set_deps(task: Dictionary, deps: Array, remember := true) -> bool:
	var before: Array = task.get("deps", []).duplicate()
	var res: Dictionary = await patcher.call(task["id"], {"deps": deps})
	if not res.get("ok", false):
		refused.emit(str(res.get("error", "Das ging nicht.")))
		return false
	if remember:
		_undo.append({"id": task["id"], "deps": before, "title": task["title"] if task.get("title") else "Ohne Titel"})
		if _undo.size() > 50:
			_undo.pop_front()
		_show_undo()
	return true


## Nimmt den letzten Zug zurück: die Aufgabe liegt wieder, wo sie war, oder
## wartet wieder auf das, worauf sie vorher gewartet hat.
func undo() -> void:
	if _undo.is_empty() or _ws == null:
		return
	var step: Dictionary = _undo.pop_back()
	_show_undo()
	if _ws.task(step["id"]) == null:
		say("Die Aufgabe gibt es nicht mehr")
		return
	if step.has("deps"):
		if await _set_deps(_ws.task(step["id"]), step["deps"], false):
			say("Zurückgenommen: %s" % step["title"], Palette.OK)
		return
	var res: Dictionary = await _go(step["id"], step["place"], step["index"], false)
	if res.get("ok", false):
		say("Zurückgenommen: %s" % step["title"], Palette.OK)
	else:
		refused.emit(str(res.get("error", "Das ging nicht.")))


func _show_undo() -> void:
	_undo_button.disabled = _undo.is_empty()
	_undo_button.tooltip_text = "Nichts zurückzunehmen" if _undo.is_empty() else "Zurücknehmen (Strg+Z): %s" % _undo[_undo.size() - 1]["title"]


## Der Abschnitt der Bereitschaft, in den die Aufgabe gehört: unter ihre
## Markierung, sonst unter ihre Kategorie.
func _loose_place(task: Dictionary) -> Dictionary:
	var loose := task.duplicate()
	loose["milestoneId"] = null
	loose["groupId"] = null
	loose["ready"] = true
	return _place_of(loose)


## Der Marschbefehl: die Aufgabe kommt ans Ende des Milestones.
func _assign(id: String) -> void:
	_pending = id
	var res: Dictionary = await _go(id, {"milestoneId": _milestone["id"]}, -1)
	if not res.get("ok", false):
		_pending = ""
		_drop_ghost()
		refused.emit(str(res.get("error", "Das ging nicht.")))


## Die Karte wird zum Abzeichen: sie fliegt an ihren Platz, ihr Rahmen
## zerfällt in Splitter, und das Abzeichen setzt auf.
func _materialise() -> void:
	var id := _pending
	_pending = ""
	var spot = _field.spot_of(id)
	if _ghost == null or spot == null:
		_drop_ghost()
		_field.land(id)
		return
	_field.hold_back(id)
	var at: Vector2 = _field.position + spot
	var card := _ghost
	_ghost = null
	var tween := card.create_tween()
	tween.tween_property(card, "position", at - Card.SIZE / 2.0, FLY_SECONDS).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.parallel().tween_property(card, "rotation", 0.0, FLY_SECONDS)
	tween.parallel().tween_property(card, "scale", Vector2(0.5, 0.5), FLY_SECONDS)
	tween.tween_callback(func() -> void:
		_splinter(at)
		_field.land(id))
	tween.tween_property(card, "modulate:a", 0.0, 0.14)
	tween.parallel().tween_property(card, "scale", Vector2(0.4, 0.4), 0.14)
	tween.tween_callback(card.queue_free)


## Der Rahmen der Karte fliegt in Splittern auseinander.
func _splinter(at: Vector2) -> void:
	for k in 10:
		var angle := k * TAU / 10.0 + 0.3
		var bit := ColorRect.new()
		bit.color = Color("cfd6d2")
		bit.size = Vector2(9, 3)
		bit.pivot_offset = bit.size / 2.0
		bit.rotation = angle
		bit.z_index = 96
		bit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bit.position = at + Vector2(cos(angle) * 22.0, sin(angle) * 30.0) - bit.size / 2.0
		add_child(bit)
		var far := at + Vector2(cos(angle), sin(angle)) * (54.0 + (k % 3) * 14.0) - bit.size / 2.0
		var tween := bit.create_tween()
		tween.tween_property(bit, "position", far, 0.34).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(bit, "modulate:a", 0.0, 0.34)
		tween.tween_callback(bit.queue_free)


## Ein Abzeichen wurde losgelassen: über der Reserve geht die Aufgabe zurück
## in die Bereitschaft.
func _on_badge_released(id: String, at: Vector2) -> void:
	if _field.position.x + at.x > RESERVE_WIDTH:
		return
	_drop_in_reserve(id)


## Nimmt die Aufgabe aus dem Milestone: sie liegt danach in der Bereitschaft.
func _unassign(id: String) -> void:
	var task = _ws.task(id)
	if task == null:
		return
	if task.get("parentId"):
		refused.emit("Eine Unteraufgabe bleibt bei ihrem Stapel")
		return
	# In die Bereitschaft, unter seine Markierung oder Kategorie.
	var res: Dictionary = await _go(id, _loose_place(task), -1)
	if not res.get("ok", false):
		refused.emit(str(res.get("error", "Das ging nicht.")))
	else:
		say("Zurück in der Reserve: %s" % (task["title"] if task.get("title") else "Ohne Titel"), Palette.OK)
