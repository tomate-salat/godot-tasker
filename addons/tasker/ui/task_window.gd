@tool
extends Window
## Eine Aufgabe in einem eigenen Fenster: Titel, Status, Prio, die
## Beschreibung als gerendertes Markdown und die Unteraufgaben.
##
## Je Aufgabe gibt es höchstens ein Fenster – wer es öffnet, steht in
## `plugin.gd`. Ein Klick auf Titel oder Beschreibung öffnet das Bearbeiten.

## Eine andere Aufgabe oder ein Milestone soll geöffnet werden: ein Verweis
## oder eine Unteraufgabe.
signal task_requested(task_id: String)
## Ein Bild aus der Beschreibung soll groß gezeigt werden.
signal image_requested(key: String, title: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Palette := preload("palette.gd")
const Results := preload("results.gd")
const Description := preload("description.gd")
const ContentEditor := preload("content_editor.gd")
const Model := preload("../rules/model.gd")
const Tisch := preload("../rules/tisch.gd")
const Progress := preload("../rules/progress.gd")
const Links := preload("../core/links.gd")
const Refs := preload("../rules/refs.gd")

## Was dieses Fenster zeigt – für das Speichern.
const KIND := "task"

var store: Store
var images: Images
var task_id := ""
## Die Verknüpfungen mit Szenen und Nodes – fehlt außerhalb des Editors.
var links: Links

var _crumb: Label
var _ref: Label
var _title: Label
var _props: HBoxContainer
var _status: OptionButton
var _prio: OptionButton
var _prio_label: Label
var _message: Label
var _desc: Description
var _editor: ContentEditor
## Was beim Bearbeiten dem Feld weicht.
var _reading: Array[Control] = []
var _kids: VBoxContainer
var _where: HFlowContainer


func _init() -> void:
	size = Vector2i(620, 720)
	min_size = Vector2i(360, 320)
	wrap_controls = false
	close_requested.connect(_close)
	_build()


func _ready() -> void:
	_desc.store = store
	_editor.store = store
	_desc.images = images
	if store != null:
		store.changed.connect(refresh)
	if links != null:
		links.memory.changed.connect(refresh)
	refresh()


## Zeigt den aktuellen Stand der Aufgabe. Gibt es sie nicht mehr, schließt
## sich das Fenster.
func refresh() -> void:
	var t = store.ws.task(task_id) if store != null else null
	if t == null:
		queue_free()
		return
	var ws := store.ws
	var name: String = t["title"] if t.get("title") else "Ohne Titel"
	title = "$%d  %s" % [int(t.get("ref", 0)), name]
	_crumb.text = Results.where(ws, t)
	_ref.text = "$%d" % int(t.get("ref", 0))
	_title.text = name
	_status.select(maxi(Model.STATUS.find(t.get("status")), 0))
	_prio.select(clampi(int(t.get("prio", 0)), 0, 3))
	# Eine Doku-Seite hat weder Status noch Priorität – der Weg in den Browser bleibt.
	for c in [_status, _prio, _prio_label]:
		c.visible = not ws.is_doc(t)
	_message.visible = _message.text != ""
	_desc.show_text(t.get("desc"), "taskId", task_id)

	# Woran die Aufgabe in Godot hängt: ein Klick springt hin.
	for c in _where.get_children():
		c.queue_free()
	var refs := links.of_task(task_id) if links != null else []
	_where.visible = not refs.is_empty()
	for ref in refs:
		var jump := Button.new()
		jump.text = "⌖ " + Refs.label(ref)
		jump.tooltip_text = "Zeig mir, wo: öffnet die Szene und wählt den Node aus"
		jump.pressed.connect(_reveal.bind(ref))
		_where.add_child(jump)

	for c in _kids.get_children():
		c.queue_free()
	var kids := ws.kids(task_id)
	if kids.size() > 0:
		var head := Label.new()
		head.text = "Unteraufgaben  %d/%d" % [Progress.done_count(ws, t), Progress.total(ws, t)]
		head.add_theme_color_override("font_color", Palette.MUTED)
		_kids.add_child(head)
	for k in kids:
		var row := Button.new()
		row.flat = true
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.icon = Palette.status_icon(k.get("status"))
		row.text = "$%d  %s" % [int(k.get("ref", 0)), k["title"] if k.get("title") else "Ohne Titel"]
		row.clip_text = true
		row.pressed.connect(func() -> void: task_requested.emit(k["id"]))
		_kids.add_child(row)


func _build() -> void:
	var back := PanelContainer.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	back.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	_crumb = Label.new()
	_crumb.clip_text = true
	_crumb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_crumb.add_theme_color_override("font_color", Palette.MUTED)
	box.add_child(_crumb)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_ref = Label.new()
	_ref.add_theme_color_override("font_color", Palette.MUTED)
	_ref.add_theme_font_size_override("font_size", 20)
	_ref.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	head.add_child(_ref)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_font_override("font", Palette.title_font())
	_title.add_theme_font_size_override("font_size", 20)
	head.add_child(_title)

	_props = HBoxContainer.new()
	box.add_child(_props)
	_status = OptionButton.new()
	for i in Model.STATUS.size():
		_status.add_icon_item(Palette.status_icon(Model.STATUS[i]), Palette.STATUS_LABELS[Model.STATUS[i]], i)
	_status.item_selected.connect(func(i: int) -> void: _change({"status": Model.STATUS[i]}))
	_props.add_child(_status)
	_prio_label = Label.new()
	_prio_label.text = "   Priorität"
	_prio_label.add_theme_color_override("font_color", Palette.MUTED)
	_props.add_child(_prio_label)
	_prio = OptionButton.new()
	for i in Palette.PRIO_LABELS.size():
		_prio.add_item(Palette.PRIO_LABELS[i], i)
	_prio.item_selected.connect(func(i: int) -> void: _change({"prio": i}))
	_props.add_child(_prio)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_props.add_child(gap)
	var browser := Button.new()
	browser.text = "In Tasker öffnen"
	browser.tooltip_text = "Öffnet die Aufgabe in der Web-App im Browser"
	browser.pressed.connect(_open_in_browser)
	_props.add_child(browser)

	_where = HFlowContainer.new()
	_where.visible = false
	box.add_child(_where)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Palette.P2)
	_message.visible = false
	box.add_child(_message)

	box.add_child(HSeparator.new())

	_desc = Description.new()
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc.custom_minimum_size.y = 80
	_desc.target_requested.connect(func(id: String) -> void: task_requested.emit(id))
	_desc.image_requested.connect(func(key: String, name: String) -> void: image_requested.emit(key, name))
	_desc.save_failed.connect(_on_desc_failed)
	_desc.edit_requested.connect(_edit)
	box.add_child(_desc)

	_editor = ContentEditor.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.closed.connect(_show_editing.bind(false))
	box.add_child(_editor)
	_reading = [_title, _desc]
	_title.mouse_filter = Control.MOUSE_FILTER_STOP
	_title.mouse_default_cursor_shape = Control.CURSOR_IBEAM
	_title.tooltip_text = "Klicken zum Bearbeiten"
	_title.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_edit())

	_kids = VBoxContainer.new()
	_kids.add_theme_constant_override("separation", 0)
	box.add_child(_kids)


## Schickt eine Änderung und sagt, wenn sie nicht greift.
func _change(changes: Dictionary) -> void:
	var t = store.ws.task(task_id)
	if t == null or changes.get("status") == t.get("status"):
		return
	# Dieselbe Regel wie in Tasker: erledigt erst, wenn alles darunter erledigt ist.
	var refusal := Tisch.done_refusal(store.ws, t) if changes.get("status") == "done" else ""
	if refusal != "":
		_message.text = refusal
		refresh()
		return
	_message.text = ""
	var res := await store.patch("task", task_id, changes)
	if not is_instance_valid(self):
		return
	_message.text = "" if res["ok"] else str(res["error"])
	refresh()


func _open_in_browser() -> void:
	var t = store.ws.task(task_id)
	if t != null:
		OS.shell_open(store.web_url(t))


func _reveal(ref: Dictionary) -> void:
	var problem: String = await links.reveal(ref)
	if is_instance_valid(self):
		_message.text = problem
		_message.visible = problem != ""



## Ein Kästchen der Beschreibung ließ sich nicht umschalten.
func _on_desc_failed(message: String) -> void:
	_message.text = message
	_message.visible = true


# ---------------------------------------------------------- Bearbeiten

## Titel und Beschreibung weichen dem Feld zum Bearbeiten.
func _edit() -> void:
	if _editor.is_open() or not _editor.open(KIND, task_id):
		return
	_show_editing(true)


func _show_editing(on: bool) -> void:
	for c in _reading:
		c.visible = not on


## Das Fenster soll zu: was getippt wurde, wird vorher übernommen. Geht das
## nicht, bleibt es offen und das Feld sagt, warum.
func _close() -> void:
	if _editor.is_open() and not await _editor.commit():
		return
	queue_free()


## Escape übernimmt beim Bearbeiten den Text (oder schließt dort nur die
## Auswahlliste) – wie in Tasker – und schließt
## sonst das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		if _editor.is_open():
			_editor.escape()
		else:
			queue_free()
