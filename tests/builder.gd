extends RefCounted
## Kleiner Baukasten, damit die Tests lesbar bleiben – wie `Builder` in
## Taskers `shared/testing.ts`.

const Workspace := preload("res://addons/tasker/rules/workspace.gd")
const Builder := preload("builder.gd")

var data := {
	"projects": [],
	"categories": [],
	"marks": [],
	"groups": [],
	"milestones": [],
	"tasks": [],
}
var _n := 0
var _ref := 1


func project(id: String, o := {}) -> Builder:
	var p := {"id": id, "version": 1, "name": id, "color": "#2A6B5A", "order": data["projects"].size(), "coverImageId": null}
	p.merge(o, true)
	data["projects"].append(p)
	return self


func category(id: String, project_id: String, o := {}) -> Builder:
	var c := {"id": id, "version": 1, "projectId": project_id, "name": id, "order": data["categories"].size(), "coverImageId": null}
	c.merge(o, true)
	data["categories"].append(c)
	return self


func mark(id: String, project_id: String, o := {}) -> Builder:
	var k := {"id": id, "version": 1, "projectId": project_id, "emoji": "*", "name": id, "order": data["marks"].size(), "coverImageId": null}
	k.merge(o, true)
	data["marks"].append(k)
	return self


func milestone(id: String, project_id: String, o := {}) -> Builder:
	var m := {
		"id": id,
		"ref": _ref,
		"version": 1,
		"projectId": project_id,
		"title": id,
		"desc": "",
		"planned": false,
		"status": "open",
		"order": data["milestones"].size(),
		"qorder": data["milestones"].size(),
		"startDate": null,
		"endDate": null,
		"endAuto": false,
		"archivedAt": null,
		"deps": [],
	}
	_ref += 1
	m.merge(o, true)
	data["milestones"].append(m)
	return self


func task(id: String, project_id: String, o := {}) -> Builder:
	var t := {
		"id": id,
		"ref": _ref,
		"version": 1,
		"projectId": project_id,
		"parentId": null,
		"milestoneId": null,
		"groupId": null,
		"doc": false,
		"title": id,
		"desc": "",
		"prio": 0,
		"status": "open",
		"doneAt": null,
		"order": _n,
		"categoryId": null,
		"markId": null,
		"ready": false,
		"coverImageId": null,
		"playOrder": 0,
		"archivedAt": null,
		"tags": [],
		"deps": [],
	}
	_ref += 1
	_n += 1
	t.merge(o, true)
	data["tasks"].append(t)
	return self


func build() -> Workspace:
	return Workspace.new(data)
