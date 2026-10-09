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
