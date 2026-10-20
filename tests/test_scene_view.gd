extends "suite.gd"
## Filter und Stapelbildung der Karten im Viewport.

const SceneView := preload("res://addons/tasker/rules/scene_view.gd")


func _ws() -> Workspace:
	return Builder.new() \
		.project("p") \
		.milestone("m", "p", {"status": "progress"}) \
		.milestone("später", "p") \
		.task("a", "p", {"milestoneId": "m"}) \
		.task("stapel", "p", {"milestoneId": "m"}) \
		.task("kind", "p", {"parentId": "stapel"}) \
		.task("enkel", "p", {"parentId": "kind"}) \
		.task("b", "p", {"milestoneId": "m"}) \
		.task("fern", "p", {"milestoneId": "später"}) \
		.task("lose", "p") \
		.build()


func _ids(allowed: Variant) -> Array:
	var out: Array = allowed.keys()
	out.sort()
	return out


func test_alle_laesst_alles_durch_und_aus_nichts() -> void:
	var ws := _ws()
	eq(SceneView.allowed(ws, "p", SceneView.ALL), null)
	eq(SceneView.allowed(ws, "p", SceneView.OFF), {})


func test_der_milestone_filter_nimmt_unteraufgaben_mit() -> void:
	eq(_ids(SceneView.allowed(_ws(), "p", SceneView.MILESTONE)), ["a", "b", "enkel", "kind", "stapel"])


func test_der_hand_filter_zeigt_was_gezogen_wurde_samt_unteraufgaben() -> void:
	var ws := _ws()
	eq(_ids(SceneView.allowed(ws, "p", SceneView.HAND, {"hand": ["stapel", "fern"]})), ["enkel", "kind", "stapel"])
	eq(SceneView.allowed(ws, "p", SceneView.HAND, null), {})


func test_ohne_laufenden_milestone_zeigen_die_engen_filter_nichts() -> void:
	var ws: Workspace = Builder.new().project("p").milestone("m", "p").task("a", "p", {"milestoneId": "m"}).build()
	eq(SceneView.allowed(ws, "p", SceneView.MILESTONE), {})


func test_unbekanntes_wird_zu_alle() -> void:
	eq(SceneView.mode_of("hand"), "hand")
	eq(SceneView.mode_of("quatsch"), "all")
	eq(SceneView.mode_of(null), "all")


func test_nahe_punkte_ruecken_zu_einem_stapel_zusammen() -> void:
	var points := [Vector2(0, 0), Vector2(100, 0), Vector2(8, 4), Vector2(104, 2), Vector2(300, 300), Vector2(15, 0)]
	eq(SceneView.clusters(points, 20.0), [[0, 2, 5], [1, 3], [4]])
	eq(SceneView.clusters([], 20.0), [])


func _ref(task_id: String, node_path: String, via := "") -> Dictionary:
	var ref := {"taskId": task_id, "nodePath": node_path}
	if via != "":
		ref["via"] = via
	return ref


func test_nur_die_tiefsten_nodes_einer_aufgabe_zeigen_eine_karte() -> void:
	var refs := [
		_ref("a", "."), _ref("a", "Dummies"), _ref("a", "Dummies/Model"),
		_ref("a", "Dummies/Model2"), _ref("a", "Dummies2"),
		_ref("b", "Dummies"),
	]
	eq(SceneView.leaves(refs).map(func(r: Dictionary) -> String: return r["taskId"] + ":" + r["nodePath"]),
		["a:Dummies/Model", "a:Dummies/Model2", "a:Dummies2", "b:Dummies"])


func test_blaetter_gehen_durch_instanzen_hindurch() -> void:
	# Am Prefab hängt die Aufgabe an seiner Wurzel und an einem Kind, in der
	# Szene an der Instanz selbst.
	var refs := [_ref("a", "Npc"), _ref("a", ".", "Npc"), _ref("a", "Body", "Npc"), _ref("a", "Npcs")]
	eq(SceneView.leaves(refs), [_ref("a", "Body", "Npc"), _ref("a", "Npcs")])
