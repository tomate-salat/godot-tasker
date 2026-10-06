extends "suite.gd"
## Die übrigen portierten Regeln: Checkliste, Fortschritt, Sperren, Titelbild.

const Checklist := preload("res://addons/tasker/rules/checklist.gd")
const Progress := preload("res://addons/tasker/rules/progress.gd")
const Blocking := preload("res://addons/tasker/rules/blocking.gd")
const Inherit := preload("res://addons/tasker/rules/inherit.gd")
const Model := preload("res://addons/tasker/rules/model.gd")


func test_checkliste_zaehlt_punkte_aber_nicht_in_code_bloecken() -> void:
	var text := "- [x] eins\n* [ ] zwei\n1. [X] drei\n```\n- [ ] im Code\n```\n  - [ ] eingerückt\nkein [ ] Punkt"
	eq(Checklist.count(text), {"total": 4, "done": 2})
	eq(Checklist.count(null), {"total": 0, "done": 0})


func test_checkliste_schaltet_einen_punkt_um() -> void:
	eq(Checklist.toggle_item("- [ ] a\n- [x] b", 0), "- [x] a\n- [x] b")
	eq(Checklist.toggle_item("- [ ] a\n- [x] b", 1), "- [ ] a\n- [ ] b")
	eq(Checklist.toggle_item("- [ ] a", 5), "- [ ] a")


func test_stabile_sortierung_behaelt_die_reihenfolge_bei_gleichstand() -> void:
	var list := [{"id": "a", "k": 1}, {"id": "b", "k": 0}, {"id": "c", "k": 1}, {"id": "d", "k": 0}]
	var sorted := Model.stable_sort(list, func(x: Dictionary, y: Dictionary) -> bool: return x["k"] < y["k"])
	eq(ids(sorted), ["b", "d", "a", "c"])


func test_fortschritt_zaehlt_blaetter_und_erledigte_stapel_voll() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.task("stapel", "p") \
		.task("a", "p", {"parentId": "stapel", "status": "done"}) \
		.task("b", "p", {"parentId": "stapel"}) \
		.task("unter", "p", {"parentId": "stapel", "status": "done"}) \
		.task("c", "p", {"parentId": "unter"}) \
		.task("d", "p", {"parentId": "unter"}) \
		.build()
	eq(Progress.total(ws, ws.task("stapel")), 4)
	eq(Progress.done_count(ws, ws.task("stapel")), 3)
	eq(Progress.all_done(ws, ws.task("stapel")), false)
	eq(Progress.status_segments(ws, ws.task("stapel")).size(), 4)


func test_milestone_fortschritt_rechnet_checklisten_anteilig() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p") \
		.task("a", "p", {"milestoneId": "m", "status": "done"}) \
		.task("b", "p", {"milestoneId": "m", "desc": "- [x] eins\n- [ ] zwei"}) \
		.build()
	var stats := Progress.milestone_stats(ws, ws.milestone("m"))
	eq(stats["total"], 2)
	eq(stats["done"], 1)
	eq(Progress.milestone_progress_pct(ws, ws.milestone("m")), 75)
	eq(Progress.milestone_done(ws, ws.milestone("m")), false)


func test_sperren_vererben_sich_auf_unteraufgaben_und_loesen_sich_mit_dem_blocker() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.task("vor", "p") \
		.task("stapel", "p", {"deps": ["vor"]}) \
		.task("kind", "p", {"parentId": "stapel"}) \
		.task("frei", "p", {"deps": ["erledigt"]}) \
		.task("erledigt", "p", {"status": "done"}) \
		.build()
	eq(Blocking.is_blocked(ws, ws.task("stapel")), true)
	eq(Blocking.is_blocked(ws, ws.task("kind")), true, "geerbt")
	eq(ids(Blocking.blockers(ws, ws.task("kind"))), ["vor"])
	eq(Blocking.is_blocked(ws, ws.task("frei")), false, "Blocker erledigt")


func test_ein_task_wartet_auf_einen_milestone_bis_dessen_aufgaben_erledigt_sind() -> void:
	var b: Builder = Builder.new() \
		.project("p") \
		.milestone("m", "p") \
		.task("drin", "p", {"milestoneId": "m"}) \
		.task("wartet", "p", {"deps": ["m"]})
	eq(Blocking.is_blocked(b.build(), b.data["tasks"][1]), true)
	b.data["tasks"][0]["status"] = "done"
	eq(Blocking.is_blocked(b.build(), b.data["tasks"][1]), false)


func test_abhaengigkeit_ueber_umwege_wird_erkannt() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.task("a", "p", {"deps": ["b"]}) \
		.task("b", "p", {"deps": ["c"]}) \
		.task("c", "p") \
		.build()
	eq(Blocking.depends_on(ws, ws.task("a"), "c"), true)
	eq(Blocking.depends_on(ws, ws.task("c"), "a"), false)


func test_titelbild_folgt_der_kette_task_markierung_kategorie_projekt() -> void:
	var ws: Workspace = Builder.new() \
		.project("p", {"coverImageId": "bild-projekt"}) \
		.category("kat", "p", {"coverImageId": "bild-kategorie"}) \
		.mark("mk", "p", {"coverImageId": "bild-markierung"}) \
		.task("nur-projekt", "p") \
		.task("mit-kategorie", "p", {"categoryId": "kat"}) \
		.task("mit-beidem", "p", {"categoryId": "kat", "markId": "mk"}) \
		.task("eigenes", "p", {"categoryId": "kat", "coverImageId": "bild-task"}) \
		.task("kind", "p", {"parentId": "eigenes"}) \
		.task("enkel", "p", {"parentId": "mit-kategorie"}) \
		.build()
	eq(Inherit.effective_cover(ws, ws.task("nur-projekt")), {"image_id": "bild-projekt", "from": "project"})
	eq(Inherit.effective_cover(ws, ws.task("mit-kategorie"))["image_id"], "bild-kategorie")
	eq(Inherit.effective_cover(ws, ws.task("mit-beidem"))["image_id"], "bild-markierung")
	eq(Inherit.effective_cover(ws, ws.task("eigenes"))["image_id"], "bild-task")
	eq(Inherit.effective_cover(ws, ws.task("kind"))["image_id"], "bild-task", "vom Elternteil")
	eq(Inherit.effective_cover(ws, ws.task("enkel"))["image_id"], "bild-kategorie", "Kategorie geerbt")


func test_ohne_bild_gibt_es_kein_titelbild() -> void:
	var ws: Workspace = Builder.new().project("p").task("a", "p").build()
	eq(Inherit.effective_cover(ws, ws.task("a")), null)


func test_suche_findet_nach_nummer_titel_label_und_beschreibung_in_dieser_reihenfolge() -> void:
	var Search := preload("res://addons/tasker/rules/search.gd")
	var ws: Workspace = Builder.new() \
		.project("p") \
		.project("q") \
		.task("beschreibung", "p", {"title": "Menü", "desc": "Der Sprung fehlt"}) \
		.task("label", "p", {"title": "Physik", "tags": ["sprung"]}) \
		.task("mitte", "p", {"title": "Wandsprung"}) \
		.task("anfang", "p", {"title": "Sprung über Kisten"}) \
		.task("fertig", "p", {"title": "Sprung testen", "status": "done"}) \
		.task("fremd", "q", {"title": "Sprung im anderen Projekt"}) \
		.task("weg", "p", {"title": "Sprung archiviert", "archivedAt": "2026-01-01T00:00:00Z"}) \
		.build()
	eq(ids(Search.find(ws, "p", "sprung")), ["anfang", "fertig", "mitte", "label", "beschreibung"])
	eq(ids(Search.find(ws, "p", "SPRUNG kisten")), ["anfang"], "alle Wörter")
	eq(ids(Search.find(ws, "p", "$%d" % ws.task("label")["ref"])), ["label"], "Nummer")
	eq(ids(Search.find(ws, "p", "   ")), [], "leer")
	eq(Search.find(ws, "p", "sprung", 2).size(), 2, "Grenze")
