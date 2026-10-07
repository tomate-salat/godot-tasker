@tool
extends Window
## Ein Bild oder eine Zeichnung in groß, zum Hineinzoomen.
##
## Das Mausrad zoomt auf die Stelle unter dem Zeiger, Ziehen verschiebt, ein
## Doppelklick passt das Bild wieder ein, Escape schließt.

const Palette := preload("palette.gd")

const ZOOM_STEP := 1.2
const MAX_ZOOM := 8.0

var texture: Texture2D

var _view: Control
var _hint: Label
var _zoom := 1.0
## Wo die linke obere Ecke des Bildes im Fenster liegt.
var _offset := Vector2.ZERO
## Solange nicht gezoomt oder verschoben wurde, bleibt das Bild eingepasst.
var _fitted := true
var _panning := false


func _init() -> void:
	size = Vector2i(1100, 800)
	min_size = Vector2i(320, 240)
	wrap_controls = false
	close_requested.connect(queue_free)
	size_changed.connect(func() -> void:
		if _fitted:
			fit())

	var back := ColorRect.new()
	back.color = Palette.SURFACE.darkened(0.25)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)

	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.clip_contents = true
	_view.draw.connect(_draw_view)
	_view.gui_input.connect(_on_input)
	add_child(_view)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hint.offset_left = 10
	_hint.offset_top = -28
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)


func _ready() -> void:
	fit()


## Passt das Bild ins Fenster ein, ohne es über seine eigene Größe zu vergrößern.
func fit() -> void:
	if texture == null:
		return
	var room := Vector2(size) - Vector2(32, 32)
	var image := texture.get_size()
	_zoom = minf(1.0, minf(room.x / image.x, room.y / image.y))
	_offset = (Vector2(size) - image * _zoom) / 2.0
	_fitted = true
	_update()


func _update() -> void:
	_hint.text = "%d %%   ·   Mausrad zoomt, Ziehen verschiebt, Doppelklick passt ein" % roundi(_zoom * 100.0)
	_view.queue_redraw()


func _draw_view() -> void:
	if texture != null:
		_view.draw_texture_rect(texture, Rect2(_offset, texture.get_size() * _zoom), false)


func _on_input(event: InputEvent) -> void:
	if texture == null:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(event.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(event.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE:
				if event.pressed and event.double_click:
					_panning = false
					fit()
				else:
					_panning = event.pressed
	elif event is InputEventMouseMotion and _panning:
		_offset += event.relative
		_fitted = false
		_update()


## Zoomt so, dass der Punkt unter dem Zeiger an seiner Stelle bleibt.
func _zoom_at(at: Vector2, factor: float) -> void:
	var image := texture.get_size()
	var smallest := minf(1.0, minf(size.x / image.x, size.y / image.y) * 0.5)
	var next := clampf(_zoom * factor, smallest, MAX_ZOOM)
	_offset = at - (at - _offset) * (next / _zoom)
	_zoom = next
	_fitted = false
	_update()


## Escape schließt das Fenster.
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		set_input_as_handled()
		queue_free()
