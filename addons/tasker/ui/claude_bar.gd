@tool
extends PanelContainer
## Die Claude-Zeile am unteren Rand des Aufgabenfensters (Nutzer, 2026-10-19):
## ein Feld für eine Anweisung („das Addon heißt Dialogic“, „Frage 2: ja“),
## Senden und „Mehr“ mit den festen Aufträgen. Während Claude arbeitet, zeigt
## dieselbe Zeile, was gerade dran ist; danach, was geändert wurde, mit
## „Rückgängig“.
##
## Gearbeitet wird in `core/claude_tasks.gd`; diese Zeile startet nur und zeigt
## an. Läuft schon ein Auftrag für die Aufgabe – etwa aus dem Schnellanlegen –,
## zeigt sie ihn beim Öffnen gleich.

const ClaudeTasks := preload("../core/claude_tasks.gd")
const SceneTools := preload("../core/scene_tools.gd")
const ClaudeCli := preload("../core/claude_cli.gd")
const Palette := preload("palette.gd")
const Quick := preload("../rules/quick.gd")

const SPINNER := ["◐", "◓", "◑", "◒"]
const SPIN_SECONDS := 0.15

var tasks: ClaudeTasks
var scene_tools: SceneTools
var task_id := ""

var _idle: HBoxContainer
var _input: LineEdit
var _more: MenuButton
var _work: HBoxContainer
var _spinner: Label
var _step: Label
var _clock: Label
var _done: HBoxContainer
var _done_icon: Label
var _done_text: Label
var _undo: Button
var _frame: StyleBoxFlat
var _spin := 0.0
## Der Schnappschuss wird gerade gemacht – noch läuft kein Auftrag.
var _starting := false


func _init() -> void:
	_frame = StyleBoxFlat.new()
	_frame.set_corner_radius_all(8)
	_frame.set_border_width_all(1)
	_frame.set_content_margin_all(6)
	add_theme_stylebox_override("panel", _frame)
	var stack := VBoxContainer.new()
	add_child(stack)

	_idle = HBoxContainer.new()
	_idle.add_theme_constant_override("separation", 6)
	stack.add_child(_idle)
	var spark := TextureRect.new()
	spark.texture = Palette.sparkles_icon()
	spark.modulate = Palette.ACCENT
	spark.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	spark.custom_minimum_size = Vector2(20, 0)
	_idle.add_child(spark)
	_input = LineEdit.new()
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.placeholder_text = "Was soll Claude ändern?"
	_input.tooltip_text = "Eine Anweisung an Claude – etwa „das Addon heißt Dialogic“ oder „Frage 2: ja, eigene UI bleibt“.\nClaude ändert nur, was verlangt ist; auch woran die Aufgabe hängt. Enter schickt ab."
	_input.text_submitted.connect(func(_t: String) -> void: _send_instruction())
	_idle.add_child(_input)
	var send := Button.new()
	send.text = "Senden"
	send.tooltip_text = "Schickt die Anweisung an Claude (Enter)"
	send.pressed.connect(_send_instruction)
	_idle.add_child(send)
	_more = MenuButton.new()
	_more.text = "Mehr ▾"
	_more.flat = false
	_more.tooltip_text = "Feste Aufträge an Claude"
	var menu := _more.get_popup()
	for i in Quick.MODES.size():
		menu.add_item(Quick.LABELS[Quick.MODES[i]], i)
		menu.set_item_tooltip(i, Quick.TOOLTIPS[Quick.MODES[i]])
	menu.id_pressed.connect(func(i: int) -> void: _start(Quick.MODES[i], ""))
	_idle.add_child(_more)

	_work = HBoxContainer.new()
	_work.add_theme_constant_override("separation", 8)
	stack.add_child(_work)
	_spinner = Label.new()
	_spinner.add_theme_color_override("font_color", Palette.ACCENT)
	_work.add_child(_spinner)
	_step = Label.new()
	_step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_step.clip_text = true
	_step.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_work.add_child(_step)
	_clock = Label.new()
	_clock.add_theme_color_override("font_color", Palette.MUTED)
	_work.add_child(_clock)
	var cancel := Button.new()
	cancel.text = "Abbrechen"
	cancel.flat = true
	cancel.tooltip_text = "Claude anhalten – an der Aufgabe ändert sich dann nichts"
	cancel.pressed.connect(func() -> void: tasks.cancel(task_id))
	_work.add_child(cancel)

	_done = HBoxContainer.new()
	_done.add_theme_constant_override("separation", 8)
	stack.add_child(_done)
	_done_icon = Label.new()
	_done.add_child(_done_icon)
	_done_text = Label.new()
	_done_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_done_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_done.add_child(_done_text)
	_undo = Button.new()
	_undo.text = "Rückgängig"
	_undo.tooltip_text = "Nimmt zurück, was Claude geändert hat – Text und Verknüpfungen"
	_undo.pressed.connect(_on_undo)
	_done.add_child(_undo)
	var dismiss := Button.new()
	dismiss.text = "✕"
	dismiss.flat = true
	dismiss.tooltip_text = "Ausblenden"
	dismiss.pressed.connect(_show_idle)
	_done.add_child(dismiss)


func _ready() -> void:
	tasks.progress.connect(_on_progress)
	tasks.finished.connect(_on_finished)
	if tasks.running.has(task_id):
		_show_work(Quick.BUSY.get(tasks.running[task_id], "Claude arbeitet an %s") % "der Aufgabe")
	else:
		_show_idle()


func _send_instruction() -> void:
	var text := _input.text.strip_edges()
	if text == "":
		_input.grab_focus()
		return
	_start(Quick.INSTRUCT, text)


## Macht den Schnappschuss und schickt Claude los.
func _start(mode: String, instruction: String) -> void:
	if _starting or tasks.running.has(task_id):
		return
	_starting = true
	_show_work("„%s“" % instruction if instruction != "" else Quick.LABELS[mode])
	_step.text = "hält fest, was im Editor offen ist"
	var snapshot := await scene_tools.snapshot()
	_starting = false
	if not is_instance_valid(self):
		return
	_step.text = "„%s“" % instruction if instruction != "" else Quick.LABELS[mode]
	tasks.improve(task_id, mode, snapshot, ClaudeCli.PATIENCE_MSEC, instruction, false)


func _on_progress(id: String, line: String) -> void:
	if id == task_id:
		_step.text = line + " …"


func _on_finished(id: String, ok: bool, message: String, _show: bool) -> void:
	if id != task_id:
		return
	_input.text = "" if ok else _input.text
	_set_state(_done, Palette.status_color("done") if ok else Palette.P2)
	_done_icon.text = "✓" if ok else "!"
	_done_icon.add_theme_color_override("font_color", Palette.status_color("done") if ok else Palette.P2)
	_done_text.text = message
	_undo.visible = tasks.can_undo(task_id)


func _on_undo() -> void:
	_undo.disabled = true
	var res: Dictionary = await tasks.undo(task_id)
	if not is_instance_valid(self):
		return
	_undo.disabled = false
	_undo.visible = tasks.can_undo(task_id)
	_done_icon.text = "↶" if res["ok"] else "!"
	_done_text.text = res["message"]


func _show_idle() -> void:
	_set_state(_idle, Palette.LINE_STRONG)


func _show_work(text: String) -> void:
	_set_state(_work, Palette.ACCENT)
	_step.text = text
	_spin = 0.0


func _set_state(shown: Control, edge: Color) -> void:
	for part in [_idle, _work, _done]:
		part.visible = part == shown
	_frame.bg_color = Color(edge, 0.07)
	_frame.border_color = Color(edge, 0.45)
	set_process(shown == _work)


func _process(delta: float) -> void:
	_spin += delta
	_spinner.text = SPINNER[int(_spin / SPIN_SECONDS) % SPINNER.size()]
	var since: int = tasks.started.get(task_id, 0)
	var seconds := (Time.get_ticks_msec() - since) / 1000 if since > 0 else int(_spin)
	_clock.text = "%d:%02d" % [seconds / 60, seconds % 60]
