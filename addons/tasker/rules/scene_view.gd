extends RefCounted
## Welche Karten der Viewport zeigt und welche davon zu einem Stapel
## zusammenrücken. Gezeichnet wird in `ui/scene_cards.gd`.

const Workspace := preload("workspace.gd")
const Tisch := preload("tisch.gd")
const Hand := preload("hand.gd")

## Der Filter in der Viewport-Leiste.
const ALL := "all"
const MILESTONE := "milestone"
const HAND := "hand"
const OFF := "off"
const MODES := [ALL, MILESTONE, HAND, OFF]
const LABELS := {
	ALL: "Alle Karten",
	MILESTONE: "Laufender Milestone",
	HAND: "Nur die Hand",
	OFF: "Keine Karten",
}

## Unter diesem Schlüssel merkt sich das Addon den Filter.
const KEY := "scene_cards_show"


static func mode_of(saved: Variant) -> String:
	return saved if saved is String and MODES.has(saved) else ALL


## Die IDs der Aufgaben, die der Filter durchlässt – null, wenn er alles
## durchlässt. `hand_state` ist der gemerkte Zustand des Tischs für den
## laufenden Milestone (`Hand.key`).
##
## Unteraufgaben zählen zu ihrer Wurzel: liegt die auf der Hand oder im
## Milestone, gilt das auch für alles darunter.
static func allowed(ws: Workspace, project_id: String, mode: String, hand_state: Variant = null) -> Variant:
	if mode == ALL:
		return null
	var out := {}
	if mode == OFF:
		return out
	var m = Tisch.active_milestone(ws, project_id)
	if m == null:
		return out
	var layout := Tisch.layout(ws, m)
	var roots := []
	if mode == HAND:
		for id in Hand.sanitize(hand_state, layout["open"], ws)["hand"]:
			roots.append(ws.task(id))
	else:
		for t in ws.tasks:
			if t.get("milestoneId") == m["id"] and not t.get("parentId"):
				roots.append(t)
	while not roots.is_empty():
		var t = roots.pop_back()
		if t == null or out.has(t["id"]):
			continue
		out[t["id"]] = true
		roots.append_array(ws.kids(t["id"]))
	return out


## Fasst Punkte zusammen, die näher als `reach` beieinander liegen: eine Liste
## von Gruppen, jede eine Liste von Indizes in `points`. Eine Gruppe sammelt
## sich um ihren ersten Punkt; die Reihenfolge der Punkte bleibt erhalten.
static func clusters(points: Array, reach: float) -> Array:
	var groups := []
	for i in points.size():
		var home := -1
		for g in groups.size():
			if points[groups[g][0]].distance_to(points[i]) < reach:
				home = g
				break
		if home < 0:
			groups.append([i])
		else:
			groups[home].append(i)
	return groups
