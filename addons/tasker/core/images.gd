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


## Das Bild als Textur – `small` ist die Vorschau für Karten. Null, wenn es
## das Bild nicht gibt oder der Server nicht antwortet.
func get_texture(id: String, small := true) -> Texture2D:
	var key := id + ("-k" if small else "")
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
		var res := await client.request(HTTPClient.METHOD_GET, "/api/bilder/%s%s" % [id.uri_encode(), "?v=klein" if small else ""])
		if res["ok"]:
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
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
