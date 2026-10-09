@tool
extends RefCounted
## Wo die Einstellungen des Addons liegen.
##
## Nichts davon steht im Repo des Spiels: Server und Zugangs-Token liegen in
## den Editor-Einstellungen und gelten für alle Projekte auf diesem Rechner.
## Welches Tasker-Projekt zu diesem Godot-Projekt gehört, merkt sich der Editor
## je Projekt (unter `.godot/`, das nicht versioniert wird).

const SERVER_URL := "tasker/server_url"
const TOKEN := "tasker/token"
const HAND_SIZE := "tasker/hand_size"
const SOUND := "tasker/sound"
## Womit auf dem Feld gekämpft wird: "soldiers" oder "bugs".
const FIELD_STYLE := "tasker/field_style"

const METADATA := "tasker"
const PROJECT_ID := "project_id"

const DEFAULT_HAND_SIZE := 7

## Bis zum ersten Commit standen Server und Projekt in `project.godot`.
const OLD_SERVER_URL := "tasker/server_url"
const OLD_PROJECT_ID := "tasker/project_id"


static func register() -> void:
	_editor_setting(SERVER_URL, "", TYPE_STRING, PROPERTY_HINT_PLACEHOLDER_TEXT, "https://tasker.example.com")
	_editor_setting(TOKEN, "", TYPE_STRING, PROPERTY_HINT_PASSWORD)
	_editor_setting(HAND_SIZE, DEFAULT_HAND_SIZE, TYPE_INT, PROPERTY_HINT_RANGE, "1,20,1")
	_editor_setting(SOUND, true, TYPE_BOOL)
	_editor_setting(FIELD_STYLE, "soldiers", TYPE_STRING, PROPERTY_HINT_ENUM, "soldiers,bugs")
	_move_out_of_project_settings()


static func server_url() -> String:
	return str(_editor().get_setting(SERVER_URL)).strip_edges().trim_suffix("/") if _editor().has_setting(SERVER_URL) else ""


static func project_id() -> String:
	return str(_editor().get_project_metadata(METADATA, PROJECT_ID, ""))


static func token() -> String:
	return str(_editor().get_setting(TOKEN)) if _editor().has_setting(TOKEN) else ""


static func sound() -> bool:
	return bool(_editor().get_setting(SOUND)) if _editor().has_setting(SOUND) else true


static func hand_size() -> int:
	return int(_editor().get_setting(HAND_SIZE)) if _editor().has_setting(HAND_SIZE) else DEFAULT_HAND_SIZE


static func is_configured() -> bool:
	return server_url() != "" and token() != "" and project_id() != ""


static func save(url: String, new_token: String, new_project_id: String) -> void:
	_editor().set_setting(SERVER_URL, url.strip_edges().trim_suffix("/"))
	_editor().set_setting(TOKEN, new_token)
	_editor().set_project_metadata(METADATA, PROJECT_ID, new_project_id)


static func _editor() -> EditorSettings:
	return EditorInterface.get_editor_settings()


static func _editor_setting(name: String, value: Variant, type: int, hint := PROPERTY_HINT_NONE, hint_string := "") -> void:
	var es := _editor()
	if not es.has_setting(name):
		es.set_setting(name, value)
	es.set_initial_value(name, value, false)
	es.add_property_info({"name": name, "type": type, "hint": hint, "hint_string": hint_string})


## Übernimmt, was noch in `project.godot` steht, und räumt es dort weg.
static func _move_out_of_project_settings() -> void:
	var found := false
	if ProjectSettings.has_setting(OLD_SERVER_URL):
		found = true
		var url := str(ProjectSettings.get_setting(OLD_SERVER_URL))
		if url != "" and server_url() == "":
			_editor().set_setting(SERVER_URL, url.strip_edges().trim_suffix("/"))
		ProjectSettings.set_setting(OLD_SERVER_URL, null)
	if ProjectSettings.has_setting(OLD_PROJECT_ID):
		found = true
		var id := str(ProjectSettings.get_setting(OLD_PROJECT_ID))
		if id != "" and project_id() == "":
			_editor().set_project_metadata(METADATA, PROJECT_ID, id)
		ProjectSettings.set_setting(OLD_PROJECT_ID, null)
	if found:
		ProjectSettings.save()


static func field_style() -> String:
	return str(_editor().get_setting(FIELD_STYLE)) if _editor().has_setting(FIELD_STYLE) else "soldiers"
