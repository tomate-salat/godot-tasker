@tool
extends RefCounted
## Markdown einer Beschreibung zu BBCode für ein `RichTextLabel`.
##
## Godot rendert kein Markdown, und Tasker nutzt dafür im Browser `marked`.
## Hier steht ein kleiner Übersetzer für das, was in Beschreibungen vorkommt:
## Überschriften, Listen, Checklisten, Zitate, Code, Hervorhebungen, Links,
## Bilder aus der Galerie und Verweise wie `$142`. Wie in Tasker bleibt jeder
## Zeilenumbruch einer. Tabellen bleiben als Text stehen.

## Steht im Ergebnis an der Stelle eines Bildes: `IMAGE + id + IMAGE` für ein
## Bild der Galerie, `IMAGE + DRAWING + name + IMAGE` für eine Zeichnung.
## Wer anzeigt, teilt dort auf und setzt das Bild ein.
const IMAGE := "\u0001"
const DRAWING := "zeichnung:"
## Verweise auf Aufgaben werden Links mit diesem Anfang: `tasker:142`.
const REF_SCHEME := "tasker:"

const _HOLD := "\u0002"
const _HEADING_SIZES := [22, 19, 17, 16, 15, 15]
const _MUTED := "#9ba49f"
const _CODE := "#e6ae58"

static var _re := {}


## `resolve_ref` bekommt die Nummer eines Verweises und gibt den Titel des
## Ziels zurück – oder "", wenn es das Ziel nicht (mehr) gibt.
static func to_bbcode(source: Variant, resolve_ref := Callable()) -> String:
	var out := PackedStringArray()
	var fence := ""
	for raw in (source if source is String else "").split("\n"):
		var line: String = raw.trim_suffix("\r")

		var fm := _rx("^\\s*(```|~~~)").search(line)
		if fm:
			if fence == "":
				fence = fm.get_string(1)
			elif fence == fm.get_string(1):
				fence = ""
			continue
		if fence != "":
			out.append("[code][color=%s]%s[/color][/code]" % [_CODE, _escape(line)])
			continue

		out.append(_block(line, resolve_ref))
	return "\n".join(out)


static func _block(line: String, resolve_ref: Callable) -> String:
	if line.strip_edges() == "":
		return ""

	var m := _rx("^ {0,3}(#{1,6})\\s+(.*?)\\s*#*\\s*$").search(line)
	if m:
		return "[font_size=%d][b]%s[/b][/font_size]" % [_HEADING_SIZES[m.get_string(1).length() - 1], _inline(m.get_string(2), resolve_ref)]

	if _rx("^ {0,3}([-*_])( ?\\1){2,}\\s*$").search(line):
		return "[color=%s]────────────[/color]" % _MUTED

	m = _rx("^\\s*>\\s?(.*)$").search(line)
	if m:
		return "[indent][color=%s][i]%s[/i][/color][/indent]" % [_MUTED, _inline(m.get_string(1), resolve_ref)]

	m = _rx("^(\\s*)(?:([-*+])|(\\d+)[.)])\\s+(?:\\[( |x|X)\\]\\s+)?(.*)$").search(line)
	if m:
		var depth := m.get_string(1).replace("\t", "    ").length() / 2
		var bullet := "•"
		if m.get_string(3) != "":
			bullet = m.get_string(3) + "."
		var text := _inline(m.get_string(5), resolve_ref)
		var check := m.get_string(4)
		if check == " ":
			bullet = "☐"
		elif check != "":
			bullet = "☑"
			text = "[color=%s]%s[/color]" % [_MUTED, text]
		return "%s%s %s" % ["    ".repeat(depth), bullet, text]

	return _inline(line, resolve_ref)


static func _inline(text: String, resolve_ref: Callable) -> String:
	var held := []
	var hold := func(bbcode: String) -> String:
		held.append(bbcode)
		return "%s%d%s" % [_HOLD, held.size() - 1, _HOLD]

	# Code zuerst: darin gilt nichts von allem anderen.
	text = _replace(text, "`([^`]+)`", func(m: RegExMatch) -> String:
		return hold.call("[code][color=%s]%s[/color][/code]" % [_CODE, _escape(m.get_string(1))]))

	# Zeichnungen rendert Tasker auf Anfrage als Bild.
	text = _replace(text, "!\\[\\[zeichnung:([^\\]]+)\\]\\]", func(m: RegExMatch) -> String:
		return hold.call(IMAGE + DRAWING + m.get_string(1) + IMAGE))

	text = _replace(text, "!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)", func(m: RegExMatch) -> String:
		var id := _rx("/api/bilder/([^/?#]+)").search(m.get_string(2))
		if id:
			return hold.call(IMAGE + id.get_string(1).uri_decode() + IMAGE)
		return hold.call("[color=%s]▣ %s[/color]" % [_MUTED, _escape(m.get_string(1) if m.get_string(1) != "" else "Bild")]))

	text = _replace(text, "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", func(m: RegExMatch) -> String:
		return hold.call("[url=%s]%s[/url]" % [m.get_string(2), _escape(m.get_string(1))]))

	text = _replace(text, "(?<![\\w/\"=])https?://[^\\s<>\\]]+", func(m: RegExMatch) -> String:
		return hold.call("[url]%s[/url]" % m.get_string(0)))

	text = _escape(text)

	text = _rx("\\*\\*(.+?)\\*\\*").sub(text, "[b]$1[/b]", true)
	text = _rx("__(.+?)__").sub(text, "[b]$1[/b]", true)
	text = _rx("~~(.+?)~~").sub(text, "[s]$1[/s]", true)
	text = _rx("(?<![*\\w])\\*(?!\\s)(.+?)(?<!\\s)\\*(?!\\*)").sub(text, "[i]$1[/i]", true)
	text = _rx("(?<![\\w_])_(?!\\s)(.+?)(?<!\\s)_(?![\\w_])").sub(text, "[i]$1[/i]", true)

	# Verweise: eine Nummer beginnt nie mit 0 und steht nicht mitten in einem
	# Wort, damit `5$` oder `a$1` keine werden – wie in Taskers `shared/refs.ts`.
	text = _replace(text, "(^|[^\\w$])\\$([1-9]\\d*)(?![\\w$])", func(m: RegExMatch) -> String:
		var number := m.get_string(2)
		var title: String = str(resolve_ref.call(int(number))) if resolve_ref.is_valid() else ""
		if title == "":
			return m.get_string(0)
		return "%s[url=%s%s]$%s %s[/url]" % [m.get_string(1), REF_SCHEME, number, number, _escape(title)])

	return _replace(text, _HOLD + "(\\d+)" + _HOLD, func(m: RegExMatch) -> String:
		return held[int(m.get_string(1))])


## Eckige Klammern sind in BBCode die Tags.
static func _escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func _replace(text: String, pattern: String, with: Callable) -> String:
	var out := ""
	var at := 0
	for m in _rx(pattern).search_all(text):
		out += text.substr(at, m.get_start() - at) + str(with.call(m))
		at = m.get_end()
	return out + text.substr(at)


static func _rx(pattern: String) -> RegEx:
	if not _re.has(pattern):
		_re[pattern] = RegEx.create_from_string(pattern)
	return _re[pattern]
