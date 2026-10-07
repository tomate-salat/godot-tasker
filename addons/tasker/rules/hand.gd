extends RefCounted
## Hand und Nachziehstapel des Tischs.
##
## Tasker kennt nur „Offen“. Das Addon teilt es auf: was gezogen wurde, liegt
## auf der Hand, der Rest im Nachziehstapel. Dieser Zustand ist lokal und
## steht nicht in Tasker – hier sind nur die Regeln dazu, gespeichert wird
## woanders (`core/memory.gd`).
##
## Der Zustand je Milestone: `{ hand, buried, open }` – die IDs auf der Hand in
## ihrer Reihenfolge, die zurück unter den Stapel gelegten, und der Pfad der
## aufgefächerten Stapel.

const Workspace := preload("workspace.gd")

## Wie viel wahrscheinlicher eine Karte je Priorität gezogen wird.
const PRIO_WEIGHT := {0: 1.0, 1: 4.0, 2: 2.5, 3: 1.5}
## Die oberste Karte im Plan zählt doppelt so viel wie die unterste.
const FRONT_WEIGHT := 2.0
## Was unter den Stapel gelegt wurde, kommt so viel seltener wieder.
const BURIED_WEIGHT := 0.1


## Unter diesem Schlüssel liegt der Zustand eines Milestones.
static func key(milestone_id: String) -> String:
	return "tisch_" + milestone_id


## Bringt den gespeicherten Zustand mit dem Stand vom Server zusammen: auf der
## Hand bleibt nur, was noch offen ist; alles andere hat sich in Tasker
## erledigt, verschoben oder ist gesperrt worden.
static func sanitize(state: Variant, open: Array, ws: Workspace) -> Dictionary:
	var open_ids := {}
	for t in open:
		open_ids[t["id"]] = true
	var saved: Dictionary = state if state is Dictionary else {}

	var hand := []
	for id in saved.get("hand", []):
		if open_ids.has(id) and not hand.has(id):
			hand.append(id)
	var buried := []
	for id in saved.get("buried", []):
		if open_ids.has(id) and not hand.has(id) and not buried.has(id):
			buried.append(id)
	# Aufgefächert bleibt ein Stapel nur, solange er noch einer ist.
	var path := []
	for id in saved.get("open", []):
		var t = ws.task(id)
		if t == null or ws.kids(id).is_empty():
			break
		path.append(id)
	return {"hand": hand, "buried": buried, "open": path}


## Die offenen Karten, die nicht auf der Hand liegen, in Plan-Reihenfolge.
static func deck_of(open: Array, hand: Array) -> Array:
	return open.filter(func(t: Dictionary) -> bool: return not hand.has(t["id"]))


## Das Gewicht jeder Karte des Stapels beim Ziehen: hohe Prio und weit vorn
## im Plan kommen wahrscheinlicher.
static func weights(deck: Array, buried: Array) -> Array:
	var out := []
	var n := deck.size()
	for i in n:
		var t: Dictionary = deck[i]
		var front := 1.0 if n <= 1 else lerpf(FRONT_WEIGHT, 1.0, float(i) / (n - 1))
		var w: float = PRIO_WEIGHT.get(int(t.get("prio", 0)), 1.0) * front
		if buried.has(t["id"]):
			w *= BURIED_WEIGHT
		out.append(w)
	return out


## Zieht eine Karte. `roll` ist eine Zufallszahl von 0 bis unter 1.
static func pick(deck: Array, buried: Array, roll: float) -> Variant:
	if deck.is_empty():
		return null
	var ws := weights(deck, buried)
	var total := 0.0
	for w in ws:
		total += w
	var at := clampf(roll, 0.0, 0.999999) * total
	for i in deck.size():
		at -= ws[i]
		if at < 0.0:
			return deck[i]
	return deck[deck.size() - 1]
