extends Control
## 背包面板（M30.2）。用户定案：**单独做一个面板，新键 B**。
##
## ⭐ 交互契约（用户原话，逐条落地）：
##    · **左键**点一件东西 = 选中 1 个（继续点每次 **+1**，到上限就停在全部）
##    · **右键**点一件东西 = 选中**全部**（再按一次右键 = 取消选择）
##    · 然后按「使用」或「丢弃」—— 按钮可点，也有键盘：**Q = 使用 / Delete = 丢弃**
##    · 左键点一件东西的同时，右边就把**基本信息**写出来（类别 / 卖价 / 药力 / 能不能用）
##
## ⭐ 捡到 / 用掉 / 丢掉之后，选中数量会自动夹回「实际拥有」—— 不会出现「已选 5 / 拥有 2」。
## ⚠️ 丢弃要按**两下**：材料是攒出来的，误点一下不该永久损失。
## ⚠️ 和别的面板一样：打开时游戏暂停，所以必须 PROCESS_MODE_WHEN_PAUSED。
## ⚠️ 打开面板的**那一帧**不接受操作（同一个事件会继续传到面板里）—— 见 _opened_frame。

signal closed

const ItemsScript := preload("res://scripts/Items.gd")

var player = null
var game = null

var _font: Font = null
var _opened_frame := -1
var _msg := ""

## 选中的物品名（"" = 还没选）+ 选中的数量。
## ⭐ 只存名字和数字，不存下标 —— 背包一变化（用掉 / 丢掉），下标就失效了，名字不会。
var sel_item := ""
var sel_count := 0
var _confirm_discard := false

const ROW_H := 36.0
const HEAD := 56.0          # 列表标题占的高度


func _ready() -> void:
	_font = GameData.make_font()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func open(p, g = null) -> void:
	player = p
	game = g
	sel_item = ""
	sel_count = 0
	_confirm_discard = false
	_msg = ""
	visible = true
	_opened_frame = Engine.get_process_frames()
	# ⭐ 覆盖整个视口 —— 面板自己画背景，这样「点空白处」不会穿透到世界里去
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func close() -> void:
	visible = false
	_msg = ""
	close_confirm()
	closed.emit()


# ==================== 几何 ====================

func panel_rect() -> Rect2:
	return Rect2(Vector2(110.0, 70.0), Vector2(1146.0, 628.0))


func list_rect() -> Rect2:
	return Rect2(Vector2(134.0, 94.0), Vector2(640.0, 580.0))


func detail_rect() -> Rect2:
	return Rect2(Vector2(798.0, 94.0), Vector2(434.0, 580.0))


func row_rect(i: int) -> Rect2:
	return Rect2(list_rect().position + Vector2(0.0, HEAD + ROW_H * float(i)),
			Vector2(list_rect().size.x, ROW_H))


func use_rect() -> Rect2:
	var d := detail_rect()
	return Rect2(Vector2(d.position.x + 22.0, d.position.y + d.size.y - 108.0), Vector2(184.0, 46.0))


func discard_rect() -> Rect2:
	var d := detail_rect()
	return Rect2(Vector2(d.position.x + 224.0, d.position.y + d.size.y - 108.0), Vector2(184.0, 46.0))


# ==================== 内容 ====================

## 列表内容：背包里的**材料**（有数量的）+ 你拥有的**灵印**（只读：看信息，不能在这里丢）。
func entries() -> Array:
	var out: Array = []
	if player == null:
		return out
	for name_key in player.bag.items.keys():
		var n := int(player.bag.items[name_key])
		if n > 0:
			out.append({"name": str(name_key), "kind": "mat", "count": n})
	out.sort_custom(func(a, b): return str(a["name"]) < str(b["name"]))
	var seals: Array = []
	for nk in player.bag_seals:
		if not seals.has(str(nk)):
			seals.append(str(nk))
	for nk in player.reserve_seals:
		if not seals.has(str(nk)):
			seals.append(str(nk))
	for nk in seals:
		out.append({"name": str(nk), "kind": "seal", "count": 1})
	return out


func count_of(name_key: String) -> int:
	if player == null:
		return 0
	if GameData.MATERIALS.has(name_key):
		return int(player.bag.count(name_key))
	return 1


func selected_entry() -> Dictionary:
	for e in entries():
		if str(e["name"]) == sel_item:
			return e
	return {}


# ==================== 选中（这就是用户要的那套点法）====================

## 左键：选中 1 个，**继续点每次 +1**，点满就停在全部。
func select_one(name_key: String) -> void:
	if name_key != sel_item:
		sel_item = name_key
		sel_count = 0
	close_confirm()
	sel_count = clampi(sel_count + 1, 1, maxi(1, count_of(name_key)))
	_msg = ""
	queue_redraw()


## 右键：**全选**；已经是全选就取消（省得再想一个键）。
func select_all(name_key: String) -> void:
	close_confirm()
	var n := maxi(1, count_of(name_key))
	if name_key == sel_item and sel_count >= n:
		sel_count = 0
		_msg = ""
	else:
		sel_item = name_key
		sel_count = n
		_msg = ""
	queue_redraw()


func close_confirm() -> void:
	_confirm_discard = false


func clamp_selection() -> void:
	if sel_item == "":
		return
	var n := count_of(sel_item)
	if n <= 0 or not entries().any(func(e): return str(e["name"]) == sel_item):
		sel_item = ""
		sel_count = 0
		return
	sel_count = clampi(sel_count, 1, n)


# ==================== 使用 / 丢弃 ====================

func do_use() -> int:
	if player == null or sel_item == "":
		_msg = "先点一件东西，选好数量"
		queue_redraw()
		return 0
	var reason := ItemsScript.use_reason(sel_item, player)
	if reason != "":
		_msg = reason
		queue_redraw()
		return 0
	var r: Dictionary = ItemsScript.use_apply(player, sel_item, sel_count)
	if int(r["used"]) <= 0:
		_msg = ItemsScript.use_reason(sel_item, player)
		if _msg == "":
			_msg = "没用到东西"
	else:
		_msg = "使用 %s ×%d：灵力 +%.0f" % [sel_item, int(r["used"]), float(r["gained"])]
		if float(r.get("wasted", 0.0)) > 0.5:
			_msg += "（到上限了，多出的 %.0f 浪费了）" % float(r["wasted"])
	clamp_selection()
	queue_redraw()
	return int(r["used"])


func do_discard() -> int:
	if player == null or sel_item == "":
		_msg = "先点一件东西，选好数量"
		queue_redraw()
		return 0
	if not ItemsScript.can_discard(sel_item):
		_msg = ItemsScript.discard_reason(sel_item)
		queue_redraw()
		return 0
	if not _confirm_discard:
		_confirm_discard = true
		_msg = "再按一次（或再点一下「丢弃」）就真的丢掉 %s ×%d，不可恢复" % [sel_item, sel_count]
		queue_redraw()
		return 0
	var lost := ItemsScript.discard_apply(player, sel_item, sel_count)
	_confirm_discard = false
	_msg = "丢弃了 %s ×%d" % [sel_item, lost]
	clamp_selection()
	queue_redraw()
	return lost


# ==================== 输入 ====================

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Engine.get_process_frames() == _opened_frame:
		# ⭐ 开面板的那一下不算操作（同一个事件也会传到面板里）
		get_viewport().set_input_as_handled()
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	if event.is_action_pressed("open_bag") or (is_key and event.keycode == KEY_ESCAPE):
		# ⭐ 必须吃掉这个键 —— 否则暂停解除后同一帧 Game._input 会把面板又开回来
		get_viewport().set_input_as_handled()
		close()
		return
	if is_key:
		get_viewport().set_input_as_handled()
		if event.keycode == KEY_Q:
			do_use()
		elif event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			do_discard()


func _row_at(pos: Vector2) -> int:
	var r := list_rect()
	if not Rect2(r.position + Vector2(0.0, HEAD), Vector2(r.size.x, r.size.y - HEAD)).has_point(pos):
		return -1
	var i := int((pos.y - (r.position.y + HEAD)) / ROW_H)
	if i < 0 or i >= entries().size():
		return -1
	return i


func _gui_input(event: InputEvent) -> void:
	if not visible or player == null:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if Engine.get_process_frames() == _opened_frame:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and use_rect().has_point(mb.position):
		do_use()
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and discard_rect().has_point(mb.position):
		do_discard()
		return
	var i := _row_at(mb.position)
	if i < 0:
		close_confirm()
		queue_redraw()
		return
	var e: Dictionary = entries()[i]
	if mb.button_index == MOUSE_BUTTON_LEFT:
		select_one(str(e["name"]))
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		select_all(str(e["name"]))


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# ==================== 画 ====================

func _draw() -> void:
	if not visible or player == null:
		return
	var pr := panel_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.03, 0.04, 0.55))     # 压暗世界
	draw_rect(pr, Color(0.06, 0.07, 0.09, 0.96))
	draw_rect(pr, Color(0.32, 0.36, 0.42, 0.85), false, 2.0)

	_text("背包", pr.position + Vector2(24.0, 40.0), Color(0.90, 0.92, 0.94), 24)
	_text("左键 +1 · 右键 全选 · Q 使用 · Delete 丢弃 · B / Esc 关闭",
			pr.position + Vector2(120.0, 39.0), Color(0.56, 0.60, 0.66), 14)
	_text("背包容积 %d / %d     灵石 %d" % [player.bag.capacity_used(), int(GameData.BAG_CAPACITY),
			int(player.bag.stones)], pr.position + Vector2(820.0, 39.0), Color(0.72, 0.76, 0.80), 15)

	_draw_list()
	_draw_detail()


func _draw_list() -> void:
	var r := list_rect()
	draw_rect(r, Color(0.04, 0.05, 0.07, 0.92))
	draw_rect(r, Color(0.28, 0.32, 0.38, 0.7), false, 1.5)
	_text("物品", r.position + Vector2(16.0, 34.0), Color(0.84, 0.86, 0.90), 18)

	var es := entries()
	if es.is_empty():
		_text("（空的 —— 去采点东西，或者打死敌人捡掉落）", r.position + Vector2(16.0, HEAD + 24.0),
				Color(0.46, 0.50, 0.56), 14)
		return
	var max_rows := int((r.size.y - HEAD) / ROW_H)
	for i in range(mini(es.size(), max_rows)):
		var e: Dictionary = es[i]
		var rr := row_rect(i)
		var name_key := str(e["name"])
		var picked: bool = name_key == sel_item
		if picked:
			draw_rect(Rect2(rr.position + Vector2(6.0, 2.0), Vector2(rr.size.x - 12.0, rr.size.y - 4.0)),
					Color(0.92, 0.88, 0.60, 0.14))
		if str(e["kind"]) == "seal":
			var d: Dictionary = GameData.SEALS[name_key]
			# ⭐ M30.6：灵印也用它的 32×32 贴图（没图才回退到形状）
			var stex := ActorVisual.texture_of(d)
			if stex != null:
				ActorVisual.draw_icon(self, stex, rr.position + Vector2(28.0, 18.0))
			else:
				_draw_diamond(rr.position + Vector2(26.0, 18.0), 9.0, d["color"])
			_text("%s（灵印）" % name_key, rr.position + Vector2(46.0, 24.0), Color(0.88, 0.82, 0.76), 15)
			_text("炼化 %d%%" % int(player.refine_of(name_key)),
					rr.position + Vector2(rr.size.x - 130.0, 24.0), Color(0.62, 0.66, 0.72), 13)
		else:
			# ⭐ M30.5b：材料行画 32×32 图标（面板是原生分辨率，1:1 正好一行）
			ActorVisual.draw_icon(self, ActorVisual.texture_of(GameData.item_visual(name_key)),
					rr.position + Vector2(28.0, 18.0))
			_text(name_key, rr.position + Vector2(46.0, 24.0), Color(0.80, 0.84, 0.88), 15)
			if picked:
				_text("已选 %d / %d" % [sel_count, int(e["count"])],
						rr.position + Vector2(rr.size.x - 190.0, 24.0), Color(0.95, 0.90, 0.62), 13)
			var each := GameData.volume_of(name_key)
			_text("×%d · %d格" % [int(e["count"]), int(e["count"]) * each],
					rr.position + Vector2(rr.size.x - 132.0, 24.0), Color(0.74, 0.78, 0.82), 14)
	if es.size() > max_rows:
		_text("…还有 %d 项" % (es.size() - max_rows), r.position + Vector2(16.0, r.size.y - 12.0),
				Color(0.50, 0.54, 0.60), 12)


func _draw_detail() -> void:
	var d := detail_rect()
	draw_rect(d, Color(0.05, 0.06, 0.08, 0.92))
	draw_rect(d, Color(0.28, 0.32, 0.38, 0.7), false, 1.5)
	var x := d.position.x + 22.0
	var y := d.position.y + 36.0
	var e := selected_entry()
	if e.is_empty():
		_text("选一件东西", Vector2(x, y), Color(0.84, 0.86, 0.90), 18)
		_text("左键点一下 = 选中 1 个，继续点每次 +1；", Vector2(x, y + 34.0), Color(0.60, 0.64, 0.70), 14)
		_text("右键点一下 = 直接全选。", Vector2(x, y + 56.0), Color(0.60, 0.64, 0.70), 14)
		_draw_buttons(false)
		return

	_text(str(e["name"]), Vector2(x, y), Color(0.94, 0.92, 0.86), 22)
	y += 30.0
	if str(e["kind"]) == "seal":
		var sd: Dictionary = GameData.SEALS[str(e["name"])]
		_text("灵印 · %s · 炼化 %d%%" % [GameData.RANKS[int(sd["rank"])], int(player.refine_of(str(e["name"])))],
				Vector2(x, y), Color(0.80, 0.78, 0.72), 14)
		y += 26.0
		_text("炼化去 Tab 命窍面板（花灵力，不再吃材料）；换上活跃槽也在那里。",
				Vector2(x, y), Color(0.66, 0.70, 0.76), 13)
		y += 22.0
		_text("丢弃 = 永久失去这枚印（只有本命印丢不掉）。", Vector2(x, y), Color(0.72, 0.62, 0.52), 13)
		y += 30.0
	else:
		var md: Dictionary = GameData.MATERIALS[str(e["name"])]
		_text("材料 · %s" % str(md["kind"]), Vector2(x, y), Color(0.80, 0.84, 0.90), 14)
		y += 26.0
		_text("卖价 %d 灵石 · 用于合炼（炼化只吃灵力）" % int(md["price"]),
				Vector2(x, y), Color(0.70, 0.74, 0.80), 13)
		y += 22.0
		_text("体积 %d 格 / 件　·　背包 %d / %d 格" % [GameData.volume_of(str(e["name"])),
				player.bag.capacity_used(), int(GameData.BAG_CAPACITY)], Vector2(x, y),
				Color(0.78, 0.72, 0.58), 13)
		y += 22.0
		var fx := ItemsScript.use_effect(str(e["name"]))
		if fx.is_empty():
			_text("不能直接使用：它是合炼用的材料。", Vector2(x, y), Color(0.74, 0.66, 0.56), 13)
		else:
			_text("使用：回 %.0f 灵力（和采一口一样）" % float(fx.get("essence", 0.0)),
					Vector2(x, y), Color(0.62, 0.84, 0.66), 13)
		y += 30.0

	_text("已选 %d / 拥有 %d" % [sel_count, count_of(sel_item)], Vector2(x, y),
			Color(0.95, 0.90, 0.62), 18)
	y += 30.0
	if _msg != "":
		_text(_msg, Vector2(x, y), Color(0.86, 0.78, 0.60), 13)
	_draw_buttons(true)


func _draw_buttons(has_sel: bool) -> void:
	var ur := use_rect()
	var dr := discard_rect()
	var use_reason := "" if not has_sel else ItemsScript.use_reason(sel_item, player)
	var use_ok: bool = has_sel and use_reason == ""
	var dis_ok: bool = has_sel and ItemsScript.can_discard(sel_item)

	draw_rect(ur, Color(0.14, 0.20, 0.15, 0.96) if use_ok else Color(0.10, 0.11, 0.13, 0.96))
	draw_rect(ur, Color(0.45, 0.72, 0.48, 0.85) if use_ok else Color(0.26, 0.29, 0.33, 0.8), false, 1.5)
	_text("使用（Q）", ur.position + Vector2(20.0, 30.0),
			Color(0.78, 0.92, 0.80) if use_ok else Color(0.48, 0.52, 0.56), 16)

	draw_rect(dr, Color(0.20, 0.12, 0.12, 0.96) if dis_ok else Color(0.10, 0.11, 0.13, 0.96))
	draw_rect(dr, Color(0.78, 0.42, 0.40, 0.85) if dis_ok else Color(0.26, 0.29, 0.33, 0.8), false, 1.5)
	var dlabel := "确认丢弃（Delete）" if _confirm_discard else "丢弃（Delete）"
	_text(dlabel, dr.position + Vector2(18.0, 30.0),
			Color(0.94, 0.74, 0.72) if dis_ok else Color(0.48, 0.52, 0.56), 16)

	if has_sel and not use_ok and use_reason != "":
		var d2 := detail_rect()
		_text(use_reason, Vector2(d2.position.x + 22.0, d2.position.y + d2.size.y - 22.0),
				Color(0.70, 0.62, 0.52), 12)


func _draw_diamond(at: Vector2, s: float, col: Color) -> void:
	draw_colored_polygon(PackedVector2Array([
		at + Vector2(0.0, -s), at + Vector2(s, 0.0), at + Vector2(0.0, s), at + Vector2(-s, 0.0)]), col)


func _text(s: String, at: Vector2, col: Color, px: int) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
