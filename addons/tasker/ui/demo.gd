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

	return {
		"projects": [{"id": PROJECT, "version": 1, "name": "Beispiel", "color": "#2A6B5A", "order": 0, "coverImageId": null}],
		"categories": [],
		"marks": [{"id": "mk", "version": 1, "projectId": PROJECT, "emoji": "🔧", "name": "Wichtig", "order": 0, "coverImageId": null}],
		"groups": [],
		"milestones": [{
			"id": "ms", "ref": 1, "version": 1, "projectId": PROJECT, "title": "Erster spielbarer Stand", "desc": "",
			"planned": true, "status": "progress", "order": 0, "qorder": 0, "startDate": null, "endDate": null,
			"endAuto": false, "archivedAt": null, "deps": [],
		}],
		"tasks": tasks,
	}
