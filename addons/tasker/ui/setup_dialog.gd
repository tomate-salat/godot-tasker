@tool
extends ConfirmationDialog
## Einrichten: Server, Zugangs-Token und Projekt.
##
## Geprüft wird über `/api/bootstrap` – das beweist das Token und liefert
## gleich die Projekte zur Auswahl.

signal saved

const Config := preload("../core/config.gd")
const Client := preload("../core/client.gd")

var _url: LineEdit
var _token: LineEdit
var _project: OptionButton
var _check: Button
var _status: Label
## Ein eigener Client, damit ein Fehlversuch die laufende Verbindung nicht verstellt.
var _probe: Client
var _project_ids: Array = []


func _init() -> void:
	title = "Tasker einrichten"
	ok_button_text = "Speichern"
	min_size = Vector2i(520, 0)
	confirmed.connect(_save)

	_probe = Client.new()
	add_child(_probe)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)

	_url = LineEdit.new()
	_url.placeholder_text = "https://tasker.example.com"
	_url.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_row(grid, "Server", _url)

	_token = LineEdit.new()
	_token.secret = true
	_token.placeholder_text = "tsk_…"
	_row(grid, "Zugangs-Token", _token)

	_check = Button.new()
	_check.text = "Verbindung prüfen"
	_check.pressed.connect(_connect_now)
	_row(grid, "", _check)

	_project = OptionButton.new()
	_project.disabled = true
	_project.item_selected.connect(func(_i: int) -> void: _update_ok())
	_row(grid, "Projekt", _project)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(380, 44)
	_row(grid, "", _status)


func open() -> void:
	_url.text = Config.server_url()
	_token.text = Config.token()
	_project.clear()
	_project.disabled = true
	_project_ids = []
	_status.text = "Das Token legst du in Tasker im Profil an."
	_update_ok()
	popup_centered()
	if _url.text != "" and _token.text != "":
		_connect_now()


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	grid.add_child(l)
	grid.add_child(control)


func _connect_now() -> void:
	_probe.base_url = _url.text.strip_edges().trim_suffix("/")
	_probe.token = _token.text.strip_edges()
	_check.disabled = true
	_status.text = "Verbinde …"
	var res := await _probe.get_json("/api/bootstrap")
	_check.disabled = false

	_project.clear()
	_project_ids = []
	if not res["ok"] or not res["data"] is Dictionary:
		_project.disabled = true
		_status.text = res["error"] if res["error"] != "" else "Der Server hat nichts Lesbares geschickt."
		_update_ok()
		return

	var projects: Array = res["data"].get("projects", [])
	var current := Config.project_id()
	for p in projects:
		_project.add_item(p["name"])
		_project_ids.append(p["id"])
		if p["id"] == current:
			_project.select(_project.item_count - 1)
	_project.disabled = projects.is_empty()
	_status.text = "Verbunden – %d %s." % [projects.size(), "Projekt" if projects.size() == 1 else "Projekte"]

	# Bilder und Tempo sind erst mit dem neueren Server per Token lesbar.
	var settings := await _probe.get_json("/api/settings")
	if not settings["ok"]:
		_status.text += " Das Tempo ist per Token nicht lesbar, der Server ist älter – das Wochenziel rechnet dann mit der Vorgabe."
	_update_ok()


func _update_ok() -> void:
	get_ok_button().disabled = _project.disabled or _project.selected < 0


func _save() -> void:
	if _project.selected < 0:
		return
	Config.save(_url.text, _token.text.strip_edges(), _project_ids[_project.selected])
	saved.emit()
