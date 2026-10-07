@tool
extends Control
## Das Burnup-Diagramm eines Milestones, nach `Burnup.tsx` in Tasker:
## Committed und Erledigt je Tag seit dem Start, gestrichelt die Prognose,
## dazu die Linien für heute und das Enddatum.
##
## Gezeichnet wird, was `rules/burnup.gd` ausgerechnet hat.

const Palette := preload("palette.gd")
const Burnup := preload("../rules/burnup.gd")

const LEFT := 34.0
const RIGHT := 44.0
const TOP := 24.0
const BOTTOM := 26.0
const FONT_SIZE := 11

## Das Ergebnis von `Burnup.data` – ohne gibt es nichts zu zeichnen.
var data: Variant = null: set = set_data

## Der Tag unter dem Zeiger, als Tage seit dem Start – oder -1.
var _hover := -1


func _init() -> void:
	custom_minimum_size = Vector2(320, 210)
	mouse_exited.connect(func() -> void:
		_hover = -1
		tooltip_text = ""
		queue_redraw())


func set_data(value: Variant) -> void:
	data = value
	queue_redraw()


func _top() -> float:
	return ceilf(data["max_v"] * 1.1)


func _x(i: float) -> float:
	return LEFT + (i / data["max_i"]) * (size.x - LEFT - RIGHT)


func _y(v: float) -> float:
	return TOP + (1.0 - v / _top()) * (size.y - TOP - BOTTOM)


func _gui_input(event: InputEvent) -> void:
	if data == null or not event is InputEventMouseMotion:
		return
	var i := roundi(clampf((event.position.x - LEFT) / (size.x - LEFT - RIGHT), 0.0, 1.0) * data["max_i"])
	if i == _hover:
		return
	_hover = i
	var day := Burnup.format_day(data["start_day"] + i)
	if i <= data["end_i"]:
		tooltip_text = "%s\nCommitted %d · Erledigt %d" % [day, data["scope"][i], data["done_s"][i]]
	elif data["fc_i"] != null and i <= ceili(data["fc_i"]):
		var done: float = minf(data["s"], data["dn"] + (data["s"] - data["dn"]) * (i - data["today_i"]) / (data["fc_i"] - data["today_i"]))
		tooltip_text = "%s · Prognose\nCommitted %d · Erledigt %.1f" % [day, data["s"], done]
	else:
		tooltip_text = ""
	queue_redraw()


func _draw() -> void:
	if data == null:
		return
	var font := Palette.body_font()
	var top := _top()
	var base := size.y - BOTTOM
	var grid := Color(Palette.INK, 0.10)

	for v in [0.0, roundf(top / 2.0), top]:
		draw_line(Vector2(LEFT, _y(v)), Vector2(size.x - RIGHT, _y(v)), grid, 1.0)
		_text(font, Vector2(LEFT - 6, _y(v) + 4), str(int(v)), Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)

	# Erledigt: die Fläche unter der Kurve.
	var done_line := _curve(data["done_s"])
	if done_line.size() >= 2:
		var area := done_line.duplicate()
		area.append(Vector2(done_line[done_line.size() - 1].x, base))
		area.append(Vector2(done_line[0].x, base))
		draw_colored_polygon(area, Color(Palette.ACCENT, 0.16))

	var today_x := _x(data["today_i"])
	if not data["done"]:
		draw_line(Vector2(today_x, TOP - 4), Vector2(today_x, base), Color(Palette.INK, 0.55), 1.0)
	if data["dead_i"] != null:
		draw_dashed_line(Vector2(_x(data["dead_i"]), TOP - 4), Vector2(_x(data["dead_i"]), base), Palette.P1, 1.5, 4.0)

	# Der committete Umfang läuft gepunktet weiter bis zum Ende oder zur Prognose.
	var scope_end: float = maxf(data["today_i"], maxf(data["fc_i"] if data["fc_i"] != null else 0.0, float(data["dead_i"]) if data["dead_i"] != null else 0.0))
	if not data["done"] and scope_end > data["today_i"]:
		draw_dashed_line(Vector2(today_x, _y(data["s"])), Vector2(_x(scope_end), _y(data["s"])), Palette.MUTED, 1.5, 2.0)
	if data["fc_i"] != null:
		draw_dashed_line(Vector2(today_x, _y(data["dn"])), Vector2(_x(data["fc_i"]), _y(data["s"])), Palette.ACCENT, 2.0, 6.0)

	var scope_line := _curve(data["scope"])
	if scope_line.size() >= 2:
		draw_polyline(scope_line, Palette.MUTED, 2.0, true)
	if done_line.size() >= 2:
		draw_polyline(done_line, Palette.ACCENT, 2.0, true)

	# Die Werte am Ende der beiden Linien rücken auseinander, wenn sie sich überdecken würden.
	var y_scope := _y(data["s"])
	var y_done := _y(data["dn"])
	if absf(y_scope - y_done) < 12.0:
		var push := 6.0 if y_scope <= y_done else -6.0
		y_scope -= push
		y_done += push
	var end_x := _x(data["end_i"]) + 5.0
	_text(font, Vector2(end_x, y_scope + 4), str(data["s"]), Palette.MUTED)
	_text(font, Vector2(end_x, y_done + 4), str(data["dn"]), Palette.ACCENT)

	if not data["done"]:
		var near: bool = data["dead_i"] != null and absf(_x(data["dead_i"]) - today_x) < 70.0
		var to_left: bool = near and _x(data["dead_i"]) >= today_x
		_text(font, Vector2(today_x + (-4.0 if to_left else 0.0), TOP - 9), "Heute", Palette.INK,
			HORIZONTAL_ALIGNMENT_RIGHT if to_left else HORIZONTAL_ALIGNMENT_CENTER)
	if data["dead_i"] != null:
		var dead_x := _x(data["dead_i"])
		var label := "Ende %s" % Burnup.format_day(data["start_day"] + data["dead_i"])
		var crowded: bool = not data["done"] and absf(dead_x - today_x) < 70.0
		var align := HORIZONTAL_ALIGNMENT_CENTER
		if crowded:
			align = HORIZONTAL_ALIGNMENT_LEFT if dead_x >= today_x else HORIZONTAL_ALIGNMENT_RIGHT
		elif dead_x > size.x - RIGHT - 30.0:
			align = HORIZONTAL_ALIGNMENT_RIGHT
		_text(font, Vector2(dead_x + (4.0 if align == HORIZONTAL_ALIGNMENT_LEFT else 0.0), TOP - 9), label, Palette.P1, align)

	_text(font, Vector2(LEFT, size.y - 6), Burnup.format_day(data["start_day"]), Palette.MUTED)
	_text(font, Vector2(size.x - RIGHT, size.y - 6), Burnup.format_day(data["start_day"] + roundi(data["max_i"])), Palette.MUTED, HORIZONTAL_ALIGNMENT_RIGHT)

	if _hover >= 0 and _hover <= data["end_i"]:
		var hx := _x(_hover)
		draw_line(Vector2(hx, TOP), Vector2(hx, base), Color(Palette.INK, 0.3), 1.0)
		draw_circle(Vector2(hx, _y(data["scope"][_hover])), 4.0, Palette.MUTED, true, -1.0, true)
		draw_circle(Vector2(hx, _y(data["done_s"][_hover])), 4.0, Palette.ACCENT, true, -1.0, true)


## Text an einem Ankerpunkt: links davon, mittig darauf oder rechts davon.
func _text(font: Font, at: Vector2, text: String, color: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= width
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= width / 2.0
	draw_string(font, Vector2(x, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)


## Weiche Kurve durch die Tagespunkte (monotone kubische Interpolation nach
## Fritsch-Carlson): schießt nie über die Werte hinaus, Plateaus bleiben flach.
func _curve(values: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in values.size():
		pts.append(Vector2(_x(i), _y(values[i])))
	var n := pts.size()
	if n < 3:
		return pts

	var slope := []
	for i in n - 1:
		slope.append((pts[i + 1].y - pts[i].y) / (pts[i + 1].x - pts[i].x))
	var t := []
	t.resize(n)
	t[0] = slope[0]
	t[n - 1] = slope[n - 2]
	for i in range(1, n - 1):
		t[i] = 0.0 if slope[i - 1] * slope[i] <= 0.0 else (slope[i - 1] + slope[i]) / 2.0
	for i in n - 1:
		if slope[i] == 0.0:
			t[i] = 0.0
			t[i + 1] = 0.0
			continue
		var a: float = t[i] / slope[i]
		var b: float = t[i + 1] / slope[i]
		var q := a * a + b * b
		if q > 9.0:
			var k := 3.0 / sqrt(q)
			t[i] = k * a * slope[i]
			t[i + 1] = k * b * slope[i]

	var out := PackedVector2Array()
	for i in n - 1:
		var h := (pts[i + 1].x - pts[i].x) / 3.0
		var c1 := Vector2(pts[i].x + h, pts[i].y + t[i] * h)
		var c2 := Vector2(pts[i + 1].x - h, pts[i + 1].y - t[i + 1] * h)
		for step in 8:
			out.append(pts[i].bezier_interpolate(c1, c2, pts[i + 1], step / 8.0))
	out.append(pts[n - 1])
	return out
