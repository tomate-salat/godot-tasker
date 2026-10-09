extends "suite.gd"
## Die Fälle aus Taskers `shared/parentStatus.test.ts`, dazu die Regel fürs Zurücknehmen.

const ParentStatus := preload("res://addons/tasker/rules/parent_status.gd")
const Field := preload("res://addons/tasker/rules/field.gd")


func test_eine_unteraufgabe_in_arbeit_oder_erledigt_macht_die_offene_eltern_aufgabe_in_progress() -> void:
	eq(ParentStatus.after("open", "progress", ["progress", "open"]), "progress")
	eq(ParentStatus.after("open", "done", ["done", "open"]), "progress")


func test_alle_wieder_offen_die_eltern_aufgabe_auch() -> void:
	eq(ParentStatus.after("progress", "open", ["open", "open"]), "open")
	eq(ParentStatus.after("done", "open", ["open"]), "open")


func test_alle_erledigt_die_eltern_aufgabe_bleibt_in_arbeit() -> void:
	eq(ParentStatus.after("progress", "done", ["done", "done"]), null)
	eq(ParentStatus.after("done", "done", ["done", "done"]), null)


func test_eine_wieder_aufgemachte_unteraufgabe_zieht_die_eltern_aufgabe_aus_erledigt() -> void:
	eq(ParentStatus.after("done", "progress", ["progress", "done"]), "progress")
	eq(ParentStatus.after("done", "open", ["open", "done"]), "progress")


func test_unklar_und_blockiert_bleiben_stehen() -> void:
	eq(ParentStatus.after("unclear", "progress", ["progress"]), null)
	eq(ParentStatus.after("blocked", "open", ["open"]), null)


func test_ein_stapel_laesst_sich_nicht_auf_offen_stellen_solange_darunter_etwas_laeuft_oder_erledigt_ist() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("laeuft", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("l1", "p", {"parentId": "laeuft", "status": "progress"}) \
		.task("fertig", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("f1", "p", {"parentId": "fertig", "status": "done"}) \
		.task("tief", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("t1", "p", {"parentId": "tief"}) \
		.task("t2", "p", {"parentId": "t1", "status": "progress"}) \
		.task("ruht", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("r1", "p", {"parentId": "ruht"}) \
		.build()
	eq(Field.untap_refusal(ws, ws.task("laeuft")) != "", true)
	eq(Field.untap_refusal(ws, ws.task("fertig")) != "", true)
	# Auch eine Ebene tiefer zählt.
	eq(Field.untap_refusal(ws, ws.task("tief")) != "", true)
	eq(Field.untap_refusal(ws, ws.task("ruht")), "")
	# Eine Karte ohne Unteraufgaben lässt sich immer zurücknehmen.
	eq(Field.untap_refusal(ws, ws.task("l1")), "")
