@tool
extends Control
## Eine Seite des aufgeschlagenen Ordners: Karten in Fächern, zum
## Durchblättern – wie ein Sammelordner für Kartenspiele.
##
## Die Planung (`plan_view.gd`) legt zwei davon nebeneinander: links den
## Vorrat, rechts die Decks, dazwischen die Ringe. Am äußeren Rand stehen die
## Registerblätter; sie springen zur ersten Seite ihres Abschnitts. Geblättert
## wird mit dem Mausrad, den Knöpfen unter der Seite oder einem Registerblatt.
##
## Ein Abschnitt: `{ title, items, tip, header }`. `items` sind die Karten in
## Reihenfolge, je `{ task, child_of }` – `child_of` ist der Titel der Karte,
## aus der eine Unteraufgabe aufgefächert wurde, sonst leer. `header` ist leer
## oder `{ id, title, line, late, pct, accent, tip }` und steht dann über der Seite.

## Die Kopfzeile einer Seite wurde angeklickt.
signal header_pressed(id: String)

const Card := preload("card.gd")
const Palette := preload("palette.gd")

## Über jeder Karte steht in ihrem Fach, wozu sie gehört.
const CAPTION := 18.0
const POCKET := Vector2(Card.SIZE.x + 12.0, Card.SIZE.y + CAPTION + 12.0)
const GAP := 6.0
const PAD := 14.0
## Am Rand zur Ordnermitte bleibt Platz für die Löcher der Ringe.
const INNER := 30.0
const FOOT := 36.0
const HEADER := 62.0
## So weit ragen die Registerblätter mindestens über die Seite hinaus.
const TAB_OUT := 104.0
const TAB_HEIGHT := 30.0
const RINGS := 3

## So lange dauert das Umblättern einer Seite.
const FLIP_SECONDS := 0.26

const PAGE := Color("232c29")
const SLEEVE := Color("1a211f")
const HOLE := Color("0c1110")
## Die Farben der Registerblätter, der Reihe nach.
const TAB_COLORS := [Palette.ACCENT, Palette.INFO, Palette.P2, Palette.UNCLEAR, Palette.P1, Palette.OK, Palette.P3]

## Macht aus einer Aufgabe ihre Karte.
var card_maker := Callable()
## Auf welcher Seite des Ordners dieses Blatt liegt: links ist die Ordnermitte
## rechts und die Registerblätter stehen links heraus, rechts umgekehrt.
var left_side := false
var columns := 3
## So weit ragen die Registerblätter über die Seite hinaus – mehr, wenn Platz ist.
var tab_out := TAB_OUT
## Mit welchem Abschnitt ein Ordner aufgeschlagen wird, den es noch nicht gab.
var start_section := 0
## Ob jeder Abschnitt auf einer neuen Seite beginnt und eine Seite nur Karten
## eines Abschnitts trägt – sonst laufen die Karten durch.
var break_pages := false

var _sections: Array = []
## Die Seiten: je `{ section, items }` – `items` mit `{ task, child_of, section }`.
var _leaves: Array = []
## Welcher Ordner gezeigt wird, und je Ordner die aufgeschlagene Seite.
var _key := ""
var _pages := {}
var _flipping := false
var _flip: Tween
## Der Abschnitt, dessen Registerblatt zuletzt angeklickt wurde (-1: keiner),
## und wie stark seine Fächer gerade aufleuchten (1 bis 0).
var _picked := -1
var _glow := 0.0: set = _set_glow
var _glow_tween: Tween

var _tabs: Control
## Hier liegen die Seiten: die aufgeschlagene und, beim Blättern, die zweite.
var _sheets: Control
var _sheet: Control
var _prev: Button
var _next: Button
var _count: Label
var _shade: GradientTexture2D
var _cast: GradientTexture2D


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Die Registerblätter stecken unter dem Seitenrand.
	_tabs = Control.new()
	_tabs.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_tabs)
	_sheets = Control.new()
	_sheets.mouse_filter = Control.MOUSE_FILTER_PASS
	_sheets.clip_contents = true
	add_child(_sheets)

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


## Wie breit ein Blatt mit so vielen Spalten ist, ohne die Registerblätter.
static func sheet_width(column_count: int) -> float:
	return INNER + PAD + column_count * POCKET.x + (column_count - 1) * GAP


## Auf welcher Höhe die Ringe durch ein Blatt dieser Höhe gehen.
static func ring_heights(height: float) -> Array:
	var out := []
	for r in RINGS:
		out.append((height - FOOT) * (r + 0.5) / RINGS)
	return out


## Wo das Blatt liegt, vom linken Rand dieses Bausteins aus.
func sheet_left() -> float:
	return tab_out if left_side else 0.0


## Zeigt diese Abschnitte im Ordner `key`. Jeder Ordner merkt sich seine Seite.
func show_sections(key: String, sections: Array) -> void:
	if _flip != null:
		_flip.kill()
	_flipping = false
	_key = key
	_sections = sections
	var wide := sheet_width(columns)
	_sheets.position = Vector2(sheet_left(), 0.0)
	_sheets.size = Vector2(wide, size.y - FOOT)
	_prev.position = Vector2(sheet_left() + 6.0, size.y - FOOT + 2.0)
	_next.position = Vector2(sheet_left() + wide - 40.0, size.y - FOOT + 2.0)
	_count.position = Vector2(sheet_left() + 44.0, size.y - FOOT + 8.0)
	_count.size = Vector2(wide - 88.0, 20.0)
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


## Wie viele Reihen Fächer auf ein Blatt passen, mit oder ohne Kopfzeile.
func _rows(with_header: bool) -> int:
	var room := size.y - FOOT - PAD * 2.0 - (HEADER if with_header else 0.0)
	return maxi(int((room + GAP) / (POCKET.y + GAP)), 1)


## Teilt die Abschnitte auf Seiten auf.
func _paginate() -> void:
	_leaves = []
	if break_pages:
		for s in _sections.size():
			var per_page := _rows(not _sections[s].get("header", {}).is_empty()) * columns
			var items: Array = _sections[s]["items"]
			# Auch ein leerer Abschnitt hat seine Seite.
			for from in range(0, maxi(items.size(), 1), per_page):
				_leaves.append({"section": s, "items": items.slice(from, from + per_page).map(func(item: Dictionary) -> Dictionary:
					return {"task": item["task"], "child_of": item.get("child_of", ""), "section": s})})
		if _leaves.is_empty():
			_leaves.append({"section": 0, "items": []})
		return
	var all := []
	for s in _sections.size():
		for item in _sections[s]["items"]:
			all.append({"task": item["task"], "child_of": item.get("child_of", ""), "section": s})
	var per_page := _rows(false) * columns
	for from in range(0, maxi(all.size(), 1), per_page):
		var items := all.slice(from, from + per_page)
		_leaves.append({"section": items[0]["section"] if not items.is_empty() else 0, "items": items})


func page_count() -> int:
	return _leaves.size()


## Blättert um `by` Seiten weiter oder zurück.
func turn(by: int) -> void:
	_picked = -1
	open_page(_pages.get(_key, 0) + by)


## Schlägt die Seite auf. Vorwärts hebt sich die alte Seite am freien Rand und
## schwenkt um die Ordnermitte weg; rückwärts schwenkt die neue herein.
func open_page(to: int) -> void:
	to = clampi(to, 0, page_count() - 1)
	var from: int = _pages.get(_key, 0)
	if _flipping or to == from:
		return
	_flipping = true
	_pages[_key] = to

	var old := _sheet
	_sheet = _make_sheet(to)
	var forward := to > from
	# Die Seite, die sich bewegt, liegt oben; darunter die andere, dazwischen der Schatten.
	var moving := old if forward else _sheet
	_sheets.add_child(_sheet)
	if forward:
		_sheets.move_child(_sheet, 0)
	var wide := _sheets.size.x

	var cast := TextureRect.new()
	cast.texture = _cast
	cast.stretch_mode = TextureRect.STRETCH_SCALE
	cast.flip_h = left_side
	cast.size = Vector2(110.0, _sheets.size.y)
	cast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sheets.add_child(cast)
	_sheets.move_child(cast, 1)

	var shade := TextureRect.new()
	shade.texture = _shade
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.flip_h = left_side
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	moving.add_child(shade)
	# Gedreht wird um den Rand zur Ordnermitte.
	moving.pivot_offset = Vector2(wide if left_side else 0.0, moving.size.y / 2.0)

	# Aufgerichtet ist die Seite nur noch eine Kante, etwas höher, weil näher, und im
	# Schatten. Der geworfene Schatten liegt jenseits ihres freien Rands.
	var flat := {"scale": Vector2.ONE, "shade": 0.0, "cast": -110.0 if left_side else wide, "cast_a": 0.0}
	var upright := {"scale": Vector2(0.0, 1.07), "shade": 1.0, "cast": wide - 110.0 if left_side else 0.0, "cast_a": 1.0}
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
		old.queue_free()
		cast.queue_free()
		if is_instance_valid(shade):
			shade.queue_free()
		_flipping = false)
	_show_place()


# -------------------------------------------------------------- Aufbau

## Die Registerblätter am äußeren Rand: je Abschnitt eines, in eigener Farbe,
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
			if left_side:
				box.border_width_left = 1
				box.corner_radius_top_left = 9
				box.corner_radius_bottom_left = 9
				box.content_margin_left = 10.0
				box.content_margin_right = 18.0
			else:
				box.border_width_right = 1
				box.corner_radius_top_right = 9
				box.corner_radius_bottom_right = 9
				box.content_margin_left = 20.0
				box.content_margin_right = 8.0
			tab.add_theme_stylebox_override(state, box)
		tab.tooltip_text = section.get("tip", "Zu „%s“ blättern" % section["title"])
		tab.pressed.connect(_pick.bind(s))
		tab.position.y = 16.0 + s * step
		tab.size = Vector2(tab_out + 8.0, minf(TAB_HEIGHT, step - 2.0))
		_tabs.add_child(tab)


## Ein Registerblatt wurde angeklickt: zur ersten Seite des Abschnitts
## blättern – oder, liegt er schon aufgeschlagen da, seine Fächer aufleuchten
## lassen.
func _pick(section: int) -> void:
	_picked = section
	for i in _leaves.size():
		if _leaves[i]["section"] == section or _leaves[i]["items"].any(func(item: Dictionary) -> bool: return item["section"] == section):
			open_page(i)
			break
	_show_place()
	if _glow_tween != null:
		_glow_tween.kill()
	_glow = 1.0
	_glow_tween = create_tween()
	_glow_tween.tween_interval(FLIP_SECONDS if _flipping else 0.01)
	_glow_tween.tween_property(self, "_glow", 0.0, 1.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _set_glow(value: float) -> void:
	_glow = value
	if is_instance_valid(_sheet):
		_sheet.queue_redraw()


## Eine Seite des Ordners: das Blatt mit seinen Fächern und den Karten darin.
func _make_sheet(page: int) -> Control:
	var sheet := Control.new()
	sheet.size = _sheets.size
	sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	var leaf: Dictionary = _leaves[page]
	var header: Dictionary = _sections[leaf["section"]].get("header", {}) if break_pages and not _sections.is_empty() else {}
	var top := PAD + (HEADER if not header.is_empty() else 0.0)
	var rows := _rows(not header.is_empty())
	# Was in der Höhe übrig bleibt, verteilt sich über und unter den Fächern.
	var spare := maxf(sheet.size.y - top - PAD - rows * POCKET.y - (rows - 1) * GAP, 0.0) / 2.0
	var left := PAD if left_side else INNER
	var items: Array = leaf["items"]
	var pockets := []
	for k in rows * columns:
		var rect := Rect2(Vector2(left + (k % columns) * (POCKET.x + GAP), top + spare + (k / columns) * (POCKET.y + GAP)), POCKET)
		var pocket := {"rect": rect, "caption": "", "color": Palette.MUTED, "section": -1}
		if k < items.size():
			var item: Dictionary = items[k]
			pocket["section"] = item["section"]
			if item["child_of"] != "":
				pocket["caption"] = "↳ " + item["child_of"]
				pocket["color"] = Palette.ACCENT
			elif not break_pages and (k == 0 or item["section"] != items[k - 1]["section"] or items[k - 1]["child_of"] != ""):
				pocket["caption"] = _sections[item["section"]]["title"]
			var card: Control = card_maker.call(item["task"])
			card.position = rect.position + Vector2((POCKET.x - Card.SIZE.x) / 2.0, CAPTION + 6.0)
			sheet.add_child(card)
		pockets.append(pocket)
	if not header.is_empty():
		# Die Kopfzeile ist ein Knopf über die Breite der Fächer.
		var open := Button.new()
		open.flat = true
		open.focus_mode = Control.FOCUS_NONE
		open.mouse_filter = Control.MOUSE_FILTER_PASS
		open.tooltip_text = header.get("tip", "")
		open.position = Vector2(left, PAD - 4.0)
		open.size = Vector2(columns * POCKET.x + (columns - 1) * GAP, HEADER - 4.0)
		open.pressed.connect(func() -> void: header_pressed.emit(header["id"]))
		sheet.add_child(open)
	sheet.draw.connect(_draw_sheet.bind(sheet, pockets, header, left))
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
	# Hervorgehoben ist der Abschnitt, mit dem die Seite beginnt – oder der
	# zuletzt angeklickte, solange Karten von ihm auf der Seite liegen.
	var current: int = _leaves[page]["section"]
	if _picked >= 0 and _leaves[page]["items"].any(func(item: Dictionary) -> bool: return item["section"] == _picked):
		current = _picked
	var rest := 6.0 if left_side else sheet_width(columns) - 14.0
	var n := 0
	for tab in _tabs.get_children():
		if tab.is_queued_for_deletion():
			continue
		tab.set_pressed_no_signal(n == current)
		# Das Blatt des aufgeschlagenen Abschnitts steht etwas weiter heraus.
		tab.position.x = rest + ((-6.0 if left_side else 6.0) if n == current else 0.0)
		n += 1


# ------------------------------------------------------------ Zeichnen

## Das Blatt und seine Fächer: eine Hülle je Platz, darüber der Name des
## Abschnitts, wo einer beginnt.
func _draw_sheet(sheet: Control, pockets: Array, header: Dictionary, left: float) -> void:
	var paper := StyleBoxFlat.new()
	paper.bg_color = PAGE
	paper.border_color = Palette.LINE_STRONG
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(8)
	sheet.draw_style_box(paper, Rect2(1.0, 4.0, sheet.size.x - 2.0, sheet.size.y - 8.0))
	# Die Löcher für die Ringe, am Rand zur Ordnermitte.
	for y in ring_heights(size.y):
		sheet.draw_circle(Vector2(sheet.size.x - 14.0 if left_side else 14.0, y), 5.0, HOLE)

	var font := sheet.get_theme_default_font()
	if not header.is_empty():
		var wide := columns * POCKET.x + (columns - 1) * GAP
		var accent: Color = header.get("accent", Palette.INK)
		sheet.draw_string(Palette.title_font(), Vector2(left + 4.0, PAD + 16.0), header["title"], HORIZONTAL_ALIGNMENT_LEFT, wide - 8.0, 16, accent)
		sheet.draw_string(font, Vector2(left + 4.0, PAD + 36.0), header["line"], HORIZONTAL_ALIGNMENT_LEFT, wide - 8.0, 12, Palette.P1 if header.get("late", false) else Palette.MUTED)
		sheet.draw_rect(Rect2(left + 4.0, PAD + 44.0, wide - 8.0, 5.0), Color(1, 1, 1, 0.08))
		sheet.draw_rect(Rect2(left + 4.0, PAD + 44.0, (wide - 8.0) * clampf(header.get("pct", 0) / 100.0, 0.0, 1.0), 5.0), Palette.ACCENT)

	var sleeve := StyleBoxFlat.new()
	sleeve.bg_color = SLEEVE
	sleeve.border_color = Color(1, 1, 1, 0.07)
	sleeve.set_border_width_all(1)
	sleeve.set_corner_radius_all(8)
	for pocket in pockets:
		var rect: Rect2 = pocket["rect"]
		sheet.draw_style_box(sleeve, rect)
		if _glow > 0.0 and pocket["section"] == _picked and sheet == _sheet:
			sheet.draw_rect(rect.grow(1.0), Color(Palette.ACCENT, _glow), false, 2.5)
			sheet.draw_rect(rect, Color(Palette.ACCENT, _glow * 0.12))
		if pocket["caption"] != "":
			sheet.draw_string(font, rect.position + Vector2(8.0, 15.0), pocket["caption"], HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 14.0, 11, pocket["color"])


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
