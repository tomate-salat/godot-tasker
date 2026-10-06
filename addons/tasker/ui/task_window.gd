@tool
extends Window
## Eine Aufgabe in einem eigenen Fenster: Titel, Status, Prio, die
## Beschreibung als gerendertes Markdown und die Unteraufgaben.
##
## Je Aufgabe gibt es höchstens ein Fenster – wer es öffnet, steht in
## `plugin.gd`. Titel und Beschreibung sind vorerst nur Anzeige.

## Eine andere Aufgabe soll geöffnet werden: ein Verweis oder eine Unteraufgabe.
signal task_requested(task_id: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Palette := preload("palette.gd")
const Results := preload("results.gd")
const Markdown := preload("markdown.gd")
const Model := preload("../rules/model.gd")
const Tisch := preload("../rules/tisch.gd")
const Progress := preload("../rules/progress.gd")

var store: Store
var images: Images
var task_id := ""

## Bilder, die sich nicht laden ließen – damit nicht endlos neu versucht wird.
var _missing_images := {}

var _crumb: Label
var _ref: Label
var _title: Label
var _props: HBoxContainer
var _status: OptionButton
var _prio: OptionButton
var _prio_label: Label
var _message: Label
var _desc: RichTextLabel
var _kids: VBoxContainer


func _init() -> void:
	size = Vector2i(620, 720)
	min_size = Vector2i(360, 320)
	wrap_controls = false
	close_requested.connect(queue_free)
	_build()


func _ready() -> void:
	if store != null:
		store.changed.connect(refresh)
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
	_render_desc(t)

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

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Palette.P2)
	_message.visible = false
	box.add_child(_message)

	box.add_child(HSeparator.new())

	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.selection_enabled = true
	_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_desc.custom_minimum_size.y = 80
	_desc.meta_clicked.connect(_on_link)
	box.add_child(_desc)

	_kids = VBoxContainer.new()
	_kids.add_theme_constant_override("separation", 0)
	box.add_child(_kids)


# ------------------------------------------------------- Beschreibung

## Die Beschreibung als gerendertes Markdown, mit den Bildern aus der Galerie.
func _render_desc(t: Dictionary) -> void:
	_desc.clear()
	var faint := Palette.FAINT.to_html(false)
	var bbcode := Markdown.to_bbcode(t.get("desc"), _ref_title)
	if bbcode.strip_edges() == "":
		_desc.append_text("[color=#%s]Keine Beschreibung[/color]" % faint)
		return
	var parts := bbcode.split(Markdown.IMAGE)
	for i in parts.size():
		if i % 2 == 0:
			_desc.append_text(parts[i])
			continue
		# Eine Marke des Übersetzers: ein Bild der Galerie oder eine Zeichnung.
		var mark: String = parts[i]
		var what := "Bild"
		var key := ""
		var drawing = null
		if mark.begins_with(Markdown.DRAWING):
			var name := mark.trim_prefix(Markdown.DRAWING)
			what = "Zeichnung „%s“" % name.replace("[", "[lb]")
			drawing = _drawing(t, name)
			if drawing == null:
				_desc.append_text("[color=#%s]▣ %s gibt es nicht (mehr)[/color]" % [faint, what])
				continue
			key = Images.drawing_key(drawing)
		else:
			key = Images.image_key(mark, false)

		var texture: Texture2D = images.peek_key(key) if images != null else null
		if texture != null:
			_desc.add_image(texture, mini(texture.get_width(), maxi(size.x - 60, 64)))
		elif images == null or _missing_images.has(key):
			_desc.append_text("[color=#%s]▣ %s ist leer oder nicht verfügbar[/color]" % [faint, what])
		else:
			_desc.append_text("[color=#%s]▣ %s wird geladen …[/color]" % [faint, what])
			_load_image(key, mark, drawing)


## Die Zeichnung dieses Namens an der Aufgabe – aus `drawings` im Stand.
func _drawing(t: Dictionary, name: String) -> Variant:
	for d in store.data.get("drawings", []):
		if d.get("taskId") == t["id"] and d.get("name") == name:
			return d
	return null


func _load_image(key: String, id: String, drawing: Variant) -> void:
	var texture: Texture2D
	if drawing != null:
		texture = await images.get_drawing(drawing)
	else:
		texture = await images.get_texture(id, false)
	if not is_instance_valid(self):
		return
	if texture == null:
		_missing_images[key] = true
	refresh()


## Der Titel zu einem Verweis wie `$142` – leer, wenn es das Ziel nicht gibt.
func _ref_title(number: int) -> String:
	var target = _by_ref(number)
	if target == null:
		return ""
	return target["title"] if target.get("title") else "Ohne Titel"


func _by_ref(number: int) -> Variant:
	for list in [store.ws.tasks, store.ws.milestones]:
		for x in list:
			if int(x.get("ref", 0)) == number:
				return x
	return null


## Ein Verweis öffnet die Aufgabe in ihrem Fenster, alles andere den Browser.
func _on_link(meta: Variant) -> void:
	var link := str(meta)
	if link.begins_with(Markdown.REF_SCHEME):
		var target = _by_ref(int(link.trim_prefix(Markdown.REF_SCHEME)))
		if target != null and not Model.is_milestone(target):
			task_requested.emit(target["id"])
	elif link.begins_with("http://") or link.begins_with("https://"):
		OS.shell_open(link)


# ------------------------------------------------------------- Ändern

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


## Escape schließt das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
