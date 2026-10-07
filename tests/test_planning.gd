extends "suite.gd"
## Planen am Tisch: Prognose, Decks, Vorrat und Schlösser.

const Schedule := preload("res://addons/tasker/rules/schedule.gd")
const Planning := preload("res://addons/tasker/rules/planning.gd")

## 2026-10-07, ein Mittwoch.
const TODAY := 20733


func _plan() -> Builder:
	var b := Builder.new() \
		.project("p") \
		.milestone("eins", "p", {"planned": true, "status": "progress"}) \
		.milestone("zwei", "p", {"planned": true}) \
		.milestone("entwurf", "p") \
		.task("a1", "p", {"milestoneId": "eins"}) \
		.task("a2", "p", {"milestoneId": "eins"}) \
		.task("a3", "p", {"milestoneId": "eins"}) \
		.task("a4", "p", {"milestoneId": "eins", "status": "done"}) \
		.task("b1", "p", {"milestoneId": "zwei"}) \
		.task("b2", "p", {"milestoneId": "zwei"})
	return b


func _by(list: Array) -> Dictionary:
	var out := {}
	for x in list:
		out[x["milestone"]["id"]] = x
	return out


func test_heute_ist_die_richtige_tagesnummer() -> void:
	eq(int(Time.get_unix_time_from_datetime_string("2026-10-07")) / 86400, TODAY)


func test_die_kalenderwoche_folgt_iso_8601() -> void:
	eq(Schedule.iso_week(TODAY), 41)
	eq(Schedule.iso_week(int(Time.get_unix_time_from_datetime_string("2021-01-03")) / 86400), 53, "Sonntag gehört zur alten Woche")
	eq(Schedule.iso_week(int(Time.get_unix_time_from_datetime_string("2024-12-30")) / 86400), 1, "Montag gehört schon zum neuen Jahr")


func test_milestones_stehen_nacheinander_und_enden_nach_dem_tempo() -> void:
	var s := _by(Schedule.schedule(_plan().build(), 2, TODAY))
	eq(s["eins"]["start"], 0.0)
	eq(s["eins"]["end"], 1.5, "drei offene Aufgaben bei zwei je Woche")
	eq(s["zwei"]["start"], 1.5)
	eq(s["zwei"]["end"], 2.5)
	ok(not s.has("entwurf"), "nur Eingeplantes")


func test_ein_startdatum_haelt_den_milestone_fest_und_ein_enddatum_kann_reissen() -> void:
	var b := _plan()
	b.data["milestones"][1]["startDate"] = "2026-10-21"
	b.data["milestones"][1]["endDate"] = "2026-10-24"
	var s := _by(Schedule.schedule(b.build(), 2, TODAY))
	eq(s["zwei"]["start"], 2.0)
	ok(s["zwei"]["fixed"] and s["zwei"]["fixed_end"])
	eq(s["zwei"]["forecast_end"], 3.0)
	ok(s["zwei"]["late"], "die Rechnung läuft über das Enddatum hinaus")


func test_wartet_eine_aufgabe_auf_einen_spaeteren_milestone_kommt_der_zuerst() -> void:
	var b := _plan()
	b.data["tasks"][0]["deps"] = ["b1"]
	var list := Schedule.schedule(b.build(), 2, TODAY)
	eq(list.map(func(x: Dictionary) -> String: return x["milestone"]["id"]), ["zwei", "eins"])
	eq(_by(list)["eins"]["deps"], ["zwei"])
	eq(_by(list)["eins"]["start"], 1.0)


func _stock() -> Workspace:
	var b := _plan() \
		.mark("idee", "p", {"emoji": "💡", "name": "Idee"}) \
		.category("grafik", "p") \
		.task("r1", "p", {"ready": true, "markId": "idee"}) \
		.task("r2", "p", {"ready": true, "categoryId": "grafik"}) \
		.task("r3", "p", {"ready": true}) \
		.task("r3kind", "p", {"parentId": "r3"}) \
		.task("u1", "p") \
		.task("g1", "p", {"groupId": "gruppe"}) \
		.task("e1", "p", {"milestoneId": "entwurf"}) \
		.task("doku", "p", {"doc": true}) \
		.task("fremd", "anderes", {"ready": true})
	b.data["groups"].append({"id": "gruppe", "version": 1, "projectId": "p", "title": "Technik", "order": 0, "archivedAt": null})
	return b.build()


func _shape(sections: Array) -> Array:
	return sections.map(func(s: Dictionary) -> Array: return [s["title"], ids(s["cards"])])


func test_die_decks_sind_die_eingeplanten_milestones() -> void:
	eq(ids(Planning.decks(_stock(), "p")), ["eins", "zwei"])


func test_ready_ist_nach_markierung_und_sonst_nach_kategorie_gegliedert() -> void:
	eq(_shape(Planning.stock(_stock(), "p", Planning.READY)), [["💡 Idee", ["r1"]], ["grafik", ["r2"]], ["Ohne Kategorie", ["r3"]]])
	eq(Planning.stock_count(_stock(), "p", Planning.READY), 3)


func test_das_backlog_ist_alles_andere_uneingeplante() -> void:
	eq(_shape(Planning.stock(_stock(), "p", Planning.BACKLOG)), [["Technik", ["g1"]], ["◆ entwurf", ["e1"]], ["Unsortiert", ["u1"]]])


func test_das_schloss_ist_gelb_wenn_die_karte_wartet_und_rot_wenn_das_ziel_spaeter_liegt() -> void:
	var b := _plan().task("lose", "p").task("a2kind", "p", {"parentId": "a2"})
	var tasks: Array = b.data["tasks"]
	var set_deps := func(id: String, deps: Array) -> void:
		for t in tasks:
			if t["id"] == id:
				t["deps"] = deps
	set_deps.call("a1", ["a4"])
	set_deps.call("a3", ["a1"])
	set_deps.call("b1", ["a1"])
	set_deps.call("a2kind", ["b2"])
	set_deps.call("b2", ["lose"])
	set_deps.call("lose", ["a3"])
	var ws: Workspace = b.build()
	var order := Planning.deck_order(Planning.decks(ws, "p"))
	eq(Planning.lock_of(ws, ws.task("a1"), order), "", "Erledigtes sperrt nicht")
	eq(Planning.lock_of(ws, ws.task("a3"), order), Planning.WAITS, "im selben Deck")
	eq(Planning.lock_of(ws, ws.task("b1"), order), Planning.WAITS, "auf ein früheres Deck")
	eq(Planning.lock_of(ws, ws.task("a2"), order), Planning.MISPLACED, "eine Unteraufgabe wartet auf ein späteres Deck")
	eq(Planning.lock_of(ws, ws.task("b2"), order), Planning.MISPLACED, "wartet auf etwas im Vorrat")
	eq(Planning.lock_of(ws, ws.task("lose"), order), Planning.WAITS, "im Vorrat wird es nie rot")
	eq(ids(Planning.card_blockers(ws, ws.task("a2"))), ["b2"])
