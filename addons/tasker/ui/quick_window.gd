@tool
extends "card_window.gd"
## Schnellanlegen (Nutzer, 2026-10-19): oben die Knöpfe, in der Mitte das Feld
## zum Bearbeiten – dasselbe wie im Aufgabenfenster, die erste Zeile ist der
## Titel, mit `/` und `$` –, darunter, woran die Aufgabe hängen soll,
## vorbelegt mit der Auswahl im Szenenbaum.
##
## Zwei Knöpfe (Nutzer, 2026-10-19 – erst waren es drei Claude-Aufträge):
## „Anlegen“ legt an und öffnet die Aufgabe. „Mit Claude“ legt an und lässt
## Claude sie nach der Vorlage neu schreiben und anhängen (`Quick.REWRITE`,
## `core/claude_tasks.gd`); das Fenster zeigt
## dann, was passiert, und die Aufgabe geht erst auf, wenn Claude fertig ist
## (Nutzer: sie gleich zu öffnen war verwirrend, weil nirgends stand, dass
## noch etwas läuft). Der Schnappschuss des Editors ist beim Klick gemacht –
## weiterarbeiten darf man sofort, und wer das Fenster schließt, lässt Claude
## im Hintergrund weitermachen.

## Die angelegte Aufgabe soll in ihrem Fenster aufgehen.
signal task_requested(task_id: String)

const ClaudeTasks := preload("../core/claude_tasks.gd")
const SceneTools := preload("../core/scene_tools.gd")
const Links := preload("../core/links.gd")
const Config := preload("../core/config.gd")
const ContentEditor := preload("content_editor.gd")
const Quick := preload("../rules/quick.gd")

## So viele Zeilen dessen, was Claude getan hat, bleiben stehen.
const TRAIL := 5
const SPINNER := ["◐", "◓", "◑", "◒"]
const SPIN_SECONDS := 0.15

var tasks: ClaudeTasks
var scene_tools: SceneTools
var links: Links

## Woran die Aufgabe hängen soll: `{ scene, path }`.
var _refs: Array = []
## Wird gerade angelegt – solange bleibt das Fenster offen.
var _busy := false
## Die angelegte Aufgabe, an der Claude arbeitet.
var _task_id := ""
var _started := 0
var _spin := 0.0
var _head: Label
var _editor: ContentEditor
var _where: HFlowContainer
var _message: Label
var _buttons: Array[Button] = []
var _work: PanelContainer
var _spinner: Label
var _phase: Label
var _clock: Label
var _steps: VBoxContainer
var _cancel: Button


func _init() -> void:
	super()
	size = Vector2i(620, 460)
	min_size = Vector2i(440, 340)
	close_requested.connect(func() -> void:
		if not _busy:
			shut())
	_build()
	set_process(false)


func _ready() -> void:
	var project: Variant = tasks.store.ws.project(Config.project_id()) if tasks != null and tasks.store != null else null
	_head.text = "Neue Aufgabe%s" % ("  ·  %s" % project["name"] if project != null else "")
	_editor.store = tasks.store if tasks != null else null
	_editor.open_draft(Config.project_id(), "Erste Zeile: der Titel\nDarunter, was dir auffällt …  ( / für Befehle, $ für Verweise)")
	tasks.progress.connect(_on_progress)
	tasks.finished.connect(_on_finished)
	add_selection()


## Nimmt die im Szenenbaum ausgewählten Nodes dazu.
func add_selection() -> void:
	if _task_id != "":
		return
	var root := EditorInterface.get_edited_scene_root()
	if root == null or links == null:
		return
	if root.scene_file_path == "":
		_say("Die Szene ist noch nie gespeichert – an ihr lässt sich nichts anhängen.")
		return
	for node in links.selection():
		if node != root and not root.is_ancestor_of(node):
			continue
		var ref := {"scene": root.scene_file_path, "path": str(root.get_path_to(node))}
		if not _refs.has(ref):
			_refs.append(ref)
	_show_refs()


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	face.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	_head = Label.new()
	_head.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_head.clip_text = true
	_head.add_theme_color_override("font_color", Palette.MUTED)
	top.add_child(_head)
	top.add_child(pin_button())
	top.add_child(close_button())

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	box.add_child(bar)
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	var create := Button.new()
	create.text = "Anlegen"
	create.tooltip_text = "Legt die Aufgabe an, wie sie dasteht, und öffnet sie (Strg+Enter)"
	create.pressed.connect(_submit.bind(""))
	bar.add_child(create)
	_buttons.append(create)
	var claude := Button.new()
	claude.text = "Mit Claude anlegen"
	claude.icon = Palette.sparkles_icon()
	claude.add_theme_color_override("icon_normal_color", Palette.ACCENT)
	claude.add_theme_color_override("icon_hover_color", Palette.ACCENT)
	claude.add_theme_color_override("icon_pressed_color", Palette.ACCENT)
	claude.tooltip_text = "Legt die Aufgabe an und lässt Claude sie ausarbeiten: Kontext aus Szene und Code,\nTo-do, offene Fragen – auf Englisch – und hängt sie an die betroffenen Nodes.\nSie geht auf, sobald Claude fertig ist."
	claude.pressed.connect(_submit.bind(Quick.REWRITE))
	bar.add_child(claude)
	_buttons.append(claude)

	_editor = ContentEditor.new()
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.submitted.connect(_submit.bind(""))
	box.add_child(_editor)

	_where = HFlowContainer.new()
	_where.add_theme_constant_override("h_separation", 6)
	_where.add_theme_constant_override("v_separation", 6)
	box.add_child(_where)

	_work = _build_work()
	_work.visible = false
	box.add_child(_work)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_message.add_theme_color_override("font_color", Palette.P2)
	_message.visible = false
	box.add_child(_message)


## Was zu sehen ist, während Claude arbeitet: ein Kreisel, was gerade dran ist,
## die Zeit und die letzten Schritte.
func _build_work() -> PanelContainer:
	var panel := PanelContainer.new()
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color(Palette.ACCENT, 0.08)
	frame.border_color = Color(Palette.ACCENT, 0.35)
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(8)
	frame.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", frame)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_spinner = Label.new()
	_spinner.add_theme_color_override("font_color", Palette.ACCENT)
	row.add_child(_spinner)
	_phase = Label.new()
	_phase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_phase.clip_text = true
	row.add_child(_phase)
	_clock = Label.new()
	_clock.add_theme_color_override("font_color", Palette.MUTED)
	row.add_child(_clock)
	_cancel = Button.new()
	_cancel.text = "Abbrechen"
	_cancel.flat = true
	_cancel.tooltip_text = "Claude anhalten – die Aufgabe bleibt angelegt, wie sie ist"
	_cancel.pressed.connect(func() -> void:
		if _task_id != "":
			tasks.cancel(_task_id))
	row.add_child(_cancel)
	_steps = VBoxContainer.new()
	_steps.add_theme_constant_override("separation", 0)
	box.add_child(_steps)
	var hint := Label.new()
	hint.text = "Du kannst weiterarbeiten. Schließt du das Fenster, macht Claude im Hintergrund weiter; die Aufgabe geht auf, wenn sie fertig ist."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Palette.FAINT)
	box.add_child(hint)
	return panel


func _show_refs() -> void:
	for c in _where.get_children():
		c.queue_free()
	for ref in _refs:
		var chip := Button.new()
		var file: String = ref["scene"].get_file()
		chip.text = "⌖ %s  ✕" % (file if ref["path"] == "." else "%s › %s" % [file, ref["path"]])
		chip.tooltip_text = "%s\nKlicken: nicht anhängen" % ref["scene"]
		chip.focus_mode = Control.FOCUS_NONE
		chip.pressed.connect(func() -> void:
			_refs.erase(ref)
			_show_refs())
		_where.add_child(chip)
	var more := Button.new()
	more.text = "+ Auswahl"
	more.flat = true
	more.focus_mode = Control.FOCUS_NONE
	more.tooltip_text = "Hängt auch an, was im Szenenbaum gerade ausgewählt ist"
	more.pressed.connect(add_selection)
	_where.add_child(more)


## Legt an – und schickt mit `mode` danach Claude los.
func _submit(mode: String) -> void:
	if _busy or _task_id != "" or tasks == null:
		return
	var parts := ContentEditor.split(_editor.get_text())
	if str(parts["title"]).strip_edges() == "":
		_say("Erst etwas schreiben – die erste Zeile ist der Titel.")
		return
	if mode != "":
		_start_work("Hält fest, was im Editor offen ist")
	_lock(true)
	# Der Schnappschuss zuerst: danach darf sich im Editor alles ändern.
	var snapshot := await scene_tools.snapshot() if mode != "" else ""
	if not is_instance_valid(self):
		return
	if mode != "":
		_step("Schnappschuss gemacht")
		_phase.text = "Legt die Aufgabe an"
	var made: Dictionary = await tasks.create(parts["title"], parts["desc"], _refs, mode != "")
	if not is_instance_valid(self):
		return
	if not made["ok"]:
		_lock(false)
		_work.visible = false
		set_process(false)
		_say(made["error"])
		return
	if not made["problems"].is_empty():
		EditorInterface.get_editor_toaster().push_toast("Tasker: angelegt, aber nicht überall angehängt: %s" % "; ".join(made["problems"]), EditorToaster.SEVERITY_WARNING)
	_busy = false
	if mode == "":
		task_requested.emit(made["task_id"])
		shut()
		return
	_task_id = made["task_id"]
	var task: Variant = tasks.store.ws.task(_task_id)
	var label := "$%d" % int(task.get("ref", 0)) if task != null else "Die Aufgabe"
	_step("%s angelegt" % label)
	_phase.text = Quick.BUSY[mode] % label
	tasks.improve(_task_id, mode, snapshot)


func _start_work(phase: String) -> void:
	_where.visible = false
	_work.visible = true
	_phase.text = phase
	_started = Time.get_ticks_msec()
	_spin = 0.0
	_spinner.text = SPINNER[0]
	_clock.text = "0:00"
	set_process(true)


## Eine Zeile unter dem, was gerade dran ist; ältere rücken nach oben weg.
func _step(line: String) -> void:
	var label := Label.new()
	label.text = "✓ " + line
	label.clip_text = true
	label.add_theme_color_override("font_color", Palette.MUTED)
	_steps.add_child(label)
	while _steps.get_child_count() > TRAIL:
		var old := _steps.get_child(0)
		_steps.remove_child(old)
		old.queue_free()


func _on_progress(task_id: String, line: String) -> void:
	if task_id == _task_id:
		_step(line)


func _on_finished(task_id: String, _ok: bool, _message: String, _show: bool) -> void:
	# Aufgehen lässt die Aufgabe das Addon (`plugin.gd`) – auch wenn dieses
	# Fenster längst zu ist. Was war, sagt der Hinweis unten rechts.
	if task_id == _task_id:
		set_process(false)
		shut()


func _process(delta: float) -> void:
	_spin += delta
	_spinner.text = SPINNER[int(_spin / SPIN_SECONDS) % SPINNER.size()]
	var seconds := (Time.get_ticks_msec() - _started) / 1000
	_clock.text = "%d:%02d" % [seconds / 60, seconds % 60]


func _lock(on: bool) -> void:
	_busy = on
	_editor.lock(on)
	for b in _buttons:
		b.disabled = on or _task_id != ""
	_say("Legt an …" if on and not _work.visible else "")


func _say(text: String) -> void:
	_message.text = text
	_message.visible = text != ""
	_message.add_theme_color_override("font_color", Palette.MUTED if _busy else Palette.P2)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		if _editor.menu_open():
			_editor.escape()
		elif not _busy:
			shut()
