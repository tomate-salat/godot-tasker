@tool
extends EditorPlugin
## Tasker im Godot-Editor. Der Plan steht in `PLAN.md` im Projektordner.

const Config := preload("core/config.gd")
const Client := preload("core/client.gd")
const Images := preload("core/images.gd")
const Store := preload("core/store.gd")
const SetupDialog := preload("ui/setup_dialog.gd")
const TableWindow := preload("ui/table_window.gd")

const MENU_SETUP := "Tasker einrichten …"
const MENU_TABLE := "Tasker-Tisch (Prototyp)"

var client: Client
var images: Images
var store: Store

var _setup: SetupDialog
var _table: TableWindow


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

	add_tool_menu_item(MENU_SETUP, _open_setup)
	add_tool_menu_item(MENU_TABLE, _open_table)

	_connect_to_server()


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_SETUP)
	remove_tool_menu_item(MENU_TABLE)
	for node in [_setup, _table, store, images, client]:
		if node != null:
			node.queue_free()


## Übernimmt die Einstellungen und lädt den Stand, sobald alles beisammen ist.
func _connect_to_server() -> void:
	client.base_url = Config.server_url()
	client.token = Config.token()
	store.project_id = Config.project_id()
	if Config.is_configured():
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
		_table.visible = false
		EditorInterface.get_base_control().add_child(_table)
	_table.popup_centered()
