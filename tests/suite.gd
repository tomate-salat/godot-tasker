extends RefCounted
## Basis der Testdateien: Methoden, die mit `test_` beginnen, sind Tests.

const Builder := preload("builder.gd")
const Workspace := preload("res://addons/tasker/rules/workspace.gd")

var errors: Array = []


func eq(actual: Variant, expected: Variant, what := "") -> void:
	if typeof(actual) != typeof(expected) or actual != expected:
		errors.append("%serwartet %s, bekommen %s" % [what + ": " if what else "", var_to_str(expected), var_to_str(actual)])


func ok(value: Variant, what := "") -> void:
	if not value:
		errors.append("%ssollte zutreffen" % [what + ": " if what else ""])


func ids(list: Array) -> Array:
	var out := []
	for x in list:
		out.append(x["id"])
	return out
