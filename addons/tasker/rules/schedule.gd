extends RefCounted
## Die Prognose, aus Taskers `shared/schedule.ts`: Die eingeplanten Milestones
## eines Projekts stehen nacheinander, und aus den offenen Aufgaben und dem
## Tempo ergibt sich, wann jeder fertig wird.

const Model := preload("model.gd")
const Progress := preload("progress.gd")
const Workspace := preload("workspace.gd")

const DAY := 86400


## Wochen zwischen heute und einem Kalendertag `YYYY-MM-DD`; negativ heißt
## Vergangenheit. `today` ist die Tagesnummer von heute (`Burnup.day_of`).
static func weeks_from_today(iso_day: String, today: int) -> float:
	return (int(Time.get_unix_time_from_datetime_string(iso_day.substr(0, 10))) / DAY - today) / 7.0


## Die Umkehrung: die Tagesnummer, die `weeks` Wochen von heute entfernt liegt.
static func day_from_weeks(weeks: float, today: int) -> int:
	return today + roundi(weeks * 7.0)


## Kalenderwoche nach ISO 8601 zu einer Tagesnummer.
static func iso_week(day: int) -> int:
	# Auf den Donnerstag derselben Woche schieben; dessen Jahr zählt.
	var weekday: int = Time.get_date_dict_from_unix_time(day * DAY)["weekday"]
	var thursday := day + 4 - (7 if weekday == 0 else weekday)
	var year: int = Time.get_date_dict_from_unix_time(thursday * DAY)["year"]
	var jan1 := int(Time.get_unix_time_from_datetime_string("%04d-01-01" % year)) / DAY
	return (thursday - jan1) / 7 + 1


## Die Milestones, auf die `m` wartet – eigene Abhängigkeiten und die seiner
## Aufgaben, die auf Aufgaben eines anderen Milestones warten. Gezählt wird
## nur, was eingeplant und noch nicht fertig ist.
static func milestone_deps(ws: Workspace, m: Dictionary) -> Array:
	var out := []
	var add := func(other: Variant) -> void:
		if other != null and other["id"] != m["id"] and other.get("planned", false) and not out.has(other["id"]):
			out.append(other["id"])
	for id in m.get("deps", []):
		var other = ws.milestone(id)
		if other != null and not Progress.milestone_stats(ws, other)["is_done"]:
			add.call(other)
	for root in ws.ms_roots(m):
		for task in [root] + ws.desc(root):
			for dep_id in task.get("deps", []):
				# Wartet die Aufgabe direkt auf einen Milestone, wartet auch dieser hier.
				var dep_ms = ws.milestone(dep_id)
				if dep_ms != null:
					if not Progress.milestone_stats(ws, dep_ms)["is_done"]:
						add.call(dep_ms)
					continue
				var dep = ws.task(dep_id)
				if dep == null or Model.is_done(dep):
					continue
				add.call(ws.milestone_of(dep))
	return out


## Reiht die eingeplanten Milestones je Projekt nacheinander auf.
##
## Gibt eine Liste in der Reihenfolge der Rechnung zurück, je Milestone die
## Zahlen aus `Progress.milestone_stats` und dazu:
## `{ milestone, deps, start, end, forecast_end, fixed, fixed_end, early, late, pos }`
## – `start` und `end` in Wochen ab heute.
static func schedule(ws: Workspace, velocity: int, today: int) -> Array:
	var speed := maxf(1.0, velocity)
	var planned := ws.planned_milestones()
	var by_id := {}
	for m in planned:
		var x := Progress.milestone_stats(ws, m)
		x.merge({
			"milestone": m, "deps": milestone_deps(ws, m), "start": 0.0, "end": 0.0, "forecast_end": 0.0,
			"fixed": false, "fixed_end": false, "early": false, "late": false, "pos": 0,
		})
		by_id[m["id"]] = x

	var pending := planned.duplicate()
	var list := []
	# Jedes Projekt hat seine eigene Reihe: Projekte verschieben sich nicht
	# gegenseitig. Nur eine ausdrückliche Abhängigkeit wirkt über die Grenze.
	var cursors := {}
	while not pending.is_empty():
		# Als Nächstes der erste, dessen Abhängigkeiten schon eingeplant sind.
		# Bei einem Kreis greift der Rückfall auf den ersten Eintrag.
		var at := 0
		for i in pending.size():
			var free := true
			for d in by_id[pending[i]["id"]]["deps"]:
				if pending.any(func(p: Dictionary) -> bool: return p["id"] == d):
					free = false
					break
			if free:
				at = i
				break
		var m: Dictionary = pending.pop_at(at)
		var x: Dictionary = by_id[m["id"]]
		var dep_end := 0.0
		for d in x["deps"]:
			dep_end = maxf(dep_end, by_id[d]["end"] if by_id.has(d) else 0.0)
		var cursor: float = cursors.get(m["projectId"], 0.0)

		x["fixed"] = m.get("startDate") != null
		x["fixed_end"] = m.get("endDate") != null
		# Mit Startdatum beginnt der Milestone dort; ohne nach dem vorherigen
		# beziehungsweise nach den Abhängigkeiten.
		x["start"] = weeks_from_today(m["startDate"], today) if x["fixed"] else maxf(cursor, dep_end)
		x["early"] = x["fixed"] and x["deps"].size() > 0 and x["start"] < dep_end - 1e-6
		# Liegt der Start in der Vergangenheit, wird die Restarbeit ab heute gerechnet.
		x["forecast_end"] = maxf(x["start"], 0.0) + x["open"] / speed
		x["end"] = weeks_from_today(m["endDate"], today) if x["fixed_end"] else x["forecast_end"]
		if x["fixed_end"] and not x["fixed"]:
			x["start"] = minf(x["start"], x["end"])
		x["late"] = not x["is_done"] and x["fixed_end"] and x["forecast_end"] > x["end"] + 1e-6

		cursors[m["projectId"]] = maxf(cursor, x["end"] if x["is_done"] else maxf(x["end"], x["forecast_end"]))
		x["pos"] = list.size() + 1
		list.append(x)
	return list
