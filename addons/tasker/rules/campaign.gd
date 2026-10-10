extends RefCounted
## Der Feldzug: ein Release als Karte, nach derselben Logik wie das Feld
## (`field.gd`), nur eine Ebene höher. In der Mitte steht das Release, die
## Milestones liegen als Städte in Ringen darum.
##
## - Was ein Milestone braucht, liegt einen Ring weiter außen: die Milestones,
##   von denen er abhängt. Im innersten Ring liegt, worauf kein anderer wartet.
## - Ein aktiver Milestone greift an: den Milestone, der auf ihn wartet, oder –
##   im innersten Ring – das Release selbst.
## - Gezeigt wird nur, was zum Release gehört.

const Model := preload("model.gd")
const Progress := preload("progress.gd")
const Field := preload("field.gd")
const Workspace := preload("workspace.gd")

const DONE := "done"
const ACTIVE := "active"
const PLANNED := "planned"


## Baut den Feldzug eines Releases:
##
## - `nodes`: je Milestone `{ id, milestone, ring, inner, state, total, done,
##   fights }`. `ring` zählt von innen ab 1, `inner` ist der Milestone, der auf
##   ihn wartet (leer für die Mitte), `state` ist `done`, `active` oder
##   `planned`, `fights` die Zahl der Aufgaben, an denen gerade gearbeitet wird.
## - `ways`: die Verbindungen nach innen, `{ from, to }`; `to` ist leer für die
##   Mitte. Umwege fehlen wie im Feld.
## - `attacks`: die Verbindungen, auf denen ein aktiver Milestone angreift.
## - `front`: der äußerste Ring, auf dem noch ein Milestone offen ist; 0, wenn
##   alle fertig sind.
## - `boss`: `{ total, done }` über alle Aufgaben des Releases.
static func build(ws: Workspace, release: Dictionary) -> Dictionary:
	var milestones := ws.release_milestones(release["id"])
	var here := {}
	for m in milestones:
		here[m["id"]] = m

	# Wohin jeder Milestone nach innen führt: zu allem, was auf ihn wartet.
	var inward := {}
	for m in milestones:
		inward[m["id"]] = []
	for m in milestones:
		for dep_id in m.get("deps", []):
			if here.has(dep_id) and dep_id != m["id"] and not inward[dep_id].has(m["id"]):
				inward[dep_id].append(m["id"])

	var rings := {}
	for m in milestones:
		Field._ring_of(m["id"], inward, rings, {})

	var nodes := []
	var ways := []
	var attacks := []
	var total := 0
	var done := 0
	var front := 0
	for m in milestones:
		var id: String = m["id"]
		var stats := Progress.milestone_stats(ws, m)
		var state := DONE if Progress.milestone_done(ws, m) else ACTIVE if m.get("status") == "progress" else PLANNED
		var inner := ""
		for other in inward[id]:
			if inner == "" or rings[other] > rings[inner]:
				inner = other
		var fights := 0
		for root in ws.ms_roots(m):
			for t in [root] + ws.desc(root):
				if Field.is_tapped(t):
					fights += 1
		nodes.append({"id": id, "milestone": m, "ring": rings[id], "inner": inner, "state": state,
			"total": stats["total"], "done": stats["total"] if state == DONE else stats["done"], "fights": fights})
		total += stats["total"]
		done += stats["total"] if state == DONE else stats["done"]
		if state != DONE:
			front = maxi(front, rings[id])

		var targets := []
		if inward[id].is_empty():
			targets.append("")
		for other in inward[id]:
			var around := false
			for via in inward[id]:
				if via != other and Field._leads(via, other, inward, {}):
					around = true
			if not around:
				targets.append(other)
		for target in targets:
			ways.append({"from": id, "to": target})
			if state == ACTIVE:
				attacks.append({"from": id, "to": target})
	return {"nodes": nodes, "ways": ways, "attacks": attacks, "front": front, "boss": {"total": total, "done": done}}
