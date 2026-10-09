@tool
extends Control
## Ein Stapel, aus dem Ordner gezogen und aufgefächert.
##
## Die Karte gleitet aus ihrem Fach nach oben in die Mitte, ihre Unteraufgaben
## fächern sich darunter auf. Ein Klick auf einen Stapel darin geht eine Ebene
## tiefer: er rückt nach oben neben seine Eltern-Karte, und seine
## Unteraufgaben fächern sich auf. Beim Schließen sammelt sich alles wieder
## ein, und die Karte gleitet zurück in ihr Fach.
##
## Hier wird nur angesehen: gezogen wird im Ordner, und Unteraufgaben wandern
## mit ihrer Karte.

## Eine Karte soll geöffnet werden.
signal task_requested(id: String)
## Rechtsklick auf eine Karte.
signal menu_requested(id: String)
## Alles ist wieder eingesammelt, die Karte liegt im Fach.
signal closed

const Card := preload("card.gd")
const Palette := preload("palette.gd")
const Workspace := preload("../rules/workspace.gd")

## So groß liegen die Karten des Wegs oben, die letzte etwas größer.
const PATH_SCALE := 0.72
const HEAD_SCALE := 0.9
const PATH_Y := 118.0
const PATH_STEP := 116.0
## Abstand der aufgefächerten Karten und wie weit der Fächer sich wölbt.
const FAN_STEP := 146.0
const ROW_STEP := 198.0
const FAN_TURN := 2.6
const FAN_DROP := 5.0
const EDGE := 70.0
const MOVE_SECONDS := 0.42
const STAGGER := 0.05
## Der Stapel wird langsam aus seinem Fach gezogen (eine Kartenhöhe mal
## `PULL`) und gleitet dann zügig an seinen Platz.
const PULL_SECONDS := 0.58
const FLY_SECONDS := 0.36
const PULL := 1.04
## Die Karten des Wegs liegen über dem Fächer: die Unteraufgaben gleiten
## unter dem Stapel hervor und wieder darunter.
const PATH_Z := 60
## So lange nach einem Klick zählt ein zweiter noch als Doppelklick auf
## dieselbe Karte – auch wenn sie inzwischen unter dem Zeiger weggeglitten ist.
const DOUBLE_CLICK_MS := 400

var _ws: Workspace
var _images: Node
## Der Weg vom Stapel aus dem Ordner bis zur Karte, deren Unteraufgaben gerade
## aufgefächert sind – als Aufgaben-IDs.
var _path: Array = []
## Wo die Karte im Ordner liegt (im Fenster gemessen), als Rect2 – oder null,
## wenn ihr Fach nicht aufgeschlagen ist.
var _home: Callable
var _cards := {}
var _dim: ColorRect
var _layer: Control
var _label: Label
var _hint: Label
var _closing := false
## Die Karte gleitet noch aus ihrem Fach.
var _opening := false
var _last_click := ""
var _last_click_at := 0


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 90

	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.07, 0.06, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim)
	add_child(_dim)

	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_label.offset_top = PATH_Y + Card.SIZE.y * HEAD_SCALE / 2.0 + 14.0
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.72))
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	_hint = Label.new()
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_top = -84.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.text = "Klick auf einen Stapel fächert weiter auf  ·  Doppelklick öffnet die Aufgabe  ·  Escape geht zurück"
	add_child(_hint)

	_layer = Control.new()
	_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_layer)
	resized.connect(func() -> void:
		if visible and not _closing:
			_arrange(false))


func is_open() -> bool:
	return visible


## Zieht den Stapel dieser Aufgabe aus dem Ordner. `home` sagt, wo seine Karte
## dort liegt (Rect2 im Fenster, oder null).
func open(ws: Workspace, images: Node, task_id: String, home: Callable) -> void:
	_clear()
	_ws = ws
	_images = images
	_home = home
	_path = [task_id]
	_closing = false
	visible = true
	_dim.modulate.a = 0.0
	_label.modulate.a = 0.0
	_hint.modulate.a = 0.0
	var fade := create_tween().set_parallel()
	fade.tween_property(_dim, "modulate:a", 1.0, 0.2)
	fade.tween_property(_label, "modulate:a", 1.0, 0.3).set_delay(0.15)
	fade.tween_property(_hint, "modulate:a", 1.0, 0.3).set_delay(0.3)
	# Die Karte beginnt dort, wo sie im Ordner liegt. Sie gleitet in einem Zug
	# nach oben aus ihrem Fach – wie eine Karte aus der Hülle – und im Bogen in
	# die Mitte. Erst wenn der Stapel dort liegt, gleiten die Unteraufgaben
	# unter ihm hervor an ihre Plätze.
	var card := _make(task_id)
	if card != null and _put_at_home(card):
		_opening = true
		card.z_index = PATH_Z
		card.tight = true
		await _travel(card, _center_to_position(Vector2(size.x / 2.0, PATH_Y)), HEAD_SCALE, true)
		_opening = false
		card.tight = false
		if not visible or _closing or _path != [task_id]:
			return
	_arrange(true)


## Der Stand hat sich geändert: die Karten zeigen den neuen. Gibt es den
## Stapel nicht mehr, ist der Fächer weg.
func refresh(ws: Workspace) -> void:
	if not visible or _closing:
		return
	_ws = ws
	while not _path.is_empty() and (_ws.task(_path[-1]) == null or _ws.kids(_path[-1]).is_empty()):
		_path.pop_back()
	if _path.is_empty():
		_clear()
		visible = false
		closed.emit()
		return
	for id: String in _cards.keys():
		var t = _ws.task(id)
		if t != null:
			_cards[id].show_task(_ws, t, _images)
	_arrange(true)


## Eine Ebene zurück – ganz oben schließt das den Fächer.
func back() -> void:
	if _closing:
		return
	if _path.size() <= 1:
		close()
	else:
		_path.pop_back()
		_arrange(true)


## Sammelt alles ein und lässt die Karte zurück in ihr Fach gleiten.
func close() -> void:
	if not visible or _closing:
		return
	_closing = true
	var root: String = _path[0] if not _path.is_empty() else ""
	var root_card: Control = _cards.get(root)
	# Erst gleiten die Karten nacheinander zurück unter den Stapel, die zuletzt
	# erschienene zuerst; dann geht er zurück in sein Fach.
	var gather: Vector2 = root_card.position if root_card != null else size / 2.0
	var leaving := []
	for id: String in _cards.keys():
		if id != root:
			leaving.append(_cards[id])
	_cards = {root: root_card} if root_card != null else {}
	var gathered := _leave_all(leaving, func(_card: Control) -> Vector2: return gather)
	if root_card != null:
		_fill(root_card, 1.0, MOVE_SECONDS * 0.6, maxf(gathered - MOVE_SECONDS * 0.6, 0.15))
	var fade := create_tween().set_parallel()
	fade.tween_property(_dim, "modulate:a", 0.0, PULL_SECONDS + FLY_SECONDS).set_delay(gathered)
	fade.tween_property(_label, "modulate:a", 0.0, 0.12)
	fade.tween_property(_hint, "modulate:a", 0.0, 0.12)
	if gathered > 0.0:
		await get_tree().create_timer(gathered).timeout
	if is_instance_valid(root_card):
		var home = _home.call() if _home.is_valid() else null
		if home is Rect2:
			root_card.tight = true
			await _travel(root_card, _center_to_position(_to_local(home.get_center())), home.size.x / Card.SIZE.x, false)
		else:
			# Ihr Fach ist nicht aufgeschlagen: sie löst sich auf.
			await root_card.create_tween().tween_property(root_card, "modulate:a", 0.0, MOVE_SECONDS).finished
	_clear()
	visible = false
	_closing = false
	closed.emit()


# --------------------------------------------------------------- Legen

## Legt alle Karten an ihren Platz: der Weg oben, die Unteraufgaben der
## letzten Karte des Wegs als Fächer darunter. Was nicht mehr dazugehört,
## sammelt sich in seiner Eltern-Karte.
func _arrange(animated: bool) -> void:
	if _path.is_empty() or _ws == null:
		return
	var head: String = _path[-1]
	var kids: Array = _ws.kids(head).map(func(t: Dictionary) -> String: return t["id"])
	var wanted := {}
	for id: String in _path + kids:
		wanted[id] = true

	# Was nicht mehr dazugehört, gleitet zurück unter seine Eltern-Karte –
	# nacheinander, die zuletzt erschienene zuerst. Alles andere wartet darauf.
	var head_card: Control = _cards.get(head)
	var first := size.x / 2.0 - (_path.size() - 1) * PATH_STEP / 2.0
	var head_place := _center_to_position(Vector2(first + (_path.size() - 1) * PATH_STEP, PATH_Y))
	var fallback: Vector2 = head_card.position if head_card != null else head_place
	var leaving := []
	for id: String in _cards.keys():
		if not wanted.has(id):
			leaving.append(_cards[id])
			_cards.erase(id)
	var held := _cards
	var wait := _leave_all(leaving, func(card: Control) -> Vector2:
		var t = _ws.task(card.task_id)
		var parent: Control = held.get(t.get("parentId")) if t != null else null
		return parent.position if parent != null else fallback) if animated else 0.0
	if not animated:
		for card: Control in leaving:
			card.queue_free()

	# Der Weg: nebeneinander, die letzte Karte etwas größer.
	var head_travels := head_card != null and head_card.position.distance_to(head_place) > 2.0
	for i in _path.size():
		var card := _card_for(_path[i], head_place)
		if card == null:
			continue
		card.z_index = PATH_Z + i
		var last := i == _path.size() - 1
		_move(card, Vector2(first + i * PATH_STEP, PATH_Y), HEAD_SCALE if last else PATH_SCALE, 0.0, wait, animated)

	# Neue Karten kommen unter dem Stapel hervor – also erst, wenn er liegt.
	var spring := head_place
	var deal := wait + (MOVE_SECONDS if head_travels else 0.0) + 0.06

	# Der Fächer: so viele Reihen wie nötig, eine einzelne Reihe gewölbt.
	var top := PATH_Y + Card.SIZE.y * HEAD_SCALE / 2.0 + 56.0
	var room := Vector2(maxf(size.x - EDGE * 2.0, FAN_STEP), maxf(size.y - top - 60.0, ROW_STEP * 0.5))
	var per_row := maxi(1, int(room.x / FAN_STEP))
	var rows := ceili(kids.size() / float(per_row))
	var fit := clampf(room.y / (rows * ROW_STEP), 0.5, 1.0) if rows > 0 else 1.0
	if fit < 1.0:
		# Kleinere Karten: es passen auch mehr nebeneinander.
		per_row = maxi(1, int(room.x / (FAN_STEP * fit)))
		rows = ceili(kids.size() / float(per_row))
	var middle := top + room.y / 2.0
	for i in kids.size():
		var fresh := not _cards.has(kids[i])
		var card := _card_for(kids[i], spring)
		if card == null:
			continue
		var row := i / per_row
		var in_row := mini(per_row, kids.size() - row * per_row)
		var t := (i % per_row) - (in_row - 1) / 2.0
		var at := Vector2(size.x / 2.0 + t * FAN_STEP * fit, middle + (row - (rows - 1) / 2.0) * ROW_STEP * fit)
		var turn := 0.0
		if rows == 1:
			at.y += t * t * FAN_DROP
			turn = deg_to_rad(clampf(t * FAN_TURN, -12.0, 12.0))
		card.z_index = 10 + i
		_move(card, at, fit, turn, (deal if fresh else wait) + STAGGER * i if animated else 0.0, animated)

	# Der Stapel, dessen Unteraufgaben ausliegen, leert sich mit jeder Karte,
	# die unter ihm hervorkommt, bis nur die oberste bleibt. Jeder andere füllt
	# sich wieder, während seine Karten unter ihn zurückgleiten.
	for id: String in _cards.keys():
		var card: Control = _cards[id]
		if id == head and not kids.is_empty():
			_fill(card, 0.0, deal + MOVE_SECONDS * 0.1, STAGGER * (kids.size() - 1) + MOVE_SECONDS * 0.5, animated)
		elif card.pile < 1.0:
			_fill(card, 1.0, MOVE_SECONDS * 0.6, maxf(wait - MOVE_SECONDS * 0.6, 0.15), animated)

	var names := _path.map(func(id: String) -> String:
		var t = _ws.task(id)
		return str(t["title"]) if t != null and t.get("title") else "Ohne Titel")
	_label.text = "%s  ·  %d %s" % ["  ›  ".join(names), kids.size(), "Unteraufgabe" if kids.size() == 1 else "Unteraufgaben"]


## Die Karte dieser Aufgabe – neu angelegt, wenn es sie noch nicht gibt: dann
## taucht sie bei `spring` auf.
func _card_for(id: String, spring: Vector2) -> Control:
	if _cards.has(id):
		return _cards[id]
	var card := _make(id)
	if card != null:
		card.position = spring
		card.scale = Vector2(HEAD_SCALE, HEAD_SCALE) * 0.94
		card.modulate.a = 0.0
	return card


func _make(id: String) -> Control:
	var t = _ws.task(id)
	if t == null:
		return null
	var card := Card.new()
	_layer.add_child(card)
	card.show_task(_ws, t, _images)
	card.pressed.connect(_on_card)
	card.mouse_entered.connect(_lift.bind(card, true))
	card.mouse_exited.connect(_lift.bind(card, false))
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if not _ws.kids(id).is_empty() or _path.has(id) else Control.CURSOR_ARROW
	_cards[id] = card
	return card


## Bewegt eine Karte: ihre Mitte nach `center`.
func _move(card: Control, center: Vector2, card_scale: float, turn: float, delay := 0.0, animated := true) -> void:
	_stop(card)
	var to := _center_to_position(center)
	if not animated:
		card.position = to
		card.scale = Vector2(card_scale, card_scale)
		card.rotation = turn
		card.modulate.a = 1.0
		return
	var tween: Tween = card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "position", to, MOVE_SECONDS).set_delay(delay)
	tween.tween_property(card, "scale", Vector2(card_scale, card_scale), MOVE_SECONDS).set_delay(delay)
	tween.tween_property(card, "rotation", turn, MOVE_SECONDS).set_delay(delay)
	tween.tween_property(card, "modulate:a", 1.0, 0.03).set_delay(delay)
	card.set_meta("move", tween)


## Der Weg des Stapels zwischen Fach und Mitte, in einem Zug und ohne
## anzuhalten. Heraus (`out`) wird er erst langsam und ganz gerade nach oben
## aus seiner Tasche gezogen, so vorsichtig, wie man eine Karte aus der Hülle
## holt; sobald er ganz draußen ist, nimmt er Fahrt auf und gleitet im Bogen
## an seinen Platz. Hinein läuft dasselbe rückwärts.
func _travel(card: Control, to: Vector2, to_scale: float, out: bool) -> void:
	_stop(card)
	# Gerechnet wird immer vom Fach aus; hinein läuft die Zeit rückwärts.
	var pocket := card.position if out else to
	var pocket_scale := card.scale.x if out else to_scale
	var place := to if out else card.position
	var place_scale := to_scale if out else card.scale.x
	var spin := card.rotation
	# Ganz draußen ist er eine Kartenhöhe über dem Fach.
	var clear := pocket + Vector2(0, -Card.SIZE.y * pocket_scale * PULL)
	var seconds := PULL_SECONDS + FLY_SECONDS
	var share := PULL_SECONDS / seconds
	# Damit er am Übergang weder stockt noch ruckt, verlässt der Bogen das
	# Fach senkrecht und mit dem Tempo des Herausziehens.
	var lead := Vector2(0, -Card.SIZE.y * pocket_scale * PULL * FLY_SECONDS / (6.0 * PULL_SECONDS))
	var settle := Vector2(0, Card.SIZE.y * 0.45)
	var at := func(p: float) -> void:
		if p < share:
			# Sachte anfahren, dann gleichmäßig ziehen.
			var u := p / share
			card.position = pocket.lerp(clear, u * u * (2.0 - u) if u < 1.0 else 1.0)
			card.scale = Vector2(pocket_scale, pocket_scale)
		else:
			var w := (p - share) / (1.0 - share)
			var eased := 1.0 - (1.0 - w) * (1.0 - w)
			card.position = clear.bezier_interpolate(clear + lead, place + settle, place, eased)
			var s := lerpf(pocket_scale, place_scale, smoothstep(0.0, 1.0, w))
			card.scale = Vector2(s, s)
		card.rotation = spin * ((1.0 - p) if out else p)
	var tween: Tween = card.create_tween()
	tween.tween_method(at, 0.0 if out else 1.0, 1.0 if out else 0.0, seconds)
	card.set_meta("move", tween)
	await tween.finished


## Eine Karte verschwindet: sie gleitet nach `to` zurück unter den Stapel –
## so, wie sie hervorgekommen ist, nur rückwärts.
func _leave(card: Control, to: Vector2, delay := 0.0) -> void:
	_stop(card)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.z_index = 5
	var under := Vector2(HEAD_SCALE, HEAD_SCALE) * 0.94
	var tween: Tween = card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.tween_property(card, "position", to, MOVE_SECONDS).set_delay(delay)
	tween.tween_property(card, "scale", under, MOVE_SECONDS).set_delay(delay)
	tween.tween_property(card, "rotation", 0.0, MOVE_SECONDS).set_delay(delay)
	tween.chain().tween_callback(card.queue_free)


## Lässt Karten nacheinander verschwinden, die zuletzt erschienene zuerst.
## Gibt zurück, wie lange das dauert. `target` nennt je Karte, wohin sie gleitet.
func _leave_all(leaving: Array, target: Callable) -> float:
	if leaving.is_empty():
		return 0.0
	leaving.sort_custom(func(a: Control, b: Control) -> bool: return a.z_index > b.z_index)
	for i in leaving.size():
		_leave(leaving[i], target.call(leaving[i]), STAGGER * i)
	return STAGGER * (leaving.size() - 1) + MOVE_SECONDS


## Lässt den Stapel hinter einer Karte dünner oder voller werden (`Card.pile`).
func _fill(card: Control, to: float, delay: float, seconds: float, animated := true) -> void:
	if card.has_meta("fill"):
		var running: Tween = card.get_meta("fill")
		if running != null and running.is_valid():
			running.kill()
	if not animated:
		card.pile = to
		return
	var tween: Tween = card.create_tween()
	tween.tween_property(card, "pile", to, seconds).set_delay(delay)
	card.set_meta("fill", tween)


func _stop(card: Control) -> void:
	if card.has_meta("move"):
		var running: Tween = card.get_meta("move")
		if running != null and running.is_valid():
			running.kill()


func _put_at_home(card: Control) -> bool:
	var home = _home.call() if _home.is_valid() else null
	if home is Rect2:
		card.position = _center_to_position(_to_local(home.get_center()))
		var s: float = home.size.x / Card.SIZE.x
		card.scale = Vector2(s, s)
		return true
	else:
		card.position = _center_to_position(size / 2.0)
		card.modulate.a = 0.0
	return false


## Karten drehen und stauchen sich um ihre Mitte.
static func _center_to_position(center: Vector2) -> Vector2:
	return center - Card.SIZE / 2.0


func _to_local(global: Vector2) -> Vector2:
	return get_global_transform().affine_inverse() * global


func _clear() -> void:
	for c in _layer.get_children():
		c.queue_free()
	_cards = {}


# --------------------------------------------------------------- Maus

func _lift(card: Control, on: bool) -> void:
	if is_instance_valid(card) and not _closing:
		card.create_tween().tween_property(card, "lift", 0.7 if on else 0.0, 0.12)


func _on_card(card: Control, event: InputEventMouseButton) -> void:
	if _closing:
		return
	var id: String = card.task_id
	if event.button_index == MOUSE_BUTTON_RIGHT:
		menu_requested.emit(id)
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.double_click:
		_open_clicked(id)
		return
	_last_click = id
	_last_click_at = Time.get_ticks_msec()
	var at := _path.find(id)
	if at == _path.size() - 1:
		# Die Karte, deren Unteraufgaben aufgefächert sind: zurück.
		back()
	elif at >= 0:
		_path.resize(at + 1)
		_arrange(true)
	elif not _ws.kids(id).is_empty():
		_path.append(id)
		_arrange(true)


## Neben die Karten geklickt: der Fächer schließt sich. Ein zweiter Klick kurz
## nach einem auf eine Karte gilt aber noch ihr – sie ist nur weggeglitten.
func _on_dim(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index != MOUSE_BUTTON_LEFT and event.button_index != MOUSE_BUTTON_RIGHT:
		return
	if _last_click != "" and Time.get_ticks_msec() - _last_click_at < DOUBLE_CLICK_MS:
		if event.double_click:
			_open_clicked(_last_click)
		return
	close()


func _open_clicked(id: String) -> void:
	_last_click = ""
	task_requested.emit(id)


## Ein Doppelklick im Ordner hat den Fächer geöffnet und meint doch die
## Aufgabe: so heißt die Karte, auf die zuletzt geklickt wurde.
func note_click(id: String) -> void:
	_last_click = id
	_last_click_at = Time.get_ticks_msec()
