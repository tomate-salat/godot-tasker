@tool
extends Control
## Die Feldzugskarte: das aktive Release als Landkarte, eine Ebene über dem
## Feld und nach derselben Logik (`rules/campaign.gd`). In der Mitte steht das
## Release als Festung, die Milestones liegen als Städte in Ringen darum.
## Landstraßen verbinden, was aufeinander wartet; von jedem aktiven Milestone
## rollen Panzer nach innen, Flieger darüber.
##
## Die Karte ist zum Ansehen und Hineinspringen: ein Klick auf eine Stadt
## öffnet ihr Feld. Geändert wird hier nichts.

## Eine Stadt wurde gewählt: ihr Feld soll aufgehen.
signal milestone_chosen(milestone_id: String)
## Die Einzelheiten eines Milestones sind gefragt (Rechtsklick).
signal details_requested(milestone_id: String)

const Campaign := preload("../rules/campaign.gd")
const Release := preload("../rules/release.gd")
const Workspace := preload("../rules/workspace.gd")
const Palette := preload("palette.gd")

const TOP := 62.0
const MARGIN := 26.0
## Der innerste Ring und der Abstand der Ringe (Halbachsen); eine Stadt ist so groß.
const RING := Vector2(330.0, 225.0)
const STEP := Vector2(255.0, 175.0)
const CITY := 70.0
const SQUASH := 0.8
const BOSS_RADIUS := 80.0
const ZOOM_MIN := 0.6
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.12
## Wer über einer Stadt so weit hineinzoomt, landet in ihrem Feld.
const ZOOM_ENTER := 2.0
const MIN_SCALE := 0.35

const ATTACK := Color("f06a55")
const ROAD := Color("2a3837")
const WATER := Color("172f3c")
const OWN := Color("7fa3d8")
const OWN_LIGHT := Color("a7c2ee")
const FOE := Color("d86a55")
const FOE_LIGHT := Color("ee8a68")
const DARK := Color("15181b")
const GREEN := [Color("2f5a49"), Color("376655"), Color("3f7160")]
const RED := [Color("5a3a33"), Color("66413a"), Color("714a41")]
const GROUND := Color("1a2a26")
## Panzer rollen so schnell (Pixel je Sekunde), Flieger so viel schneller.
const TANK_SPEED := 22.0
const PLANE_SPEED := 70.0

var _campaign := {}
var _release: Variant
var _status := ""
var _centers := {}
var _nodes := {}
var _rings := 0
var _grow := 1.0
var _bounds := Rect2(-300, -300, 600, 600)
var _zoom := 1.0
var _pan := Vector2.ZERO
var _panning := false
var _time := 0.0
var _hovered := ""
## Das Land und die Blöcke der Städte: einmal ausgewürfelt, dann nur gezeichnet.
var _land_seed := -1
var _fields := []
var _woods := []
var _river := PackedVector2Array()
var _towns := {}
var _message: Label


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_message = Label.new()
	_message.set_anchors_preset(Control.PRESET_CENTER)
	_message.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message.add_theme_color_override("font_color", Color(1, 1, 1, 0.62))
	_message.visible = false
	add_child(_message)


## Zeigt den Feldzug dieses Releases; `release` null: es gibt keines.
func show_campaign(ws: Workspace, release: Variant) -> void:
	_release = release
	_message.visible = release == null
	if release == null:
		_message.text = "Kein Release in Arbeit"
		_campaign = {}
		queue_redraw()
		return
	_campaign = Campaign.build(ws, release)
	_status = Release.LABEL[Release.status(ws, release)]
	_nodes = {}
	for n in _campaign["nodes"]:
		_nodes[n["id"]] = n
	_layout()
	_scatter(hash(str(release["id"])))
	if not _nodes.has(_hovered):
		_hovered = ""
	queue_redraw()


## Zurück zur Ansicht, in der alles zu sehen ist.
func reset_view() -> void:
	_zoom = 1.0
	_pan = Vector2.ZERO
	queue_redraw()


# ------------------------------------------------------------ Anordnung

## Die Halbachsen eines Rings; der innerste ist der erste.
func _reach(ring_no: int) -> Vector2:
	return (RING + STEP * (ring_no - 1.0)) * _grow


## Verteilt die Städte auf ihre Ringe, wie das Feld seine Karten: jede bekommt
## einen Winkelbereich, so breit wie das, was hinter ihr nach außen hängt.
func _layout() -> void:
	_centers = {}
	var outer := {}
	var ring := {}
	for n in _campaign["nodes"]:
		outer.get_or_add(n["inner"], []).append(n["id"])
		ring[n["id"]] = n["ring"]
	var weight := {}
	_weigh("", outer, weight)
	var around := TAU * sqrt((RING.x * RING.x + RING.y * RING.y) / 2.0)
	_grow = maxf(1.0, weight[""] * (CITY * 2.0 + 90.0) / around)
	_rings = 0
	for id in ring:
		_rings = maxi(_rings, ring[id])
	# Die längste Kette zeigt zur Seite – dort ist im Fenster am meisten Platz.
	var deepest := ""
	for n in _campaign["nodes"]:
		if deepest == "" or n["ring"] > ring[deepest]:
			deepest = n["id"]
	var start := -PI
	if deepest != "":
		_spread("", 0.0, TAU, outer, weight, ring)
		start = PI - _centers[deepest].angle()
		_centers = {}
	_spread("", start, TAU, outer, weight, ring)
	var box := Rect2(-BOSS_RADIUS, -BOSS_RADIUS - 60.0, BOSS_RADIUS * 2.0, BOSS_RADIUS * 2.0 + 60.0)
	for id in _centers:
		box = box.merge(Rect2(_centers[id] - Vector2(CITY + 30.0, CITY + 50.0), Vector2(CITY * 2.0 + 60.0, CITY * 2.0 + 100.0)))
	_bounds = box.grow(16.0)


func _weigh(id: String, outer: Dictionary, weight: Dictionary) -> float:
	var sum := 0.0
	for other in outer.get(id, []):
		sum += _weigh(other, outer, weight)
	weight[id] = maxf(sum, 1.0)
	return weight[id]


func _spread(id: String, from: float, span: float, outer: Dictionary, weight: Dictionary, ring: Dictionary) -> void:
	if id != "":
		var angle := from + span / 2.0
		var reach := _reach(ring[id])
		_centers[id] = Vector2(cos(angle) * reach.x, sin(angle) * reach.y)
	var list: Array = outer.get(id, [])
	var total := 0.0
	for other in list:
		total += sqrt(weight[other])
	var at := from
	for other in list:
		var part: float = span * sqrt(weight[other]) / maxf(total, 1.0)
		_spread(other, at, part, outer, weight, ring)
		at += part


## Würfelt das Land aus – Äcker, Wälder, ein Fluss jenseits der Ringe – und
## die Blöcke jeder Stadt. Aus derselben Kennung entsteht immer dasselbe.
func _scatter(seed_value: int) -> void:
	var far := _reach(maxi(_rings, 1)) + Vector2(520.0, 420.0)
	if seed_value != _land_seed:
		_land_seed = seed_value
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		_fields = []
		for k in 60:
			var mid := Vector2(rng.randf_range(-far.x, far.x), rng.randf_range(-far.y, far.y))
			var half := Vector2(rng.randf_range(34.0, 80.0), rng.randf_range(20.0, 46.0))
			var turn := rng.randf_range(-0.5, 0.5)
			var poly := PackedVector2Array()
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				poly.append(mid + (corner * half).rotated(turn))
			_fields.append({"poly": poly, "tone": rng.randi() % 2})
		_woods = []
		for k in 34:
			var mid := Vector2(rng.randf_range(-far.x, far.x), rng.randf_range(-far.y, far.y))
			for j in 9:
				_woods.append([mid + Vector2(rng.randf_range(-36.0, 36.0), rng.randf_range(-24.0, 24.0)), rng.randf_range(7.0, 13.0)])
		_towns = {}
	# Der Fluss läuft jenseits des äußersten Rings: so kreuzt er keine Straße.
	_river = PackedVector2Array()
	var beyond := -(_reach(maxi(_rings, 1)).y + CITY + 110.0)
	var x := -far.x - 200.0
	while x <= far.x + 200.0:
		_river.append(Vector2(x, beyond + sin(x * 0.006 + seed_value % 7) * 46.0))
		x += 30.0
	for id in _nodes:
		if _towns.has(id):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(str(id))
		var blocks := []
		var step := 13.0
		var y := -CITY
		while y <= CITY:
			var bx := -CITY
			while bx <= CITY:
				var d := Vector2(bx, y / SQUASH).length() / CITY
				if d <= 1.0 - rng.randf() * 0.2 and d >= 0.27:
					blocks.append({"at": Vector2(bx, y), "size": Vector2(step - 3.0 - rng.randf() * 3.0, step - 3.0 - rng.randf() * 3.0), "d": d, "tone": rng.randi() % 3})
				bx += step
			y += step
		_towns[id] = blocks


# -------------------------------------------------------------- Bedienen

## Wie die Karte gerade im Fenster liegt: Maß und Ursprung.
func _view() -> Transform2D:
	var room := size - Vector2(MARGIN * 2.0, TOP + MARGIN)
	var s := 1.0
	if room.x > 0.0 and room.y > 0.0:
		s = clampf(minf(room.x / _bounds.size.x, room.y / _bounds.size.y), MIN_SCALE, 1.0)
	s *= _zoom
	var middle := Vector2(size.x / 2.0, TOP + maxf(room.y, 0.0) / 2.0)
	return Transform2D(Vector2(s, 0), Vector2(0, s), (middle - _bounds.get_center() * s + _pan).round())


func _city_at(point: Vector2) -> String:
	var at := _view().affine_inverse() * point
	for id in _centers:
		var away: Vector2 = at - _centers[id]
		if Vector2(away.x, away.y / SQUASH).length() <= CITY + 6.0:
			return id
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _panning:
			_pan += event.relative
		var over := _city_at(event.position)
		if over != _hovered:
			_hovered = over
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if over != "" else Control.CURSOR_ARROW
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not event.pressed:
				return
			var before := _zoom
			_zoom = clampf(_zoom * (ZOOM_STEP if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
			var middle := Vector2(size.x / 2.0, TOP + (size.y - TOP - MARGIN) / 2.0)
			_pan += (event.position - middle - _pan) * (1.0 - _zoom / before)
			# Weit genug über einer Stadt hineingezoomt: aufs Feld.
			var over := _city_at(event.position)
			if over != "" and _zoom >= ZOOM_ENTER and _zoom > before:
				_enter(over)
			accept_event()
			queue_redraw()
		elif event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var over := _city_at(event.position)
			if over != "":
				_enter(over)
			elif event.double_click:
				reset_view()
		elif event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			var over := _city_at(event.position)
			if over != "":
				details_requested.emit(over)


func _enter(id: String) -> void:
	_panning = false
	reset_view()
	milestone_chosen.emit(id)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered != "":
		_hovered = ""
		queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree() or _campaign.is_empty():
		return
	_time += delta
	queue_redraw()


# -------------------------------------------------------------- Zeichnen

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Palette.FELT)
	if _campaign.is_empty():
		return
	var view := _view()
	draw_set_transform_matrix(view)

	# Das Land.
	for field in _fields:
		draw_colored_polygon(field["poly"], Color("24443a") if field["tone"] == 0 else Color("213d34"))
	for wood in _woods:
		draw_circle(wood[0], wood[1], Color(0.10, 0.29, 0.21, 0.5))
	if _river.size() >= 2:
		draw_polyline(_river, WATER, 30.0, true)

	# Die Ringe in den Farben der Einnahme, wie im Feld.
	var front: int = _campaign["front"]
	for k in _rings:
		var at_front := k + 1 == front
		var tone := Palette.OK if k + 1 > front else Palette.P2 if at_front else Palette.P1
		_draw_ellipse(Vector2.ZERO, _reach(k + 1), Color(tone, 0.34 + 0.1 * sin(_time * 1.8) if at_front else 0.22), 2.0 if at_front else 1.5)

	# Die Landstraßen, und was auf ihnen unterwegs ist.
	var attacking := {}
	for attack in _campaign["attacks"]:
		attacking["%s>%s" % [attack["from"], attack["to"]]] = true
	var units := []
	for way in _campaign["ways"]:
		if not _centers.has(way["from"]):
			continue
		var path := _road(way["from"], way["to"])
		var from_node: Dictionary = _nodes[way["from"]]
		var shown := 1.0 if _hovered == "" or way["from"] == _hovered or way["to"] == _hovered else 0.2
		draw_polyline(path, Color(ROAD, shown), 12.0, true)
		if attacking.has("%s>%s" % [way["from"], way["to"]]):
			draw_polyline(path, Color(ATTACK, 0.4 * shown), 3.0, true)
			_draw_flow(path, Color(ATTACK, shown), 3.0, 60.0, 30.0, 12.0)
			var tip := path[path.size() - 1]
			var dir := (tip - path[path.size() - 2]).normalized()
			var side := dir.orthogonal()
			draw_colored_polygon(PackedVector2Array([tip, tip - dir * 12.0 + side * 6.5, tip - dir * 12.0 - side * 6.5]), Color(ATTACK, shown))
			units.append(path)
		else:
			var tone := Color(Palette.OK, 0.6) if from_node["state"] == Campaign.DONE else Color(1, 1, 1, 0.26)
			tone.a *= shown
			draw_polyline(path, tone, 2.0, true)
			_draw_flow(path, Color(tone.lightened(0.45), minf(tone.a + 0.3, 1.0)), 2.0, 22.0, 64.0, 12.0)

	_draw_boss(view)
	for id in _centers:
		_draw_city(view, _nodes[id])

	# Panzer rollen nach innen, vor dem Ziel hält ein gegnerischer; Flieger darüber.
	for path in units:
		var length := _length(path)
		var count := clampi(int(length / 110.0), 1, 4)
		for k in count:
			var way := fposmod(_time * TANK_SPEED + k * length / count, length)
			# Kurz vor dem Ziel ist Schluss: dort steht der Gegner.
			if way < length - 52.0:
				_draw_tank(view, _along(path, way), OWN, 1.0)
		var stand := _along(path, length - 30.0)
		_draw_tank(view, Transform2D(stand.get_rotation() + PI, stand.origin), FOE, 1.0)
	for path in units:
		var length := _length(path)
		var spot := _along(path, fposmod(_time * PLANE_SPEED, length + 160.0) - 80.0)
		_draw_plane(view, Transform2D(spot.get_rotation(), spot.origin + Vector2(0, -42.0)))
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_ellipse(mid: Vector2, reach: Vector2, color: Color, width: float) -> void:
	var loop := PackedVector2Array()
	for i in 97:
		var a := TAU * i / 96.0
		loop.append(mid + Vector2(cos(a) * reach.x, sin(a) * reach.y))
	draw_polyline(loop, color, width, true)


## Die Straße von einer Stadt nach innen – zur Stadt `to_id` oder, leer, zur
## Mitte: leicht geschwungen, von Stadtrand zu Stadtrand.
func _road(from_id: String, to_id: String) -> PackedVector2Array:
	var a: Vector2 = _centers[from_id]
	var b: Vector2 = _centers[to_id] if to_id != "" and _centers.has(to_id) else Vector2.ZERO
	var dir := (b - a).normalized()
	var start := a + Vector2(dir.x, dir.y * SQUASH) * (CITY + 4.0)
	# Die Straße reicht bis an den Rand des Ziels – ohne Lücke.
	var gap := BOSS_RADIUS + 3.0 if to_id == "" else CITY + 4.0
	var end := b - (dir * gap if to_id == "" else Vector2(dir.x, dir.y * SQUASH) * gap)
	var bow := (24.0 if hash(from_id) % 2 == 0 else -24.0) * minf(start.distance_to(end) / 260.0, 1.4)
	var mid := (start + end) / 2.0 + dir.orthogonal() * bow
	var path := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		path.append(start.lerp(mid, t).lerp(mid.lerp(end, t), t))
	return path


static func _length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in path.size() - 1:
		total += path[i].distance_to(path[i + 1])
	return total


## Lage und Richtung an einer Stelle eines Wegs, `way` Pixel nach seinem Anfang.
static func _along(path: PackedVector2Array, way: float) -> Transform2D:
	var left := way
	for i in path.size() - 1:
		var piece := path[i].distance_to(path[i + 1])
		if left <= piece or i == path.size() - 2:
			var dir := (path[i + 1] - path[i]).normalized()
			return Transform2D(dir.angle(), path[i] + dir * left)
		left -= piece
	return Transform2D(0.0, path[0])


## Striche, die einen Weg entlangwandern, auch um die Kurven.
func _draw_flow(path: PackedVector2Array, color: Color, width: float, speed: float, gap: float, dash: float) -> void:
	var done := 0.0
	for i in path.size() - 1:
		var from := path[i]
		var length := from.distance_to(path[i + 1])
		if length < 0.01:
			continue
		var dir := (path[i + 1] - from) / length
		var at := fposmod(_time * speed - done, gap) - gap
		while at < length:
			var start := maxf(at, 0.0)
			var end := minf(at + dash, length)
			if end > start:
				draw_line(from + dir * start, from + dir * end, color, width, true)
			at += gap
		done += length


## Die Mitte: das Release als Festung des Gegners, außen herum, was noch fehlt.
func _draw_boss(view: Transform2D) -> void:
	draw_circle(Vector2.ZERO, BOSS_RADIUS, Color(0, 0, 0, 0.3))
	draw_arc(Vector2.ZERO, BOSS_RADIUS, 0.0, TAU, 96, Color(1, 1, 1, 0.16), 6.0, true)
	var total: int = maxi(_campaign["boss"]["total"], 1)
	var left: int = total - _campaign["boss"]["done"]
	if left > 0:
		draw_arc(Vector2.ZERO, BOSS_RADIUS, -PI / 2.0, -PI / 2.0 + TAU * left / total, 96, Palette.P1, 6.0, true)
	var star := PackedVector2Array()
	for k in 10:
		var a := -PI / 2.0 + k * PI / 5.0
		star.append(Vector2(0, -8) + Vector2.from_angle(a) * (24.0 if k % 2 == 1 else 46.0))
	draw_colored_polygon(star, Color("3a2f2a"))
	star.append(star[0])
	draw_polyline(star, Color("75604a"), 2.5, true)
	draw_circle(Vector2(0, -8), 13.0, Color("5a4a3a"))
	draw_line(Vector2(0, -8), Vector2(0, -28), Color("2b2622"), 2.4, true)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -28), Vector2(12, -28), Vector2(8, -24), Vector2(12, -20), Vector2(0, -20)]), Palette.P1)
	var text := "noch %d von %d" % [left, total] if left > 0 else "eingenommen"
	draw_string(Palette.sharp_body_font(), Vector2(-BOSS_RADIUS, 58.0), text, HORIZONTAL_ALIGNMENT_CENTER, BOSS_RADIUS * 2.0, 12, Color(1, 1, 1, 0.75))
	_draw_plate(Vector2(0, -BOSS_RADIUS - 34.0), Release.label(_release), "Release · %s" % _status, Palette.P1, false)


## Eine Stadt, verkleinert: ihre Blöcke von außen her eingenommen, ihre Ringe,
## ihr Fortschritt in der Mitte – und wer dort gerade kämpft.
func _draw_city(view: Transform2D, n: Dictionary) -> void:
	var id: String = n["id"]
	var mid: Vector2 = _centers[id]
	var state: String = n["state"]
	var share := 1.0 if state == Campaign.DONE else float(n["done"]) / maxf(n["total"], 1.0)
	var tone := Palette.OK if state == Campaign.DONE else Palette.P2 if state == Campaign.ACTIVE else Palette.P1
	# Der Grund der Stadt hebt sie vom Land ab.
	var ground := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		ground.append(mid + Vector2(cos(a) * (CITY + 4.0), sin(a) * (CITY + 4.0) * SQUASH))
	draw_colored_polygon(ground, GROUND)
	for b in _towns.get(id, []):
		var own: bool = b["d"] > 1.0 - share
		var color: Color = (GREEN if own else RED)[b["tone"]]
		if b["d"] > 0.84:
			color.a = 0.55
		draw_rect(Rect2(mid + b["at"], b["size"]), color)
	# Die Ringe der Stadt, von außen nach innen eingenommen.
	for part in [0.96, 0.7, 0.42]:
		var ring_tone := Palette.OK if 1.0 - part < share - 0.02 or state == Campaign.DONE else Palette.P2 if state == Campaign.ACTIVE and part == 0.96 else Palette.P1
		_draw_ellipse(mid, Vector2(CITY * part, CITY * part * SQUASH), Color(ring_tone, 0.5), 1.2)
	if id == _hovered:
		_draw_ellipse(mid, Vector2(CITY + 9.0, (CITY + 9.0) * SQUASH), Color(tone, 0.9), 2.0)
	# Die Mitte mit dem Fortschritt.
	draw_circle(mid, 16.0, Color("0f211c"))
	draw_arc(mid, 16.0, 0.0, TAU, 48, Color(1, 1, 1, 0.16), 4.0, true)
	if share > 0.0:
		draw_arc(mid, 16.0, -PI / 2.0, -PI / 2.0 + TAU * share, 48, tone, 4.0, true)
	draw_string(Palette.sharp_body_font(), mid + Vector2(-16.0, 4.0), "%d%%" % roundi(share * 100.0), HORIZONTAL_ALIGNMENT_CENTER, 32.0, 10, Palette.INK)
	# Die Kämpfe: je laufender Aufgabe ein Paar, eigene blau, Gegner rot.
	if state == Campaign.ACTIVE:
		for k in mini(n["fights"], 5):
			var a := float(hash("%s|%d" % [id, k]) % 628) / 100.0
			var at := mid + Vector2(cos(a) * CITY * 0.62, sin(a) * CITY * 0.5)
			draw_circle(at - Vector2(6, 0), 3.8, DARK)
			draw_circle(at - Vector2(6, 0), 3.0, OWN_LIGHT)
			draw_circle(at + Vector2(6, 0), 3.8, DARK)
			draw_circle(at + Vector2(6, 0), 3.0, FOE_LIGHT)
			# Ein Schuss blitzt in eigenem Takt auf.
			if fposmod(_time + k * 0.37 + a, 1.7) < 0.14:
				draw_line(at - Vector2(2, 0), at + Vector2(2, 0), Color(1.0, 0.93, 0.69), 1.2, true)
	elif state == Campaign.PLANNED:
		for a in [0.6, 2.5, 4.4]:
			var at := mid + Vector2(cos(a) * CITY * 0.55, sin(a) * CITY * 0.45)
			draw_circle(at, 3.8, DARK)
			draw_circle(at, 3.0, FOE_LIGHT)
	# Das Schild liegt auf der Seite, zu der keine Straße nach innen abgeht.
	var inner: Vector2 = (_centers.get(n["inner"], Vector2.ZERO) - mid).normalized()
	var above := inner.y > 0.25
	var word := "eingenommen" if state == Campaign.DONE else "umkämpft" if state == Campaign.ACTIVE else "beim Gegner"
	_draw_plate(mid + Vector2(0, -CITY * SQUASH - 30.0 if above else CITY * SQUASH + 30.0), str(n["milestone"].get("title", "")),
		"%d/%d · %s" % [n["done"], n["total"], word], tone, id == _hovered)


## Ein Schild mit zwei Zeilen, um `mid` herum.
func _draw_plate(mid: Vector2, title: String, note: String, tone: Color, lit: bool) -> void:
	var font := Palette.sharp_title_font()
	var small := Palette.sharp_body_font()
	var wide := maxf(maxf(font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, small.get_string_size(note, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) + 26.0, 120.0)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.SURFACE
	box.border_color = Color(tone, 1.0 if lit else 0.7)
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	var rect := Rect2(mid - Vector2(wide / 2.0, 20.0), Vector2(wide, 40.0))
	draw_style_box(box, rect)
	draw_string(font, rect.position + Vector2(0, 17.0), title, HORIZONTAL_ALIGNMENT_CENTER, wide, 13, Palette.INK)
	draw_string(small, rect.position + Vector2(0, 32.0), note, HORIZONTAL_ALIGNMENT_CENTER, wide, 10, tone)


## Ein Panzer von oben: Ketten, Wanne, Turm, Rohr. `spot` gibt Lage und Richtung.
func _draw_tank(view: Transform2D, spot: Transform2D, body: Color, girth: float) -> void:
	draw_set_transform_matrix(view * spot * Transform2D(0.0, Vector2(girth, girth), 0.0, Vector2.ZERO))
	draw_rect(Rect2(-9, -7, 18, 3.4), Color("1c1a18"))
	draw_rect(Rect2(-9, 3.6, 18, 3.4), Color("1c1a18"))
	draw_rect(Rect2(-8.5, -5.5, 17, 11), DARK)
	draw_rect(Rect2(-7.6, -4.6, 15.2, 9.2), body)
	draw_line(Vector2(1, 0), Vector2(14, 0), DARK, 2.4, true)
	draw_circle(Vector2.ZERO, 4.2, DARK)
	draw_circle(Vector2.ZERO, 3.3, body.lightened(0.12))
	draw_set_transform_matrix(view)


## Ein Flieger von oben, mit seinem Schatten auf dem Land.
func _draw_plane(view: Transform2D, spot: Transform2D) -> void:
	var shape := PackedVector2Array([Vector2(13, 0), Vector2(3, -2.2), Vector2(-1, -13), Vector2(-5, -13), Vector2(-3, -2), Vector2(-10, -1.6),
		Vector2(-12, -5.5), Vector2(-14.5, -5.5), Vector2(-13.5, 0), Vector2(-14.5, 5.5), Vector2(-12, 5.5), Vector2(-10, 1.6), Vector2(-3, 2),
		Vector2(-5, 13), Vector2(-1, 13), Vector2(3, 2.2)])
	# Der Flügel knickt nach innen: als ein Vieleck ließe er sich nicht füllen, darum in Dreiecken um die Mitte.
	for pass_no in 2:
		var shift := Vector2(8, 46) if pass_no == 0 else Vector2.ZERO
		var color := Color(0, 0, 0, 0.26) if pass_no == 0 else OWN_LIGHT
		draw_set_transform_matrix(view * Transform2D(spot.get_rotation(), spot.origin + shift))
		for i in shape.size():
			draw_colored_polygon(PackedVector2Array([Vector2(-3, 0), shape[i], shape[(i + 1) % shape.size()]]), color)
		if pass_no == 1:
			var edge := shape.duplicate()
			edge.append(shape[0])
			draw_polyline(edge, DARK, 0.9, true)
	draw_set_transform_matrix(view)
