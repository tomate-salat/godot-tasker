@tool
extends Control
## Ein Sammelordner für Karten, nach hinten umgeschlagen: zu sehen ist eine
## Seite mit Fächern, die Ringe greifen um ihre linke Kante, dahinter schauen
## Deckel und umgeblätterte Seiten hervor. Rechts stehen die Registerblätter.
##
## Die Planung (`plan_view.gd`) legt zwei davon nebeneinander: einen für den
## Vorrat, einen für die Decks. Jeder Abschnitt hat sein Registerblatt und
## seine eigenen Seiten – auf einer Seite stecken nur Karten eines Abschnitts.
## Geblättert wird mit dem Mausrad, den Knöpfen unter dem Ordner oder einem
## Registerblatt; die Seite schwenkt dabei um die Ringe nach hinten.
##
## Ein Abschnitt: `{ title, items, tip, header }`. `items` sind die Karten in
## Reihenfolge, je `{ task, child_of }` – `child_of` ist der Titel der Karte,
## aus der eine Unteraufgabe aufgefächert wurde, sonst leer. `header` steht
## über jeder Seite des Abschnitts: `{ id, title, line, late, pct, accent, tip }`;
## ohne `pct` gibt es keinen Fortschrittsbalken, ohne `id` keinen Klick.

## Die Kopfzeile einer Seite wurde angeklickt.
signal header_pressed(id: String)

const Card := preload("card.gd")
const Palette := preload("palette.gd")

## Über einer aufgefächerten Unteraufgabe steht in ihrem Fach, wozu sie gehört.
const CAPTION := 18.0
const POCKET := Vector2(Card.SIZE.x + 12.0, Card.SIZE.y + CAPTION + 12.0)
const GAP := 6.0
const PAD := 12.0
## An der linken Kante bleibt Platz für die Löcher der Ringe.
const INNER := 26.0
## So weit steht die Seite vom linken Rand, damit die Ringe um ihre Kante
## greifen können.
const EDGE := 16.0
const FOOT := 36.0
const HEADER := 62.0
## So weit ragen die Registerblätter mindestens über die Seite hinaus.
const TAB_OUT := 84.0
const TAB_HEIGHT := 30.0
const RINGS := 3

## So lange dauert das Umblättern einer Seite.
const FLIP_SECONDS := 0.26

const COVER := Color("101614")
const PAGE := Color("232c29")
const SLEEVE := Color("1a211f")
const HOLE := Color("0c1110")
const METAL := Color("59645f")
const SHINE := Color("c3cdc8")
## Die Farben der Registerblätter, der Reihe nach.
const TAB_COLORS := [Palette.ACCENT, Palette.INFO, Palette.P2, Palette.UNCLEAR, Palette.P1, Palette.OK, Palette.P3]

## Macht aus einer Aufgabe ihre Karte.
var card_maker := Callable()
var columns := 3
## So weit ragen die Registerblätter über die Seite hinaus – mehr, wenn Platz ist.
var tab_out := TAB_OUT
## Mit welchem Abschnitt ein Ordner aufgeschlagen wird, den es noch nicht gab.
var start_section := 0

var _sections: Array = []
## Die Seiten: je `{ section, items }` – `items` mit `{ task, child_of }`.
var _leaves: Array = []
## Welcher Ordner gezeigt wird, und je Ordner die aufgeschlagene Seite.
var _key := ""
var _pages := {}
var _flipping := false
var _flip: Tween
## Die Karte, zu der geblättert wurde, und wie stark ihr Fach gerade
## aufleuchtet (1 bis 0).
var _glow_task := ""
var _glow := 0.0: set = _set_glow
var _glow_tween: Tween

var _tabs: Control
## Hier liegen die Seiten: die aufgeschlagene und, beim Blättern, die zweite.
var _sheets: Control
var _sheet: Control
var _rings: Control
var _prev: Button
var _next: Button
var _count: Label
var _shade: GradientTexture2D
var _cast: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Die Registerblätter stecken unter dem Rand der Seite.
	_tabs = Control.new()
	_tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_tabs)
	_sheets = Control.new()
	_sheets.mouse_filter = Control.MOUSE_FILTER_PASS
	_sheets.clip_contents = true
	add_child(_sheets)
	# Die Ringe gehen durch die Seite und liegen deshalb über ihr.
	_rings = Control.new()
	_rings.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rings.draw.connect(_draw_rings)
	add_child(_rings)

	_prev = _flip_button("‹", "Zurückblättern", -1)
	_next = _flip_button("›", "Weiterblättern", 1)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.add_theme_color_override("font_color", Palette.MUTED)
	_count.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_count)

	# Der Schatten auf der Seite, die sich hebt: zum freien Rand hin dunkler …
	_shade = _gradient(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0.9))
	# … und der, den sie auf die Seite darunter wirft.
	_cast = _gradient(Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.0))


static func _gradient(from: Color, to: Color) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, from)
	g.set_color(1, to)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 4
	return t


func _flip_button(text: String, tip: String, by: int) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(func() -> void: turn(by))
	add_child(b)
	return b


## Wie breit eine Seite mit so vielen Spalten ist.
static func page_width(column_count: int) -> float:
	return INNER + PAD + column_count * POCKET.x + (column_count - 1) * GAP


## Wie breit der Ordner ist, ohne die Registerblätter.
static func binder_width(column_count: int) -> float:
	return EDGE + page_width(column_count)


## Zeigt diese Abschnitte im Ordner `key`. Jeder Ordner merkt sich, wo er aufgeschlagen ist.
func show_sections(key: String, sections: Array) -> void:
	if _flip != null:
		_flip.kill()
	_flipping = false
	_key = key
	_sections = sections
	var wide := page_width(columns)
	var tall := size.y - FOOT
	_sheets.position = Vector2(EDGE, 0.0)
	_sheets.size = Vector2(wide, tall)
	_rings.position = Vector2(-EDGE, 0.0)
	_rings.size = Vector2(EDGE * 2.0 + 30.0, tall)
	_rings.queue_redraw()
	var middle := binder_width(columns) / 2.0
	_prev.position = Vector2(middle - 150.0, tall + 2.0)
	_next.position = Vector2(middle + 120.0, tall + 2.0)
	_count.position = Vector2(middle - 115.0, tall + 8.0)
	_count.size = Vector2(230.0, 20.0)

	_paginate()
	if not _pages.has(_key):
		for i in _leaves.size():
			if _leaves[i]["section"] == start_section:
				_pages[_key] = i
				break
	_pages[_key] = clampi(_pages.get(_key, 0), 0, _leaves.size() - 1)
	_build_tabs()
	for c in _sheets.get_children():
		c.queue_free()
	_sheet = _make_sheet(_pages[_key])
	_sheets.add_child(_sheet)
	_show_place()
	queue_redraw()


## Wie viele Reihen Fächer auf eine Seite passen.
func _rows() -> int:
	return maxi(int((size.y - FOOT - PAD * 2.0 - HEADER + GAP) / (POCKET.y + GAP)), 1)


## Teilt die Abschnitte auf Seiten auf: jeder beginnt auf einer neuen.
func _paginate() -> void:
	_leaves = []
	var per_page := _rows() * columns
	for s in _sections.size():
		var items: Array = _sections[s]["items"]
		# Auch ein leerer Abschnitt hat seine Seite.
		for from in range(0, maxi(items.size(), 1), per_page):
			_leaves.append({"section": s, "items": items.slice(from, from + per_page)})
	if _leaves.is_empty():
		_leaves.append({"section": 0, "items": []})


func page_count() -> int:
	return _leaves.size()


## Blättert um `by` Seiten weiter oder zurück.
func turn(by: int) -> void:
	open_page(_pages.get(_key, 0) + by)


## Schlägt die Seite auf. Vorwärts richtet sich die alte Seite auf und
## schwenkt um die Ringe nach hinten weg, darunter liegt schon die nächste;
## rückwärts kommt die Seite von hinten um die Ringe und legt sich obenauf.
func open_page(to: int) -> void:
	to = clampi(to, 0, page_count() - 1)
	var from: int = _pages.get(_key, 0)
	if _flipping or to == from:
		return
	_flipping = true
	_pages[_key] = to
	var forward := to > from

	var old := _sheet
	_sheet = _make_sheet(to)
	_sheets.add_child(_sheet)
	if forward:
		_sheets.move_child(_sheet, 0)
	# Die Seite, die sich bewegt, liegt oben; darunter die andere, dazwischen der Schatten.
	var moving := old if forward else _sheet
	var wide := _sheets.size.x

	var cast := TextureRect.new()
	cast.texture = _cast
	cast.stretch_mode = TextureRect.STRETCH_SCALE
	cast.size = Vector2(110.0, _sheets.size.y)
	cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheets.add_child(cast)
	_sheets.move_child(cast, 1)

	var shade := TextureRect.new()
	shade.texture = _shade
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moving.add_child(shade)
	# Gedreht wird um die linke Kante, an der die Ringe sitzen.
	moving.pivot_offset = Vector2(0.0, moving.size.y / 2.0)

	# Aufgerichtet ist die Seite nur noch eine Kante, etwas höher, weil näher, und im
	# Schatten. Der geworfene Schatten liegt jenseits ihres freien Rands.
	var flat := {"scale": Vector2.ONE, "shade": 0.0, "cast": wide, "cast_a": 0.0}
	var upright := {"scale": Vector2(0.0, 1.06), "shade": 1.0, "cast": 0.0, "cast_a": 1.0}
	var start := flat if forward else upright
	var end := upright if forward else flat
	moving.scale = start["scale"]
	shade.modulate.a = start["shade"]
	cast.position.x = start["cast"]
	cast.modulate.a = start["cast_a"]

	_flip = create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN if forward else Tween.EASE_OUT)
	_flip.tween_property(moving, "scale", end["scale"], FLIP_SECONDS)
	_flip.tween_property(shade, "modulate:a", end["shade"], FLIP_SECONDS)
	_flip.tween_property(cast, "position:x", end["cast"], FLIP_SECONDS)
	_flip.tween_property(cast, "modulate:a", end["cast_a"], FLIP_SECONDS)
	_flip.chain().tween_callback(func() -> void:
		for x in [old, cast, shade]:
			if is_instance_valid(x):
				x.queue_free()
		_flipping = false)
	_show_place()


# -------------------------------------------------------------- Aufbau

## Die Registerblätter am rechten Rand: je Abschnitt eines, in eigener Farbe,
## das zu seiner ersten Seite springt.
func _build_tabs() -> void:
	for c in _tabs.get_children():
		c.queue_free()
	# Viele Abschnitte rücken zusammen, damit alle Blätter an den Rand passen.
	var step := minf(TAB_HEIGHT + 4.0, (size.y - FOOT - 24.0) / maxf(_sections.size(), 1))
	for s in _sections.size():
		var section: Dictionary = _sections[s]
		var color: Color = TAB_COLORS[s % TAB_COLORS.size()]
		var tab := Button.new()
		tab.text = section["title"]
		tab.toggle_mode = true
		tab.focus_mode = Control.FOCUS_NONE
		tab.clip_text = true
		tab.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tab.add_theme_font_size_override("font_size", 12)
		tab.add_theme_color_override("font_color", Color(Palette.INK, 0.75))
		tab.add_theme_color_override("font_hover_color", Palette.INK)
		tab.add_theme_color_override("font_pressed_color", Palette.SURFACE)
		tab.add_theme_color_override("font_hover_pressed_color", Palette.SURFACE)
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var box := StyleBoxFlat.new()
			box.bg_color = color if state.contains("pressed") else color.darkened(0.62 if state == "normal" else 0.5)
			box.border_color = color.darkened(0.25)
			box.border_width_top = 1
			box.border_width_bottom = 1
			box.border_width_right = 1
			box.corner_radius_top_right = 9
			box.corner_radius_bottom_right = 9
			box.content_margin_left = 20.0
			box.content_margin_right = 8.0
			tab.add_theme_stylebox_override(state, box)
		tab.tooltip_text = section.get("tip", "Zu „%s“ blättern" % section["title"])
		tab.pressed.connect(reveal_section.bind(s))
		tab.position.y = 16.0 + s * step
		tab.size = Vector2(tab_out + 8.0, minf(TAB_HEIGHT, step - 2.0))
		_tabs.add_child(tab)


## Blättert zur ersten Seite dieses Abschnitts.
func reveal_section(section: int) -> void:
	for i in _leaves.size():
		if _leaves[i]["section"] == section:
			open_page(i)
			break
	_show_place()


## Blättert zur Karte dieser Aufgabe und lässt ihr Fach aufleuchten. Falsch,
## wenn sie in diesem Ordner nicht steckt.
func reveal(task_id: String) -> bool:
	for i in _leaves.size():
		for item in _leaves[i]["items"]:
			if item["task"]["id"] == task_id:
				_glow_task = task_id
				open_page(i)
				_show_place()
				if _glow_tween != null:
					_glow_tween.kill()
				_glow = 1.0
				_glow_tween = create_tween()
				_glow_tween.tween_interval(FLIP_SECONDS if _flipping else 0.01)
				_glow_tween.tween_property(self, "_glow", 0.0, 1.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
				return true
	return false


func _set_glow(value: float) -> void:
	_glow = value
	if is_instance_valid(_sheet):
		_sheet.queue_redraw()


## Eine Seite des Ordners: das Blatt mit Kopfzeile, Fächern und den Karten darin.
func _make_sheet(page: int) -> Control:
	var sheet := Control.new()
	sheet.size = _sheets.size
	sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	var leaf: Dictionary = _leaves[page]
	var header: Dictionary = _sections[leaf["section"]].get("header", {}) if not _sections.is_empty() else {}
	var top := PAD + HEADER
	var rows := _rows()
	# Was in der Höhe übrig bleibt, verteilt sich über und unter den Fächern.
	var spare := maxf(sheet.size.y - top - PAD - rows * POCKET.y - (rows - 1) * GAP, 0.0) / 2.0
	var items: Array = leaf["items"]
	var pockets := []
	for k in rows * columns:
		var rect := Rect2(Vector2(INNER + (k % columns) * (POCKET.x + GAP), top + spare + (k / columns) * (POCKET.y + GAP)), POCKET)
		var pocket := {"rect": rect, "caption": "", "task": ""}
		if k < items.size():
			var item: Dictionary = items[k]
			pocket["task"] = item["task"]["id"]
			if item.get("child_of", "") != "":
				pocket["caption"] = "↳ " + item["child_of"]
			var card: Control = card_maker.call(item["task"])
			card.position = rect.position + Vector2((POCKET.x - Card.SIZE.x) / 2.0, CAPTION + 6.0)
			sheet.add_child(card)
		pockets.append(pocket)
	if header.get("id", "") != "":
		# Die Kopfzeile ist ein Knopf über die Breite der Fächer.
		var open := Button.new()
		open.flat = true
		open.focus_mode = Control.FOCUS_NONE
		open.mouse_filter = Control.MOUSE_FILTER_PASS
		open.tooltip_text = header.get("tip", "")
		open.position = Vector2(INNER, PAD - 4.0)
		open.size = Vector2(columns * POCKET.x + (columns - 1) * GAP, HEADER - 4.0)
		open.pressed.connect(func() -> void: header_pressed.emit(header["id"]))
		sheet.add_child(open)
	sheet.draw.connect(_draw_sheet.bind(sheet, pockets, header))
	return sheet


## Seitenzahl, Blätter-Knöpfe und das Registerblatt des aufgeschlagenen Abschnitts.
func _show_place() -> void:
	var page: int = _pages.get(_key, 0)
	_prev.disabled = page <= 0
	_next.disabled = page >= page_count() - 1
	var cards := 0
	for section in _sections:
		cards += section["items"].size()
	_count.text = "Seite %d von %d  ·  %d %s" % [page + 1, page_count(), cards, "Karte" if cards == 1 else "Karten"]
	var current: int = _leaves[page]["section"]
	var rest := binder_width(columns) - 14.0
	var n := 0
	for tab in _tabs.get_children():
		if tab.is_queued_for_deletion():
			continue
		tab.set_pressed_no_signal(n == current)
		# Das Blatt des aufgeschlagenen Abschnitts steht etwas weiter heraus.
		tab.position.x = rest + (6.0 if n == current else 0.0)
		n += 1


# ------------------------------------------------------------ Zeichnen

## Hinter der Seite liegen der Deckel und der Stapel der schon umgeblätterten
## Seiten und schauen unten und rechts hervor.
func _draw() -> void:
	var cover := StyleBoxFlat.new()
	cover.bg_color = COVER
	cover.border_color = Color(1, 1, 1, 0.06)
	cover.set_border_width_all(1)
	cover.set_corner_radius_all(14)
	cover.shadow_color = Color(0, 0, 0, 0.4)
	cover.shadow_size = 10
	cover.shadow_offset = Vector2(0, 4)
	var wide := page_width(columns)
	var tall := size.y - FOOT
	draw_style_box(cover, Rect2(-6.0, 4.0, EDGE + wide + 20.0, tall + 10.0))
	var back := StyleBoxFlat.new()
	back.bg_color = PAGE.darkened(0.22)
	back.border_color = Palette.LINE_STRONG
	back.set_border_width_all(1)
	back.set_corner_radius_all(8)
	for k in [3, 2, 1]:
		draw_style_box(back, Rect2(EDGE + k * 3.0, 2.0 + k * 3.0, wide - 2.0, tall - 4.0))


## Jeder Ring greift aus seinem Loch im Bogen um die linke Kante der Seite
## herum nach hinten.
func _draw_rings() -> void:
	var edge := EDGE * 2.0
	for r in RINGS:
		var y := _rings.size.y * (r + 0.5) / RINGS
		var arc := PackedVector2Array()
		for i in 17:
			var a := PI * i / 16.0
			arc.append(Vector2(edge + cos(a) * 14.0, y - sin(a) * 10.0))
		_rings.draw_polyline(arc, Color(0, 0, 0, 0.45), 8.0, true)
		_rings.draw_polyline(arc, METAL, 5.0, true)
		_rings.draw_polyline(arc.slice(3, 10), SHINE, 1.5, true)


## Das Blatt: Kopfzeile, und je Platz eine Hülle.
func _draw_sheet(sheet: Control, pockets: Array, header: Dictionary) -> void:
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAGE
	paper.border_color = Palette.LINE_STRONG
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(8)
	sheet.draw_style_box(paper, Rect2(1.0, 2.0, sheet.size.x - 2.0, sheet.size.y - 4.0))
	# Die Löcher für die Ringe.
	for r in RINGS:
		sheet.draw_circle(Vector2(14.0, sheet.size.y * (r + 0.5) / RINGS), 5.0, HOLE)

	var font := sheet.get_theme_default_font()
	if not header.is_empty():
		var wide := columns * POCKET.x + (columns - 1) * GAP
		sheet.draw_string(Palette.title_font(), Vector2(INNER + 4.0, PAD + 16.0), header["title"], HORIZONTAL_ALIGNMENT_LEFT, wide - 8.0, 16, header.get("accent", Palette.INK))
		sheet.draw_string(font, Vector2(INNER + 4.0, PAD + 36.0), header.get("line", ""), HORIZONTAL_ALIGNMENT_LEFT, wide - 8.0, 12, Palette.P1 if header.get("late", false) else Palette.MUTED)
		if header.has("pct"):
			sheet.draw_rect(Rect2(INNER + 4.0, PAD + 44.0, wide - 8.0, 5.0), Color(1, 1, 1, 0.08))
			sheet.draw_rect(Rect2(INNER + 4.0, PAD + 44.0, (wide - 8.0) * clampf(header["pct"] / 100.0, 0.0, 1.0), 5.0), Palette.ACCENT)
		else:
			sheet.draw_line(Vector2(INNER + 4.0, PAD + 46.0), Vector2(INNER + wide - 4.0, PAD + 46.0), Color(1, 1, 1, 0.08), 1.0)

	var sleeve := StyleBoxFlat.new()
	sleeve.bg_color = SLEEVE
	sleeve.border_color = Color(1, 1, 1, 0.07)
	sleeve.set_border_width_all(1)
	sleeve.set_corner_radius_all(8)
	for pocket in pockets:
		var rect: Rect2 = pocket["rect"]
		sheet.draw_style_box(sleeve, rect)
		# Wurde zu einer Karte geblättert, leuchtet ihr Fach kurz auf.
		if _glow > 0.0 and sheet == _sheet and _glow_task != "" and pocket["task"] == _glow_task:
			sheet.draw_rect(rect.grow(1.0), Color(Palette.ACCENT, _glow), false, 2.5)
			sheet.draw_rect(rect, Color(Palette.ACCENT, _glow * 0.12))
		if pocket["caption"] != "":
			sheet.draw_string(font, rect.position + Vector2(8.0, 15.0), pocket["caption"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14.0, 11, Palette.ACCENT)


# ------------------------------------------------------------ Blättern

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				turn(1)
				accept_event()
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				turn(-1)
				accept_event()
