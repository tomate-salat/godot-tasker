extends "suite.gd"
## Was eine Anweisung an Claude an Feldern einer Aufgabe ändern darf:
## `rules/task_changes.gd`.

const TaskChanges := preload("res://addons/tasker/rules/task_changes.gd")


func _ws() -> Workspace:
	return Builder.new().project("p") \
		.mark("bug", "p", {"name": "Bug"}) \
		.category("grafik", "p", {"name": "Grafik"}) \
		.milestone("kampf", "p", {"title": "Kampf"}) \
		.milestone("alt", "p", {"title": "Alt", "archivedAt": "2026-01-01"}) \
		.group("ideen", "p", {"title": "Ideen"}) \
		.task("a", "p", {"ref": 10, "title": "Dialoge", "status": "ready"}) \
		.task("b", "p", {"ref": 11, "title": "Kamera"}) \
		.task("kind", "p", {"ref": 12, "parentId": "a", "status": "open"}) \
		.task("wartet", "p", {"ref": 13, "deps": ["a"]}) \
		.build()


func test_namen_werden_zu_feldern() -> void:
	var ws := _ws()
	var got := TaskChanges.resolve(ws, "p", ws.task("a"), {"prio": "high", "mark": "bug", "category": "Grafik", "tags": ["ui", "ui", "npc"], "status": "progress"})
	eq(got["patch"], {"prio": 1, "markId": "bug", "categoryId": "grafik", "tags": ["ui", "npc"], "status": "progress"})
	eq(got["problems"], [])
	eq(got["place"], null)


func test_was_schon_so_ist_faellt_weg_und_leeres_entfernt() -> void:
	var ws := Builder.new().project("p").mark("bug", "p", {"name": "Bug"}).task("a", "p", {"markId": "bug", "prio": 2}).build()
	var got := TaskChanges.resolve(ws, "p", ws.task("a"), {"prio": "medium", "mark": ""})
	eq(got["patch"], {"markId": null})


func test_regeln_gelten_wie_in_tasker() -> void:
	var ws := _ws()
	var got := TaskChanges.resolve(ws, "p", ws.task("a"), {"status": "done", "mark": "Feature", "deps": ["$13", "$99"]})
	eq(got["patch"], {}, "nichts davon geht")
	eq(got["problems"].size(), 4, str(got["problems"]))
	ok(got["problems"][0].begins_with("Status:"), "erledigt erst, wenn die Unteraufgabe erledigt ist")


func test_abhaengigkeiten_als_nummern() -> void:
	var ws := _ws()
	var both := TaskChanges.resolve(ws, "p", ws.task("b"), {"deps": ["$10", "11"]})
	eq([both["patch"], both["problems"].size()], [{"deps": ["a"]}, 1], "auf sich selbst wartet nichts")
	eq(TaskChanges.resolve(ws, "p", ws.task("wartet"), {"deps": []})["patch"], {"deps": []}, "die ganze Liste – leer löst alle")


func test_der_ort_nach_namen() -> void:
	var ws := _ws()
	eq(TaskChanges.resolve(ws, "p", ws.task("b"), {"place": "kampf"})["place"], {"milestoneId": "kampf", "groupId": null, "parentId": null})
	eq(TaskChanges.resolve(ws, "p", ws.task("b"), {"place": "Ideen"})["place"], {"milestoneId": null, "groupId": "ideen", "parentId": null})
	eq(TaskChanges.resolve(ws, "p", ws.task("b"), {"place": "Backlog"})["place"], null, "liegt schon dort")
	eq(TaskChanges.resolve(ws, "p", ws.task("kind"), {"place": "Backlog"})["place"], {"milestoneId": null, "groupId": null, "parentId": null}, "aus dem Stapel heraus")
	var gone := TaskChanges.resolve(ws, "p", ws.task("b"), {"place": "Alt"})
	eq([gone["place"], gone["problems"].size()], [null, 1], "archivierte Milestones nicht")


func test_claude_erfaehrt_stand_und_wahl() -> void:
	var ws := _ws()
	var text := TaskChanges.facts(ws, "p", ws.task("a"))
	for part in ["Status: ready", "„Bug“", "„Grafik“", "Kampf", "Ideen", "Backlog", "$12"]:
		ok(text.contains(part), part)
	ok(not text.contains("Alt"), "archivierte Milestones stehen nicht zur Wahl")


func test_die_antwort_wird_geprueft() -> void:
	var got := TaskChanges.parse({"changes": {"prio": "high", "tags": ["a", " ", 3], "status": 5}, "subtasks": [{"title": " Add NPC "}, {"title": ""}, "quatsch"]})
	eq(got["changes"], {"prio": "high", "tags": ["a", "3"]})
	eq(got["subtasks"], [{"title": "Add NPC", "desc": "", "links": []}])


func test_unteraufgaben_lassen_sich_verteilen() -> void:
	var got := TaskChanges.parse({
		"subtasks": [{"title": "Repair", "links": [{"scene": "res://cell.tscn", "paths": ["Repair Npc"]}]}],
		"kid_links": [{"task": "$528", "scene": "res://cell.tscn", "paths": ["./Shop Npc"]}, {"task": "", "scene": "res://cell.tscn", "paths": ["X"]}, {"task": "$529", "scene": "kaputt", "paths": ["Y"]}],
	})
	eq(got["subtasks"][0]["links"], [{"scene": "res://cell.tscn", "paths": ["Repair Npc"]}])
	eq(got["kid_links"], [{"task": "$528", "scene": "res://cell.tscn", "paths": ["Shop Npc"]}])
