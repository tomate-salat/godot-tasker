extends "suite.gd"
## Listen weiterschreiben – die Fälle aus Taskers `shared/listEdit.test.ts`.

const ListEdit := preload("res://addons/tasker/rules/list_edit.gd")


## Text mit `|` als Schreibmarke (oder zwei `|` als Auswahl) → Ergebnis im
## selben Format, oder null.
func _run(src: String, f: Callable) -> Variant:
	var s := src.find("|")
	var rest := src.substr(0, s) + src.substr(s + 1)
	var e2 := rest.find("|")
	var value := rest if e2 < 0 else rest.substr(0, e2) + rest.substr(e2 + 1)
	var e := s if e2 < 0 else e2
	var edit = f.call(value, s, e)
	if edit == null:
		return null
	var out: String = value.substr(0, edit["from"]) + edit["text"] + value.substr(edit["to"])
	var a: int = edit["sel_start"]
	var b: int = edit["sel_end"]
	if a == b:
		return out.substr(0, a) + "|" + out.substr(a)
	return out.substr(0, a) + "|" + out.substr(a, b - a) + "|" + out.substr(b)


func _enter(src: String) -> Variant:
	return _run(src, ListEdit.enter_in_list)


func _tab(src: String) -> Variant:
	return _run(src, func(v: String, s: int, e: int) -> Variant: return ListEdit.tab_in_list(v, s, e, 1))


func _untab(src: String) -> Variant:
	return _run(src, func(v: String, s: int, e: int) -> Variant: return ListEdit.tab_in_list(v, s, e, -1))


func _up(src: String) -> Variant:
	return _run(src, func(v: String, s: int, e: int) -> Variant: return ListEdit.move_lines(v, s, e, -1))


func _down(src: String) -> Variant:
	return _run(src, func(v: String, s: int, e: int) -> Variant: return ListEdit.move_lines(v, s, e, 1))


func _brk(src: String) -> Variant:
	return _run(src, ListEdit.break_in_item)


func test_enter_setzt_eine_checkliste_mit_leerem_kaestchen_fort() -> void:
	eq(_enter("- [ ] Abc|"), "- [ ] Abc\n- [ ] |")
	eq(_enter("- [x] Erledigt|"), "- [x] Erledigt\n- [ ] |")


func test_enter_setzt_aufzaehlungen_und_nummerierte_listen_fort() -> void:
	eq(_enter("- Abc|"), "- Abc\n- |")
	eq(_enter("* Abc|"), "* Abc\n* |")
	eq(_enter("1. Abc|"), "1. Abc\n2. |")
	eq(_enter("9) Abc|"), "9) Abc\n10) |")


func test_enter_behaelt_die_einrueckung_und_nimmt_text_hinter_der_marke_mit() -> void:
	eq(_enter("- a\n  - b|"), "- a\n  - b\n  - |")
	eq(_enter("- Ab|c"), "- Ab\n- |c")


func test_enter_beendet_die_liste_in_einem_leeren_punkt() -> void:
	eq(_enter("- a\n- |"), "- a\n|")
	eq(_enter("- [ ] a\n- [ ] |"), "- [ ] a\n|")


func test_enter_geht_in_einem_leeren_eingerueckten_punkt_eine_ebene_hinauf() -> void:
	eq(_enter("- a\n  - |"), "- a\n- |")


func test_enter_beginnt_auch_in_einer_folgezeile_den_naechsten_punkt() -> void:
	eq(_enter("- [ ] Abc\n- [ ] Def\n  ghi|"), "- [ ] Abc\n- [ ] Def\n  ghi\n- [ ] |")
	eq(_enter("- a\n  - b\n\n    mehr|"), "- a\n  - b\n\n    mehr\n  - |")
	eq(_enter("1. a\n   text|"), "1. a\n   text\n2. |")


func test_enter_laesst_normalen_text_und_stellen_vor_der_marke_in_ruhe() -> void:
	eq(_enter("Absatz\n  eingerückt|"), null)
	eq(_enter("- a\n  |"), null)
	eq(_enter("Abc|"), null)
	eq(_enter("-Abc|"), null)
	eq(_enter("|- Abc"), null)
	eq(_enter("- a|b|c"), null)


func test_tab_rueckt_unter_den_punkt_darueber_ein_und_wieder_aus() -> void:
	eq(_tab("- a\n- b|"), "- a\n  - b|")
	eq(_untab("- a\n  - b|"), "- a\n- b|")


func test_tab_unter_nummerierten_punkten_zaehlt_neu() -> void:
	eq(_tab("1. a\n2. b|"), "1. a\n   1. b|")
	eq(_untab("1. a\n   1. b|"), "1. a\n2. b|")


func test_tab_rueckt_alle_markierten_listenpunkte_ein() -> void:
	eq(_tab("- a\n- |b\n- c|"), "- a\n  - |b\n  - c|")


func test_tab_macht_ausserhalb_von_listen_nichts() -> void:
	eq(_tab("Abc|"), null)
	eq(_untab("- a|"), null)


func test_tab_behaelt_das_kaestchen() -> void:
	eq(_tab("- [ ] a\n- [ ] b|"), "- [ ] a\n  - [ ] b|")


func test_zeile_tauscht_mit_der_darueber_und_nimmt_die_schreibmarke_mit() -> void:
	eq(_up("- [ ] Repair\n- [ ] De|stroy"), "- [ ] De|stroy\n- [ ] Repair")


func test_zeile_tauscht_mit_der_darunter() -> void:
	eq(_down("- [ ] Re|pair\n- [ ] Destroy"), "- [ ] Destroy\n- [ ] Re|pair")


func test_zeilen_bleiben_am_rand_stehen() -> void:
	eq(_up("- [ ] Re|pair\n- [ ] Destroy"), null)
	eq(_down("- [ ] Repair\n- [ ] De|stroy"), null)


func test_eine_markierung_ueber_mehrere_zeilen_wandert_als_block() -> void:
	eq(_down("a\n|b\nc|\nd"), "a\nd\n|b\nc|")
	eq(_up("a\n|b\nc|\nd"), "|b\nc|\na\nd")


func test_verschieben_kuemmert_sich_nicht_um_den_inhalt_der_zeile() -> void:
	eq(_down("-----\nText|"), null)
	eq(_up("-----\nTe|xt"), "Te|xt\n-----")


func test_verschieben_kommt_mit_leeren_zeilen_zurecht() -> void:
	eq(_up("a\n\nb|"), "a\nb|\n")
	eq(_down("|\na"), "a\n|")


func test_umbruch_rueckt_die_neue_zeile_unter_den_inhalt_des_punktes() -> void:
	eq(_brk("- [ ] test|"), "- [ ] test\n  |")
	eq(_brk("- abc|"), "- abc\n  |")
	eq(_brk("1. abc|"), "1. abc\n   |")
	eq(_brk("- a\n  - b|"), "- a\n  - b\n    |")


func test_umbruch_behaelt_in_einer_folgezeile_deren_einrueckung() -> void:
	eq(_brk("- [ ] test\n  abc|"), "- [ ] test\n  abc\n  |")
	eq(_brk("- [ ] test\n    abc\n\n    def|"), "- [ ] test\n    abc\n\n    def\n    |")
	eq(_brk("- [ ] test\n  |"), "- [ ] test\n  \n  |")


func test_umbruch_nimmt_den_text_hinter_der_schreibmarke_mit() -> void:
	eq(_brk("- abc|def"), "- abc\n  |def")


func test_umbruch_laesst_normalen_text_in_ruhe() -> void:
	eq(_brk("Abc|"), null)
	eq(_brk("  eingerückt|"), null)
	eq(_brk("|- abc"), null)
	eq(_brk("Absatz\n  abc|"), null)
