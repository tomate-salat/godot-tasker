extends "suite.gd"
## Abhängigkeiten anlegen und lösen: die Regeln aus `rules/dependency.gd`.

const Dependency := preload("res://addons/tasker/rules/dependency.gd")


func _ws() -> Workspace:
	return Builder.new().project("p").milestone("m", "p") \
		.task("a", "p", {"milestoneId": "m", "title": "A"}) \
		.task("b", "p", {"milestoneId": "m", "title": "B", "deps": ["a"]}) \
		.task("c", "p", {"milestoneId": "m", "title": "C", "deps": ["b"]}) \
		.task("frei", "p", {"milestoneId": "m"}) \
		.task("kind", "p", {"parentId": "frei"}) \
		.build()


func test_eine_freie_aufgabe_kann_auf_eine_andere_warten() -> void:
	var ws := _ws()
	eq(Dependency.link_refusal(ws, ws.task("frei"), ws.task("a")), "")
	eq(Dependency.with_dep(ws.task("frei"), "a"), ["a"])


func test_doppelt_und_auf_sich_selbst_geht_nicht() -> void:
	var ws := _ws()
	eq(Dependency.link_refusal(ws, ws.task("b"), ws.task("a")), "Wartet schon darauf")
	ok(Dependency.link_refusal(ws, ws.task("a"), ws.task("a")) != "")
	# Doppelt eingetragen wird auch dann nichts.
	eq(Dependency.with_dep(ws.task("b"), "a"), ["a"])


func test_ein_kreis_wird_abgelehnt_auch_ueber_mehrere_stufen() -> void:
	var ws := _ws()
	eq(Dependency.link_refusal(ws, ws.task("a"), ws.task("b")), "Das ergäbe einen Kreis: „B“ wartet schon auf „A“")
	eq(Dependency.link_refusal(ws, ws.task("a"), ws.task("c")), "Das ergäbe einen Kreis: „C“ wartet schon auf „A“")


func test_stapel_und_unteraufgabe_bekommen_keine_abhaengigkeit() -> void:
	var ws := _ws()
	ok(Dependency.link_refusal(ws, ws.task("kind"), ws.task("frei")) != "")
	ok(Dependency.link_refusal(ws, ws.task("frei"), ws.task("kind")) != "")


func test_loesen_nimmt_genau_die_eine_heraus() -> void:
	var ws: Workspace = Builder.new().project("p").task("x", "p", {"deps": ["a", "b"]}).build()
	eq(Dependency.without_dep(ws.task("x"), "a"), ["b"])
	eq(Dependency.without_dep(ws.task("x"), "fremd"), ["a", "b"])
