extends RefCounted
## Der Tisch, aus Taskers `shared/tisch.ts`: die Arbeit am aktiven Milestone als
## Kartenspiel. Aktiv ist ein Milestone mit Status „In Progress“ – je Projekt
## höchstens einer. Die Zonen ergeben sich aus Status und Abhängigkeiten,
## nichts davon wird eigens gespeichert.
##
## Hand und Nachziehstapel des Addons teilen `open` weiter auf; das ist lokaler
## Zustand und steht nicht hier.

const Model := preload("model.gd")
const Checklist := preload("checklist.gd")
const Blocking := preload("blocking.gd")
const Workspace := preload("workspace.gd")

const DAY := 86400


## Die Milestones eines Projekts auf „In Progress“, eingeplante zuerst in
## Plan-Reihenfolge. Normal ist es höchstens einer.
static func active_milestones(ws: Workspace, project_id: String) -> Array:
	var list := ws.milestones.filter(func(m: Dictionary) -> bool:
		return m["projectId"] == project_id and m["status"] == "progress" and not Model.is_archived(m))
	return Model.stable_sort(list, func(a: Dictionary, b: Dictionary) -> bool:
		if a["planned"] != b["planned"]:
			return a["planned"]
		return a["qorder"] < b["qorder"] if a["planned"] else a["order"] < b["order"])


## Der aktive Milestone des Projekts – bei mehreren der oberste im Plan.
static func active_milestone(ws: Workspace, project_id: String) -> Variant:
	var list := active_milestones(ws, project_id)
	return list[0] if list.size() else null


## Ein anderer aktiver Milestone im selben Projekt – solange es ihn gibt,
## bleibt „In Progress“ für `m` gesperrt.
static func progress_locked_by(ws: Workspace, m: Dictionary) -> Variant:
	for x in active_milestones(ws, m["projectId"]):
		if x["id"] != m["id"]:
			return x
	return null


## Wohin jede Karte gehört: `{ locked, open, play, pile }`.
##
## - Ein Task mit Unteraufgaben ist ein Stapel. Er kommt nie ins Spiel – dort
##   liegt nur die Arbeit selbst, also Unteraufgaben ohne eigene Kinder.
## - „In Progress“ geht vor „gesperrt“: was schon läuft, liegt im Spiel.
## - Gesperrte Unteraufgaben bleiben in ihrem Stapel.
static func layout(ws: Workspace, m: Dictionary) -> Dictionary:
	var locked := []
	var open := []
	var play := []
	var pile := []
	for root in ws.ms_roots(m):
		if ws.is_doc(root):
			continue
		var all := [root]
		all.append_array(ws.desc(root))
		for t in all:
			if Model.is_done(t):
				pile.append(t)
		# In Arbeit sind nur Blätter, Stapel nie.
		for t in all:
			if t["status"] == "progress" and ws.kids(t["id"]).is_empty() and not _done_above(ws, t, root):
				play.append(t)
		if Model.is_done(root) or (root["status"] == "progress" and ws.kids(root["id"]).is_empty()):
			continue
		if Blocking.is_blocked(ws, root):
			locked.append(root)
		else:
			open.append(root)
	# Im Spiel wird von Hand sortiert; bei Gleichstand bleibt die Baumreihenfolge.
	play = Model.stable_sort(play, func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("playOrder", 0) < b.get("playOrder", 0))
	# Ohne Zeitpunkt ist es gerade eben erledigt worden – das gehört obenauf.
	pile = Model.stable_sort(pile, func(a: Dictionary, b: Dictionary) -> bool:
		return _done_key(a) > _done_key(b))
	return {"locked": locked, "open": open, "play": play, "pile": pile}


static func _done_key(t: Dictionary) -> String:
	var at = t.get("doneAt")
	return at if at else "￿"


## Liegt ein erledigter Elternteil darüber? Dann ist die Karte mit ihm abgelegt.
static func _done_above(ws: Workspace, t: Dictionary, root: Dictionary) -> bool:
	if t["id"] == root["id"]:
		return false
	return ws.ancestors(t).any(Model.is_done)


## Warum eine Karte nicht ins Spiel darf – leer heißt: sie darf.
static func play_refusal(ws: Workspace, t: Dictionary) -> String:
	if Model.is_done(t):
		return ""
	if ws.kids(t["id"]).size() > 0:
		return "Ein Stapel kommt nicht ins Spiel – spiel seine Unteraufgaben aus"
	if Blocking.is_blocked(ws, t):
		return "Die Karte ist noch angekettet"
	return ""


## Warum eine Karte nicht auf den Erledigt-Stapel darf – leer heißt: sie darf.
static func done_refusal(ws: Workspace, t: Dictionary) -> String:
	var cl := Checklist.count(t.get("desc"))
	var open: int = cl["total"] - cl["done"]
	for k in ws.kids(t["id"]):
		if not Model.is_done(k):
			open += 1
	if open > 0:
		return "Erst erledigt, wenn alles darunter erledigt ist – noch %d offen" % open
	return ""


## Ein Stapel, dessen Unteraufgaben alle erledigt sind – er wartet aufs Ablegen.
static func stack_ready(ws: Workspace, t: Dictionary) -> bool:
	return not Model.is_done(t) and ws.kids(t["id"]).size() > 0 and done_refusal(ws, t) == ""


# ---------------------------------------------------------------- Ablage

## Zeitpunkt aus dem ISO-Text des Servers (UTC), in Sekunden.
static func parse_time(iso: String) -> float:
	var unix := float(Time.get_unix_time_from_datetime_string(iso.substr(0, 19)))
	if iso.length() > 20 and iso[19] == ".":
		unix += ("0" + iso.substr(19, 4)).to_float()
	return unix


## Der Montag der Woche, in der `unix` liegt, als `YYYY-MM-DD`.
##
## `tz_minutes` ist der Abstand des Geräts zu UTC – der Server kennt nur UTC.
## Es gilt der heutige Abstand auch für ältere Zeitpunkte; über eine
## Zeitumstellung hinweg kann eine Karte um Mitternacht am Wochenwechsel
## deshalb eine Stunde danebenliegen.
static func week_start(unix: float, tz_minutes: int) -> String:
	var local := int(floor(unix)) + tz_minutes * 60
	var midnight := local - posmod(local, DAY)
	var weekday: int = Time.get_date_dict_from_unix_time(midnight)["weekday"]
	return Time.get_date_string_from_unix_time(midnight - ((weekday + 6) % 7) * DAY)


static func _weeks_before(start: String, weeks: int) -> String:
	return Time.get_date_string_from_unix_time(Time.get_unix_time_from_datetime_string(start) - 7 * DAY * weeks)


## Der aufgedeckte Erledigt-Stapel: was im Milestone erledigt wurde, je Woche.
##
## `{ weeks = [{ start, cards, count, current, best }], streak, this_week }` –
## die jüngste Woche zuerst, Wochen ohne Erledigtes fehlen. `count` zählt nur
## Karten ohne Unteraufgaben. Die laufende Woche bricht die Serie nicht.
static func done_shelf(ws: Workspace, m: Dictionary, now_unix: float, tz_minutes: int) -> Dictionary:
	# Erledigt Archiviertes bleibt liegen – sonst schrumpften alte Wochen beim Aufräumen.
	var done := []
	for root in ws.ms_counted(m):
		if not root.get("doc", false):
			_walk_done(ws, root, done)

	var at := func(t: Dictionary) -> float:
		return parse_time(t["doneAt"]) if t.get("doneAt") else now_unix
	done = Model.stable_sort(done, func(a: Dictionary, b: Dictionary) -> bool:
		return at.call(a) > at.call(b))

	var this_start := week_start(now_unix, tz_minutes)
	var by_start := {}
	for t in done:
		var start := week_start(at.call(t), tz_minutes)
		if not by_start.has(start):
			by_start[start] = {"start": start, "cards": [], "count": 0, "current": start == this_start, "best": false}
		by_start[start]["cards"].append(t)
		if ws.counted_kids(t["id"]).is_empty():
			by_start[start]["count"] += 1

	var weeks := by_start.values()
	weeks.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["start"] > b["start"])

	var most := 0
	for w in weeks:
		most = maxi(most, w["count"])
	if weeks.size() > 1 and most > 0:
		for w in weeks:
			if w["count"] == most:
				w["best"] = true
				break

	var count_of := func(start: String) -> int:
		return by_start[start]["count"] if by_start.has(start) else 0
	var from := 0 if count_of.call(this_start) > 0 else 1
	var streak := 0
	while count_of.call(_weeks_before(this_start, from)) > 0:
		streak += 1
		from += 1

	return {"weeks": weeks, "streak": streak, "this_week": count_of.call(this_start)}


static func _walk_done(ws: Workspace, t: Dictionary, out: Array) -> void:
	if Model.is_done(t):
		out.append(t)
	for k in ws.counted_kids(t["id"]):
		_walk_done(ws, k, out)
