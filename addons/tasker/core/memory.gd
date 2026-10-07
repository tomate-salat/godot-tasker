@tool
extends RefCounted
## Was sich das Addon lokal merkt und Tasker nicht kennt – etwa welche Karten
## auf der Hand liegen.
##
## Im Editor liegt es in den Projekt-Metadaten (unter `.godot/`, nicht
## versioniert). Ohne Editor, etwa in Tests, nur im Arbeitsspeicher.

signal changed

const SECTION := "tasker"
## Steht für „nichts gemerkt“, wenn der Editor nach einem Schlüssel gefragt wird.
const MISSING := "<tasker:nichts gemerkt>"

## Im Editor auf wahr setzen, damit der Zustand einen Neustart übersteht.
var persistent := false

var _data := {}


func read(key: String, default: Variant = null) -> Variant:
	if persistent:
		# Ohne Vorgabe meldet der Editor einen Fehler, wenn der Schlüssel fehlt –
		# und „null“ zählt für ihn als keine Vorgabe.
		var value = EditorInterface.get_editor_settings().get_project_metadata(SECTION, key, MISSING)
		return default if value is String and value == MISSING else value
	return _data.get(key, default)


func write(key: String, value: Variant) -> void:
	if persistent:
		EditorInterface.get_editor_settings().set_project_metadata(SECTION, key, value)
	else:
		_data[key] = value
	changed.emit()
