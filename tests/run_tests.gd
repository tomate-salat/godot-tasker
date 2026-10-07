extends SceneTree
## Lässt alle Tests laufen:
##   godot --headless --path . -s tests/run_tests.gd

const SUITES := ["res://tests/test_tisch.gd", "res://tests/test_rules.gd", "res://tests/test_markdown.gd", "res://tests/test_hand.gd", "res://tests/test_burnup.gd", "res://tests/test_events.gd", "res://tests/test_refs.gd"]


func _init() -> void:
	var count := 0
	var failed := 0
	for path in SUITES:
		var script: GDScript = load(path)
		if script == null or not script.can_instantiate():
			print("FEHLER  %s lässt sich nicht laden" % path)
			failed += 1
			continue
		var suite = script.new()
		for m in suite.get_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_"):
				continue
			count += 1
			suite.errors = []
			suite.call(name)
			if suite.errors.size() > 0:
				failed += 1
				print("FEHLER  %s" % name)
				for e in suite.errors:
					print("        %s" % e)
	print("%d Tests, %d fehlgeschlagen" % [count, failed])
	quit(1 if failed > 0 else 0)
