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
## - Geht eine Unteraufgabe in Arbeit oder wird erledigt, ist die offene oder
##   bereite Eltern-Aufgabe „In Progress“.
## - Ist keine Unteraufgabe mehr angefangen, fällt die Eltern-Aufgabe zurück:
##   auf „Bereit“, wenn alle bereit sind, sonst auf „Offen“. Eine
##   Eltern-Aufgabe, die selbst noch nicht angefangen ist, bleibt dabei, wie sie ist.
## - Sind alle erledigt, wird die Eltern-Aufgabe nicht von selbst erledigt.
## - Wird bei einer erledigten Eltern-Aufgabe eine Unteraufgabe wieder
##   aufgemacht, ist sie nicht mehr erledigt.
##
## „Unklar“ und „Blockiert“ werden nur ausdrücklich gesetzt und bleiben stehen.
## `kids` sind die Status aller direkten Unteraufgaben, die geänderte schon mit
## ihrem neuen Status. Null heißt: bleibt, wie es ist.
static func after(parent: Variant, child: Variant, kids: Array) -> Variant:
	if not _not_started(parent) and parent != "progress" and parent != "done":
		return null
	if kids.size() > 0 and kids.all(_not_started):
		if _not_started(parent):
			return null
		return "ready" if kids.all(func(s: Variant) -> bool: return s == "ready") else "open"
	if _not_started(parent) and (child == "progress" or child == "done"):
		return "progress"
	if parent == "done" and child != "done":
		return "progress"
	return null


## Noch nicht angefangen: offen oder fertig geplant.
static func _not_started(s: Variant) -> bool:
	return s == "open" or s == "ready"


## Was ein Task zusätzlich zu seinem eigenen Status anzeigt, abgeleitet aus
## allen Nachfahren (Taskers `implicitStatus`) – nur Anzeige, nichts wird
## gespeichert. Null heißt: nur der eigene Status zählt.
##
## - Ist eine Unteraufgabe blockiert, erscheint ein offener, bereiter oder
##   laufender Task blockiert; sonst bei einer unklaren Unteraufgabe unklar.
## - Ein offener oder bereiter Task, unter dem gearbeitet wird, erscheint in Arbeit.
## - Ein bereiter Task mit einer noch offenen Unteraufgabe erscheint offen –
##   fertig geplant ist er erst, wenn alles darunter es ist.
static func implicit(ws: Workspace, t: Dictionary) -> Variant:
	var own: Variant = t.get("status")
	if not _not_started(own) and own != "progress":
		return null
	var desc := ws.desc(t)
	if desc.any(func(d: Dictionary) -> bool: return d.get("status") == "blocked"):
		return "blocked"
	if desc.any(func(d: Dictionary) -> bool: return d.get("status") == "unclear"):
		return "unclear"
	if _not_started(own) and desc.any(func(d: Dictionary) -> bool: return d.get("status") == "progress"):
		return "progress"
	if own == "ready" and desc.any(func(d: Dictionary) -> bool: return d.get("status") == "open"):
		return "open"
	return null


## Noch nicht fertig geplant (Taskers `notReady`): eine offene Aufgabe – oder
## eine bereite, unter der noch etwas offen ist. Am Tisch und im Feld liegt sie gesperrt.
static func not_ready(ws: Workspace, t: Dictionary) -> bool:
	return t.get("status") == "open" or (t.get("status") == "ready" and implicit(ws, t) == "open")


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
