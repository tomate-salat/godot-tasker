extends "suite.gd"
## Schnellanlegen und Claude-Aufträge, so weit es ohne Editor und CLI geht:
## `rules/quick.gd` und das Lesen der CLI-Antwort in `core/claude_cli.gd`.

const Quick := preload("res://addons/tasker/rules/quick.gd")
const ClaudeCli := preload("res://addons/tasker/core/claude_cli.gd")


func test_die_antwort_wird_geprueft_und_nach_szene_gruppiert() -> void:
	var got := Quick.parse(Quick.REWRITE, {
		"title": " Fix pants ",
		"desc": "**Observation**\nNo pants.",
		"links": [
			{"scene": "res://arena.tscn", "paths": ["Player", "./Player", ""]},
			{"scene": "res://arena.tscn", "paths": ["Enemy"]},
			{"scene": "res://player.gd", "paths": ["."]},
			{"scene": "arena.tscn", "paths": ["X"]},
			"quatsch",
		],
		"note": "Angenommen: der linke Gladiator.",
	})
	ok(got["ok"])
	eq(got["title"], "Fix pants")
	eq(got["links"], [{"scene": "res://arena.tscn", "paths": ["Player", ".", "Enemy"]}], "nur .tscn mit res://, ohne Doppelte")
	eq(got["note"], "Angenommen: der linke Gladiator.")


func test_ueberschriften_bekommen_eine_leerzeile() -> void:
	eq(Quick.spaced("**Observation**\nNo pants.\n**Context**\nHidden.\n\n**To-do**\n- [ ] **fix** it"),
		"**Observation**\nNo pants.\n\n**Context**\nHidden.\n\n**To-do**\n- [ ] **fix** it")


func test_ohne_titel_wird_nichts_eingetragen() -> void:
	eq(Quick.parse(Quick.EXTEND, {"title": " ", "desc": "x", "links": [], "note": ""})["ok"], false)
	eq(Quick.parse(Quick.EXTEND, "kein Objekt")["ok"], false)
	# Beim Suchen nach Abhängigkeiten gibt es keinen Titel.
	ok(Quick.parse(Quick.LINKS, {"links": [], "note": ""})["ok"])


func test_die_form_der_antwort_haengt_am_auftrag() -> void:
	eq(Quick.schema(Quick.LINKS)["required"], ["links", "note"])
	eq(Quick.schema(Quick.REWRITE)["required"], ["title", "desc", "links", "note"])


func test_schon_angehaengtes_faellt_heraus() -> void:
	var linked := [{"scenePath": "res://arena.tscn", "nodePath": "Player"}]
	eq(Quick.without_linked([{"scene": "res://arena.tscn", "paths": ["Player", "Enemy"]}, {"scene": "res://hub.tscn", "paths": ["."]}], linked),
		[{"scene": "res://arena.tscn", "paths": ["Enemy"]}, {"scene": "res://hub.tscn", "paths": ["."]}])
	eq(Quick.without_linked([{"scene": "res://arena.tscn", "paths": ["Player"]}], linked), [])


func test_der_auftrag_nennt_aufgabe_schnappschuss_und_vorlage() -> void:
	var task := {"ref": 412, "title": "Hose weg", "desc": "beim Angriff"}
	var text := Quick.prompt(Quick.REWRITE, task, ["- scene: res://arena.tscn   path: Player"], "Szene: res://arena.tscn", "C:/spiel")
	for part in ["$412", "Hose weg", "beim Angriff", "res://arena.tscn   path: Player", "Szene: res://arena.tscn", "C:/spiel", "As a <who>", "**To-do**", "`title`"]:
		ok(text.contains(part), part)
	var links_only := Quick.prompt(Quick.LINKS, task, [], "", "C:/spiel")
	ok(not links_only.contains("`title`"), "beim Suchen bleibt der Text, wie er ist")
	ok(links_only.contains("(nichts)"))


func test_argumente_fuer_windows() -> void:
	eq(ClaudeCli.quote("einfach"), "einfach")
	eq(ClaudeCli.quote("{\"a\":1}"), "{\\\"a\\\":1}")
	eq(ClaudeCli.quote("a\\\"b"), "a\\\\\\\"b", "Rückstrich vor Anführungszeichen wird verdoppelt")
	eq(ClaudeCli.quote("C:\\mit leer\\"), "C:\\mit leer\\\\", "am Ende verdoppelt, wenn Godot Anführungszeichen setzt")
	eq(ClaudeCli.quote("C:\\ohne\\"), "C:\\ohne\\")


func test_die_antwort_der_cli_wird_gelesen() -> void:
	var good := ClaudeCli.read_answer(JSON.stringify({"is_error": false, "structured_output": {"links": []}, "result": ""}), "")
	ok(good["ok"])
	eq(good["data"], {"links": []})
	# Ohne strukturierte Antwort zählt das JSON im Text.
	eq(ClaudeCli.read_answer(JSON.stringify({"is_error": false, "result": "{\"note\":\"x\"}"}), "")["data"], {"note": "x"})
	var bad := ClaudeCli.read_answer("", "Warning: no stdin data received in 3s\nError: nicht angemeldet")
	eq(bad["ok"], false)
	ok(bad["error"].contains("nicht angemeldet"), bad["error"])
	eq(ClaudeCli.read_answer(JSON.stringify({"is_error": true, "result": "Kontingent"}), "")["error"], "Claude meldet einen Fehler: Kontingent")


func test_was_claude_tut_wird_zur_zeile() -> void:
	eq(Quick.activity("Read", {"file_path": "C:\\spiel\\scenes\\cell.tscn"}), "liest cell.tscn")
	eq(Quick.activity("Read", {"file_path": "C:/spiel/.godot/tasker/claude/abc-rewrite.md"}), "liest den Auftrag")
	eq(Quick.activity("Grep", {"pattern": "Healer"}), "sucht „Healer“")
	eq(Quick.activity("mcp__godot-tasker__find_tasks", {"query": "heal"}), "sucht Aufgaben zu „heal“")
	eq(Quick.activity("Unbekannt", {}), "")


func test_die_antwort_kommt_auch_als_strom() -> void:
	var lines := [
		JSON.stringify({"type": "system", "subtype": "init"}),
		JSON.stringify({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Read", "input": {"file_path": "a.gd"}}]}}),
		JSON.stringify({"type": "result", "subtype": "success", "is_error": false, "structured_output": {"note": "ok"}}),
		JSON.stringify({"type": "system", "subtype": "task_summary"}),
	]
	eq(ClaudeCli.read_answer("\n".join(lines), "")["data"], {"note": "ok"})
	eq(ClaudeCli.tool_uses(lines[1]), [["Read", {"file_path": "a.gd"}]])
	eq(ClaudeCli.tool_uses(lines[0]), [])


func test_eine_anweisung_darf_auch_loesen() -> void:
	ok(Quick.schema(Quick.INSTRUCT)["required"].has("unlink"))
	ok(not Quick.schema(Quick.REWRITE)["properties"].has("unlink"), "nur die Anweisung löst")
	var got := Quick.parse(Quick.INSTRUCT, {"title": "T", "desc": "D", "links": [], "unlink": [{"scene": "res://cell.tscn", "paths": ["Healer Npc"]}], "note": "gelöst"})
	eq(got["unlink"], [{"scene": "res://cell.tscn", "paths": ["Healer Npc"]}])
	eq(Quick.parse(Quick.REWRITE, {"title": "T", "desc": "D", "links": [], "unlink": [{"scene": "res://cell.tscn", "paths": ["X"]}], "note": ""})["unlink"], [])


func test_die_anweisung_steht_im_auftrag() -> void:
	var text := Quick.prompt(Quick.INSTRUCT, {"ref": 414, "title": "Introduce Third Wheel", "desc": "x"}, [], "", "C:/spiel", "Das Addon heißt Dialogic")
	ok(text.contains("Das Addon heißt Dialogic"))
	ok(text.contains("`unlink`"))
	ok(not text.contains("As a <who>"), "keine Vorlage – der Rest bleibt, wie er ist")


func test_neu_geschriebene_aufgaben_haben_akzeptanzkriterien() -> void:
	var task := {"ref": 1, "title": "x", "desc": ""}
	ok(Quick.prompt(Quick.REWRITE, task, [], "", "C:/spiel").contains("**Acceptance criteria**"))
	ok(Quick.prompt(Quick.EXTEND, task, [], "", "C:/spiel").contains("**Acceptance criteria**"), "Erweitern ergänzt sie, wo sie fehlen")


func test_gesucht_wird_nur_fuer_offene_aufgaben_ohne_referenz() -> void:
	var roots := [
		{"id": "a", "status": "open", "archivedAt": null},
		{"id": "b", "status": "progress", "archivedAt": null},
		{"id": "c", "status": "done", "archivedAt": null},
		{"id": "d", "status": "open", "archivedAt": "2026-10-01"},
		{"id": "e", "status": "ready", "archivedAt": null},
	]
	eq(Quick.unlinked(roots, [{"taskId": "b"}, {"taskId": "x"}]), ["a", "e"])
