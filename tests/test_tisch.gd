extends "suite.gd"
## Die Fälle aus Taskers `shared/tisch.test.ts`, damit beide Seiten dieselben
## Regeln spielen.

const Tisch := preload("res://addons/tasker/rules/tisch.gd")

## Die Ablage-Tests rechnen in Sommerzeit (UTC+2), unabhängig vom Gerät.
const TZ := 120


func test_aktiv_ist_der_milestone_auf_in_progress_bei_mehreren_der_oberste_im_plan() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m1", "p", {"planned": true, "qorder": 2, "status": "progress"}) \
		.milestone("m2", "p", {"planned": true, "qorder": 1, "status": "progress"}) \
		.milestone("m3", "p", {"status": "progress"}) \
		.build()
	eq(Tisch.active_milestone(ws, "p")["id"], "m2")
	eq(Tisch.progress_locked_by(ws, ws.milestone("m1"))["id"], "m2")


func test_ohne_anderen_aktiven_milestone_ist_in_progress_frei() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.project("q") \
		.milestone("m1", "p", {"status": "progress"}) \
		.milestone("m2", "q") \
		.milestone("m3", "p", {"status": "progress", "archivedAt": "2026-01-01T00:00:00Z"}) \
		.build()
	eq(Tisch.progress_locked_by(ws, ws.milestone("m2")), null)
	eq(Tisch.progress_locked_by(ws, ws.milestone("m1")), null)


func test_verteilt_die_karten_auf_die_zonen() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("frei", "p", {"milestoneId": "m"}) \
		.task("unklar", "p", {"milestoneId": "m", "status": "unclear"}) \
		.task("wartet", "p", {"milestoneId": "m", "deps": ["frei"]}) \
		.task("blockiert", "p", {"milestoneId": "m", "status": "blocked"}) \
		.task("läuft", "p", {"milestoneId": "m", "status": "progress", "deps": ["frei"]}) \
		.task("fertig", "p", {"milestoneId": "m", "status": "done", "doneAt": "2026-09-01T00:00:00Z"}) \
		.build()
	var l := Tisch.layout(ws, ws.milestone("m"))
	eq(ids(l["open"]), ["frei", "unklar"], "open")
	eq(ids(l["locked"]), ["wartet", "blockiert"], "locked")
	eq(ids(l["play"]), ["läuft"], "play")
	eq(ids(l["pile"]), ["fertig"], "pile")


func test_ein_stapel_bleibt_in_der_mitte_seine_unteraufgaben_kommen_ins_spiel() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("stapel", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("a", "p", {"parentId": "stapel", "status": "progress"}) \
		.task("b", "p", {"parentId": "stapel"}) \
		.task("unter", "p", {"parentId": "stapel", "status": "progress"}) \
		.task("c", "p", {"parentId": "unter", "status": "progress"}) \
		.build()
	var l := Tisch.layout(ws, ws.milestone("m"))
	eq(ids(l["open"]), ["stapel"], "open")
	eq(ids(l["play"]), ["a", "c"], "play")


func test_im_spiel_gilt_die_reihenfolge_von_hand_bei_gleichstand_die_des_baums() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "progress", "playOrder": 2}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("b", "p", {"parentId": "stapel", "status": "progress", "playOrder": 1}) \
		.task("c", "p", {"milestoneId": "m", "status": "progress", "playOrder": 2}) \
		.build()
	eq(ids(Tisch.layout(ws, ws.milestone("m"))["play"]), ["b", "a", "c"])


func test_der_erledigt_stapel_zeigt_das_zuletzt_erledigte_zuerst_jeder_ebene() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("alt", "p", {"milestoneId": "m", "status": "done", "doneAt": "2026-09-01T00:00:00Z"}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("neu", "p", {"parentId": "stapel", "status": "done", "doneAt": "2026-09-03T00:00:00Z"}) \
		.build()
	eq(ids(Tisch.layout(ws, ws.milestone("m"))["pile"]), ["neu", "alt"])


func test_gerade_erst_erledigt_noch_ohne_zeitpunkt_liegt_obenauf() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("alt", "p", {"milestoneId": "m", "status": "done", "doneAt": "2026-09-01T00:00:00Z"}) \
		.task("eben", "p", {"milestoneId": "m", "status": "done", "doneAt": null}) \
		.build()
	eq(ids(Tisch.layout(ws, ws.milestone("m"))["pile"]), ["eben", "alt"])


func test_gesperrte_und_stapel_duerfen_nicht_ins_spiel() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.task("a", "p") \
		.task("b", "p", {"deps": ["a"]}) \
		.task("stapel", "p") \
		.task("kind", "p", {"parentId": "stapel"}) \
		.build()
	eq(Tisch.play_refusal(ws, ws.task("a")), "")
	ok(Tisch.play_refusal(ws, ws.task("b")) != "", "gesperrt")
	ok(Tisch.play_refusal(ws, ws.task("stapel")) != "", "stapel")


func test_ein_stapel_darf_erst_auf_den_erledigt_stapel_wenn_alles_darunter_erledigt_ist() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.task("offen", "p") \
		.task("k1", "p", {"parentId": "offen", "status": "done"}) \
		.task("k2", "p", {"parentId": "offen"}) \
		.task("fertig", "p") \
		.task("k3", "p", {"parentId": "fertig", "status": "done"}) \
		.task("liste", "p", {"desc": "- [x] eins\n- [ ] zwei"}) \
		.build()
	ok(Tisch.done_refusal(ws, ws.task("offen")) != "", "offen")
	eq(Tisch.done_refusal(ws, ws.task("fertig")), "")
	ok(Tisch.done_refusal(ws, ws.task("liste")) != "", "liste")
	eq(Tisch.stack_ready(ws, ws.task("fertig")), true)
	eq(Tisch.stack_ready(ws, ws.task("offen")), false)


# ---------------------------------------------------------------- Ablage

## Ortszeit (UTC+2) im Jahr 2026 als Sekunden seit 1970.
func _unix(month: int, day: int, hour := 12) -> float:
	return float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": month, "day": day, "hour": hour, "minute": 0, "second": 0})) - TZ * 60


## Dieselbe Ortszeit als ISO-Text in UTC, wie ihn der Server schickt.
func _on(month: int, day: int, hour := 12) -> String:
	return Time.get_datetime_string_from_unix_time(int(_unix(month, day, hour))) + ".000Z"


func test_die_woche_beginnt_am_montag_auch_am_sonntag_und_ueber_den_monatswechsel() -> void:
	# Mittwoch, 07.10.2026 – die Woche beginnt am Montag, 05.10.
	eq(Tisch.week_start(_unix(10, 7), TZ), "2026-10-05")
	eq(Tisch.week_start(_unix(10, 4, 23), TZ), "2026-09-28")
	eq(Tisch.week_start(_unix(10, 5, 0), TZ), "2026-10-05")


func test_legt_erledigtes_je_woche_ab_das_juengste_zuerst_und_zaehlt_nur_karten_ohne_unteraufgaben() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("offen", "p", {"milestoneId": "m"}) \
		.task("stapel", "p", {"milestoneId": "m", "status": "done", "doneAt": _on(10, 6, 15)}) \
		.task("k1", "p", {"parentId": "stapel", "status": "done", "doneAt": _on(10, 6, 14)}) \
		.task("k2", "p", {"parentId": "stapel", "status": "done", "doneAt": _on(9, 30)}) \
		.task("alt", "p", {"milestoneId": "m", "status": "done", "doneAt": _on(9, 29)}) \
		.task("älter", "p", {"milestoneId": "m", "status": "done", "doneAt": _on(9, 15)}) \
		.task("eben", "p", {"milestoneId": "m", "status": "done", "doneAt": null}) \
		.build()
	var s := Tisch.done_shelf(ws, ws.milestone("m"), _unix(10, 7), TZ)
	var rows := []
	for w in s["weeks"]:
		rows.append([w["start"], ids(w["cards"]), w["count"], w["current"], w["best"]])
	eq(rows, [
		["2026-10-05", ["eben", "stapel", "k1"], 2, true, true],
		["2026-09-28", ["k2", "alt"], 2, false, false],
		["2026-09-14", ["älter"], 1, false, false],
	])
	eq(s["this_week"], 2)
	# 05.10. und 28.09. – die Woche ab 21.09. ist leer.
	eq(s["streak"], 2)


func test_die_laufende_woche_bricht_die_serie_nicht_und_erledigt_archiviertes_bleibt_liegen() -> void:
	var b: Builder = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "done", "doneAt": _on(9, 29)}) \
		.task("b", "p", {"milestoneId": "m", "status": "done", "doneAt": _on(9, 22)})
	var archiviert: Dictionary = b.data["tasks"][1].duplicate()
	archiviert.merge({"id": "weg", "title": "weg", "doneAt": _on(9, 23), "archivedAt": _on(10, 1)}, true)
	var data: Dictionary = b.data.duplicate()
	data["archivedTasks"] = [archiviert]
	var ws := Workspace.new(data)
	var s := Tisch.done_shelf(ws, ws.milestone("m"), _unix(10, 7), TZ)
	var cards := []
	for w in s["weeks"]:
		cards.append(ids(w["cards"]))
	eq(cards, [["a"], ["weg", "b"]])
	eq(s["weeks"][1]["best"], true)
	eq(s["this_week"], 0)
	eq(s["streak"], 2)
