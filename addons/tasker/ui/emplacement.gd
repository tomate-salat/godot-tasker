@tool
extends RefCounted
## Die Geräte der Nebenquests, von oben gezeichnet wie Panzer und Flieger der
## Feldzugskarte – modern, nicht mittelalterlich (Nutzer, 2026-10-24). Jedes
## Gerät hat eine feste Reihe Bauteile (`Sidequest.PARTS`); gezeichnet wird,
## was davon steht. `built == parts` heißt: erledigt, das Gerät feuert.
##
## Alles wird um `at` gezeichnet, `s` ist der Maßstab (1 = auf der Karte),
## `turn` die Richtung, in die das Rohr zeigt.

const Sidequest := preload("../rules/sidequest.gd")

const SAND := Color("b8a37c")
const SAND_DARK := Color("7d6b4c")
const PEG := Color("d86a45")
const HULL := Color("4f6b3a")
const HULL_DARK := Color("34482a")
const STEEL := Color("2f3a28")
const NET := Color(0.36, 0.48, 0.29, 0.75)
const LINE := Color(1.0, 0.85, 0.55, 0.7)
const DARK := Color("15181b")
const OWN_LIGHT := Color("a7c2ee")
const FLASH := Color(1.0, 0.93, 0.69)
const GROUND := Color(0.10, 0.19, 0.16, 0.85)
const TARMAC := Color("33383a")
const ROCKET_RED := Color("e24b4a")

## So groß ist ein einzelnes Gerät auf der Karte (Halbmesser), und so groß
## Feuerstellung und Flugplatz.
const UNIT := 22.0
const BASE := 44.0


## Wie weit ein Gerät reicht – für Platz und Treffer.
static func reach(kind: String) -> float:
	return BASE if kind == Sidequest.BATTERY or kind == Sidequest.AIRFIELD else UNIT


## Zeichnet ein einzelnes Gerät: Mörser, Raketenwerfer oder Jet.
static func draw_unit(ci: CanvasItem, kind: String, at: Vector2, s: float, built: int, turn: float, time: float, alpha := 1.0) -> void:
	match kind:
		Sidequest.MORTAR:
			_mortar(ci, at, s, built, turn, time, alpha)
		Sidequest.ROCKET:
			_rocket(ci, at, s, built, turn, time, alpha)
		Sidequest.JET:
			_jet(ci, at, s, built, turn, alpha)


## Zeichnet eine Stellung samt den Geräten darin. `units` wie in
## `Sidequest.positions`; Geräte früherer Releases stehen blass. Ohne
## `with_units` nur Wall bzw. Bahn – im Zoom stehen die Geräte im Ring.
static func draw_position(ci: CanvasItem, p: Dictionary, at: Vector2, s: float, turn: float, time: float, alpha := 1.0, with_units := true) -> void:
	var kind: String = p["kind"]
	if kind == Sidequest.MORTAR or kind == Sidequest.ROCKET:
		ci.draw_circle(at, (UNIT + 6.0) * s, Color(GROUND, GROUND.a * alpha))
		draw_unit(ci, kind, at, s, p["built"], turn, time, alpha)
		return
	var spots := unit_spots(p, s)
	if kind == Sidequest.BATTERY:
		ci.draw_circle(at, (BASE + 6.0) * s, Color(GROUND, GROUND.a * alpha))
		_wall(ci, at, (BASE - 2.0) * s, p["built"], p["parts"], 7.0 * s, alpha)
		if not with_units:
			return
		for i in p["units"].size():
			var u: Dictionary = p["units"][i]
			draw_unit(ci, u["kind"], at + spots[i], s * 0.5, u["built"], turn, time + i * 0.7, alpha * (0.45 if u["earlier"] != null else 1.0))
	else:
		_airfield(ci, at, s, p["built"], p["parts"], turn, alpha)
		if not with_units:
			return
		for i in p["units"].size():
			var u: Dictionary = p["units"][i]
			# Ein erledigter Jet ist gestartet: er fliegt über der Stellung (das zeichnet die Karte).
			if u["done"] and u["earlier"] == null:
				continue
			draw_unit(ci, Sidequest.JET, at + spots[i].rotated(turn), s * 0.55, u["built"], turn - PI / 2.0, time, alpha * (0.45 if u["earlier"] != null else 1.0))


## Wo die Geräte in Feuerstellung und Flugplatz stehen, relativ zur Mitte.
static func unit_spots(p: Dictionary, s: float) -> Array:
	var n: int = p["units"].size()
	var out := []
	if p["kind"] == Sidequest.AIRFIELD:
		# In einer Reihe neben der Bahn.
		for i in n:
			var x := (i - (n - 1) / 2.0) * 15.0 * s + 12.0 * s
			out.append(Vector2(x, -16.0 * s))
		return out
	if n == 1:
		return [Vector2.ZERO]
	var r := (17.0 if n <= 3 else 24.0) * s
	for i in n:
		var a := -PI / 2.0 + TAU * i / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


# ------------------------------------------------------------- Bauteile

## Pflöcke und gestrichelter Umriss: hier wird gebaut.
static func _pegs(ci: CanvasItem, at: Vector2, half: float, s: float, alpha: float) -> void:
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		ci.draw_rect(Rect2(at + c * half - Vector2(1.5, 3.5) * s, Vector2(3.0, 7.0) * s), Color(PEG, alpha))
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for i in 4:
		ci.draw_dashed_line(at + corners[i] * half * 0.86, at + corners[(i + 1) % 4] * half * 0.86, Color(LINE, LINE.a * alpha), maxf(1.0 * s, 1.0), 4.0 * s)


## Ein Sandsackwall als Ring: `share` 0 bis 1, von oben im Uhrzeigersinn.
static func _sandbags(ci: CanvasItem, at: Vector2, r: float, share: float, width: float, alpha: float) -> void:
	if share <= 0.0:
		return
	var count := maxi(8, int(TAU * r / (width * 1.3)))
	var shown := int(round(count * share))
	for k in shown:
		var a0 := -PI / 2.0 + TAU * k / count
		var a1 := a0 + TAU / count * 0.82
		ci.draw_arc(at, r, a0, a1, 4, Color(SAND_DARK, alpha), width + 1.6, true)
		ci.draw_arc(at, r, a0 + 0.02, a1 - 0.02, 4, Color(SAND, alpha), width, true)


## Der Wall der Feuerstellung: Pflöcke, dann Stück für Stück der Ring.
static func _wall(ci: CanvasItem, at: Vector2, r: float, built: int, parts: int, width: float, alpha: float) -> void:
	if built >= 1:
		for k in 8:
			var a := TAU * k / 8.0
			ci.draw_rect(Rect2(at + Vector2(cos(a), sin(a)) * r - Vector2(1.5, 3.5), Vector2(3, 7)), Color(PEG, alpha))
	if built >= 2:
		_sandbags(ci, at, r, float(built - 1) / float(parts - 1), width, alpha)


static func _mortar(ci: CanvasItem, at: Vector2, s: float, built: int, turn: float, time: float, alpha: float) -> void:
	var r := UNIT * 0.72 * s
	if built <= 2:
		_pegs(ci, at, UNIT * 0.62 * s, s, alpha)
	if built >= 2:
		_sandbags(ci, at, r, 0.5 if built == 2 else 1.0, 5.0 * s, alpha)
	if built >= 4:
		ci.draw_circle(at, 6.0 * s, Color(HULL_DARK, alpha))
		var tip := at + Vector2.from_angle(turn) * 11.0 * s
		var kick := 0.0
		if built >= 5:
			var shot := fposmod(time, 2.4)
			kick = 2.0 * s * maxf(0.0, 1.0 - shot / 0.25)
			if shot < 0.08:
				ci.draw_circle(tip, 4.0 * s, Color(FLASH, alpha))
		ci.draw_line(at, tip - Vector2.from_angle(turn) * kick, Color(STEEL, alpha), 4.0 * s, true)
		ci.draw_circle(at, 3.0 * s, Color(HULL, alpha))
	if built >= 5:
		_net(ci, at, r * 0.9, s, alpha)


static func _rocket(ci: CanvasItem, at: Vector2, s: float, built: int, turn: float, time: float, alpha: float) -> void:
	var r := UNIT * 0.86 * s
	if built <= 4:
		_pegs(ci, at, UNIT * 0.66 * s, s, alpha)
	if built >= 2:
		_sandbags(ci, at, r, minf(float(built - 1) / 3.0, 1.0) * 0.8, 5.0 * s, alpha)
	var body := Transform2D(turn + PI / 2.0, at)
	if built >= 5:
		# Fahrgestell: Räder und Wanne.
		for y in [-8.0, 0.0, 8.0]:
			for x in [-6.5, 6.5]:
				ci.draw_colored_polygon(_quad(body, Vector2(x, y) * s, Vector2(3.0, 5.0) * s), Color(DARK, alpha))
		ci.draw_colored_polygon(_quad(body, Vector2(0, 0), Vector2(11.0, 26.0) * s), Color(HULL, alpha))
	if built >= 6:
		ci.draw_colored_polygon(_quad(body, Vector2(0, -9.5) * s, Vector2(10.0, 7.0) * s), Color(HULL_DARK, alpha))
	if built >= 7:
		var launcher := Transform2D(turn + PI / 2.0 + (0.0 if built < 8 else -0.5), at + Vector2.from_angle(turn + PI) * 3.0 * s)
		ci.draw_colored_polygon(_quad(launcher, Vector2(0, 4.0) * s, Vector2(9.0, 13.0) * s), Color(STEEL, alpha))
		for x in [-2.5, 0.0, 2.5]:
			ci.draw_circle(launcher * (Vector2(x, -1.0) * s), 1.0 * s, Color(ROCKET_RED, alpha))
		if built >= 8 and fposmod(time, 3.0) < 0.12:
			ci.draw_circle(launcher * (Vector2(0, -6.0) * s), 4.5 * s, Color(FLASH, alpha))
	if built >= 8:
		_net(ci, at, r * 0.75, s, alpha)


static func _jet(ci: CanvasItem, at: Vector2, s: float, built: int, turn: float, alpha: float) -> void:
	var body := Transform2D(turn, at)
	var shape := [Vector2(13, 0), Vector2(3, -2.2), Vector2(-1, -13), Vector2(-5, -13), Vector2(-3, -2), Vector2(-10, -1.6),
		Vector2(-12, -5.5), Vector2(-14.5, -5.5), Vector2(-13.5, 0), Vector2(-14.5, 5.5), Vector2(-12, 5.5), Vector2(-10, 1.6), Vector2(-3, 2),
		Vector2(-5, 13), Vector2(-1, 13), Vector2(3, 2.2)]
	var outline := PackedVector2Array()
	for v in shape:
		outline.append(body * (v * s))
	outline.append(outline[0])
	if built <= 1:
		ci.draw_polyline(outline, Color(LINE, LINE.a * alpha), maxf(1.0 * s, 1.0), true)
		return
	# Rumpf, Flügel, Leitwerk: in Dreiecken um die Mitte, wie der Flieger der Karte.
	var parts := [[0, 1, 15], [1, 2, 3, 4], [14, 15, 12, 13], [5, 6, 7, 8, 9, 10, 11]]
	var color := OWN_LIGHT if built >= 5 else Color("8a9690")
	for p in mini(built - 1, parts.size()):
		var idx: Array = parts[p]
		for i in idx.size():
			ci.draw_colored_polygon(PackedVector2Array([body * (Vector2(-3, 0) * s), body * (shape[idx[i]] * s), body * (shape[idx[(i + 1) % idx.size()]] * s)]), Color(color, alpha))
	if built >= 2:
		ci.draw_colored_polygon(PackedVector2Array([body * (Vector2(13, 0) * s), body * (Vector2(-10, -2) * s), body * (Vector2(-10, 2) * s)]), Color(color, alpha))
	ci.draw_polyline(outline, Color(DARK, alpha), 0.9, true)
	if built >= 6:
		for y in [-8.0, 8.0]:
			ci.draw_line(body * (Vector2(-4, y) * s), body * (Vector2(2, y) * s), Color(ROCKET_RED, alpha), 1.4 * s, true)


static func _airfield(ci: CanvasItem, at: Vector2, s: float, built: int, parts: int, turn: float, alpha: float) -> void:
	var t := Transform2D(turn, at)
	ci.draw_colored_polygon(_quad(t, Vector2(0, 2) * s, Vector2(BASE * 2.3, 46.0) * s), Color(GROUND, GROUND.a * alpha))
	if built <= 1:
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for i in 4:
			ci.draw_dashed_line(t * (corners[i] * Vector2(BASE, 6.0) * s + Vector2(0, 12) * s), t * (corners[(i + 1) % 4] * Vector2(BASE, 6.0) * s + Vector2(0, 12) * s), Color(LINE, LINE.a * alpha), 1.0, 4.0)
		for x in [-BASE, BASE]:
			ci.draw_rect(Rect2(t * (Vector2(x, 12) * s) - Vector2(1.5, 3.5), Vector2(3, 7)), Color(PEG, alpha))
		return
	# Die Bahn.
	ci.draw_colored_polygon(_quad(t, Vector2(0, 12) * s, Vector2(BASE * 2.1, 12.0) * s), Color(TARMAC, alpha))
	if built >= 3:
		# Die Halle am Rand.
		ci.draw_colored_polygon(_quad(t, Vector2(-BASE * 0.72, -14) * s, Vector2(20.0, 14.0) * s), Color("5f5e5a", alpha))
		ci.draw_line(t * (Vector2(-BASE * 0.72 - 10, -14) * s), t * (Vector2(-BASE * 0.72 + 10, -14) * s), Color("888780", alpha), 1.2, true)
	if built >= parts:
		var x := -BASE * 0.9
		while x < BASE * 0.9:
			ci.draw_line(t * (Vector2(x, 12) * s), t * (Vector2(x + 6.0, 12) * s), Color(1, 1, 1, 0.7 * alpha), 1.0, true)
			x += 12.0


## Ein Tarnnetz: ein paar Maschen über dem Gerät.
static func _net(ci: CanvasItem, at: Vector2, r: float, s: float, alpha: float) -> void:
	for k in 4:
		var a := k * PI / 4.0
		ci.draw_line(at - Vector2.from_angle(a) * r, at + Vector2.from_angle(a) * r, Color(NET, NET.a * alpha), 1.0 * s, true)


static func _quad(t: Transform2D, mid: Vector2, extent: Vector2) -> PackedVector2Array:
	var h := extent / 2.0
	return PackedVector2Array([t * (mid + Vector2(-h.x, -h.y)), t * (mid + Vector2(h.x, -h.y)), t * (mid + Vector2(h.x, h.y)), t * (mid + Vector2(-h.x, h.y))])
