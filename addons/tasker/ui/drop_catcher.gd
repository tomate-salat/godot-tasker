@tool
extends Control
## Fängt eine aus dem Dock gezogene Karte über einem Stück des Editors auf.
##
## Szenenbaum und Viewports nehmen nur ihre eigenen Zieh-Daten an. Solange
## eine Karte gezogen wird, liegt deshalb dieses durchsichtige Feld darüber;
## danach verschwindet es wieder, und alles andere Ziehen bleibt, wie es war.

## Die Karte schwebt an dieser Stelle.
signal hovered(at: Vector2)
signal dropped(at: Vector2, task_id: String)

## So sehen die Zieh-Daten einer Karte aus: `{ type, id }`.
const TYPE := "tasker_task"

## Zeichnet, worauf die Karte fallen würde: bekommt dieses Feld.
var painter := Callable()


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP


static func is_card(data: Variant) -> bool:
	return data is Dictionary and data.get("type") == TYPE and data.get("id") is String


func _can_drop_data(at: Vector2, data: Variant) -> bool:
	if not is_card(data):
		return false
	hovered.emit(at)
	queue_redraw()
	return true


func _drop_data(at: Vector2, data: Variant) -> void:
	dropped.emit(at, data["id"])


func _draw() -> void:
	if painter.is_valid():
		painter.call(self)
