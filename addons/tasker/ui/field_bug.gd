@tool
extends Node2D
## Ein Käfer von oben: ein Schädling, ein Marienkäfer oder der große Käfer
## des Milestones. Gezeichnet, nicht geladen – so gibt es ihn in jeder Größe.
##
## Der Käfer sitzt mit seiner Mitte auf `position` und schaut nach `rotation`
## (0 heißt: Kopf nach oben). Er ist kein Bedienelement: so zeichnet Godot ihn
## auch dann, wenn seine Mitte knapp außerhalb des Bildes liegt.

const Palette := preload("palette.gd")

const PEST := "pest"
const LADY := "lady"
const BOSS := "boss"

## Womit gekämpft wird: Marienkäfer gegen Schädlinge oder Soldaten gegen Soldaten.
const BUGS := "bugs"
const SOLDIERS := "soldiers"
static var style := SOLDIERS

## Wie die Soldaten gezeichnet sind – fünf Vorschläge zur Auswahl.
const LOOK_PLAIN := "a"
const LOOK_OUTLINE := "b"
const LOOK_CHUNKY := "c"
const LOOK_TOY := "d"
const LOOK_TOKEN := "e"
const LOOK_ROUND := "f"
static var look := LOOK_ROUND

var kind := PEST: set = set_kind
## Wie groß er ist: 1 passt gut auf eine Karte.
var girth := 1.0: set = set_girth
## Wie sehr ihm schon zugesetzt wurde, 0 bis 1: mit jedem Sechstel fehlt ein Bein.
var hurt := 0.0: set = set_hurt
## Besiegt: er liegt auf dem Rücken.
var dead := false: set = set_dead
## Eine Mauer statt eines Tiers: die Karte steht selbst auf „Blockiert“.
var wall := false: set = set_wall

## Die sechs Beine: wo sie am Körper ansetzen und wohin sie zeigen.
const LEGS := [
	[Vector2(-6, -4), Vector2(-14, -9)], [Vector2(6, -4), Vector2(14, -9)],
	[Vector2(-7, 1), Vector2(-16, 1)], [Vector2(7, 1), Vector2(16, 1)],
	[Vector2(-6, 6), Vector2(-14, 11)], [Vector2(6, 6), Vector2(14, 11)],
]


func set_kind(value: String) -> void:
	kind = value
	queue_redraw()


func set_girth(value: float) -> void:
	girth = value
	queue_redraw()


func set_hurt(value: float) -> void:
	hurt = clampf(value, 0.0, 1.0)
	queue_redraw()


func set_dead(value: bool) -> void:
	dead = value
	queue_redraw()


func set_wall(value: bool) -> void:
	wall = value
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(girth, girth))
	if wall:
		_draw_wall()
	elif style == SOLDIERS:
		if kind == BOSS:
			_draw_tank()
		else:
			_draw_soldier(kind == PEST)
			if kind == PEST and not dead and hurt > 0.0:
				_draw_health()
	elif kind == BOSS:
		_draw_boss()
	elif kind == LADY:
		_draw_lady()
	else:
		_draw_pest()
	draw_set_transform(Vector2.ZERO)


## Der große Käfer des Milestones: ein Hirschkäfer von oben, mit Geweih,
## gegliederten Beinen und glänzenden Flügeldecken.
func _draw_boss() -> void:
	var shell := Color("2c1f3d")
	var shell_light := Color("5b3f7c")
	var chest := Color("231830")
	var horn := Color("8a3d2c")
	var horn_light := Color("c0694a")
	var leg := Color("17111f")

	# Schatten unter dem Tier.
	_ellipse_plain(Vector2(1.5, 5.0), Vector2(12.5, 15.0), Color(0, 0, 0, 0.22))

	# Die Beine: Schenkel, Schiene, Fuß – vorn nach vorn, hinten nach hinten.
	for side in [-1.0, 1.0]:
		for part in [
			[Vector2(6, -6), Vector2(13, -11), Vector2(15, -17), Vector2(17, -19)],
			[Vector2(8, 1), Vector2(15, 1), Vector2(19, 5), Vector2(21, 5)],
			[Vector2(7, 8), Vector2(13, 13), Vector2(14, 20), Vector2(16, 22)],
		]:
			var points := PackedVector2Array()
			for p in part:
				points.append(Vector2(p.x * side, p.y))
			draw_line(points[0], points[1], leg, 2.2, false)
			draw_line(points[1], points[2], leg, 1.5, false)
			draw_line(points[2], points[3], leg, 1.0, false)
			draw_circle(points[1], 1.3, leg, true, -1.0, false)

	# Das Geweih: zwei geschwungene Zangen mit einem Zahn nach innen.
	for side in [-1.0, 1.0]:
		var antler := PackedVector2Array()
		for p in [Vector2(2.5, -14), Vector2(6.5, -18), Vector2(8, -23), Vector2(6, -27.5), Vector2(3, -29)]:
			antler.append(Vector2(p.x * side, p.y))
		draw_polyline(antler, horn, 2.4, false)
		draw_polyline(antler, horn_light, 0.8, false)
		draw_line(Vector2(7.6 * side, -22), Vector2(4.6 * side, -22.5), horn, 1.6, false)
		# Fühler
		draw_line(Vector2(3.5 * side, -13), Vector2(9 * side, -15), leg, 0.9, false)
		draw_line(Vector2(9 * side, -15), Vector2(11 * side, -13), leg, 1.6, false)

	# Kopf, Brustschild, Flügeldecken.
	_rounded(Rect2(-4.5, -16.5, 9.0, 5.5), 2.0, chest)
	draw_circle(Vector2(-3.6, -14.5), 1.1, Color("e6ae58"), true, -1.0, false)
	draw_circle(Vector2(3.6, -14.5), 1.1, Color("e6ae58"), true, -1.0, false)
	_rounded(Rect2(-8.0, -12.0, 16.0, 8.5), 3.5, chest)
	draw_line(Vector2(-5.5, -10.2), Vector2(5.5, -10.2), Color(1, 1, 1, 0.12), 1.0, false)
	_ellipse_plain(Vector2(0, 6.0), Vector2(10.5, 12.5), shell)
	# Glanz: ein heller Bogen auf jeder Flügeldecke und feine Rillen.
	for side in [-1.0, 1.0]:
		var gloss := PackedVector2Array()
		for i in 9:
			var a := lerpf(-2.2, -0.9, i / 8.0)
			gloss.append(Vector2(0, 6.0) + Vector2(cos(a) * 7.6 * side * -1.0, sin(a) * 9.8))
		draw_polyline(gloss, Color(shell_light, 0.85), 1.6, false)
		for ridge in [3.2, 6.2]:
			var line := PackedVector2Array()
			for i in 9:
				var y := lerpf(-3.0, 15.0, i / 8.0)
				var bulge := sqrt(maxf(1.0 - pow((y - 6.0) / 12.5, 2.0), 0.0))
				line.append(Vector2(ridge * side * bulge, y))
			draw_polyline(line, Color(0, 0, 0, 0.28), 0.7, false)
	draw_line(Vector2(0, -4.5), Vector2(0, 18.0), Color(0, 0, 0, 0.55), 1.0, false)
	# Das kleine Schildchen, wo die Flügeldecken zusammenstoßen.
	draw_colored_polygon(PackedVector2Array([Vector2(-2.2, -4.5), Vector2(2.2, -4.5), Vector2(0, -0.8)]), chest)


# ------------------------------------------------------------ Soldaten

## Ein Soldat von oben: Helm, Schultern, das Gewehr nach vorn. Die eigenen
## sind blau, die gegnerischen rot; unter einem Gegner steht, wie viel er noch
## aushält.
func _draw_soldier(enemy: bool) -> void:
	if PIXELS.has(look):
		if enemy and not dead:
			_ellipse_plain(Vector2(0, 1), Vector2(16.0, 17.0), Color(0, 0, 0, 0.42))
		_draw_pixels(PIXELS[look], _pixel_colors(enemy))
		return
	if dead:
		# Gefallen: grau, ohne Waffe, lang ausgestreckt.
		_ellipse_plain(Vector2(0, 4), Vector2(5.0, 10.0), Color("7b817d"))
		draw_circle(Vector2(0, -7), 4.5, Color("8f9590"), true, -1.0, false)
		return
	if enemy and look == LOOK_PLAIN:
		_ellipse_plain(Vector2(0, 1), Vector2(16.0, 17.0), Color(0, 0, 0, 0.42))
	match look:
		LOOK_OUTLINE:
			_soldier_outline(enemy)
		LOOK_CHUNKY:
			_soldier_chunky(enemy)
		LOOK_TOY:
			_soldier_toy(enemy)
		LOOK_ROUND:
			_soldier_round(enemy)
		LOOK_TOKEN:
			_soldier_token(enemy)
		_:
			_soldier_plain(enemy)


## A – schlicht: Rucksack, Schultern, die Arme nach vorn ans Gewehr, darüber der Helm.
func _soldier_plain(enemy: bool) -> void:
	var cloth := Color("b8463c") if enemy else Color("3d74c2")
	var helmet := Color("7c2a24") if enemy else Color("234a85")
	var gun := Color("8a9297")
	var skin := Color("e2b48c")
	var sleeve := cloth.darkened(0.2)
	_rounded(Rect2(-4.5, 3.5, 9.0, 5.5), 1.5, cloth.darkened(0.35))
	draw_line(Vector2(3.5, -2), Vector2(3.5, -19), gun, 2.0, false)
	draw_line(Vector2(3.5, -19), Vector2(3.5, -22), Color("c9d1cd"), 1.2, false)
	_ellipse_plain(Vector2(0, 1.5), Vector2(10.5, 4.6), cloth)
	draw_line(Vector2(8.5, 0.5), Vector2(4.5, -6.5), sleeve, 2.6, false)
	draw_line(Vector2(-8.5, 0.5), Vector2(2.5, -11.5), sleeve, 2.6, false)
	draw_circle(Vector2(4.2, -7), 1.6, skin, true, -1.0, false)
	draw_circle(Vector2(2.8, -12), 1.6, skin, true, -1.0, false)
	draw_circle(Vector2(0, 0), 5.4, helmet, true, -1.0, false)
	draw_circle(Vector2(0, 0), 5.4, Color(0, 0, 0, 0.35), false, 0.7, false)
	draw_circle(Vector2(-1.3, -1.3), 2.0, helmet.lightened(0.28), true, -1.0, false)


## B – mit Kontur: klare Flächen, jede dunkel umrandet, wie in einem Comic.
func _soldier_outline(enemy: bool) -> void:
	var cloth := Color("d2574b") if enemy else Color("4c8be0")
	var helmet := Color("9a3229") if enemy else Color("2c5cab")
	var ink := Color("0d1012")
	var gun := Color("4a5258")
	var skin := Color("f0c49a")
	# Erst alles etwas größer in Schwarz, dann die Farbe darauf.
	_rounded(Rect2(-10.2, -4.2, 20.4, 11.4), 4.5, ink)
	_rounded(Rect2(1.3, -22.2, 5.4, 20.4), 1.5, ink)
	draw_circle(Vector2(0, -0.5), 7.0, ink, true, -1.0, false)
	_rounded(Rect2(-9.0, -3.0, 18.0, 9.0), 3.8, cloth)
	_rounded(Rect2(2.4, -21.0, 3.2, 18.0), 1.0, gun)
	draw_circle(Vector2(4.0, -7.5), 2.6, ink, true, -1.0, false)
	draw_circle(Vector2(4.0, -13.5), 2.6, ink, true, -1.0, false)
	draw_circle(Vector2(4.0, -7.5), 1.7, skin, true, -1.0, false)
	draw_circle(Vector2(4.0, -13.5), 1.7, skin, true, -1.0, false)
	draw_circle(Vector2(0, -0.5), 5.8, helmet, true, -1.0, false)
	draw_circle(Vector2(-1.6, -2.2), 1.8, helmet.lightened(0.35), true, -1.0, false)


## C – knubbelig: großer Helm mit Streifen, runde Schulterstücke, kurzes dickes Gewehr.
func _soldier_chunky(enemy: bool) -> void:
	var cloth := Color("c24a3f") if enemy else Color("3f7fd6")
	var helmet := Color("8a2c24") if enemy else Color("27539c")
	var band := Color("f0c9b8") if enemy else Color("c9dcf7")
	var gun := Color("2a2e31")
	_ellipse_plain(Vector2(0, 3.0), Vector2(8.5, 5.0), cloth.darkened(0.25))
	draw_line(Vector2(6.0, -3), Vector2(6.0, -17), gun, 3.6, false)
	draw_line(Vector2(6.0, -17), Vector2(6.0, -19.5), Color("8a9297"), 2.0, false)
	draw_circle(Vector2(-9.0, 1.5), 4.0, cloth, true, -1.0, false)
	draw_circle(Vector2(9.0, 1.5), 4.0, cloth, true, -1.0, false)
	draw_circle(Vector2(0, 0), 7.6, helmet, true, -1.0, false)
	# Der Streifen quer über den Helm.
	draw_line(Vector2(-6.8, 1.6), Vector2(6.8, 1.6), band, 2.2, false)
	draw_circle(Vector2(0, 0), 7.6, Color(0, 0, 0, 0.4), false, 0.9, false)
	draw_circle(Vector2(-2.4, -3.2), 2.2, helmet.lightened(0.3), true, -1.0, false)


## D – Spielzeugsoldat: aus einem Guss in einer Farbe, auf seinem ovalen Sockel.
func _soldier_toy(enemy: bool) -> void:
	var plastic := Color("cfa14f") if enemy else Color("5fa348")
	var shade := plastic.darkened(0.3)
	var light := plastic.lightened(0.3)
	_ellipse_plain(Vector2(0.8, 3.6), Vector2(14.0, 11.0), Color(0, 0, 0, 0.35))
	_ellipse_plain(Vector2(0, 2.5), Vector2(13.0, 10.0), shade)
	_ellipse_plain(Vector2(0, 2.5), Vector2(11.6, 8.6), plastic.darkened(0.12))
	draw_line(Vector2(3.8, -2), Vector2(3.8, -20), shade, 2.4, false)
	_ellipse_plain(Vector2(0, 1.5), Vector2(9.0, 4.4), plastic)
	draw_line(Vector2(7.5, 0.5), Vector2(4.6, -7), plastic, 2.8, false)
	draw_line(Vector2(-7.5, 0.5), Vector2(3.0, -12), plastic, 2.8, false)
	draw_circle(Vector2(0, 0), 5.2, plastic, true, -1.0, false)
	draw_circle(Vector2(0, 0), 5.2, shade, false, 0.8, false)
	draw_circle(Vector2(-1.5, -1.6), 1.9, light, true, -1.0, false)


## E – Spielmarke: eine flache Scheibe mit Helm darauf, eine Kerbe zeigt die Richtung.
func _soldier_token(enemy: bool) -> void:
	var ring := Color("e0584b") if enemy else Color("4c8be0")
	var face := Color("1b2024")
	draw_circle(Vector2(0.8, 1.2), 12.5, Color(0, 0, 0, 0.4), true, -1.0, false)
	draw_circle(Vector2.ZERO, 12.0, ring, true, -1.0, false)
	draw_circle(Vector2.ZERO, 9.2, face, true, -1.0, false)
	# Wohin die Marke schaut.
	draw_colored_polygon(PackedVector2Array([Vector2(0, -17.5), Vector2(-4.5, -11.0), Vector2(4.5, -11.0)]), ring)
	# Ein Helm von der Seite, als Zeichen.
	var dome := PackedVector2Array()
	for i in 13:
		var a := PI + PI * i / 12.0
		dome.append(Vector2(cos(a) * 5.6, sin(a) * 5.2 + 1.5))
	draw_colored_polygon(dome, ring.lightened(0.45))
	draw_line(Vector2(-7.0, 2.2), Vector2(7.0, 2.2), ring.lightened(0.45), 1.6, false)


## F – nach der Vorlage: von oben der helle runde Helm, darum der dunklere
## Körper, hinten der Rucksack. Das Gewehr hält er an der rechten Seite: die
## rechte Hand am Griff, der linke Arm greift vor dem Körper nach vorn an den
## Schaft. Körper und Helm haben dieselbe Farbe, der Helm heller.
func _soldier_round(enemy: bool) -> void:
	var cloth := Color("a9402f") if enemy else Color("4a6aa6")
	var helmet := Color("ee8a68") if enemy else Color("a7c2ee")
	var ink := Color("15181b")
	var pack := Color("9a6a48")
	var left := PackedVector2Array([Vector2(-9.5, 2.5), Vector2(-10.8, -4.5), Vector2(-4.5, -10.5), Vector2(5.2, -13.5)])
	var right := PackedVector2Array([Vector2(9.5, 2.5), Vector2(12.0, -1.5), Vector2(8.2, -5.5)])

	# Rucksack mit Riemen, hinter dem Körper.
	_rounded(Rect2(-7.0, 5.5, 14.0, 9.0), 3.0, ink)
	_rounded(Rect2(-6.0, 6.3, 12.0, 7.4), 2.4, pack)
	draw_line(Vector2(-6.0, 10.0), Vector2(6.0, 10.0), pack.darkened(0.35), 1.0, false)

	# Körper: erst dunkel und etwas größer – das gibt die Kontur –, dann die Farbe.
	_ellipse_plain(Vector2(0, 2.0), Vector2(11.6, 8.6), ink)
	_ellipse_plain(Vector2(0, 2.0), Vector2(10.6, 7.6), cloth)
	_ellipse_plain(Vector2(-6.0, 0.5), Vector2(3.4, 4.2), cloth.lightened(0.16))

	_rifle(Vector2(7.0, 0.0))

	# Die Arme über dem Gewehr, Handschuhe an Griff und Schaft.
	_limb(left, 6.4, ink)
	_limb(right, 6.4, ink)
	_limb(left, 4.6, cloth)
	_limb(right, 4.6, cloth)
	draw_circle(Vector2(5.2, -13.5), 2.6, ink, true, -1.0, false)
	draw_circle(Vector2(8.2, -5.5), 2.6, ink, true, -1.0, false)

	draw_circle(Vector2(0, 0.5), 8.0, ink, true, -1.0, false)
	draw_circle(Vector2(0, 0.5), 7.1, helmet.darkened(0.14), true, -1.0, false)
	draw_circle(Vector2(-0.8, -0.4), 5.9, helmet, true, -1.0, false)
	draw_circle(Vector2(-2.2, -1.8), 2.6, helmet.lightened(0.45), true, -1.0, false)


## Ein Sturmgewehr von oben, die Mündung nach vorn: Kolben aus Holz, dunkles
## Gehäuse mit Magazin an der Seite, Handschutz, schmaler Lauf mit Mündung.
## Ein heller Saum hält es auch auf einer dunklen Karte sichtbar.
func _rifle(at: Vector2) -> void:
	var edge := Color("9aa3a8")
	var steel := Color("2c3338")
	var wood := Color("8a5a3c")
	# Der Saum: alles einmal etwas größer und hell.
	_rounded(Rect2(at.x - 2.6, at.y - 0.6, 5.2, 7.2), 1.2, edge)
	_rounded(Rect2(at.x - 2.9, at.y - 12.6, 5.8, 12.6), 1.0, edge)
	_rounded(Rect2(at.x + 1.4, at.y - 9.6, 4.8, 4.2), 0.8, edge)
	_rounded(Rect2(at.x - 1.8, at.y - 25.6, 3.6, 13.6), 0.8, edge)
	# Kolben, Gehäuse, Magazin, Handschutz, Lauf.
	_rounded(Rect2(at.x - 2.0, at.y, 4.0, 6.0), 1.0, wood)
	_rounded(Rect2(at.x - 2.3, at.y - 12.0, 4.6, 12.0), 0.8, steel)
	_rounded(Rect2(at.x + 2.0, at.y - 9.0, 3.6, 3.0), 0.6, steel)
	_rounded(Rect2(at.x - 2.3, at.y - 18.0, 4.6, 6.0), 0.8, wood.darkened(0.25))
	_rounded(Rect2(at.x - 1.2, at.y - 25.0, 2.4, 8.0), 0.5, steel)
	_rounded(Rect2(at.x - 1.7, at.y - 25.0, 3.4, 2.4), 0.5, steel.lightened(0.15))
	# Kimme und ein rotes Band, wie in der Vorlage.
	draw_line(Vector2(at.x - 2.3, at.y - 11.2), Vector2(at.x + 2.3, at.y - 11.2), Color("e0453a"), 1.3, false)


## Ein Arm: eine dicke Linie durch die Punkte, an den Gelenken rund.
func _limb(points: PackedVector2Array, width: float, color: Color) -> void:
	for i in points.size() - 1:
		draw_line(points[i], points[i + 1], color, width, false)
	for p in points:
		draw_circle(p, width / 2.0, color, true, -1.0, false)


## Wie viel ein Gegner noch aushält – ein Balken, der nicht mitdreht.
func _draw_health() -> void:
	draw_set_transform(Vector2.ZERO, -rotation, Vector2(girth, girth))
	var bar := Rect2(-9, 12, 18, 3)
	draw_rect(bar.grow(0.8), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * (1.0 - hurt), bar.size.y)), Color("6cc08c").lerp(Color("e57a66"), hurt))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(girth, girth))


## Der Gegner des Milestones: ein Panzer von oben.
func _draw_tank() -> void:
	var hull := Color("5a4a3a")
	var plate := Color("75604a")
	var track := Color("1c1a18")
	_ellipse_plain(Vector2(1.5, 3.0), Vector2(17.0, 22.0), Color(0, 0, 0, 0.22))
	# Die Ketten links und rechts, mit Gliedern.
	for side in [-1.0, 1.0]:
		_rounded(Rect2(side * 12.0 - 3.5, -19.0, 7.0, 38.0), 2.0, track)
		for i in 9:
			var y := -17.0 + i * 4.2
			draw_line(Vector2(side * 12.0 - 3.0, y), Vector2(side * 12.0 + 3.0, y), Color("3a3632"), 0.9, false)
	_rounded(Rect2(-10.5, -17.0, 21.0, 34.0), 3.0, hull)
	_rounded(Rect2(-8.0, -14.5, 16.0, 6.0), 1.5, plate)
	draw_line(Vector2(-8, 11), Vector2(8, 11), Color(0, 0, 0, 0.3), 0.9, false)
	draw_line(Vector2(-8, 14), Vector2(8, 14), Color(0, 0, 0, 0.3), 0.9, false)
	# Turm und Rohr.
	draw_line(Vector2(0, -2), Vector2(0, -30), Color("2b2622"), 3.4, false)
	draw_line(Vector2(0, -27), Vector2(0, -31), Color("15120f"), 4.6, false)
	draw_circle(Vector2(0, 1), 8.5, plate, true, -1.0, false)
	draw_circle(Vector2(0, 1), 8.5, Color(0, 0, 0, 0.35), false, 0.9, false)
	draw_circle(Vector2(2.5, 3), 2.6, hull, true, -1.0, false)
	draw_circle(Vector2(-3.5, -2), 1.1, Color("e6ae58"), true, -1.0, false)


# ----------------------------------------------------------- Pixelart

## Soldaten als Pixelbilder, von oben, Blick nach oben. Jede Zeile ist eine
## Pixelreihe, jeder Buchstabe eine Farbe aus `_pixel_colors`; ein Punkt ist leer.
const PIXELS := {
	# Klein und grob, 12 × 12.
	"p1": [
		"........g...",
		"........g...",
		"........g...",
		"...hhhh.g...",
		"..hHHhhhgs..",
		".chHhhhhhcc.",
		".cchhhhhhcc.",
		".ccdhhhhdcc.",
		"..ccddddcc..",
		"...bbbbbb...",
		"...bbbbbb...",
		"............",
	],
	# Mit Licht und Schatten, 16 × 16.
	"p2": [
		"..........G.....",
		"..........g.....",
		"..........g.....",
		"..........g.....",
		".....hhhh.g.....",
		"....hHHhhhgs....",
		"...hHHhhhhgs....",
		".cchHhhhhhhcccc.",
		".ccchhhhhhdcccc.",
		".kccdhhhhddcckk.",
		"..kkcddddddckk..",
		"....bbbbbbbb....",
		"....bBbbbbBb....",
		"....bbbbbbbb....",
		".....kk..kk.....",
		"................",
	],
	# Dasselbe mit dunkler Kontur, 16 × 16.
	"p3": [
		"..........oo....",
		".........ogo....",
		".........ogo....",
		"....oooo.ogo....",
		"...ohhhhoogo....",
		"..ohHHhhhogso...",
		".oohHhhhhhgsoo..",
		"occhhhhhhhhcccco",
		"occchhhhhhdcccco",
		"okccdhhhhddcckko",
		".okkcddddddckko.",
		"..oobbbbbbbboo..",
		"...obBbbbbBbo...",
		"...obbbbbbbbo...",
		"....oooooooo....",
		"................",
	],
	# Schwerer Schütze: großer Helm mit Streifen, das Gewehr mit beiden Händen vor sich, 16 × 16.
	"p4": [
		".......GG.......",
		".......gg.......",
		".......gg.......",
		"......sggs......",
		".....ccggcc.....",
		"....cchhhhcc....",
		"...cchHHhhhcc...",
		"..cchHHhhhhhcc..",
		"..cchhwwwwhhcc..",
		"..kchhhhhhhhck..",
		"..kkdhhhhhhdkk..",
		"...kkddddddkk...",
		"....bbbbbbbb....",
		"....bBbbbbBb....",
		".....bbbbbb.....",
		"................",
	],
}


func _pixel_colors(enemy: bool) -> Dictionary:
	if dead:
		return {"h": Color("8f9590"), "H": Color("a4aaa6"), "d": Color("767c78"), "c": Color("7b817d"), "k": Color("6b716d"),
			"b": Color("5f6562"), "B": Color("767c78"), "s": Color("a4aaa6"), "w": Color("b4bab6"), "o": Color("2a2e2c")}
	var colors := {"s": Color("f0c49a"), "g": Color("7b848a"), "G": Color("c9d1cd"), "o": Color("0d1012")}
	if enemy:
		colors.merge({"h": Color("9a3229"), "H": Color("d06a5c"), "d": Color("6e211b"), "c": Color("d2574b"), "k": Color("a53b31"),
			"b": Color("5c1f1a"), "B": Color("8a3028"), "w": Color("ffe1da")})
	else:
		colors.merge({"h": Color("2c5cab"), "H": Color("5b8fe0"), "d": Color("1f4480"), "c": Color("4c8be0"), "k": Color("2f62b0"),
			"b": Color("27406e"), "B": Color("3b5f9e"), "w": Color("dfeaff")})
	return colors


## Zeichnet ein Pixelbild um die Mitte: jedes Pixel ein kleines Quadrat, so
## bleibt es in jeder Größe kantig.
func _draw_pixels(rows: Array, colors: Dictionary) -> void:
	var count: int = rows.size()
	# So groß wie die gezeichneten Soldaten: gut 26 Einheiten hoch.
	var px := 26.0 / count
	var half := count * px / 2.0
	for y in count:
		var row: String = rows[y]
		for x in row.length():
			var color = colors.get(row[x])
			if color != null:
				# Ein Hauch größer, damit zwischen den Quadraten nichts durchblitzt.
				draw_rect(Rect2(x * px - half, y * px - half, px + 0.04, px + 0.04), color)


func _ellipse_plain(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 32:
		var a := TAU * i / 32.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)


func _rounded(rect: Rect2, radius: float, color: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(int(radius * 4.0))
	box.anti_aliasing_size = 0.3
	# Die Rundung ist in Bildpunkten gemeint, gezeichnet wird vergrößert: darum
	# hier vierfach fein und beim Zeichnen wieder verkleinert.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(girth, girth) / 4.0)
	draw_style_box(box, Rect2(rect.position * 4.0, rect.size * 4.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(girth, girth))


## Ein Schädling: giftgrün und mit dunklem Fleck darunter, damit er auf jeder
## Karte auffällt – auch auf einem Titelbild.
func _draw_pest() -> void:
	var body := Color("c6d94a")
	var head := Color("7f9324")
	var leg := Color("a9bb3a")
	if dead:
		body = Color("8f9590")
		head = Color("7b817d")
		leg = Color("8f9590")
	else:
		_ellipse_plain(Vector2(0, 1), Vector2(17.0, 19.0), Color(0, 0, 0, 0.42))
	# Wem zugesetzt wurde, dem fehlen Beine.
	var legs := 6 if dead else 6 - mini(int(hurt * 6.0), 5)
	for i in legs:
		var from: Vector2 = LEGS[i][0]
		var to: Vector2 = LEGS[i][1]
		if dead:
			# Auf dem Rücken sind die Beine angezogen.
			to = from + (to - from) * 0.6 + Vector2(0, -3)
		draw_line(from, to, leg, 1.6, false)
	draw_line(Vector2(-2, -12), Vector2(-6, -18), leg, 1.2, false)
	draw_line(Vector2(2, -12), Vector2(6, -18), leg, 1.2, false)
	_ellipse(Vector2(0, 2), Vector2(7.5, 10.0), body)
	draw_circle(Vector2(0, -9), 4.5, head, true, -1.0, false)
	if dead:
		for y in [-1.0, 3.0, 7.0]:
			draw_line(Vector2(-4, y), Vector2(4, y), Color("6b716d"), 0.8, false)
	else:
		draw_line(Vector2(0, -6), Vector2(0, 11), Color(0, 0, 0, 0.35), 0.9, false)
		draw_circle(Vector2(-2, -10), 1.0, Color("1b1d1c"), true, -1.0, false)
		draw_circle(Vector2(2, -10), 1.0, Color("1b1d1c"), true, -1.0, false)


func _draw_lady() -> void:
	var leg := Color("1b1d1c")
	for l in LEGS:
		draw_line(l[0], l[0] + (l[1] - l[0]) * 0.85, leg, 1.2, false)
	draw_line(Vector2(-2, -11), Vector2(-5, -16), leg, 1.0, false)
	draw_line(Vector2(2, -11), Vector2(5, -16), leg, 1.0, false)
	draw_circle(Vector2(0, -8), 4.5, Color("1b1d1c"), true, -1.0, false)
	draw_circle(Vector2(-2, -9.5), 1.0, Color.WHITE, true, -1.0, false)
	draw_circle(Vector2(2, -9.5), 1.0, Color.WHITE, true, -1.0, false)
	_ellipse(Vector2(0, 2), Vector2(8.5, 9.5), Color("e2463f"))
	draw_line(Vector2(0, -7), Vector2(0, 11), Color("1b1d1c"), 1.0, false)
	for spot in [Vector2(-4, -1), Vector2(4, -1), Vector2(-4.5, 5), Vector2(4.5, 5)]:
		draw_circle(spot, 1.6, Color("1b1d1c"), true, -1.0, false)


## Ein paar Steine: daran ändert kein Marienkäfer etwas.
func _draw_wall() -> void:
	var stone := Color("8c9590")
	var line := Color("3c4643")
	for row in 3:
		var shift := 5.0 if row % 2 == 1 else 0.0
		for col in 3:
			var r := Rect2(-15.0 + col * 10.0 + shift - 2.5, -9.0 + row * 6.0, 9.0, 5.0)
			draw_rect(r, stone)
			draw_rect(r, line, false, 0.8)


func _ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	draw_colored_polygon(points, color)
	points.append(points[0])
	draw_polyline(points, color.darkened(0.25), 0.8, false)
