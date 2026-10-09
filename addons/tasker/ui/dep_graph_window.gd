@tool
extends "card_window.gd"
## Der Graph einer Karte in einem eigenen Fenster – für das Dock, das für ihn
## zu schmal ist. Am Tisch legt er sich stattdessen über die Karten.
##
## Je Karte gibt es höchstens ein Fenster; wer es öffnet, steht in `plugin.gd`.

## Eine Karte des Graphen soll geöffnet werden.
signal task_requested(task_id: String)

const Store := preload("../core/store.gd")
const DepGraphView := preload("dep_graph_view.gd")


var store: Store
var task_id := ""

var _view: DepGraphView


func _init() -> void:
	super()
	# Die Karte trägt die Farben des Graphen, wie er am Tisch über den Karten liegt.
	fill = Color("141a18")
	edge_color = Palette.SURFACE.lerp(Palette.ACCENT, 0.6)
	# Groß genug, dass der Graph sich beim Öffnen ausbreiten kann; danach
	# schrumpft das Fenster auf ihn.
	size = Vector2i(1280, 760)
	min_size = Vector2i(480, 240)
	close_requested.connect(shut)
	_view = DepGraphView.new()
	_view.task_requested.connect(func(id: String) -> void: task_requested.emit(id))
	add_child(_view)


func _ready() -> void:
	var item = store.ws.task(task_id) if store != null else null
	if item == null:
		queue_free()
		return
	var name: String = item["title"] if item.get("title") else "Ohne Titel"
	title = "Abhängigkeiten: $%d  %s" % [int(item.get("ref", 0)), name]
	_view.open(store.ws, item, store.project_id)
	# Das Fenster ist die Karte: Rahmen und Grund des Graphen weichen ihr, und
	# es schließt sich um ihn.
	var panel: Control = _view._panel
	var plain := StyleBoxEmpty.new()
	plain.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", plain)
	_view._dim.visible = false
	var mid := position + size / 2
	size = Vector2i(panel.size) + Vector2i(_edge, _edge) * 2
	position = mid - size / 2
	_fit()
	size_changed.connect(_fit)
	# Am Graphen greift man die Karte wie an ihrem Rand.
	panel.gui_input.connect(_on_face_input)
	_view.closer = shut
	# Schließt der Graph sich selbst (Kreuz), geht das Fenster mit.
	_view.visibility_changed.connect(func() -> void:
		if not _view.visible:
			queue_free())


## Der Graph füllt die Karte, auch wenn sie ihre Größe ändert.
func _fit() -> void:
	var panel: Control = _view._panel
	panel.position = face.position
	panel.size = face.size
	panel.pivot_offset = panel.size / 2.0


## Escape schließt das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		shut()
