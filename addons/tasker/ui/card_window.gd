@tool
extends Window
## Ein Fenster, das selbst eine Karte ist: ohne Titelleiste, mit runden Ecken
## und Schatten. Was das Betriebssystem sonst mitbringt – verschieben, Größe
## ändern, schließen – macht die Karte selbst.
##
## Wer davon erbt, baut seinen Inhalt in `face` und setzt `size` und
## `min_size` auf die Maße der Karte; der Rand für den Schatten kommt dazu,
## sobald das Fenster im Baum ist.

const Palette := preload("palette.gd")

const RADIUS := 18
## Der durchsichtige Rand um die Karte, in dem ihr Schatten liegt.
const SHADOW := 28
const GRIP := 16.0
## So weit sitzt der Griff von der Ecke der Karte.
const GRIP_INSET := 11.0
const POP_FROM := 0.965
const OPEN_SECONDS := 0.28
## So lange blendet die Karte beim Öffnen ein.
const FADE_SECONDS := 0.2
const SHUT_SECONDS := 0.12
## So viele Bilder braucht ein neues Bild, bis es sicher im Fenster angekommen ist.
const LAG_FRAMES := 3
## In diesem Bild nach dem Öffnen liegt die Karte an ihrem Platz, ist aber noch nicht zu sehen.
const PHOTO_FRAME := 2

## Die Karte: hier hinein kommt der Inhalt.
var face: PanelContainer
## Runde Ecken auch dort, wo das Fenster nicht durchsichtig sein kann – für Bildproben.
var force_round := false
## Grund und Rand der Karte – vor dem Einhängen zu setzen.
var fill := Palette.SURFACE
var edge_color := Palette.LINE_STRONG
## Mit Schattenrand, wo das Fenster durchsichtig sein darf. Ohne ihn füllt der
## Inhalt das Fenster bis an die Kante – für den Tisch, der mit der ganzen
## Fensterfläche rechnet.
var shadow := true
## Der Rand der Karte liegt über dem Inhalt statt darunter – wenn der Inhalt
## die Karte bis an die Kante bemalt.
var rim_on_top := false
## Die Karte bleibt vor dem Editor, auch wenn man in ihn klickt. Je Fenster
## über die Stecknadel umzuschalten.
var in_front := true: set = set_in_front
## Die Karte wird nur kurz versteckt und neu gezeigt, um umzuschalten – kein
## Öffnen, bei dem etwas neu aufgebaut werden müsste.
var reshowing := false
var _switching := false
## Neu gezeigt ohne Animation: nur warten, bis das erste Bild da ist.
var _quiet := false

## Wie groß die Karte gerade gezeigt wird: beim Öffnen wächst sie ein wenig
## auf 1, beim Schließen schrumpft sie wieder.
var _pop := 1.0: set = _set_pop
var _closing := false
## Wie groß der Umriss des Fensters gerade ist.
var _shape := 1.0
## Auf einen Punkt zugeschnitten: das Fenster ist da, aber nicht zu sehen.
var _unseen := false
var _following := false
var _frames := 0
var _time := 0.0
var _trail: Array[float] = []
## Beim Schließen über das Foto ausblenden – sonst nur schrumpfen.
var _fading := false
## Das Foto dessen, was hinter der Karte liegt, über ihrem Inhalt.
var _veil_layer: CanvasLayer
var _veil: TextureRect
var _back_layer: CanvasLayer
var _back: TextureRect
var _veil_rect := Rect2i()
## Auf den ganzen Bildschirm gebracht – und wo die Karte vorher lag.
var _maxed := false
var _restore := Rect2i()

var _edge := 0
var _framed := false
## Ohne Durchsichtigkeit: das Fenster ist auf die Kartenform zugeschnitten.
var _cut := false
var _grip: Control
## Verschieben und Größe ändern von Hand, wo das Betriebssystem es nicht übernimmt.
var _moving := false
var _sizing := false
var _grab_mouse := Vector2i.ZERO
var _grab_value := Vector2i.ZERO


func _init() -> void:
	borderless = true
	always_on_top = true
	wrap_controls = false
	face = PanelContainer.new()
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.gui_input.connect(_on_face_input)
	add_child(face)
	tree_entered.connect(_frame)
	tree_exiting.connect(_stop_following)
	size_changed.connect(func() -> void:
		_pop = _pop
		_update_passthrough())
	visibility_changed.connect(_pop_open)


## Hält die Karte vor allen anderen Fenstern oder gibt sie frei.
##
## An das Fenster des Editors binden (`transient`) hält ein Fenster unter
## Windows nicht vorn, darum „immer im Vordergrund“ – und das wirkt nur
## sauber, wenn es beim Erzeugen des Fensters gesetzt ist. Eine offene Karte
## muss also kurz weg und neu her.
func set_in_front(value: bool) -> void:
	in_front = value
	if always_on_top == value:
		return
	if not is_inside_tree() or not visible or is_embedded():
		always_on_top = value
		return
	if not _switching:
		_switch_front()


## Tauscht das Fenster gegen eines mit der anderen Einstellung, ohne dass man
## es sieht: solange es weg ist, steht ein Bild der Karte an seiner Stelle.
func _switch_front() -> void:
	_switching = true
	var tiny := PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])
	var stand := Window.new()
	stand.borderless = true
	stand.always_on_top = true
	stand.unfocusable = true
	stand.position = position
	stand.size = size
	var picture := TextureRect.new()
	picture.texture = ImageTexture.create_from_image(get_texture().get_image())
	picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	stand.add_child(picture)
	# Auch das Bild zeigt sich erst, wenn es im Fenster angekommen ist.
	stand.mouse_passthrough_polygon = tiny
	get_parent().add_child(stand)
	var tree := get_tree()
	var clear := func() -> void:
		if is_instance_valid(stand):
			stand.queue_free()
	tree_exiting.connect(clear)
	for i in LAG_FRAMES + 2:
		await tree.process_frame
	stand.mouse_passthrough_polygon = mouse_passthrough_polygon if _cut else PackedVector2Array()
	for i in LAG_FRAMES:
		await tree.process_frame
	reshowing = true
	hide()
	always_on_top = in_front
	show()
	reshowing = false
	for i in LAG_FRAMES * 2 + 4:
		await tree.process_frame
	tree_exiting.disconnect(clear)
	stand.queue_free()
	_switching = false
	if visible and always_on_top != in_front:
		_switch_front()


## Zeigt die Karte mittig über dem Fenster, zu dem sie gehört. Statt
## `popup_centered()`: das bindet das Fenster an seinen Elter, und ein
## gebundenes Fenster darf nicht „immer im Vordergrund" sein.
func open_centered() -> void:
	var host := get_parent().get_window() if get_parent() != null else null
	if host != null and not is_embedded():
		position = host.position + (host.size - size) / 2
	elif host != null:
		position = (host.size - size) / 2
	show()


## Eine Stecknadel für die Kopfzeile: hält die Karte vor dem Editor oder lässt
## sie dahinter verschwinden.
func pin_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.toggle_mode = true
	button.button_pressed = in_front
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(24, 0)
	button.tooltip_text = "Im Vordergrund halten, auch wenn man in den Editor klickt"
	button.toggled.connect(func(on: bool) -> void:
		in_front = on
		button.queue_redraw())
	button.mouse_entered.connect(button.queue_redraw)
	button.mouse_exited.connect(button.queue_redraw)
	button.draw.connect(func() -> void:
		# Eine Nadel in dünnen Linien, im Ton des Kreuzes daneben: angeheftet
		# mit gefülltem Kopf, sonst blass und nur als Umriss.
		var color := Palette.FAINT
		if button.is_hovered():
			color = Palette.INK
		elif in_front:
			color = Palette.MUTED
		button.draw_set_transform(button.size / 2.0 + Vector2(0.5, 0.0), deg_to_rad(45.0))
		var head := PackedVector2Array([Vector2(-2.0, -6.5), Vector2(2.0, -6.5), Vector2(2.0, -2.0), Vector2(4.0, 0.5), Vector2(-4.0, 0.5), Vector2(-2.0, -2.0)])
		if in_front:
			button.draw_colored_polygon(head, color)
		head.append(head[0])
		button.draw_polyline(head, color, 1.0, true)
		button.draw_line(Vector2(0.0, 0.5), Vector2(0.0, 6.5), color, 1.0, true)
		button.draw_set_transform(Vector2.ZERO))
	return button


## Ein Kreuz, das die Karte schließt – für die Kopfzeile.
func close_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.text = "✕"
	button.tooltip_text = "Schließen (Esc)"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Palette.MUTED)
	button.add_theme_color_override("font_hover_color", Palette.INK)
	button.pressed.connect(func() -> void: close_requested.emit())
	return button


## Je ein Knopf für die Kopfzeile, der das Fenster auf den ganzen Bildschirm
## bringt und zurück.
func max_button() -> Button:
	var button := Button.new()
	button.flat = true
	button.text = "▢"
	button.tooltip_text = "Maximieren / Wiederherstellen"
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Palette.MUTED)
	button.add_theme_color_override("font_hover_color", Palette.INK)
	button.pressed.connect(toggle_max)
	return button


## Bringt die Karte auf die ganze nutzbare Bildschirmfläche und zurück. Von
## Hand statt über den Fenstermodus: der wirft bei rahmenlosen Fenstern Fehler
## und würde die Taskleiste überdecken.
func toggle_max() -> void:
	if is_embedded():
		return
	if _maxed:
		_maxed = false
		position = _restore.position
		size = _restore.size
	else:
		_restore = Rect2i(position, size)
		# Einen Pixel unter der vollen Fläche: deckt ein rahmenloses Fenster sie
		# genau, behandelt Godot es als Vollbild und wirft Fehler.
		var area := DisplayServer.screen_get_usable_rect(current_screen).grow(-1)
		_maxed = true
		position = area.position
		size = area.size
	_update_passthrough()


# ------------------------------------------------- Öffnen und Schließen

## Schließt die Karte: sie blendet aus und ist dann weg.
##
## Durchsichtig kann ein Fenster im Editor nicht sein. Die Karte fotografiert
## deshalb beim Öffnen – solange sie noch unsichtbar ist –, was an ihrer
## Stelle auf dem Bildschirm liegt, und blendet beim Schließen dieses Foto
## über sich ein. Das stimmt nur, solange sie liegt, wo sie lag; sonst
## schrumpft sie bloß kurz.
func shut() -> void:
	if _closing:
		return
	_closing = true
	_unseen = false
	_time = 0.0
	_fading = _veil != null and _veil.texture != null and _veil_rect == Rect2i(position, size)
	if _fading:
		_shape = 1.0
		_update_passthrough()
		_veil.modulate.a = 0.0
		_veil_layer.visible = true
	_start_following()


## Was nach dem Schließen mit dem Fenster geschieht. Wer es nur versteckt,
## überschreibt das.
func _gone() -> void:
	queue_free()


func _pop_open() -> void:
	if not _framed or not visible:
		return
	_closing = false
	if _veil_layer != null:
		_veil_layer.visible = false
		_back_layer.visible = false
	if reshowing:
		# Nur umgeschaltet: die Karte steht sofort ganz da, sobald ihr erstes Bild angekommen ist.
		_frames = 0
		_pop = 1.0
		_shape = 1.0
		_quiet = true
		_unseen = _cut
		_update_passthrough()
		_start_following()
		return
	_frames = 0
	_time = 0.0
	_trail.clear()
	_pop = POP_FROM
	_shape = POP_FROM
	# Bis das erste Bild im Fenster angekommen ist, ist es auf einen Punkt
	# zugeschnitten – sonst sähe man kurz leere Fensterfläche.
	_unseen = _cut
	_update_passthrough()
	_start_following()


## Ein Bild weiter. Gezählt wird in Bildern und mit gedeckelter Zeit: die
## ersten Bilder eines neuen Fensters dauern lange, sonst springt die Karte.
func _follow() -> void:
	_frames += 1
	if _closing:
		_time += minf(get_process_delta_time(), 1.0 / 50.0)
		var out := ease(minf(_time / SHUT_SECONDS, 1.0), 2.0)
		if _fading:
			# Nur blenden, nicht schrumpfen: sonst wächst am Rand ein Streifen Kartengrund hervor.
			_veil.modulate.a = out
		else:
			_pop = lerpf(1.0, POP_FROM, out)
			_shape = _pop
			_update_passthrough()
		if out >= 1.0:
			_stop_following()
			_closing = false
			_gone()
		return
	if _quiet:
		if _frames > LAG_FRAMES + 1:
			_quiet = false
			_unseen = false
			_update_passthrough()
			_stop_following()
		return
	if _frames == PHOTO_FRAME and _cut:
		_take_photo()
	if _veil != null and _veil.texture != null:
		# Mit Foto: es liegt über der Karte und blendet aus, und es liegt
		# hinter ihr – dort füllt es den Rand, solange sie noch kleiner ist.
		if _frames <= PHOTO_FRAME + LAG_FRAMES:
			return
		if _unseen:
			_unseen = false
			_shape = 1.0
			_update_passthrough()
		_time += minf(get_process_delta_time(), 1.0 / 50.0)
		_pop = lerpf(POP_FROM, 1.0, ease(minf(_time / OPEN_SECONDS, 1.0), 0.4))
		_veil.modulate.a = 1.0 - ease(minf(_time / FADE_SECONDS, 1.0), 0.6)
		if _time >= OPEN_SECONDS:
			_veil_layer.visible = false
			_back_layer.visible = false
			_stop_following()
		return
	if _frames <= LAG_FRAMES:
		return
	_unseen = false
	_time += minf(get_process_delta_time(), 1.0 / 50.0)
	_pop = lerpf(POP_FROM, 1.0, ease(minf(_time / OPEN_SECONDS, 1.0), 0.4))
	# Ohne Foto: der Umriss greift sofort, das Bild kommt ein paar Bilder
	# später an – beim Wachsen läuft der Umriss deshalb hinterher.
	_trail.append(_pop)
	if _trail.size() > LAG_FRAMES:
		_shape = _trail.pop_front()
	_update_passthrough()
	if _shape >= 1.0:
		_stop_following()


## Hält fest, was gerade an der Stelle der Karte auf dem Bildschirm liegt, und
## legt es über und hinter sie.
func _take_photo() -> void:
	if _veil == null:
		_veil_layer = CanvasLayer.new()
		_veil_layer.layer = 100
		add_child(_veil_layer)
		_veil = _photo_rect()
		_veil_layer.add_child(_veil)
		_back_layer = CanvasLayer.new()
		_back_layer.layer = -100
		add_child(_back_layer)
		_back = _photo_rect()
		_back_layer.add_child(_back)
	_veil_rect = Rect2i(position, size)
	var shot := DisplayServer.screen_get_image_rect(_veil_rect)
	_veil.texture = ImageTexture.create_from_image(shot) if shot != null and not shot.is_empty() else null
	_back.texture = _veil.texture
	_veil.modulate.a = 1.0
	_veil_layer.visible = _veil.texture != null
	_back_layer.visible = _veil.texture != null


func _photo_rect() -> TextureRect:
	var rect := TextureRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


func _start_following() -> void:
	if not _following:
		_following = true
		get_tree().process_frame.connect(_follow)


func _stop_following() -> void:
	if _following:
		_following = false
		get_tree().process_frame.disconnect(_follow)


## Der ganze Inhalt wird um die Fenstermitte verkleinert gezeichnet.
func _set_pop(value: float) -> void:
	_pop = value
	if not is_inside_tree():
		return
	var mid := Vector2(size) / 2.0
	canvas_transform = Transform2D(0.0, Vector2(value, value), 0.0, mid * (1.0 - value))


## Gibt der Karte ihre Form. Wie, steht erst fest, wenn das Fenster im Baum ist:
## Darf es durchsichtig sein, bekommt die Karte runde Ecken und einen Schatten.
## Der Editor erlaubt das seinen Fenstern nicht – dort schneidet das Fenster
## sich selbst auf die runde Form zu, ohne Schatten.
func _frame() -> void:
	if _framed:
		return
	_framed = true
	var clear := shadow and (force_round or is_embedded() or DisplayServer.is_window_transparency_available())
	_cut = not clear and not is_embedded()
	_edge = SHADOW if clear else 0
	transparent = clear
	transparent_bg = clear

	if _cut:
		# Hinter der Karte liegt ihre Randfarbe, damit an der geschnittenen
		# Kante nichts Schwarzes durchblitzt.
		var under := Panel.new()
		var ground := StyleBoxFlat.new()
		ground.bg_color = edge_color
		# Selbst rund – ist die Karte beim Öffnen noch kleiner als ihr Fenster,
		# stünden sonst eckige Ecken hervor –, aber etwas weniger als der
		# Zuschnitt, damit an dessen Kante nichts durchblitzt.
		ground.set_corner_radius_all(RADIUS - 4)
		under.add_theme_stylebox_override("panel", ground)
		under.set_anchors_preset(Control.PRESET_FULL_RECT)
		under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(under)
		move_child(under, 0)

	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = edge_color
	style.set_border_width_all(1)
	var radius := RADIUS if clear or _cut else 0
	style.set_corner_radius_all(radius)
	style.anti_aliasing_size = 0.6
	if clear:
		style.shadow_color = Color(0, 0, 0, 0.42)
		style.shadow_size = 18
		style.shadow_offset = Vector2(0, 6)
	face.add_theme_stylebox_override("panel", style)
	face.offset_left = _edge
	face.offset_top = _edge
	face.offset_right = -_edge
	face.offset_bottom = -_edge
	min_size += Vector2i(_edge, _edge) * 2
	size += Vector2i(_edge, _edge) * 2

	_grip = Control.new()
	_grip.custom_minimum_size = Vector2(GRIP, GRIP)
	_grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_grip.offset_left = -_edge - GRIP - GRIP_INSET
	_grip.offset_top = -_edge - GRIP - GRIP_INSET
	_grip.offset_right = -_edge - GRIP_INSET
	_grip.offset_bottom = -_edge - GRIP_INSET
	_grip.mouse_default_cursor_shape = Control.CURSOR_FDIAGSIZE
	_grip.tooltip_text = "Ziehen ändert die Größe"
	_grip.draw.connect(_draw_grip)
	_grip.gui_input.connect(_on_grip_input)
	add_child(_grip)
	if rim_on_top:
		var rim := Panel.new()
		var line := StyleBoxFlat.new()
		line.bg_color = Color(0, 0, 0, 0)
		line.border_color = edge_color
		line.set_border_width_all(1)
		line.set_corner_radius_all(radius)
		line.anti_aliasing_size = 0.6
		rim.add_theme_stylebox_override("panel", line)
		rim.set_anchors_preset(Control.PRESET_FULL_RECT)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rim.z_index = RenderingServer.CANVAS_ITEM_Z_MAX
		add_child(rim)
	_update_passthrough()
	_pop_open()


## Das Fenster endet, wo die Karte endet: im Schattenrand gehen Klicks an das,
## was dahinter liegt, und ohne Durchsichtigkeit schneidet derselbe Umriss die
## Ecken rund.
func _update_passthrough() -> void:
	if not _framed:
		return
	if _unseen:
		mouse_passthrough_polygon = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(0, 1)])
		return
	# Ohne Rand und ohne Zuschnitt – oder auf dem ganzen Bildschirm – bleibt das Fenster ein Rechteck.
	if (not _cut and _edge == 0) or (_maxed and _shape >= 1.0):
		mouse_passthrough_polygon = PackedVector2Array()
		return
	var r := Rect2(Vector2(_edge, _edge), Vector2(size) - Vector2(_edge, _edge) * 2.0)
	var outline := PackedVector2Array()
	if _cut:
		var corners := [r.position + Vector2(RADIUS, RADIUS), Vector2(r.end.x - RADIUS, r.position.y + RADIUS), r.end - Vector2(RADIUS, RADIUS), Vector2(r.position.x + RADIUS, r.end.y - RADIUS)]
		for i in 4:
			for step in 13:
				var angle := PI + i * PI / 2.0 + step * PI / 24.0
				outline.append(corners[i] + Vector2(cos(angle), sin(angle)) * RADIUS)
	else:
		outline = PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	# Wächst oder schrumpft die Karte gerade, geht der Umriss mit.
	var mid := Vector2(size) / 2.0
	for i in outline.size():
		outline[i] = mid + (outline[i] - mid) * _shape
	mouse_passthrough_polygon = outline


func _draw_grip() -> void:
	for i in 3:
		var d := 4.0 + i * 4.0
		_grip.draw_line(Vector2(GRIP, GRIP - d), Vector2(GRIP - d, GRIP), Palette.FAINT, 1.5, true)


## Wo nichts anderes den Klick nimmt, greift man die Karte und verschiebt sie.
func _on_face_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_moving = false
		elif is_embedded():
			_moving = true
			_grab_mouse = DisplayServer.mouse_get_position()
			_grab_value = position
		else:
			DisplayServer.window_start_drag(get_window_id())
	elif event is InputEventMouseMotion and _moving:
		position = _grab_value + DisplayServer.mouse_get_position() - _grab_mouse


func _on_grip_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_sizing = false
		elif is_embedded():
			_sizing = true
			_grab_mouse = DisplayServer.mouse_get_position()
			_grab_value = size
		else:
			DisplayServer.window_start_resize(DisplayServer.WINDOW_EDGE_BOTTOM_RIGHT, get_window_id())
	elif event is InputEventMouseMotion and _sizing:
		var wanted := _grab_value + DisplayServer.mouse_get_position() - _grab_mouse
		size = Vector2i(maxi(wanted.x, min_size.x), maxi(wanted.y, min_size.y))
