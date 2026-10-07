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
const MilestoneWindow := preload("ui/milestone_window.gd")
const ImageWindow := preload("ui/image_window.gd")
const Links := preload("core/links.gd")
const SceneMenu := preload("ui/scene_menu.gd")
const SceneCards := preload("ui/scene_cards.gd")
const SceneView := preload("rules/scene_view.gd")

const MENU_SETUP := "Tasker einrichten …"
const MENU_TABLE := "Tasker-Tisch"

const SHORTCUT_SEARCH := "tasker/search"
const COMMANDS := {
	"tasker/search": "Tasker: Aufgabe suchen",
	"tasker/table": "Tasker: Tisch öffnen",
	"tasker/reload": "Tasker: Neu laden",
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
## Die Suche, die eine Aufgabe für die ausgewählten Nodes aussucht.
var _attach: SearchPopup
var _attach_nodes: Array = []
var _scene_menu: SceneMenu
var _scene_cards: SceneCards
## Der Filter der Karten in den Leisten des 2D- und des 3D-Editors: Leiste → Knopf.
var _filters := {}
var _last_reload := 0
## Die offenen Aufgabenfenster, je Aufgabe höchstens eines: ID → Fenster.
var _task_windows := {}


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

	_scene_menu = SceneMenu.new()
	_scene_menu.store = store
	_scene_menu.links = links
	_scene_menu.attach_requested.connect(_open_attach)
	_scene_menu.task_requested.connect(_open_task)
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

	_panel = Dock.new()
	_dock = EditorDock.new()
	_dock.title = "Tasker"
	_dock.layout_key = "tasker"
	# Als Tab neben dem Inspektor.
	_dock.default_slot = EditorDock.DOCK_SLOT_RIGHT_UL
	_dock.add_child(_panel)
	_panel.setup_requested.connect(_open_setup)
	_panel.table_requested.connect(_open_table)
	_panel.task_requested.connect(_open_task)
	add_dock(_dock)
	_panel.connect_store(store, images, memory, links)

	add_tool_menu_item(MENU_SETUP, _open_setup)
	add_tool_menu_item(MENU_TABLE, _open_table)
	_register_commands()

	_connect_to_server()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_SETUP)
	remove_tool_menu_item(MENU_TABLE)
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
	if events != null:
		events.stop()
	for node in [_dock, _search, _attach, _setup, _table, _scene_cards, links, events, store, images, client]:
		if node != null:
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

	var palette := EditorInterface.get_command_palette()
	palette.add_command(COMMANDS["tasker/search"], "tasker/search", _open_search, es.get_shortcut(SHORTCUT_SEARCH).get_as_text())
	palette.add_command(COMMANDS["tasker/table"], "tasker/table", _open_table)
	palette.add_command(COMMANDS["tasker/reload"], "tasker/reload", _reload)


## Übernimmt die Einstellungen und lädt den Stand, sobald alles beisammen ist.
func _connect_to_server() -> void:
	client.base_url = Config.server_url()
	client.token = Config.token()
	store.project_id = Config.project_id()
	if Config.is_configured():
		_reload()
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
		EditorInterface.get_base_control().add_child(_setup)
	_setup.open()


func _open_table() -> void:
	if _table == null:
		_table = TableWindow.new()
		_table.store = store
		_table.images = images
		_table.memory = memory
		_table.visible = false
		_table.task_requested.connect(_open_task)
		EditorInterface.get_base_control().add_child(_table)
	_table.hand_size = Config.hand_size()
	_table.sound_enabled = Config.sound()
	if _table.visible:
		if _table.mode == Window.MODE_MINIMIZED:
			_table.mode = Window.MODE_WINDOWED
		_table.grab_focus()
	else:
		_table.popup_centered()


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

	# Milestones haben ihr eigenes Fenster; geöffnet und gemerkt werden beide gleich.
	var window: Window = MilestoneWindow.new() if store.ws.milestone(task_id) != null else TaskWindow.new()
	window.set("store", store)
	window.set("images", images)
	window.set("task_id", task_id)
	window.set("links", links)
	window.visible = false
	window.connect("task_requested", _open_task)
	window.connect("image_requested", _open_image)
	window.tree_exited.connect(func() -> void:
		if _task_windows.get(task_id) == window:
			_task_windows.erase(task_id))
	_task_windows[task_id] = window
	EditorInterface.get_base_control().add_child(window)
	window.popup_centered()
	# Neue Fenster leicht versetzt, damit sie sich nicht genau verdecken.
	var shift := (_task_windows.size() - 1) % 8 * 28
	window.position += Vector2i(shift, shift)


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
	window.popup_centered()


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


## Der Filter in der Leiste über dem Viewport: welche Karten eingeblendet werden.
func _add_filter(bar: int) -> void:
	var button := OptionButton.new()
	button.flat = true
	button.tooltip_text = "Tasker: welche Karten an den Nodes eingeblendet werden"
	for i in SceneView.MODES.size():
		button.add_item("▣ " + SceneView.LABELS[SceneView.MODES[i]], i)
	button.select(SceneView.MODES.find(_scene_cards.mode))
	button.item_selected.connect(func(i: int) -> void:
		_scene_cards.mode = SceneView.MODES[i]
		# Beide Leisten zeigen denselben Filter.
		for other in _filters.values():
			other.select(i))
	add_control_to_container(bar, button)
	_filters[bar] = button
