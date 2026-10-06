extends RefCounted
## Markdown-Checklisten in einer Beschreibung: „- [ ]“ offen, „- [x]“ erledigt.
## Aus Taskers `shared/checklist.ts`, inklusive der Regel, dass Zeilen in
## Code-Blöcken nicht zählen.

static var _check: RegEx
static var _fence: RegEx


static func _check_re() -> RegEx:
	if _check == null:
		_check = RegEx.create_from_string("^(\\s*(?:[-*+]|\\d+[.)])\\s+\\[)( |x|X)(\\])")
	return _check


static func _fence_re() -> RegEx:
	if _fence == null:
		_fence = RegEx.create_from_string("^\\s*(```|~~~)")
	return _fence


## Alle Checklisten-Zeilen außerhalb von Code-Blöcken: `{ lines, out }`,
## `out` sind die Zeilennummern in Reihenfolge.
static func lines_of(s: Variant) -> Dictionary:
	var lines: Array = Array((s if s is String else "").split("\n"))
	var out := []
	var fence := ""
	for i in lines.size():
		var fm := _fence_re().search(lines[i])
		if fm:
			var mark := fm.get_string(1)
			if fence == mark:
				fence = ""
			elif fence == "":
				fence = mark
			continue
		if fence == "" and _check_re().search(lines[i]):
			out.append(i)
	return {"lines": lines, "out": out}


static func line_done(line: String) -> bool:
	var m := _check_re().search(line)
	return m != null and m.get_string(2) != " "


## `{ total, done }`
static func count(s: Variant) -> Dictionary:
	var cl := lines_of(s)
	var done := 0
	for i in cl["out"]:
		if line_done(cl["lines"][i]):
			done += 1
	return {"total": cl["out"].size(), "done": done}


## Schaltet den n-ten Punkt um und gibt den neuen Text zurück.
static func toggle_item(s: String, n: int) -> String:
	var cl := lines_of(s)
	if n < 0 or n >= cl["out"].size():
		return s
	var i: int = cl["out"][n]
	var line: String = cl["lines"][i]
	var m := _check_re().search(line)
	var at := m.get_start(2)
	cl["lines"][i] = line.substr(0, at) + ("x" if m.get_string(2) == " " else " ") + line.substr(at + 1)
	return "\n".join(PackedStringArray(cl["lines"]))
