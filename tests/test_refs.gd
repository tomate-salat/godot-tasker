extends "suite.gd"
## Referenzen von Aufgaben auf Szenen und Nodes.

const Refs := preload("res://addons/tasker/rules/refs.gd")

const LEVEL := "res://levels/level2.tscn"
const UID := "uid://level2"

const TSCN := """[gd_scene format=3 uid="uid://level2"]

[ext_resource type="PackedScene" path="res://boss.tscn" id="1"]

[node name="Level" type="Node3D" unique_id=100]

[node name="Enemies" type="Node3D" parent="." unique_id=200]

[node name="Boss" parent="Enemies" unique_id=300 instance=ExtResource("1")]

[node name="Der \\"Chef\\"" type="Node3D" parent="Enemies/Boss" unique_id=400]

[node name="Hut" type="MeshInstance3D" parent="Enemies/Boss/Body"]

[connection signal="ready" from="." to="." method="_on_ready"]
"""


func _ref(task: String, node: String, id := 0) -> Dictionary:
	return Refs.make(task, UID, LEVEL, node, "Node3D", id)


func _paths(refs: Array) -> Array:
	return refs.map(func(r: Dictionary) -> String: return "%s@%s" % [r["taskId"], r["nodePath"]])


func test_die_wurzel_steht_fuer_die_szene_als_ganzes() -> void:
	eq(_ref("a", ".")["kind"], "scene")
	eq(_ref("a", "Enemies/Boss")["kind"], "node")
	eq(Refs.label(_ref("a", ".")), "level2.tscn")
	eq(Refs.label(_ref("a", "Enemies/Boss")), "level2.tscn › Enemies/Boss")


func test_dieselbe_referenz_kommt_nicht_doppelt_hinein() -> void:
	var refs := Refs.add([], _ref("a", "Enemies"))
	refs = Refs.add(refs, _ref("a", "Enemies"))
	refs = Refs.add(refs, _ref("b", "Enemies"))
	refs = Refs.add(refs, _ref("a", "Enemies/Boss"))
	eq(_paths(refs), ["a@Enemies", "b@Enemies", "a@Enemies/Boss"])
	eq(_paths(Refs.of_task(refs, "a")), ["a@Enemies", "a@Enemies/Boss"])
	eq(_paths(Refs.of_node(refs, UID, LEVEL, "Enemies")), ["a@Enemies", "b@Enemies"])
	eq(_paths(Refs.remove(refs, _ref("a", "Enemies"))), ["b@Enemies", "a@Enemies/Boss"])


func test_die_uid_haelt_die_szene_auch_nach_dem_verschieben() -> void:
	var refs := [_ref("a", "."), Refs.make("b", "", LEVEL, ".", "Node3D"), Refs.make("c", "uid://anders", "res://x.tscn", ".", "Node")]
	eq(_paths(Refs.of_scene(refs, UID, "res://neu/level2.tscn")), ["a@."])
	eq(_paths(Refs.of_scene(refs, UID, LEVEL)), ["a@.", "b@."], "ohne UID zählt der Pfad")
	var moved := Refs.rename_scene(refs, UID, "res://neu/level2.tscn")
	eq(moved[0]["scenePath"], "res://neu/level2.tscn")
	eq(moved[2]["scenePath"], "res://x.tscn")


func test_umbenennen_zieht_die_referenzen_des_nodes_mit() -> void:
	var refs := [_ref("a", "Enemies/Boss"), _ref("b", "Enemies"), Refs.make("c", "uid://anders", "res://x.tscn", "Enemies/Boss", "Node")]
	var moved := Refs.move(refs, UID, LEVEL, "Enemies/Boss", "Enemies/Endgegner", "CharacterBody3D")
	eq(_paths(moved), ["a@Enemies/Endgegner", "b@Enemies", "c@Enemies/Boss"])
	eq(moved[0]["nodeType"], "CharacterBody3D")
	eq(refs[0]["nodePath"], "Enemies/Boss", "die alte Liste bleibt, wie sie war")
	eq(Refs.move(refs, UID, LEVEL, "Enemies", ".")[1]["kind"], "scene")


func test_die_node_nummern_stehen_in_der_szenendatei() -> void:
	eq(Refs.scene_ids(TSCN), {".": 100, "Enemies": 200, "Enemies/Boss": 300, "Enemies/Boss/Der \"Chef\"": 400})


func test_der_abgleich_folgt_der_nummer_und_traegt_fehlende_nach() -> void:
	var ids := Refs.scene_ids(TSCN)
	var refs := [_ref("a", "Gegner/Boss", 300), _ref("b", "Enemies"), _ref("c", "Gibtsnicht"), _ref("d", "Enemies", 999)]
	var out := Refs.reconcile(refs, UID, LEVEL, ids)
	eq(_paths(out), ["a@Enemies/Boss", "b@Enemies", "c@Gibtsnicht", "d@Enemies"])
	eq(out[1]["nodeId"], 200, "die Nummer wird nachgetragen")
	eq(out[2]["nodeId"], 0)
	eq(out[3]["nodeId"], 200, "eine verschwundene Nummer weicht der des Pfads")


func test_bei_ungespeicherter_szene_wird_nur_verlorenes_verschoben() -> void:
	var ids := Refs.scene_ids(TSCN)
	var refs := [_ref("a", "Gegner/Boss", 300), _ref("b", "Enemies"), _ref("c", "Umbenannt", 200)]
	var out := Refs.reconcile(refs, UID, LEVEL, ids, ["Gegner/Boss"])
	eq(_paths(out), ["a@Enemies/Boss", "b@Enemies", "c@Umbenannt"])
	eq(out[1]["nodeId"], 0)


func test_unlesbares_faellt_beim_laden_weg() -> void:
	var saved := [_ref("a", "Enemies", 200), "quatsch", {"taskId": "b"}, {"taskId": "c", "scenePath": LEVEL}, _ref("a", "Enemies")]
	var out := Refs.sanitize(saved)
	eq(_paths(out), ["a@Enemies", "c@."])
	eq(out[0]["nodeId"], 200)
	eq(out[1]["kind"], "scene")
	eq(Refs.sanitize(null), [])
