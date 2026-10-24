@tool
extends Control
## Planen auf der Ebene des Releases (Nutzer, 2026-10-24): die Feldzugskarte
## ruhig wie ein Lageplan, links als Reserve die Nebenquests – die Gruppe mit
## der Kennung `sidequest`, in Taskers Reihenfolge.
##
## Eine Zeile auf die Festung ziehen nimmt die Nebenquest in Arbeit (bei einem
## Stapel die erste bereite Unteraufgabe); gestempelt wird sie dabei am Server.
## Eine Stellung zurück in die Reserve ziehen setzt, was läuft, wieder auf
## „Bereit“ – das geht nur, solange nichts davon erledigt ist. Ziehen heißt im
## Planen also immer „hinlegen“; gearbeitet wird im Feld.

signal task_requested(task_id: String)
## Statusänderungen, die das Ziehen auslöst: `{ task_id: { status } }`.
signal changes_requested(changes: Dictionary, message: String)
signal refused(text: String)
## Eine Stadt wurde gewählt: ihr Lageplan soll aufgehen.
signal milestone_chosen(milestone_id: String)

const Model := preload("../rules/model.gd")
const Release := preload("../rules/release.gd")
const Sidequest := preload("../rules/sidequest.gd")
const Workspace := preload("../rules/workspace.gd")
const Inherit := preload("../rules/inherit.gd")
const Palette := preload("palette.gd")
const Card := preload("card.gd")
const CampaignView := preload("campaign_view.gd")
const PlanMap := preload("plan_map.gd")
const FieldView := preload("field_view.gd")

const RESERVE_WIDTH := PlanMap.RESERVE_WIDTH
const TOP := PlanMap.TOP
const THUMB := PlanMap.THUMB
const HELD := PlanMap.HELD
const DRAG_START := PlanMap.DRAG_START

var _ws: Workspace
var _project := ""
var _release: Variant
var _images: Node
var _map: CampaignView
var _list: VBoxContainer
var _count: Label
var _peek: Card
var _ghost: Card
var _zone: Panel
var _shown_stock := ""
## Was gerade gegriffen ist: eine Zeile der Reserve oder eine Stellung der Karte.
var _press_id := ""
var _press_from_map := false
var _press_at := Vector2.ZERO
var _dragging := false


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_map = CampaignView.new()
	_map.plan = true
	_map.offset_left = RESERVE_WIDTH
	_map.task_requested.connect(func(id: String) -> void: task_requested.emit(id))
	_map.release_requested.connect(func(id: String) -> void: task_requested.emit(id))
	_map.details_requested.connect(func(id: String) -> void: task_requested.emit(id))
	_map.milestone_chosen.connect(func(id: String) -> void: milestone_chosen.emit(id))
	_map.gui_input.connect(_on_map_input)
	add_child(_map)

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
	var head := HBoxContainer.new()
	column.add_child(head)
	var title := Label.new()
	title.text = "Nebenquests"
	title.add_theme_font_override("font", Palette.title_font())
	title.add_theme_font_size_override("font_size", 13)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 11)
	_count.add_theme_color_override("font_color", Palette.MUTED)
	head.add_child(_count)
	column.add_child(HSeparator.new())
	var hint := Label.new()
	hint.text = "Auf die Festung ziehen: in Arbeit für dieses Release. Eine Stellung hierher zurückziehen: wieder bereit."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Palette.FAINT)
	column.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 5)
	scroll.add_child(_list)

	_peek = Card.new()
	_peek.visible = false
	_peek.z_index = 90
	add_child(_peek)
	FieldView._no_mouse(_peek)

	# Wird eine Stellung gezogen, leuchtet die Reserve als Ziel.
	_zone = Panel.new()
	var glow := StyleBoxFlat.new()
	glow.bg_color = Color(Palette.OK, 0.06)
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


## Zeigt die Karte des Releases als Lageplan und die Nebenquests des Projekts.
func show_plan(ws: Workspace, project_id: String, release: Variant, images: Node) -> void:
	_ws = ws
	_project = project_id
	_release = release
	_images = images
	_map.show_campaign(ws, release)
	_show_reserve()


# -------------------------------------------------------------- Reserve

func _show_reserve() -> void:
	var list := Sidequest.reserve(_ws, _project, _release)
	var stamp := ",".join(PackedStringArray(list.map(func(t: Dictionary) -> String: return "%s:%s" % [t["id"], t.get("version", 0)])))
	stamp += "|%s" % (Release.sidequests(_ws, _project) != null)
	_count.text = str(list.size())
	if stamp == _shown_stock:
		return
	_shown_stock = stamp
	for child in _list.get_children():
		child.queue_free()
	_peek.visible = false
	if Release.sidequests(_ws, _project) == null:
		_list.add_child(_faint("Tasker hat noch keine Nebenquest-Gruppe angelegt."))
		return
	if list.is_empty():
		_list.add_child(_faint("Keine Nebenquests – in Tasker Aufgaben in die Gruppe legen."))
	for t in list:
		_list.add_child(_row(t))


func _faint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Palette.FAINT)
	return l


## Eine Nebenquest als Zeile, wie in der Reserve des Lageplans.
func _row(task: Dictionary) -> Control:
	var id: String = task["id"]
	var row := PanelContainer.new()
	var status: Variant = task.get("status")
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
	row.add_theme_stylebox_override("panel", box)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(line)
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
	# Rechts: welches Gerät daraus würde – größere Nebenquests, größere Stellung.
	var kind := Label.new()
	kind.text = {Sidequest.MORTAR: "Mörser", Sidequest.ROCKET: "Raketenwerfer", Sidequest.BATTERY: "Feuerstellung", Sidequest.AIRFIELD: "Flugplatz"}[Sidequest.kind_of(_ws, task)]
	kind.add_theme_font_size_override("font_size", 10)
	kind.add_theme_color_override("font_color", Palette.MUTED)
	kind.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(kind)
	row.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_press(id, false))
	row.mouse_entered.connect(_peek_at.bind(id, row))
	row.mouse_exited.connect(func() -> void: _peek.visible = false)
	return row


func _load_thumb(thumb: TextureRect, image_id: String) -> void:
	var texture: Texture2D = await _images.get_texture(image_id, true)
	if is_instance_valid(thumb):
		thumb.texture = texture


func _peek_at(id: String, slot: Control) -> void:
	var task = _ws.task(id) if _ws != null else null
	if task == null or _dragging:
		return
	_peek.show_task(_ws, task, _images, true)
	var y := slot.global_position.y - global_position.y + slot.size.y / 2.0 - Card.SIZE.y / 2.0
	_peek.position = Vector2(RESERVE_WIDTH + 14.0, clampf(y, TOP + 8.0, maxf(size.y - Card.SIZE.y - 8.0, TOP + 8.0)))
	_peek.visible = true


# ---------------------------------------------------------------- Züge

func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not event.double_click:
		var id := _map.post_at(event.position)
		if id != "":
			_press(id, true)


func _press(id: String, from_map: bool) -> void:
	_press_id = id
	_press_from_map = from_map
	_press_at = get_local_mouse_position()
	_dragging = false


func _input(event: InputEvent) -> void:
	if _press_id == "" or not is_visible_in_tree():
		return
	if _dragging and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_end_drag()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		var mouse := get_local_mouse_position()
		if not _dragging and mouse.distance_to(_press_at) > DRAG_START:
			_start_drag()
		if _dragging and _ghost != null:
			_ghost.position = mouse - Card.SIZE / 2.0
			_map.drop_hint = not _press_from_map and _over_fort()
			_zone.visible = _press_from_map
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var id := _press_id
		var was_drag := _dragging
		var from_map := _press_from_map
		_end_drag()
		var task = _ws.task(id) if _ws != null else null
		if task == null:
			return
		if not was_drag:
			# Ein Klick auf eine Zeile öffnet die Aufgabe; auf der Karte zoomt nur der Doppelklick.
			if not from_map:
				task_requested.emit(id)
			return
		if not from_map and _over_fort():
			_deploy(task)
		elif from_map and get_local_mouse_position().x < RESERVE_WIDTH:
			_withdraw(task)


func _over_fort() -> bool:
	return _map.over_fort(_map.get_local_mouse_position())


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


func _end_drag() -> void:
	_press_id = ""
	_dragging = false
	_map.drop_hint = false
	_zone.visible = false
	if _ghost != null:
		var gone := _ghost
		_ghost = null
		var tween := gone.create_tween()
		tween.tween_property(gone, "modulate:a", 0.0, 0.15)
		tween.tween_callback(gone.queue_free)


func _deploy(task: Dictionary) -> void:
	if _release == null:
		refused.emit("Es gibt kein aktives Release")
		return
	var res := Sidequest.deploy(_ws, task)
	if res["refusal"] != "":
		refused.emit(res["refusal"])
	elif not res["changes"].is_empty():
		changes_requested.emit(res["changes"], "In Arbeit für %s: %s" % [Release.label(_release), Sidequest._title(task)])


func _withdraw(task: Dictionary) -> void:
	var res := Sidequest.withdraw(_ws, task)
	if res["refusal"] != "":
		refused.emit(res["refusal"])
	elif not res["changes"].is_empty():
		changes_requested.emit(res["changes"], "Zurück in den Nebenquests: %s" % Sidequest._title(task))
