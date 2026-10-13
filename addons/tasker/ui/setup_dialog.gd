@tool
extends AcceptDialog
## Die Einstellungen des Addons an einem Ort: Verbindung, wie Tasker geöffnet
## wird, Tisch, und der Zugang für Claude Code.
##
## Die Verbindung wird geprüft, bevor sie gespeichert wird (`/api/bootstrap`
## beweist das Token und liefert gleich die Projekte zur Auswahl). Alles andere
## gilt sofort. Gespeichert wird in den Editor-Einstellungen (`core/config.gd`),
## nichts davon im Projekt.

## Die Verbindung wurde gespeichert.
signal saved
## Eine der übrigen Einstellungen hat sich geändert.
signal changed

const Config := preload("../core/config.gd")
const Client := preload("../core/client.gd")

## Was das Plugin für den Abschnitt „Claude Code“ beisteuert:
## `mcp_status() -> String` sagt, ob der Server läuft;
## `mcp_copy() -> String` legt den Befehl für Claude Code in die Zwischenablage,
## `agent_install() -> String` den Agenten in den Nutzerordner – beide geben
## zurück, was dem Nutzer dazu zu sagen ist; `agent_status() -> String`.
var mcp_status: Callable
var mcp_copy: Callable
var agent_install: Callable
var agent_status: Callable

var _url: LineEdit
var _token: LineEdit
var _project: OptionButton
var _check: Button
var _save_button: Button
var _status: Label
## Ein eigener Client, damit ein Fehlversuch die laufende Verbindung nicht verstellt.
var _probe: Client
var _project_ids: Array = []

var _open_with: OptionButton
var _sound: CheckBox
var _style: OptionButton
var _mcp_on: CheckBox
var _mcp_port: SpinBox
var _mcp_state: Label
var _agent_state: Label
## Solange die Felder gefüllt werden, ist das keine Änderung des Nutzers.
var _filling := false


func _init() -> void:
	title = "Tasker-Einstellungen"
	ok_button_text = "Schließen"
	min_size = Vector2i(600, 0)

	_probe = Client.new()
	add_child(_probe)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 8)
	add_child(page)

	# ------------------------------------------------------ Verbindung
	var grid := _section(page, "Verbindung")
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
	_project.item_selected.connect(func(_i: int) -> void: _update_save())
	_row(grid, "Projekt", _project)

	_status = _note()
	_row(grid, "", _status)

	_save_button = Button.new()
	_save_button.text = "Verbindung speichern"
	_save_button.pressed.connect(_save)
	_row(grid, "", _save_button)

	# ------------------------------------------------ Öffnen in Tasker
	grid = _section(page, "In Tasker öffnen")
	_open_with = OptionButton.new()
	_open_with.add_item("Im Browser (Adresse)")
	_open_with.set_item_metadata(0, Config.OPEN_BROWSER)
	_open_with.add_item("In der installierten Tasker-App (Deeplink)")
	_open_with.set_item_metadata(1, Config.OPEN_APP)
	_open_with.item_selected.connect(func(i: int) -> void: _store(Config.OPEN_WITH, _open_with.get_item_metadata(i)))
	_row(grid, "Aufgaben öffnen", _open_with)
	var hint := _note()
	hint.text = "Der Deeplink (%s…) setzt voraus, dass Tasker als Web-App installiert ist und das Schema kennt. Ob er ankommt, erfährt das Addon nicht – geht nichts auf, hier wieder auf „Im Browser“ stellen." % Config.APP_SCHEME
	_row(grid, "", hint)

	# ------------------------------------------------------------ Tisch
	grid = _section(page, "Tisch")
	_sound = CheckBox.new()
	_sound.text = "Töne"
	_sound.toggled.connect(func(on: bool) -> void: _store(Config.SOUND, on))
	_row(grid, "", _sound)
	_style = OptionButton.new()
	_style.add_item("Soldaten")
	_style.set_item_metadata(0, "soldiers")
	_style.add_item("Käfer")
	_style.set_item_metadata(1, "bugs")
	_style.item_selected.connect(func(i: int) -> void: _store(Config.FIELD_STYLE, _style.get_item_metadata(i)))
	_row(grid, "Figuren im Feld", _style)

	# ------------------------------------------------------ Claude Code
	grid = _section(page, "Claude Code")
	_mcp_on = CheckBox.new()
	_mcp_on.text = "MCP-Server einschalten"
	_mcp_on.tooltip_text = "Claude Code kann dann sehen, was im Editor offen ist, Tasker-Aufgaben anlegen und an Nodes hängen.\nDer Server hört nur auf diesem Rechner und nur mit Kennwort. Im Spiel läuft dafür der Autoload „TaskerProbe“ mit."
	_mcp_on.toggled.connect(func(on: bool) -> void:
		_store(Config.MCP_ENABLED, on)
		_refresh_claude())
	_row(grid, "", _mcp_on)
	_mcp_port = SpinBox.new()
	_mcp_port.min_value = 1024
	_mcp_port.max_value = 65535
	_mcp_port.value_changed.connect(func(value: float) -> void:
		_store(Config.MCP_PORT, int(value))
		_refresh_claude())
	_row(grid, "Port", _mcp_port)
	_mcp_state = _note()
	_row(grid, "", _mcp_state)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	var copy := Button.new()
	copy.text = "Befehl für Claude Code kopieren"
	copy.tooltip_text = "Legt den Befehl in die Zwischenablage, der den Server in Claude Code einträgt –\neinmal in einem Terminal ausführen. Er enthält das Kennwort."
	copy.pressed.connect(func() -> void:
		_mcp_state.text = mcp_copy.call() if mcp_copy.is_valid() else "")
	buttons.add_child(copy)
	var agent := Button.new()
	agent.text = "Agent „tasker-scout“ installieren"
	agent.tooltip_text = "Legt den Agenten, den das Addon mitbringt, in den Agenten-Ordner von Claude Code –\ner gilt dann in allen Projekten und bereitet Aufgaben vor."
	agent.pressed.connect(func() -> void:
		_agent_state.text = agent_install.call() if agent_install.is_valid() else "")
	buttons.add_child(agent)
	_row(grid, "", buttons)
	_agent_state = _note()
	_row(grid, "", _agent_state)


func open() -> void:
	_filling = true
	_url.text = Config.server_url()
	_token.text = Config.token()
	_project.clear()
	_project.disabled = true
	_project_ids = []
	_status.text = "Das Token legst du in Tasker im Profil an."
	_pick(_open_with, Config.open_with())
	_sound.button_pressed = Config.sound()
	_pick(_style, Config.field_style())
	_mcp_on.button_pressed = Config.mcp_enabled()
	_mcp_port.value = Config.mcp_port()
	_filling = false
	_update_save()
	_refresh_claude()
	popup_centered()
	if _url.text != "" and _token.text != "":
		_connect_now()


## Ein Abschnitt mit Überschrift; gibt das Raster für seine Zeilen zurück.
func _section(page: VBoxContainer, heading: String) -> GridContainer:
	if page.get_child_count() > 0:
		page.add_child(HSeparator.new())
	var label := Label.new()
	label.text = heading
	label.add_theme_font_size_override("font_size", 15)
	page.add_child(label)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	page.add_child(grid)
	return grid


func _row(grid: GridContainer, label: String, control: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 140
	grid.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _note() -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(420, 0)
	label.modulate.a = 0.75
	return label


static func _pick(options: OptionButton, value: Variant) -> void:
	for i in options.item_count:
		if options.get_item_metadata(i) == value:
			options.select(i)
			return
	options.select(0)


## Schreibt eine Einstellung – wenn es der Nutzer war und sie sich geändert hat.
func _store(key: String, value: Variant) -> void:
	if _filling:
		return
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(key) and typeof(settings.get_setting(key)) == typeof(value) and settings.get_setting(key) == value:
		return
	settings.set_setting(key, value)
	changed.emit()


## Zeigt, wie es um Server und Agent steht – kurz nach einer Änderung, wenn
## das Plugin sie umgesetzt hat.
func _refresh_claude() -> void:
	if not is_inside_tree():
		return
	await get_tree().process_frame
	await get_tree().process_frame
	_mcp_state.text = mcp_status.call() if mcp_status.is_valid() else ""
	_agent_state.text = agent_status.call() if agent_status.is_valid() else ""


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
		_update_save()
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
	_update_save()


func _update_save() -> void:
	_save_button.disabled = _project.disabled or _project.selected < 0


func _save() -> void:
	if _project.selected < 0:
		return
	Config.save(_url.text, _token.text.strip_edges(), _project_ids[_project.selected])
	_status.text = "Gespeichert."
	saved.emit()
