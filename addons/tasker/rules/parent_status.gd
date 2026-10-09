extends RefCounted
## Der Status einer Eltern-Aufgabe, aus Taskers `shared/parentStatus.ts`.
##
## Tasker zieht ihn am Server nach, sobald eine Unteraufgabe ihren Status
## ändert. Das Addon kennt die Regel, um nichts anzubieten, was der Server
## gleich wieder zurückdreht – und für die Beispieldaten ohne Verbindung.

const Model := preload("model.gd")
const Workspace := preload("workspace.gd")


## Wie sich der Status einer Eltern-Aufgabe ändert, wenn eine ihrer
## Unteraufgaben einen neuen Status bekommt:
##
## - Geht eine Unteraufgabe in Arbeit oder wird erledigt, ist die offene
##   Eltern-Aufgabe „In Progress“.
## - Stehen alle Unteraufgaben wieder auf „Offen“, ist es die Eltern-Aufgabe auch.
## - Sind alle erledigt, wird die Eltern-Aufgabe nicht von selbst erledigt.
## - Wird bei einer erledigten Eltern-Aufgabe eine Unteraufgabe wieder
##   aufgemacht, ist sie nicht mehr erledigt.
##
## „Unklar“ und „Blockiert“ werden nur ausdrücklich gesetzt und bleiben stehen.
## `kids` sind die Status aller direkten Unteraufgaben, die geänderte schon mit
## ihrem neuen Status. Null heißt: bleibt, wie es ist.
static func after(parent: Variant, child: Variant, kids: Array) -> Variant:
	if parent != "open" and parent != "progress" and parent != "done":
		return null
	if kids.size() > 0 and kids.all(func(s: Variant) -> bool: return s == "open"):
		return null if parent == "open" else "open"
	if parent == "open" and (child == "progress" or child == "done"):
		return "progress"
	if parent == "done" and child != "done":
		return "progress"
	return null


## Warum sich der Status eines Stapels nicht von Hand auf „Offen“ stellen
## lässt – leer heißt: es geht. Solange darunter etwas in Arbeit oder erledigt
## ist, stellte Tasker ihn beim nächsten Schritt ohnehin wieder zurück.
static func open_refusal(ws: Workspace, t: Dictionary) -> String:
	var busy := 0
	for k in ws.desc(t):
		if Model.is_done(k) or k.get("status") == "progress":
			busy += 1
	if busy > 0:
		return "Der Stapel bleibt in Arbeit, solange darunter etwas läuft oder erledigt ist – noch %d" % busy
	return ""
