extends "suite.gd"
## Titel und Beschreibung als ein Feld.

const ContentEditor := preload("res://addons/tasker/ui/content_editor.gd")


func test_die_erste_zeile_ist_der_titel() -> void:
	eq(ContentEditor.join("Titel", "eins\nzwei"), "Titel\n\neins\nzwei")
	eq(ContentEditor.join("Nur Titel", ""), "Nur Titel")
	eq(ContentEditor.split("Titel\n\neins\nzwei"), {"title": "Titel", "desc": "eins\nzwei"})
	eq(ContentEditor.split("  Titel  \neins"), {"title": "Titel", "desc": "eins"})
	eq(ContentEditor.split("Titel\n\n\n\n- [ ] a\n\nb\n"), {"title": "Titel", "desc": "- [ ] a\n\nb\n"})
	eq(ContentEditor.split("Nur Titel"), {"title": "Nur Titel", "desc": ""})
	eq(ContentEditor.split(""), {"title": "", "desc": ""})
	eq(ContentEditor.split("Titel\r\n\r\nText"), {"title": "Titel", "desc": "Text"})


func test_hin_und_zurueck_aendert_nichts() -> void:
	for pair in [["A", "b\n\nc"], ["A", ""], ["", "nur Text"], ["A", "  eingerückt"]]:
		eq(ContentEditor.split(ContentEditor.join(pair[0], pair[1])), {"title": pair[0], "desc": pair[1]})
