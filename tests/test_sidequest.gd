extends "suite.gd"
## Nebenquests auf der Feldzugskarte: `rules/sidequest.gd`.

const Sidequest := preload("res://addons/tasker/rules/sidequest.gd")


func _boxes(n: int, done := 0) -> String:
	var lines := []
	for i in n:
		lines.append("- [%s] Schritt %d" % ["x" if i < done else " ", i + 1])
	return "\n".join(lines)


func _ws() -> Workspace:
	return Builder.new().project("p").release("alt", "p").release("r", "p") \
		.group("neben", "p", {"kind": "sidequest"}) \
		.task("klein", "p", {"ref": 1, "groupId": "neben", "releasedIn": "r", "status": "progress", "desc": _boxes(2, 1)}) \
		.task("gross", "p", {"ref": 2, "groupId": "neben", "releasedIn": "r", "status": "done", "desc": _boxes(6, 6)}) \
		.task("stapel", "p", {"ref": 3, "groupId": "neben", "releasedIn": "r", "status": "progress"}) \
		.task("s1", "p", {"ref": 4, "parentId": "stapel", "releasedIn": "alt", "status": "done", "desc": _boxes(2, 2)}) \
		.task("s2", "p", {"ref": 5, "parentId": "stapel", "releasedIn": "r", "status": "progress", "desc": _boxes(4, 1)}) \
		.task("s3", "p", {"ref": 6, "parentId": "stapel", "status": "ready"}) \
		.task("wartet", "p", {"ref": 7, "groupId": "neben", "status": "ready"}) \
		.task("offen", "p", {"ref": 8, "groupId": "neben", "status": "open"}) \
		.task("anderswo", "p", {"ref": 9, "status": "ready"}) \
		.build()


func test_die_stellung_richtet_sich_nach_der_groesse() -> void:
	var ws := _ws()
	eq(Sidequest.kind_of(ws, ws.task("klein")), Sidequest.MORTAR)
	eq(Sidequest.kind_of(ws, ws.task("gross")), Sidequest.ROCKET)
	# 3 Unteraufgaben + 6 Kästchen = 9 < 12
	eq(Sidequest.size_of(ws, ws.task("stapel")), 9)
	eq(Sidequest.kind_of(ws, ws.task("stapel")), Sidequest.BATTERY)
	var gross: Workspace = Builder.new().project("p") \
		.task("t", "p", {}).task("k1", "p", {"parentId": "t", "desc": _boxes(6)}).task("k2", "p", {"parentId": "t", "desc": _boxes(4)}).build()
	eq(Sidequest.kind_of(gross, gross.task("t")), Sidequest.AIRFIELD)


func test_gebaut_wird_nach_anteil_der_schritte() -> void:
	eq(Sidequest.built(0, 6, 8, false), 1, "die Pflöcke stehen ab dem Beginn")
	eq(Sidequest.built(3, 6, 8, false), 4)
	eq(Sidequest.built(6, 6, 8, false), 7, "das letzte Teil erst mit Erledigt")
	eq(Sidequest.built(6, 6, 8, true), 8)
	eq(Sidequest.built(0, 0, 5, false), 1, "ohne Kästchen nur die Pflöcke")
	eq(Sidequest.built(1, 40, 8, false), 1, "bei vielen Kästchen braucht ein Bauteil mehrere")


func test_die_stellungen_des_releases() -> void:
	var ws := _ws()
	var list := Sidequest.positions(ws, ws.release("r"))
	eq(list.map(func(p: Dictionary) -> String: return p["id"]), ["klein", "gross", "stapel"], "Unteraufgaben sind keine eigene Stellung")
	var stapel: Dictionary = list[2]
	eq(stapel["units"].map(func(u: Dictionary) -> String: return u["id"]), ["s1", "s2", "s3"])
	eq(stapel["units"][0]["earlier"], "alt", "schon in einem früheren Release erledigt")
	eq(stapel["units"][1]["earlier"], null)
	ok(stapel["units"][0]["done"])
	eq(list[1]["built"], list[1]["parts"], "erledigt: alles steht")


func test_in_die_reserve_kommt_was_noch_nicht_laeuft() -> void:
	var ws := _ws()
	eq(Sidequest.reserve(ws, "p", ws.release("r")).map(func(t: Dictionary) -> String: return t["id"]), ["wartet", "offen"])


func test_ziehen_setzt_in_arbeit() -> void:
	var ws := _ws()
	eq(Sidequest.deploy(ws, ws.task("wartet"))["changes"], {"wartet": {"status": "progress"}})
	ok(Sidequest.deploy(ws, ws.task("offen"))["refusal"] != "", "nicht fertig geplant")
	var stapel: Workspace = Builder.new().project("p") \
		.task("t", "p", {}).task("k1", "p", {"parentId": "t", "status": "open"}).task("k2", "p", {"parentId": "t", "status": "ready"}).build()
	eq(Sidequest.deploy(stapel, stapel.task("t"))["changes"], {"k2": {"status": "progress"}}, "beim Stapel die erste bereite Unteraufgabe")


func test_zurueckziehen_nur_ohne_erledigtes() -> void:
	var ws := _ws()
	eq(Sidequest.withdraw(ws, ws.task("klein"))["changes"], {"klein": {"status": "ready"}})
	ok(Sidequest.withdraw(ws, ws.task("stapel"))["refusal"] != "", "s1 ist erledigt")
	ok(Sidequest.withdraw(ws, ws.task("gross"))["refusal"] != "")


func test_die_kaestchen_als_texte() -> void:
	eq(Sidequest.boxes({"desc": "Text\n- [x] Erstens\n- [ ] Zweitens\n```\n- [ ] im Code\n```"}),
		[{"text": "Erstens", "done": true}, {"text": "Zweitens", "done": false}])
