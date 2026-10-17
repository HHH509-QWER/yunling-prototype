extends Control
## 交易面板（M14）。⭐ 左边他卖你的，右边你卖他的；`Q` 换边，数字选，`E` 成交一个。
##
## ⚠️ 打开时游戏暂停，所以必须 PROCESS_MODE_WHEN_PAUSED。
## ⚠️ 关闭时必须**吃掉这个键**（原因见 SealPanel._input 的注释：不吃掉会被 Game 又开回来）。

signal closed

const TradeScript := preload("res://scripts/Trade.gd")

var game = null
var side := 0            # 0 = 买（他的货架） / 1 = 卖（我的背包）
var index := 0

var _msg := ""
## ⭐ 打开面板的**那一帧**不接受操作。
##    实测：按 E 开交易面板，会顺手把第一件商品买下来 ——
##    因为「开面板」和「面板处理按键」看到的是**同一个事件**。
var _opened_frame := -1

## ⭐ 双击自己算，不依赖 `event.double_click`。
##    那个标志是**操作系统**发出来的（WM_LBUTTONDBLCLK）—— 合成/注入的事件不带它，
##    某些平台（触屏、远程注入）也不给。自己按时间判定才靠得住。
const DOUBLE_CLICK_MS := 350
var _last_click_ms := -99999
var _last_click_row := -1
var _font: Font = null


func _ready() -> void:
	_font = GameData.make_font()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false


func open(g) -> void:
	game = g
	side = 0
	index = 0
	_msg = ""
	visible = true
	_opened_frame = Engine.get_process_frames()
	queue_redraw()


func close() -> void:
	visible = false
	_msg = ""
	closed.emit()


## 当前这一侧的条目（买 = 货架 + 服务；卖 = 背包材料）。
func entries() -> Array:
	if game == null:
		return []
	return TradeScript.buy_entries(game) if side == 0 else TradeScript.sell_entries(game)


## 保留旧名字 —— 自测里用的是它。
func list() -> Array:
	return entries()


func current_entry() -> Dictionary:
	var es := entries()
	if index < 0 or index >= es.size():
		return {}
	return es[index]


func current_item() -> String:
	return str(current_entry().get("id", ""))


## 成交一个（买或卖，看当前在哪一侧）。
func trade() -> Dictionary:
	var item := current_item()
	if item == "":
		_msg = "这边没得选 —— 按 Q 换一边，或者先出门赚点货"
		queue_redraw()
		return {"ok": false, "reason": "no_item"}
	var r: Dictionary = TradeScript.buy_entry(game, current_entry()) if side == 0 \
			else TradeScript.sell(game, item)
	if bool(r["ok"]):
		if side == 0:
			_msg = "买下 %s，花了 %d 灵石" % [item, int(r["spent"])]
		else:
			_msg = "卖出 %s，进账 %d 灵石" % [item, int(r["earned"])]
	else:
		_msg = str(r.get("reason", "不行"))
	index = clampi(index, 0, maxi(0, list().size() - 1))
	queue_redraw()
	return r


## 某一行的矩形。⭐ **画的和点的共用这一个函数** —— 各自算一遍迟早会错位。
func row_rect(i: int, which: int) -> Rect2:
	var x := 160.0 if which == 0 else 720.0
	return Rect2(Vector2(x, 200.0 + 44.0 * float(i)), Vector2(420.0, 36.0))


## 鼠标点在哪儿？返回 {"side": 0/1, "index": i}；没点到就返回空。
func row_at(pos: Vector2) -> Dictionary:
	for i in range(TradeScript.stock_list(game).size()):
		if row_rect(i, 0).has_point(pos):
			return {"side": 0, "index": i}
	for i in range(TradeScript.sell_list(game).size()):
		if row_rect(i, 1).has_point(pos):
			return {"side": 1, "index": i}
	return {}


## ⭐ 鼠标：**点一下选中，双击成交**。点哪一列就算哪一列 ——
##    不需要先按 Q 切「买 / 卖」（那是键盘思维，鼠标用户会觉得别扭）。
func _gui_input(event: InputEvent) -> void:
	if not visible or game == null:
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var hit := row_at(event.position)
	if hit.is_empty():
		return
	get_viewport().set_input_as_handled()
	side = int(hit["side"])
	index = int(hit["index"])

	# 同一行、350ms 内的第二次按下 = 双击（平台给了标志也认）
	var row_key := int(hit["side"]) * 1000 + int(hit["index"])
	var now := Time.get_ticks_msec()
	var is_double: bool = event.double_click
	if not is_double and row_key == _last_click_row and now - _last_click_ms <= DOUBLE_CLICK_MS:
		is_double = true
	_last_click_ms = now
	_last_click_row = row_key

	if is_double:
		trade()                          # 双击 = 成交（买卖由点在哪儿决定）
	else:
		_msg = ""                        # 单击 = 只选中
		queue_redraw()


## 只给自测与键盘用：把「当前侧」设成 s。
func set_side(s: int) -> void:
	side = clampi(s, 0, 1)
	index = 0
	_msg = ""
	queue_redraw()


## 已废弃：以前用 Q 切换买/卖。保留成 set_side 的别名，免得老代码断掉。
func switch_side() -> void:
	set_side(1 - side)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Engine.get_process_frames() == _opened_frame:
		# 开面板的那一下不算操作（同一个事件会继续传到这里）
		get_viewport().set_input_as_handled()
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	if is_key and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		trade()
		return
	if is_key:
		get_viewport().set_input_as_handled()
		# ⭐ 没有 Q 了 —— 鼠标点哪一列就是买/卖哪一列，不需要先切边
		var idx := int(event.keycode) - int(KEY_1)
		if idx >= 0 and idx < list().size():
			index = idx
			_msg = ""
			queue_redraw()


func _draw() -> void:
	if not visible or game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.03, 0.02, 0.91))
	_text("商 人", Vector2(140.0, 96.0), Color(0.94, 0.84, 0.52), 28)
	_text("灵石 %d" % game.player.bag.stones, Vector2(300.0, 96.0), Color(0.92, 0.82, 0.45), 20)
	_text("点一下选中  ·  双击成交  ·  键盘：数字选 + E 成交  ·  Esc 走人", Vector2(142.0, 124.0),
			Color(0.72, 0.74, 0.78), 14)
	_text("他卖你的" + ("（当前）" if side == 0 else ""), Vector2(160.0, 172.0),
			Color(0.86, 0.88, 0.90) if side == 0 else Color(0.52, 0.55, 0.58), 18)
	_text("你卖他的" + ("（当前）" if side == 1 else ""), Vector2(720.0, 172.0),
			Color(0.86, 0.88, 0.90) if side == 1 else Color(0.52, 0.55, 0.58), 18)

	for i in range(TradeScript.stock_list(game).size()):
		_draw_row(i, 0)
	for i in range(TradeScript.sell_list(game).size()):
		_draw_row(i, 1)
	if _msg != "":
		_text(_msg, Vector2(142.0, 700.0), Color(0.88, 0.90, 0.66), 15)


func _draw_row(i: int, which: int) -> void:
	var es: Array = TradeScript.buy_entries(game) if which == 0 else TradeScript.sell_entries(game)
	var entry: Dictionary = es[i]
	var item := str(entry["id"])
	var is_service: bool = str(entry["kind"]) == "service"
	var label := str(entry.get("label", item))
	var box := row_rect(i, which)
	var x := box.position.x
	var y := box.position.y
	var picked: bool = which == side and i == index
	# 服务不是材料，颜色单独给（青 = 灵力），免得去材料表里查不到
	var col: Color = Color(0.55, 0.85, 0.95) if is_service else GameData.MATERIALS[item]["color"]
	draw_rect(box, Color(0.11, 0.10, 0.09, 0.95))
	if picked:
		draw_rect(box, Color(0.94, 0.80, 0.45, 0.85), false, 3.0)
	var c := Vector2(x + 18.0, y + 18.0)
	draw_colored_polygon(PackedVector2Array([
		c + Vector2(0.0, -7.0), c + Vector2(7.0, 0.0), c + Vector2(0.0, 7.0), c + Vector2(-7.0, 0.0)]), col)
	_text("%d   %s%s" % [i + 1, label, "（服务 · %d 点）" % int(entry.get("amount", 0)) if is_service else ""],
			Vector2(x + 34.0, y + 24.0), Color(0.90, 0.90, 0.86), 15)
	if which == 0:
		_text("%d 灵石" % int(entry["price"]), Vector2(x + 220.0, y + 24.0),
				Color(0.92, 0.82, 0.45), 15)
		_text(str(entry["detail"]), Vector2(x + 320.0, y + 24.0), Color(0.68, 0.72, 0.76), 14)
	else:
		_text("+%d 灵石" % int(entry["price"]), Vector2(x + 220.0, y + 24.0),
				Color(0.72, 0.86, 0.62), 15)
		_text(str(entry["detail"]), Vector2(x + 320.0, y + 24.0), Color(0.68, 0.72, 0.76), 14)
func _text(s: String, at: Vector2, col: Color, px: int) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)