extends "suite.gd"
## Das Feld gibt es nur im Addon; die Regeln stehen in `rules/field.gd`.

const Field := preload("res://addons/tasker/rules/field.gd")


func _node(field: Dictionary, id: String) -> Dictionary:
	for n in field["nodes"]:
		if n["id"] == id:
			return n
	return {}


func _ways(field: Dictionary) -> Array:
	var out: Array = field["ways"].map(func(w: Dictionary) -> String: return "%s>%s" % [w["from"], w["to"]])
	out.sort()
	return out


func test_innen_liegt_woran_nichts_haengt_voraussetzungen_liegen_weiter_aussen() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m"}) \
		.task("b", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.task("c", "p", {"milestoneId": "m", "deps": ["b"]}) \
		.task("frei", "p", {"milestoneId": "m"}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq([_node(field, "c")["ring"], _node(field, "b")["ring"], _node(field, "a")["ring"], _node(field, "frei")["ring"]], [1, 2, 3, 1])
	eq([_node(field, "a")["inner"], _node(field, "b")["inner"], _node(field, "c")["inner"]], ["b", "c", ""])


func test_von_jeder_karte_fuehrt_ein_weg_zur_mitte() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m"}) \
		.task("b", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.task("frei", "p", {"milestoneId": "m"}) \
		.build()
	eq(_ways(Field.build(ws, ws.milestone("m"))), ["a>b", "b>", "frei>"])


func test_umwege_werden_nicht_eigens_gezeichnet() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m"}) \
		.task("b", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.task("c", "p", {"milestoneId": "m", "deps": ["a", "b"]}) \
		.build()
	eq(_ways(Field.build(ws, ws.milestone("m"))), ["a>b", "b>c", "c>"])


func test_unteraufgaben_liegen_einen_ring_weiter_aussen_als_ihr_stapel() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("s1", "p", {"parentId": "stapel"}) \
		.task("s2", "p", {"parentId": "stapel", "deps": ["s1"]}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq([_node(field, "stapel")["ring"], _node(field, "s2")["ring"], _node(field, "s1")["ring"]], [1, 2, 3])
	eq(_node(field, "s1")["inner"], "s2")
	eq(_ways(field), ["s1>s2", "s2>stapel", "stapel>"])


func test_die_form_bleibt_wenn_eine_voraussetzung_erledigt_ist() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "done"}) \
		.task("b", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq(_node(field, "a")["ring"], 2)
	eq(field["pests"].has("b"), false)


func test_fuer_alles_was_fehlt_sitzt_ein_schaedling_auf_der_karte() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m"}) \
		.task("b", "p", {"milestoneId": "m", "status": "done"}) \
		.task("ziel", "p", {"milestoneId": "m", "deps": ["a", "b"]}) \
		.task("k1", "p", {"parentId": "ziel"}) \
		.task("k2", "p", {"parentId": "ziel", "status": "done"}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	# Die offene Voraussetzung und die offene Unteraufgabe.
	eq(field["pests"]["ziel"].map(func(p: Dictionary) -> String: return p["blocker_id"]), ["a", "k1"])


func test_eine_getappte_karte_schickt_ihren_marienkaefer_zu_jedem_schaedling_den_sie_stellt() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("x", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.task("y", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq(field["fronts"]["a"].map(func(f: Dictionary) -> String: return f["on"]), ["x", "y"])
	eq(field["pests"]["x"][0]["engaged"], true)


func test_im_innersten_ring_geht_der_marienkaefer_zum_grossen_kaefer() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "progress"}) \
		.task("b", "p", {"milestoneId": "m", "status": "done"}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq(field["fronts"]["a"], [])
	eq(field["boss"], {"total": 2, "done": 1})


func test_eine_unteraufgabe_in_arbeit_greift_ihren_schaedling_auf_dem_stapel_an() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("s1", "p", {"parentId": "stapel", "status": "progress"}) \
		.task("s2", "p", {"parentId": "stapel", "status": "done"}) \
		.task("ziel", "p", {"milestoneId": "m", "deps": ["stapel"]}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq(field["fronts"]["s1"], [{"on": "stapel", "blocker_id": "s1"}])
	# Am Stapel wird gearbeitet: sein Schädling auf dem Ziel merkt es, und eine
	# von zwei Unteraufgaben ist erledigt.
	eq(field["pests"]["ziel"][0]["engaged"], true)
	eq(field["pests"]["ziel"][0]["damage"], 0.5)


func test_abgehakte_kaestchen_setzen_dem_schaedling_zu() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "progress", "desc": "- [x] eins\n- [ ] zwei\n- [ ] drei\n- [ ] vier"}) \
		.task("ziel", "p", {"milestoneId": "m", "deps": ["a"]}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq(field["pests"]["ziel"][0]["damage"], 0.25)


func test_blockiert_ist_eine_mauer_an_der_keine_andere_karte_etwas_aendert() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m", "status": "blocked"}) \
		.build()
	var field := Field.build(ws, ws.milestone("m"))
	eq(field["pests"]["a"].size(), 1)
	eq(field["pests"]["a"][0]["wall"], true)
	eq(Field.tap_refusal(ws, ws.task("a")) != "", true)


func test_tappen_geht_nur_bei_freien_karten_ohne_unteraufgaben() -> void:
	var ws: Workspace = Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("frei", "p", {"milestoneId": "m"}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("kind", "p", {"parentId": "stapel"}) \
		.task("wartet", "p", {"milestoneId": "m", "deps": ["frei"]}) \
		.build()
	eq(Field.tap_refusal(ws, ws.task("frei")), "")
	eq(Field.tap_refusal(ws, ws.task("kind")), "")
	eq(Field.tap_refusal(ws, ws.task("stapel")) != "", true)
	eq(Field.tap_refusal(ws, ws.task("wartet")) != "", true)
