extends "suite.gd"
## Der Änderungs-Strom: Zerlegen der Ereignisse und Anwenden auf den Stand.

const Events := preload("res://addons/tasker/core/events.gd")
const Store := preload("res://addons/tasker/core/store.gd")
const Client := preload("res://addons/tasker/core/client.gd")


func _store() -> Store:
	var store := Store.new()
	store.client = Client.new()
	store.client.client_id = "ich"
	store.data = Builder.new().project("p").task("a", "p").task("b", "p").data
	store.ws = Workspace.new(store.data)
	store.state = "ready"
	return store


func _free(store: Store) -> void:
	store.client.free()
	store.free()


func test_ereignisse_kommen_auch_ueber_mehrere_stuecke_verteilt_an() -> void:
	var events := Events.new()
	eq(events.feed("event: ready\ndata: 1\nretry: 3000\n\n"), [], "Lebenszeichen")
	eq(events.feed("id: 7\ndata: {\"id\":7,\"origin\":null,\"ev"), [], "unvollständig")
	var out := events.feed("ent\":{\"type\":\"reload\",\"reason\":\"Verschoben\"}}\n\nevent: ping\ndata: \n\n")
	eq(out.size(), 1)
	eq(out[0]["event"]["type"], "reload")
	eq(out[0]["id"], 7.0)
	events.free()


func test_zeilenenden_mit_wagenruecklauf_und_mehrere_ereignisse_in_einem_stueck() -> void:
	var events := Events.new()
	var out := events.feed("data: {\"id\":1,\"origin\":\"x\",\"event\":{\"type\":\"delete\",\"kind\":\"task\",\"id\":\"a\"}}\r\n\r\ndata: {\"id\":2,\"origin\":null,\"event\":{\"type\":\"reload\",\"reason\":\"r\"}}\r\n\r\n")
	eq(out.size(), 2)
	eq(out[0]["origin"], "x")
	eq(out[1]["id"], 2.0)
	events.free()


func test_unlesbares_wird_uebergangen() -> void:
	var events := Events.new()
	eq(events.feed("data: kein json\n\ndata: {\"id\":3}\n\n"), [])
	events.free()


func test_server_adresse_wird_zerlegt() -> void:
	eq(Events.parse_url("https://tasker.example.com"), {"host": "tasker.example.com", "port": 443, "tls": true, "prefix": ""})
	eq(Events.parse_url("http://localhost:8787/"), {"host": "localhost", "port": 8787, "tls": false, "prefix": ""})
	eq(Events.parse_url("https://example.com/tasker/"), {"host": "example.com", "port": 443, "tls": true, "prefix": "/tasker"})
	eq(Events.parse_url("tasker.example.com"), {})


func test_eine_aenderung_von_woanders_wird_eingesetzt() -> void:
	var store := _store()
	var changed: Dictionary = store.data["tasks"][0].duplicate()
	changed["title"] = "neu"
	changed["version"] = 2
	store.apply_event({"id": 1, "origin": "anderer-tab", "event": {"type": "upsert", "kind": "task", "object": changed}})
	eq(store.ws.task("a")["title"], "neu")
	eq(store.ws.tasks.size(), 2)
	_free(store)


func test_der_eigene_hall_wird_uebergangen() -> void:
	var store := _store()
	var changed: Dictionary = store.data["tasks"][0].duplicate()
	changed["title"] = "Hall"
	store.apply_event({"id": 1, "origin": "ich", "event": {"type": "upsert", "kind": "task", "object": changed}})
	eq(store.ws.task("a")["title"], "a")
	_free(store)


func test_geloeschtes_verschwindet_und_das_tempo_folgt_den_einstellungen() -> void:
	var store := _store()
	store.apply_event({"id": 1, "origin": null, "event": {"type": "delete", "kind": "task", "id": "b"}})
	eq(store.ws.task("b"), null)
	store.apply_event({"id": 2, "origin": null, "event": {"type": "settings", "settings": {"velocity": 5, "theme": "dark"}}})
	eq(store.velocity, 5)
	_free(store)
