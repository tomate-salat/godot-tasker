extends "suite.gd"
## Markdown der Beschreibungen zu BBCode.

const Markdown := preload("res://addons/tasker/ui/markdown.gd")


func _titles(n: int) -> String:
	return "Sprungphysik" if n == 142 else ""


func test_ueberschriften_hervorhebungen_und_zeilenumbrueche() -> void:
	eq(Markdown.to_bbcode("# Titel\nerste Zeile\nzweite **fett** und *kursiv* und ~~weg~~"),
		"[font_size=22][b]Titel[/b][/font_size]\nerste Zeile\nzweite [b]fett[/b] und [i]kursiv[/i] und [s]weg[/s]")
	eq(Markdown.to_bbcode(null), "")


func test_listen_und_checklisten_mit_einrueckung() -> void:
	eq(Markdown.to_bbcode("- eins\n  - zwei\n1. drei\n- [ ] offen\n- [x] fertig"),
		"• eins\n    • zwei\n1. drei\n☐ offen\n☑ [color=#9ba49f]fertig[/color]")


func test_code_bleibt_woertlich() -> void:
	eq(Markdown.to_bbcode("vor `a*b*c [x]` nach"),
		"vor [code][color=#e6ae58]a*b*c [lb]x][/color][/code] nach")
	eq(Markdown.to_bbcode("```gdscript\nvar a = **b**\n```\ndanach"),
		"[code][color=#e6ae58]var a = **b**[/color][/code]\ndanach")


func test_eckige_klammern_werden_keine_tags() -> void:
	eq(Markdown.to_bbcode("Feld [b] bleibt Text"), "Feld [lb]b] bleibt Text")


func test_links_und_nackte_adressen() -> void:
	eq(Markdown.to_bbcode("siehe [Doku](https://example.com/a_b) oder https://example.com/x_y_z"),
		"siehe [url=https://example.com/a_b]Doku[/url] oder [url]https://example.com/x_y_z[/url]")


func test_unterstriche_in_woertern_sind_keine_hervorhebung() -> void:
	eq(Markdown.to_bbcode("player_move_speed und _betont_"), "player_move_speed und [i]betont[/i]")


func test_verweise_werden_links_mit_titel() -> void:
	eq(Markdown.to_bbcode("wartet auf $142, nicht auf $7 oder 5$ oder a$142", _titles),
		"wartet auf [url=tasker:142]$142 Sprungphysik[/url], nicht auf $7 oder 5$ oder a$142")


func test_bilder_der_galerie_bekommen_eine_marke_andere_nur_ihren_namen() -> void:
	eq(Markdown.to_bbcode("![Skizze](/api/bilder/abc123)"), Markdown.IMAGE + "abc123" + Markdown.IMAGE)
	eq(Markdown.to_bbcode("![Logo](https://example.com/logo.png)"), "[color=#9ba49f]▣ Logo[/color]")
	eq(Markdown.to_bbcode("![[zeichnung:Level 2]]"), Markdown.IMAGE + "zeichnung:Level 2" + Markdown.IMAGE)


func test_zitat_und_trennlinie() -> void:
	eq(Markdown.to_bbcode("> gesagt\n---"),
		"[indent][color=#9ba49f][i]gesagt[/i][/color][/indent]\n[color=#9ba49f]────────────[/color]")
