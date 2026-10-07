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
	_text.editable = not on
	_cancel.disabled = on
	_done.disabled = on
	_done.text = "Speichert …" if on else "Fertig"


func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


func _on_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var enter: bool = event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER
	if event.keycode == KEY_ESCAPE or (enter and event.is_command_or_control_pressed()):
		_text.accept_event()
		commit()


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
