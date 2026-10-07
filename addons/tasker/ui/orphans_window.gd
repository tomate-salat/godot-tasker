@tool
extends Window
## Die verwaisten Verknüpfungen: Aufgaben, deren Node, Szene oder die selbst
## nicht mehr zu finden sind. Für verlorene Nodes steht hier ein Vorschlag,
## wo sie jetzt sein könnten – übernommen wird erst auf Knopfdruck.

signal task_requested(task_id: String)

const Store := preload("../core/store.gd")
const Links := preload("../core/links.gd")
const Palette := preload("palette.gd")
const Refs := preload("../rules/refs.gd")

const REASONS := {
	Links.NODE_GONE: "Der Node ist nicht mehr zu finden.",
	Links.SCENE_GONE: "Die Szene gibt es nicht mehr.",
	Links.TASK_GONE: "Die Aufgabe ist nicht mehr im Stand – archiviert oder gelöscht.",
}

var store: Store
var links: Links

var _summary: Label
var _take_all: Button
var _message: Label
var _rows: VBoxContainer


func _init() -> void:
	title = "Tasker: verwaiste Verknüpfungen"
	size = Vector2i(760, 520)
	min_size = Vector2i(480, 260)
	wrap_controls = false
	close_requested.connect(queue_free)

	var back := PanelContainer.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	back.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_summary = Label.new()
	_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	head.add_child(_summary)
	_take_all = Button.new()
	_take_all.text = "Alle Vorschläge übernehmen"
	_take_all.pressed.connect(_heal_all)
	head.add_child(_take_all)
	var again := Button.new()
	again.text = "Erneut prüfen"
	again.pressed.connect(refresh)
	head.add_child(again)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Palette.P2)
	_message.visible = false
	box.add_child(_message)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)


func _ready() -> void:
	store.changed.connect(refresh)
	links.memory.changed.connect(refresh)
	links.scene_changed.connect(refresh)
	refresh()


func refresh() -> void:
	for c in _rows.get_children():
		c.queue_free()
	var found := links.orphans(store.ws if store.state == "ready" else null)
	var with_suggestion := found.filter(func(o: Dictionary) -> bool: return o["suggestion"] != "")
	_take_all.visible = with_suggestion.size() > 1
	if found.is_empty():
		_summary.text = "Alles hängt, wo es soll."
		return
	_summary.text = "%d %s ins Leere. In anderen Szenen als der offenen lässt sich nur prüfen, was schon einmal mit der Szene gespeichert wurde." % [
		found.size(), "Verknüpfung zeigt" if found.size() == 1 else "Verknüpfungen zeigen"]
	for o in found:
		_rows.add_child(_row(o))


func _row(o: Dictionary) -> Control:
	var ref: Dictionary = o["ref"]
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var t = store.ws.task(ref["taskId"]) if store.state == "ready" else null
	var name := Button.new()
	name.flat = true
	name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name.clip_text = true
	if t != null:
		name.icon = Palette.status_icon(t.get("status"))
		name.text = "$%d  %s" % [int(t.get("ref", 0)), t["title"] if t.get("title") else "Ohne Titel"]
		name.tooltip_text = "Aufgabe öffnen"
		name.pressed.connect(func() -> void: task_requested.emit(ref["taskId"]))
	else:
		name.text = "Unbekannte Aufgabe"
		name.disabled = true
	box.add_child(name)

	var where := Label.new()
	where.text = "%s\n%s" % [Refs.label(ref), REASONS[o["reason"]]]
	where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	where.add_theme_color_override("font_color", Palette.MUTED)
	box.add_child(where)

	var actions := HFlowContainer.new()
	box.add_child(actions)
	if o["suggestion"] != "":
		var take := Button.new()
		take.text = "Übernehmen: %s" % o["suggestion"]
		take.tooltip_text = "Die Verknüpfung zeigt künftig auf diesen Node"
		take.pressed.connect(func() -> void: links.heal(ref, o["suggestion"]))
		actions.add_child(take)
	if o["reason"] == Links.NODE_GONE:
		var hang := Button.new()
		hang.text = "An ausgewählten Node hängen"
		hang.tooltip_text = "Der im Szenenbaum ausgewählte Node – die Szene der Verknüpfung muss offen sein"
		hang.pressed.connect(func() -> void:
			var chosen := links.selection()
			_say("Erst einen Node im Szenenbaum auswählen." if chosen.is_empty() else links.rehang(ref, chosen[0])))
		actions.add_child(hang)
		var show := Button.new()
		show.text = "Szene öffnen"
		show.pressed.connect(func() -> void: EditorInterface.open_scene_from_path(Links._current_path(ref)))
		actions.add_child(show)
	var drop := Button.new()
	drop.text = "Verknüpfung lösen"
	drop.pressed.connect(func() -> void: links.unlink(ref))
	actions.add_child(drop)
	return panel


func _heal_all() -> void:
	for o in links.orphans(store.ws if store.state == "ready" else null):
		if o["suggestion"] != "":
			links.heal(o["ref"], o["suggestion"])


func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""


## Escape schließt das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
