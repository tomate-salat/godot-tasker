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
## Wie Aufgaben in Tasker geöffnet werden: mit ihrer Adresse im Browser oder
## per Deeplink in der installierten Web-App (Nutzer, 2026-10-13).
const OPEN_WITH := "tasker/open_with"
const OPEN_BROWSER := "browser"
const OPEN_APP := "app"
## Das Schema des Deeplinks. Web-Apps dürfen nur Schemata anmelden, die mit
## „web+“ beginnen. Ohne „//“ dahinter: sonst gälte die Projekt-ID als
## Rechnername, und manche Wege schreiben den klein – die IDs unterscheiden
## aber Groß- und Kleinschreibung. Tasker nimmt beide Formen an.
const APP_SCHEME := "web+tasker:"
## Die Handgröße gehörte zum Spieltisch, den es nicht mehr gibt.
const OLD_HAND_SIZE := "tasker/hand_size"
const SOUND := "tasker/sound"
## Womit auf dem Feld gekämpft wird: "soldiers" oder "bugs".
const FIELD_STYLE := "tasker/field_style"

## Der MCP-Server des Addons (`core/mcp_server.gd`): ob er läuft, auf
## welchem Port, und das Kennwort, das jede Anfrage tragen muss.
const MCP_ENABLED := "tasker/mcp_enabled"
const MCP_PORT := "tasker/mcp_port"
const MCP_TOKEN := "tasker/mcp_token"
const DEFAULT_MCP_PORT := 9309

const METADATA := "tasker"
const PROJECT_ID := "project_id"

## Bis zum ersten Commit standen Server und Projekt in `project.godot`.
const OLD_SERVER_URL := "tasker/server_url"
const OLD_PROJECT_ID := "tasker/project_id"


static func register() -> void:
	_editor_setting(SERVER_URL, "", TYPE_STRING, PROPERTY_HINT_PLACEHOLDER_TEXT, "https://tasker.example.com")
	_editor_setting(TOKEN, "", TYPE_STRING, PROPERTY_HINT_PASSWORD)
	_editor_setting(OPEN_WITH, OPEN_BROWSER, TYPE_STRING, PROPERTY_HINT_ENUM, "%s,%s" % [OPEN_BROWSER, OPEN_APP])
	if _editor().has_setting(OLD_HAND_SIZE):
		_editor().erase(OLD_HAND_SIZE)
	_editor_setting(SOUND, true, TYPE_BOOL)
	_editor_setting(FIELD_STYLE, "soldiers", TYPE_STRING, PROPERTY_HINT_ENUM, "soldiers,bugs")
	_editor_setting(MCP_ENABLED, false, TYPE_BOOL)
	_editor_setting(MCP_PORT, DEFAULT_MCP_PORT, TYPE_INT, PROPERTY_HINT_RANGE, "1024,65535,1")
	_editor_setting(MCP_TOKEN, "", TYPE_STRING, PROPERTY_HINT_PASSWORD)
	_move_out_of_project_settings()


static func server_url() -> String:
	return str(_editor().get_setting(SERVER_URL)).strip_edges().trim_suffix("/") if _editor().has_setting(SERVER_URL) else ""


static func project_id() -> String:
	return str(_editor().get_project_metadata(METADATA, PROJECT_ID, ""))


static func token() -> String:
	return str(_editor().get_setting(TOKEN)) if _editor().has_setting(TOKEN) else ""


static func sound() -> bool:
	return bool(_editor().get_setting(SOUND)) if _editor().has_setting(SOUND) else true


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


static func mcp_enabled() -> bool:
	return bool(_editor().get_setting(MCP_ENABLED)) if _editor().has_setting(MCP_ENABLED) else false


static func mcp_port() -> int:
	return int(_editor().get_setting(MCP_PORT)) if _editor().has_setting(MCP_PORT) else DEFAULT_MCP_PORT


## Das Kennwort des MCP-Servers. Gibt es noch keines, wird eines gewürfelt.
static func mcp_token() -> String:
	var known := str(_editor().get_setting(MCP_TOKEN)) if _editor().has_setting(MCP_TOKEN) else ""
	if known.strip_edges() == "":
		known = Crypto.new().generate_random_bytes(24).hex_encode()
		_editor().set_setting(MCP_TOKEN, known)
	return known


static func open_with() -> String:
	return str(_editor().get_setting(OPEN_WITH)) if _editor().has_setting(OPEN_WITH) else OPEN_BROWSER
