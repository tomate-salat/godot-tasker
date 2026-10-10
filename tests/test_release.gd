extends "suite.gd"
## Releases liest das Addon nur; der Stand folgt Taskers `shared/release.ts`,
## der Feldzug (`rules/campaign.gd`) ist eine Sache des Addons.

const Release := preload("res://addons/tasker/rules/release.gd")
const Campaign := preload("res://addons/tasker/rules/campaign.gd")


func _node(campaign: Dictionary, id: String) -> Dictionary:
	for n in campaign["nodes"]:
		if n["id"] == id:
			return n
	return {}


func _pairs(list: Array) -> Array:
	var out: Array = list.map(func(w: Dictionary) -> String: return "%s>%s" % [w["from"], w["to"]])
	out.sort()
	return out


func test_ohne_begonnenes_ist_ein_release_geplant() -> void:
	var ws: Workspace = Builder.new().project("p").release("r", "p").milestone("m", "p", {"releaseId": "r"}).task("t", "p", {"milestoneId": "m"}).build()
	eq(Release.status(ws, ws.release("r")), "planned")


func test_ein_aktiver_milestone_macht_das_release_zu_in_arbeit() -> void:
	var ws: Workspace = Builder.new().project("p").release("r", "p") \
		.milestone("m", "p", {"releaseId": "r", "status": "progress"}).task("t", "p", {"milestoneId": "m"}).build()
	eq(Release.status(ws, ws.release("r")), "progress")


func test_sind_alle_milestones_fertig_ist_das_release_bereit() -> void:
	var ws: Workspace = Builder.new().project("p").release("r", "p").stage("s", "r") \
		.milestone("m", "p", {"releaseId": "r", "status": "done"}).build()
	eq(Release.status(ws, ws.release("r")), "ready")


func test_sind_alle_kanaele_abgehakt_ist_es_veroeffentlicht() -> void:
	var ws: Workspace = Builder.new().project("p").release("r", "p").stage("s", "r", {"doneAt": 5}) \
		.milestone("m", "p", {"releaseId": "r", "status": "progress"}).build()
	eq(Release.status(ws, ws.release("r")), "released")


func test_aktiv_ist_das_erste_unveroeffentlichte_release_mit_aktivem_milestone() -> void:
	var ws: Workspace = Builder.new().project("p") \
		.release("alt", "p").stage("s", "alt", {"doneAt": 5}).milestone("a", "p", {"releaseId": "alt", "status": "done"}) \
		.release("geplant", "p").milestone("g", "p", {"releaseId": "geplant"}) \
		.release("laufend", "p").milestone("l", "p", {"releaseId": "laufend", "status": "progress"}) \
		.release("leer", "p") \
		.build()
	eq(Release.active(ws, "p")["id"], "laufend")


func test_ohne_aktiven_milestone_ist_es_das_erste_unveroeffentlichte() -> void:
	var ws: Workspace = Builder.new().project("p") \
		.release("leer", "p") \
		.release("geplant", "p").milestone("g", "p", {"releaseId": "geplant"}) \
		.build()
	eq(Release.active(ws, "p")["id"], "geplant")
	eq(Release.active(ws, "anderes"), null)


func test_was_ein_milestone_des_releases_braucht_zaehlt_mit_dazu() -> void:
	var ws: Workspace = Builder.new().project("p").project("q") \
		.release("erstes", "p").release("zweites", "p") \
		.milestone("a", "p", {"releaseId": "erstes", "deps": ["b", "fremd"]}) \
		.milestone("b", "p", {"deps": ["c"]}) \
		.milestone("c", "p") \
		.milestone("z", "p", {"releaseId": "zweites", "deps": ["c", "eigen"]}) \
		.milestone("eigen", "p", {"releaseId": "erstes"}) \
		.milestone("fremd", "q") \
		.milestone("lose", "p") \
		.build()
	var ids := func(release_id: String) -> Array:
		var out: Array = ws.release_milestones(release_id).map(func(m: Dictionary) -> String: return m["id"])
		out.sort()
		return out
	# Über die ganze Kette, aber nicht über die Projektgrenze; die ausdrückliche Zuordnung geht vor.
	eq(ids.call("erstes"), ["a", "b", "c", "eigen"])
	eq(ids.call("zweites"), ["z"])
	eq(ws.release_of(ws.milestone("c"))["id"], "erstes")
	eq(ws.release_of(ws.milestone("lose")), null)


func test_im_feldzug_liegt_weiter_aussen_was_ein_milestone_braucht() -> void:
	var ws: Workspace = Builder.new().project("p").release("r", "p") \
		.milestone("grund", "p", {"releaseId": "r", "status": "done"}) \
		.milestone("mitte", "p", {"releaseId": "r", "status": "progress", "deps": ["grund"]}) \
		.milestone("frei", "p", {"releaseId": "r"}) \
		.milestone("fremd", "p") \
		.task("t1", "p", {"milestoneId": "mitte", "status": "progress"}) \
		.task("t2", "p", {"milestoneId": "mitte"}) \
		.task("t3", "p", {"milestoneId": "frei"}) \
		.build()
	var campaign := Campaign.build(ws, ws.release("r"))
	eq(campaign["nodes"].size(), 3)
	eq([_node(campaign, "mitte")["ring"], _node(campaign, "grund")["ring"], _node(campaign, "frei")["ring"]], [1, 2, 1])
	eq(_node(campaign, "grund")["inner"], "mitte")
	eq([_node(campaign, "grund")["state"], _node(campaign, "mitte")["state"], _node(campaign, "frei")["state"]], ["done", "active", "planned"])
	eq(_node(campaign, "mitte")["fights"], 1)
	eq(_pairs(campaign["ways"]), ["frei>", "grund>mitte", "mitte>"])
	# Nur der aktive Milestone greift an.
	eq(_pairs(campaign["attacks"]), ["mitte>"])
	eq(campaign["front"], 1)
	eq(campaign["boss"], {"total": 3, "done": 0})
