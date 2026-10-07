@tool
extends RichTextLabel
## Eine Beschreibung als gerendertes Markdown – in den Fenstern von Aufgaben
## und Milestones gleich. Bilder der Galerie und Zeichnungen werden
## eingesetzt, Verweise wie `$142` sind anklickbar.

## Ein Verweis wurde angeklickt: die Aufgabe oder der Milestone soll geöffnet werden.
signal target_requested(id: String)
## Ein Bild oder eine Zeichnung wurde angeklickt und soll groß gezeigt werden.
signal image_requested(key: String, title: String)
## Ein Kästchen ließ sich nicht umschalten – mit dem Grund.
signal save_failed(message: String)
## Ein Klick in den Text, der weder Verweis noch Kästchen traf und nichts
## markiert hat: es soll bearbeitet werden.
signal edit_requested

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Palette := preload("palette.gd")
const Markdown := preload("markdown.gd")
const Checklist := preload("../rules/checklist.gd")

const IMAGE_SCHEME := "bild:"
## Kantenlänge eines Kästchens in der Zeile.
const BOX_SIZE := 16

var store: Store
var images: Images

var _text := ""
## Wem die Beschreibung gehört – daran hängen ihre Zeichnungen.
var _owner_field := "taskId"
var _owner_id := ""
## Bilder, die sich nicht laden ließen – damit nicht endlos neu versucht wird.
var _missing := {}
## Wie die gezeigten Bilder heißen: Schlüssel → Name, für den Fenstertitel.
var _titles := {}
## Ein umgeschaltetes Kästchen ist unterwegs; `_unsaved`: seither kam noch eins dazu.
var _saving := false
var _unsaved := false
## Ein Neuzeichnen ist schon für den nächsten Leerlauf bestellt.
var _render_queued := false
## Wo die Maustaste herunterging, und in welchem Bild zuletzt ein Verweis,
## ein Bild oder ein Kästchen angeklickt wurde.
var _press_at := Vector2.INF
var _link_frame := -1
## Die Bilder der Kästchen, offen und abgehakt – gezeichnet statt gesetzt,
## weil die Schriftzeichen dafür verschieden breit ausfallen.
static var _boxes := {}


func _init() -> void:
	bbcode_enabled = true
	selection_enabled = true
	meta_clicked.connect(_on_link)


## Zeigt die Beschreibung. `owner_field` ist "taskId" oder "milestoneId".
func show_text(text: Variant, owner_field: String, owner_id: String) -> void:
	var same := owner_id == _owner_id and owner_field == _owner_field
	# Ein Kästchen, das noch nicht hinausgegangen ist, soll der Stand nicht zurücknehmen.
	if not (same and _saving and _unsaved):
		_text = text if text is String else ""
	_owner_field = owner_field
	_owner_id = owner_id
	# Dieselbe Beschreibung neu gezeigt bleibt, wo man gerade liest.
	var scroll := get_v_scroll_bar().value if same else 0.0
	_render()
	if scroll > 0.0:
		get_v_scroll_bar().set_deferred("value", scroll)


func _render() -> void:
	clear()
	var faint := Palette.FAINT.to_html(false)
	var bbcode := Markdown.to_bbcode(_text, _ref_title)
	if bbcode.strip_edges() == "":
		append_text("[color=#%s]Keine Beschreibung[/color]" % faint)
		return
	var parts := bbcode.split(Markdown.IMAGE)
	for i in parts.size():
		if i % 2 == 0:
			append_text(parts[i])
			continue
		# Eine Marke des Übersetzers: ein Bild der Galerie oder eine Zeichnung.
		var mark: String = parts[i]
		if mark.begins_with(Markdown.CHECK):
			# Ein Kästchen: anklickbar, solange gespeichert werden kann.
			var bits := mark.trim_prefix(Markdown.CHECK).split(":")
			var box := _box(bits[1] == "1")
			if _can_tick():
				push_meta(Markdown.CHECK + bits[0], RichTextLabel.META_UNDERLINE_NEVER, "Klicken hakt ab" if bits[1] == "0" else "Klicken nimmt den Haken weg")
				add_image(box, BOX_SIZE, BOX_SIZE, Color.WHITE, INLINE_ALIGNMENT_CENTER)
				pop()
			else:
				add_image(box, BOX_SIZE, BOX_SIZE, Color.WHITE, INLINE_ALIGNMENT_CENTER)
			continue
		var what := "Bild"
		var key := ""
		var drawing = null
		if mark.begins_with(Markdown.DRAWING):
			var name := mark.trim_prefix(Markdown.DRAWING)
			what = "Zeichnung „%s“" % name.replace("[", "[lb]")
			drawing = _drawing(name)
			if drawing == null:
				append_text("[color=#%s]▣ %s gibt es nicht (mehr)[/color]" % [faint, what])
				continue
			key = Images.drawing_key(drawing)
		else:
			key = Images.image_key(mark, false)

		var texture: Texture2D = images.peek_key(key) if images != null else null
		if texture != null:
			var room := int(size.x) - 16 if size.x > 120.0 else 520
			# Ein Klick auf das Bild zeigt es groß.
			_titles[key] = what
			push_meta(IMAGE_SCHEME + key, RichTextLabel.META_UNDERLINE_NEVER, "Klicken zeigt es groß")
			add_image(texture, mini(texture.get_width(), room))
			pop()
		elif images == null or _missing.has(key):
			append_text("[color=#%s]▣ %s[/color]" % [faint, _why_missing(what, key, drawing != null)])
		else:
			append_text("[color=#%s]▣ %s wird geladen …[/color]" % [faint, what])
			_load(key, mark, drawing)


## Die Zeichnung dieses Namens am Besitzer – aus `drawings` im Stand.
func _drawing(name: String) -> Variant:
	for d in store.data.get("drawings", []):
		if d.get(_owner_field) == _owner_id and d.get("name") == name:
			return d
	return null


func _load(key: String, id: String, drawing: Variant) -> void:
	var texture: Texture2D
	if drawing != null:
		texture = await images.get_drawing(drawing)
	else:
		texture = await images.get_texture(id, false)
	if not is_instance_valid(self):
		return
	if texture == null:
		_missing[key] = true
	# Nie mitten im Zeichnen: kommt das Bild ohne Warten (etwa von der Platte),
	# liefe sonst ein zweites Zeichnen im ersten, und der Rest stünde doppelt da.
	_render_soon()


## Warum statt eines Bildes nur sein Name dasteht.
func _why_missing(what: String, key: String, is_drawing: bool) -> String:
	var status := images.status_of(key) if images != null else 0
	if is_drawing and status == 204:
		return "%s hat noch kein Bild – es entsteht, sobald sie in Tasker gespeichert wird (oder sie ist leer)" % what
	if status == 404:
		return "%s gibt es auf dem Server nicht" % what
	if status == 401:
		return "%s ist mit diesem Token nicht abrufbar" % what
	if status >= 500:
		return "%s ließ sich auf dem Server nicht erzeugen" % what
	return "%s ist nicht verfügbar" % what


## Der Titel zu einem Verweis wie `$142` – leer, wenn es das Ziel nicht gibt.
func _ref_title(number: int) -> String:
	var target = _by_ref(number)
	if target == null:
		return ""
	return target["title"] if target.get("title") else "Ohne Titel"


func _by_ref(number: int) -> Variant:
	for list in [store.ws.tasks, store.ws.milestones]:
		for x in list:
			if int(x.get("ref", 0)) == number:
				return x
	return null


## Ein Verweis öffnet sein Ziel in dessen Fenster, alles andere den Browser.
func _on_link(meta: Variant) -> void:
	_link_frame = Engine.get_process_frames()
	var link := str(meta)
	if link.begins_with(Markdown.CHECK):
		_tick(int(link.trim_prefix(Markdown.CHECK)))
		return
	if link.begins_with(IMAGE_SCHEME):
		var key := link.trim_prefix(IMAGE_SCHEME)
		image_requested.emit(key, str(_titles.get(key, "Bild")).replace("[lb]", "["))
	elif link.begins_with(Markdown.REF_SCHEME):
		var target = _by_ref(int(link.trim_prefix(Markdown.REF_SCHEME)))
		if target != null:
			target_requested.emit(target["id"])
	elif link.begins_with("http://") or link.begins_with("https://"):
		OS.shell_open(link)


# ------------------------------------------------------------- Abhaken

## Kästchen lassen sich nur umschalten, wenn die Änderung auch ankommt.
func _can_tick() -> bool:
	return store != null and store.state == "ready" and _owner_id != ""


## Schaltet das Kästchen in dieser Zeile des Quelltexts um. Es steht sofort
## so da; lehnt Tasker ab, gilt wieder, was im Stand steht.
func _tick(line: int) -> void:
	var n: int = Checklist.lines_of(_text)["out"].find(line)
	if n < 0 or not _can_tick():
		return
	_text = Checklist.toggle_item(_text, n)
	show_text(_text, _owner_field, _owner_id)
	_unsaved = true
	if _saving:
		return
	# Mehrere Klicks kurz nacheinander gehen nacheinander hinaus: jede
	# Änderung muss die Version nennen, die die vorige hinterlassen hat.
	_saving = true
	var owner_id := _owner_id
	var kind := "task" if _owner_field == "taskId" else "milestone"
	while _unsaved and owner_id == _owner_id:
		_unsaved = false
		var res := await store.patch(kind, owner_id, {"desc": _text})
		if not is_instance_valid(self):
			return
		if not res["ok"]:
			_unsaved = false
			if owner_id == _owner_id:
				var current = store._find(kind, owner_id)
				_text = current.get("desc") if current != null and current.get("desc") is String else ""
				_render()
				save_failed.emit(str(res["error"]))
	_saving = false


## Das Bild eines Kästchens: offen ein Rahmen, abgehakt gefüllt mit Haken.
static func _box(done: bool) -> Texture2D:
	if _boxes.has(done):
		return _boxes[done]
	# Doppelt so groß gezeichnet, damit es verkleinert glatt aussieht.
	var n := BOX_SIZE * 4
	var image := Image.create_empty(n, n, true, Image.FORMAT_RGBA8)
	var edge := Palette.ACCENT if done else Palette.MUTED
	var fill := Color(Palette.ACCENT, 0.9) if done else Color(Palette.MUTED, 0.0)
	var inset := 6.0
	var radius := 12.0
	var border := 6.0
	# Der Haken als zwei Striche.
	var a := Vector2(0.24, 0.52) * n
	var b := Vector2(0.43, 0.70) * n
	var c := Vector2(0.77, 0.30) * n
	var half := Vector2(n, n) / 2.0 - Vector2(inset, inset)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			# Abstand zum abgerundeten Rechteck: innen negativ.
			var q := (p - Vector2(n, n) / 2.0).abs() - half + Vector2(radius, radius)
			var dist := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - radius
			var color := Color(0, 0, 0, 0)
			if dist <= 0.0:
				color = edge if dist > -border else fill
			if done and dist < -border:
				var near := minf(_to_segment(p, a, b), _to_segment(p, b, c))
				if near < 4.5:
					color = Palette.SURFACE
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	_boxes[done] = ImageTexture.create_from_image(image)
	return _boxes[done]


static func _to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
	return p.distance_to(a + (b - a) * t)


# ---------------------------------------------------------- Bearbeiten

## Ein schlichter Klick in den Text öffnet das Bearbeiten – wie in Tasker.
## Wer zieht, markiert; wer einen Verweis oder ein Kästchen trifft, meint das.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		_press_at = event.position if not event.double_click else Vector2.INF
	elif _press_at.distance_to(event.position) < 4.0:
		# Erst danach steht fest, ob der Klick einem Verweis galt.
		_maybe_edit.call_deferred()


func _maybe_edit() -> void:
	if _link_frame == Engine.get_process_frames() or get_selected_text() != "" or not _can_tick():
		return
	edit_requested.emit()


## Zeichnet beim nächsten Leerlauf neu – mehrere Wünsche im selben Bild nur einmal.
func _render_soon() -> void:
	if _render_queued:
		return
	_render_queued = true
	(func() -> void:
		_render_queued = false
		var scroll := get_v_scroll_bar().value
		_render()
		if scroll > 0.0:
			get_v_scroll_bar().set_deferred("value", scroll)).call_deferred()
