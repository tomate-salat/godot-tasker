extends RefCounted
## Burnup eines Milestones, aus Taskers `shared/burnup.ts`.
##
## Der Server führt je Milestone ein Protokoll und liefert es mit dem Stand
## (`milestoneLog`): Einträge `{ at, s, dn }` – Zeitpunkt in UTC, committete
## Aufgaben ab da, davon erledigt. Zu Kalendertagen werden sie erst hier, in
## der Zeitzone des Geräts.
##
## Gerechnet wird in Tagesnummern (Tage seit 1970 in Ortszeit) statt mit
## Datumsobjekten wie in Tasker.

const Model := preload("model.gd")
const Progress := preload("progress.gd")
const Workspace := preload("workspace.gd")

const DAY := 86400
const SINCE_EVER := "1970-01-01T00:00:00.000Z"


## Die Tagesnummer eines Zeitpunkts in Ortszeit.
static func day_of(unix: float, tz_minutes: int) -> int:
	return int(floor((unix + tz_minutes * 60.0) / DAY))


## Die Tagesnummer eines Kalendertags `YYYY-MM-DD`.
static func day_of_date(iso_day: String) -> int:
	return int(Time.get_unix_time_from_datetime_string(iso_day.substr(0, 10))) / DAY


## Der Kalendertag zu einer Tagesnummer als `TT.MM.` oder mit Jahr.
static func format_day(day: int, with_year := false) -> String:
	var d := Time.get_date_dict_from_unix_time(day * DAY)
	return "%02d.%02d.%s" % [d["day"], d["month"], str(d["year"]) if with_year else ""]


static func _unix(iso: String) -> float:
	return float(Time.get_unix_time_from_datetime_string(iso.substr(0, 19)))


## Umfang und Erledigtes heute, gezählt wie überall: Aufgaben, nicht Punkte.
static func points(ws: Workspace, m: Dictionary) -> Dictionary:
	var stats := Progress.milestone_stats(ws, m)
	return {"s": stats["total"], "dn": stats["done"]}


## Für Milestones ohne Protokoll: Umfang wie heute, Erledigtes aus den
## Abschlusszeitpunkten der Aufgaben. Aufgaben ohne Zeitpunkt zählen von
## Anfang an als erledigt.
static func backfill_log(ws: Workspace, m: Dictionary) -> Array:
	var roots := ws.ms_counted(m)
	var s := 0
	var events := []
	for r in roots:
		s += Progress.total(ws, r)
		_walk_done(ws, r, events)

	var dn := 0
	var dated := []
	for e in events:
		if e["at"] == null:
			dn += e["p"]
		else:
			dated.append(e)
	dated = Model.stable_sort(dated, func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])

	var log := [{"at": SINCE_EVER, "s": s, "dn": dn}]
	for e in dated:
		dn += e["p"]
		var last: Dictionary = log[log.size() - 1]
		if last["at"] == e["at"]:
			last["dn"] = dn
		else:
			log.append({"at": e["at"], "s": s, "dn": dn})
	return log


static func _walk_done(ws: Workspace, t: Dictionary, events: Array) -> void:
	if Model.is_done(t):
		events.append({"at": t.get("doneAt"), "p": Progress.total(ws, t)})
		return
	for k in ws.counted_kids(t["id"]):
		_walk_done(ws, k, events)


## Das Protokoll samt dem aktuellen Stand – damit die Kurve jeder Änderung
## sofort folgt, auch bevor der Server sie protokolliert hat.
static func with_now(log: Array, s: int, dn: int, now_iso: String) -> Array:
	if log.size() > 0:
		var last: Dictionary = log[log.size() - 1]
		if int(last["s"]) == s and int(last["dn"]) == dn:
			return log
	var out := log.duplicate()
	out.append({"at": now_iso, "s": s, "dn": dn})
	return out


## Je Kalendertag in Ortszeit der letzte Stand: `[{ day, s, dn }]`.
static func _to_days(log: Array, tz_minutes: int) -> Array:
	var sorted := Model.stable_sort(log, func(a: Dictionary, b: Dictionary) -> bool: return a["at"] < b["at"])
	var out := []
	for e in sorted:
		var day := day_of(_unix(e["at"]), tz_minutes)
		if out.size() > 0 and out[out.size() - 1]["day"] == day:
			out[out.size() - 1]["s"] = int(e["s"])
			out[out.size() - 1]["dn"] = int(e["dn"])
		else:
			out.append({"day": day, "s": int(e["s"]), "dn": int(e["dn"])})
	return out


static func _log_at(days: Array, day: int) -> Dictionary:
	var found = null
	for e in days:
		if e["day"] <= day:
			found = e
		else:
			break
	if found != null:
		return found
	return days[0] if days.size() > 0 else {"day": day, "s": 0, "dn": 0}


## Die Kurve ab dem Startdatum; ohne (oder mit künftigem) Start gibt es keine.
##
## `{ start_day, scope, done_s, s, dn, open, done, today_i, end_i, fc_i,
## dead_i, max_i, max_v, added, removed }` – die `_i` sind Tage seit dem
## Start; `fc_i` (Prognose) und `dead_i` (Enddatum) können null sein.
static func data(m: Dictionary, log: Array, velocity: int, now_unix: float, tz_minutes: int) -> Variant:
	if not m.get("startDate"):
		return null
	var start := day_of_date(m["startDate"])
	var today := day_of(now_unix, tz_minutes)
	if start > today:
		return null

	var days := _to_days(log, tz_minutes)
	var done: bool = m.get("status") == "done"
	var today_i := today - start
	var end_i := today_i
	if done and m.get("endDate"):
		end_i = clampi(day_of_date(m["endDate"]) - start, 0, today_i)

	var scope := []
	var done_s := []
	for i in end_i + 1:
		var e := _log_at(days, start + i)
		scope.append(e["s"])
		done_s.append(mini(e["dn"], e["s"]))

	var s: int = scope[end_i]
	var dn: int = done_s[end_i]
	var open := maxi(0, s - dn)
	var fc_i = null
	if not done and open > 0:
		fc_i = today_i + (float(open) / maxi(1, velocity)) * 7.0
	var dead_i = null
	if m.get("endDate"):
		dead_i = day_of_date(m["endDate"]) - start

	var max_i := maxf(maxf(end_i, 1.0), maxf(fc_i if fc_i != null else 0.0, float(dead_i) if dead_i != null else 0.0))
	var max_v := 1
	for v in scope:
		max_v = maxi(max_v, v)
	var added := 0
	var removed := 0
	for i in range(1, scope.size()):
		var diff: int = scope[i] - scope[i - 1]
		if diff > 0:
			added += diff
		else:
			removed -= diff

	return {
		"start_day": start, "scope": scope, "done_s": done_s, "s": s, "dn": dn, "open": open, "done": done,
		"today_i": today_i, "end_i": end_i, "fc_i": fc_i, "dead_i": dead_i, "max_i": max_i, "max_v": max_v,
		"added": added, "removed": removed,
	}
