@tool
extends Control
## Eine Aufgabe als Karte – dieselbe im Dock, in der Suche und am Tisch.
##
## Nachgebaut nach `CardFace` in Taskers `Cards.tsx` und `cards.css`:
## Titelbild füllt die Karte, der Titel liegt oben darauf, der Fuß trägt die
## Farbe des Status. Eine Aufgabe mit Unteraufgaben ist ein Stapel und zeigt
## zwei Kartenkanten dahinter.

const Model := preload("../rules/model.gd")
const Checklist := preload("../rules/checklist.gd")
const Progress := preload("../rules/progress.gd")
const Blocking := preload("../rules/blocking.gd")
const Inherit := preload("../rules/inherit.gd")
const Workspace := preload("../rules/workspace.gd")
const Palette := preload("palette.gd")

const SIZE := Vector2(128, 176)
const RADIUS := 11
const TITLE_SIZE := 14
const NBSP := " "

## Ein Mausklick auf die Karte, mit dem Ereignis (Taste, Doppelklick).
signal pressed(card: Control, event: InputEventMouseButton)

var task_id := ""
## Hervorgehoben: die Karte, deren Einzelheiten gerade offen sind.
var selected := false: set = set_selected
## Wie weit die Karte vom Tisch abgehoben ist, 0 bis 1 – bestimmt ihren Schatten.
var lift := 0.0: set = set_lift

var _status: Variant = "open"
var _prio := 0
var _stack := false
var _locked := false
var _segments: Array = []

var _body: Panel
var _face: StyleBoxFlat
var _cover: TextureRect
var _shade: TextureRect
var _foil: ColorRect
var _is_foil := false
var _crumb: Label
var _title: Label
## Die Markierung steht vor dem Titel, aber ohne dessen Kontur – die steht einem Emoji nicht.
var _mark: Label
var _foot: PanelContainer
var _dot: Control
var _prio_icon: Control
var _lock: Control
var _count: Label
var _bar: Control


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	pivot_offset = SIZE / 2.0
	_build()


## Zeigt `task`. Mit `crumb` steht über dem Titel, zu welchen Eltern-Tasks
## eine Unteraufgabe gehört. `images` ist der Bild-Zwischenspeicher
## (`core/images.gd`) – ohne ihn bleibt die Karte ohne Titelbild.
func show_task(ws: Workspace, task: Dictionary, images: Node = null, crumb := false) -> void:
	task_id = task["id"]
	var doc := ws.is_doc(task)
	var kids := ws.kids(task_id)
	var counted := ws.counted_kids(task_id).size()
	var cl := Checklist.count(task.get("desc"))
	var done := Model.is_done(task)

	_status = null if doc else task.get("status")
	_prio = int(task.get("prio", 0))
	_stack = kids.size() > 0
	_locked = not doc and not done and Blocking.is_blocked(ws, task)
	_segments = [] if doc else _sorted(Progress.status_segments(ws, task))

	var mark = ws.mark(task.get("markId"))
	var title: String = task.get("title", "")
	_mark.visible = mark != null
	var indent := ""
	if mark != null:
		# Der Titel rückt um die Breite des Zeichens ein und bricht danach normal um.
		_mark.text = mark["emoji"]
		var font := Palette.title_font()
		var wide := font.get_string_size(mark["emoji"] + " ", HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
		var space := font.get_string_size(NBSP, HORIZONTAL_ALIGNMENT_LEFT, -1, TITLE_SIZE).x
		indent = NBSP.repeat(ceili(wide / maxf(space, 1.0)))
	_title.text = indent + (title if title != "" else "Ohne Titel")

	var up := ws.ancestors(task)
	_crumb.visible = crumb and up.size() > 0
	if _crumb.visible:
		_crumb.text = " › ".join(up.map(func(a: Dictionary) -> String: return a["title"] if a.get("title") else "Ohne Titel")) + " ›"

	# Mit Unteraufgaben zählt die Checkliste im Zähler mit – zwei Zähler
	# nebeneinander sprengen die Karte.
	if doc:
		_count.text = str(kids.size()) if kids.size() > 0 else ""
	elif counted > 0:
		_count.text = "%d/%d" % [Progress.done_count(ws, task) + cl["done"], Progress.total(ws, task) + cl["total"]]
	elif cl["total"] > 0:
		_count.text = "%d/%d" % [cl["done"], cl["total"]]
	else:
		_count.text = ""

	_dot.visible = not doc
	_prio_icon.visible = not doc
	_lock.visible = _locked
	_is_foil = _prio == 1 and not done and not doc
	_bar.visible = _segments.size() > 0
	modulate.a = 0.55 if done else 1.0

	var foot := StyleBoxFlat.new()
	foot.bg_color = Palette.foot_color(_status)
	foot.border_color = Palette.foot_line(_status)
	foot.border_width_top = 1
	foot.content_margin_left = 10
	foot.content_margin_right = 10
	foot.content_margin_top = 8
	foot.content_margin_bottom = 10
	_foot.add_theme_stylebox_override("panel", foot)

	_set_cover(null)
	for c in [_dot, _prio_icon, _lock, _bar, self]:
		c.queue_redraw()
	_layout_title()

	var cover = Inherit.effective_cover(ws, task)
	if cover != null and images != null:
		var id := task_id
		var texture: Texture2D = await images.get_texture(cover["image_id"], true)
		# Inzwischen kann die Karte eine andere Aufgabe zeigen oder weg sein.
		if is_instance_valid(self) and task_id == id:
			_set_cover(texture)


func _set_cover(texture: Texture2D) -> void:
	_cover.texture = texture
	_cover.visible = texture != null
	_shade.visible = texture != null
	# Auf dem Bild: weißer Titel mit schwarzer Kontur, damit er auf jedem Bild lesbar bleibt.
	_title.add_theme_color_override("font_color", Color.WHITE if texture != null else Palette.INK)
	_title.add_theme_constant_override("outline_size", 6 if texture != null else 0)
	_crumb.add_theme_color_override("font_color", Color.WHITE if texture != null else Palette.MUTED)
	_mark.add_theme_color_override("font_color", Color.WHITE if texture != null else Palette.INK)


func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP

	_body = Panel.new()
	_body.set_anchors_preset(Control.PRESET_FULL_RECT)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Das Titelbild und der Fuß enden an den runden Ecken der Karte.
	_body.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	_face = StyleBoxFlat.new()
	_face.bg_color = Palette.SURFACE
	_face.border_color = Palette.LINE_STRONG
	_face.set_border_width_all(1)
	_face.set_corner_radius_all(RADIUS)
	_face.anti_aliasing_size = 0.6
	_body.add_theme_stylebox_override("panel", _face)
	add_child(_body)

	_cover = TextureRect.new()
	_cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cover.visible = false
	_body.add_child(_cover)

	_shade = TextureRect.new()
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shade.stretch_mode = TextureRect.STRETCH_SCALE
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shade.texture = _shade_texture()
	_shade.visible = false
	_body.add_child(_shade)

	# Licht und Folien-Schimmer beim Kippen liegen über dem Bild, unter der Schrift.
	_foil = ColorRect.new()
	_foil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_foil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foil.material = ShaderMaterial.new()
	_foil.material.shader = _foil_shader()
	_foil.visible = false
	_body.add_child(_foil)

	_crumb = Label.new()
	_crumb.position = Vector2(12, 6)
	_crumb.size = Vector2(SIZE.x - 24, 15)
	_crumb.clip_text = true
	_crumb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_crumb.add_theme_font_override("font", Palette.body_font())
	_crumb.add_theme_font_size_override("font_size", 11)
	_crumb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crumb.visible = false
	_body.add_child(_crumb)

	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.max_lines_visible = 4
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_title.add_theme_font_override("font", Palette.title_font())
	_title.add_theme_font_size_override("font_size", TITLE_SIZE)
	_title.add_theme_constant_override("line_spacing", -1)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_title)

	_mark = Label.new()
	_mark.add_theme_font_override("font", Palette.title_font())
	_mark.add_theme_font_size_override("font_size", TITLE_SIZE)
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mark.visible = false
	_body.add_child(_mark)

	_foot = PanelContainer.new()
	_foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_foot.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(_foot)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_foot.add_child(rows)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", 7)
	meta.custom_minimum_size.y = 16
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(meta)

	_dot = _icon(Vector2(12, 12), _draw_dot)
	meta.add_child(_dot)
	_prio_icon = _icon(Vector2(14, 12), _draw_prio)
	meta.add_child(_prio_icon)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(gap)

	_lock = _icon(Vector2(11, 12), _draw_lock)
	meta.add_child(_lock)

	_count = Label.new()
	_count.add_theme_font_override("font", Palette.body_font())
	_count.add_theme_font_size_override("font_size", 12)
	_count.add_theme_color_override("font_color", Palette.MUTED)
	_count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.add_child(_count)

	_bar = _icon(Vector2(0, 6), _draw_bar)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	rows.add_child(_bar)

	_layout_title()


func _icon(min_size: Vector2, painter: Callable) -> Control:
	var c := Control.new()
	c.custom_minimum_size = min_size
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(painter)
	return c


func _layout_title() -> void:
	var top := 22.0 if _crumb.visible else 10.0
	_title.position = Vector2(12, top)
	_mark.position = Vector2(12, top)
	_title.size = Vector2(SIZE.x - 24, SIZE.y - top - 44)


## Zwei Kartenkanten hinter der Karte: sie hat Unteraufgaben.
func _draw() -> void:
	# Der Schatten: je höher die Karte angehoben ist, desto weiter fällt er.
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.30)
	shadow.set_corner_radius_all(RADIUS)
	shadow.shadow_color = Color(0, 0, 0, 0.30)
	shadow.shadow_size = int(7.0 + 16.0 * lift)
	shadow.shadow_offset = Vector2(0.0, 3.0 + 11.0 * lift)
	# Ein Stapel wirft den Schatten seiner hintersten Karte.
	draw_style_box(shadow, Rect2(Vector2(5, 5) if _stack else Vector2.ZERO, size))
	if not _stack:
		return
	var edge := StyleBoxFlat.new()
	edge.bg_color = Palette.SURFACE
	edge.border_color = Palette.LINE_STRONG
	edge.set_border_width_all(1)
	edge.set_corner_radius_all(RADIUS)
	var half := size / 2.0
	for e in [[Vector2(6, 6), 2.0], [Vector2(3, 3), -1.0]]:
		draw_set_transform(half + e[0], deg_to_rad(e[1]))
		draw_style_box(edge, Rect2(-half, size))
	draw_set_transform(Vector2.ZERO)


func _draw_dot() -> void:
	var c := _dot.size / 2.0
	var color := Palette.status_color(_status)
	if _status == "open":
		_dot.draw_arc(c, 4.5, 0, TAU, 24, color, 1.5, true)
	else:
		_dot.draw_circle(c, 5.0, color, true, -1.0, true)
		if _status == "done":
			_dot.draw_polyline(PackedVector2Array([c + Vector2(-2.5, 0), c + Vector2(-0.5, 2), c + Vector2(2.5, -2)]), Palette.SURFACE, 1.5, true)


## Drei Balken: hoch = alle drei, mittel = zwei, niedrig = einer, ohne = keiner.
func _draw_prio() -> void:
	var filled := 0 if _prio == 0 else 4 - _prio
	for i in 3:
		var h := 4.0 + i * 3.0
		var rect := Rect2(i * 5.0, _prio_icon.size.y - h - 1.0, 3.0, h)
		_prio_icon.draw_rect(rect, Palette.prio_color(_prio) if i < filled else Color(Palette.INK, 0.14))


func _draw_lock() -> void:
	var color := Palette.P1
	_lock.draw_arc(Vector2(5.5, 5.0), 3.0, PI, TAU, 12, color, 1.5, true)
	_lock.draw_rect(Rect2(1.0, 5.0, 9.0, 6.5), color)


func _draw_bar() -> void:
	var n := _segments.size()
	if n == 0:
		return
	var gap := 2.0 if n <= 30 else 0.0
	var w := (_bar.size.x - gap * (n - 1)) / n
	for i in n:
		var s: Dictionary = _segments[i]
		var color := Color(Palette.INK, 0.12)
		if s["kind"] == "checklist":
			if s["done"]:
				color = Palette.OK
		elif s["status"] != "open":
			color = Palette.status_color(s["status"])
		_bar.draw_rect(Rect2(i * (w + gap), 0.0, maxf(w, 1.0), _bar.size.y), color)


## Erledigtes zuerst, dann was läuft, dann was hängt, zuletzt das Offene.
static func _sorted(segments: Array) -> Array:
	var rank := func(s: Dictionary) -> int:
		if s["kind"] == "checklist":
			return 0 if s["done"] else 4
		match s["status"]:
			"done":
				return 0
			"progress":
				return 1
			"blocked":
				return 2
			"unclear":
				return 3
		return 4
	return Model.stable_sort(segments, func(a: Dictionary, b: Dictionary) -> bool:
		return rank.call(a) < rank.call(b))


## Oben dunkel, damit der Titel auf dem Bild steht, nach unten auslaufend.
static func _shade_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([Color(0, 0, 0, 0.62), Color(0, 0, 0, 0.05), Color(0, 0, 0, 0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill_from = Vector2(0, 0)
	texture.fill_to = Vector2(0, 1)
	texture.width = 4
	texture.height = 64
	return texture


func set_selected(value: bool) -> void:
	selected = value
	_face.border_color = Palette.ACCENT if value else Palette.LINE_STRONG
	_face.set_border_width_all(2 if value else 1)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		pressed.emit(self, event)


func set_lift(value: float) -> void:
	lift = clampf(value, 0.0, 1.0)
	queue_redraw()


## Karten mit hoher Priorität schimmern wie eine Folienkarte, wenn sie kippen.
func has_foil() -> bool:
	return _is_foil


## Wie die Karte gerade gekippt ist: x nach links/rechts, y nach oben/unten,
## je von -1 bis 1. Die zurückweichende Seite wird dunkler, die nahe heller –
## und über Folienkarten wandert dabei der Lichtstreifen.
func set_tilt(tilt: Vector2) -> void:
	var resting := tilt.length() < 0.01
	_foil.visible = not resting
	if resting:
		return
	_foil.material.set_shader_parameter("tilt", tilt)
	_foil.material.set_shader_parameter("foil", 1.0 if _is_foil else 0.0)


static var _foil_code: Shader


static func _foil_shader() -> Shader:
	if _foil_code == null:
		_foil_code = Shader.new()
		_foil_code.code = "
shader_type canvas_item;

uniform vec2 tilt = vec2(0.0);
uniform float foil = 0.0;

void fragment() {
	// Licht von vorn: die Seite, die sich dem Betrachter zuneigt, wird heller.
	float light = dot(UV - vec2(0.5), tilt) * 1.6;
	vec3 color = light > 0.0 ? vec3(1.0) : vec3(0.0);
	float alpha = light > 0.0 ? light * 0.22 : -light * 0.42;

	// Der Folienstreifen wandert mit der Neigung über die Karte.
	float d = UV.x * 0.62 + UV.y * 0.48;
	float phase = 0.5 + tilt.x * 0.55 + tilt.y * 0.25;
	float band = smoothstep(0.17, 0.0, abs(d - phase * 1.1)) * foil * clamp(length(tilt) * 2.5, 0.0, 1.0);
	vec3 hue = 0.55 + 0.45 * cos(6.2831 * (d * 1.6 + vec3(0.0, 0.33, 0.67)));
	color = mix(color, hue, band);
	alpha = max(alpha, band * 0.5);

	COLOR = vec4(color, alpha);
}
"
	return _foil_code
