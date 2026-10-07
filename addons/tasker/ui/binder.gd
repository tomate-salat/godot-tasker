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
## ohne `pct` gibt es keinen Fortschrittsbalken, ohne `id` keinen Klick. Mit
## `drop: false` nimmt der Abschnitt keine Karten an. Mit `hide_if_empty`
## hat er, solange er leer ist, weder Seite noch Registerblatt – beides
## erscheint nur, während eine Karte gezogen wird.
##
## Karten lassen sich ablegen: in ein Fach (die Karte landet
## an diesem Platz), auf ein Registerblatt (ans Ende des Abschnitts), auch in den
## anderen Ordner. Gezogen wird in der Planung; der Ordner zeigt nur das Ziel.

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
## So blass ist das Abbild einer gezogenen Karte in ihrem Fach.
const GHOST := 0.28
## So schnell rücken die Karten zur Seite, wenn eine dazwischen soll.
const SHIFT_SECONDS := 0.14

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
## Was über der Seite steht, wenn kein Abschnitt etwas zu zeigen hat.
var empty_title := "Hier steckt nichts"

var _sections: Array = []
## Die Seiten: je `{ section, items }` – `items` mit `{ task, child_of }`.
var _leaves: Array = []
## Welcher Ordner gezeigt wird, und je Ordner die aufgeschlagene Seite.
var _key := ""
var _pages := {}
var _flipping := false
var _flip: Tween
## Das Fach, vor dem eine gezogene Karte landen würde (-1: keins), und das
## Registerblatt, auf dem sie schwebt.
var _drop_pocket := -1
var _drop_tab := -1
## Die Karte, die gerade über dem Ordner schwebt, und die, von der im Fach nur
## ein blasses Abbild liegt.
var _dragged := ""
var _ghost_id := ""
## Solange eine Karte gezogen wird, zeigen sich auch die Registerblätter
## leerer Abschnitte, damit man etwas hineinlegen kann.
var _show_empty := false

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
var _landing: StyleBoxFlat


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

	# So sieht das Fach aus, in dem eine gezogene Karte landen würde.
	_landing = StyleBoxFlat.new()
	_landing.bg_color = Color(Palette.ACCENT, 0.14)
	_landing.border_color = Color(Palette.ACCENT, 0.85)
	_landing.set_border_width_all(2)
	_landing.set_corner_radius_all(8)
	_landing.shadow_color = Color(Palette.ACCENT, 0.22)
	_landing.shadow_size = 7


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
		# Ein leerer Abschnitt hat seine Seite – außer er versteckt sich, solange er leer ist.
		if _hidden(s):
			continue
		for from in range(0, maxi(items.size(), 1), per_page):
			_leaves.append({"section": s, "items": items.slice(from, from + per_page)})
	if _leaves.is_empty():
		# Nichts zu zeigen: eine leere Seite, die zu keinem Abschnitt gehört.
		_leaves.append({"section": -1, "items": []})


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
	# Eine Lücke für eine schwebende Karte gehört zur alten Seite.
	_drop_pocket = -1
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
		_tabs.add_child(tab)
	_place_tabs(false)


## Ob der Abschnitt gerade weder Seite noch Registerblatt hat: leer und zum
## Verstecken bestimmt – außer es wird eine Karte gezogen.
func _hidden(section: int) -> bool:
	return not _show_empty and _sections[section].get("hide_if_empty", false) and _sections[section]["items"].is_empty()


## Reiht die Registerblätter am Rand auf. Versteckte fehlen – außer es wird
## gerade eine Karte gezogen: dann schieben sie sich dazwischen.
func _place_tabs(animated: bool) -> void:
	var tabs := _tabs.get_children().filter(func(t: Node) -> bool: return not t.is_queued_for_deletion())
	var shown := []
	for s in tabs.size():
		if not _hidden(s):
			shown.append(s)
	# Viele Abschnitte rücken zusammen, damit alle Blätter an den Rand passen.
	var step := minf(TAB_HEIGHT + 4.0, (size.y - FOOT - 24.0) / maxf(shown.size(), 1))
	for s in tabs.size():
		var tab: Control = tabs[s]
		var at := shown.find(s)
		var y := 16.0 + maxi(at, 0) * step
		tab.size = Vector2(tab_out + 8.0, minf(TAB_HEIGHT, step - 2.0))
		if tab.has_meta("slide"):
			var running: Tween = tab.get_meta("slide")
			if running != null and running.is_valid():
				running.kill()
		if not animated:
			tab.visible = at >= 0
			tab.position.y = y
			tab.modulate.a = 1.0
			continue
		# Ein neues Blatt blendet an seinem Platz ein, die anderen rücken.
		if at >= 0 and not tab.visible:
			tab.visible = true
			tab.position.y = y
			tab.modulate.a = 0.0
		var slide: Tween = tab.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		slide.tween_property(tab, "position:y", y, 0.16)
		slide.tween_property(tab, "modulate:a", 1.0 if at >= 0 else 0.0, 0.16)
		if at < 0:
			slide.chain().tween_callback(func() -> void: tab.visible = false)
		tab.set_meta("slide", slide)


## Eine Karte wird gezogen (oder nicht mehr): solange zeigen sich auch die
## Registerblätter leerer Abschnitte.
func set_dragging(on: bool) -> void:
	if on == _show_empty:
		return
	_show_empty = on
	_repaginate()
	_place_tabs(true)


## Teilt die Seiten neu ein, ohne umzublättern: beim Ziehen kommen die Seiten
## leerer Abschnitte dazu, danach fallen sie wieder weg.
func _repaginate() -> void:
	var page: int = _pages.get(_key, 0)
	var section: int = _leaves[page]["section"] if page < _leaves.size() else -1
	# Die wievielte Seite ihres Abschnitts aufgeschlagen ist.
	var nth := 0
	for i in mini(page, _leaves.size()):
		if _leaves[i]["section"] == section:
			nth += 1
	_paginate()
	var to := -1
	var seen := 0
	for i in _leaves.size():
		if _leaves[i]["section"] == section:
			if seen == nth:
				to = i
				break
			seen += 1
	if to >= 0:
		_pages[_key] = to
	else:
		# Die aufgeschlagene Seite gibt es nicht mehr – sie gehörte zu einem
		# leeren Abschnitt. Dann liegt die nächstgelegene da.
		_pages[_key] = clampi(page, 0, _leaves.size() - 1)
		for c in _sheets.get_children():
			c.queue_free()
		_sheet = _make_sheet(_pages[_key])
		_sheets.add_child(_sheet)
	_show_place()


## Blättert zur ersten Seite dieses Abschnitts.
func reveal_section(section: int) -> void:
	for i in _leaves.size():
		if _leaves[i]["section"] == section:
			open_page(i)
			break
	_show_place()


## Eine Seite des Ordners: das Blatt mit Kopfzeile, Fächern und den Karten darin.
func _make_sheet(page: int) -> Control:
	var sheet := Control.new()
	sheet.size = _sheets.size
	sheet.mouse_filter = Control.MOUSE_FILTER_PASS
	var leaf: Dictionary = _leaves[page]
	var header: Dictionary = _sections[leaf["section"]].get("header", {}) if leaf["section"] >= 0 else {"title": empty_title, "line": ""}
	var top := PAD + HEADER
	var rows := _rows()
	# Was in der Höhe übrig bleibt, verteilt sich über und unter den Fächern.
	var spare := maxf(sheet.size.y - top - PAD - rows * POCKET.y - (rows - 1) * GAP, 0.0) / 2.0
	var items: Array = leaf["items"]
	var pockets := []
	var cards := []
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
			card.set_meta("task", item["task"]["id"])
			# Erledigte Karten sind von sich aus blass – das soll beim Rücken so bleiben.
			card.set_meta("alpha", card.modulate.a)
			if item["task"]["id"] == _ghost_id:
				card.modulate.a *= GHOST
			cards.append(card)
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
	sheet.set_meta("pockets", pockets)
	sheet.set_meta("cards", cards)
	sheet.set_meta("page", page)
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
		tab.position.x = rest + (6.0 if n == current or n == _drop_tab else 0.0)
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
		# Hier würde die gezogene Karte landen: das Fach leuchtet.
		if sheet == _sheet and _drop_pocket >= 0 and pockets[_drop_pocket] == pocket:
			sheet.draw_style_box(_landing, rect)
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


# ------------------------------------------------------------- Ablegen
#
# Gezogen wird in der Planung (`plan_view.gd`), über beide Ordner hinweg. Der
# Ordner sagt nur, was unter der schwebenden Karte liegt, macht dort Platz
# und nennt am Ende das Ziel.

## Das Fach an dieser Stelle der aufgeschlagenen Seite – das nächstgelegene,
## wenn sie zwischen zweien liegt.
func _pocket_at(at: Vector2) -> int:
	var pockets: Array = _sheet.get_meta("pockets", [])
	var best := -1
	var near := INF
	for k in pockets.size():
		var rect: Rect2 = pockets[k]["rect"]
		if rect.has_point(at):
			return k
		var far := rect.get_center().distance_squared_to(at)
		if far < near:
			near = far
			best = k
	return best


## Eine gezogene Karte schwebt an dieser Stelle des Fensters. Zeigt, wo sie
## landen würde – vor einem Fach oder auf einem Registerblatt –, und macht
## dort Platz. Wahr, wenn sie in diesem Ordner landen könnte.
func hover(at: Vector2, task_id: String) -> bool:
	var tab := -1
	var pocket := -1
	if not _flipping and is_instance_valid(_sheet):
		var n := 0
		for t in _tabs.get_children():
			if t.is_queued_for_deletion():
				continue
			if t.visible and t.get_global_rect().has_point(at) and _sections[n].get("drop", true):
				tab = n
			n += 1
		var local: Vector2 = _sheets.get_global_transform().affine_inverse() * at
		var section: int = _leaves[_pages.get(_key, 0)]["section"]
		if tab < 0 and section >= 0 and Rect2(Vector2.ZERO, _sheets.size).has_point(local) and _sections[section].get("drop", true):
			# Weiter hinten als hinter die letzte Karte der Seite geht es nicht.
			pocket = mini(_pocket_at(local), _others(task_id).size())
	_dragged = task_id
	if tab != _drop_tab or pocket != _drop_pocket:
		_drop_tab = tab
		_drop_pocket = pocket
		_make_room(pocket, task_id)
		_sheet.queue_redraw()
		_show_place()
	return tab >= 0 or pocket >= 0


## Die Karte schwebt nicht mehr hier: alles rückt zurück.
func end_hover() -> void:
	if _drop_pocket == -1 and _drop_tab == -1:
		return
	_drop_pocket = -1
	_drop_tab = -1
	_make_room(-1, _dragged)
	if is_instance_valid(_sheet):
		_sheet.queue_redraw()
	_show_place()


## Wohin die schwebende Karte fiele: leer, oder `{ section, before, at, into_tab }`.
## `before` ist die Karte, vor der sie landet (leer: ans Ende), `at` die Stelle
## im Fenster, an die sie dafür fliegt.
func drop_target() -> Dictionary:
	if _drop_tab >= 0:
		var n := 0
		for t in _tabs.get_children():
			if t.is_queued_for_deletion():
				continue
			if n == _drop_tab:
				return {"section": _drop_tab, "before": "", "at": t.get_global_rect().get_center(), "into_tab": true}
			n += 1
	if _drop_pocket < 0 or not is_instance_valid(_sheet):
		return {}
	var page: int = _pages.get(_key, 0)
	var leaf: Dictionary = _leaves[page]
	# Das Fach ist der Platz, den die Karte einnimmt: sie landet vor der Karte,
	# die – ohne sie selbst gezählt – dort liegt. Liegt dort keine, kommt sie
	# hinter die letzte dieser Seite, also vor die erste der nächsten, wenn der
	# Abschnitt dort weitergeht.
	var others := _others(_dragged)
	var before := ""
	if _drop_pocket < others.size():
		before = others[_drop_pocket]
	elif page + 1 < _leaves.size() and _leaves[page + 1]["section"] == leaf["section"] and not _leaves[page + 1]["items"].is_empty():
		before = _leaves[page + 1]["items"][0]["task"]["id"]
	var pockets: Array = _sheet.get_meta("pockets", [])
	var slot := mini(_drop_pocket, pockets.size() - 1)
	return {"section": leaf["section"], "before": before, "at": _sheets.get_global_transform() * _home(pockets[slot]["rect"]), "into_tab": false}


## Die Karten der aufgeschlagenen Seite ohne die gezogene, als IDs in Reihenfolge.
func _others(moved_id: String) -> Array:
	var out := []
	for item in _leaves[_pages.get(_key, 0)]["items"]:
		if item["task"]["id"] != moved_id:
			out.append(item["task"]["id"])
	return out


## Wo die Karte dieser Aufgabe auf der aufgeschlagenen Seite liegt, im Fenster
## gemessen – null, wenn sie dort nicht steckt.
func place_of(task_id: String) -> Variant:
	var card := _card_of(task_id)
	if card == null:
		return null
	var pockets: Array = _sheet.get_meta("pockets", [])
	var k: int = _sheet.get_meta("cards", []).find(card)
	return _sheets.get_global_transform() * _home(pockets[k]["rect"])


## Lässt von der gezogenen Karte ein blasses Abbild im Fach – oder holt sie zurück.
func ghost(task_id: String, on: bool) -> void:
	_ghost_id = task_id if on else ""
	var card := _card_of(task_id)
	if card != null:
		var own: float = card.get_meta("alpha", 1.0)
		card.create_tween().tween_property(card, "modulate:a", GHOST * own if on else own, 0.12)


## Lässt die Karte dieser Aufgabe in ihrem Fach ankommen: sie setzt sich mit
## einem kleinen Nachfedern.
func land(task_id: String) -> void:
	var card := _card_of(task_id)
	if card != null:
		card.create_tween().tween_property(card, "scale", Vector2.ONE, 0.3).from(Vector2(1.08, 1.08)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Ein Zug ging nicht: die Karte gleitet von dort, wo sie abgelegt wurde,
## zurück in ihr Fach.
func slide_back(task_id: String, from: Vector2) -> void:
	var card := _card_of(task_id)
	if card == null:
		return
	var home := card.position
	card.z_index = 20
	var back: Tween = card.create_tween()
	back.tween_property(card, "position", home, 0.36).from(_sheets.get_global_transform().affine_inverse() * from).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	back.tween_callback(func() -> void: card.z_index = 0)


func _card_of(task_id: String) -> Control:
	if is_instance_valid(_sheet):
		for card in _sheet.get_meta("cards", []):
			if is_instance_valid(card) and card.get_meta("task") == task_id:
				return card
	return null


## Wo die Karte in einem Fach sitzt.
static func _home(pocket: Rect2) -> Vector2:
	return pocket.position + Vector2((POCKET.x - Card.SIZE.x) / 2.0, CAPTION + 6.0)


## Rückt die Karten der Seite so, dass vor dem Fach `gap` Platz für die
## gezogene Karte ist (-1: alle zurück an ihren Platz). Steckt die gezogene
## selbst auf der Seite, schließt sich ihre Lücke.
func _make_room(gap: int, moved_id: String) -> void:
	if not is_instance_valid(_sheet):
		return
	var pockets: Array = _sheet.get_meta("pockets", [])
	var cards: Array = _sheet.get_meta("cards", [])
	# Wie viele andere Karten vor der gerade betrachteten liegen.
	var ahead := 0
	for k in cards.size():
		var card: Control = cards[k]
		if not is_instance_valid(card):
			continue
		var at := k
		var own: float = card.get_meta("alpha", 1.0)
		var seen := own
		if card.get_meta("task") == _ghost_id:
			# Die gezogene Karte liegt am Zeiger; rücken die anderen, weicht ihr Abbild.
			seen = 0.0 if gap >= 0 else GHOST * own
		elif gap >= 0:
			# Alles ab dem Fach rückt um einen Platz weiter.
			at = ahead + (1 if ahead >= gap else 0)
			ahead += 1
			# Was hinten nicht mehr auf die Seite passt, rückt auf die nächste.
			if at >= pockets.size():
				at = pockets.size() - 1
				seen = 0.0
		if card.has_meta("shift"):
			var running: Tween = card.get_meta("shift")
			if running != null and running.is_valid():
				running.kill()
		var shift: Tween = card.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		shift.tween_property(card, "position", _home(pockets[at]["rect"]), SHIFT_SECONDS)
		shift.tween_property(card, "modulate:a", seen, SHIFT_SECONDS)
		card.set_meta("shift", shift)


## Das Ziehen ist vorbei: kein Abbild und keine Marke mehr, auch nicht auf
## Seiten, die erst noch aufgeschlagen werden.
func clear_drag() -> void:
	set_dragging(false)
	var ghost_id := _ghost_id
	_ghost_id = ""
	_dragged = ""
	_drop_pocket = -1
	_drop_tab = -1
	var card := _card_of(ghost_id) if ghost_id != "" else null
	if card != null:
		card.modulate.a = card.get_meta("alpha", 1.0)
	if is_instance_valid(_sheet):
		_sheet.queue_redraw()
	_show_place()
