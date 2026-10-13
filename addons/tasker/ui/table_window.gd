@tool
extends "card_window.gd"
## Der Tisch: das Fenster des Editors, in dem gespielt und geplant wird.
##
## Zwei Ansichten: das Feld – der laufende Milestone als Schlachtfeld
## (`field_view.gd`), darüber die Feldzugskarte des Releases
## (`campaign_view.gd`) – und die Planung (`plan_view.gd`). Die Kopfzeile
## zeigt, was gerade zu sehen ist, dazu Wochenziel und Serie.
##
## Den Spieltisch mit Hand und Nachziehstapel, den es hier früher gab, hat das
## Feld abgelöst (Nutzer, 2026-10-12).

## Die Aufgabe soll in ihrem Fenster gezeigt werden.
signal task_requested(task_id: String)

const Demo := preload("demo.gd")
const Model := preload("../rules/model.gd")
const ParentStatus := preload("../rules/parent_status.gd")
const Tisch := preload("../rules/tisch.gd")
const Progress := preload("../rules/progress.gd")
const Workspace := preload("../rules/workspace.gd")
const Store := preload("../core/store.gd")
const Images := preload("../core/images.gd")
const Sounds := preload("sounds.gd")
const Shelf := preload("shelf.gd")
const PlanMap := preload("plan_map.gd")
const Planning := preload("../rules/planning.gd")
const FieldView := preload("field_view.gd")
const CampaignView := preload("campaign_view.gd")
const Release := preload("../rules/release.gd")
const DepGraphView := preload("dep_graph_view.gd")

const MARGIN := 28.0
## So breit ist der Umschalter „Feld / Planen“ links oben.
const MODES_WIDTH := 176.0
## So hoch ist der Streifen am oberen Rand, an dem man das Fenster verschiebt.
const HEADER_HEIGHT := 58.0

## Der Datenbestand und der Bild-Zwischenspeicher – ohne sie oder ohne
## Verbindung liegen ausgedachte Karten auf dem Tisch.
var store: Store
var images: Images
## Ob der Tisch Töne spielt (Addon-Einstellung).
var sound_enabled := true: set = set_sound_enabled

var _demo_data := {}
var _ws: Workspace
var _project := ""
## Der laufende Milestone, in dem gespielt wird – bei mehreren der gewählte.
var _milestone: Variant
## Das Release, an dem gerade gearbeitet wird, oder null. Gibt es eines, liegt
## über dem Feld die Feldzugskarte: `_map` sagt, ob sie gerade zu sehen ist.
var _release: Variant
var _map := false
var _map_decided := false
## Der Milestone, dessen Feld auf der Karte gewählt wurde, und der, der im Feld liegt.
var _chosen := ""
var _shown: Variant
var _campaign: CampaignView
var _release_chip: Button
var _bar: HBoxContainer

## Die Ablage ist offen: sie zeigt je Woche, was erledigt wurde.
var _shelf := false
var _shelf_data := {"weeks": [], "streak": 0, "this_week": 0}
## Der Stand beim letzten Abgleich – daran erkennt der Tisch, was sich getan hat.
var _seen := {}

var _week: Button
var _week_bar: ProgressBar
var _streak: Label
var _shelf_panel: Shelf
var _dim: ColorRect
var _sounds: Sounds
## Hier steigen Worte und Funken auf, über Feld und Karte.
var _effects: Control
var _title: Button
var _progress: ProgressBar
var _count: Label
## Der Graph einer Karte.
var _graph: DepGraphView
var _mode_field: Button
var _mode_plan: Button
## „Planen“ ist der Lageplan. Den Ordner mit Decks und Vorrat, den es hier
## früher gab, hat er abgelöst (Nutzer, 2026-10-12).
var lage := false: set = set_lage
var _plan_map: PlanMap
var _field: FieldView


func _init() -> void:
	super()
	# Der Tisch rechnet mit der ganzen Fensterfläche und bemalt sie bis an die Kante.
	shadow = false
	rim_on_top = true
	fill = Palette.FELT
	title = "Tasker – Tisch"
	# Gezeichnetes – die Figuren des Feldes – bekommt glatte Kanten, ohne weich zu werden.
	msaa_2d = Viewport.MSAA_4X
	size = Vector2i(1440, 900)
	min_size = Vector2i(1100, 800)
	close_requested.connect(shut)
	size_changed.connect(_place)
	_build()


func _ready() -> void:
	if store != null:
		store.changed.connect(_sync)
		store.state_changed.connect(_sync)
	_sync()


func set_sound_enabled(value: bool) -> void:
	sound_enabled = value
	if _sounds != null:
		_sounds.enabled = value


func _build() -> void:
	_sounds = Sounds.new()
	_sounds.enabled = sound_enabled
	add_child(_sounds)

	var bar := HBoxContainer.new()
	_bar = bar
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = MARGIN + MODES_WIDTH
	bar.offset_right = -MARGIN - 92
	bar.offset_top = 14
	bar.add_theme_constant_override("separation", 14)
	add_child(bar)

	# Das Release: ein Klick führt auf die Feldzugskarte.
	_release_chip = Button.new()
	_release_chip.focus_mode = Control.FOCUS_NONE
	_release_chip.visible = false
	_release_chip.tooltip_text = "Die Feldzugskarte: alle Milestones dieses Releases"
	_release_chip.add_theme_font_size_override("font_size", 14)
	_release_chip.add_theme_color_override("font_disabled_color", Palette.INK)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var chip := StyleBoxFlat.new()
		chip.bg_color = Color(Palette.P1, 0.26 if state == "hover" else 0.16)
		chip.border_color = Color(Palette.P1, 0.7)
		chip.set_border_width_all(1)
		chip.set_corner_radius_all(8)
		chip.content_margin_left = 10
		chip.content_margin_right = 10
		chip.content_margin_top = 3
		chip.content_margin_bottom = 3
		_release_chip.add_theme_stylebox_override(state, chip)
	_release_chip.pressed.connect(func() -> void:
		# Auf der Karte führt der Knopf weiter ins Fenster des Releases.
		if not lage and _on_map() and store != null and store.state == "ready":
			task_requested.emit(_release["id"])
			return
		lage = false
		_set_map(true))
	bar.add_child(_release_chip)
	# Der Milestone selbst: ein Klick öffnet sein Fenster.
	_title = Button.new()
	_title.flat = true
	_title.focus_mode = Control.FOCUS_NONE
	_title.pressed.connect(func() -> void:
		var head: Variant = _shown if _shown != null else _milestone
		if head != null and store != null and store.state == "ready":
			task_requested.emit(head["id"]))
	_title.add_theme_font_override("font", Palette.title_font())
	_title.add_theme_font_size_override("font_size", 18)
	bar.add_child(_title)
	_progress = ProgressBar.new()
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(220, 8)
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_progress)
	_count = Label.new()
	_count.tooltip_text = "Erledigte von allen Aufgaben"
	bar.add_child(_count)

	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(gap)
	_streak = Label.new()
	_streak.add_theme_color_override("font_color", Palette.P2)
	_streak.tooltip_text = "Wochen in Folge mit mindestens einer erledigten Karte"
	bar.add_child(_streak)
	# Das Wochenziel: ein Klick öffnet die Ablage mit dem, was je Woche erledigt wurde.
	_week = Button.new()
	_week.flat = true
	_week.focus_mode = Control.FOCUS_NONE
	_week.tooltip_text = "Erledigte Karten ohne Unteraufgaben diese Woche, gegen das Tempo aus den Tasker-Einstellungen.\nEin Klick zeigt die Ablage: was in welcher Woche erledigt wurde."
	_week.pressed.connect(func() -> void: _set_shelf(not _shelf))
	bar.add_child(_week)
	_week_bar = ProgressBar.new()
	_week_bar.show_percentage = false
	_week_bar.custom_minimum_size = Vector2(120, 8)
	_week_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_child(_week_bar)

	# Das Feld füllt das Fenster; die Kopfzeile bleibt darüber.
	_field = FieldView.new()
	_field.visible = false
	_field.task_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	_field.graph_requested.connect(_open_graph)
	_field.refused.connect(_refuse)
	_field.change_requested.connect(_field_change)
	add_child(_field)
	move_child(_field, bar.get_index())
	_field.left.connect(func() -> void: _set_map(true))
	# Der Lageplan liegt an derselben Stelle.
	_plan_map = PlanMap.new()
	_plan_map.visible = false
	_plan_map.mover = _move
	_plan_map.patcher = _patch
	_plan_map.task_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	_plan_map.graph_requested.connect(_open_graph)
	_plan_map.refused.connect(_refuse)
	_plan_map.milestone_chosen.connect(func(id: String) -> void:
		_chosen = id
		_sync())
	add_child(_plan_map)
	move_child(_plan_map, bar.get_index())
	# Die Feldzugskarte liegt an derselben Stelle wie das Feld, eine Ebene höher.
	_campaign = CampaignView.new()
	_campaign.visible = false
	_campaign.milestone_chosen.connect(func(id: String) -> void:
		_chosen = id
		_set_map(false))
	_campaign.details_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	_campaign.release_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	add_child(_campaign)
	move_child(_campaign, bar.get_index())
	# Über dem Feld bleibt oben ein Streifen in voller Breite, an dem man das
	# Fenster greift – das Feld selbst nimmt sonst jeden Klick für sich.
	var header := Control.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_bottom = HEADER_HEIGHT
	header.gui_input.connect(_on_face_input)
	add_child(header)
	move_child(header, bar.get_index())

	_effects = Control.new()
	_effects.set_anchors_preset(Control.PRESET_FULL_RECT)
	_effects.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_effects)

	# Der Graph legt sich über das Feld.
	_graph = DepGraphView.new()
	_graph.z_index = 700
	_graph.task_requested.connect(func(id: String) -> void:
		if store != null and store.state == "ready":
			task_requested.emit(id))
	add_child(_graph)

	var modes := HBoxContainer.new()
	modes.position = Vector2(MARGIN, 14)
	modes.add_theme_constant_override("separation", 0)
	add_child(modes)
	_mode_field = _mode_button("Feld", "Der laufende Milestone als Schlachtfeld, darüber die Feldzugskarte des Releases")
	_mode_field.pressed.connect(func() -> void: lage = false)
	modes.add_child(_mode_field)
	_mode_plan = _mode_button("Planen", "Der Lageplan: die Stadt des Milestones, links die Reserve – Karten hineinziehen teilt sie zu")
	_mode_plan.pressed.connect(func() -> void: lage = true)
	modes.add_child(_mode_plan)
	_round_modes([_mode_field, _mode_plan])

	# Die Ablage legt sich über alles, mit einem Schleier dahinter.
	_dim = ColorRect.new()
	_dim.color = Color(0.03, 0.07, 0.06, 0.86)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.z_index = 750
	_dim.visible = false
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_set_shelf(false))
	add_child(_dim)
	_shelf_panel = Shelf.new()
	_shelf_panel.z_index = 760
	_shelf_panel.visible = false
	_shelf_panel.close_requested.connect(func() -> void: _set_shelf(false))
	_shelf_panel.task_requested.connect(func(id: String) -> void: task_requested.emit(id))
	add_child(_shelf_panel)

	# Was sonst die Titelleiste trägt, liegt oben rechts über allem.
	var frame_buttons := HBoxContainer.new()
	frame_buttons.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	frame_buttons.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	frame_buttons.offset_top = 10
	frame_buttons.offset_right = -14
	frame_buttons.add_theme_constant_override("separation", 0)
	frame_buttons.z_index = 800
	frame_buttons.add_child(pin_button())
	frame_buttons.add_child(max_button())
	frame_buttons.add_child(close_button())
	add_child(frame_buttons)
	# Auch an Fortschritt und Beschriftung greift man das Fenster; nur Knöpfe bleiben Knöpfe.
	for part in [bar, gap, _progress, _count, _streak, _week_bar]:
		part.mouse_filter = Control.MOUSE_FILTER_PASS
	bar.gui_input.connect(_on_face_input)
	_show_mode()
	_place()


func _mode_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.x = MODES_WIDTH / 2.0 - 8.0
	# Eigenes Aussehen statt des Editor-Themas: dunkel und flach, der gewählte
	# Reiter fast schwarz. Die Ecken rundet `_round_modes`, wenn alle da sind.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color("0b1411") if state.contains("pressed") else Color("22302b") if state == "hover" else Color("18231f")
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 5
		box.content_margin_bottom = 6
		b.add_theme_stylebox_override(state, box)
	b.add_theme_color_override("font_color", Color(Palette.INK, 0.85))
	b.add_theme_color_override("font_hover_color", Palette.INK)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	return b


## Rundet die äußeren Ecken der Reiter: zusammen sind sie ein Stück.
func _round_modes(buttons: Array) -> void:
	for i in buttons.size():
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var box: StyleBoxFlat = buttons[i].get_theme_stylebox(state)
			if i == 0:
				box.corner_radius_top_left = 7
				box.corner_radius_bottom_left = 7
			if i == buttons.size() - 1:
				box.corner_radius_top_right = 7
				box.corner_radius_bottom_right = 7


## Wechselt auf den Lageplan und zurück.
func set_lage(value: bool) -> void:
	lage = value
	if _plan_map == null:
		return
	_shelf = false
	_graph.close()
	_show_mode()
	_sync()


## Womit auf dem Feld gekämpft wird: Soldaten oder Käfer.
func set_field_style(value: String) -> void:
	_field.set_style(value)


## Ein Zug auf dem Feld: tappen, zurücknehmen, erledigen.
func _field_change(id: String, changes: Dictionary) -> void:
	# Im Feld eines Milestones, der nicht läuft, wird nur geschaut.
	if _shown != null and _shown.get("status") != "progress":
		_refuse("„%s“ ist nicht aktiv – gespielt wird nur in einem laufenden Milestone" % _shown.get("title", ""))
		return
	_sounds.play("play" if changes.get("status") == "progress" else "draw" if changes.get("status") == "open" else "done")
	await _change(id, changes)
	_sync()


## Wechselt zwischen der Feldzugskarte und dem Feld eines Milestones.
func _set_map(value: bool) -> void:
	if value and _release == null:
		return
	_map = value
	_map_decided = true
	_shelf = false
	_graph.close()
	_show_mode()
	_sync()


func _on_map() -> bool:
	return _map and _release != null


func _show_mode() -> void:
	_plan_map.visible = lage
	# Im Lageplan beginnt die Kopfzeile erst über der Karte, nicht über der Reserve.
	_bar.offset_left = maxf(MARGIN + MODES_WIDTH, PlanMap.RESERVE_WIDTH + 18.0) if lage else MARGIN + MODES_WIDTH
	_field.visible = not lage and not _on_map()
	_campaign.visible = not lage and _on_map()
	_mode_field.set_pressed_no_signal(not lage)
	_mode_plan.set_pressed_no_signal(lage)


## Die Ablage füllt das Fenster bis auf einen Rand.
func _place() -> void:
	if _shelf_panel == null:
		return
	_shelf_panel.position = Vector2(20, 20)
	_shelf_panel.size = Vector2(size) - Vector2(40, 40)


# ----------------------------------------------------------- Abgleich

## Bringt den Tisch auf den Stand der Daten.
func _sync() -> void:
	if not is_inside_tree():
		return
	var demo := store == null or store.state != "ready"
	if demo:
		if _demo_data.is_empty():
			_demo_data = Demo.data()
			_ws = Workspace.new(_demo_data)
		_project = Demo.PROJECT
	else:
		_ws = store.ws
		_project = store.project_id

	var active: Variant = Tisch.active_milestone(_ws, _project)
	_release = Release.active(_ws, _project)
	if _release != null and not _map_decided:
		# Mit genau einem laufenden Milestone geht es gleich auf sein Feld, sonst erst auf die Karte.
		_map_decided = true
		_map = _ws.release_milestones(_release["id"]).filter(func(m: Dictionary) -> bool: return m.get("status") == "progress").size() != 1
	var chosen: Variant = _ws.milestone(_chosen) if _chosen != "" else null
	if chosen != null and (Model.is_archived(chosen) or chosen.get("projectId") != _project):
		chosen = null
	# Im Feld liegt, was auf der Karte gewählt wurde – auch ein geplanter oder
	# fertiger Milestone. Gespielt wird nur in einem laufenden.
	_shown = chosen if chosen != null else active
	if _shown == null and _release != null:
		_shown = _ws.release_milestones(_release["id"])[0]
	_milestone = chosen if chosen != null and chosen.get("status") == "progress" else active
	# Zum Planen braucht es keinen laufenden Milestone: dann eben den ersten im Plan.
	if _shown == null and lage:
		var decks := Planning.decks(_ws, _project)
		if decks.size() > 0:
			_shown = decks[0]
	_show_mode()
	if lage:
		_plan_map.show_plan(_ws, _project, _shown, images if not demo else null)
	else:
		if _on_map():
			_campaign.show_campaign(_ws, _release)
		else:
			_field.show_field(_ws, _shown, images if not demo else null)

	_show_head(demo)
	if _milestone == null:
		_week.text = ""
		_streak.text = ""
		_week_bar.visible = false
		_shelf_data = {"weeks": [], "streak": 0, "this_week": 0}
		_seen = {}
		_shelf = false
	else:
		# Wochenziel und Serie: das Ziel ist das Tempo aus den Tasker-Einstellungen.
		_shelf_data = Tisch.done_shelf(_ws, _milestone, Time.get_unix_time_from_system(), Time.get_time_zone_from_system()["bias"])
		var goal := _goal()
		var reached: bool = _shelf_data["this_week"] >= goal
		_week.text = "%sWoche %d/%d" % ["★ " if reached else "", _shelf_data["this_week"], goal]
		_week.add_theme_color_override("font_color", Palette.OK if reached else Palette.INK)
		_week_bar.visible = true
		_week_bar.max_value = goal
		_week_bar.value = mini(_shelf_data["this_week"], goal)
		_streak.text = "Serie: %d Wochen" % _shelf_data["streak"] if _shelf_data["streak"] >= 2 else ""
		if _shelf_data["weeks"].is_empty():
			_shelf = false
		_notice_changes()
		if _shelf:
			_shelf_panel.show_shelf(_ws, _shelf_data, goal, images if not demo else null, Time.get_time_zone_from_system()["bias"])
	# Im Lageplan wird geplant, nicht gezählt: Fortschritt, Serie und Wochenziel
	# bleiben dem Feld (Nutzer, 2026-10-12).
	for part in [_count, _streak, _week]:
		part.visible = not lage
	if lage:
		_progress.visible = false
		_week_bar.visible = false
	_dim.visible = _shelf
	_shelf_panel.visible = _shelf


## Die Kopfzeile: das Release als Knopf zur Karte, daneben der Milestone,
## dessen Feld zu sehen ist – oder auf der Karte der Stand des Releases.
func _show_head(demo: bool) -> void:
	# Im Feld steht das laufende Release da und führt auf die Feldzugskarte. Im
	# Lageplan steht das Release des Milestones, der gerade geplant wird – zur
	# Karte führt es nur, wenn es das laufende ist.
	var named: Variant = _release
	if lage:
		named = _ws.release_of(_shown) if _shown != null else null
	_release_chip.visible = named != null
	if named != null:
		_release_chip.text = Release.label(named)
		_release_chip.disabled = _release == null or named["id"] != _release["id"]
		_release_chip.tooltip_text = "Das Release dieses Milestones" if _release_chip.disabled else "Das Release in seinem Fenster zeigen" if not lage and _on_map() else "Die Feldzugskarte: alle Milestones dieses Releases"
	if not lage and _on_map():
		_title.visible = false
		var boss: Dictionary = _campaign._campaign.get("boss", {"total": 0, "done": 0})
		_progress.visible = true
		_progress.value = 100.0 * boss["done"] / maxf(boss["total"], 1.0)
		_count.text = "%d/%d" % [boss["done"], boss["total"]]
		return
	_title.visible = true
	var head: Variant = _shown if _shown != null else _milestone
	if head == null:
		_title.text = "Kein aktiver Milestone"
		_progress.visible = false
		_count.text = ""
		return
	var stats := Progress.milestone_stats(_ws, head)
	_title.text = "◆ %s%s" % [head["title"], "   (Beispieldaten, keine Verbindung)" if demo else ""]
	_progress.visible = true
	_progress.value = Progress.milestone_progress_pct(_ws, head)
	_count.text = "%d/%d" % [stats["done"], stats["total"]]


func _goal() -> int:
	return maxi(1, store.velocity if store != null and store.state == "ready" else Store.DEFAULT_VELOCITY)


## Vergleicht mit dem letzten Abgleich und feiert, was sich getan hat – egal
## ob am Tisch, im Dock oder in der Web-App.
func _notice_changes() -> void:
	var layout := Tisch.layout(_ws, _milestone)
	var locked := {}
	for t in layout["locked"]:
		locked[t["id"]] = true
	var now := {
		"milestone": _milestone["id"],
		"locked": locked,
		"pile": layout["pile"].size(),
		"week": _shelf_data["this_week"],
		"complete": layout["pile"].size() > 0 and layout["open"].is_empty() and layout["play"].is_empty() and layout["locked"].is_empty(),
	}
	var before := _seen
	_seen = now
	if before.get("milestone") != now["milestone"]:
		return

	for id in before["locked"]:
		var t = _ws.task(id)
		if not locked.has(id) and t != null and not Model.is_done(t) and _ws.is_active(t):
			_say("Frei geworden: %s" % (t["title"] if t.get("title") else "Ohne Titel"), Palette.OK)
			_sounds.play("unlock")

	var top := Vector2(size.x / 2.0, HEADER_HEIGHT + 90.0)
	var gained: int = now["pile"] - before["pile"]
	if gained > 0:
		_float_text(top, "+%d" % gained, Palette.OK)
		var goal := _goal()
		if now["week"] >= goal and before["week"] < goal:
			_float_text(top + Vector2(0, 40), "★ Wochenziel", Palette.P2)
			_burst(top, Palette.P2)
			_sounds.play("goal")
		else:
			_sounds.play("done")
	if now["complete"] and not before["complete"]:
		_float_text(Vector2(size.x / 2.0, size.y * 0.36), "◆ Milestone geschafft", Palette.P2, 34)
		_burst(Vector2(size.x * 0.35, size.y * 0.4), Palette.P2)
		_burst(Vector2(size.x * 0.65, size.y * 0.4), Palette.OK)
		_sounds.play("complete")


func _open_graph(id: String) -> void:
	var item = _ws.task(id)
	if item != null:
		_graph.open(_ws, item, _project)


## Öffnet oder schließt die Ablage.
func _set_shelf(on: bool) -> void:
	_shelf = on and _shelf_data["weeks"].size() > 0
	if on and not _shelf:
		_say("Noch nichts erledigt – die Ablage ist leer")
	_sync()


# ------------------------------------------------------------- Ändern

## Schickt eine Änderung an Tasker. Sie gilt sofort (`Store.patch`).
func _change(id: String, changes: Dictionary) -> bool:
	var ok := true
	if store == null or store.state != "ready":
		_change_demo(id, changes)
	else:
		var res := await store.patch("task", id, changes)
		ok = res["ok"]
		if not ok:
			_say(str(res["error"]))
	return ok


## Ohne Verbindung ändert sich nur das Beispiel.
func _change_demo(id: String, changes: Dictionary) -> void:
	var by_id := {}
	for t in _demo_data["tasks"]:
		by_id[t["id"]] = t
	var changed = by_id.get(id)
	if changed == null:
		return
	changed.merge(changes, true)
	if changes.has("status"):
		changed["doneAt"] = Time.get_datetime_string_from_system(true) + ".000Z" if changes["status"] == "done" else null
		# Wie am Server: der Status der Eltern-Aufgaben zieht nach, Stufe um Stufe.
		var child: Dictionary = changed
		while child.get("parentId") and by_id.has(child["parentId"]):
			var parent: Dictionary = by_id[child["parentId"]]
			var kids := []
			for t in _demo_data["tasks"]:
				if t.get("parentId") == parent["id"] and not t.get("archivedAt"):
					kids.append(t.get("status"))
			var next = ParentStatus.after(parent.get("status"), child.get("status"), kids)
			if next == null:
				break
			parent["status"] = next
			if next != "done":
				parent["doneAt"] = null
			child = parent
	_ws = Workspace.new(_demo_data)


## Ein abgelehnter Zug: der Tisch sagt, warum.
func _refuse(text: String) -> void:
	_sounds.play("refuse")
	_say(text)


func _say(text: String, color := Palette.P2) -> void:
	if lage:
		_plan_map.say(text, color)
	else:
		_field.say(text, color)


## Eine Änderung aus dem Lageplan an einer Aufgabe – etwa worauf sie wartet.
func _patch(id: String, changes: Dictionary) -> Dictionary:
	_sounds.play("play")
	var ok := await _change(id, changes)
	_sync()
	return {"ok": ok, "error": ""}


## Ein Zug im Lageplan: eine Aufgabe einem Milestone zuteilen oder zurück in
## die Reserve. `body` bekommt Taskers `/api/move`, `local` gilt sofort.
func _move(id: String, body: Dictionary, local: Dictionary) -> Dictionary:
	_sounds.play("play")
	if store != null and store.state == "ready":
		return await store.move(id, body, local)
	# Ohne Verbindung ändert sich nur das Beispiel.
	for t in _demo_data["tasks"]:
		if local.has(t["id"]):
			t.merge(local[t["id"]], true)
	_ws = Workspace.new(_demo_data)
	_sync()
	return {"ok": true, "error": ""}


# ------------------------------------------------------------ Effekte

## Ein Wort, das kurz aufsteigt und verblasst – „+1“, wenn etwas erledigt ist.
func _float_text(at: Vector2, text: String, color: Color, font_size := 22) -> void:
	var l := Label.new()
	l.text = text
	l.z_index = 700
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", Palette.title_font())
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_effects.add_child(l)
	l.position = at - Vector2(l.get_minimum_size().x / 2.0, 0)
	var tween := l.create_tween()
	tween.tween_property(l, "position:y", l.position.y - 46.0, 1.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.8)
	tween.tween_callback(l.queue_free)


## Funken, die von einer Stelle aus aufstieben.
func _burst(at: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.z_index = 650
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 46
	p.lifetime = 1.0
	p.direction = Vector2.UP
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 340.0
	p.gravity = Vector2(0, 520)
	p.scale_amount_min = 2.5
	p.scale_amount_max = 5.5
	var fade := Gradient.new()
	fade.colors = PackedColorArray([color, Color(color, 0.0)])
	p.color_ramp = fade
	_effects.add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


## Der Tisch wird nicht verworfen, nur weggelegt: beim nächsten Öffnen liegt
## alles, wo es lag.
func _gone() -> void:
	hide()
