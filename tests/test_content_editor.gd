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


func test_stellen_im_text_und_zeile_mit_spalte_sind_dasselbe() -> void:
	var text := "ab\n\ncde\n"
	eq(ContentEditor.offset_of(text, 0, 0), 0)
	eq(ContentEditor.offset_of(text, 1, 0), 3)
	eq(ContentEditor.offset_of(text, 2, 2), 6)
	eq(ContentEditor.offset_of(text, 3, 0), 8)
	for at in text.length() + 1:
		var place := ContentEditor.place_of(text, at)
		eq(ContentEditor.offset_of(text, place.x, place.y), at)
