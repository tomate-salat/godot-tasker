@tool
extends Node
## Ruft die Claude-CLI im Druckmodus (`claude -p`) auf und wartet auf ihre
## Antwort, ohne den Editor anzuhalten: der Prozess läuft für sich, gelesen
## wird in kleinen Abständen.
##
## Angemeldet ist, wer in der CLI angemeldet ist – das Addon kennt weder
## Schlüssel noch Konto. Claude darf hier nur lesen: Dateien und, falls der
## MCP-Server läuft, die Suche nach Aufgaben.

const POLL_SECONDS := 0.25
## Länger wartet niemand; danach wird der Prozess beendet.
const PATIENCE_MSEC := 10 * 60 * 1000
const MODEL := "haiku"
const TOOLS := "Read,Grep,Glob"
const ALLOWED := "Read,Grep,Glob,mcp__godot-tasker__find_tasks"

## Die laufenden Prozesse – beim Beenden des Editors werden sie mitbeendet.
var _pids: Array[int] = []
var _command := ""


func _exit_tree() -> void:
	for pid in _pids:
		if OS.is_process_running(pid):
			OS.kill(pid)
	_pids.clear()


## Wo die CLI liegt – leer, wenn sie nicht zu finden ist.
func command() -> String:
	if _command != "" and FileAccess.file_exists(_command):
		return _command
	_command = find_command()
	return _command


static func find_command() -> String:
	var windows := OS.get_name() == "Windows"
	var out := []
	if OS.execute("where" if windows else "which", ["claude"], out) == 0 and not out.is_empty():
		var found := Array(str(out[0]).replace("\r", "").split("\n", false))
		# Unter Windows nur die .exe: eine .cmd ließe sich nur über cmd starten.
		for line in found:
			if not windows or line.to_lower().ends_with(".exe"):
				return line.strip_edges()
	var home := OS.get_environment("USERPROFILE" if windows else "HOME")
	var guess := home.path_join(".local/bin/claude" + (".exe" if windows else ""))
	return guess if FileAccess.file_exists(guess) else ""


## Ein Auftrag: Claude liest die Datei `prompt_file` und antwortet nach
## `schema`. Antwort: `{ ok, error, data }` mit der Antwort als Dictionary.
## `on_tool` hört jeden Werkzeugaufruf mit (Name, Eingabe). In `handle`
## steht danach `pid`; `stop(handle)` bricht ab.
func run(prompt_file: String, schema: Dictionary, project_dir: String, on_tool := Callable(), handle := {}, patience := PATIENCE_MSEC) -> Dictionary:
	var exe := command()
	if exe == "":
		return _failed("Die Claude-CLI ist nicht zu finden (gesucht mit „%s claude“ und in ~/.local/bin)." % ("where" if OS.get_name() == "Windows" else "which"))
	var args := [
		# Der Auftrag liegt in einer Datei: er ist zu lang und zu bunt für eine Befehlszeile.
		"-p", "Lies die Datei %s und folge dem Auftrag darin." % prompt_file,
		"--model", MODEL,
		# Als Strom, damit sich mitlesen lässt, was Claude gerade tut.
		"--output-format", "stream-json",
		"--verbose",
		"--json-schema", JSON.stringify(schema),
		"--tools", TOOLS,
		"--allowedTools", ALLOWED,
		"--permission-mode", "dontAsk",
		"--no-session-persistence",
		"--add-dir", project_dir,
	]
	if OS.get_name() == "Windows":
		args = args.map(quote)
	var started := OS.execute_with_pipe(exe, args, false)
	if started.is_empty():
		return _failed("Die Claude-CLI ließ sich nicht starten (%s)." % exe)
	var pid: int = started["pid"]
	var stdio: FileAccess = started["stdio"]
	var stderr: FileAccess = started["stderr"]
	_pids.append(pid)
	handle["pid"] = pid
	var out := PackedByteArray()
	var err := PackedByteArray()
	var seen := 0
	var since := Time.get_ticks_msec()
	while OS.is_process_running(pid):
		out.append_array(stdio.get_buffer(65536))
		err.append_array(stderr.get_buffer(65536))
		seen = _listen(out, seen, on_tool)
		if Time.get_ticks_msec() - since > patience:
			OS.kill(pid)
			_pids.erase(pid)
			return _failed("Claude hat nach %s Minuten nicht geantwortet – abgebrochen." % String.num(patience / 60000.0, 1).trim_suffix(".0"))
		await get_tree().create_timer(POLL_SECONDS).timeout
		if not is_inside_tree():
			return _failed("Abgebrochen.")
	out.append_array(stdio.get_buffer(1 << 22))
	err.append_array(stderr.get_buffer(1 << 16))
	_listen(out, seen, on_tool)
	_pids.erase(pid)
	stdio.close()
	stderr.close()
	if handle.get("stopped", false):
		return _failed("Abgebrochen.")
	return read_answer(out.get_string_from_utf8(), err.get_string_from_utf8())


## Bricht einen laufenden Auftrag ab.
func stop(handle: Dictionary) -> void:
	handle["stopped"] = true
	if handle.has("pid") and OS.is_process_running(handle["pid"]):
		OS.kill(handle["pid"])


## Meldet die Werkzeugaufrufe der Zeilen, die seit `seen` vollständig
## angekommen sind. Gibt zurück, bis wohin gelesen ist.
static func _listen(out: PackedByteArray, seen: int, on_tool: Callable) -> int:
	while true:
		var end := out.find(10, seen)
		if end < 0:
			return seen
		if on_tool.is_valid():
			for use in tool_uses(out.slice(seen, end).get_string_from_utf8()):
				on_tool.call(use[0], use[1])
		seen = end + 1
	return seen


## Die Werkzeugaufrufe in einer Zeile des Stroms: `[[Name, Eingabe], …]`.
static func tool_uses(line: String) -> Array:
	var event: Variant = JSON.parse_string(line) if line.strip_edges().begins_with("{") else null
	if not event is Dictionary or event.get("type") != "assistant" or not event.get("message") is Dictionary:
		return []
	var content: Variant = event["message"].get("content")
	var out := []
	for part in content if content is Array else []:
		if part is Dictionary and part.get("type") == "tool_use":
			out.append([str(part.get("name", "")), part.get("input") if part.get("input") is Dictionary else {}])
	return out


## Liest, was die CLI ausgibt: eine Antwort (`--output-format json`) oder
## einen Strom, in dem die Zeile vom Typ `result` die Antwort ist.
static func read_answer(stdout: String, stderr: String) -> Dictionary:
	var data: Variant = null
	for line in stdout.split("\n", false):
		var event: Variant = JSON.parse_string(line) if line.strip_edges().begins_with("{") else null
		if event is Dictionary and event.get("type", "result") == "result":
			data = event
	if not data is Dictionary:
		var why := _last_line(stderr)
		return _failed("Die Claude-CLI hat keine lesbare Antwort gegeben%s." % (": " + why if why != "" else ""))
	if data.get("is_error", false):
		return _failed("Claude meldet einen Fehler: %s" % str(data.get("result", data.get("subtype", "unbekannt"))))
	var answer: Variant = data.get("structured_output")
	if not answer is Dictionary:
		# Ohne strukturierte Antwort steht das JSON vielleicht im Text.
		answer = JSON.parse_string(str(data.get("result", "")))
	if not answer is Dictionary:
		return _failed("Claude hat nicht in der verlangten Form geantwortet.")
	return {"ok": true, "error": "", "data": answer}


## Ein Argument so, wie es die C-Laufzeit unter Windows wieder auseinandernimmt:
## Anführungszeichen mit Rückstrich, Rückstriche davor verdoppelt. Die äußeren
## Anführungszeichen setzt Godot selbst, sobald ein Leerzeichen darin ist –
## nur dann werden auch Rückstriche am Ende verdoppelt.
static func quote(text: String) -> String:
	var out := ""
	var slashes := 0
	for c in text:
		if c == "\\":
			slashes += 1
			continue
		if c == "\"":
			out += "\\".repeat(slashes * 2 + 1) + "\""
		else:
			out += "\\".repeat(slashes) + c
		slashes = 0
	return out + "\\".repeat(slashes * (2 if text.contains(" ") else 1))


static func _last_line(text: String) -> String:
	var lines := Array(text.strip_edges().split("\n", false)).filter(func(l: String) -> bool: return not l.begins_with("Warning: no stdin"))
	return str(lines[-1]).strip_edges() if not lines.is_empty() else ""


static func _failed(why: String) -> Dictionary:
	return {"ok": false, "error": why, "data": {}}
