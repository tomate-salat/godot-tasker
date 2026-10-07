@tool
extends EditorPlugin
## Tasker im Godot-Editor. Der Plan steht in `PLAN.md` im Projektordner.

const Config := preload("core/config.gd")
const Client := preload("core/client.gd")
const Images := preload("core/images.gd")
const Store := preload("core/store.gd")
const Dock := preload("ui/dock.gd")
const SearchPopup := preload("ui/search_popup.gd")
const SetupDialog := preload("ui/setup_dialog.gd")
const TableWindow := preload("ui/table_window.gd")
const Memory := preload("core/memory.gd")
const TaskWindow := preload("ui/task_window.gd")
const MilestoneWindow := preload("ui/milestone_window.gd")
const ImageWindow := preload("ui/image_window.gd")

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
var memory: Memory

var _dock: EditorDock
var _panel: Dock
var _search: SearchPopup
var _setup: SetupDialog
var _table: TableWindow
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

	memory = Memory.new()
	memory.persistent = true

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
	_panel.connect_store(store, images, memory)

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
	if _dock != null:
		remove_dock(_dock)
	for window in _task_windows.values():
		if is_instance_valid(window):
			window.queue_free()
	_task_windows.clear()
	for node in [_dock, _search, _setup, _table, store, images, client]:
		if node != null:
			node.queue_free()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and store != null and Config.is_configured():
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
