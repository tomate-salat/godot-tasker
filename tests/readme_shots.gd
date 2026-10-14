extends SceneTree
## Entwicklerhilfe: die Bilder für die README, aus den Beispieldaten. Der
## Datenbestand gilt als verbunden, damit kein Hinweis „Beispieldaten“ im Kopf
## steht; geschickt wird nichts. Bilder landen unter `docs/screenshots/`.
##   godot --path . -s tests/readme_shots.gd

const TableWindow := preload("res://addons/tasker/ui/table_window.gd")
const TaskWindow := preload("res://addons/tasker/ui/task_window.gd")
const MilestoneWindow := preload("res://addons/tasker/ui/milestone_window.gd")
const ReleaseWindow := preload("res://addons/tasker/ui/release_window.gd")
const Store := preload("res://addons/tasker/core/store.gd")
const Workspace := preload("res://addons/tasker/rules/workspace.gd")
const Demo := preload("res://addons/tasker/ui/demo.gd")

const OUT := "res://docs/screenshots/"
const DAY := 86400.0

var _store: Store
var _table: TableWindow
var _window: Window
var _elapsed := 0.0
var _step := 0


## Die Beispieldaten, ergänzt um ein Release und ein paar Tage Verlauf.
static func _data() -> Dictionary:
	var data := Demo.data()
	var now := Time.get_unix_time_from_system()
	var iso := func(days_ago: float) -> String:
		return Time.get_datetime_string_from_unix_time(int(now - days_ago * DAY)) + ".000Z"
	var date := func(days: float) -> String:
		return Time.get_date_string_from_unix_time(int(now + days * DAY))
	# Erledigtes verteilt sich auf die letzten Tage, damit Woche und Burnup etwas zeigen.
	var done := {"k": 9.0, "j": 5.0, "d1": 1.0, "p1": 20.0}
	for t in data["tasks"]:
		if done.has(t["id"]):
			t["doneAt"] = iso.call(done[t["id"]])
	for m in data["milestones"]:
		m["releaseId"] = "rel"
		if m["id"] == "ms":
			m["startDate"] = date.call(-10)
			m["endDate"] = date.call(6)
			m["desc"] = "Ein Level, das man von vorn bis hinten **durchspielen** kann.\n\n- [x] Steuerung\n- [ ] Speichern\n- [ ] Ein Abspann"
	data["releases"] = [{"id": "rel", "ref": 80, "version": 1, "projectId": Demo.PROJECT, "name": "0.1", "title": "Early Access",
		"desc": "Die erste Fassung für Steam.", "order": 0, "archivedAt": null}]
	data["stages"] = [
		{"id": "st1", "version": 1, "releaseId": "rel", "name": "Steam", "order": 0, "doneAt": null},
		{"id": "st2", "version": 1, "releaseId": "rel", "name": "itch.io", "order": 1, "doneAt": null},
	]
	return data


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	_store = Store.new()
	_store.data = _data()
	_store.ws = Workspace.new(_store.data)
	_store.project_id = Demo.PROJECT
	_store.state = "ready"
	root.add_child(_store)


func _shoot(window: Window, name: String) -> void:
	window.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT + name + ".png"))


func _open(window: Window, id: String) -> void:
	if _window != null:
		_window.queue_free()
	_window = window
	_window.set("store", _store)
	_window.set("task_id", id)
	root.add_child(_window)
	_window.popup_centered()


func _process(delta: float) -> bool:
	_elapsed += delta
	if _step > 0 and _elapsed < 2.5:
		return false
	_elapsed = 0.0
	match _step:
		0:
			_table = TableWindow.new()
			_table.store = _store
			root.add_child(_table)
			_table.popup_centered(Vector2i(1440, 900))
		1:
			_shoot(_table, "feld")
			_table.lage = true
		2:
			_shoot(_table, "planen")
			_table.lage = false
			_table._set_map(true)
		3:
			_shoot(_table, "feldzug")
			_table.hide()
			var task := TaskWindow.new()
			task.size = Vector2i(620, 470)
			_open(task, "a")
		4:
			_shoot(_window, "aufgabe")
			_open(MilestoneWindow.new(), "ms")
		5:
			_shoot(_window, "milestone")
			_open(ReleaseWindow.new(), "rel")
		6:
			_shoot(_window, "release")
			quit()
	_step += 1
	return false
