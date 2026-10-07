@tool
extends Window
## Der Graph einer Karte in einem eigenen Fenster – für das Dock, das für ihn
## zu schmal ist. Am Tisch legt er sich stattdessen über die Karten.
##
## Je Karte gibt es höchstens ein Fenster; wer es öffnet, steht in `plugin.gd`.

## Eine Karte des Graphen soll geöffnet werden.
signal task_requested(task_id: String)

const Store := preload("../core/store.gd")
const Palette := preload("palette.gd")
const DepGraphView := preload("dep_graph_view.gd")

## Rand zwischen Graph und Fensterkante.
const EDGE := 10.0

var store: Store
var task_id := ""

var _view: DepGraphView


func _init() -> void:
	# Groß genug, dass der Graph sich beim Öffnen ausbreiten kann; danach
	# schrumpft das Fenster auf ihn.
	size = Vector2i(1280, 760)
	wrap_controls = false
	close_requested.connect(queue_free)
	var back := ColorRect.new()
	back.color = Palette.SURFACE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
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
	# Das Fenster ist der Rahmen: es schließt sich um den Graphen.
	var panel: Control = _view._panel
	var mid := position + size / 2
	size = Vector2i(panel.size + Vector2(EDGE, EDGE) * 2.0)
	position = mid - size / 2
	panel.position = Vector2(EDGE, EDGE)
	# Schließt der Graph sich selbst (Kreuz, Klick daneben), geht das Fenster mit.
	_view.visibility_changed.connect(func() -> void:
		if not _view.visible:
			queue_free())


## Escape schließt das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
