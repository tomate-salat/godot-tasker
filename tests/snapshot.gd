extends SceneTree
## Entwicklerhilfe: öffnet den Tisch mit Beispieldaten und speichert je ein
## Bild vom Feld und von der Planung unter `.godot/tasker_tisch_<n>.png`.
##   godot --path . -s tests/snapshot.gd

const TableWindow := preload("res://addons/tasker/ui/table_window.gd")

var _table: TableWindow
var _elapsed := 0.0
var _step := 0


func _process(delta: float) -> bool:
	_elapsed += delta
	if _step == 0:
		_table = TableWindow.new()
		root.add_child(_table)
		_table.popup_centered()
		_step = 1
		_elapsed = 0.0
	elif _elapsed > 2.0:
		_table.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://.godot/tasker_tisch_%d.png" % _step))
		if _step == 1:
			_table.lage = true
		else:
			quit()
		_step += 1
		_elapsed = 0.0
	return false
