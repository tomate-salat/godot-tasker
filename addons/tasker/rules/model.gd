extends RefCounted
## Grundlagen aus Taskers `shared/model.ts`.
##
## Die Objekte bleiben Dictionaries, so wie sie als JSON vom Server kommen –
## eigene Klassen je Typ müssten bei jeder Modelländerung in Tasker nachziehen.

## Die Status einer Aufgabe, in der Reihenfolge des Durchschaltens: Offen →
## Bereit (fertig geplant) → In Progress → Erledigt. Milestones kennen „Bereit“ nicht.
const STATUS := ["open", "ready", "progress", "done", "unclear", "blocked"]


## Erledigt ist kein eigenes Feld – es ist genau dieser Status.
static func is_done(x: Dictionary) -> bool:
	return x.get("status") == "done"


static func is_archived(x: Dictionary) -> bool:
	return x.get("archivedAt") != null


## Milestones erkennt man wie in Tasker an `planned`.
## Was sich ändert, wenn ein Milestone startet – wie in Taskers
## `setMilestoneStatus`: er steht auf „In Arbeit“, und hat er noch kein
## Startdatum, bekommt er das heutige (`today` als JJJJ-MM-TT). Leer, wenn er
## schon läuft oder fertig ist.
static func start_changes(m: Dictionary, today: String) -> Dictionary:
	if m.get("status") == "progress" or m.get("status") == "done":
		return {}
	var changes := {"status": "progress"}
	if not m.get("startDate"):
		changes["startDate"] = today
	return changes


static func is_milestone(x: Dictionary) -> bool:
	return x.has("planned")


## `Array.sort_custom` ist nicht stabil, JavaScripts `sort` schon – und die
## Regeln verlassen sich darauf („bei Gleichstand gilt die Baumreihenfolge“).
static func stable_sort(list: Array, less: Callable) -> Array:
	var rows := []
	for i in list.size():
		rows.append([list[i], i])
	rows.sort_custom(func(a: Array, b: Array) -> bool:
		if less.call(a[0], b[0]):
			return true
		if less.call(b[0], a[0]):
			return false
		return a[1] < b[1])
	var out := []
	for r in rows:
		out.append(r[0])
	return out


static func by_order(a: Dictionary, b: Dictionary) -> bool:
	return a["order"] < b["order"]
