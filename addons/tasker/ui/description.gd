@tool
extends RichTextLabel
## Eine Beschreibung als gerendertes Markdown – in den Fenstern von Aufgaben
## und Milestones gleich. Bilder der Galerie und Zeichnungen werden
## eingesetzt, Verweise wie `$142` sind anklickbar.

## Ein Verweis wurde angeklickt: die Aufgabe oder der Milestone soll geöffnet werden.
signal target_requested(id: String)
## Ein Bild oder eine Zeichnung wurde angeklickt und soll groß gezeigt werden.
signal image_requested(key: String, title: String)

const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Palette := preload("palette.gd")
const Markdown := preload("markdown.gd")

const IMAGE_SCHEME := "bild:"

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


func _init() -> void:
	bbcode_enabled = true
	selection_enabled = true
	meta_clicked.connect(_on_link)


## Zeigt die Beschreibung. `owner_field` ist "taskId" oder "milestoneId".
func show_text(text: Variant, owner_field: String, owner_id: String) -> void:
	_text = text if text is String else ""
	_owner_field = owner_field
	_owner_id = owner_id
	_render()


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
	_render()


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
	var link := str(meta)
	if link.begins_with(IMAGE_SCHEME):
		var key := link.trim_prefix(IMAGE_SCHEME)
		image_requested.emit(key, str(_titles.get(key, "Bild")).replace("[lb]", "["))
	elif link.begins_with(Markdown.REF_SCHEME):
		var target = _by_ref(int(link.trim_prefix(Markdown.REF_SCHEME)))
		if target != null:
			target_requested.emit(target["id"])
	elif link.begins_with("http://") or link.begins_with("https://"):
		OS.shell_open(link)
