extends RefCounted
## Listen im Beschreibungsfeld weiterschreiben. Aus Taskers
## `shared/listEdit.ts`: reine Textfunktionen, die Text und Auswahl bekommen
## und die Änderung liefern – das Textfeld wendet sie an.
##
## - Enter in einem Listenpunkt (`- `, `* `, `1. `, auch mit `[ ]`) beginnt den
##   nächsten Punkt gleicher Art; ein Kästchen kommt immer leer mit.
## - Enter in einem leeren Punkt beendet die Liste: eingerückt geht es eine
##   Ebene hinauf, ganz außen verschwindet das Zeichen.
## - Umschalt+Enter bricht im Punkt die Zeile um und rückt die neue so weit
##   ein, dass sie noch zum Punkt gehört.
## - Tab / Umschalt+Tab rücken Listenpunkte ein und aus – alle markierten
##   Zeilen, die Listenpunkte sind.
## - Alt und Pfeil hoch/runter schieben die Zeile der Schreibmarke (oder alle
##   markierten) nach oben oder unten.
##
## Eine Änderung ist `{ from, to, text, sel_start, sel_end }`: ersetze
## `from..to` durch `text`, danach steht die Auswahl bei `sel_start..sel_end`.
## `null` heißt: die Taste bleibt, was sie war.

static var _item_re: RegEx


## Der Listenpunkt am Anfang dieser Zeile – oder null. `indent` ist die
## Einrückung, `marker` das Zeichen (`-`, `*`, `+`, `1.`, `1)`), `num` die
## Nummer (-1 ohne), `delim` ihr Abschluss, `gap` der Abstand danach, `box`
## ein Kästchen samt Abstand, `prefix` die Länge von alldem.
static func item(line: String) -> Variant:
	if _item_re == null:
		_item_re = RegEx.create_from_string("^( *)([-*+]|(\\d{1,9})([.)]))( +)(\\[[ xX]\\] +)?")
	var m := _item_re.search(line)
	if m == null:
		return null
	return {
		"indent": m.get_string(1),
		"marker": m.get_string(2),
		"num": int(m.get_string(3)) if m.get_string(3) != "" else -1,
		"delim": m.get_string(4),
		"gap": m.get_string(5),
		"box": m.get_string(6),
		"prefix": m.get_string(0).length(),
	}


## Wie weit der Inhalt eines Punktes eingerückt ist – so tief muss ein Unterpunkt stehen.
static func _content_width(it: Dictionary) -> int:
	return it["marker"].length() + it["gap"].length()


## Wie viele Leerzeichen am Anfang der Zeile stehen.
static func _lead(line: String) -> int:
	var n := 0
	while n < line.length() and line[n] == " ":
		n += 1
	return n


## Der Anfang der Zeile, in der `i` steht.
static func line_start(v: String, i: int) -> int:
	return 0 if i <= 0 else v.rfind("\n", i - 1) + 1


static func line_end(v: String, i: int) -> int:
	var n := v.find("\n", i)
	return v.length() if n < 0 else n


static func _edit(from: int, to: int, text: String, sel_start: int, sel_end: int) -> Dictionary:
	return {"from": from, "to": to, "text": text, "sel_start": sel_start, "sel_end": sel_end}


static func _lines(text: String) -> Array:
	return Array(text.split("\n"))


## Enter: nächsten Punkt beginnen oder die Liste beenden.
static func enter_in_list(value: String, sel_start: int, sel_end: int) -> Variant:
	if sel_start != sel_end:
		return null
	var start := line_start(value, sel_start)
	var end := line_end(value, sel_start)
	var line := value.substr(start, end - start)
	var it = item(line)
	if it == null:
		return _next_after_body(value, start, line, sel_start)
	# Vor oder im Listenzeichen gilt das normale Enter.
	if sel_start - start < it["prefix"]:
		return null

	if line.substr(it["prefix"]).strip_edges() == "":
		if it["indent"] != "":
			var out = _shift_lines(value, sel_start, sel_start, -1)
			if out != null:
				return out
		# Ganz außen: das leere Zeichen verschwindet, die Zeile bleibt.
		return _edit(start, end, "", start, start)

	return _next_item(it, sel_start)


## Der Punkt nach `it`, eingefügt bei `at`.
static func _next_item(it: Dictionary, at: int) -> Dictionary:
	var marker: String = it["marker"] if it["num"] < 0 else "%d%s" % [it["num"] + 1, it["delim"]]
	var text: String = "\n%s%s%s%s" % [it["indent"], marker, it["gap"], "[ ] " if it["box"] != "" else ""]
	return _edit(at, at, text, at + text.length(), at + text.length())


## Enter in einer Folgezeile eines Punktes (eingerückter Text darunter): auch
## hier beginnt der nächste Punkt – auf der Ebene des Punktes, zu dem die Zeile
## gehört.
static func _next_after_body(value: String, start: int, line: String, at: int) -> Variant:
	var width := _lead(line)
	if line.strip_edges() == "" or at - start < width:
		return null
	var owner = _owner_item(_lines(value.substr(0, start)), width)
	return _next_item(owner, at) if owner != null else null


## Umschalt+Enter: neue Zeile, die noch zum Listenpunkt gehört – eingerückt bis
## unter seinen Inhalt. In einer Zeile, die schon zu einem Punkt gehört, bleibt
## ihre Einrückung.
static func break_in_item(value: String, sel_start: int, sel_end: int) -> Variant:
	var start := line_start(value, sel_start)
	var line := value.substr(start, line_end(value, sel_start) - start)
	var it = item(line)
	var indent := 0
	if it != null:
		if sel_start - start < it["prefix"]:
			return null
		indent = it["indent"].length() + _content_width(it)
	else:
		indent = _lead(line)
		if indent == 0 or sel_start - start < indent or _owner_item(_lines(value.substr(0, start)), indent) == null:
			return null
	var text := "\n" + " ".repeat(indent)
	var at := sel_start + text.length()
	return _edit(sel_start, sel_end, text, at, at)


## Der Listenpunkt darüber, zu dem eine Zeile mit dieser Einrückung noch gehört.
static func _owner_item(above: Array, width: int) -> Variant:
	for i in range(above.size() - 1, -1, -1):
		var line: String = above[i]
		if line.strip_edges() == "":
			continue
		var it = item(line)
		if it != null and it["indent"].length() < width:
			return it
		if _lead(line) < width:
			return null
	return null


## Tab (`dir` 1) oder Umschalt+Tab (`dir` -1) für die Zeilen der Auswahl.
## Null, wenn die Zeile mit der Schreibmarke kein Listenpunkt ist oder sich
## nichts ändert.
static func tab_in_list(value: String, sel_start: int, sel_end: int, dir: int) -> Variant:
	if not in_item(value, sel_start):
		return null
	return _shift_lines(value, sel_start, sel_end, dir)


## Ob die Zeile, in der `at` steht, ein Listenpunkt ist.
static func in_item(value: String, at: int) -> bool:
	var first := line_start(value, at)
	return item(value.substr(first, line_end(value, first) - first)) != null


## Alt und Pfeil hoch/runter: die Zeile der Schreibmarke mit ihrer Nachbarin
## tauschen – bei einer Markierung der ganze Block. Die Markierung wandert mit.
## Null heißt: am Rand angekommen.
static func move_lines(value: String, sel_start: int, sel_end: int, dir: int) -> Variant:
	var from := line_start(value, sel_start)
	var to := line_end(value, sel_end)
	var block := value.substr(from, to - from)

	if dir == -1:
		if from == 0:
			return null
		var above := line_start(value, from - 1)
		var shift := from - above
		return _edit(above, to, "%s\n%s" % [block, value.substr(above, from - 1 - above)], sel_start - shift, sel_end - shift)

	if to >= value.length():
		return null
	var below := line_end(value, to + 1)
	var next := value.substr(to + 1, below - to - 1)
	var down := next.length() + 1
	return _edit(from, below, "%s\n%s" % [next, block], sel_start + down, sel_end + down)


static func _shift_lines(value: String, sel_start: int, sel_end: int, dir: int) -> Variant:
	var from := line_start(value, sel_start)
	var to := line_end(value, sel_end)
	# Die Zeilen davor – als Maßstab für die Einrückung, laufend mit den geänderten.
	var above := []
	if from > 0:
		above = _lines(value.substr(0, from))
		above.pop_back()
	var lines := _lines(value.substr(from, to - from))

	var changed := false
	var out := []
	for line: String in lines:
		var it = item(line)
		var next := line
		if it != null:
			var width: int = it["indent"].length()
			var target := _indent_for(above, width) if dir == 1 else _outdent_for(above, width)
			if target >= 0 and target != width:
				var rest := line.substr(width + it["marker"].length())
				var marker: String = it["marker"] if it["num"] < 0 else "%d%s" % [_number_at(above, target), it["delim"]]
				next = " ".repeat(target) + marker + rest
				changed = true
		out.append(next)
		above.append(next)
	if not changed:
		return null

	# Eine Stelle im alten Text auf den neuen abbilden: geändert wird nur der
	# Zeilenanfang, also wandert die Stelle um die Längenänderung ihrer Zeile
	# und aller Zeilen davor – aber nie vor den Anfang ihrer Zeile.
	var map := func(pos: int) -> int:
		var old_start := from
		var new_start := from
		for i in lines.size():
			var old_len: int = lines[i].length()
			var new_len: int = out[i].length()
			if pos <= old_start + old_len or i == lines.size() - 1:
				var at := new_start + (pos - old_start) + (new_len - old_len)
				return maxi(new_start, mini(new_start + new_len, at))
			old_start += old_len + 1
			new_start += new_len + 1
		return pos

	return _edit(from, to, "\n".join(PackedStringArray(out)), map.call(sel_start), map.call(sel_end))


## Der nächste Listenpunkt darüber, der höchstens so tief steht wie `width`
## (`strict`: weniger tief).
static func _parent_item(above: Array, width: int, strict: bool) -> Variant:
	for i in range(above.size() - 1, -1, -1):
		var line: String = above[i]
		if line.strip_edges() == "":
			continue
		var it = item(line)
		if it == null:
			return null
		var w: int = it["indent"].length()
		if (w < width) if strict else (w <= width):
			return it
	return null


## Einrücken: unter den Inhalt des Punktes darüber. Ohne Punkt darüber: zwei Leerzeichen.
static func _indent_for(above: Array, width: int) -> int:
	var sibling = _parent_item(above, width, false)
	if sibling == null:
		return width + 2
	var under: int = sibling["indent"].length() + _content_width(sibling)
	return under if under > width else width + 2


## Ausrücken: auf die Tiefe des übergeordneten Punktes. -1: geht nicht weiter.
static func _outdent_for(above: Array, width: int) -> int:
	if width == 0:
		return -1
	var parent = _parent_item(above, width, true)
	return parent["indent"].length() if parent != null else 0


## Die passende Nummer auf der neuen Ebene: eins weiter als der Punkt davor, sonst 1.
static func _number_at(above: Array, width: int) -> int:
	for i in range(above.size() - 1, -1, -1):
		var line: String = above[i]
		if line.strip_edges() == "":
			continue
		var it = item(line)
		if it == null:
			break
		var w: int = it["indent"].length()
		if w < width:
			break
		if w == width:
			return 1 if it["num"] < 0 else it["num"] + 1
	return 1
