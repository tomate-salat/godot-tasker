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
			10:
				_table._plan._open_graph("q5")
			11:
				# Mitten im Aufbau und mit dem Zeiger auf einem Knoten.
				_table._plan._graph.close()
				_table._plan._graph.visible = false
				_table._plan._open_graph("q5")
				_table._plan._graph.set_process(false)
				_table._plan._graph._time = 0.42
			12:
				_table._plan._graph._time = 5.3
				_table._plan._graph._hot = "q4"
				_table._plan._graph._canvas.queue_redraw()
			13:
				# Eine Karte aus dem Vorrat hängt am Zeiger und schwebt über einem Deck.
				var plan = _table._plan
				plan._graph.visible = false
				plan._pressed = plan._left._sheet.get_meta("cards")[1]
				plan._start_drag(Vector2(900, 380))
				# Beim Ziehen zurückblättern, auf die Seite einer leeren Gruppe.
				plan._left.turn(-1)
				plan._flying.position = Vector2(880, 330)
				plan._pointer_speed = Vector2(900, -200)
				plan._last_move = Time.get_ticks_msec() + 5000
				plan._over = plan._right
				plan._right.hover(Vector2(1140, 720), plan._flying.task_id)
			14:
				# Ohne Verbindung fliegt sie zurück.
				_table._plan._drop()
			15:
				# Noch einmal greifen und mit Escape abbrechen: die Karte liegt wieder im Fach.
				var plan = _table._plan
				plan._pressed = plan._left._sheet.get_meta("cards")[1]
				plan._start_drag(Vector2(900, 380))
				plan._over = plan._right
				plan._right.hover(Vector2(1140, 720), plan._flying.task_id)
				var esc := InputEventAction.new()
				esc.action = "ui_cancel"
				esc.pressed = true
				plan._input(esc)
				print("Nach Escape: fliegt=", plan._flying != null, " gedrückt=", plan._pressed != null)
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
