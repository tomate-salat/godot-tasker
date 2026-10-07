extends SceneTree
## Entwicklerhilfe: stellt in der Planung nach, dass Tasker einen Zug ablehnt.
## Der Datenbestand ist „verbunden“, sein Client antwortet aber nur zum Schein:
## erst mit einem Fehler, dann mit einem Konflikt (409). Bilder landen unter
## `.godot/tasker_fehler_<n>.png`.
##   godot --path . -s tests/snapshot_move_fail.gd

const TableWindow := preload("res://addons/tasker/ui/table_window.gd")
const Store := preload("res://addons/tasker/core/store.gd")
const Client := preload("res://addons/tasker/core/client.gd")
const Demo := preload("res://addons/tasker/ui/demo.gd")

## So lange lässt sich der Schein-Server Zeit.
const ANSWER_SECONDS := 0.6


## Ein Client, der nichts verschickt.
class FakeClient extends Client:
	var status := 500
	var bootstrap := {}

	func request(method: int, path: String, _body: Variant = null) -> Dictionary:
		await Engine.get_main_loop().create_timer(ANSWER_SECONDS if method == HTTPClient.METHOD_POST else 0.05).timeout
		if path == "/api/bootstrap":
			return {"ok": true, "status": 200, "data": bootstrap, "error": "", "body": PackedByteArray()}
		if path == "/api/move":
			return _failed(status, "Der Server meldet einen Fehler (%d)." % status)
		return _failed(404, "Gibt es hier nicht.")


var _table: TableWindow
var _store: Store
var _client: FakeClient
var _elapsed := 0.0
var _step := 0
var _shots := 0
## Wann nach dem vorigen Schritt der nächste dran ist.
const WAITS := [0.0, 1.2, 0.6, 0.3, 0.3, 0.55, 0.08, 0.08, 0.6, 0.3, 0.3, 0.3, 0.6, 0.12, 0.8]


func _process(delta: float) -> bool:
	_elapsed += delta
	if _step >= WAITS.size():
		return true
	if _elapsed < WAITS[_step]:
		return false
	if _step > 0:
		_shot()
	match _step:
		0:
			_client = FakeClient.new()
			_client.bootstrap = Demo.data()
			_store = Store.new()
			_store.client = _client
			_store.project_id = Demo.PROJECT
			_store.data = Demo.data()
			_store._rebuild()
			_store.state = "ready"
			root.add_child(_client)
			root.add_child(_store)
			_table = TableWindow.new()
			_table.store = _store
			root.add_child(_table)
			_table.popup_centered()
			_table.planning = true
		1:
			_table._plan._show_stock("backlog")
		2:
			_grab()
		3:
			# Loslassen: die Karte liegt sofort im Deck, der Server lehnt gleich ab (500).
			_table._plan._drop()
		9:
			# Dasselbe mit einem Konflikt: danach wird neu geladen.
			_client.status = 409
			_grab()
		10:
			_table._plan._drop()
	_step += 1
	_elapsed = 0.0
	return false


## Eine Karte aus dem Vorrat über ein Fach des laufenden Decks halten.
func _grab() -> void:
	var plan = _table._plan
	plan._pressed = plan._left._sheet.get_meta("cards")[1]
	print("Gezogen: ", plan._pressed.task_id, " moving=", plan._moving)
	plan._start_drag(Vector2(900, 380))
	plan._flying.position = Vector2(1090, 600)
	plan._over = plan._right
	plan._right.hover(Vector2(1140, 720), plan._flying.task_id)


func _shot() -> void:
	_shots += 1
	var out := ProjectSettings.globalize_path("res://.godot/tasker_fehler_%d.png" % _shots)
	_table.get_texture().get_image().save_png(out)
	var plan = _table._plan
	print("Bild ", _shots, ": ", plan._note.text if plan._note.modulate.a > 0.0 else "(kein Hinweis)",
		" | Vorrat: ", plan._left._sheet.get_meta("cards").size(), " Karten auf der Seite, Deck: ", plan._right._sheet.get_meta("cards").size(),
		" | unterwegs: ", plan._moving)
