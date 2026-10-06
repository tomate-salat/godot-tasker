extends SceneTree
## Entwicklerhilfe: öffnet den Tisch mit Beispieldaten, speichert ein Bild und
## beendet sich wieder.
##   godot --path . -s tests/snapshot.gd

const TableWindow := preload("res://addons/tasker/ui/table_window.gd")

var _table: TableWindow
var _elapsed := 0.0
var _step := 0


func _process(delta: float) -> bool:
	_elapsed += delta
	if _step == 0:
		_step = 1
		_table = TableWindow.new()
		root.add_child(_table)
		_table.popup_centered()
	elif _step == 1 and _elapsed > 1.5:
		_step = 2
		# Ohne Server gibt es keine Titelbilder – eines von Hand, um die Karte damit zu sehen.
		var cards: Array = _table._zones.get("open", [])
		if cards.size() > 3:
			cards[3]._set_cover(_test_cover())
			cards[1]._set_cover(_test_cover())
	elif _step == 2 and _elapsed > 2.0:
		_step = 3
		var out := ProjectSettings.globalize_path("res://.godot/tasker_snapshot.png")
		_table.get_texture().get_image().save_png(out)
		print("Bild: ", out)
	# Beendet sich in jedem Fall, auch wenn vorher etwas schiefging.
	return _elapsed > 2.5


func _test_cover() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color("f2c14e"), Color("d1495b"), Color("edf2f4")])
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	var image := noise.get_image(256, 256)
	for y in 256:
		for x in 256:
			image.set_pixel(x, y, gradient.sample(image.get_pixel(x, y).r))
	return ImageTexture.create_from_image(image)
