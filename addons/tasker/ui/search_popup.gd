@tool
extends PopupPanel
## Die Suche als Popup, aus der Befehlspalette oder per Tastenkürzel – wie
## „Quick Open“: tippen, mit den Pfeiltasten wählen, Eingabe übernimmt.

signal picked(task_id: String)

const Store := preload("../core/store.gd")
const Search := preload("../rules/search.gd")
const Results := preload("results.gd")

var store: Store
## Was die Eingabetaste mit dem Treffer tut – steht im Hinweis unter der Liste.
var action := "öffnet die Aufgabe"

var _query: LineEdit
var _list: ItemList
var _hint: Label


func _init() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_query = LineEdit.new()
	_query.placeholder_text = "Aufgabe suchen – Titel, Label, Beschreibung oder $Nummer"
	_query.clear_button_enabled = true
	_query.text_changed.connect(func(_t: String) -> void: _update())
	_query.gui_input.connect(_on_key)
	box.add_child(_query)

	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(_pick)
	_list.item_clicked.connect(func(i: int, _pos: Vector2, button: int) -> void:
		if button == MOUSE_BUTTON_LEFT:
			_pick(i))
	box.add_child(_list)

	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	box.add_child(_hint)


func open() -> void:
	_query.clear()
	_update()
	popup_centered(Vector2i(620, 420))
	_query.grab_focus()


func _update() -> void:
	if store == null or store.state != "ready":
		_list.clear()
		_hint.text = "Keine Verbindung zu Tasker."
		return
	var tasks := Search.find(store.ws, store.project_id, _query.text, 60)
	Results.fill(_list, store.ws, tasks)
	if _list.item_count > 0:
		_list.select(0)
	if _query.text.strip_edges() == "":
		_hint.text = "Gesucht wird im Projekt, ohne Archiv."
	else:
		_hint.text = "Nichts gefunden." if tasks.is_empty() else "%d Treffer – Eingabe %s." % [tasks.size(), action]


func _on_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var selected := _list.get_selected_items()
	var at: int = selected[0] if selected.size() else -1
	match event.keycode:
		KEY_DOWN, KEY_UP:
			if _list.item_count > 0:
				at = clampi(at + (1 if event.keycode == KEY_DOWN else -1), 0, _list.item_count - 1)
				_list.select(at)
				_list.ensure_current_is_visible()
			_query.accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			if at >= 0:
				_pick(at)
			_query.accept_event()


func _pick(index: int) -> void:
	var id: String = _list.get_item_metadata(index)
	hide()
	picked.emit(id)
