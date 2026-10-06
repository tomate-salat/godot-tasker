@tool
extends RefCounted
## Farben und Schriften der Karten – die dunkle Palette aus Taskers
## `styles.css`, damit die Karten in Godot aussehen wie dort.

const SURFACE := Color("181d1b")
const INK := Color("e3e8e4")
const MUTED := Color("9ba49f")
const FAINT := Color("687170")
const LINE := Color("28302d")
const LINE_STRONG := Color("3c4643")
const ACCENT := Color("63b69d")
const P1 := Color("e57a66")
const P2 := Color("e6ae58")
const P3 := Color("8c9590")
const OK := Color("6cc08c")
const INFO := Color("6fa8dc")
const UNCLEAR := Color("ae9be0")
## Der Filz des Tischs.
const FELT := Color("1f3a31")

static var _title_font: Font
static var _body_font: Font


static func status_color(status: Variant) -> Color:
	match status:
		"progress":
			return INFO
		"done":
			return OK
		"blocked":
			return P1
		"unclear":
			return UNCLEAR
	return MUTED


static func prio_color(prio: int) -> Color:
	match prio:
		1:
			return P1
		2:
			return P2
		3:
			return P3
	return FAINT


## Der Fuß einer Karte trägt die Farbe des Status; „Offen“ bleibt neutral.
static func foot_color(status: Variant) -> Color:
	match status:
		"progress":
			return SURFACE.lerp(INFO, 0.22)
		"done":
			return SURFACE.lerp(OK, 0.22)
		"blocked":
			return SURFACE.lerp(P1, 0.18)
		"unclear":
			return SURFACE.lerp(UNCLEAR, 0.20)
	return Color(SURFACE, 0.75)


static func foot_line(status: Variant) -> Color:
	match status:
		"progress":
			return LINE.lerp(INFO, 0.45)
		"done":
			return LINE.lerp(OK, 0.45)
		"blocked":
			return LINE.lerp(P1, 0.40)
		"unclear":
			return LINE.lerp(UNCLEAR, 0.45)
	return LINE


static func title_font() -> Font:
	if _title_font == null:
		_title_font = _system_font(["Bricolage Grotesque", "Segoe UI", "Helvetica Neue", "Noto Sans"], 650)
	return _title_font


static func body_font() -> Font:
	if _body_font == null:
		_body_font = _system_font(["IBM Plex Sans", "Segoe UI", "Helvetica Neue", "Noto Sans"], 500)
	return _body_font


static func _system_font(names: Array, weight: int) -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(names)
	font.font_weight = weight
	# Markierungen sind Emojis und stehen vor dem Titel.
	var emoji := SystemFont.new()
	emoji.font_names = PackedStringArray(["Segoe UI Emoji", "Apple Color Emoji", "Noto Color Emoji"])
	font.fallbacks = [emoji]
	return font


static var _status_icons := {}

const STATUS_LABELS := {
	"open": "Offen",
	"progress": "In Progress",
	"done": "Erledigt",
	"unclear": "Unklar",
	"blocked": "Blockiert",
}
const PRIO_LABELS := ["Keine", "Hoch", "Mittel", "Niedrig"]


## Der Statuspunkt als kleines Bild, für Listen und Menüs.
static func status_icon(status: Variant) -> Texture2D:
	if _status_icons.has(status):
		return _status_icons[status]
	var size := 14
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var color := status_color(status)
	var center := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(center)
			var alpha := clampf(5.5 - d, 0.0, 1.0)
			# „Offen“ ist nur ein Ring.
			if status == "open":
				alpha *= clampf(d - 3.2, 0.0, 1.0)
			image.set_pixel(x, y, Color(color, alpha))
	var texture := ImageTexture.create_from_image(image)
	_status_icons[status] = texture
	return texture
