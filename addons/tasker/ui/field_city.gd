@tool
extends Node2D
## Die Stadt hinter dem Feld: Viertel, Straßen, Häuserblöcke, Parks und ein
## Fluss, wie auf einem Stadtplan. Sie gehört erst dem Gegner (rot) und färbt
## sich von außen nach innen grün, so weit das Feld eingenommen ist.
##
## Die Stadt ist ausgedacht: aus der Kennung des Milestones entsteht immer
## dieselbe. Sie richtet sich nicht nach den Ringen – eine ordentliche Stadt
## sähe nach Schablone aus, erst recht bei wenigen Ringen. Nur die Einfärbung
## folgt ihnen.
##
## Gebaut wird sie so: ein paar große Straßen schneiden die Fläche in Viertel.
## Jedes Viertel hat sein eigenes, gedrehtes Straßenraster, das immer weiter
## geteilt wird, bis ungleich große Blöcke übrig sind. Darin stehen die
## Gebäude – alles im rechten Winkel, nichts verzogen.

## So weit reicht die Stadt von der Mitte.
const EXTENT := Vector2(2000, 1500)
## Wie viele große Straßen die Stadt durchschneiden, und wie breit die
## Straßen sind: große, gewöhnliche und Gassen.
const AVENUES := 6
const AVENUE := 26.0
const STREET_WIDE := 11.0
const ALLEY := 6.0
## Der Fluss ist so breit, und so weit von seiner Mitte bleibt das Ufer frei.
const RIVER := 86.0
const BANK := 58.0
## Um die Mitte bleibt ein Platz frei.
const PLAZA := 132.0

## Die Straßen heben sich hell vom Grund der Blöcke ab – daran erkennt man die Stadt.
const STREET := Color("2a3837")
const LANE := Color(1, 1, 1, 0.13)
const WATER := Color("172f3c")
## Grund und Dächer: beim Gegner und eingenommen.
const FOE_GROUND := Color("2b2321")
const FOE_ROOFS := [Color("3b2c29"), Color("42302c"), Color("362826"), Color("48342f")]
const OWN_GROUND := Color("1b3129")
const OWN_ROOFS := [Color("254539"), Color("294b3f"), Color("224035"), Color("2e5144")]
const FOE_PARK := Color("2f2a1f")
const OWN_PARK := Color("224836")

## Wie viel zu sehen ist: 0 nur die Blöcke, 1 mit Gebäuden, 2 dazu Schatten und Bäume.
static var detail := 1

## Bis zu welchem Ring die Stadt eingenommen ist, von außen gezählt: alles,
## was weiter außen liegt als dieser Wert, ist grün. Gezählt wird wie die
## Ringe, der innerste ist 0; Zwischenwerte liegen zwischen zwei Ringen.
var front := 99.0:
	set(value):
		if not is_equal_approx(front, value):
			front = value
			queue_redraw()

var _seed := -1
var _ring := Vector2.ONE
var _step := Vector2.ONE
## Die Blöcke: `{ poly, mid, at, kind, roofs }`, `at` ist ihre Lage in Ringen
## gemessen, `roofs` sind `{ poly, mid, tone, at }`.
var _blocks := []
var _river := PackedVector2Array()
## Die großen Straßen, je zwei Endpunkte – für den Mittelstreifen.
var _avenues := []


## Baut die Stadt zu diesem Milestone. `ring` und `step` sind der innerste
## Ring und der Abstand der Ringe, wie das Feld sie gerade zeichnet.
func build(seed_value: int, ring: Vector2, step: Vector2) -> void:
	if seed_value == _seed and ring.is_equal_approx(_ring) and step.is_equal_approx(_step):
		return
	var same_town := seed_value == _seed
	_seed = seed_value
	_ring = ring
	_step = step
	if not same_town:
		_generate()
	# Wo ein Block liegt, hängt an den Ringen – das ist schnell neu gerechnet.
	for b in _blocks:
		b["at"] = _ring_at(b["mid"])
		for roof in b["roofs"]:
			roof["at"] = _ring_at(roof["mid"])
	queue_redraw()


## Wie weit außen ein Punkt liegt, in Ringen gemessen: 0 auf dem innersten
## Ring, 1 auf dem nächsten, dazwischen Bruchteile, innerhalb des innersten
## negativ.
func _ring_at(p: Vector2) -> float:
	var low := -1.2
	var high := 40.0
	for i in 14:
		var mid := (low + high) / 2.0
		var reach := _ring + _step * mid
		if reach.x <= 1.0 or reach.y <= 1.0 or pow(p.x / reach.x, 2.0) + pow(p.y / reach.y, 2.0) > 1.0:
			low = mid
		else:
			high = mid
	return (low + high) / 2.0


func _generate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _seed
	_blocks = []
	_avenues = []

	# Ein Fluss quer durch die Stadt, an der Mitte vorbei.
	_river = PackedVector2Array()
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var offset := side * rng.randf_range(430.0, 640.0)
	var slope := rng.randf_range(-0.22, 0.22)
	var wave := rng.randf() * TAU
	var x := -EXTENT.x - 100.0
	while x <= EXTENT.x + 100.0:
		_river.append(Vector2(x, offset + slope * x + sin(x * 0.0023 + wave) * 190.0))
		x += 40.0

	# Große Straßen schneiden die Fläche in Viertel – in jeder Richtung, aber nie durch die Mitte.
	var districts: Array = [PackedVector2Array([-EXTENT, Vector2(EXTENT.x, -EXTENT.y), EXTENT, Vector2(-EXTENT.x, EXTENT.y)])]
	var far := 6000.0
	for k in AVENUES:
		var dir := Vector2.from_angle(rng.randf() * PI)
		var normal := Vector2(-dir.y, dir.x)
		var through := normal * rng.randf_range(210.0, 980.0) * (-1.0 if rng.randf() < 0.5 else 1.0)
		_avenues.append([through - dir * far, through + dir * far])
		var next := []
		for way in [1.0, -1.0]:
			var half := PackedVector2Array([through - dir * far, through + dir * far, through + dir * far + normal * far * way, through - dir * far + normal * far * way])
			for district in districts:
				for piece in Geometry2D.intersect_polygons(district, half):
					if not Geometry2D.is_polygon_clockwise(piece):
						next.append(piece)
		districts = next

	for district in districts:
		for inner in Geometry2D.offset_polygon(district, -AVENUE / 2.0):
			if Geometry2D.is_polygon_clockwise(inner) or _area(inner) < 3000.0:
				continue
			# Jedes Viertel hat sein eigenes Raster, anders gedreht als die Nachbarn.
			var turn := rng.randf_range(-PI / 4.0, PI / 4.0)
			var low := Vector2(INF, INF)
			var high := Vector2(-INF, -INF)
			for p in inner:
				var q: Vector2 = p.rotated(-turn)
				low = low.min(q)
				high = high.max(q)
			_split(Rect2(low, high - low), turn, inner, rng)


## Teilt ein Stück Viertel durch eine Straße, immer wieder, bis Blöcke übrig
## sind. Wo und wie fein geteilt wird, ist jedes Mal anders – so werden die
## Blöcke ungleich groß.
func _split(rect: Rect2, turn: float, district: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var limit := rng.randf_range(92.0, 210.0)
	var wide := rect.size.x >= rect.size.y
	var length := rect.size.x if wide else rect.size.y
	if length <= limit or length < 100.0:
		_add_block(rect, turn, district, rng)
		return
	var gap := ALLEY if rng.randf() < 0.3 else STREET_WIDE
	var cut := length * rng.randf_range(0.34, 0.66)
	if wide:
		_split(Rect2(rect.position, Vector2(cut - gap / 2.0, rect.size.y)), turn, district, rng)
		_split(Rect2(rect.position + Vector2(cut + gap / 2.0, 0), Vector2(rect.size.x - cut - gap / 2.0, rect.size.y)), turn, district, rng)
	else:
		_split(Rect2(rect.position, Vector2(rect.size.x, cut - gap / 2.0)), turn, district, rng)
		_split(Rect2(rect.position + Vector2(0, cut + gap / 2.0), Vector2(rect.size.x, rect.size.y - cut - gap / 2.0)), turn, district, rng)


func _add_block(rect: Rect2, turn: float, district: PackedVector2Array, rng: RandomNumberGenerator) -> void:
	var corners := PackedVector2Array()
	for c in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		corners.append(c.rotated(turn))
	# Die Gebäude werden für den ganzen Block ausgewürfelt, auch wenn am Rand
	# des Viertels nur ein Teil von ihm übrig bleibt.
	var park := rng.randf() < 0.07
	var shapes := _footprints(rng)
	var tones := []
	for shape in shapes:
		tones.append(rng.randi() % 4)
	for piece in Geometry2D.intersect_polygons(corners, district):
		if Geometry2D.is_polygon_clockwise(piece) or _area(piece) < 1500.0:
			continue
		var mid := Vector2.ZERO
		var wet := false
		for p in piece:
			mid += p
			if _river_distance(p) < BANK:
				wet = true
		mid /= piece.size()
		# Um die Zitadelle bleibt ein Platz frei, und am Fluss das Ufer.
		if wet or mid.length() < PLAZA or _river_distance(mid) < BANK:
			continue
		var roofs := []
		if not park:
			for i in shapes.size():
				var poly := PackedVector2Array()
				var middle := Vector2.ZERO
				var inside := true
				for p in shapes[i]:
					var q: Vector2 = (rect.position + Vector2(p.x * rect.size.x, p.y * rect.size.y)).rotated(turn)
					poly.append(q)
					middle += q
					if not Geometry2D.is_point_in_polygon(q, piece):
						inside = false
				# Ein Gebäude, das über den Block hinausragte, wird nicht gebaut.
				if inside:
					roofs.append({"poly": poly, "mid": middle / poly.size(), "tone": tones[i], "at": 0.0})
		_blocks.append({"poly": piece, "mid": mid, "kind": "park" if park else "town", "roofs": roofs, "at": 0.0})


static func _area(poly: PackedVector2Array) -> float:
	var sum := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		sum += a.x * b.y - b.x * a.y
	return absf(sum) / 2.0


## Wie nah ein Punkt dem Fluss kommt: der Abstand zu seiner Mittellinie.
func _river_distance(p: Vector2) -> float:
	var best := INF
	for i in _river.size() - 1:
		# Nur die Stücke in der Nähe lohnen das Rechnen.
		if absf(_river[i].x - p.x) > 260.0:
			continue
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, _river[i], _river[i + 1]).distance_to(p))
	return best


## Die Grundrisse der Gebäude eines Blocks, wie auf einem Stadtplan: nicht
## lauter gleiche Rechtecke, sondern Häuserzeilen, Winkel- und Hofbauten, ein
## großer Bau mit Nebengebäuden oder Verstreutes. Gerechnet wird im Block von
## 0 bis 1 in beide Richtungen; jeder Grundriss ist eine Folge von Ecken.
func _footprints(rng: RandomNumberGenerator) -> Array:
	var out := []
	var edge := 0.08
	var far := 1.0 - edge
	match rng.randi() % 6:
		0, 1:
			# Zwei Häuserzeilen an gegenüberliegenden Straßen, dazwischen Höfe.
			for side in 2:
				if rng.randf() < 0.15:
					continue
				var count := 3 + rng.randi() % 4
				var each := (far - edge) / count
				for i in count:
					var deep := rng.randf_range(0.24, 0.4)
					var wide := each * rng.randf_range(0.82, 1.0) - 0.015
					var top := edge if side == 0 else far - deep
					out.append(_rect(edge + i * each, top, wide, deep))
		2:
			# Ein Winkelbau, im freien Eck manchmal ein Nebengebäude.
			var thick := rng.randf_range(0.3, 0.44)
			out.append([Vector2(edge, edge), Vector2(far, edge), Vector2(far, edge + thick), Vector2(edge + thick, edge + thick),
				Vector2(edge + thick, far), Vector2(edge, far)])
			if rng.randf() < 0.6:
				var from := edge + thick + 0.1
				out.append(_rect(from, from, (far - from) * rng.randf_range(0.6, 1.0), (far - from) * rng.randf_range(0.6, 1.0)))
		3:
			# Ein Hofbau: drei Flügel um einen offenen Hof.
			var wing := rng.randf_range(0.2, 0.28)
			out.append([Vector2(edge, edge), Vector2(far, edge), Vector2(far, far), Vector2(far - wing, far),
				Vector2(far - wing, edge + wing), Vector2(edge + wing, edge + wing), Vector2(edge + wing, far), Vector2(edge, far)])
		4:
			# Ein großer Bau, daneben zwei oder drei kleine.
			var big := rng.randf_range(0.48, 0.62)
			out.append(_rect(edge, edge, big, far - edge))
			var count := 2 + rng.randi() % 2
			var from := edge + big + 0.07
			var each := (far - edge) / count
			for i in count:
				if rng.randf() < 0.2:
					continue
				out.append(_rect(from, edge + i * each, (far - from) * rng.randf_range(0.7, 1.0), each - 0.06))
		_:
			# Verstreut: ein paar Bauten verschiedener Größe, mit Lücken.
			var columns := 2 + rng.randi() % 2
			var rows := 2 + rng.randi() % 2
			for v in rows:
				for u in columns:
					if rng.randf() < 0.22:
						continue
					var cell := Vector2((far - edge) / columns, (far - edge) / rows)
					var size := Vector2(cell.x * rng.randf_range(0.55, 0.9), cell.y * rng.randf_range(0.55, 0.9))
					var at := Vector2(edge + u * cell.x, edge + v * cell.y) + (cell - size) * Vector2(rng.randf(), rng.randf())
					out.append(_rect(at.x, at.y, size.x, size.y))
	# Jeder Block liegt anders herum.
	var flip_u := rng.randf() < 0.5
	var flip_v := rng.randf() < 0.5
	var swap := rng.randf() < 0.5
	for shape in out:
		for i in shape.size():
			var p: Vector2 = shape[i]
			if flip_u:
				p.x = 1.0 - p.x
			if flip_v:
				p.y = 1.0 - p.y
			shape[i] = Vector2(p.y, p.x) if swap else p
	return out


static func _rect(x: float, y: float, w: float, h: float) -> Array:
	return [Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]


## Wie sehr ein Punkt in dieser Lage eingenommen ist, 0 bis 1 – mit einem
## weichen Übergang an der Front.
func _taken(at: float) -> float:
	return smoothstep(front - 0.12, front + 0.12, at)


func _draw() -> void:
	draw_rect(Rect2(-EXTENT, EXTENT * 2.0), STREET)
	# Der Mittelstreifen der großen Straßen.
	for avenue in _avenues:
		draw_dashed_line(avenue[0], avenue[1], LANE, 1.6, 16.0, true, false)
	if _river.size() >= 2:
		draw_polyline(_river, WATER, RIVER, false)
	for b in _blocks:
		var t := _taken(b["at"])
		if b["kind"] == "park":
			var grass: Color = FOE_PARK.lerp(OWN_PARK, t)
			draw_colored_polygon(b["poly"], grass)
			if detail >= 2:
				for k in 4:
					var tree: Vector2 = b["mid"] + Vector2(-14.0 + 28.0 * (k % 2), -14.0 + 28.0 * (k / 2))
					draw_circle(tree, 7.0, grass.lightened(0.12), true, -1.0, false)
			continue
		draw_colored_polygon(b["poly"], FOE_GROUND.lerp(OWN_GROUND, t))
		if detail < 1:
			continue
		for roof in b["roofs"]:
			var own := _taken(roof["at"])
			var poly: PackedVector2Array = roof["poly"]
			if detail >= 2:
				var shade := PackedVector2Array()
				for p in poly:
					shade.append(p + Vector2(3.0, 3.5))
				draw_colored_polygon(shade, Color(0, 0, 0, 0.35))
			draw_colored_polygon(poly, FOE_ROOFS[roof["tone"]].lerp(OWN_ROOFS[roof["tone"]], own))
