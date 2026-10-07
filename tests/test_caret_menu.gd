extends "suite.gd"
## Befehle nach `/` und Verweise nach `$` im Beschreibungsfeld.

const CaretMenu := preload("res://addons/tasker/rules/caret_menu.gd")


## Text mit `|` als Schreibmarke: Befehl an der Suche davor übernehmen.
func _slash(src: String, id: String) -> Variant:
	var caret := src.find("|")
	var value := src.replace("|", "")
	var q = CaretMenu.query_at(value, caret, CaretMenu.SLASH)
	if q == null:
		return null
	var command: Dictionary = CaretMenu.SLASH_COMMANDS.filter(func(c: Dictionary) -> bool: return c["id"] == id)[0]
	var edit := CaretMenu.slash_edit(value, q["start"], caret, command)
	var out: String = value.substr(0, edit["from"]) + edit["text"] + value.substr(edit["to"])
	return out.substr(0, edit["sel_start"]) + "|" + out.substr(edit["sel_start"])


func _labels(query: String) -> Array:
	return CaretMenu.slash_matches(query).map(func(c: Dictionary) -> String: return c["label"])


func test_die_suche_beginnt_nach_dem_ausloesezeichen() -> void:
	eq(CaretMenu.query_at("a /to", 5, CaretMenu.SLASH), {"start": 2, "text": "to"})
	eq(CaretMenu.query_at("/", 1, CaretMenu.SLASH), {"start": 0, "text": ""})
	eq(CaretMenu.query_at("Zeile\n/li", 9, CaretMenu.SLASH), {"start": 6, "text": "li"})
	eq(CaretMenu.query_at("a/b", 3, CaretMenu.SLASH), null, "mitten im Wort kein Befehl")
	eq(CaretMenu.query_at("/a b", 4, CaretMenu.SLASH), null, "nach einem Leerzeichen ist die Suche vorbei")
	eq(CaretMenu.query_at("/abc", 2, CaretMenu.SLASH), {"start": 0, "text": "a"}, "es zählt, was vor der Schreibmarke steht")
	eq(CaretMenu.query_at("siehe $14", 9, CaretMenu.REF), {"start": 6, "text": "14"})
	eq(CaretMenu.query_at("$", 1, CaretMenu.REF), {"start": 0, "text": ""})
	eq(CaretMenu.query_at("5$", 2, CaretMenu.REF), null, "ein Betrag ist kein Verweis")
	eq(CaretMenu.query_at("$$a", 3, CaretMenu.REF), null)


func test_befehle_werden_nach_name_und_stichwort_gefunden() -> void:
	eq(_labels(""), ["TodoListe", "Liste"])
	eq(_labels("to"), ["TodoListe"])
	eq(_labels("li"), ["Liste", "TodoListe"], "wer so anfängt, steht vorn")
	eq(_labels("check"), ["TodoListe"])
	eq(_labels("bul"), ["Liste"])
	eq(_labels("xyz"), [])


func test_ein_befehl_beginnt_die_leere_zeile() -> void:
	eq(_slash("/|", "todo"), "- [ ] |")
	eq(_slash("Titel\n\n/to|", "todo"), "Titel\n\n- [ ] |")
	eq(_slash("  /|", "list"), "  - |")


func test_ein_befehl_ersetzt_einen_leeren_listenpunkt() -> void:
	eq(_slash("- /|", "todo"), "- [ ] |")
	eq(_slash("  - [ ] /li|", "list"), "  - |")


func test_ein_befehl_hinter_text_beginnt_eine_neue_zeile_darunter() -> void:
	eq(_slash("Text /|", "todo"), "Text\n- [ ] |")
	eq(_slash("  - a /|", "list"), "  - a\n  - |")
	eq(_slash("Text /to| und mehr", "todo"), "Text\n- [ ] | und mehr")


func _targets() -> Workspace:
	return Builder.new() \
		.project("p").project("q") \
		.milestone("Menüs", "p") \
		.task("Kamera", "p") \
		.task("Kampf", "q") \
		.task("Karte", "p", {"status": "done"}) \
		.task("Nebenkamera", "p") \
		.task("Selbst", "p") \
		.build()


func _titles(query: String) -> Array:
	return CaretMenu.ref_search(_targets(), query, "p", "Selbst").map(func(t: Dictionary) -> String: return t["title"])


func test_verweise_eigenes_projekt_zuerst_erledigtes_zuletzt() -> void:
	eq(_titles(""), ["Kamera", "Menüs", "Nebenkamera", "Kampf", "Karte"])
	eq(_titles("ka"), ["Kamera", "Nebenkamera", "Kampf", "Karte"], "Anfang vor Mitte, fremdes Projekt danach")
	eq(_titles("KAM"), ["Kamera", "Nebenkamera", "Kampf"])
	eq(_titles("selbst"), [], "auf sich selbst verweist man nicht")


func test_verweise_nach_nummer() -> void:
	eq(_titles("1"), ["Menüs"])
	eq(_titles("3"), ["Kampf"])
	eq(_titles("9"), [])


func test_ein_verweis_ersetzt_das_getippte() -> void:
	var hit: Dictionary = CaretMenu.ref_search(_targets(), "kame", "p", "Selbst")[0]
	eq(hit["ref"], 2)
	eq(hit["kind"], "task")
	eq(CaretMenu.ref_icon(hit), "")
	eq(CaretMenu.ref_edit(6, 11, hit), {"from": 6, "to": 11, "text": "$2 ", "sel_start": 9, "sel_end": 9})
	eq(CaretMenu.ref_icon(CaretMenu.ref_search(_targets(), "men", "p", "Selbst")[0]), "◆ ")
