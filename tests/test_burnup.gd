extends "suite.gd"
## Burnup: aus dem Protokoll des Servers wird die Kurve je Tag.

const Burnup := preload("res://addons/tasker/rules/burnup.gd")

## Gerechnet wird in Sommerzeit (UTC+2), unabhängig vom Gerät.
const TZ := 120


## Mittags Ortszeit an diesem Tag im Oktober 2026.
func _noon(day: int) -> float:
	return float(Time.get_unix_time_from_datetime_dict({"year": 2026, "month": 10, "day": day, "hour": 12, "minute": 0, "second": 0})) - TZ * 60


func _milestone(o := {}) -> Dictionary:
	var m := {"id": "m", "status": "progress", "startDate": "2026-10-01", "endDate": null}
	m.merge(o, true)
	return m


func test_ohne_start_oder_mit_kuenftigem_start_gibt_es_keine_kurve() -> void:
	eq(Burnup.data(_milestone({"startDate": null}), [], 7, _noon(7), TZ), null)
	eq(Burnup.data(_milestone({"startDate": "2026-10-20"}), [], 7, _noon(7), TZ), null)


func test_je_tag_gilt_der_letzte_stand_auch_ueber_mitternacht_in_ortszeit() -> void:
	var log := [
		{"at": "1970-01-01T00:00:00.000Z", "s": 10, "dn": 0},
		{"at": "2026-10-02T09:00:00.000Z", "s": 10, "dn": 2},
		{"at": "2026-10-02T15:00:00.000Z", "s": 12, "dn": 3},
		# 22:30 UTC ist in Ortszeit schon der 4. Oktober.
		{"at": "2026-10-03T22:30:00.000Z", "s": 11, "dn": 5},
	]
	var d = Burnup.data(_milestone(), log, 7, _noon(5), TZ)
	eq(d["scope"], [10, 12, 12, 11, 11])
	eq(d["done_s"], [0, 3, 3, 5, 5])
	eq(d["today_i"], 4)
	eq(d["s"], 11)
	eq(d["dn"], 5)
	eq(d["added"], 2)
	eq(d["removed"], 1)


func test_die_prognose_rechnet_das_offene_mit_dem_tempo_hoch() -> void:
	var log := [{"at": "1970-01-01T00:00:00.000Z", "s": 15, "dn": 8}]
	var d = Burnup.data(_milestone({"endDate": "2026-10-09"}), log, 7, _noon(7), TZ)
	eq(d["open"], 7)
	# Sieben offene Aufgaben bei sieben pro Woche: eine Woche ab heute (Tag 6).
	eq(d["fc_i"], 13.0)
	eq(d["dead_i"], 8)
	eq(d["max_i"], 13.0)


func test_ein_erledigter_milestone_endet_am_enddatum_und_hat_keine_prognose() -> void:
	var log := [{"at": "1970-01-01T00:00:00.000Z", "s": 4, "dn": 4}]
	var d = Burnup.data(_milestone({"status": "done", "endDate": "2026-10-03"}), log, 7, _noon(7), TZ)
	eq(d["end_i"], 2)
	eq(d["fc_i"], null)
	eq(d["scope"].size(), 3)


func test_ohne_protokoll_entsteht_es_aus_den_abschlusszeitpunkten() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p") \
		.task("a", "p", {"milestoneId": "m", "status": "done", "doneAt": "2026-10-02T10:00:00.000Z"}) \
		.task("b", "p", {"milestoneId": "m", "status": "done", "doneAt": null}) \
		.task("c", "p", {"milestoneId": "m"}) \
		.build()
	eq(Burnup.backfill_log(ws, ws.milestone("m")), [
		{"at": "1970-01-01T00:00:00.000Z", "s": 3, "dn": 1},
		{"at": "2026-10-02T10:00:00.000Z", "s": 3, "dn": 2},
	])


func test_der_aktuelle_stand_kommt_nur_dazu_wenn_er_abweicht() -> void:
	var log := [{"at": "2026-10-02T10:00:00.000Z", "s": 3, "dn": 2}]
	eq(Burnup.with_now(log, 3, 2, "jetzt").size(), 1)
	eq(Burnup.with_now(log, 3, 3, "jetzt")[1], {"at": "jetzt", "s": 3, "dn": 3})


func test_tage_werden_deutsch_geschrieben() -> void:
	eq(Burnup.format_day(Burnup.day_of_date("2026-10-09")), "09.10.")
	eq(Burnup.format_day(Burnup.day_of_date("2026-10-09"), true), "09.10.2026")
