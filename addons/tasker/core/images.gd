@tool
extends Node
## Holt Bilder aus Taskers Galerie und merkt sie sich.
##
## Die ID eines Bildes ist sein Inhalts-Hash: dasselbe Bild liegt nie unter
## zwei Adressen und eine Adresse nie auf zwei Bildern. Deshalb bleiben Bilder
## für immer auf der Platte liegen und werden nie erneut geholt.

signal loaded(key: String)

const Client := preload("client.gd")

var client: Client
## Ordner für den Zwischenspeicher; leer heißt: nur im Arbeitsspeicher.
var cache_dir := ""

var _textures := {}
var _pending := {}
## Mit welchem Status der Server zuletzt auf einen Schlüssel geantwortet hat.
var _status := {}


## Längere Kante einer gerenderten Zeichnung in Pixeln.
const DRAWING_EDGE := 1600


## Das Bild als Textur – `small` ist die Vorschau für Karten. Null, wenn es
## das Bild nicht gibt oder der Server nicht antwortet.
func get_texture(id: String, small := true) -> Texture2D:
	return await _load(image_key(id, small), "/api/bilder/%s%s" % [id.uri_encode(), "?v=klein" if small else ""])


## Eine Zeichnung als Bild. Tasker rendert sie beim Abruf (`/api/zeichnungsbild`)
## und speichert nichts dazu. `meta` ist der Eintrag aus `drawings` im Stand.
##
## Die Version steht im Schlüssel: solange sie gleich bleibt, kommt das Bild
## von der Platte, und der Server muss nicht neu zeichnen – sein Zeichner
## läuft als eigener Prozess und soll nicht unnötig geweckt werden.
func get_drawing(meta: Dictionary) -> Texture2D:
	var owner_param := "taskId" if meta.get("taskId") else "milestoneId"
	var path := "/api/zeichnungsbild?%s=%s&name=%s&kante=%d&thema=dunkel" % [
		owner_param, str(meta[owner_param]).uri_encode(), str(meta["name"]).uri_encode(), DRAWING_EDGE]
	return await _load(drawing_key(meta), path)


static func image_key(id: String, small := true) -> String:
	return id + ("-k" if small else "")


static func drawing_key(meta: Dictionary) -> String:
	return "z-%s-%d" % [meta["id"], int(meta.get("version", 0))]



## Das Bild unter diesem Schlüssel, falls es schon geladen ist – ohne zu warten.
## Der Status der letzten Antwort des Servers zu diesem Schlüssel, 0 ohne Anfrage.
func status_of(key: String) -> int:
	return _status.get(key, 0)


func peek_key(key: String) -> Texture2D:
	return _textures.get(key)


func _load(key: String, path: String) -> Texture2D:
	if _textures.has(key):
		return _textures[key]
	# Dieselbe Karte kann mehrfach auf dem Tisch liegen – geholt wird nur einmal.
	while _pending.has(key):
		await loaded
	if _textures.has(key):
		return _textures[key]

	_pending[key] = true
	var bytes := _read(key)
	if bytes.is_empty() and client != null:
		var res := await client.request(HTTPClient.METHOD_GET, path)
		_status[key] = res["status"]
		# 204 heißt bei Zeichnungen: sie ist leer, oder Tasker hat noch kein Bild
		# von ihr. Das wird nicht auf der Platte gemerkt – mit der nächsten
		# Version der Zeichnung lohnt ein neuer Versuch.
		if res["ok"] and res["body"].size() > 0:
			bytes = res["body"]
			_write(key, bytes)
	var texture := _decode(bytes)
	if texture != null:
		_textures[key] = texture
	_pending.erase(key)
	loaded.emit(key)
	return texture


## Tasker liefert WebP, PNG nur für Browser, die kein WebP kodieren können.
static func _decode(bytes: PackedByteArray) -> Texture2D:
	if bytes.size() < 12:
		return null
	var image := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		err = image.load_webp_from_buffer(bytes)
	elif bytes[0] == 0x89 and bytes[1] == 0x50:
		err = image.load_png_from_buffer(bytes)
	if err != OK:
		return null
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


func _path(key: String) -> String:
	if cache_dir == "":
		return ""
	return cache_dir.path_join(key if key.is_valid_filename() else key.sha256_text())


func _read(key: String) -> PackedByteArray:
	var path := _path(key)
	if path == "" or not FileAccess.file_exists(path):
		return PackedByteArray()
	return FileAccess.get_file_as_bytes(path)


func _write(key: String, bytes: PackedByteArray) -> void:
	var path := _path(key)
	if path == "":
		return
	DirAccess.make_dir_recursive_absolute(cache_dir)
	# Von einer Zeichnung bleibt nur die neueste Version liegen.
	if key.begins_with("z-"):
		var older := key.substr(0, key.rfind("-") + 1)
		for name in DirAccess.get_files_at(cache_dir):
			if name.begins_with(older) and name != key:
				DirAccess.remove_absolute(cache_dir.path_join(name))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
