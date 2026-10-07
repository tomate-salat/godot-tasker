extends "suite.gd"
## Der Abhängigkeitsgraph einer Karte.

const DepGraph := preload("res://addons/tasker/rules/dep_graph.gd")
const Planning := preload("res://addons/tasker/rules/planning.gd")


## pfad ─┐
## licht ─┴→ ki (mit kikind → grund) → gegner → boss ← speicher (späteres Deck)
func _ws() -> Workspace:
	return Builder.new() \
		.project("p") \
		.milestone("eins", "p", {"planned": true, "status": "progress"}) \
		.milestone("zwei", "p", {"planned": true, "deps": ["eins"]}) \
		.milestone("entwurf", "p") \
		.task("pfad", "p") \
		.task("licht", "p", {"ready": true, "status": "done"}) \
		.task("ki", "p", {"ready": true, "deps": ["pfad", "licht"]}) \
		.task("kikind", "p", {"parentId": "ki", "deps": ["grund"]}) \
		.task("grund", "p", {"milestoneId": "eins"}) \
		.task("gegner", "p", {"milestoneId": "eins", "deps": ["ki"]}) \
		.task("boss", "p", {"milestoneId": "eins", "deps": ["gegner", "speicher"]}) \
		.task("speicher", "p", {"milestoneId": "zwei"}) \
		.task("allein", "p", {"milestoneId": "zwei"}) \
		.task("skizze", "p", {"milestoneId": "entwurf"}) \
		.build()


func _layers(graph: Dictionary) -> Dictionary:
	var out := {}
	for n in graph["nodes"]:
		out[n["item"]["id"]] = n["layer"]
	return out


func _edges(graph: Dictionary) -> Array:
	var out: Array = graph["edges"].map(func(e: Dictionary) -> String: return "%s>%s" % [e["from"], e["to"]])
	out.sort()
	return out


func test_eine_karte_wartet_auch_auf_das_was_ihre_unteraufgaben_brauchen() -> void:
	var ws := _ws()
	eq(ids(DepGraph.waits_on(ws, ws.task("ki"))), ["pfad", "licht", "grund"])
	eq(ids(DepGraph.waits_on(ws, ws.task("kikind"))), ["grund", "pfad", "licht"], "und die Unteraufgabe auf das der Karte darüber")
	eq(ids(DepGraph.waited_by(ws, ws.task("ki"))), ["gegner"])
	eq(ids(DepGraph.waited_by(ws, ws.task("grund"))), ["kikind"])


func test_der_graph_reicht_ueber_alle_stufen_in_beide_richtungen() -> void:
	var ws := _ws()
	var graph := DepGraph.build(ws, ws.task("ki"))
	eq(_layers(graph), {"ki": 0, "pfad": -1, "licht": -1, "grund": -1, "gegner": 1, "boss": 2})
	eq(_edges(graph), ["gegner>boss", "grund>ki", "ki>gegner", "licht>ki", "pfad>ki"])
	ok(not graph["cut"])


func test_von_hinten_gesehen_liegt_alles_auf_der_wartet_auf_seite() -> void:
	var ws := _ws()
	var graph := DepGraph.build(ws, ws.task("boss"))
	eq(_layers(graph), {"boss": 0, "gegner": -1, "speicher": -1, "ki": -2, "pfad": -3, "licht": -3, "grund": -3})


func test_milestones_haengen_auch_voneinander_ab() -> void:
	var ws := _ws()
	eq(_layers(DepGraph.build(ws, ws.milestone("eins"))), {"eins": 0, "zwei": 1})
	eq(_layers(DepGraph.build(ws, ws.task("allein"))), {"allein": 0})


func test_die_kante_sagt_ob_die_voraussetzung_richtig_liegt() -> void:
	var ws := _ws()
	var order := Planning.deck_order(Planning.decks(ws, "p"))
	eq(DepGraph.edge_state(ws, ws.task("licht"), ws.task("ki"), order), DepGraph.DONE)
	eq(DepGraph.edge_state(ws, ws.task("pfad"), ws.task("ki"), order), DepGraph.OK, "im Vorrat wird nichts bemängelt")
	eq(DepGraph.edge_state(ws, ws.task("gegner"), ws.task("boss"), order), DepGraph.OK)
	eq(DepGraph.edge_state(ws, ws.task("speicher"), ws.task("boss"), order), DepGraph.MISPLACED, "späteres Deck")
	eq(DepGraph.edge_state(ws, ws.task("ki"), ws.task("gegner"), order), DepGraph.MISPLACED, "noch im Vorrat")
	eq(DepGraph.edge_state(ws, ws.milestone("eins"), ws.milestone("zwei"), order), DepGraph.OK)


func test_jeder_knoten_nennt_wo_er_liegt() -> void:
	var ws := _ws()
	eq(DepGraph.place_label(ws, ws.task("ki")), "Ready")
	eq(DepGraph.place_label(ws, ws.task("kikind")), "Ready")
	eq(DepGraph.place_label(ws, ws.task("pfad")), "Backlog")
	eq(DepGraph.place_label(ws, ws.task("boss")), "◆ eins")
	eq(DepGraph.place_label(ws, ws.task("skizze")), "◆ entwurf (nicht eingeplant)")
	eq(DepGraph.place_label(ws, ws.milestone("zwei")), "Milestone")


func test_die_stufe_ist_der_laengste_weg_damit_alle_pfeile_nach_rechts_zeigen() -> void:
	# modell → generator → brett → arena, dazu modell → arena direkt.
	var ws: Workspace = Builder.new().project("p") \
		.task("modell", "p") \
		.task("generator", "p", {"deps": ["modell"]}) \
		.task("brett", "p", {"deps": ["generator"]}) \
		.task("arena", "p", {"deps": ["brett", "modell"]}) \
		.build()
	eq(_layers(DepGraph.build(ws, ws.task("arena"))), {"arena": 0, "brett": -1, "generator": -2, "modell": -3})
	eq(_layers(DepGraph.build(ws, ws.task("modell"))), {"modell": 0, "generator": 1, "brett": 2, "arena": 3})
	eq(_layers(DepGraph.build(ws, ws.task("generator"))), {"generator": 0, "modell": -1, "brett": 1, "arena": 2})


func test_ein_kreis_haelt_den_graphen_nicht_auf() -> void:
	var ws: Workspace = Builder.new().project("p") \
		.task("a", "p", {"deps": ["b"]}) \
		.task("b", "p", {"deps": ["a"]}) \
		.build()
	var layers := _layers(DepGraph.build(ws, ws.task("a")))
	eq(layers.size(), 2)
	eq(layers["a"], 0)
