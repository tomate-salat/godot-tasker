@tool
extends RefCounted
## Schnellanlegen und die Claude-Knöpfe (Nutzer, 2026-10-19): eine Aufgabe
## aus dem Addon anlegen und sie danach von der Claude-CLI überarbeiten lassen.
##
## Drei Aufträge: die Aufgabe nach der Vorlage (`FORMAT`) neu schreiben, sie um Details erweitern, oder nur die Szenen und Nodes finden,
## die zu ihr gehören. Claude liest nur – Dateien und den Schnappschuss, den
## das Addon beim Klick gemacht hat – und antwortet mit einem festen JSON. Das
## Addon trägt es selbst ein (`core/claude_tasks.gd`).
##
## Dazu die freie Anweisung aus dem Aufgabenfenster (`INSTRUCT`, Nutzer,
## 2026-10-19): „das Addon heißt Dialogic“, „Frage 2: ja“ – Claude ändert nur,
## was verlangt ist, und darf dabei auch Verknüpfungen lösen.

const TaskChanges := preload("task_changes.gd")

const REWRITE := "rewrite"
const EXTEND := "extend"
const LINKS := "links"
const INSTRUCT := "instruct"
## Die festen Aufträge – auch die, die Tasker aus der Web-App schicken darf.
const MODES := [REWRITE, EXTEND, LINKS]

const LABELS := {
	REWRITE: "Neu schreiben",
	EXTEND: "Erweitern",
	LINKS: "Abhängigkeiten finden",
	INSTRUCT: "Anweisung",
}
const TOOLTIPS := {
	REWRITE: "Claude schreibt die Aufgabe nach der Vorlage neu: Observation, Context, Affected, Acceptance criteria, To-do, Open questions – auf Englisch",
	EXTEND: "Claude behält, was dasteht, und ergänzt Details aus Szene und Code",
	LINKS: "Claude sucht die Szenen und Nodes, die zur Aufgabe gehören, und hängt sie an",
}
## Was im Fenster steht, solange Claude arbeitet – `%s` ist die Nummer.
const BUSY := {
	REWRITE: "Claude schreibt %s neu",
	EXTEND: "Claude erweitert %s",
	LINKS: "Claude sucht, woran %s hängt",
	INSTRUCT: "Claude ändert %s",
}
const DONE := {
	REWRITE: "%s ist neu geschrieben.",
	EXTEND: "%s ist erweitert.",
	LINKS: "Für %s ist gesucht.",
	INSTRUCT: "%s ist geändert.",
}

## Was Claude nennen darf, um eine Aufgabe anzuhängen: Szenen und Nodes darin.
const LINK_SCHEMA := {
	"type": "array",
	"items": {
		"type": "object",
		"properties": {
			"scene": {"type": "string"},
			"paths": {"type": "array", "items": {"type": "string"}},
		},
		"required": ["scene", "paths"],
	},
}

## Die Gliederung der Beschreibung. Früher stand sie auch im Agenten
## „tasker-scout“; den gibt es nicht mehr, sie steht nur noch hier.
const FORMAT := """**Observation**
What the user noticed, close to their own words.

**Context**
What the scene and the code say about it, in three to six sentences. Only what you checked.

**Affected**
- Scenes and nodes (res:// path, node path)
- Scripts and assets (res:// path)

**Acceptance criteria**
- [ ] two to five observable results that show the task is done – what the user can check in the game or editor, not steps to get there

**To-do**
- [ ] three to seven steps, rough, in a sensible order

**Open questions**
- Assumptions you made, and what the user still has to decide

**Related**
- $number title"""


## Die Form der Antwort für `--json-schema`.
static func schema(mode: String) -> Dictionary:
	var props := {
		"links": LINK_SCHEMA,
		"note": {"type": "string"},
	}
	var required := ["links", "note"]
	if mode != LINKS:
		props["title"] = {"type": "string"}
		props["desc"] = {"type": "string"}
		required = ["title", "desc", "links", "note"]
	# Nur eine Anweisung darf auch lösen, woran die Aufgabe hängt, und die
	# Felder ändern, die man sonst in der Web-App setzt.
	if mode == INSTRUCT:
		props["unlink"] = LINK_SCHEMA
		props.merge(TaskChanges.SCHEMA)
		required.append_array(["unlink", "changes", "subtasks"])
	return {"type": "object", "properties": props, "required": required}


## Der Auftrag an Claude. `linked` sind die Verknüpfungen, die schon bestehen
## (je eine Zeile), `snapshot` ist die Ausgabe von `context` beim Klick,
## `instruction` die Anweisung des Nutzers (nur bei `INSTRUCT`).
static func prompt(mode: String, task: Dictionary, linked: Array, snapshot: String, project_dir: String, instruction := "", facts := "") -> String:
	var lines := [
		"Du arbeitest an einer Aufgabe in Tasker, der Aufgabenverwaltung des Nutzers. Sie gehört zu seinem Godot-Projekt in %s – `res://` ist dieses Verzeichnis." % project_dir,
		"",
		"Du änderst keine Datei und legst nichts an. Deine Antwort ist das verlangte JSON; das Addon trägt es selbst ein. Du fragst nicht zurück: Ist etwas unklar, triffst du die naheliegendste Annahme und schreibst sie auf.",
		"",
		"## Die Aufgabe",
		"",
		"Nummer: $%d" % int(task.get("ref", 0)),
		"Titel: %s" % str(task.get("title", "")),
		"Beschreibung:",
		"<<<",
		str(task.get("desc", "")) if str(task.get("desc", "")).strip_edges() != "" else "(leer)",
		">>>",
		"",
		"## Schon angehängt",
		"",
		"\n".join(linked) if not linked.is_empty() else "(nichts)",
		"",
		"## Schnappschuss des Editors",
		"",
		"So stand es im Editor, als der Nutzer den Knopf drückte. Er arbeitet inzwischen weiter; was der Editor jetzt zeigt, kann etwas anderes sein – dieser Schnappschuss gilt. Läuft laut Schnappschuss das Spiel, meint der Nutzer sehr wahrscheinlich, was er dort sieht.",
		"",
		"<<<",
		snapshot if snapshot.strip_edges() != "" else "(keiner)",
		">>>",
		"",
		"## Umsehen",
		"",
		"Alles Weitere liest du aus den Dateien des Projekts (Read, Grep, Glob): die Szenendateien, die Skripte an den betroffenen Nodes, instanzierte Szenen, passende Assets. Bleib an der Oberfläche – höchstens etwa zehn Dateien. Gibt es das Werkzeug `find_tasks` (godot-tasker), such damit nach ein, zwei Stichwörtern verwandte Aufgaben.",
		"",
		"## Dein Auftrag",
		"",
	]
	match mode:
		REWRITE:
			lines.append("Schreib die Aufgabe neu. Was der Nutzer geschrieben hat, ist seine Beobachtung; sie kommt sinngemäß unter „Observation“, nichts davon geht verloren.")
		EXTEND:
			lines.append("Erweitere die Aufgabe. Was dasteht, bleibt in Sinn und Reihenfolge erhalten; ist es nicht auf Englisch, übersetzt du es sinngemäß. Du ergänzt, was fehlt – Abschnitte der Gliederung, Details aus Szene und Code, Schritte –, und schreibst nichts um, was schon stimmt.")
		LINKS:
			lines.append("Finde die Szenen und Nodes, die zu dieser Aufgabe gehören – woran sie im Projekt hängt. Titel und Beschreibung änderst du nicht.")
		INSTRUCT:
			lines.append_array([
				"Ändere die Aufgabe nach dieser Anweisung des Nutzers:",
				"",
				"<<<",
				instruction.strip_edges(),
				">>>",
				"",
				"Ändere nur, was die Anweisung verlangt. Alles andere bleibt wortgleich stehen – Gliederung, Reihenfolge, Häkchen in Checklisten, Verweise. Beantwortet die Anweisung eine offene Frage, nimm die Frage aus „Open questions“ und arbeite die Antwort dort ein, wo sie hingehört. Die Aufgabe bleibt auf Englisch, auch wenn die Anweisung deutsch ist. Musst du für die Anweisung etwas nachsehen, tu es; sonst lies nichts.",
			])
	if mode == INSTRUCT:
		lines.append_array([
			"",
			"So steht die Aufgabe in Tasker:",
			"",
			facts if facts != "" else "(unbekannt)",
			"",
			"- `title`: der Titel – unverändert, außer die Anweisung betrifft ihn.",
			"- `desc`: die ganze Beschreibung mit deinen Änderungen, nicht nur die geänderten Stellen.",
			"- `changes`: nur, was die Anweisung an diesen Feldern verlangt; alles andere weglassen. `status`, `prio` aus der jeweiligen Wahl; `mark`, `category`, `place` mit dem Namen aus der Wahl (`place`: Milestone, Gruppe oder \"Backlog\"); `tags` und `deps` jeweils die ganze neue Liste (`deps` als Nummern wie \"$142\" – die Aufgaben, auf die diese wartet).",
			"- `subtasks`: neue Unteraufgaben, wenn die Anweisung sie verlangt (etwa „teil das auf“) – je `title` (kurz, englisch, als Tätigkeit) und `desc` (darf leer sein). Was du in Unteraufgaben auslagerst, nimmst du aus der Beschreibung heraus, statt es doppelt zu führen. Sonst leere Liste.",
			"- `unlink`: was von „Schon angehängt“ gelöst werden soll, weil die Anweisung es verlangt – gleiche Form wie `links`, `scene` und `path` genau wie oben. Sonst leere Liste.",
		])
	elif mode != LINKS:
		lines.append_array([
			"",
			"- `title`: kurz, auf Englisch, als Tätigkeit („Add pants for the player character“).",
			"- `desc`: Markdown auf Englisch, in dieser Gliederung, mit einer Leerzeile vor jeder Überschrift; Abschnitte ohne Inhalt weglassen. Nur, was du gesehen hast – Vermutungen stehen unter „Open questions“, nicht unter „Context“.",
			"",
			"```",
			FORMAT,
			"```",
		])
	lines.append_array([
		"",
		"- `links`: die betroffenen Szenen und Nodes, die noch nicht angehängt sind. Je Eintrag `scene` (res://-Pfad einer .tscn) und `paths` (Node-Pfade relativ zur Wurzel dieser Szene, \".\" ist die Wurzel – in der .tscn ist das `parent` + \"/\" + `name`, bei `parent=\".\"` nur der Name). Läuft das Spiel, nimmst du nicht den Pfad zur Laufzeit, sondern die Szenendatei, aus der der Node stammt („Instanz: …“). Nur, was du in einer Datei oder im Schnappschuss gesehen hast; im Zweifel weniger. Skripte und Ressourcen ohne Szene lassen sich nicht anhängen – die gehören unter „Affected“. Nichts Passendes: leere Liste.",
		"- `note`: ein kurzer Satz auf Deutsch, was du geändert hast (etwa „Titel und 6 Stellen: Third Wheel → Dialogic“)." if mode == INSTRUCT else \
			"- `note`: ein, zwei kurze Sätze auf Deutsch für den Nutzer: welche Annahme du getroffen hast, falls eine, sonst was du getan hast.",
	])
	return "\n".join(lines)


## Prüft die Antwort: `{ ok, error, title, desc, links, note }`. `links` sind
## nach Szene gruppiert, `{ scene, paths }`; Unbrauchbares fällt heraus.
static func parse(mode: String, answer: Variant) -> Dictionary:
	var out := {"ok": false, "error": "", "title": "", "desc": "", "links": [], "unlink": [], "changes": {}, "subtasks": [], "note": ""}
	if not answer is Dictionary:
		out["error"] = "Claude hat keine lesbare Antwort geschickt."
		return out
	if mode != LINKS:
		out["title"] = str(answer.get("title", "")).strip_edges()
		out["desc"] = spaced(str(answer.get("desc", "")).strip_edges())
		if out["title"] == "":
			out["error"] = "Claude hat keinen Titel geschickt."
			return out
	out["note"] = str(answer.get("note", "")).strip_edges()
	out["links"] = _groups(answer.get("links", []))
	out["unlink"] = _groups(answer.get("unlink", [])) if mode == INSTRUCT else []
	var more := TaskChanges.parse(answer) if mode == INSTRUCT else {"changes": {}, "subtasks": []}
	out["changes"] = more["changes"]
	out["subtasks"] = more["subtasks"]
	out["ok"] = true
	return out


## Szenen und Node-Pfade aus der Antwort, nach Szene gruppiert: `{ scene, paths }`.
static func _groups(given: Variant) -> Array:
	var by_scene := {}
	for entry in given if given is Array else []:
		if not entry is Dictionary:
			continue
		var scene := str(entry.get("scene", "")).strip_edges()
		if not scene.begins_with("res://") or scene.get_extension() != "tscn":
			continue
		var paths: Variant = entry.get("paths", [])
		for p in paths if paths is Array else []:
			var path := str(p).strip_edges().trim_prefix("./")
			if path == "":
				path = "."
			if not by_scene.has(scene):
				by_scene[scene] = []
			if not by_scene[scene].has(path):
				by_scene[scene].append(path)
	var out := []
	for scene in by_scene:
		out.append({"scene": scene, "paths": by_scene[scene]})
	return out


## Eine Leerzeile vor jeder Überschrift der Gliederung (`**Context**`) – ohne
## sie liefe die Überschrift im Markdown in den Absatz davor.
static func spaced(desc: String) -> String:
	var lines := desc.replace("\r\n", "\n").split("\n")
	var out := []
	for line in lines:
		var bare := line.strip_edges()
		var heading := bare.length() > 4 and bare.begins_with("**") and bare.ends_with("**") and not bare.substr(2, bare.length() - 4).contains("*")
		if heading and not out.is_empty() and str(out[-1]).strip_edges() != "":
			out.append("")
		out.append(line)
	return "\n".join(out)


## Was Claude gerade tut, als Zeile fürs Fenster – aus einem Werkzeugaufruf
## der CLI. Leer, wenn es nichts zu zeigen gibt.
static func activity(tool: String, input: Dictionary) -> String:
	match tool:
		"Read":
			var path := str(input.get("file_path", "")).replace("\\", "/")
			return "liest den Auftrag" if path.contains(".godot/tasker/claude/") else "liest %s" % path.get_file()
		"Grep":
			return "sucht „%s“" % str(input.get("pattern", ""))
		"Glob":
			return "sucht Dateien %s" % str(input.get("pattern", ""))
		"mcp__godot-tasker__find_tasks":
			return "sucht Aufgaben zu „%s“" % str(input.get("query", ""))
		"StructuredOutput":
			return "schreibt die Antwort"
	return ""


## Lässt weg, was schon angehängt ist. `linked` sind Referenzen (`rules/refs.gd`).
static func without_linked(groups: Array, linked: Array) -> Array:
	var out := []
	for g in groups:
		var fresh: Array = g["paths"].filter(func(path: String) -> bool:
			return not linked.any(func(ref: Dictionary) -> bool: return ref["scenePath"] == g["scene"] and ref["nodePath"] == path))
		if not fresh.is_empty():
			out.append({"scene": g["scene"], "paths": fresh})
	return out
