@tool
extends VBoxContainer
## Titel und Beschreibung einer Aufgabe oder eines Milestones bearbeiten.
##
## Wie in Tasker (`client/ui/Inspector.tsx`, `Content`) sind beide ein Feld:
## die erste Zeile ist der Titel. „Fertig“, Escape oder Strg+Enter übernehmen,
## „Abbrechen“ verwirft. Beim Öffnen steht die Schreibmarke am Ende.
##
## Anders als in Tasker geht der eigene Text nicht verloren, wenn inzwischen
## jemand anderes geändert hat: das Feld bleibt offen und sagt es; ein zweites
## „Fertig“ überschreibt dann bewusst.

## Das Feld ist wieder zu – gespeichert oder verworfen.
signal closed

const Store := preload("../core/store.gd")
const Palette := preload("palette.gd")
const ListEdit := preload("../rules/list_edit.gd")
const CaretMenu := preload("../rules/caret_menu.gd")

## Breite der Liste unter der Schreibmarke.
const MENU_WIDTH := 320

var store: Store
## "task" oder "milestone".
var kind := "task"
var item_id := ""
## Das Feld wächst mit dem Text, statt selbst zu scrollen – für Fenster, die
## als Ganzes scrollen.
var grow := false: set = set_grow

var _text: TextEdit
var _message: Label
var _cancel: Button
var _done: Button
## Titel und Beschreibung, auf denen der Text im Feld beruht.
var _base_title := ""
var _base_desc := ""
var _saving := false
## Die Liste unter der Schreibmarke: Befehle nach `/`, Verweise nach `$`.
var _menu: PanelContainer
var _menu_rows: VBoxContainer
var _menu_kind := ""
var _menu_start := 0
var _menu_query := ""
var _menu_hits: Array = []
var _menu_active := 0
## Wo die Liste mit Escape geschlossen wurde (-1: nirgends).
var _menu_dismissed := -1
var _row_on: StyleBoxFlat
var _row_off: StyleBoxEmpty


func _init() -> void:
	visible = false
	add_theme_constant_override("separation", 6)

	_text = TextEdit.new()
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.custom_minimum_size.y = 160
	_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_text.caret_blink = true
	_text.tooltip_text = "Die erste Zeile ist der Titel"
	_text.gui_input.connect(_on_key)
	add_child(_text)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Palette.P2)
	_message.visible = false
	add_child(_message)

	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_END
	add_child(bar)
	_cancel = Button.new()
	_cancel.text = "Abbrechen"
	_cancel.flat = true
	_cancel.tooltip_text = "Änderungen verwerfen"
	_cancel.pressed.connect(cancel)
	bar.add_child(_cancel)
	_done = Button.new()
	_done.text = "Fertig"
	_done.tooltip_text = "Übernehmen – auch mit Esc oder Strg+Enter"
	_done.pressed.connect(commit)
	bar.add_child(_done)

	# Die Liste liegt über allem im Fenster und nimmt dem Feld nie die Schreibmarke.
	_menu = PanelContainer.new()
	_menu.top_level = true
	_menu.z_index = 100
	_menu.visible = false
	var frame := StyleBoxFlat.new()
	frame.bg_color = Palette.SURFACE
	frame.border_color = Palette.LINE_STRONG
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(6)
	frame.set_content_margin_all(4)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 8
	_menu.add_theme_stylebox_override("panel", frame)
	add_child(_menu)
	_menu_rows = VBoxContainer.new()
	_menu_rows.add_theme_constant_override("separation", 0)
	_menu.add_child(_menu_rows)
	_row_on = StyleBoxFlat.new()
	_row_on.bg_color = Color(Palette.ACCENT, 0.22)
	_row_on.set_corner_radius_all(4)
	_row_on.set_content_margin_all(5)
	_row_on.content_margin_right = 70
	_row_off = StyleBoxEmpty.new()
	_row_off.set_content_margin_all(5)
	_row_off.content_margin_right = 70
	_text.text_changed.connect(_update_menu)
	_text.caret_changed.connect(_update_menu)
	_text.focus_exited.connect(_close_menu)
	visibility_changed.connect(func() -> void:
		if not is_visible_in_tree():
			_close_menu())


func set_grow(value: bool) -> void:
	grow = value
	_text.scroll_fit_content_height = value
	_text.size_flags_vertical = Control.SIZE_FILL if value else Control.SIZE_EXPAND_FILL


func is_open() -> bool:
	return visible


## Öffnet das Feld mit dem Stand dieses Objekts. Falsch, wenn gerade nichts
## gespeichert werden könnte – dann bleibt es zu.
func open(item_kind: String, id: String) -> bool:
	if store == null or store.state != "ready":
		return false
	var item = store._find(item_kind, id)
	if item == null:
		return false
	kind = item_kind
	item_id = id
	_base_title = _title_of(item)
	_base_desc = _desc_of(item)
	_text.text = join(_base_title, _base_desc)
	_text.clear_undo_history()
	_say("")
	_lock(false)
	visible = true
	_text.grab_focus()
	var last := _text.get_line_count() - 1
	_text.set_caret_line(last)
	_text.set_caret_column(_text.get_line(last).length())
	return true


## Verwirft, was getippt wurde.
func cancel() -> void:
	if _saving:
		return
	visible = false
	closed.emit()


## Übernimmt den Text. Wahr, wenn das Feld danach zu ist.
func commit() -> bool:
	if _saving or not visible:
		return false
	var next := split(_text.text)
	var current = store._find(kind, item_id)
	if current == null:
		cancel()
		return true
	# Inzwischen woanders geändert: nicht stillschweigend überschreiben.
	if _title_of(current) != _base_title or _desc_of(current) != _base_desc:
		_rebase(current)
		return false
	if next["title"] == _base_title and next["desc"] == _base_desc:
		visible = false
		closed.emit()
		return true

	_lock(true)
	var res := await store.patch(kind, item_id, next)
	if not is_instance_valid(self):
		return false
	_lock(false)
	if res["ok"]:
		visible = false
		closed.emit()
		return true
	if res["conflict"] and res["object"] is Dictionary:
		_rebase(res["object"])
	else:
		_say("%s Dein Text steht noch hier." % str(res["error"]))
	_text.grab_focus()
	return false


## Der Stand hat sich geändert, während getippt wurde: der eigene Text bleibt,
## und ein zweites „Fertig“ gilt dem neuen Stand.
func _rebase(current: Dictionary) -> void:
	_base_title = _title_of(current)
	_base_desc = _desc_of(current)
	_say("Inzwischen woanders geändert. Dein Text steht noch hier: „Fertig“ überschreibt den neuen Stand, „Abbrechen“ verwirft deinen Text.")


func _lock(on: bool) -> void:
	_saving = on
	if on:
		_close_menu()
	_text.editable = not on
	_cancel.disabled = on
	_done.disabled = on
	_done.text = "Speichert …" if on else "Fertig"


func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


## Die Tasten des Feldes: übernehmen, Listen weiterschreiben, Zeilen schieben
## – wie Taskers `useSmartEditor`.
func _on_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var key: int = event.keycode
	var enter := key == KEY_ENTER or key == KEY_KP_ENTER
	var ctrl: bool = event.is_command_or_control_pressed()
	if _menu_key(event):
		_text.accept_event()
		return
	if key == KEY_ESCAPE or (enter and ctrl):
		_text.accept_event()
		if not event.echo:
			if key == KEY_ESCAPE:
				escape()
			else:
				commit()
		return

	var sel := _selection()
	var value := _text.text
	# Alt und Pfeil hoch/runter verschieben die Zeile. Auch am Rand bleibt die
	# Taste hier, sonst spränge die Schreibmarke doch noch weg.
	if event.alt_pressed and not ctrl and (key == KEY_UP or key == KEY_DOWN):
		_text.accept_event()
		var moved = ListEdit.move_lines(value, sel[0], sel[1], 1 if key == KEY_DOWN else -1)
		if moved != null:
			_apply(moved)
		return
	if event.alt_pressed or ctrl:
		return

	if enter:
		var edit = ListEdit.break_in_item(value, sel[0], sel[1]) if event.shift_pressed else ListEdit.enter_in_list(value, sel[0], sel[1])
		# Umschalt+Enter ist sonst ein gewöhnlicher Umbruch – das Feld kennt ihn von sich aus nicht.
		if edit == null and event.shift_pressed:
			edit = {"from": sel[0], "to": sel[1], "text": "\n", "sel_start": sel[0] + 1, "sel_end": sel[0] + 1}
		if edit != null:
			_text.accept_event()
			_apply(edit)
	elif key == KEY_TAB or key == KEY_BACKTAB:
		# Tab schreibt nie ein Tabulatorzeichen: im Listenpunkt rückt es ein und
		# aus, sonst geht es zum nächsten Bedienelement wie im Browser.
		_text.accept_event()
		var back: bool = event.shift_pressed or key == KEY_BACKTAB
		var edit = ListEdit.tab_in_list(value, sel[0], sel[1], -1 if back else 1)
		if edit != null:
			_apply(edit)
		elif not ListEdit.in_item(value, sel[0]):
			var next := _text.find_prev_valid_focus() if back else _text.find_next_valid_focus()
			if next != null:
				next.grab_focus()


# ------------------------------------------------- Liste unter der Schreibmarke

## Schaut nach, ob vor der Schreibmarke ein `$` oder `/` mit Suche steht, und
## zeigt die Treffer – wie Taskers `useCaretMenu`.
func _update_menu() -> void:
	if not visible or _saving or _text.has_selection():
		_close_menu()
		return
	var value := _text.text
	var caret := offset_of(value, _text.get_caret_line(), _text.get_caret_column())
	for kind: String in [CaretMenu.REF, CaretMenu.SLASH]:
		var q = CaretMenu.query_at(value, caret, kind)
		if q == null:
			continue
		# Mit Escape geschlossen: an dieser Stelle nicht gleich wieder öffnen.
		if q["start"] == _menu_dismissed:
			_close_menu(false)
			return
		var item = store._find(self.kind, item_id)
		var hits: Array = CaretMenu.slash_matches(q["text"]) if kind == CaretMenu.SLASH else \
			CaretMenu.ref_search(store.ws, q["text"], item.get("projectId") if item != null else null, item_id)
		if hits.is_empty():
			break
		if kind != _menu_kind or q["text"] != _menu_query:
			_menu_active = 0
		_menu_kind = kind
		_menu_start = q["start"]
		_menu_query = q["text"]
		_menu_hits = hits
		_menu_active = mini(_menu_active, hits.size() - 1)
		_menu_dismissed = -1
		_show_menu()
		return
	_close_menu()


## Schließt die Liste. `forget`: eine mit Escape weggeklickte Stelle gilt nicht mehr.
func _close_menu(forget := true) -> void:
	_menu_kind = ""
	_menu_hits = []
	_menu.visible = false
	if forget:
		_menu_dismissed = -1


func _menu_open() -> bool:
	return _menu_kind != "" and not _menu_hits.is_empty()


func _show_menu() -> void:
	for c in _menu_rows.get_children():
		_menu_rows.remove_child(c)
		c.queue_free()
	for i in _menu_hits.size():
		var hit: Dictionary = _menu_hits[i]
		var is_ref := _menu_kind == CaretMenu.REF
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.clip_text = true
		row.custom_minimum_size = Vector2(MENU_WIDTH, 0)
		row.text = (CaretMenu.ref_icon(hit) + (hit["title"] if hit["title"] != "" else "Ohne Titel")) if is_ref else hit["label"]
		row.add_theme_stylebox_override("normal", _row_on if i == _menu_active else _row_off)
		row.add_theme_stylebox_override("hover", _row_on)
		row.add_theme_stylebox_override("pressed", _row_on)
		if is_ref and hit["done"]:
			row.add_theme_color_override("font_color", Palette.FAINT)
		# Rechts klein: die Nummer oder die Schreibweise.
		var hint := Label.new()
		hint.text = "$%d" % hit["ref"] if is_ref else hit["hint"]
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hint.add_theme_color_override("font_color", Palette.MUTED)
		hint.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
		hint.offset_right = -8
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		hint.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		row.add_child(hint)
		# Beim Drücken, nicht beim Loslassen: das Feld behält die Schreibmarke.
		row.button_down.connect(_take.bind(i))
		_menu_rows.add_child(row)
	_menu.visible = true
	_menu.reset_size()
	# Unter der Stelle des Auslösezeichens, aber nicht aus dem Fenster hinaus.
	var place := place_of(_text.text, _menu_start)
	var at: Rect2 = _text.get_rect_at_line_column(place.x, place.y)
	var below := _text.global_position + Vector2(at.position.x, at.end.y + 2.0)
	var room := get_viewport_rect().size
	var need := _menu.get_combined_minimum_size()
	if below.y + need.y > room.y - 8.0:
		below.y = _text.global_position.y + at.position.y - need.y - 2.0
	below.x = clampf(below.x, 8.0, maxf(8.0, room.x - need.x - 8.0))
	_menu.global_position = below


## Übernimmt den Treffer an dieser Stelle der Liste.
func _take(index: int) -> void:
	if not _menu_open():
		return
	var hit: Dictionary = _menu_hits[clampi(index, 0, _menu_hits.size() - 1)]
	var value := _text.text
	var caret := offset_of(value, _text.get_caret_line(), _text.get_caret_column())
	var edit := CaretMenu.slash_edit(value, _menu_start, caret, hit) if _menu_kind == CaretMenu.SLASH else CaretMenu.ref_edit(_menu_start, caret, hit)
	_close_menu()
	_apply(edit)
	_text.grab_focus()


## Die Tasten der Liste: ↑/↓ wählen, Enter oder Tab übernehmen. Wahr, wenn die
## Taste der Liste galt.
func _menu_key(event: InputEventKey) -> bool:
	if not _menu_open():
		return false
	var key := event.keycode
	if key == KEY_UP or key == KEY_DOWN:
		_menu_active = posmod(_menu_active + (1 if key == KEY_DOWN else -1), _menu_hits.size())
		_show_menu()
		return true
	if (key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_TAB) and not event.is_command_or_control_pressed():
		_take(_menu_active)
		return true
	return false


## Escape: schließt nur die Liste, wenn eine offen ist – sonst übernimmt es den Text.
func escape() -> void:
	if _menu_open():
		_menu_dismissed = _menu_start
		_close_menu(false)
	else:
		commit()


## Die Auswahl als Stellen im Text: `[anfang, ende]`, ohne Auswahl beide die Schreibmarke.
func _selection() -> Array:
	var value := _text.text
	if _text.has_selection():
		return [offset_of(value, _text.get_selection_from_line(), _text.get_selection_from_column()),
			offset_of(value, _text.get_selection_to_line(), _text.get_selection_to_column())]
	var at := offset_of(value, _text.get_caret_line(), _text.get_caret_column())
	return [at, at]


## Wendet eine Änderung aus `rules/list_edit.gd` an – als einen Schritt zum Rückgängigmachen.
func _apply(edit: Dictionary) -> void:
	var value := _text.text
	var from := place_of(value, edit["from"])
	var to := place_of(value, edit["to"])
	_text.begin_complex_operation()
	_text.deselect()
	if edit["to"] > edit["from"]:
		_text.remove_text(from.x, from.y, to.x, to.y)
	if edit["text"] != "":
		_text.insert_text(edit["text"], from.x, from.y)
	_text.end_complex_operation()
	var next := _text.text
	var a := place_of(next, edit["sel_start"])
	var b := place_of(next, edit["sel_end"])
	if a == b:
		_text.set_caret_line(a.x)
		_text.set_caret_column(a.y)
	else:
		_text.select(a.x, a.y, b.x, b.y)
	_text.adjust_viewport_to_caret()


## Zeile und Spalte als Stelle im Text.
static func offset_of(text: String, line: int, column: int) -> int:
	var at := 0
	for i in line:
		at = text.find("\n", at) + 1
	return at + column


## Eine Stelle im Text als (Zeile, Spalte).
static func place_of(text: String, offset: int) -> Vector2i:
	var before := text.substr(0, offset)
	return Vector2i(before.count("\n"), offset - (before.rfind("\n") + 1))


static func _title_of(item: Dictionary) -> String:
	return item.get("title") if item.get("title") is String else ""


static func _desc_of(item: Dictionary) -> String:
	return item.get("desc") if item.get("desc") is String else ""


## Titel und Beschreibung als ein Text: die erste Zeile ist der Titel.
static func join(title: String, desc: String) -> String:
	return title + ("\n\n" + desc if desc != "" else "")


## Der Text wieder getrennt: `{ title, desc }`. Leerzeilen zwischen Titel und
## Beschreibung gehören zu keinem von beiden.
static func split(text: String) -> Dictionary:
	var lines := text.replace("\r\n", "\n").split("\n")
	var rest := "\n".join(lines.slice(1))
	while rest.begins_with("\n"):
		rest = rest.substr(1)
	return {"title": lines[0].strip_edges(), "desc": rest}
