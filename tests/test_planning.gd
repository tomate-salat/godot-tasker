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
		.task("r1", "p", {"status": "ready", "markId": "idee"}) \
		.task("r2", "p", {"status": "ready", "categoryId": "grafik"}) \
		.task("r3", "p", {"status": "ready"}) \
		.task("r3kind", "p", {"parentId": "r3"}) \
		.task("u1", "p") \
		.task("g1", "p", {"groupId": "gruppe"}) \
		.task("e1", "p", {"milestoneId": "entwurf"}) \
		.task("doku", "p", {"doc": true}) \
		.task("fremd", "anderes", {"status": "ready"})
	b.data["groups"].append({"id": "gruppe", "version": 1, "projectId": "p", "title": "Technik", "order": 0, "archivedAt": null})
	return b.build()


func _shape(sections: Array) -> Array:
	return sections.map(func(s: Dictionary) -> Array: return [s["title"], ids(s["cards"])])


func test_die_decks_sind_die_eingeplanten_milestones() -> void:
	eq(ids(Planning.decks(_stock(), "p")), ["eins", "zwei"])


func test_der_vorrat_ist_alles_uneingeplante_bereit_oder_nicht() -> void:
	# „Bereit“ ist ein Status, kein Ort mehr: bereite lose Aufgaben liegen in „Unsortiert“.
	eq(_shape(Planning.stock(_stock(), "p")), [["Technik", ["g1"]], ["◆ entwurf", ["e1"]], ["Unsortiert", ["r1", "r2", "r3", "u1"]]])
	eq(Planning.stock_count(_stock(), "p"), 6)


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


func test_jeder_abschnitt_nennt_seinen_ort_fuer_das_verschieben() -> void:
	var ws := _stock()
	eq(Planning.stock(ws, "p").map(func(s: Dictionary) -> Dictionary: return s["place"]), [{"groupId": "gruppe"}, {"milestoneId": "entwurf"}, {"milestoneId": null, "groupId": null}])


func test_zum_hineinlegen_stehen_auch_leere_ziele_da() -> void:
	var ws: Workspace = _plan().category("ton", "p").mark("idee", "p").build()
	eq(_shape(Planning.stock(ws, "p", true)), [["◆ entwurf", []], ["Unsortiert", []]])
	eq(Planning.stock(ws, "p"), [], "ohne leere Ziele bleibt nichts")


func test_die_stelle_beim_ablegen_zaehlt_ohne_die_verschobene_karte() -> void:
	var roots := ["a", "b", "c", "d"]
	eq(Planning.drop_index(roots, "x", "c"), 2, "von außen vor c")
	eq(Planning.drop_index(roots, "x", ""), 4, "von außen ans Ende")
	eq(Planning.drop_index(roots, "a", "d"), 2, "a rückt hinter b und c")
	eq(Planning.drop_index(roots, "d", "a"), 0)
	eq(Planning.drop_index(roots, "b", ""), 3)
	ok(Planning.stays(roots, "b", Planning.drop_index(roots, "b", "c")), "vor den eigenen Nachfolger gelegt ändert nichts")
	ok(not Planning.stays(roots, "b", Planning.drop_index(roots, "b", "a")))
	ok(not Planning.stays(roots, "x", 0))
	eq(Planning.move_body({"milestoneId": "m"}, 3), {"milestoneId": "m", "index": 3})


func test_der_zug_steht_sofort_im_stand_wie_der_server_ihn_schreiben_wird() -> void:
	var local := Planning.local_move(["a", "b", "c"], "x", {"milestoneId": "m"}, 1)
	eq(local["a"], {"order": 0})
	eq(local["x"], {"order": 1, "parentId": null, "milestoneId": "m", "groupId": null})
	eq(local["b"], {"order": 2})
	eq(local["c"], {"order": 3})
	var loose := Planning.local_move(["a"], "a", Planning.LOOSE, 0)
	eq(loose["a"], {"order": 0, "parentId": null, "milestoneId": null, "groupId": null})
	eq(Planning.local_move(["a", "b"], "a", {"groupId": "g"}, 5)["a"]["order"], 1, "eine zu große Stelle heißt ans Ende")
