extends RefCounted
## Suche nach Aufgaben eines Projekts – lokal im geladenen Stand.
##
## Gesucht wird in Titel, Labels, Beschreibung und der `$`-Nummer. Mehrere
## Wörter müssen alle vorkommen. Archiviertes ist nicht im Stand und wird
## deshalb nicht gefunden.

const Workspace := preload("workspace.gd")
const Model := preload("model.gd")


## Die Treffer, die besten zuerst: Nummer vor Titelanfang vor Titel vor
## Labels vor Beschreibung; bei Gleichstand Offenes vor Erledigtem.
static func find(ws: Workspace, project_id: String, query: String, limit := 50) -> Array:
	var words := query.to_lower().split(" ", false)
	if words.is_empty():
		return []

	var hits := []
	for t in ws.tasks:
		if t["projectId"] != project_id or not ws.is_active(t):
			continue
		var rank := _rank(t, words)
		if rank < 0:
			continue
		hits.append({"task": t, "rank": rank * 2 + (1 if Model.is_done(t) else 0)})

	hits = Model.stable_sort(hits, func(a: Dictionary, b: Dictionary) -> bool:
		return a["rank"] < b["rank"])
	var out := []
	for h in hits.slice(0, limit):
		out.append(h["task"])
	return out


## Wie gut die Aufgabe passt – kleiner ist besser, -1 heißt: gar nicht.
static func _rank(t: Dictionary, words: PackedStringArray) -> int:
	var ref := str(int(t.get("ref", 0)))
	var title: String = str(t.get("title", "")).to_lower()
	var tags: String = " ".join(PackedStringArray(t.get("tags", []))).to_lower()
	var desc: String = str(t.get("desc", "")).to_lower()

	var worst := 0
	for w in words:
		var rank := -1
		if w.trim_prefix("$") == ref:
			rank = 0
		elif title.begins_with(w):
			rank = 1
		elif title.contains(w):
			rank = 2
		elif tags.contains(w):
			rank = 3
		elif desc.contains(w):
			rank = 4
		if rank < 0:
			return -1
		worst = maxi(worst, rank)
	return worst
