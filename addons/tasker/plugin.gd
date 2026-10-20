@tool
extends EditorPlugin
## Tasker im Godot-Editor. Der Plan steht in `PLAN.md` im Projektordner.

const Config := preload("core/config.gd")
const Client := preload("core/client.gd")
const Images := preload("core/images.gd")
const Store := preload("core/store.gd")
const Events := preload("core/events.gd")
const Dock := preload("ui/dock.gd")
const SearchPopup := preload("ui/search_popup.gd")
const SetupDialog := preload("ui/setup_dialog.gd")
const TableWindow := preload("ui/table_window.gd")
const Memory := preload("core/memory.gd")
const TaskWindow := preload("ui/task_window.gd")
const DepGraphWindow := preload("ui/dep_graph_window.gd")
const MilestoneWindow := preload("ui/milestone_window.gd")
const ReleaseWindow := preload("ui/release_window.gd")
const ImageWindow := preload("ui/image_window.gd")
const Links := preload("core/links.gd")
const SceneMenu := preload("ui/scene_menu.gd")
const SceneCards := preload("ui/scene_cards.gd")
const SceneView := preload("rules/scene_view.gd")
const OrphansWindow := preload("ui/orphans_window.gd")
const Mcp := preload("rules/mcp.gd")
const McpServer := preload("core/mcp_server.gd")
const SceneTools := preload("core/scene_tools.gd")
const GameLink := preload("core/game_link.gd")
const ClaudeCli := preload("core/claude_cli.gd")
const ClaudeTasks := preload("core/claude_tasks.gd")
const QuickWindow := preload("ui/quick_window.gd")

const MENU_SETUP := "Tasker-Einstellungen …"
const MENU_TABLE := "Tasker-Tisch"
## Der Knopf oben in der Leiste neben „Asset Store" (Nutzer, 2026-10-12).
const SCREEN_TABLE := "Tisch"
const MENU_ORPHANS := "Tasker: Verknüpfungen prüfen …"
const MCP_NAME := "godot-tasker"
## Den Agenten „tasker-scout“ brachte das Addon bis 2026-10-20 mit und legte
## ihn nach ~/.claude/agents. Aufgaben entstehen jetzt im Addon und in der
## Web-App (Nutzer); die alte Kopie wird beim Start einmal weggeräumt.
const OLD_AGENT_FILE := "tasker-scout.md"
## Das Skript, das im Spiel mitläuft und dem Editor sagt, was dort geladen ist
## (`runtime/probe.gd`). Es kommt als Autoload ins Projekt – einen anderen Weg,
## Code des Addons im Spielprozess zu haben, kennt Godot nicht (Nutzer, 2026-10-13).
const PROBE_NAME := "TaskerProbe"
const PROBE_FILE := "runtime/probe.gd"
const VERSION := "0.1.0"
## Der Eintrag „Erledigtes einblenden“ im Filter-Menü.
const FILTER_DONE := 100
## … und „Aus Prefabs“.
const FILTER_PREFABS := 101

const SHORTCUT_SEARCH := "tasker/search"
const SHORTCUT_CREATE := "tasker/create"
const COMMANDS := {
	"tasker/search": "Tasker: Aufgabe suchen",
	"tasker/create": "Tasker: Neue Aufgabe",
	"tasker/table": "Tasker: Tisch öffnen",
	"tasker/reload": "Tasker: Neu laden",
	"tasker/orphans": "Tasker: Verknüpfungen prüfen",
}

## Beim Zurückkehren in den Editor wird neu geladen – aber nicht öfter als so.
const RELOAD_EVERY_MSEC := 15_000

var client: Client
var images: Images
var store: Store
var events: Events
var memory: Memory
var links: Links

var _dock: EditorDock
var _panel: Dock
var _search: SearchPopup
var _setup: SetupDialog
var _table: TableWindow
## Die Ansicht, die vor dem Klick auf „Tisch" offen war – dorthin geht es gleich zurück.
var _screen := "3D"
## Die Suche, die eine Aufgabe für die ausgewählten Nodes aussucht.
var _attach: SearchPopup
var _attach_nodes: Array = []
var _scene_menu: SceneMenu
var _scene_cards: SceneCards
## Der Filter der Karten in den Leisten des 2D- und des 3D-Editors: Leiste → Knopf.
var _filters := {}
var _orphans: OrphansWindow
var _last_reload := 0
## Die offenen Aufgabenfenster, je Aufgabe höchstens eines: ID → Fenster.
var _task_windows := {}
## Der MCP-Server: darüber liest Claude Code die offene Szene und hängt Aufgaben an Nodes.
var _mcp: McpServer
var _scene_tools: SceneTools
var _game: GameLink
var _mcp_state := ""
## Schnellanlegen und die Claude-Aufträge im Hintergrund.
var _claude: ClaudeTasks
var _quick: QuickWindow


func _enter_tree() -> void:
	Config.register()

	client = Client.new()
	add_child(client)

	images = Images.new()
	images.client = client
	images.cache_dir = EditorInterface.get_editor_paths().get_cache_dir().path_join("tasker/images")
	add_child(images)

	store = Store.new()
	store.client = client
	add_child(store)

	events = Events.new()
	events.client = client
	events.received.connect(store.apply_event)
	# Nach einer Unterbrechung fehlt, was in der Lücke passiert ist.
	events.connected.connect(func(again: bool) -> void:
		if again:
			_reload()
		_panel.set_live(true))
	events.disconnected.connect(func() -> void: _panel.set_live(false))
	add_child(events)

	memory = Memory.new()
	memory.persistent = true

	links = Links.new()
	links.memory = memory
	add_child(links)
	scene_changed.connect(func(_root: Node) -> void: links.on_scene_changed())
	scene_saved.connect(links.on_scene_saved)
	# Was an archivierten oder gelöschten Aufgaben hing, löst sich von selbst.
	store.changed.connect(func() -> void:
		if store.state == "ready":
			links.prune(store.ws))

	_scene_menu = SceneMenu.new()
	_scene_menu.store = store
	_scene_menu.links = links
	_scene_menu.attach_requested.connect(_open_attach)
	_scene_menu.create_requested.connect(_open_quick)
	_scene_menu.task_requested.connect(_open_task)
	_scene_menu.mark_requested.connect(func(nodes: Array) -> void:
		EditorInterface.get_editor_toaster().push_toast("Tasker: " + _scene_tools.mark(nodes)))
	add_context_menu_plugin(EditorContextMenuPlugin.CONTEXT_SLOT_SCENE_TREE, _scene_menu)

	# Die Karten im 2D- und 3D-Editor: immer zeichnen und immer mithören, nicht
	# nur wenn ein bestimmter Node ausgewählt ist.
	_scene_cards = SceneCards.new()
	_scene_cards.store = store
	_scene_cards.images = images
	_scene_cards.links = links
	_scene_cards.redraw_requested.connect(update_overlays)
	_scene_cards.task_requested.connect(_open_task)
	_scene_cards.task_selected.connect(func(id: String) -> void: _panel.select(id))
	_scene_cards.problem.connect(_toast)
	add_child(_scene_cards)
	set_force_draw_over_forwarding_enabled()
	set_input_event_forwarding_always_enabled()
	for bar in [CONTAINER_CANVAS_EDITOR_MENU, CONTAINER_SPATIAL_EDITOR_MENU]:
		_add_filter(bar)
	links.scene_changed.connect(_show_filters)
	memory.changed.connect(_show_filters)

	_panel = Dock.new()
	_dock = EditorDock.new()
	_dock.title = "Tasker"
	_dock.layout_key = "tasker"
	# Als Tab neben dem Inspektor.
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.add_child(_panel)
	_panel.setup_requested.connect(_open_setup)
	_panel.table_requested.connect(_open_table)
	_panel.create_requested.connect(_open_quick)
	_panel.task_requested.connect(_open_task)
	_panel.graph_requested.connect(_open_graph)
	_panel.orphans_requested.connect(_open_orphans)
	add_dock(_dock)
	_panel.connect_store(store, images, memory, links)

	add_tool_menu_item(MENU_SETUP, _open_setup)
	add_tool_menu_item(MENU_TABLE, _open_table)
	main_screen_changed.connect(_on_main_screen_changed)
	add_tool_menu_item(MENU_ORPHANS, _open_orphans)

	_scene_tools = SceneTools.new()
	_scene_tools.links = links
	_scene_tools.store = store
	_game = GameLink.new()
	add_debugger_plugin(_game)
	_scene_tools.game = _game
	_mcp = McpServer.new()
	_mcp.handler = func(body: String) -> String: return await Mcp.answer(body, SceneTools.TOOLS, _scene_tools.run, VERSION)
	add_child(_mcp)
	_claude = ClaudeTasks.new()
	_claude.store = store
	_claude.links = links
	_claude.scene_tools = _scene_tools
	_claude.cli = ClaudeCli.new()
	_claude.add_child(_claude.cli)
	# Die Aufgabe geht erst auf, wenn Claude fertig ist – auch wenn das Fenster
	# zum Anlegen längst zu ist.
	_claude.finished.connect(func(task_id: String, _ok: bool, _message: String, show: bool) -> void:
		if show and store.ws.task(task_id) != null:
			_open_task(task_id))
	# Aufträge aus der Web-App („In Godot verfeinern“).
	events.command.connect(func(name: String, data: Dictionary) -> void:
		if name == "godot-refine":
			_claude.refine(str(data.get("requestId", "")), str(data.get("taskId", "")), str(data.get("mode", "")), str(data.get("prompt", ""))))
	add_child(_claude)
	EditorInterface.get_editor_settings().settings_changed.connect(_apply_mcp)
	_apply_mcp()
	_remove_old_agent()
	_register_commands()

	_connect_to_server()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_SETUP)
	remove_tool_menu_item(MENU_TABLE)
	remove_tool_menu_item(MENU_ORPHANS)
	if EditorInterface.get_editor_settings().settings_changed.is_connected(_apply_mcp):
		EditorInterface.get_editor_settings().settings_changed.disconnect(_apply_mcp)
	if _mcp != null:
		_mcp.stop()
		_mcp.queue_free()
	if _game != null:
		remove_debugger_plugin(_game)
		_game = null
	var palette := EditorInterface.get_command_palette()
	for key in COMMANDS:
		palette.remove_command(key)
	for bar in _filters:
		remove_control_from_container(bar, _filters[bar])
		_filters[bar].queue_free()
	_filters.clear()
	if _scene_menu != null:
		remove_context_menu_plugin(_scene_menu)
	if _dock != null:
		remove_dock(_dock)
	for window in _task_windows.values():
		if is_instance_valid(window):
			window.queue_free()
	_task_windows.clear()
	if is_instance_valid(_quick):
		_quick.queue_free()
	if _claude != null:
		_claude.queue_free()
	if events != null:
		events.stop()
	for node in [_dock, _search, _attach, _setup, _table, _orphans, _scene_cards, links, events, store, images, client]:
		if is_instance_valid(node):
			node.queue_free()


func _notification(what: int) -> void:
	# Steht der Änderungs-Strom, kommt ohnehin alles an – neu geladen wird dann nicht.
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and store != null and Config.is_configured() and not events.live:
		if Time.get_ticks_msec() - _last_reload > RELOAD_EVERY_MSEC:
			_reload()


func _shortcut_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if EditorInterface.get_editor_settings().is_shortcut(SHORTCUT_SEARCH, event):
			_open_search()
			get_viewport().set_input_as_handled()
		elif EditorInterface.get_editor_settings().is_shortcut(SHORTCUT_CREATE, event):
			_open_quick()
			get_viewport().set_input_as_handled()


func _register_commands() -> void:
	var es := EditorInterface.get_editor_settings()
	if not es.has_shortcut(SHORTCUT_SEARCH):
		var key := InputEventKey.new()
		key.keycode = KEY_T
		key.ctrl_pressed = true
		key.alt_pressed = true
		var shortcut := Shortcut.new()
		shortcut.events = [key]
		es.add_shortcut(SHORTCUT_SEARCH, shortcut)
	if not es.has_shortcut(SHORTCUT_CREATE):
		var key := InputEventKey.new()
		key.keycode = KEY_N
		key.ctrl_pressed = true
		key.alt_pressed = true
		var shortcut := Shortcut.new()
		shortcut.events = [key]
		es.add_shortcut(SHORTCUT_CREATE, shortcut)

	var palette := EditorInterface.get_command_palette()
	palette.add_command(COMMANDS["tasker/search"], "tasker/search", _open_search, es.get_shortcut(SHORTCUT_SEARCH).get_as_text())
	palette.add_command(COMMANDS["tasker/create"], "tasker/create", _open_quick, es.get_shortcut(SHORTCUT_CREATE).get_as_text())
	palette.add_command(COMMANDS["tasker/table"], "tasker/table", _open_table)
	palette.add_command(COMMANDS["tasker/reload"], "tasker/reload", _reload)
	palette.add_command(COMMANDS["tasker/orphans"], "tasker/orphans", _open_orphans)


## Übernimmt die Einstellungen und lädt den Stand, sobald alles beisammen ist.
## Übernimmt, was sich in den Einstellungen sofort ändern lässt.
func _apply_settings() -> void:
	store.open_in_app = Config.open_with() == Config.OPEN_APP
	store.app_scheme = Config.APP_SCHEME
	if is_instance_valid(_table):
		_table.sound_enabled = Config.sound()
		_table.set_field_style(Config.field_style())


func _connect_to_server() -> void:
	_apply_settings()
	client.base_url = Config.server_url()
	client.token = Config.token()
	store.project_id = Config.project_id()
	links.home = "%s|%s" % [Config.server_url(), Config.project_id()] if Config.is_configured() else ""
	if Config.is_configured():
		_reload()
		# So weiß die Web-App, dass für dieses Projekt ein Godot offen ist.
		events.addon_query = Events.addon_query_for(Config.project_id(), str(ProjectSettings.get_setting("application/config/name", "Godot")))
		events.start()
	else:
		events.stop()


func _reload() -> void:
	_last_reload = Time.get_ticks_msec()
	store.reload()


func _open_setup() -> void:
	if _setup == null:
		_setup = SetupDialog.new()
		_setup.saved.connect(_connect_to_server)
		_setup.changed.connect(_apply_settings)
		_setup.mcp_status = _mcp_status
		_setup.mcp_copy = _mcp_copy
		EditorInterface.get_base_control().add_child(_setup)
	_setup.open()


# Der Tisch als Knopf in der Leiste der Hauptansichten. Er ist ein eigenes
# Fenster, keine Ansicht: der Knopf öffnet es, und der Editor bleibt, wo er war.
func _has_main_screen() -> bool:
	return true


func _get_plugin_name() -> String:
	return SCREEN_TABLE


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon("GridMap" if theme.has_icon("GridMap", "EditorIcons") else "Node", "EditorIcons")


func _make_visible(visible: bool) -> void:
	if not visible:
		return
	_open_table()
	EditorInterface.set_main_screen_editor.call_deferred(_screen)


func _on_main_screen_changed(screen_name: String) -> void:
	if screen_name != SCREEN_TABLE:
		_screen = screen_name


func _open_table() -> void:
	if _table == null:
		_table = TableWindow.new()
		_table.store = store
		_table.images = images
		_table.visible = false
		_table.task_requested.connect(_open_task)
		EditorInterface.get_base_control().add_child(_table)
	_table.sound_enabled = Config.sound()
	_table.set_field_style(Config.field_style())
	if _table.visible:
		if _table.mode == Window.MODE_MINIMIZED:
			_table.mode = Window.MODE_WINDOWED
		_table.grab_focus()
	else:
		_table.open_centered()


func _open_search() -> void:
	if _search == null:
		_search = SearchPopup.new()
		_search.store = store
		_search.picked.connect(_open_task)
		EditorInterface.get_base_control().add_child(_search)
	_search.open()


## Öffnet die Aufgabe oder den Milestone im eigenen Fenster. Ist es schon offen, kommt es nach vorn.
func _open_task(task_id: String) -> void:
	_panel.select(task_id)
	_scene_cards.select(task_id)
	var open = _task_windows.get(task_id)
	if is_instance_valid(open):
		if open.mode == Window.MODE_MINIMIZED:
			open.mode = Window.MODE_WINDOWED
		open.grab_focus()
		return

	# Milestones und Releases haben ihr eigenes Fenster; geöffnet und gemerkt werden alle gleich.
	var window: Window = MilestoneWindow.new() if store.ws.milestone(task_id) != null else ReleaseWindow.new() if store.ws.release(task_id) != null else TaskWindow.new()
	window.set("store", store)
	window.set("images", images)
	window.set("task_id", task_id)
	window.set("links", links)
	window.set("tasks", _claude)
	window.set("scene_tools", _scene_tools)
	window.visible = false
	window.connect("task_requested", _open_task)
	window.connect("image_requested", _open_image)
	window.tree_exited.connect(func() -> void:
		if _task_windows.get(task_id) == window:
			_task_windows.erase(task_id))
	_task_windows[task_id] = window
	EditorInterface.get_base_control().add_child(window)
	window.open_centered()
	# Neue Fenster leicht versetzt, damit sie sich nicht genau verdecken.
	var shift := (_task_windows.size() - 1) % 8 * 28
	window.position += Vector2i(shift, shift)


## Zeigt die Abhängigkeiten einer Aufgabe als Graph im eigenen Fenster. Je
## Aufgabe eines, wie bei den Aufgabenfenstern.
func _open_graph(task_id: String) -> void:
	var id := "graph:" + task_id
	var open = _task_windows.get(id)
	if is_instance_valid(open):
		if open.mode == Window.MODE_MINIMIZED:
			open.mode = Window.MODE_WINDOWED
		open.grab_focus()
		return
	var window := DepGraphWindow.new()
	window.store = store
	window.task_id = task_id
	window.visible = false
	window.task_requested.connect(_open_task)
	window.tree_exited.connect(func() -> void:
		if _task_windows.get(id) == window:
			_task_windows.erase(id))
	_task_windows[id] = window
	EditorInterface.get_base_control().add_child(window)
	window.open_centered()


## Zeigt ein Bild oder eine Zeichnung groß. Je Bild ein Fenster, wie bei den Aufgaben.
func _open_image(key: String, title: String) -> void:
	var texture := images.peek_key(key)
	if texture == null:
		return
	var id := "bild:" + key
	var open = _task_windows.get(id)
	if is_instance_valid(open):
		if open.mode == Window.MODE_MINIMIZED:
			open.mode = Window.MODE_WINDOWED
		open.grab_focus()
		return
	var window := ImageWindow.new()
	window.texture = texture
	window.title = title
	window.visible = false
	window.tree_exited.connect(func() -> void:
		if _task_windows.get(id) == window:
			_task_windows.erase(id))
	_task_windows[id] = window
	EditorInterface.get_base_control().add_child(window)
	# Vor den Karten, die sich im Vordergrund halten – und deshalb ohne popup_centered(),
	# das ein Fenster an seinen Elter bindet.
	var host := EditorInterface.get_base_control().get_window()
	window.always_on_top = true
	window.position = host.position + (host.size - window.size) / 2
	window.show()


## Schnellanlegen: höchstens ein Fenster; ist es offen, kommt es nach vorn und
## nimmt die neue Auswahl dazu.
func _open_quick() -> void:
	if store.state != "ready":
		_toast("Erst mit Tasker verbinden – dann lässt sich anlegen.")
		return
	if is_instance_valid(_quick):
		if _quick.mode == Window.MODE_MINIMIZED:
			_quick.mode = Window.MODE_WINDOWED
		_quick.add_selection()
		_quick.grab_focus()
		return
	_quick = QuickWindow.new()
	_quick.tasks = _claude
	_quick.scene_tools = _scene_tools
	_quick.links = links
	_quick.visible = false
	_quick.task_requested.connect(_open_task)
	EditorInterface.get_base_control().add_child(_quick)
	_quick.open_centered()


## Sucht eine Aufgabe aus und hängt sie an die Nodes (aus dem Szenenbaum).
func _open_attach(nodes: Array) -> void:
	if _attach == null:
		_attach = SearchPopup.new()
		_attach.store = store
		_attach.action = "hängt die Aufgabe an den Node"
		_attach.picked.connect(func(task_id: String) -> void:
			_toast(links.link(task_id, _attach_nodes.filter(is_instance_valid))))
		EditorInterface.get_base_control().add_child(_attach)
	_attach_nodes = nodes
	_attach.open()


## Sagt unten rechts im Editor, warum etwas nicht ging.
func _toast(problem: String) -> void:
	if problem != "":
		EditorInterface.get_editor_toaster().push_toast("Tasker: " + problem, EditorToaster.SEVERITY_WARNING)


# ------------------------------------------------- Karten im Viewport

func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	if _scene_cards != null:
		_scene_cards.draw_2d(overlay)


func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	if _scene_cards != null:
		_scene_cards.draw_3d(overlay)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	return _scene_cards != null and _scene_cards.input(SceneCards.VIEW_2D, event)


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _scene_cards != null and _scene_cards.input(camera.get_instance_id(), event):
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


## Der Filter in der Leiste über dem Viewport: welche Karten eingeblendet
## werden, und im selben Menü, ob Erledigtes dazugehört.
func _add_filter(bar: int) -> void:
	var button := MenuButton.new()
	button.flat = true
	button.tooltip_text = "Tasker: welche Karten an den Nodes eingeblendet werden"
	var menu := button.get_popup()
	menu.hide_on_checkable_item_selection = false
	for i in SceneView.MODES.size():
		menu.add_radio_check_item(SceneView.LABELS[SceneView.MODES[i]], i)
	menu.add_separator()
	menu.add_check_item("Erledigtes einblenden", FILTER_DONE)
	menu.add_check_item("Aus Prefabs", FILTER_PREFABS)
	menu.set_item_tooltip(menu.get_item_index(FILTER_PREFABS), "Auch zeigen, was an Prefabs hängt, die hier als Instanz stecken")
	menu.id_pressed.connect(func(id: int) -> void:
		if id == FILTER_DONE:
			_scene_cards.hide_done = not _scene_cards.hide_done
		elif id == FILTER_PREFABS:
			_scene_cards.hide_prefabs = not _scene_cards.hide_prefabs
		else:
			_scene_cards.mode = SceneView.MODES[id]
		_show_filters())
	add_control_to_container(bar, button)
	_filters[bar] = button
	_show_filters()


## Beide Leisten zeigen denselben Filter – aber nur, wenn an der offenen Szene
## überhaupt etwas hängt. Sonst gäbe es nichts zu filtern.
func _show_filters() -> void:
	var any := not links.here().is_empty() or not links.from_instances().is_empty()
	for button in _filters.values():
		button.visible = any
		button.text = "▣ " + SceneView.LABELS[_scene_cards.mode]
		var menu: PopupMenu = button.get_popup()
		for i in SceneView.MODES.size():
			menu.set_item_checked(menu.get_item_index(i), SceneView.MODES[i] == _scene_cards.mode)
		menu.set_item_checked(menu.get_item_index(FILTER_DONE), not _scene_cards.hide_done)
		menu.set_item_checked(menu.get_item_index(FILTER_PREFABS), not _scene_cards.hide_prefabs)


## Zeigt die Verknüpfungen, die ins Leere zeigen, zum Aufräumen.
## Startet, stoppt oder verlegt den MCP-Server, wie es in den Einstellungen steht.
func _apply_mcp() -> void:
	if _mcp == null:
		return
	var wanted := "%s|%d|%s" % [Config.mcp_enabled(), Config.mcp_port(), Config.mcp_token() if Config.mcp_enabled() else ""]
	if wanted == _mcp_state:
		return
	_mcp_state = wanted
	if not Config.mcp_enabled():
		_mcp.stop()
		return
	_add_probe()
	_mcp.secret = Config.mcp_token()
	if not _mcp.start(Config.mcp_port()):
		_toast("MCP-Server: " + _mcp.problem)


## Trägt das Skript fürs laufende Spiel als Autoload ein – nur, wenn der
## MCP-Server gebraucht wird, und nur einmal: steht der Eintrag schon in
## `project.godot`, wird die Datei nicht angefasst.
func _add_probe() -> void:
	if not ProjectSettings.has_setting("autoload/" + PROBE_NAME):
		add_autoload_singleton(PROBE_NAME, (get_script() as Script).resource_path.get_base_dir().path_join(PROBE_FILE))


## Wird das Addon abgeschaltet, verschwindet auch der Eintrag wieder.
func _disable_plugin() -> void:
	if ProjectSettings.has_setting("autoload/" + PROBE_NAME):
		remove_autoload_singleton(PROBE_NAME)


## Räumt den früher mitgebrachten Agenten aus dem Ordner des Nutzers – nur
## die Datei, die das Addon selbst dort hingelegt hat.
static func _remove_old_agent() -> void:
	var home := OS.get_environment("USERPROFILE") if OS.has_feature("windows") else OS.get_environment("HOME")
	if home == "":
		return
	var target := home.path_join(".claude/agents").path_join(OLD_AGENT_FILE)
	if FileAccess.file_exists(target) and FileAccess.get_file_as_string(target).begins_with("---\nname: tasker-scout\n"):
		DirAccess.remove_absolute(target)


## Wie es um den MCP-Server steht, für die Einstellungsseite.
func _mcp_status() -> String:
	_apply_mcp()
	if not Config.mcp_enabled():
		return "Der Server ist aus."
	if not _mcp.is_running():
		return "Der Server läuft nicht: %s" % _mcp.problem
	return "Der Server läuft auf 127.0.0.1:%d. Claude Code erreicht ihn, solange dieser Editor offen ist." % _mcp.port()


## Legt den Befehl in die Zwischenablage, der den Server in Claude Code
## einträgt. Das Kennwort steht nur dort und in den Editor-Einstellungen –
## nicht im Projekt. Gibt zurück, was dem Nutzer dazu zu sagen ist.
func _mcp_copy() -> String:
	_apply_mcp()
	if not Config.mcp_enabled() or not _mcp.is_running():
		return "Erst den Server einschalten. %s" % _mcp.problem
	DisplayServer.clipboard_set("claude mcp add --transport http --scope user %s http://127.0.0.1:%d%s --header \"Authorization: Bearer %s\"" % [MCP_NAME, _mcp.port(), McpServer.ROUTE, Config.mcp_token()])
	return "Der Befehl liegt in der Zwischenablage – einmal in einem Terminal einfügen und ausführen. Er enthält das Kennwort."


func _open_orphans() -> void:
	if is_instance_valid(_orphans):
		if _orphans.mode == Window.MODE_MINIMIZED:
			_orphans.mode = Window.MODE_WINDOWED
		_orphans.grab_focus()
		return
	_orphans = OrphansWindow.new()
	_orphans.store = store
	_orphans.links = links
	_orphans.visible = false
	_orphans.task_requested.connect(_open_task)
	EditorInterface.get_base_control().add_child(_orphans)
	_orphans.popup_centered()
