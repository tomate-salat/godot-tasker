extends "suite.gd"
## Der MCP-Server, so weit er ohne Netz und Editor geht: `rules/mcp.gd`.

const Mcp := preload("res://addons/tasker/rules/mcp.gd")

const TOOLS := [{"name": "echo", "description": "", "inputSchema": {"type": "object"}}]


func _run(name: String, arguments: Dictionary) -> Dictionary:
	return {"text": "%s:%s" % [name, arguments.get("say", "")], "failed": arguments.has("bad")}


func _ask(message: Variant) -> Variant:
	var text := Mcp.answer(JSON.stringify(message), TOOLS, _run, "1.2.3")
	return null if text == "" else JSON.parse_string(text)


func _post(body: String, extra := "") -> PackedByteArray:
	return ("POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\n%sContent-Length: %d\r\n\r\n%s" % [extra, body.to_utf8_buffer().size(), body]).to_utf8_buffer()


func test_eine_anfrage_wird_erst_gelesen_wenn_sie_ganz_da_ist() -> void:
	var all := _post("{\"a\":\"ä\"}")
	eq(Mcp.parse_request(all.slice(0, 20))["state"], Mcp.MORE)
	eq(Mcp.parse_request(all.slice(0, all.size() - 1))["state"], Mcp.MORE)
	var got := Mcp.parse_request(all)
	eq(got["state"], Mcp.DONE)
	eq(got["method"], "POST")
	eq(got["path"], "/mcp")
	# Die Länge zählt Bytes: der Umlaut ist zwei.
	eq(got["body"], "{\"a\":\"ä\"}")
	eq(got["headers"]["host"], "127.0.0.1")


func test_kaputtes_und_zu_grosses_wird_abgewiesen() -> void:
	eq(Mcp.parse_request("quatsch\r\n\r\n".to_utf8_buffer())["state"], Mcp.BAD)
	eq(Mcp.parse_request("POST /mcp HTTP/1.1\r\nContent-Length: -4\r\n\r\n".to_utf8_buffer())["state"], Mcp.BAD)
	eq(Mcp.parse_request("POST /mcp HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".to_utf8_buffer())["state"], Mcp.BAD)
	eq(Mcp.parse_request("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n".to_utf8_buffer())["state"], Mcp.BAD)


func test_ohne_kennwort_oder_von_fremder_seite_geht_nichts() -> void:
	eq(Mcp.refusal({"authorization": "Bearer geheim"}, "geheim"), 0)
	eq(Mcp.refusal({}, "geheim"), 401)
	eq(Mcp.refusal({"authorization": "Bearer falsch"}, "geheim"), 401)
	eq(Mcp.refusal({"authorization": "Bearer "}, ""), 401)
	eq(Mcp.refusal({"authorization": "Bearer geheim", "origin": "https://boese.example"}, "geheim"), 403)
	eq(Mcp.refusal({"authorization": "Bearer geheim", "origin": "http://localhost:3000"}, "geheim"), 0)
	eq(Mcp.refusal({"authorization": "Bearer geheim", "origin": "http://localhost.boese.example"}, "geheim"), 403)


func test_initialize_nennt_werkzeuge_als_faehigkeit_und_behaelt_die_id() -> void:
	var got: Dictionary = _ask({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26"}})
	eq(got["result"]["protocolVersion"], "2025-03-26")
	ok(got["result"]["capabilities"].has("tools"))
	eq(got["result"]["serverInfo"]["version"], "1.2.3")
	# Aus der 1 der Anfrage ist keine 1.0 geworden.
	ok(Mcp.answer("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}", TOOLS, _run).contains("\"id\":1,"))
	eq(_ask({"jsonrpc": "2.0", "id": 2, "method": "initialize", "params": {"protocolVersion": "1999-01-01"}})["result"]["protocolVersion"], Mcp.LATEST)


func test_mitteilungen_bekommen_keine_antwort() -> void:
	eq(_ask({"jsonrpc": "2.0", "method": "notifications/initialized"}), null)
	eq(_ask({"jsonrpc": "2.0", "id": 3, "result": {}}), null)


func test_werkzeuge_auflisten_und_aufrufen() -> void:
	eq(_ask({"jsonrpc": "2.0", "id": "a", "method": "tools/list"})["result"]["tools"][0]["name"], "echo")
	var got: Dictionary = _ask({"jsonrpc": "2.0", "id": "b", "method": "tools/call", "params": {"name": "echo", "arguments": {"say": "hallo"}}})
	eq(got["result"]["content"][0]["text"], "echo:hallo")
	eq(got["result"]["isError"], false)
	eq(_ask({"jsonrpc": "2.0", "id": "c", "method": "tools/call", "params": {"name": "echo", "arguments": {"bad": 1}}})["result"]["isError"], true)


func test_unbekanntes_und_kaputtes_gibt_einen_fehler() -> void:
	eq(_ask({"jsonrpc": "2.0", "id": 5, "method": "gibt/es/nicht"})["error"]["code"], float(Mcp.METHOD_NOT_FOUND))
	eq(_ask({"jsonrpc": "2.0", "id": 6, "method": "tools/call", "params": {"name": "fremd"}})["error"]["code"], float(Mcp.INVALID_PARAMS))
	eq(JSON.parse_string(Mcp.answer("{kaputt", TOOLS, _run))["error"]["code"], float(Mcp.PARSE_ERROR))


func test_die_antwort_traegt_laenge_und_schliesst() -> void:
	var text := Mcp.response(200, "{\"ä\":1}").get_string_from_utf8()
	ok(text.begins_with("HTTP/1.1 200 OK\r\n"))
	ok(text.contains("Content-Length: 8\r\n"))
	ok(text.contains("Connection: close\r\n"))
	ok(text.ends_with("\r\n\r\n{\"ä\":1}"))
