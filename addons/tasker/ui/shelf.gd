@tool
extends PanelContainer
## Die Ablage: der aufgedeckte Erledigt-Stapel. Je Woche eine Reihe mit dem,
## was erledigt wurde, dazu Wochenziel, beste Woche und Serie.
##
## Hier wird nur angesehen: Karten lassen sich nicht ziehen, damit nichts aus
## Versehen wieder ins Spiel gerät. Ein Doppelklick öffnet die Aufgabe; den
## Status ändert man dort.

signal task_requested(task_id: String)
signal close_requested

const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Burnup := preload("../rules/burnup.gd")
const Tisch := preload("../rules/tisch.gd")
const Workspace := preload("../rules/workspace.gd")

const WEEKDAYS := ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]

var _summary: Label
var _streak: Label
var _weeks: VBoxContainer
## Was gerade gezeigt wird – bei gleichem Stand wird nicht neu aufgebaut.
var _shown := ""


func _init() -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("151b19")
	panel.border_color = Color(Palette.ACCENT, 0.55)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(14)
	panel.set_content_margin_all(18)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 18
	panel.shadow_offset = Vector2(0, 6)
	add_theme_stylebox_override("panel", panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	box.add_child(head)
	var title := Label.new()
	title.text = "✓ Erledigt"
	title.add_theme_font_override("font", Palette.title_font())
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Palette.OK)
	head.add_child(title)
	_summary = Label.new()
	_summary.add_theme_color_override("font_color", Palette.MUTED)
	head.add_child(_summary)
	_streak = Label.new()
	_streak.add_theme_color_override("font_color", Palette.P2)
	_streak.tooltip_text = "Wochen in Folge mit mindestens einer erledigten Karte"
	head.add_child(_streak)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	var hint := Label.new()
	hint.text = "Doppelklick öffnet die Aufgabe"
	hint.add_theme_color_override("font_color", Palette.FAINT)
	head.add_child(hint)
	var close := Button.new()
	close.text = "✕"
	close.flat = true
	close.tooltip_text = "Stapel wieder einsammeln (Esc)"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_weeks = VBoxContainer.new()
	_weeks.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weeks.add_theme_constant_override("separation", 22)
	scroll.add_child(_weeks)


## Zeigt, was `Tisch.done_shelf` ausgerechnet hat. `goal` ist das Wochenziel.
func show_shelf(ws: Workspace, shelf: Dictionary, goal: int, images: Node, tz_minutes: int) -> void:
	var total := 0
	var signature := str(goal)
	for w in shelf["weeks"]:
		total += w["cards"].size()
		signature += "|" + w["start"]
		for t in w["cards"]:
			signature += "," + t["id"] + ":" + str(int(t.get("version", 0)))
	_summary.text = "%d %s in diesem Milestone" % [total, "Karte" if total == 1 else "Karten"]
	_streak.text = "Serie: %d Wochen in Folge" % shelf["streak"] if shelf["streak"] >= 2 else ""
	if signature == _shown:
		return
	_shown = signature

	for c in _weeks.get_children():
		c.queue_free()
	for w in shelf["weeks"]:
		_weeks.add_child(_week(ws, w, goal, images, tz_minutes))


func _week(ws: Workspace, w: Dictionary, goal: int, images: Node, tz_minutes: int) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	box.add_child(head)
	var name := Label.new()
	name.text = "Diese Woche" if w["current"] else "Woche ab %s" % Burnup.format_day(Burnup.day_of_date(w["start"]))
	name.add_theme_font_override("font", Palette.title_font())
	name.add_theme_font_size_override("font_size", 16)
	head.add_child(name)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = goal
	bar.value = mini(w["count"], goal)
	bar.custom_minimum_size = Vector2(140, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(bar)
	var count := Label.new()
	count.text = "%d von %d" % [w["count"], goal]
	count.tooltip_text = "Erledigte Karten ohne Unteraufgaben gegen das Tempo aus den Tasker-Einstellungen"
	count.add_theme_color_override("font_color", Palette.MUTED)
	head.add_child(count)
	if w["count"] >= goal:
		head.add_child(_badge("★ Ziel geschafft", Palette.P2))
	if w["best"]:
		head.add_child(_badge("♛ Beste Woche", Palette.ACCENT))

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 16)
	box.add_child(flow)
	var archived := 0
	for t in w["cards"]:
		# Was archiviert wurde, zählt weiter, ist aber nicht mehr im Stand.
		if ws.task(t["id"]) == null:
			archived += 1
			continue
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var when := Label.new()
		when.text = _when(t.get("doneAt"), tz_minutes)
		when.add_theme_font_size_override("font_size", 12)
		when.add_theme_color_override("font_color", Palette.FAINT)
		cell.add_child(when)
		var card := Card.new()
		cell.add_child(card)
		# In der Ablage steht über einer Unteraufgabe, wozu sie gehört.
		card.show_task(ws, t, images, true)
		card.modulate.a = 1.0
		card.tooltip_text = "Doppelklick öffnet die Aufgabe"
		card.pressed.connect(func(c: Control, event: InputEventMouseButton) -> void:
			if event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
				task_requested.emit(c.task_id))
		flow.add_child(cell)
	if archived > 0:
		var note := Label.new()
		note.text = "dazu %d archiviert" % archived
		note.add_theme_color_override("font_color", Palette.FAINT)
		note.size_flags_vertical = Control.SIZE_SHRINK_END
		flow.add_child(note)
	return box


func _badge(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	return l


## Wochentag und Uhrzeit des Abschlusses in Ortszeit, etwa „Mi 14:32“.
static func _when(done_at: Variant, tz_minutes: int) -> String:
	if not done_at:
		return "gerade eben"
	var local := int(Tisch.parse_time(done_at)) + tz_minutes * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	return "%s %02d:%02d" % [WEEKDAYS[d["weekday"]], d["hour"], d["minute"]]
