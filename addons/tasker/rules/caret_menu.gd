extends RefCounted
## Was die Auswahlliste unter der Schreibmarke anbietet: Befehle nach `/` und
## Verweise nach `$`. Aus Taskers `client/ui/editor.tsx` (Befehle) und
## `client/ui/refs.tsx` (Suche) – hier ohne Oberfläche, die steckt in
## `ui/content_editor.gd`.
##
## Änderungen haben dieselbe Form wie in `list_edit.gd`:
## `{ from, to, text, sel_start, sel_end }`.

const Workspace := preload("workspace.gd")
const Model := preload("model.gd")

const SLASH := "slash"
const REF := "ref"

## Ein Befehl im `/`-Menü: `label`, rechts klein `hint`, weitere Suchwörter
## `keywords` und `line` – was am Zeilenanfang eingefügt wird.
const SLASH_COMMANDS := [
	{"id": "todo", "label": "TodoListe", "hint": "- [ ]", "keywords": ["todo", "checkliste", "checkbox", "aufgaben"], "line": "- [ ] "},
	{"id": "list", "label": "Liste", "hint": "-", "keywords": ["liste", "aufzählung", "punkte", "bullet"], "line": "- "},
]

const MAX_HITS := 8

static var _re := {}


static func _rx(pattern: String) -> RegEx:
	if not _re.has(pattern):
		_re[pattern] = RegEx.create_from_string(pattern)
	return _re[pattern]


## Ob vor der Schreibmarke gerade eine Suche steht: `{ start, text }` – `start`
## ist die Stelle des Auslösezeichens, `text` was dahinter getippt wurde – oder
## null.
static func query_at(value: String, caret: int, kind: String) -> Variant:
	var pattern := "(^|\\s)/([^\\s/]{0,30})$" if kind == SLASH else "(^|[^\\w$])\\$([^\\s$]{0,40})$"
	var m := _rx(pattern).search(value.substr(0, caret))
	if m == null:
		return null
	return {"start": caret - m.get_string(2).length() - 1, "text": m.get_string(2)}


# ---------------------------------------------------------------- Befehle

## Passende Befehle – wessen Name oder Stichwort so anfängt, steht vorn.
static func slash_matches(query: String) -> Array:
	var q := query.to_lower()
	var first := []
	var second := []
	for c: Dictionary in SLASH_COMMANDS:
		var label: String = c["label"].to_lower()
		if q == "" or label.begins_with(q) or c["keywords"].any(func(k: String) -> bool: return k.begins_with(q)):
			first.append(c)
		elif label.contains(q):
			second.append(c)
	return first + second


## Befehl übernehmen: steht vor dem `/` nichts (oder nur ein leerer
## Listenpunkt), beginnt der Befehl diese Zeile; sonst eine neue darunter.
## `start` ist die Stelle des `/`, `end` die Schreibmarke.
static func slash_edit(value: String, start: int, end: int, command: Dictionary) -> Dictionary:
	var line_start := 0 if start <= 0 else value.rfind("\n", start - 1) + 1
	var before := value.substr(line_start, start - line_start)
	var indent := before.length() - before.lstrip(" ").length()
	if before.strip_edges() == "" or _rx("^( *)(?:[-*+]|\\d{1,9}[.)]) +(?:\\[[ xX]\\] +)?$").search(before) != null:
		return _replace(line_start + indent, end, command["line"])
	var from := line_start + before.rstrip(" \t").length()
	return _replace(from, end, "\n" + " ".repeat(indent) + command["line"])


static func _replace(from: int, to: int, text: String) -> Dictionary:
	return {"from": from, "to": to, "text": text, "sel_start": from + text.length(), "sel_end": from + text.length()}


# --------------------------------------------------------------- Verweise

## Aufgaben, Dokumente und Milestones zum Suchtext – das eigene Projekt
## zuerst, Erledigtes zuletzt. Ziffern suchen nach der Nummer. Jeder Treffer:
## `{ id, ref, kind, title, doc, done }`.
static func ref_search(ws: Workspace, query: String, project_id: Variant, self_id: Variant) -> Array:
	var needle := query.to_lower()
	var by_number := needle.is_valid_int() and not needle.begins_with("-") and not needle.begins_with("+")
	var hits := []
	for x: Dictionary in ws.milestones + ws.tasks:
		if x["id"] == self_id:
			continue
		var title: String = x["title"] if x.get("title") is String else ""
		if needle != "":
			if by_number:
				if not str(int(x.get("ref", 0))).begins_with(needle):
					continue
			elif not title.to_lower().contains(needle):
				continue
		var is_ms := Model.is_milestone(x)
		var done := Model.is_done(x)
		hits.append({
			"id": x["id"], "ref": int(x.get("ref", 0)), "kind": "milestone" if is_ms else "task",
			"title": title, "doc": not is_ms and ws.is_doc(x), "done": done,
			"score": (0 if x.get("projectId") == project_id else 2)
				+ (0 if needle != "" and title.to_lower().begins_with(needle) else 1)
				+ (4 if done else 0),
		})
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["score"] != b["score"]:
			return a["score"] < b["score"]
		var by_title: int = a["title"].nocasecmp_to(b["title"])
		return by_title < 0 if by_title != 0 else a["ref"] < b["ref"])
	return hits.slice(0, MAX_HITS)


## Was in der Liste vor dem Titel steht.
static func ref_icon(target: Dictionary) -> String:
	return "◆ " if target["kind"] == "milestone" else ("▤ " if target["doc"] else "")


## Verweis übernehmen: `$142 ` anstelle des Getippten.
static func ref_edit(start: int, end: int, target: Dictionary) -> Dictionary:
	return _replace(start, end, "$%d " % target["ref"])
