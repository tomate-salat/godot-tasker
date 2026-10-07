extends "suite.gd"
## Hand und Nachziehstapel: der lokale Zustand des Tischs.

const Hand := preload("res://addons/tasker/rules/hand.gd")
const Tisch := preload("res://addons/tasker/rules/tisch.gd")


func _table() -> Builder:
	return Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.task("a", "p", {"milestoneId": "m"}) \
		.task("b", "p", {"milestoneId": "m", "prio": 1}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("kind", "p", {"parentId": "stapel"}) \
		.task("c", "p", {"milestoneId": "m"})


func test_auf_der_hand_bleibt_nur_was_noch_offen_ist() -> void:
	var b := _table()
	b.task("läuft", "p", {"milestoneId": "m", "status": "progress"})
	b.task("fertig", "p", {"milestoneId": "m", "status": "done"})
	b.task("wartet", "p", {"milestoneId": "m", "deps": ["a"]})
	var ws: Workspace = b.build()
	var open: Array = Tisch.layout(ws, ws.milestone("m"))["open"]
	var saved := {"hand": ["b", "läuft", "fertig", "wartet", "gibtsnicht", "b"], "buried": ["a", "b", "weg"], "open": ["stapel", "a"]}
	eq(Hand.sanitize(saved, open, ws), {"hand": ["b"], "buried": ["a"], "open": ["stapel"]})


func test_ohne_gespeicherten_zustand_ist_die_hand_leer() -> void:
	var ws: Workspace = _table().build()
	var open: Array = Tisch.layout(ws, ws.milestone("m"))["open"]
	eq(Hand.sanitize(null, open, ws), {"hand": [], "buried": [], "open": []})


func test_der_nachziehstapel_ist_der_rest_in_plan_reihenfolge() -> void:
	var ws: Workspace = _table().build()
	var open: Array = Tisch.layout(ws, ws.milestone("m"))["open"]
	eq(ids(Hand.deck_of(open, ["stapel", "a"])), ["b", "c"])


func test_hohe_prio_und_vorn_im_plan_wiegen_mehr_zurueckgelegtes_weniger() -> void:
	var ws: Workspace = _table().build()
	var deck: Array = Tisch.layout(ws, ws.milestone("m"))["open"]
	var w := Hand.weights(deck, [])
	ok(w[1] > w[0], "Prio hoch vor ohne Prio")
	ok(w[0] > w[2] and w[2] > w[3], "vorn im Plan vor hinten")
	var buried := Hand.weights(deck, ["b"])
	ok(buried[1] < w[3], "zurückgelegt wiegt am wenigsten")


func test_ziehen_folgt_der_zufallszahl_ueber_die_gewichte() -> void:
	var ws: Workspace = _table().build()
	var deck: Array = Tisch.layout(ws, ws.milestone("m"))["open"]
	eq(Hand.pick(deck, [], 0.0)["id"], "a")
	eq(Hand.pick(deck, [], 0.999999)["id"], "c")
	eq(Hand.pick(deck, [], 1.5)["id"], "c", "über 1 bleibt im Stapel")
	eq(Hand.pick([], [], 0.5), null)
	# Gewichte 2, 6.67, 1.33, 1 – die Mitte fällt auf die Karte mit hoher Prio.
	eq(Hand.pick(deck, [], 0.5)["id"], "b")
