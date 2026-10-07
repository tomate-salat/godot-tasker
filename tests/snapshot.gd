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
			5:
				_table._set_shelf(true)
			6:
				_table._close_overlays()
				_table._pressed = _table._cards["b"]
				_table._gap = 0
				_table._cards["b"].set_tilt(Vector2(-0.8, 0.3))
				_table._cards["b"].scale = Vector2(0.86, 1.04)
				_table._place()
			7:
				_table._pressed = null
				_table.planning = true
				_table._plan._fanned["r2"] = true
			8:
				_table._plan._fanned["n3"] = true
				_table._plan._show_stock("backlog")
				_table._plan._refan()
			9:
				# Mitten im Umblättern anhalten.
				_table._plan._left.turn(1)
				_table._plan._left._flip.custom_step(0.3)
				_table._plan._left._flip.pause()
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
