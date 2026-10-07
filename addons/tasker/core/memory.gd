@tool
extends RefCounted
## Was sich das Addon lokal merkt und Tasker nicht kennt – etwa welche Karten
## auf der Hand liegen.
##
## Im Editor liegt es in den Projekt-Metadaten (unter `.godot/`, nicht
## versioniert). Ohne Editor, etwa in Tests, nur im Arbeitsspeicher.

signal changed

const SECTION := "tasker"

## Im Editor auf wahr setzen, damit der Zustand einen Neustart übersteht.
var persistent := false

var _data := {}


func read(key: String, default: Variant = null) -> Variant:
	if persistent:
		return EditorInterface.get_editor_settings().get_project_metadata(SECTION, key, default)
	return _data.get(key, default)


func write(key: String, value: Variant) -> void:
	if persistent:
		EditorInterface.get_editor_settings().set_project_metadata(SECTION, key, value)
	else:
		_data[key] = value
	changed.emit()
