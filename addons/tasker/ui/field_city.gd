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
## Zum Rand hin läuft sie aus: ab diesem Anteil des Weges werden die Blöcke
## lichter und blasser, am Rand ist nur noch Umland. So viele der äußersten
## Blöcke fehlen ganz.
const FADE_FROM := 0.58
const THIN := 0.7
## Fluss und große Straßen laufen als Landstraßen weit ins Umland hinaus.
const COUNTRY := 12000.0
## Für die Wege zwischen den Karten liegt die Stadt in einem Raster aus so
## großen Feldern: frei, wo Straße ist, belegt, wo ein Block steht. Die Blöcke
## zählen dabei um einen Bordstein schmaler, damit auch Gassen durchgängig sind.
const CELL := 5.0
const CURB := 2.5
## Wege nehmen lieber breite Straßen: so viel mal so weit zählt ein Stück auf
## einer gewöhnlichen Straße und in einer Gasse oder am offenen Ufer gegenüber
## einer großen Straße.
const COST_STREET := 1.6
const COST_ALLEY := 3.2
## Unter einer Karte ist der Weg frei, aber teuer: so verlässt ein Weg seine
## eigene Karte dort, wo es ihm passt, und macht um fremde einen Bogen.
const COST_CARD := 9.0
## Wo schon ein Weg läuft, wird die Straße in dieser Breite (in Feldern nach
## jeder Seite) für die folgenden um diesen Faktor teurer – so verteilen sie
## sich auf andere Straßen und Brücken, statt übereinander zu liegen.
const SHARE_COST := 2.4
const SHARE_REACH := 2
## Gefundene Wege werden geglättet: Zacken bis zu dieser Größe verschwinden,
## und Ecken werden so weit abgerundet.
const SMOOTH := 6.0
## Brücken: so weit ragen sie an jedem Ufer über das Wasser hinaus, und
## höchstens so weit liegen zwei auseinander – wo keine große Straße den Fluss
## kreuzt, kommt eine schmalere dazu.
const BRIDGE_LAND := 16.0
## Wo der Fluss vom Bogen zwischen den Ringen nach außen abbiegt, ist die Kurve so weit.
const BEND := 90.0
const BRIDGE_EVERY := 380.0
const BRIDGE_NARROW := 20.0
const BRIDGE_DECK := Color("34443f")
const BRIDGE_RAIL := Color(1, 1, 1, 0.22)
const CORNER := 12.0
const COUNTRY_ROAD := Color(0.165, 0.22, 0.215, 0.55)
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
## Der Fluss liegt in der Lücke hinter diesem Ring (der innerste ist der
## erste), und um so viel ist diese Lücke weiter als die anderen.
var _moat_after := 1
var _moat := Vector2.ZERO
## So viele Ringe hat das Feld gerade.
var _rings := 1
## Die Blöcke: `{ poly, mid, at, kind, roofs }`, `at` ist ihre Lage in Ringen
## gemessen, `roofs` sind `{ poly, mid, tone, at }`.
var _blocks := []
var _river := PackedVector2Array()
## Die großen Straßen, je zwei Endpunkte – für den Mittelstreifen.
var _avenues := []
## Die gewöhnlichen Straßen, je zwei Endpunkte – Gassen stehen nicht darin.
var _streets := []
## Die Brücken: `{ from, to, width }`.
var _bridges := []
## Das Raster der Straßen, siehe `CELL`.
var _grid: AStarGrid2D
## Was unter den Karten lag, bevor sie das Raster überdeckten: je Feld `[belegt, Kosten]`.
var _covered := {}
## Was die Straßen kosteten, bevor Wege sie teurer machten: je Feld die Kosten.
var _used := {}


## Baut die Stadt zu diesem Milestone. `ring` und `step` sind der innerste
## Ring und der Abstand der Ringe, wie das Feld sie gerade zeichnet.
func build(seed_value: int, ring: Vector2, step: Vector2, moat := Vector2.ZERO, rings := 1, moat_after := 1) -> void:
	if moat_after == _moat_after and rings == _rings and seed_value == _seed and ring.is_equal_approx(_ring) and step.is_equal_approx(_step) and moat.is_equal_approx(_moat):
		return
	_seed = seed_value
	_ring = ring
	_step = step
	_moat = moat
	_moat_after = moat_after
	_rings = rings
	# Der Fluss liegt zwischen den Ringen – ändern die sich, wird neu gebaut.
	# Aus derselben Kennung entstehen dabei dieselben Straßen.
	_generate()
	for b in _blocks:
		b["at"] = _ring_at(b["mid"])
		for roof in b["roofs"]:
			roof["at"] = _ring_at(roof["mid"])
	queue_redraw()


## Wie weit ein Punkt zum Rand der Stadt hin liegt: 0 in der Mitte, 1 am Rand.
## Der Rand ist ein Rechteck mit weit gerundeten Ecken.
static func edge_at(p: Vector2) -> float:
	return pow(pow(p.x / EXTENT.x, 4.0) + pow(p.y / EXTENT.y, 4.0), 0.25)


## Wie deckend die Stadt an dieser Stelle noch ist.
static func _solid(p: Vector2) -> float:
	return 1.0 - smoothstep(FADE_FROM, 1.0, edge_at(p))


## Wie weit außen ein Punkt liegt, in Ringen gemessen: 0 auf dem innersten
## Ring, 1 auf dem nächsten, dazwischen Bruchteile, innerhalb des innersten
## negativ.
func _ring_at(p: Vector2) -> float:
	var low := -1.2
	var high := 40.0
	for i in 14:
		var mid := (low + high) / 2.0
		var reach := _ring + _step * mid + _moat * clampf(mid - (_moat_after - 1.0), 0.0, 1.0)
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
	_streets = []
	_bridges = []

	# Ein Fluss, der in weitem Bogen um die Mitte läuft.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var lean := rng.randf_range(-0.45, 0.45)
	var span := rng.randf_range(0.8, 1.15)
	var sway := rng.randf() * TAU
	_lay_river(side * PI / 2.0 + lean, span, sway)

	# Große Straßen schneiden die Fläche in Viertel – in jeder Richtung, aber nie durch die Mitte.
	var districts: Array = [PackedVector2Array([-EXTENT, Vector2(EXTENT.x, -EXTENT.y), EXTENT, Vector2(-EXTENT.x, EXTENT.y)])]
	var far := COUNTRY
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
	_pave()


## Legt den Fluss: einen Bogen in der Lücke hinter dem Ring `_moat_after`, um `middle` herum und nach jeder Seite `span` weit (beides
## Winkel). An seinen Enden biegt er ab und läuft gerade nach außen – so
## kreuzt er die äußeren Ringe quer und nimmt ihnen kaum Platz.
func _lay_river(middle: float, span: float, sway: float) -> void:
	var axes := _ring + _step * (_moat_after - 1.0) + (_step + _moat) / 2.0
	var bend := BEND / maxf(axes.x, 1.0)
	var arc := PackedVector2Array()
	var angle := middle - span + bend
	while angle < middle + span - bend:
		arc.append(Vector2(cos(angle), sin(angle)) * axes)
		angle += 0.04
	arc.append(Vector2(cos(middle + span - bend), sin(middle + span - bend)) * axes)
	_river = _river_leg(middle - span, 1.0, axes, sway)
	_river.append_array(arc)
	var out := _river_leg(middle + span, -1.0, axes, sway + 2.0)
	out.reverse()
	_river.append_array(out)


## Ein Ende des Flusses, von weit draußen bis an den Bogen: gerade auf die
## Mitte zu, leicht geschlängelt, und zuletzt die Kurve in den Bogen hinein –
## `inward` sagt, in welcher Drehrichtung der Bogen von hier aus liegt.
func _river_leg(angle: float, inward: float, axes: Vector2, sway: float) -> PackedVector2Array:
	var corner := Vector2(cos(angle), sin(angle)) * axes
	var away := corner.normalized()
	var leg := PackedVector2Array()
	var far := COUNTRY
	while far > BEND:
		var wide := minf((far - BEND) * 0.12, 70.0)
		leg.append(corner + away * far + away.orthogonal() * sin(far * 0.004 + sway) * wide)
		far -= 40.0
	# Die Kurve: von der Geraden über die Ecke in den Bogen.
	var from := corner + away * BEND
	var along := BEND / maxf(axes.x, 1.0) * inward
	var onto := Vector2(cos(angle + along), sin(angle + along)) * axes
	for k in 9:
		var t := k / 9.0
		leg.append(from.lerp(corner, t).lerp(corner.lerp(onto, t), t))
	return leg


## Das Stück des Flusses, das in der Stadt liegt.
func _river_inside() -> PackedVector2Array:
	var inside := PackedVector2Array()
	for p in _river:
		if absf(p.x) < EXTENT.x + 200.0 and absf(p.y) < EXTENT.y + 200.0:
			inside.append(p)
	return inside


# --------------------------------------------------------------- Wege

## Legt das Raster der Straßen an: Blöcke und Fluss sind belegt, alles andere
## ist frei. Wo eine große Straße den Fluss kreuzt, führt eine Brücke hinüber.
func _pave() -> void:
	_span()
	var cells := Vector2i((EXTENT * 2.0 / CELL).ceil())
	_grid = AStarGrid2D.new()
	_grid.region = Rect2i(Vector2i.ZERO, cells)
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.update()
	_covered = {}
	_used = {}
	for b in _blocks:
		for inner in Geometry2D.offset_polygon(b["poly"], -CURB):
			if not Geometry2D.is_polygon_clockwise(inner):
				_fill(inner)
	# Der Fluss mit etwas Ufer.
	for water in Geometry2D.offset_polyline(_river_inside(), RIVER / 2.0 + CELL):
		if not Geometry2D.is_polygon_clockwise(water):
			_fill(water)
	# Was nicht eigens Straße ist, kostet wie eine Gasse: auch Ufer und freies Land.
	_grid.fill_weight_scale_region(_grid.region, COST_ALLEY)
	for street in _streets:
		var a: Vector2 = street[0]
		var length := a.distance_to(street[1])
		var steps := maxi(int(ceil(length / (CELL * 2.0))), 1)
		for i in steps + 1:
			var patch := Rect2i(_cell(a.lerp(street[1], float(i) / steps)) - Vector2i.ONE, Vector2i(3, 3)).intersection(_grid.region)
			if patch.has_area():
				_grid.fill_weight_scale_region(patch, COST_STREET)
	# Die großen Straßen kosten am wenigsten, und wo sie über dem Wasser
	# liegen, führt eine Brücke hinüber.
	var reach := int(ceil(AVENUE / 2.0 / CELL))
	for avenue in _avenues:
		var from: Vector2 = avenue[0]
		var dir: Vector2 = (avenue[1] - from).normalized()
		# Nur das Stück in der Stadt lohnt das Abschreiten.
		var middle := (Vector2.ZERO - from).dot(dir)
		var along := middle - EXTENT.length()
		while along < middle + EXTENT.length():
			var p := from + dir * along
			along += CELL
			if absf(p.x) > EXTENT.x or absf(p.y) > EXTENT.y:
				continue
			var cell := _cell(p)
			var patch := Rect2i(cell - Vector2i(reach, reach), Vector2i(reach, reach) * 2 + Vector2i.ONE).intersection(_grid.region)
			if not patch.has_area():
				continue
			_grid.fill_weight_scale_region(patch, 1.0)
	for bridge in _bridges:
		var a: Vector2 = bridge["from"]
		var wide: float = bridge["width"]
		var around := maxi(int(floor(wide / 2.0 / CELL)), 1)
		var steps := maxi(int(ceil(a.distance_to(bridge["to"]) / CELL)), 1)
		for i in steps + 1:
			var patch := Rect2i(_cell(a.lerp(bridge["to"], float(i) / steps)) - Vector2i(around, around), Vector2i(around, around) * 2 + Vector2i.ONE).intersection(_grid.region)
			if patch.has_area():
				_grid.fill_solid_region(patch, false)
				_grid.fill_weight_scale_region(patch, 1.0 if wide >= AVENUE else COST_STREET)


## Ob eine Karte hier im Weg läge: auf einer Brücke oder im Wasser. Die
## Fläche liegt um `mid` und ist nach jeder Seite `half` groß.
func in_the_way(mid: Vector2, half: Vector2) -> bool:
	if _river_distance(mid) < RIVER / 2.0 + maxf(half.x, half.y) - 2.0:
		return true
	for bridge in _bridges:
		var a: Vector2 = bridge["from"]
		var b: Vector2 = bridge["to"]
		var wide: float = bridge["width"] / 2.0
		var steps := maxi(int(ceil(a.distance_to(b) / 8.0)), 1)
		for i in steps + 1:
			var away := (a.lerp(b, float(i) / steps) - mid).abs()
			if away.x < half.x + wide and away.y < half.y + wide:
				return true
	return false


## Baut die Brücken: eine, wo ein Ring den Fluss kreuzt, eine, wo eine große
## Straße ihn kreuzt, und dazwischen weitere, damit kein Weg weit ausholen muss.
func _span() -> void:
	var water := _river_inside()
	var reach := RIVER / 2.0 + BRIDGE_LAND
	var taken := PackedVector2Array()
	# Die Ringe: wo der Fluss von innen nach außen einen kreuzt.
	for ring_no in range(_moat_after, _rings):
		var axes := _ring + _step * float(ring_no) + _moat
		if axes.x > EXTENT.x * 0.85 or axes.y > EXTENT.y * 0.85:
			break
		for i in water.size() - 1:
			var a := water[i]
			var b := water[i + 1]
			var inside_a := pow(a.x / axes.x, 2.0) + pow(a.y / axes.y, 2.0) <= 1.0
			var inside_b := pow(b.x / axes.x, 2.0) + pow(b.y / axes.y, 2.0) <= 1.0
			if inside_a == inside_b:
				continue
			var p := (a + b) / 2.0
			var over := (b - a).normalized().orthogonal()
			_bridges.append({"from": p - over * reach, "to": p + over * reach, "width": BRIDGE_NARROW})
			taken.append(p)
	# Die großen Straßen. Je schräger eine den Fluss trifft, desto länger die
	# Brücke; läuft sie fast mit ihm, gibt es keine.
	for avenue in _avenues:
		for i in water.size() - 1:
			var hit: Variant = Geometry2D.segment_intersects_segment(avenue[0], avenue[1], water[i], water[i + 1])
			if hit == null or absf(hit.x) > EXTENT.x or absf(hit.y) > EXTENT.y:
				continue
			var dir: Vector2 = (avenue[1] - avenue[0]).normalized()
			var across := absf(dir.cross((water[i + 1] - water[i]).normalized()))
			if across <= 0.4 or _near(taken, hit, 110.0):
				continue
			_bridges.append({"from": hit - dir * reach / across, "to": hit + dir * reach / across, "width": AVENUE})
			taken.append(hit)
	# Dazwischen in Abständen quer hinüber.
	var since := BRIDGE_EVERY / 2.0
	for i in water.size() - 1:
		since += water[i].distance_to(water[i + 1])
		var p := (water[i] + water[i + 1]) / 2.0
		if since < BRIDGE_EVERY or _near(taken, p, BRIDGE_EVERY * 0.6) or absf(p.x) > EXTENT.x * 0.9 or absf(p.y) > EXTENT.y * 0.9:
			continue
		since = 0.0
		var over := (water[i + 1] - water[i]).normalized().orthogonal()
		_bridges.append({"from": p - over * reach, "to": p + over * reach, "width": BRIDGE_NARROW})
		taken.append(p)


static func _near(points: PackedVector2Array, p: Vector2, within: float) -> bool:
	for other in points:
		if other.distance_to(p) < within:
			return true
	return false


## Belegt die Felder, deren Mitte in diesem Vieleck liegt – Zeile für Zeile.
func _fill(poly: PackedVector2Array) -> void:
	var low := INF
	var high := -INF
	for p in poly:
		low = minf(low, p.y)
		high = maxf(high, p.y)
	var first := maxi(int(ceil((low + EXTENT.y) / CELL - 0.5)), 0)
	var last := mini(int(floor((high + EXTENT.y) / CELL - 0.5)), _grid.region.size.y - 1)
	for j in range(first, last + 1):
		var y := -EXTENT.y + (j + 0.5) * CELL
		var cuts := []
		for k in poly.size():
			var a := poly[k]
			var b := poly[(k + 1) % poly.size()]
			if (a.y <= y) != (b.y <= y):
				cuts.append(a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y))
		cuts.sort()
		for k in range(0, cuts.size() - 1, 2):
			var left := maxi(int(ceil((cuts[k] + EXTENT.x) / CELL - 0.5)), 0)
			var right := mini(int(floor((cuts[k + 1] + EXTENT.x) / CELL - 0.5)), _grid.region.size.x - 1)
			if right >= left:
				_grid.fill_solid_region(Rect2i(left, j, right - left + 1, 1), true)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(((p + EXTENT) / CELL).floor())


func _spot(cell: Vector2i) -> Vector2:
	return -EXTENT + (Vector2(cell) + Vector2(0.5, 0.5)) * CELL


func _blocked(cell: Vector2i) -> bool:
	return not _grid.region.has_point(cell) or _grid.is_point_solid(cell)


## Das nächste freie Feld um `cell`; (-1, -1), wenn weit und breit keines ist.
func _free_near(cell: Vector2i) -> Vector2i:
	for r in 80:
		var best := Vector2i(-1, -1)
		var near := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := cell + Vector2i(dx, dy)
				if not _blocked(c) and Vector2(dx, dy).length() < near:
					near = Vector2(dx, dy).length()
					best = c
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


## Ob zwischen zwei Punkten nur Straße liegt – und keine Karte: über die soll
## beim Begradigen keine Abkürzung führen.
func _clear(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(int(ceil(a.distance_to(b) / (CELL * 0.5))), 1)
	for i in steps + 1:
		var cell := _cell(a.lerp(b, float(i) / steps))
		if _blocked(cell) or _covered.has(cell):
			return false
	return true


## Macht die Straße entlang eines gefundenen Wegs für die nächsten teurer.
## Unter Karten nicht: dort müssen alle hinaus und hinein.
func _wear(ids: Array[Vector2i]) -> void:
	var seen := {}
	for k in range(0, ids.size(), 2):
		for dy in range(-SHARE_REACH, SHARE_REACH + 1):
			for dx in range(-SHARE_REACH, SHARE_REACH + 1):
				var cell: Vector2i = ids[k] + Vector2i(dx, dy)
				if seen.has(cell) or _covered.has(cell) or _blocked(cell):
					continue
				seen[cell] = true
				var cost := _grid.get_point_weight_scale(cell)
				if not _used.has(cell):
					_used[cell] = cost
				_grid.set_point_weight_scale(cell, cost * SHARE_COST)


## Sagt der Stadt, wo Karten liegen (und die Mitte): diese Flächen sind für
## Wege frei, aber teuer. Was vorher dort lag, kommt beim nächsten Mal zurück.
func set_cards(boxes: Array) -> void:
	if _grid == null:
		return
	# Mit den Karten beginnt auch die Wegsuche neu: alle Straßen sind wieder frei.
	for cell in _used:
		_grid.set_point_weight_scale(cell, _used[cell])
	_used = {}
	for cell in _covered:
		_grid.set_point_solid(cell, _covered[cell][0])
		_grid.set_point_weight_scale(cell, _covered[cell][1])
	_covered = {}
	for box in boxes:
		var from := _cell(box.position)
		var to := _cell(box.end)
		for j in range(maxi(from.y, 0), mini(to.y, _grid.region.size.y - 1) + 1):
			for i in range(maxi(from.x, 0), mini(to.x, _grid.region.size.x - 1) + 1):
				var cell := Vector2i(i, j)
				if not _covered.has(cell):
					_covered[cell] = [_grid.is_point_solid(cell), _grid.get_point_weight_scale(cell)]
					_grid.set_point_solid(cell, false)
					_grid.set_point_weight_scale(cell, COST_CARD)


## Der Weg von `from` nach `to` über die Straßen: ein Stich von jedem Ende
## zur nächsten Straße und dazwischen ihr entlang. Gibt es keinen, die Gerade.
func route(from: Vector2, to: Vector2) -> PackedVector2Array:
	var straight := PackedVector2Array([from, to])
	if _grid == null:
		return straight
	var a := _free_near(_cell(from))
	var b := _free_near(_cell(to))
	if a.x < 0 or b.x < 0:
		return straight
	var ids := _grid.get_id_path(a, b)
	if ids.is_empty():
		return straight
	var points := PackedVector2Array([from])
	for id in ids:
		points.append(_spot(id))
	points.append(to)
	_wear(ids)
	# Aus der Treppe von Feld zu Feld werden gerade Stücke: von jedem Punkt
	# gleich so weit, wie die Straße frei geradeaus führt.
	var out := PackedVector2Array([points[0]])
	var i := 0
	while i < points.size() - 1:
		var j := i + 1
		while j + 1 < points.size() and _clear(points[i], points[j + 1]):
			j += 1
		out.append(points[j])
		i = j
	return _round(_simplify(out, 0, out.size() - 1))


## Nimmt kleine Zacken aus einem Weg: Punkte, die weniger als `SMOOTH` von der
## Geraden zwischen ihren Nachbarn abweichen, fallen weg.
func _simplify(points: PackedVector2Array, first: int, last: int) -> PackedVector2Array:
	var far := 0.0
	var at := -1
	for i in range(first + 1, last):
		var d := Geometry2D.get_closest_point_to_segment(points[i], points[first], points[last]).distance_to(points[i])
		if d > far:
			far = d
			at = i
	if at < 0 or far <= SMOOTH:
		return PackedVector2Array([points[first], points[last]])
	var out := _simplify(points, first, at)
	var rest := _simplify(points, at, last)
	rest.remove_at(0)
	out.append_array(rest)
	return out


## Rundet die Ecken eines Wegs ab, jede höchstens um `CORNER`.
func _round(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() < 3:
		return points
	var out := PackedVector2Array([points[0]])
	for i in range(1, points.size() - 1):
		var p := points[i]
		var before := p.move_toward(points[i - 1], minf(CORNER, p.distance_to(points[i - 1]) / 2.0))
		var after := p.move_toward(points[i + 1], minf(CORNER, p.distance_to(points[i + 1]) / 2.0))
		for k in 5:
			var t := k / 4.0
			out.append(before.lerp(p, t).lerp(p.lerp(after, t), t))
	out.append(points[points.size() - 1])
	return out


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
	if gap > ALLEY:
		var from := rect.position + (Vector2(cut, 0) if wide else Vector2(0, cut))
		var to := from + (Vector2(0, rect.size.y) if wide else Vector2(rect.size.x, 0))
		_streets.append([from.rotated(turn), to.rotated(turn)])
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
		# Zum Rand hin stehen immer weniger Blöcke. Gewürfelt wird aus der Lage,
		# nicht aus der Reihe – sonst sähe die übrige Stadt anders aus.
		var solid := _solid(mid)
		if solid <= 0.02 or (hash(Vector2i(mid)) % 1000) / 1000.0 < (1.0 - solid) * THIN:
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
		_blocks.append({"poly": piece, "mid": mid, "kind": "park" if park else "town", "roofs": roofs, "at": 0.0, "solid": solid})


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
	# Im Umland sind die großen Straßen Landstraßen.
	for avenue in _avenues:
		draw_line(avenue[0], avenue[1], COUNTRY_ROAD, AVENUE * 0.5)
	_draw_ground()
	# Der Mittelstreifen der großen Straßen.
	for avenue in _avenues:
		draw_dashed_line(avenue[0], avenue[1], LANE, 1.6, 16.0, true, false)
	if _river.size() >= 2:
		draw_polyline(_river, WATER, RIVER, false)
	for bridge in _bridges:
		var a: Vector2 = bridge["from"]
		var b: Vector2 = bridge["to"]
		var fade := _solid((a + b) / 2.0)
		if fade <= 0.05:
			continue
		var wide: float = bridge["width"]
		var edge := (b - a).normalized().orthogonal() * wide / 2.0
		draw_line(a, b, Color(BRIDGE_DECK, fade), wide)
		for way in [-1.0, 1.0]:
			draw_line(a + edge * way, b + edge * way, Color(BRIDGE_RAIL, BRIDGE_RAIL.a * fade), 1.4)
		if wide >= AVENUE:
			draw_dashed_line(a, b, Color(LANE, LANE.a * fade), 1.6, 16.0, true, false)
	for b in _blocks:
		var t := _taken(b["at"])
		var solid: float = b["solid"]
		if b["kind"] == "park":
			var grass: Color = Color(FOE_PARK.lerp(OWN_PARK, t), solid)
			draw_colored_polygon(b["poly"], grass)
			if detail >= 2:
				for k in 4:
					var tree: Vector2 = b["mid"] + Vector2(-14.0 + 28.0 * (k % 2), -14.0 + 28.0 * (k / 2))
					draw_circle(tree, 7.0, grass.lightened(0.12), true, -1.0, false)
			continue
		draw_colored_polygon(b["poly"], Color(FOE_GROUND.lerp(OWN_GROUND, t), solid))
		if detail < 1:
			continue
		for roof in b["roofs"]:
			var own := _taken(roof["at"])
			var poly: PackedVector2Array = roof["poly"]
			if detail >= 2:
				var shade := PackedVector2Array()
				for p in poly:
					shade.append(p + Vector2(3.0, 3.5))
				draw_colored_polygon(shade, Color(0, 0, 0, 0.35 * solid))
			draw_colored_polygon(poly, Color(FOE_ROOFS[roof["tone"]].lerp(OWN_ROOFS[roof["tone"]], own), solid))


## Der Grund der Stadt, die Farbe ihrer Straßen: innen deckend, zum Rand hin
## immer durchsichtiger, bis nur der Filz bleibt. Ein Stück, damit keine Nähte entstehen.
func _draw_ground() -> void:
	const AROUND := 96
	var steps := [0.0, FADE_FROM, 0.72, 0.86, 1.0]
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for step in steps.size():
		var reach: float = steps[step]
		var color := Color(STREET, 1.0 - smoothstep(FADE_FROM, 1.0, reach))
		for i in AROUND:
			var angle := TAU * i / AROUND
			var c := cos(angle)
			var n := sin(angle)
			points.append(Vector2(signf(c) * sqrt(absf(c)) * EXTENT.x, signf(n) * sqrt(absf(n)) * EXTENT.y) * reach)
			colors.append(color)
		if step == 0:
			continue
		for i in AROUND:
			var a := (step - 1) * AROUND + i
			var b := (step - 1) * AROUND + (i + 1) % AROUND
			indices.append_array([a, b, a + AROUND, b, b + AROUND, a + AROUND])
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, points, colors)
