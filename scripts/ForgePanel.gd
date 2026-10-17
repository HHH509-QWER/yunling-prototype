extends Control
## 合炼面板（M13）。设计圣经 §3.3：**火候指针在绿区时点击，失误则失败**。
##
## ⭐ 一个键（E）推进到底，流程只有四步：
##    选配方 →（可能出「填料 / 减料」事件）→ 火候指针 → 结果
## ⭐ 规则全在 Smith.gd —— 这里只负责「画什么、什么时候让玩家按」。
## ⚠️ 打开时游戏暂停，所以必须 PROCESS_MODE_WHEN_PAUSED。

signal closed

const SmithScript := preload("res://scripts/Smith.gd")

var game = null
var step := 0              # 0 选配方 / 1 事件 / 2 火候 / 3 结果
var recipe_index := 0
var pointer := 0.0         # 火候指针在 0..1 之间来回
var running := false

var _t := 0.0
var _has_event := false
var _event_choice := 0     # 0 不管 / 1 加料 / 2 减料
var _msg := ""
## ⭐ 打开面板的**那一帧**不接受操作。
##    实测：按 E 开交易面板，会顺手把第一件商品买下来 ——
##    因为「开面板」和「面板处理按键」看到的是**同一个事件**。
var _opened_frame := -1
var _report: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	_font = GameData.make_font()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false


func open(g) -> void:
	game = g
	step = 0
	recipe_index = 0
	running = false
	_msg = ""
	_report = {}
	visible = true
	_opened_frame = Engine.get_process_frames()
	queue_redraw()


func close() -> void:
	visible = false
	running = false
	closed.emit()


## 全部配方（**含做不了的** —— 做不了的要显示「还缺什么」，那才是引导）。
func recipes() -> Array:
	return GameData.RECIPES


func current() -> Dictionary:
	var rs := recipes()
	if recipe_index < 0 or recipe_index >= rs.size():
		return {}
	return rs[recipe_index]


func can_do() -> bool:
	var r := current()
	return not r.is_empty() and SmithScript.can_afford(game, r)


## 开炉：先掷一次「出不出事件」，再进火候。
## force_event: -1 = 真随机（默认），0 = 强制不出，1 = 强制出（自测用来确定性驱动）。
func start(force_event := -1) -> bool:
	if not can_do():
		var miss: Array = SmithScript.missing(game, current())
		_msg = "还差：" + ", ".join(miss)
		queue_redraw()
		return false
	if force_event >= 0:
		_has_event = force_event == 1
	else:
		_has_event = randf() < float(GameData.FURNACE["event_chance"])
	_event_choice = 0
	_msg = ""
	if _has_event:
		step = 1
	else:
		_begin_pointer()
	queue_redraw()
	return true


## 事件里选「加料 / 不加」。
func choose_event(add_material: bool) -> void:
	if step != 1:
		return
	_event_choice = 1 if add_material else 2
	_begin_pointer()
	queue_redraw()


func _begin_pointer() -> void:
	step = 2
	running = true
	_t = 0.0
	pointer = 0.0


## 点火候。roll < 0 用真随机（自测传定值，见 M13 断言）。
func strike(roll := -1.0) -> Dictionary:
	if step != 2 or not running:
		return {}
	running = false
	var r := current()
	var hit := SmithScript.in_green(pointer)
	var use_roll := roll if roll >= 0.0 else randf()
	var p: Dictionary = SmithScript.plan(game, r, hit, _event_choice, use_roll)
	_report = SmithScript.apply(game, r, bool(p["success"]))
	_report["hit"] = hit
	_report["chance"] = float(p["chance"])
	step = 3
	queue_redraw()
	return _report


func _process(delta: float) -> void:
	if not visible or not running:
		return
	_t += delta * float(GameData.FURNACE["pointer_speed"])
	pointer = absf(fposmod(_t, 2.0) - 1.0)     # 三角波：0 → 1 → 0
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Engine.get_process_frames() == _opened_frame:
		# 开面板的那一下不算操作（同一个事件会继续传到这里）
		get_viewport().set_input_as_handled()
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	# ⭐ 关自己时同样要吃掉这个键（原因见 SealPanel._input 的注释）
	if is_key and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if step == 0:
			close()
		else:
			step = 0
			running = false
			queue_redraw()
		return
	if event.is_action_pressed("open_forge"):
		get_viewport().set_input_as_handled()
		close()
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		match step:
			0:
				start()
			1:
				choose_event(true)
			2:
				strike()
			_:
				step = 0
				queue_redraw()
		return
	if is_key:
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_Q and step == 1:
			choose_event(false)
			return
		var idx := int(event.keycode) - int(KEY_1)
		if idx >= 0 and idx < recipes().size() and step == 0:
			recipe_index = idx
			_msg = ""
			queue_redraw()
func _draw() -> void:
	if not visible or game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.02, 0.91))
	_text("炉 火 · 合 炼", Vector2(140.0, 92.0), Color(0.96, 0.78, 0.50), 28)
	_text(_hint(), Vector2(142.0, 120.0), Color(0.74, 0.76, 0.80), 14)
	_text("再按 F 关闭", Vector2(142.0, 140.0), Color(0.52, 0.55, 0.58), 12)

	for i in range(recipes().size()):
		_draw_recipe_row(i)
	if step >= 1:
		_draw_furnace()
	if _msg != "":
		_text(_msg, Vector2(142.0, 716.0), Color(0.95, 0.62, 0.46), 15)


func _hint() -> String:
	match step:
		0:
			return "选一条配方（数字键）  ·  E 开炉"
		1:
			return "炉火突变 —— E 加一份灵魄（+%d%%）  ·  Q 不管" % int(GameData.FURNACE["event_bonus"])
		2:
			return "指针进绿区时按 E —— 失误必失败"
	return "E 再来一次  ·  Esc 返回"


func _title(r: Dictionary) -> String:
	if str(r["mode"]) == "upgrade":
		return "升阶 · %s → %d 等" % [r["main"], int(r["to_rank"])]
	return "合成 · %s + %s → %s" % [r["a"], r["b"], r["result"]]


func _materials_line(r: Dictionary) -> String:
	var p = game.player
	var parts: Array = []
	for item in r.get("materials", {}):
		parts.append("%s %d/%d" % [item, p.bag.count(str(item)), int(r["materials"][item])])
	parts.append("灵力 %d/%d" % [int(p.essence), int(GameData.FURNACE["essence_cost"])])
	return "  ·  ".join(parts)


func _draw_recipe_row(i: int) -> void:
	var r: Dictionary = recipes()[i]
	var y := 168.0 + 58.0 * float(i)
	var box := Rect2(Vector2(140.0, y), Vector2(640.0, 50.0))
	var afford := SmithScript.can_afford(game, r)
	var picked: bool = i == recipe_index
	draw_rect(box, Color(0.10, 0.09, 0.08, 0.95))
	draw_rect(box, Color(0.95, 0.72, 0.35, 0.85 if picked else 0.20), false, 3.0 if picked else 1.5)
	_text("%d   %s" % [i + 1, _title(r)], Vector2(156.0, y + 22.0),
			Color(0.94, 0.90, 0.84) if afford else Color(0.54, 0.52, 0.50), 16)
	_text(_materials_line(r), Vector2(156.0, y + 41.0), Color(0.66, 0.70, 0.74), 12)
	_text("%.0f%%" % SmithScript.chance(game, r), Vector2(700.0, y + 30.0),
			Color(0.62, 0.82, 0.66) if afford else Color(0.46, 0.48, 0.50), 16)
	if not afford:
		var miss: Array = SmithScript.missing(game, r)
		if not miss.is_empty():
			_text(str(miss[0]), Vector2(600.0, y + 30.0), Color(0.88, 0.58, 0.42), 12)


func _draw_furnace() -> void:
	var bar := Rect2(Vector2(820.0, 240.0), Vector2(460.0, 34.0))
	draw_rect(bar, Color(0.16, 0.13, 0.11))
	var gz := float(GameData.FURNACE["green_zone"])
	var gx := bar.position.x + (0.5 - gz * 0.5) * bar.size.x
	draw_rect(Rect2(Vector2(gx, bar.position.y), Vector2(gz * bar.size.x, bar.size.y)),
			Color(0.35, 0.74, 0.42, 0.55))
	draw_rect(bar, Color(0.72, 0.62, 0.48), false, 2.0)
	if running:
		var px := bar.position.x + pointer * bar.size.x
		draw_line(Vector2(px, bar.position.y - 16.0),
				Vector2(px, bar.position.y + bar.size.y + 16.0), Color(0.98, 0.86, 0.45), 4.0)

	if step == 1:
		_text("炉火突变：加一份灵魄？", Vector2(820.0, 200.0), Color(0.96, 0.70, 0.42), 18)
	elif step == 2:
		_text("火候", Vector2(820.0, 200.0), Color(0.80, 0.82, 0.86), 18)
	else:
		_text("炉火已熄", Vector2(820.0, 200.0), Color(0.60, 0.62, 0.66), 18)

	if step == 3 and not _report.is_empty():
		var ok := bool(_report["success"])
		var line1 := "成" if ok else "败"
		var color := Color(0.62, 0.88, 0.62) if ok else Color(0.92, 0.50, 0.42)
		_text(line1, Vector2(820.0, 330.0), color, 30)
		var detail := ""
		if ok:
			detail = "%s → %d 等" % [_report["result"], int(_report["rank"])]
		elif str(_report.get("result", "")) == "":
			detail = "材料已尽，印未成" if not _report["lost_seals"].is_empty() else "辅材已尽，印未成"
		_text("命中 %s  ·  成功率 %.0f%%" % ["是" if bool(_report["hit"]) else "否", float(_report["chance"])],
				Vector2(820.0, 362.0), Color(0.70, 0.72, 0.76), 13)
		_text(detail, Vector2(820.0, 386.0), Color(0.86, 0.84, 0.80), 14)
		var lost: Array = _report["lost_materials"]
		if not lost.is_empty():
			_text("失去：" + ", ".join(lost), Vector2(820.0, 410.0), Color(0.80, 0.56, 0.48), 13)
		if not _report["lost_seals"].is_empty():
			_text("失去：" + ", ".join(_report["lost_seals"]), Vector2(820.0, 432.0),
					Color(0.80, 0.56, 0.48), 13)


func _text(s: String, at: Vector2, col: Color, px: int) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)