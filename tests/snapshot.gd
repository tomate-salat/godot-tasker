extends SceneTree
## Entwicklerhilfe: öffnet den Tisch mit Beispieldaten, spielt ein paar Züge
## und speichert nach jedem ein Bild unter `.godot/tasker_tisch_<n>.png`.
##   godot --path . -s tests/snapshot.gd

const TableWindow := preload("res://addons/tasker/ui/table_window.gd")

var _table: TableWindow
var _elapsed := 0.0
var _step := 0
var _shots := 0


func _process(delta: float) -> bool:
	_elapsed += delta
	if _step == 0:
		_table = TableWindow.new()
		root.add_child(_table)
		_table.popup_centered()
		_next()
	elif _elapsed > 0.9:
		_shot()
		match _step:
			1:
				# Fünf Karten ziehen, darunter gezielt den Stapel.
				seed(7)
				for i in 4:
					_table._draw_from_deck()
				if not _table._state["hand"].has("d"):
					_table._set_browse(true)
					_table._take_from_deck("d")
					_table._set_browse(false)
			2:
				_table._open_stack(["d"])
			3:
				# Eine Unteraufgabe ausspielen, eine Handkarte ablegen wollen, die nicht darf.
				_table._drop("d3", _table._geometry()["play"].get_center())
				_table._drop("b", _table._geometry()["pile"].get_center())
			4:
				_table._drop("h", _table._geometry()["pile"].get_center())
				_table._set_browse(true)
			_:
				return true
		_next()
	return false


func _next() -> void:
	_step += 1
	_elapsed = 0.0


func _shot() -> void:
	_shots += 1
	var out := ProjectSettings.globalize_path("res://.godot/tasker_tisch_%d.png" % _shots)
	_table.get_texture().get_image().save_png(out)
	print("Bild: ", out)
