@tool
extends RefCounted
## Ausgedachte Daten, damit der Tisch auch ohne Verbindung etwas zeigt.

const PROJECT := "demo"


static func data() -> Dictionary:
	var tasks := []
	var add := func(id: String, title: String, o := {}) -> void:
		var t := {
			"id": id, "ref": tasks.size() + 2, "version": 1, "projectId": PROJECT, "parentId": null,
			"milestoneId": "ms", "groupId": null, "doc": false, "title": title, "desc": "", "prio": 0,
			"status": "open", "doneAt": null, "order": tasks.size(), "categoryId": null, "markId": null,
			"ready": false, "coverImageId": null, "playOrder": 0, "archivedAt": null, "tags": [], "deps": [],
		}
		t.merge(o, true)
		if t["parentId"] != null:
			t["milestoneId"] = null
		tasks.append(t)

	add.call("a", "Hauptmenü aufräumen", {"prio": 2, "desc": "## Ziel
Das Menü soll **schlanker** werden, siehe $13.

- [x] Einträge sammeln
- [ ] Reihenfolge festlegen
  - `Optionen` nach unten

> Nicht vor dem Speichern anfassen.

Mehr unter https://example.com/menue"})
	add.call("b", "Speicherstände", {"prio": 1, "desc": "- [x] Format festlegen\n- [ ] Schreiben\n- [ ] Laden"})
	add.call("c", "Kamera folgt dem Spieler")
	add.call("d", "Level 2 mit langem Titel", {"markId": "mk"})
	add.call("d1", "Grundriss", {"parentId": "d", "status": "done", "doneAt": "2026-10-05T09:00:00.000Z"})
	add.call("d2", "Beleuchtung", {"parentId": "d", "status": "progress", "playOrder": 2})
	add.call("d3", "Gegner platzieren", {"parentId": "d"})
	add.call("e", "Partikel beim Landen", {"prio": 3})
	add.call("f", "Tonspur abmischen", {"status": "unclear"})
	add.call("g", "Abspann")
	add.call("h", "Sprungphysik", {"status": "progress", "playOrder": 1, "prio": 1})
	add.call("i", "Wandsprung", {"deps": ["h"]})
	add.call("j", "Steuerung belegen", {"status": "done", "doneAt": "2026-10-02T14:00:00.000Z"})
	add.call("k", "Projekt anlegen", {"status": "done", "doneAt": "2026-09-29T10:00:00.000Z"})

	# Für die Planung: zwei weitere Decks, ein abgeschlossenes und ein Vorrat.
	add.call("p1", "Prototyp-Szene", {"milestoneId": "ms0", "status": "done", "doneAt": "2026-09-20T10:00:00.000Z"})
	add.call("n1", "Bossraum", {"milestoneId": "ms2", "deps": ["m2"]})
	add.call("n2", "Fallen", {"milestoneId": "ms2", "deps": ["n1"]})
	add.call("n3", "Schatztruhen", {"milestoneId": "ms2"})
	add.call("n3a", "Modell", {"parentId": "n3"})
	add.call("n3b", "Beute würfeln", {"parentId": "n3"})
	add.call("n4", "Geheimgang", {"milestoneId": "ms2", "deps": ["r2"]})
	add.call("m1", "Optionen", {"milestoneId": "ms3"})
	add.call("m2", "Speichern im Bossraum", {"milestoneId": "ms3"})
	# Eine Kette über mehrere Stufen, damit der Graph etwas zu zeigen hat.
	add.call("q1", "Quest Model", {"milestoneId": "ms3", "status": "done", "doneAt": "2026-10-01T10:00:00.000Z"})
	add.call("q2", "Player Quest Support", {"milestoneId": "ms3", "status": "done", "doneAt": "2026-10-02T10:00:00.000Z", "deps": ["q1"]})
	add.call("q3", "Quest Generator", {"milestoneId": "ms3", "status": "done", "doneAt": "2026-10-03T10:00:00.000Z", "deps": ["q1"]})
	add.call("q4", "Quest Board", {"milestoneId": "ms3", "deps": ["q1", "q2", "q3"]})
	add.call("q5", "Update Enter Arena Dialog", {"milestoneId": "ms3", "deps": ["q2", "q4"]})
	add.call("r1", "Lichtkonzept", {"milestoneId": null, "ready": true})
	add.call("r2", "Gegner-KI", {"milestoneId": null, "ready": true, "deps": ["v3"]})
	add.call("r2a", "Pfadfindung", {"parentId": "r2"})
	add.call("r3", "Tutorial-Text", {"milestoneId": null, "ready": true, "markId": "mk"})
	for i in 26:
		add.call("v%d" % i, ["Soundkulisse", "Kamerafahrt", "Zwischensequenz", "Erfolge", "Bestenliste", "Fotomodus", "Wetter"][i % 7] + (" %d" % (i / 7 + 1) if i >= 7 else ""),
			{"milestoneId": null, "groupId": "gr" if i < 5 else null})

	return {
		"projects": [{"id": PROJECT, "version": 1, "name": "Beispiel", "color": "#2A6B5A", "order": 0, "coverImageId": null}],
		"categories": [],
		"marks": [{"id": "mk", "version": 1, "projectId": PROJECT, "emoji": "🔧", "name": "Wichtig", "order": 0, "coverImageId": null}],
		"groups": [{"id": "gr", "version": 1, "projectId": PROJECT, "title": "Stimmung", "order": 0, "archivedAt": null}],
		"milestones": [{
			"id": "ms", "ref": 1, "version": 1, "projectId": PROJECT, "title": "Erster spielbarer Stand", "desc": "",
			"planned": true, "status": "progress", "order": 0, "qorder": 0, "startDate": null, "endDate": null,
			"endAuto": false, "archivedAt": null, "deps": [],
		}, {
			"id": "ms0", "ref": 90, "version": 1, "projectId": PROJECT, "title": "Prototyp", "desc": "",
			"planned": true, "status": "done", "order": 1, "qorder": -1, "startDate": null, "endDate": null,
			"endAuto": false, "archivedAt": null, "deps": [],
		}, {
			"id": "ms2", "ref": 91, "version": 1, "projectId": PROJECT, "title": "Level 3 und der Bossraum", "desc": "",
			"planned": true, "status": "open", "order": 2, "qorder": 1, "startDate": null, "endDate": "2026-10-20",
			"endAuto": false, "archivedAt": null, "deps": [],
		}, {
			"id": "ms3", "ref": 92, "version": 1, "projectId": PROJECT, "title": "Menüs", "desc": "",
			"planned": true, "status": "open", "order": 3, "qorder": 2, "startDate": null, "endDate": null,
			"endAuto": false, "archivedAt": null, "deps": [],
		}],
		"tasks": tasks,
	}
