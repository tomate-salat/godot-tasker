@tool
extends Control
## Der Abhängigkeitsgraph einer Karte, über der Planung: links, worauf sie
## wartet, rechts, was auf sie wartet, über alle Stufen – aufgebaut wie der
## Graph in Tasker. Jeder Knoten nennt, wo er liegt.
##
## Hier wird nur angesehen. Ein Doppelklick auf einen Knoten öffnet die
## Aufgabe. Was zusammenhängt,
## steht in `rules/dep_graph.gd`.

signal task_requested(id: String)

const Palette := preload("palette.gd")
const DepGraph := preload("../rules/dep_graph.gd")
const Planning := preload("../rules/planning.gd")
const Model := preload("../rules/model.gd")
const Workspace := preload("../rules/workspace.gd")

const NODE := Vector2(190.0, 62.0)
## Abstand der Stufen nebeneinander und der Knoten untereinander.
const STEP := Vector2(270.0, 78.0)
const PAD := Vector2(30.0, 62.0)
## So lang ist eine Pfeilspitze.
const ARROW := 9.0
## Pfeile, die an einer Stufe vorbeilaufen: Abstand zu deren Knoten und zueinander.
const LANE_GAP := 16.0
const LANE_STEP := 10.0
## Der Graph baut sich von links nach rechts auf: so viel später je Stufe, und
## so lange braucht ein Pfeil, um sich zu ziehen.
const STAGGER := 0.07
const EDGE_SECONDS := 0.32
## Die wandernden Punkte: Tempo in Pixeln je Sekunde und Abstand zueinander.
const DOT_SPEED := 70.0
const DOT_SPACING := 44.0

var _panel: PanelContainer
var _title: Label
var _hint: Label
var _scroll: ScrollContainer
var _canvas: Control
## Was gezeichnet wird: die Kanten als `{ from, to, state }` mit Punkten.
var _edges: Array = []
var _focus_id := ""
## Der Knoten unter dem Zeiger: seine Pfeile treten hervor.
var _hot := ""
## Sekunden seit dem Öffnen, und wann der Aufbau fertig ist.
var _time := 0.0
var _built_at := 0.0
var _dim: ColorRect
var _fade: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false
	z_index = 100

	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.07, 0.06, 0.72)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(_dim)

	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("141a18")
	box.border_color = Color(Palette.ACCENT, 0.6)
	box.set_border_width_all(1)
	box.set_corner_radius_all(14)
	box.set_content_margin_all(18)
	box.shadow_color = Color(0, 0, 0, 0.5)
	box.shadow_size = 18
	_panel.add_theme_stylebox_override("panel", box)
	add_child(_panel)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	_panel.add_child(rows)
	var head := HBoxContainer.new()
	rows.add_child(head)
	_title = Label.new()
	_title.add_theme_font_override("font", Palette.title_font())
	_title.add_theme_font_size_override("font_size", 18)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.clip_text = true
	head.add_child(_title)
	var shut := Button.new()
	shut.text = "✕"
	shut.flat = true
	shut.tooltip_text = "Schließen (Esc)"
	shut.pressed.connect(close)
	head.add_child(shut)
	_hint = Label.new()
	_hint.add_theme_color_override("font_color", Palette.MUTED)
	# Kein Umbruch: ein umbrechender Text würde das Feld beliebig hoch ziehen.
	_hint.clip_text = true
	_hint.add_theme_font_size_override("font_size", 12)
	rows.add_child(_hint)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_scroll)
	_canvas = Control.new()
	_canvas.draw.connect(_draw_edges)
	_scroll.add_child(_canvas)


func close() -> void:
	if not visible:
		return
	if _fade != null:
		_fade.kill()
	_fade = create_tween().set_parallel()
	_fade.tween_property(_dim, "modulate:a", 0.0, 0.12)
	_fade.tween_property(_panel, "modulate:a", 0.0, 0.12)
	_fade.tween_property(_panel, "scale", Vector2(0.97, 0.97), 0.12)
	_fade.chain().tween_callback(func() -> void: visible = false)


## Solange sich etwas bewegt, wird neu gezeichnet: der Aufbau nach dem Öffnen
## und die Punkte, die über die Pfeile des Knotens unter dem Zeiger wandern.
func _process(delta: float) -> void:
	if not visible:
		return
	_time += delta
	if _time < _built_at or _hot != "":
		_canvas.queue_redraw()


## Zeigt den Graphen um diese Aufgabe (oder diesen Milestone).
func open(ws: Workspace, focus: Dictionary, project_id: String) -> void:
	_focus_id = focus["id"]
	var graph := DepGraph.build(ws, focus)
	var order := Planning.deck_order(Planning.decks(ws, project_id))
	_title.text = "Abhängigkeiten: %s" % _name(focus)
	var alone: bool = graph["nodes"].size() == 1
	_hint.text = "An dieser Karte hängt nichts, und sie hängt an nichts." if alone else \
		"Links, worauf die Karte wartet – rechts, was auf sie wartet. Doppelklick öffnet die Karte.
Rot: die Voraussetzung liegt in einem späteren Deck oder noch im Vorrat. Blass: schon erledigt.%s" % (
			"\nDer Graph ist größer, als hier Platz hat – gezeigt sind die ersten %d Knoten." % DepGraph.MAX_NODES if graph["cut"] else "")

	# Die Stufen nebeneinander, in jeder die Knoten untereinander.
	var layers := {}
	var lowest := 0
	for n in graph["nodes"]:
		layers.get_or_add(n["layer"], []).append(n["item"])
		lowest = mini(lowest, n["layer"])

	# Innerhalb einer Stufe stehen die Knoten nahe bei dem, womit sie verbunden
	# sind – von der Karte aus nach außen sortiert. So kreuzen sich weniger Pfeile.
	var row := {_focus_id: 0.0}
	var outward := layers.keys()
	outward.sort_custom(func(a: int, b: int) -> bool: return absi(a) < absi(b))
	for l in outward:
		var list: Array = layers[l]
		var pull := {}
		for item in list:
			var sum := 0.0
			var count := 0
			for e in graph["edges"]:
				var other = e["to"] if e["from"] == item["id"] else e["from"] if e["to"] == item["id"] else null
				if other != null and row.has(other):
					sum += row[other]
					count += 1
			pull[item["id"]] = sum / count if count > 0 else 0.0
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return pull[a["id"]] < pull[b["id"]])
		for i in list.size():
			row[list[i]["id"]] = i - (list.size() - 1) / 2.0
	var tallest := 0
	for l in layers:
		tallest = maxi(tallest, layers[l].size())

	for c in _canvas.get_children():
		c.queue_free()
	var at := {}
	for l in layers:
		var list: Array = layers[l]
		for i in list.size():
			var item: Dictionary = list[i]
			var pos := PAD + Vector2((l - lowest) * STEP.x, ((tallest - list.size()) / 2.0 + i) * STEP.y)
			at[item["id"]] = pos
			var node := _node(ws, item, pos, order)
			_canvas.add_child(node)
			# Stufe um Stufe von links, leicht hereingeschoben.
			var shown: float = node.modulate.a
			var wait: float = 0.1 + (l - lowest) * STAGGER
			node.modulate.a = 0.0
			node.position.x = pos.x - 14.0
			var rise := node.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			rise.tween_property(node, "modulate:a", shown, 0.22).set_delay(wait)
			rise.tween_property(node, "position:x", pos.x, 0.26).set_delay(wait)
	_canvas.custom_minimum_size = PAD * 2.0 + Vector2((layers.size() - 1) * STEP.x + NODE.x, (tallest - 1) * STEP.y + NODE.y)

	# Wo jede Stufe steht und wie weit ihre Knoten reichen – Pfeile, die eine
	# Stufe überspringen, laufen über oder unter deren Knoten vorbei.
	var column := {}
	for l in layers:
		var top := INF
		var bottom := -INF
		for item in layers[l]:
			top = minf(top, at[item["id"]].y)
			bottom = maxf(bottom, at[item["id"]].y + NODE.y)
		column[l] = {"x": PAD.x + (l - lowest) * STEP.x, "top": top, "bottom": bottom}
	var layer_of := {}
	var by_id := {}
	for n in graph["nodes"]:
		by_id[n["item"]["id"]] = n["item"]
		layer_of[n["item"]["id"]] = n["layer"]

	# Jeder Pfeil bekommt an seinem Knoten einen eigenen Anschluss, sortiert
	# nach der Höhe des anderen Endes: so kommen zwei Pfeile nicht am selben
	# Punkt an.
	var leaving := {}
	var arriving := {}
	for e in graph["edges"]:
		leaving.get_or_add(e["from"], []).append(e)
		arriving.get_or_add(e["to"], []).append(e)
	for id in leaving:
		leaving[id].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return at[x["to"]].y < at[y["to"]].y)
	for id in arriving:
		arriving[id].sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return at[x["from"]].y < at[y["from"]].y)

	_edges = []
	var lanes := {}
	for e in graph["edges"]:
		var out: Array = leaving[e["from"]]
		var into: Array = arriving[e["to"]]
		var from: Vector2 = at[e["from"]] + Vector2(NODE.x, NODE.y * (out.find(e) + 1.0) / (out.size() + 1.0))
		var to: Vector2 = at[e["to"]] + Vector2(-ARROW, NODE.y * (into.find(e) + 1.0) / (into.size() + 1.0))
		var route := [from]
		for l in range(layer_of[e["from"]] + 1, layer_of[e["to"]]):
			if not column.has(l):
				continue
			var c: Dictionary = column[l]
			var above: bool = (from.y + to.y) / 2.0 <= (c["top"] + c["bottom"]) / 2.0
			var lane: int = lanes.get([l, above], 0)
			lanes[[l, above]] = lane + 1
			var y: float = c["top"] - LANE_GAP - lane * LANE_STEP if above else c["bottom"] + LANE_GAP + lane * LANE_STEP
			route.append(Vector2(c["x"] - 16.0, y))
			route.append(Vector2(c["x"] + NODE.x + 16.0, y))
		route.append(to)
		# Zwischen den Punkten im Bogen, an einer Stufe vorbei gerade.
		var points := PackedVector2Array()
		for i in route.size() - 1:
			var p: Vector2 = route[i]
			var q: Vector2 = route[i + 1]
			if is_equal_approx(p.y, q.y):
				points.append(p)
				points.append(q)
				continue
			var pull := maxf(absf(q.x - p.x) * 0.5, 30.0)
			for k in 21:
				points.append(p.bezier_interpolate(p + Vector2(pull, 0.0), q - Vector2(pull, 0.0), q, k / 20.0))
		# Der Weg bis zu jedem Punkt, damit sich entlang der Linie in Pixeln rechnen lässt.
		var lengths := PackedFloat32Array([0.0])
		for i in range(1, points.size()):
			lengths.append(lengths[i - 1] + points[i - 1].distance_to(points[i]))
		_edges.append({
			"a": e["from"], "b": e["to"], "points": points, "lengths": lengths, "from": from, "to": to,
			"start": 0.22 + (layer_of[e["from"]] - lowest) * STAGGER,
			"state": DepGraph.edge_state(ws, by_id[e["from"]], by_id[e["to"]], order),
		})
	_canvas.queue_redraw()

	# So groß wie nötig, höchstens so groß wie die Planung.
	var want: Vector2 = _canvas.custom_minimum_size + Vector2(56.0, 170.0)
	_panel.size = Vector2(clampf(want.x, 720.0, size.x - 80.0), clampf(want.y, 260.0, size.y - 100.0))
	_panel.position = ((size - _panel.size) / 2.0).round()
	_time = 0.0
	_built_at = 0.22 + layers.size() * STAGGER + EDGE_SECONDS + 0.1
	if _fade != null:
		_fade.kill()
	_panel.pivot_offset = _panel.size / 2.0
	_panel.scale = Vector2(0.94, 0.94)
	_panel.modulate.a = 0.0
	_dim.modulate.a = 0.0
	_fade = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_fade.tween_property(_dim, "modulate:a", 1.0, 0.16)
	_fade.tween_property(_panel, "modulate:a", 1.0, 0.16)
	_fade.tween_property(_panel, "scale", Vector2.ONE, 0.22)
	visible = true


## Ein Knoten: Titel, Ort und Status. Die Karte, um die es geht, ist umrandet.
func _node(ws: Workspace, item: Dictionary, pos: Vector2, order: Dictionary) -> Control:
	var is_ms := Model.is_milestone(item)
	var place := DepGraph.place_label(ws, item)
	# Was noch gar nicht eingeplant ist, fällt auf.
	var unplanned := not order.has(item["id"]) if is_ms else Planning.place(ws, item, order) < 0
	var done: bool = item.get("status") == "done"

	var node := Button.new()
	node.position = pos
	node.size = NODE
	node.focus_mode = Control.FOCUS_NONE
	node.tooltip_text = "%s\n%s\nDoppelklick öffnet die Karte." % [_name(item), place]
	for state in ["normal", "hover", "pressed"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Palette.SURFACE if state == "normal" else Palette.SURFACE.lightened(0.06)
		box.border_color = Palette.ACCENT if item["id"] == _focus_id else Palette.LINE_STRONG
		box.set_border_width_all(2 if item["id"] == _focus_id else 1)
		box.set_corner_radius_all(10)
		node.add_theme_stylebox_override(state, box)
	node.modulate.a = 0.55 if done else 1.0
	node.gui_input.connect(_on_node_input.bind(item["id"]))
	node.mouse_entered.connect(_set_hot.bind(item["id"]))
	node.mouse_exited.connect(_set_hot.bind(""))

	var rows := VBoxContainer.new()
	rows.set_anchors_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 12.0
	rows.offset_right = -10.0
	rows.offset_top = 7.0
	rows.offset_bottom = -7.0
	rows.add_theme_constant_override("separation", 2)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	node.add_child(rows)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(line)
	if not is_ms:
		var icon := TextureRect.new()
		icon.texture = Palette.status_icon(item.get("status"))
		icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		line.add_child(icon)
	var title := Label.new()
	title.text = ("◆ " if is_ms else "") + _name(item)
	title.add_theme_font_override("font", Palette.title_font())
	title.add_theme_font_size_override("font_size", 13)
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(title)
	var where := Label.new()
	where.text = place
	where.add_theme_font_size_override("font_size", 11)
	where.add_theme_color_override("font_color", Palette.P2 if unplanned else Palette.MUTED)
	where.clip_text = true
	where.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	where.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(where)
	return node


## Ein Doppelklick öffnet die Aufgabe.
func _on_node_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and event.double_click:
		task_requested.emit(id)


func _set_hot(id: String) -> void:
	if id != _hot:
		_hot = id
		_canvas.queue_redraw()


## Die Kanten: im Bogen von der Voraussetzung zum Wartenden, mit Pfeil. Die
## Pfeile des Knotens unter dem Zeiger treten hervor, die anderen zurück.
func _draw_edges() -> void:
	# Hervorgehobenes zuletzt, damit es oben liegt.
	for pass_hot in [false, true]:
		for e in _edges:
			var hot: bool = _hot != "" and (e["a"] == _hot or e["b"] == _hot)
			if hot != pass_hot:
				continue
			var color := Color(Palette.INK, 0.6)
			var width := 2.0
			match e["state"]:
				DepGraph.MISPLACED:
					color = Palette.P1
					width = 2.4
				DepGraph.DONE:
					color = Color(Palette.OK, 0.5)
			if hot:
				color = Palette.P1 if e["state"] == DepGraph.MISPLACED else Palette.ACCENT
				width = 3.0
			elif _hot != "":
				color.a *= 0.25
			# Der Pfeil zieht sich von der Voraussetzung zum Wartenden.
			var points: PackedVector2Array = e["points"]
			var lengths: PackedFloat32Array = e["lengths"]
			var total: float = lengths[-1]
			var grown := clampf((_time - e["start"]) / EDGE_SECONDS, 0.0, 1.0)
			if grown <= 0.0:
				continue
			grown = 1.0 - pow(1.0 - grown, 3.0)
			if grown >= 1.0:
				_canvas.draw_polyline(points, color, width, true)
				var to: Vector2 = e["to"]
				_canvas.draw_colored_polygon(PackedVector2Array([to + Vector2(ARROW, 0), to + Vector2(-2, -6), to + Vector2(-2, 6)]), color)
			else:
				var part := PackedVector2Array()
				for i in points.size():
					if lengths[i] > grown * total:
						break
					part.append(points[i])
				part.append(_along(points, lengths, grown * total))
				if part.size() >= 2:
					_canvas.draw_polyline(part, color, width, true)
			_canvas.draw_circle(e["from"], 3.0, color)
			# Über die hervorgehobenen Pfeile wandern Punkte in ihre Richtung: alle
			# gleich schnell und in gleichem Abstand, ein langer Pfeil trägt mehr.
			if hot and grown >= 1.0:
				var at := fposmod(_time * DOT_SPEED, DOT_SPACING)
				while at < total:
					_canvas.draw_circle(_along(points, lengths, at), 3.5, Color(1, 1, 1, 0.9))
					at += DOT_SPACING


static func _name(item: Dictionary) -> String:
	return str(item["title"]) if item.get("title") else "Ohne Titel"


## Der Punkt auf der Linie nach so vielen Pixeln Weg. `lengths` ist der Weg
## bis zu jedem ihrer Punkte.
static func _along(points: PackedVector2Array, lengths: PackedFloat32Array, way: float) -> Vector2:
	var i := clampi(lengths.bsearch(way) - 1, 0, points.size() - 2)
	var span := lengths[i + 1] - lengths[i]
	return points[i].lerp(points[i + 1], clampf((way - lengths[i]) / span, 0.0, 1.0) if span > 0.0 else 0.0)
