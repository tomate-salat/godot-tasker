@tool
extends MarginContainer
## Der Inhalt des Docks: der laufende Milestone als Karten und die Suche.
## Ein Doppelklick auf eine Karte öffnet die Aufgabe in ihrem eigenen Fenster.
##
## Die Abschnitte folgen den Zonen des Tischs: Gespieltes, die Hand, der
## Nachziehstapel und Gesperrtes. Gezogen und zurückgelegt wird am Tisch.

signal setup_requested
signal table_requested
## Die Aufgabe soll in ihrem Fenster gezeigt werden.
signal task_requested(task_id: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Results := preload("results.gd")
const Tisch := preload("../rules/tisch.gd")
const Search := preload("../rules/search.gd")
const Progress := preload("../rules/progress.gd")
const Model := preload("../rules/model.gd")

const MENU_OPEN := 100
const MENU_BROWSER := 101

const Hand := preload("../rules/hand.gd")
const Memory := preload("../core/memory.gd")

var store: Store
var images: Images
var memory: Memory
## Die zuletzt angeklickte Karte – sie bleibt hervorgehoben.
var selected_id := ""

## Welche Abschnitte zugeklappt sind.
var _collapsed := {"locked": true, "deck": true}
var _cards: Array = []

var _query: LineEdit
var _reload_button: Button
var _notice: VBoxContainer
var _notice_text: Label
var _notice_setup: Button
var _scroll: ScrollContainer
var _sections: VBoxContainer
var _results: ItemList
var _message: Label
var _menu: PopupMenu


func _init() -> void:
	_build()


func connect_store(new_store: Store, new_images: Images, new_memory: Memory = null) -> void:
	store = new_store
	images = new_images
	store.changed.connect(_refresh)
	store.state_changed.connect(_refresh)
	memory = new_memory
	if memory != null:
		memory.changed.connect(_refresh)
	_refresh()


## Hebt die Karte dieser Aufgabe hervor.
func select(task_id: String) -> void:
	selected_id = task_id
	for card in _cards:
		card.selected = card.task_id == task_id


# ------------------------------------------------------------- Aufbau

func _build() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	var bar := HBoxContainer.new()
	root.add_child(bar)

	_query = LineEdit.new()
	_query.placeholder_text = "Aufgabe suchen …"
	_query.clear_button_enabled = true
	_query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_query.text_changed.connect(func(_t: String) -> void: _refresh())
	bar.add_child(_query)

	_reload_button = Button.new()
	_reload_button.text = "↻"
	_reload_button.pressed.connect(func() -> void:
		if store != null:
			store.reload())
	bar.add_child(_reload_button)
	set_live(false)

	var table := Button.new()
	table.text = "Tisch"
	table.tooltip_text = "Den Tisch als eigenes Fenster öffnen"
	table.pressed.connect(func() -> void: table_requested.emit())
	bar.add_child(table)

	_notice = VBoxContainer.new()
	root.add_child(_notice)
	_notice_text = Label.new()
	_notice_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.add_child(_notice_text)
	_notice_setup = Button.new()
	_notice_setup.text = "Tasker einrichten …"
	_notice_setup.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_notice_setup.pressed.connect(func() -> void: setup_requested.emit())
	_notice.add_child(_notice_setup)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Palette.P2)
	_message.visible = false
	root.add_child(_message)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	_sections = VBoxContainer.new()
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.add_theme_constant_override("separation", 8)
	_scroll.add_child(_sections)

	_results = ItemList.new()
	_results.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_results.visible = false
	_results.item_activated.connect(func(i: int) -> void: task_requested.emit(_results.get_item_metadata(i)))
	root.add_child(_results)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)
	for i in Model.STATUS.size():
		_menu.add_icon_item(Palette.status_icon(Model.STATUS[i]), Palette.STATUS_LABELS[Model.STATUS[i]], i)
	_menu.add_separator()
	_menu.add_item("Aufgabe öffnen", MENU_OPEN)
	_menu.add_item("In Tasker öffnen (Browser)", MENU_BROWSER)


# ------------------------------------------------------------ Anzeige

func _refresh() -> void:
	if store == null:
		return
	var loaded := store.state == "ready"
	_notice.visible = not loaded
	_query.editable = loaded
	if not loaded:
		_scroll.visible = false
		_results.visible = false
		match store.state:
			"loading":
				_notice_text.text = "Lade …"
			"error":
				_notice_text.text = store.error
			_:
				_notice_text.text = "Tasker ist noch nicht eingerichtet."
		_notice_setup.visible = store.state != "loading"
		return

	var searching := _query.text.strip_edges() != ""
	_scroll.visible = not searching
	_results.visible = searching
	if searching:
		Results.fill(_results, store.ws, Search.find(store.ws, store.project_id, _query.text, 80))
	else:
		_fill_sections()


func _fill_sections() -> void:
	for c in _sections.get_children():
		c.queue_free()
	_cards = []

	var ws := store.ws
	var m = Tisch.active_milestone(ws, store.project_id)
	if m == null:
		_sections.add_child(_text("Kein aktiver Milestone. Aktiv ist, was in Tasker auf „In Progress“ steht."))
		return

	var stats := Progress.milestone_stats(ws, m)
	# Der Milestone selbst: ein Klick öffnet sein Fenster.
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.text = "◆ %s" % m["title"]
	head.tooltip_text = "Milestone öffnen"
	head.add_theme_font_override("font", Palette.title_font())
	head.clip_text = true
	head.pressed.connect(func() -> void: task_requested.emit(m["id"]))
	_sections.add_child(head)

	var line := HBoxContainer.new()
	_sections.add_child(line)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.value = Progress.milestone_progress_pct(ws, m)
	bar.custom_minimum_size.y = 6
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(bar)
	var count := Label.new()
	count.text = "%d/%d" % [stats["done"], stats["total"]]
	count.tooltip_text = "Erledigte von allen Aufgaben"
	line.add_child(count)

	var layout := Tisch.layout(ws, m)
	# Hand und Nachziehstapel sind lokaler Zustand des Tischs – hier nur gelesen.
	var state := Hand.sanitize(memory.read(Hand.key(m["id"]), null) if memory != null else null, layout["open"], ws)
	var hand: Array = state["hand"].map(func(id: String) -> Dictionary: return ws.task(id))
	var sections := [
		["play", "Im Spiel", layout["play"]],
		["hand", "Hand", hand],
		["deck", "Nachziehstapel", Hand.deck_of(layout["open"], state["hand"])],
		["locked", "Gesperrt", layout["locked"]],
	]
	var any := false
	for section in sections:
		var key: String = section[0]
		var tasks: Array = section[2]
		if tasks.is_empty():
			continue
		any = true
		var toggle := Button.new()
		toggle.flat = true
		toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
		toggle.text = "%s %s  %d" % ["▸" if _collapsed.get(key, false) else "▾", section[1], tasks.size()]
		toggle.pressed.connect(func() -> void:
			_collapsed[key] = not _collapsed.get(key, false)
			_refresh())
		_sections.add_child(toggle)
		if _collapsed.get(key, false):
			continue
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 10)
		flow.add_theme_constant_override("v_separation", 12)
		_sections.add_child(flow)
		for t in tasks:
			var card := Card.new()
			flow.add_child(card)
			# Im Spiel steht über einer Unteraufgabe, wozu sie gehört.
			card.show_task(ws, t, images, key == "play")
			card.selected = t["id"] == selected_id
			card.pressed.connect(_on_card)
			_cards.append(card)
	if not any:
		_sections.add_child(_text("Alles erledigt – %d Karten auf dem Stapel." % layout["pile"].size() if layout["pile"].size() else "Noch keine Karten in diesem Milestone."))


func _text(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", Palette.MUTED)
	return l


# ------------------------------------------------------------- Ändern

## Ein Klick markiert, der Doppelklick öffnet das Fenster der Aufgabe, der Rechtsklick das Menü.
func _on_card(card: Control, event: InputEventMouseButton) -> void:
	select(card.task_id)
	if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		task_requested.emit(card.task_id)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		_menu.position = Vector2i(DisplayServer.mouse_get_position())
		_menu.popup()


func _set_status(status: String) -> void:
	var t = store.ws.task(selected_id)
	if t == null or t.get("status") == status:
		return
	# Dieselbe Regel wie in Tasker: erledigt erst, wenn alles darunter erledigt ist.
	var refusal := Tisch.done_refusal(store.ws, t) if status == "done" else ""
	_say(refusal)
	if refusal != "":
		return
	var res := await store.patch("task", selected_id, {"status": status})
	_say("" if res["ok"] else str(res["error"]))


func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


func _on_menu(id: int) -> void:
	match id:
		MENU_OPEN:
			task_requested.emit(selected_id)
		MENU_BROWSER:
			var t = store.ws.task(selected_id)
			if t != null:
				OS.shell_open(store.web_url(t))
		_:
			_set_status(Model.STATUS[id])


## Zeigt am Neuladen-Knopf, ob der Änderungs-Strom steht.
func set_live(live: bool) -> void:
	if _reload_button == null:
		return
	_reload_button.tooltip_text = "Neu laden\nÄnderungen aus Tasker kommen sofort an." if live else "Neu laden\nKeine laufende Verbindung – der Stand ist der vom letzten Laden."
	_reload_button.add_theme_color_override("font_color", Palette.OK if live else Palette.MUTED)
