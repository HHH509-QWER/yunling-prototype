extends Control
## 命窍面板：看灵印 + **炼化（只吃灵力）** + 换印。
## ⚠️ M30.3：炼化**不再消耗材料**（用户定案）—— 原来那条 `feed()` 投料通路已删除。
##
## ⭐ 两步：`1`-`4` 选印（看基础信息）→ `1`-`8` 选材料投进去（可连投）。
##    「先选印、再逐种投」是刻意的 —— 投什么材料本身就是玩家的选择。
## ⚠️ 打开时游戏暂停，所以必须 PROCESS_MODE_WHEN_PAUSED，否则收不到输入。

signal closed

var player = null
var game = null            # 修炼要飘字，所以也拿着主控；可为 null
var step := 0            # 0 = 选印，1 = 炼化（点左下按钮花灵力），2 = 换印（从备用里挑一枚换上）


## 换印：把备用第 j 枚换上当前选中的活跃格。
func swap(j: int) -> bool:
	if player == null or player.reserve_seals.is_empty():
		return false
	var incoming := str(player.reserve_seals[j]) if j < player.reserve_seals.size() else ""
	var outgoing := str(player.slot_seal[seal_index])
	if not player.swap_seal(seal_index, j):
		return false
	_msg = "第 %d 格：%s → %s" % [seal_index + 1, outgoing if outgoing != "" else "空", incoming]
	step = 1
	queue_redraw()
	return true
var seal_index := 0      # 选中的槽位（数字键 / 老接口）
var selected_name := ""  # M21：当前选中的印（空窍里或背包里都算）
var selected_slot := -1  # 若它在活跃槽里，槽位下标；否则 -1

var _font: Font = null
var _msg := ""
## ⭐ 打开面板的**那一帧**不接受操作。
##    实测：按 E 开交易面板，会顺手把第一件商品买下来 ——
##    因为「开面板」和「面板处理按键」看到的是**同一个事件**。
var _opened_frame := -1
## ⭐ 绘制/输入路标（诊断用）：画到哪一步、面板收到了什么事件。
##    绘制中途抛错时，dbg_mark 会**停在断点上** —— 这是定位「界面画不出来」最快的方法。
var dbg_mark := ""
var dbg_frames := 0


func _ready() -> void:
	_font = GameData.make_font()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false


func open(p, g = null) -> void:
	player = p
	game = g
	step = 0
	seal_index = 0
	selected_name = ""
	selected_slot = -1
	_msg = ""
	visible = true
	_opened_frame = Engine.get_process_frames()
	queue_redraw()


## ---------------- M21：球形空窍的几何 ----------------
## 空窍：一颗球，画在左边。⭐ 半径 = 灵力**容量**（境界 / 小境界 / 印的基础属性都会撑大它）。
func orb_center() -> Vector2:
	return Vector2(400.0, 368.0)


func orb_radius() -> float:
	if player == null:
		return 100.0
	return clampf(74.0 + player.essence_max * 0.30, 90.0, 168.0)


## 右侧背包：未炼化的印 + 材料，都放这儿。
func bag_rect() -> Rect2:
	return Rect2(Vector2(772.0, 150.0), Vector2(566.0, 468.0))


## 「炼化」按钮：放在背包下面（炼的是背包里选中的那枚）。
func refine_rect() -> Rect2:
	return Rect2(Vector2(772.0, 630.0), Vector2(566.0, 46.0))


## 修为那一块的布局：进度条 + 修炼按钮。⭐ 画的和点的共用这一个几何来源。
func cultivate_rect() -> Rect2:
	return Rect2(Vector2(180.0, 648.0), Vector2(250.0, 42.0))


## 现在能不能炼化当前这枚印？（没炼满 + 灵力够）
func can_refine_now() -> bool:
	if player == null:
		return false
	var nk := current_seal()
	if nk == "" or player.is_refined(nk):
		return false
	return player.essence >= float(GameData.REFINE["press_cost"])


## 点「炼化」：花灵力把这枚印往"能用"推一格。返回实际涨了多少炼化度。
func do_refine() -> float:
	if player == null:
		return 0.0
	var nk := current_seal()
	var r: Dictionary = player.refine_press(nk)
	if bool(r["ok"]):
		_msg = "%s 炼化 +%d%%（-%.0f 灵力）" % [nk, int(float(r["gained"])), float(r["spent"])]
	else:
		_msg = str(r["reason"])
	queue_redraw()
	return float(r.get("gained", 0.0))


func can_cultivate() -> bool:
	if player == null:
		return false
	return player.essence >= 1.0 and player.cultivation < player.cultivation_max() - 0.001


## 点「修炼」按钮 = 花灵力换修为。返回实际换到多少。
## ⭐ 修炼放在命窍界面里（而不是回锚点按 E）：它是个「把燃料锁成进度」的操作，
##    该在你翻命窍的时候顺手做，而不是专门跑一趟。
## 突破按钮的布局：修炼下面那个。⭐ 画的和点的共用这一个几何来源。
func breakthrough_rect() -> Rect2:
	return Rect2(Vector2(448.0, 648.0), Vector2(250.0, 42.0))


## 现在能不能突破？（修为满 + 没到顶 + 拿得到主控）
func can_breakthrough_now() -> bool:
	return player != null and game != null and player.can_breakthrough()


## 点「突破」按钮。⭐ 任意地方都能突破（用户改的规则），
##    但突破仍然**把境界钉住**（重拍快照 + 存档），死了不会退回旧境界。
func do_breakthrough() -> bool:
	if not can_breakthrough_now():
		_msg = "突破不了：修为还没攒满"
		queue_redraw()
		return false
	var ok: bool = game.try_breakthrough()
	if ok:
		_msg = "突破！境界 → %s" % player.realm_name()
	queue_redraw()
	return ok


func do_cultivate() -> float:
	if not can_cultivate():
		_msg = "修炼不动：灵力不足，或者修为已经满了"
		queue_redraw()
		return 0.0
	var gained: float = 0.0
	if game != null and game.has_method("try_cultivate"):
		gained = game.try_cultivate()
	else:
		gained = player.cultivate()
	_msg = "修炼：-%.0f 灵力 → +%.0f 修为" % [gained, gained]
	queue_redraw()
	return gained


func close() -> void:
	visible = false
	_msg = ""
	closed.emit()


## 当前选中的印名 —— ⭐ M21：空窍里的、背包里的都能选（`selected_name` 优先）。
## 没选过就退回「第 seal_index 个活跃槽」，保持老接口（数字键 / 自测都走它）。
func current_seal() -> String:
	if player == null:
		return ""
	if selected_name != "":
		return selected_name
	if seal_index < 0 or seal_index >= player.slot_seal.size():
		return ""
	return str(player.slot_seal[seal_index])


## 选一枚背包里的印（还没炼化的那些）。
func select_bag_seal(name_key: String) -> void:
	selected_name = name_key
	selected_slot = -1
	_msg = ""
	queue_redraw()


## 我拥有的**全部**印（活跃槽 + 备用 + **背包**），按槽位顺序。
func owned_seals() -> Array:
	var out_list: Array = []
	if player == null:
		return out_list
	for i in range(player.slot_seal.size()):
		var nk := str(player.slot_seal[i])
		if nk != "" and not out_list.has(nk):
			out_list.append(nk)
	for n in player.reserve_seals:
		if not out_list.has(str(n)):
			out_list.append(str(n))
	# ⭐ M29.5：背包里的印也算「我拥有的」（收藏无上限）
	for n in player.bag_seals:
		if not out_list.has(str(n)):
			out_list.append(str(n))
	return out_list


## 空窍里浮动的印 = **一切已融合的印**（⭐ 用户要的：炼化的印就放球形空窍里）。
func orb_seals() -> Array:
	var out_list: Array = []
	for nk in owned_seals():
		if player.is_refined(str(nk)):
			out_list.append(str(nk))
	return out_list


## 右侧背包的条目：**未炼化的印在前，材料在后**（⭐ 用户要的：未炼化的印和材料放一起）。
## 每项：{kind: "seal"/"material", name, index（材料在 material_list 里的下标）}
func bag_entries() -> Array:
	var out_list: Array = []
	if player == null:
		return out_list
	for nk in owned_seals():
		if not player.is_refined(str(nk)):
			out_list.append({"kind": "seal", "name": str(nk), "index": -1})
	var mats := material_list()
	for i in range(mats.size()):
		out_list.append({"kind": "material", "name": str(mats[i]), "index": i})
	return out_list


## 背包里有的材料名（按数量从多到少）。
func material_list() -> Array:
	if player == null:
		return []
	return player.bag.top_items(8)


## 选第 i 枚印（数字键与点击共用这一个入口）。
func pick_seal(i: int) -> void:
	if i < 0 or i >= player.slot_seal.size():
		return
	seal_index = i
	selected_name = str(player.slot_seal[i])
	selected_slot = i
	step = 1
	if str(player.slot_seal[i]) == "":
		_msg = "第 %d 格是空的 —— 按 Q 从备用里换一枚进来" % (i + 1)
	else:
		_msg = ""
	queue_redraw()


## ⛔ M30.3：`feed()`（投一份材料涨炼化）**已删除**。
##    用户定案：「炼化灵印需要消耗灵气而不是消耗材料」。
##    炼化从此只剩一条路：`do_refine()`（点左下按钮，花灵力）。材料只用于**合炼**与**卖**。
##    ⚠️ 别再把它加回来 —— 两条并行的涨法会让「炼化到底花什么」永远说不清。


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if Engine.get_process_frames() == _opened_frame:
		# 开面板的那一下不算操作（同一个事件会继续传到这里）
		get_viewport().set_input_as_handled()
		return
	var is_key: bool = event is InputEventKey and event.pressed and not event.echo
	# ⭐ 关自己 / 退回这一步：**必须吃掉这个键**。
	#    Godot 的 _input 是从子节点往父节点传的，所以在暂停被解除之后，
	#    Game._input 会在同一帧接着处理同一个 Tab —— 它会把面板又开回来。
	#    （这就是「按 Tab 打开命窍后关不掉」那个 bug。）
	if event.is_action_pressed("open_panel") or (is_key and event.keycode == KEY_ESCAPE):
		get_viewport().set_input_as_handled()
		if is_key and event.keycode == KEY_ESCAPE and step != 0:
			step = 0                         # Esc 先退回选印，再按一次才关
			queue_redraw()
			return
		close()
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		# ⭐ E 在命窍界面里 = 修炼（和点那个按钮等价）
		get_viewport().set_input_as_handled()
		do_cultivate()
		return
	if is_key:
		get_viewport().set_input_as_handled()
		# Q = 在「炼化」和「换印」之间切换（菜单内的临时键，不进 InputMap）
		# ⚠️ 原来是 F —— F 让给全局的「开炉」，免得一个键两义
		if event.keycode == KEY_Q:
			if player.reserve_seals.is_empty():
				_msg = "备用里没有印 —— 去打死灵师强夺"
			else:
				step = 2 if step != 2 else 1
				_msg = ""
			queue_redraw()
			return
		var idx := int(event.keycode) - int(KEY_1)
		if idx < 0:
			return
		if step == 0:
			pick_seal(idx)
		elif step == 2:
			swap(idx)
		# ⚠️ step == 1（炼化步）不吃数字键 —— 炼化只有「点左下那个按钮」一条路（M30.3）
## 点在空窍里的哪一枚印上？返回活跃槽下标；没点中返回 -1。
## ⚠️ 命中的位置和画出来的位置共用 orb_seal_pos() —— 不然点和画会错位。
## ⚠️ 返回的是它在 orb_seals() 里的下标，**不是活跃槽下标**。
##    以前返回活跃槽下标 → 备用印 slot_seal.find() 得到 -1 → pick_seal(-1) 被守卫挡掉 →
##    **空窍里只有活跃的 4 枚点得到**（而换印恰恰要点备用的）。用户就是这么撞上的。
## ⭐ 取"最近的一枚"，半径给到 26px —— 形状只有十几像素，要求点得准太苛刻。
func _orb_seal_at(pos: Vector2) -> int:
	var keys := orb_seals()
	var best := -1
	var best_d := 26.0
	for i in range(keys.size()):
		var d: float = pos.distance_to(orb_seal_pos(i, keys.size()))
		if d <= best_d:
			best_d = d
			best = i
	return best


## 点在背包第几行上？没点中返回 -1。
func _bag_row_at(pos: Vector2) -> int:
	var r := bag_rect()
	if not r.has_point(pos):
		return -1
	var i := int((pos.y - (r.position.y + 52.0)) / 34.0)
	if i < 0 or i >= bag_entries().size():
		return -1
	return i


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if refine_rect().has_point(event.position):
			do_refine()
			return
		if breakthrough_rect().has_point(event.position):
			do_breakthrough()
			return
		if cultivate_rect().has_point(event.position):
			do_cultivate()
			return
		# ---- 空窍：点一枚浮动的印 ----
		if can_swap_selected() and swap_target_rect().has_point(event.position):
			do_swap_selected()
			return
		var orb_i := _orb_seal_at(event.position)
		if orb_i >= 0:
			var nk_o := str(orb_seals()[orb_i])
			var slot_o: int = player.slot_seal.find(nk_o)
			if step == 2 and slot_o < 0:
				var j_o: int = player.reserve_seals.find(nk_o)
				if j_o >= 0:
					swap(j_o)
					return
			if slot_o >= 0:
				pick_seal(slot_o)          # 活跃印：选中它（顺带把目标槽设成它）
			else:
				select_bag_seal(nk_o)      # ⭐ 备用印也点得到、也选得中
			return
		# ---- 背包：印 → 选中它；材料 → 只解释它现在能干嘛（M30.3 起不再投料）----
		var bi := _bag_row_at(event.position)
		if bi >= 0:
			var e: Dictionary = bag_entries()[bi]
			if str(e["kind"]) == "seal":
				select_bag_seal(str(e["name"]))
				step = 0
			else:
				# ⭐ M30.3：材料不再用于炼化 —— 点它只解释「它现在能干嘛」
				var mname := str(e["name"])
				_msg = "%s：卖价 %d 灵石 · 只用于合炼（炼化现在只吃灵力）" % [mname, int(GameData.MATERIALS[mname]["price"])]
				queue_redraw()
## 灵气要动，所以面板开着的时候每帧重画。
## ⭐ 所有动画都由「时间 + 固定相位」算出来、不存状态 —— 同一时刻画面永远一样（截图可复现）。
func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


func _draw() -> void:
	if not visible or player == null:
		return
	dbg_mark = "bg"
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.03, 0.90))
	_text("命 窍 · 炼 化", Vector2(180.0, 92.0), Color(0.93, 0.88, 0.70), 28)
	_text("命窍 %d / %d" % [player.aperture_count(), player.capacity()], Vector2(430.0, 92.0),
			Color(0.72, 0.76, 0.80), 16)
	# ⭐ 提示要写清「怎么换印」—— 之前换印只有「按 Q 再按数字键」一条暗路，没人找得到。
	var hint := "点空窍里的印 = 选中它   ·   备用印会多出一个「换上」按钮"
	if step == 1:
		hint = "点左下「炼化」花 %.0f 灵力，把它往『能用』推一格（不再吃材料）" % float(GameData.REFINE["press_cost"])
		if not player.reserve_seals.is_empty():
			hint += "   ·   Q 换印"
	if step == 2:
		hint = "换印：点空窍里的备用印，或直接按数字键   ·   Q 返回"
	_text(hint, Vector2(182.0, 120.0), Color(0.72, 0.76, 0.80), 14)
	_text("再按 Tab 关闭", Vector2(182.0, 140.0), Color(0.52, 0.56, 0.60), 12)

	# ---- 左：空窍（球）----
	dbg_mark = "orb"
	_draw_orb()
	dbg_mark = "info"
	var pct: int = int(round(100.0 * clampf(player.essence / maxf(player.essence_max, 1.0), 0.0, 1.0)))
	_text("灵力 %d / %d   %d%%" % [int(player.essence), int(player.essence_max), pct],
			orb_center() + Vector2(-orb_radius(), orb_radius() + 34.0), Color(0.68, 0.86, 0.98), 15)
	_text("球越大 = 灵力容量越大（境界 / 小境界 / 印的基础属性都会撑大空窍）",
			orb_center() + Vector2(-orb_radius(), orb_radius() + 56.0), Color(0.50, 0.54, 0.60), 12)

	# ---- 中：选中印的详情（老界面把这些信息摊在每一行，现在挪到这一栏）----
	_draw_seal_info()
	dbg_mark = "bag"

	# ---- 右：背包（未炼化的印 + 材料）----
	_draw_bag()
	dbg_mark = "bottom"

	# ---- 下：修为 + 修炼 / 突破 ----
	var cmax: float = player.cultivation_max()
	var ratio: float = clampf(player.cultivation / maxf(cmax, 0.001), 0.0, 1.0)
	var ready: bool = player.can_breakthrough()
	_text("修为 %d / %d   %s %d/4%s" % [int(player.cultivation), int(cmax), player.sub_name(),
			player.sub() + 1, "   可突破" if ready else ""],
			Vector2(180.0, 616.0), Color(0.92, 0.96, 0.86) if ready else Color(0.76, 0.80, 0.86), 15)
	draw_rect(Rect2(Vector2(180.0, 624.0), Vector2(518.0, 9.0)), Color(0.16, 0.18, 0.22))
	draw_rect(Rect2(Vector2(180.0, 624.0), Vector2(518.0 * ratio, 9.0)),
			Color(0.74, 0.90, 0.98) if ready else Color(0.40, 0.56, 0.76))

	var br := cultivate_rect()
	var cul_ok: bool = can_cultivate()
	_text("修炼", br.position + Vector2(16.0, 28.0),
			Color(0.88, 0.95, 1.0) if cul_ok else Color(0.44, 0.48, 0.52), 16)
	_text("-%d 灵力 → +%d 修为" % [int(GameData.CULTIVATE["per_press"]), int(GameData.CULTIVATE["gain"])],
			br.position + Vector2(66.0, 28.0),
			Color(0.66, 0.72, 0.78) if cul_ok else Color(0.42, 0.46, 0.50), 12)
	draw_rect(br, Color(0.72, 0.88, 0.98, 0.70 if cul_ok else 0.18), false, 2.0)

	var bb := breakthrough_rect()
	var bt_ok: bool = can_breakthrough_now()
	_text("突破", bb.position + Vector2(16.0, 28.0),
			Color(0.99, 0.94, 0.70) if bt_ok else Color(0.46, 0.48, 0.50), 16)
	_text("境界 → 下一重" if bt_ok else "修为攒满才亮", bb.position + Vector2(66.0, 28.0),
			Color(0.80, 0.76, 0.58) if bt_ok else Color(0.42, 0.46, 0.50), 12)
	draw_rect(bb, Color(0.98, 0.90, 0.55, 0.85 if bt_ok else 0.16), false, 2.0)

	# ---- 炼化按钮（炼的是背包里选中的那枚）----
	_draw_refine_button()

	if _msg != "":
		_text(_msg, Vector2(786.0, 706.0), Color(0.88, 0.92, 0.72), 14)
	dbg_mark = "done"
	dbg_frames += 1
## 空窍：一颗球。⭐ 半径 = 灵力**容量**；球里的"丰盈程度" = 当前灵力 / 容量。
func _draw_orb() -> void:
	var c := orb_center()
	var r := orb_radius()
	var fill: float = clampf(player.essence / maxf(player.essence_max, 1.0), 0.0, 1.0)
	var t := float(Time.get_ticks_msec()) * 0.001
	for k in range(3):
		draw_circle(c, r + 8.0 + 10.0 * float(k), Color(0.40, 0.66, 0.88, 0.055 - 0.014 * float(k)))
	draw_circle(c, r, Color(0.04, 0.07, 0.11, 0.94))
	var surface: float = c.y + r * (1.0 - 2.0 * fill)
	# 灵气：逐行扫在圆内（比一个矩形更贴合球体），液面越高 = 灵力越满
	for i in range(34):
		var fy: float = c.y - r + (r * 2.0) * (float(i) + 0.5) / 34.0
		if fy < surface:
			continue
		var dy: float = fy - c.y
		var half: float = sqrt(maxf(0.0, r * r - dy * dy))
		var wob: float = sin(fy * 0.07 + t * 1.3) * 2.0
		draw_line(Vector2(c.x - half * 0.99, fy + wob), Vector2(c.x + half * 0.99, fy + wob),
				Color(0.30, 0.62, 0.90, 0.09 + 0.13 * fill))
	# 液面：一条会起伏的线（只在圆内）
	var dys: float = surface - c.y
	if absf(dys) < r - 3.0:
		var hs: float = sqrt(maxf(0.0, r * r - dys * dys))
		var pts := PackedVector2Array()
		for i in range(21):
			var fx: float = c.x - hs + (hs * 2.0) * float(i) / 20.0
			pts.append(Vector2(fx, surface + sin(float(i) * 0.6 + t * 1.7) * 3.0))
		draw_polyline(pts, Color(0.66, 0.92, 1.0, 0.50), 1.6)
	# 几团柔和的"气"：先铺大而淡的，再撒小亮点，合起来才像气体而不是星尘
	for k in range(5):
		var fa := float(k) * 1.7 + t * 0.25
		var fpos: Vector2 = c + Vector2(cos(fa), sin(fa * 1.3)) * r * (0.26 + 0.12 * float(k))
		draw_circle(fpos, r * 0.30, Color(0.34, 0.68, 0.94, 0.030 + 0.020 * fill))
	# 灵气粒子（气体感）
	for p in _gas_particles():
		draw_circle(p["pos"], float(p["r"]), Color(0.72, 0.93, 1.0, float(p["alpha"])))
	# 球壁
	draw_arc(c, r, 0.0, TAU, 72, Color(0.56, 0.82, 0.99, 0.55), 2.0)
	draw_arc(c, r - 3.5, 0.0, TAU, 72, Color(0.56, 0.82, 0.99, 0.16), 1.0)
	# 活跃槽里"占了位但还没融合"的印：在球底画个虚位，免得玩家以为键坏了
	for i in range(player.slot_seal.size()):
		var nk := str(player.slot_seal[i])
		if nk == "" or player.is_refined(nk):
			continue
		var at := Vector2(c.x - 26.0 * float(player.slot_seal.size() - 1) * 0.5 + 26.0 * float(i),
				c.y + r * 0.72)
		draw_arc(at, 10.0, 0.0, TAU, 16, Color(0.62, 0.42, 0.38, 0.60), 1.5)
		_text("%d 未炼化" % (i + 1), at + Vector2(-22.0, 26.0), Color(0.72, 0.50, 0.46), 11)
	# ⭐ M22：能配出印诀的两枚印之间画一条发光连线 —— 让"印配印"看得见
	var keys_link := orb_seals()
	for link in combo_links():
		var pa: Vector2 = orb_seal_pos(int(link["a"]), keys_link.size())
		var pb: Vector2 = orb_seal_pos(int(link["b"]), keys_link.size())
		var t2 := float(Time.get_ticks_msec()) * 0.001
		draw_line(pa, pb, Color(0.98, 0.86, 0.52, 0.28 + 0.22 * sin(t2 * 2.2)), 2.0)
		var nm := str(link["name"])
		_text(nm, (pa + pb) * 0.5 + Vector2(-float(nm.length()) * 6.0, -8.0),
				Color(0.99, 0.92, 0.64), 12)
	# 空窍里的印（浮在灵气里）
	var keys := orb_seals()
	for i in range(keys.size()):
		_draw_orb_seal(str(keys[i]), i, keys.size())


## 一枚浮动印的位置。⭐ 画和点共用它，不然会错位。
func orb_seal_pos(i: int, n: int) -> Vector2:
	var t := float(Time.get_ticks_msec()) * 0.001
	var ang: float = -PI * 0.5 + TAU * float(i) / maxf(1.0, float(n)) + t * 0.10
	var rr: float = orb_radius() * (0.50 if n <= 4 else 0.62)
	return (orb_center() + Vector2(cos(ang), sin(ang)) * rr
			+ Vector2(0.0, sin(t * 1.2 + float(i) * 1.9) * 6.0))


## 空窍里的一枚印：形状 + 名字 +（活跃槽的话）槽位号。
func _draw_orb_seal(nk: String, i: int, n: int) -> void:
	var d: Dictionary = GameData.SEALS[nk]
	var col: Color = d["color"]
	var t := float(Time.get_ticks_msec()) * 0.001
	var at := orb_seal_pos(i, n)
	var slot: int = player.slot_seal.find(nk)
	var usable: Dictionary = player.can_use(nk)
	if nk == selected_name:
		draw_circle(at, 21.0, Color(0.92, 0.88, 0.60, 0.16))
		draw_arc(at, 19.0, 0.0, TAU, 24, Color(0.96, 0.90, 0.62, 0.80), 1.6)
	var body_col: Color = col if bool(usable["ok"]) else Color(col.r * 0.5, col.g * 0.5, col.b * 0.5, 0.95)
	_draw_shape(at, 13.5, str(d.get("shape", "hex")), body_col, t * 0.4 + float(i))
	if slot >= 0:
		draw_circle(at + Vector2(14.0, -14.0), 8.0, Color(0.10, 0.12, 0.15, 0.95))
		_text("%d" % (slot + 1), at + Vector2(10.0, -9.0), Color(0.94, 0.96, 0.82), 12)
	if not bool(usable["ok"]):
		_text("封", at + Vector2(-6.0, 6.0), Color(0.98, 0.66, 0.62), 13)
	# 印名：先画一层深色底影，再画亮色 —— 不然压在灵气上读不清（截图里验证过）
	_text(nk, at + Vector2(-float(nk.length()) * 6.0 + 1.0, 37.0), Color(0.02, 0.03, 0.05, 0.85), 12)
	_text(nk, at + Vector2(-float(nk.length()) * 6.0, 36.0), Color(0.90, 0.93, 0.97), 12)


## 灵气粒子：全部由「时间 + 固定相位」算出来，不存状态。
func _gas_particles() -> Array:
	var out_p: Array = []
	var c := orb_center()
	var r := orb_radius()
	var fill: float = clampf(player.essence / maxf(player.essence_max, 1.0), 0.0, 1.0)
	var t := float(Time.get_ticks_msec()) * 0.001
	for i in range(52):
		var fi := float(i)
		var ph: float = fi * 2.399963
		var sp: float = 0.18 + 0.50 * fmod(fi * 0.37, 1.0)
		var rr: float = sqrt(fmod(fi * 0.618 + 0.13, 1.0)) * 0.94
		var ang: float = ph + t * sp * 0.30
		var wob: float = sin(t * (0.5 + 0.6 * fmod(fi * 0.29, 1.0)) + ph) * 0.05
		out_p.append({"pos": c + Vector2(cos(ang), sin(ang)) * (rr + wob) * r,
				"r": 1.3 + 2.4 * fmod(fi * 0.53, 1.0),
				"alpha": (0.10 + 0.32 * fmod(fi * 0.41, 1.0)) * (0.30 + 0.70 * fill)})
	return out_p


## 印的形状（M21，先简化成几何图形）。⭐ 形状 = 一眼认出是哪个印，比读名字快。
func _shape_points(shape: String) -> PackedVector2Array:
	match shape:
		"claw":
			return PackedVector2Array([Vector2(-0.95, 0.75), Vector2(-0.40, -0.95), Vector2(0.0, 0.05),
					Vector2(0.40, -0.95), Vector2(0.95, 0.75), Vector2(0.0, 0.30)])
		"hex":
			var h := PackedVector2Array()
			for k in range(6):
				var a: float = PI / 6.0 + TAU * float(k) / 6.0
				h.append(Vector2(cos(a), sin(a)))
			return h
		"bolt":
			# ⚠️ 第一版写了个自交的闪电折线 → draw_colored_polygon 失败，把整个界面画布中断在
			#    背包那一栏（截图里就是"右半边全黑"）。改成不自交的箭头：先简化，稳比对更要紧。
			return PackedVector2Array([Vector2(-0.72, -0.85), Vector2(0.72, -0.85), Vector2(0.0, 1.0)])
		"square":
			return PackedVector2Array([Vector2(-0.85, -0.85), Vector2(0.85, -0.85),
					Vector2(0.85, 0.85), Vector2(-0.85, 0.85)])
		"drop":
			return PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.62, -0.05), Vector2(0.42, 0.62),
					Vector2(0.0, 0.92), Vector2(-0.42, 0.62), Vector2(-0.62, -0.05)])
		"leaf":
			return PackedVector2Array([Vector2(0.0, -1.0), Vector2(0.55, -0.10), Vector2(0.0, 1.0),
					Vector2(-0.55, -0.10)])
		"star":
			var s := PackedVector2Array()
			for k in range(10):
				var a2: float = -PI * 0.5 + TAU * float(k) / 10.0
				var rad: float = 1.0 if k % 2 == 0 else 0.45
				s.append(Vector2(cos(a2), sin(a2)) * rad)
			return s
	return PackedVector2Array([Vector2(-0.8, -0.8), Vector2(0.8, -0.8), Vector2(0.8, 0.8), Vector2(-0.8, 0.8)])


func _draw_shape(at: Vector2, size_px: float, shape: String, col: Color, rot: float) -> void:
	var pts := _shape_points(shape)
	if pts.is_empty():
		return
	var moved := PackedVector2Array()
	for p in pts:
		moved.append(at + p.rotated(rot) * size_px)
	# ⚠️ 自交 / 凹多边形的三角化可能失败。失败了就**只描边** ——
	#    绝不能让一个坏形状把整个 _draw() 中断掉（踩过：右半边界面整块消失）。
	if Geometry2D.triangulate_polygon(moved).is_empty():
		for k2 in range(moved.size()):
			draw_line(moved[k2], moved[(k2 + 1) % moved.size()], Color(col.r, col.g, col.b, 0.92), 1.6)
		return
	draw_colored_polygon(moved, col)
	for k in range(moved.size()):
		draw_line(moved[k], moved[(k + 1) % moved.size()], Color(col.r, col.g, col.b, 0.85), 1.2)


## 中栏：选中那枚印的详情（名字 / 品阶 / 炼化度 / 状态 / 被动 / 永久基础属性）。
func _draw_seal_info() -> void:
	var r := Rect2(Vector2(534.0, 150.0), Vector2(222.0, 300.0))
	draw_rect(r, Color(0.06, 0.07, 0.09, 0.72))
	draw_rect(r, Color(0.26, 0.30, 0.36, 0.60), false, 1.5)
	var nk := current_seal()
	if nk == "" or not GameData.SEALS.has(nk):
		_text("印 的 详 情", r.position + Vector2(14.0, 28.0), Color(0.60, 0.64, 0.70), 15)
		_text("点左边的空窍，", r.position + Vector2(14.0, 62.0), Color(0.46, 0.50, 0.56), 13)
		_text("或右边的背包。", r.position + Vector2(14.0, 82.0), Color(0.46, 0.50, 0.56), 13)
		return
	var d: Dictionary = GameData.SEALS[nk]
	# ⚠️ 先把所有要写的字**算完**，再开始画。
	#    踩过：_base_text(d) 传错参数（它要的是 base 子字典）→ 里面 b["stat"] 报错 →
	#    这个函数在**已经画了一部分之后**抛出 → 整个 _draw() 从那里中断 → 背包整栏空白。
	#    算完再画，至少数据错的时候界面还是完整的。
	var col: Color = d["color"]
	var shape := str(d.get("shape", "hex"))
	var rank_txt: String = str(GameData.RANKS[int(d["rank"])])
	var usable: Dictionary = player.can_use(nk)
	var usable_ok: bool = bool(usable["ok"])
	var state_s := "已融合 · 可用" if usable_ok else str(usable["reason"])
	var refine_txt := "炼化 %d%%" % int(player.refine_of(nk))
	var passive_txt := "显化时：" + _passive_text(d)
	var base_txt := "融合后永久：" + _base_text(d.get("base", {}))
	var move_txt := "身法：养熟它 → 学会「冲刺」" if str(d.get("move", "")) != "" else ""
	var slot_txt := "槽位：" + ("活跃槽 %d" % (player.slot_seal.find(nk) + 1)
			if player.slot_seal.has(nk) else "备用 —— 点下面的「换上」按钮")
	# ---- 以下只有绘制 ----
	_draw_shape(r.position + Vector2(24.0, 28.0), 11.0, shape, col, 0.0)
	_text(nk, r.position + Vector2(44.0, 33.0), Color(0.92, 0.94, 0.86), 17)
	_text(rank_txt, r.position + Vector2(14.0, 60.0), Color(0.66, 0.70, 0.76), 13)
	_text(refine_txt, r.position + Vector2(14.0, 86.0), Color(0.78, 0.86, 0.94), 14)
	_text(state_s, r.position + Vector2(14.0, 108.0),
			Color(0.62, 0.82, 0.64) if usable_ok else Color(0.86, 0.62, 0.56), 13)
	_text(passive_txt, r.position + Vector2(14.0, 142.0), Color(0.74, 0.80, 0.88), 13)
	_text(base_txt, r.position + Vector2(14.0, 168.0), Color(0.80, 0.76, 0.60), 13)
	if move_txt != "":
		_text(move_txt, r.position + Vector2(14.0, 198.0), Color(0.62, 0.88, 0.96), 13)
	_text(slot_txt, r.position + Vector2(14.0, 234.0), Color(0.62, 0.66, 0.72), 13)
	# 备用印：给一个看得见的「换上」按钮（换印不该只有「Q + 数字键」这一条暗路）
	if can_swap_selected():
		var sb := swap_target_rect()
		draw_rect(sb, Color(0.11, 0.16, 0.13, 0.96))
		draw_rect(sb, Color(0.62, 0.88, 0.72, 0.85), false, 2.0)
		_text("换上活跃槽 %d" % (seal_index + 1), sb.position + Vector2(14.0, 23.0),
				Color(0.82, 0.96, 0.86), 14)


## 「换上活跃槽 N」按钮的布局（选中一枚**备用**印时出现在详情栏底部）。
## ⭐ 换印以前只有「按 Q 再按数字键」一条路，藏得太深 —— 现在变成看得见、点得到的按钮。
func swap_target_rect() -> Rect2:
	return Rect2(Vector2(548.0, 400.0), Vector2(194.0, 34.0))


func can_swap_selected() -> bool:
	if player == null:
		return false
	var nk := current_seal()
	return nk != "" and not player.slot_seal.has(nk) and player.has_seal(nk)


func do_swap_selected() -> bool:
	if not can_swap_selected():
		_msg = "这枚印不在你手上，换不了"
		queue_redraw()
		return false
	var nk := current_seal()
	# ⭐ M29.5：备用里的印走老路；**背包里的印**直接换上活跃槽（换下来的回背包）
	if player.reserve_seals.has(nk):
		return swap(player.reserve_seals.find(nk))
	if player.swap_in_bag_seal(seal_index, nk):
		_msg = "第 %d 格：换上背包里的 %s" % [seal_index + 1, nk]
		step = 1
		queue_redraw()
		return true
	_msg = "命窍装不下（%d / %d 都占着），先把一枚放回背包" % [player.aperture_count(), player.capacity()]
	queue_redraw()
	return false


## 空窍里**能配出印诀**的印对：[{a, b, name}]（a/b 是 orb_seals() 下标）。
## ⭐ 界面和自测共用它 —— 不然"画出来的连线"和"真放得出的印诀"会对不上。
func combo_links() -> Array:
	var out_links: Array = []
	var keys := orb_seals()
	for i in range(keys.size()):
		for j in range(i + 1, keys.size()):
			var k: String = GameData.combo_key(str(keys[i]), str(keys[j]))
			if GameData.COMBOS.has(k):
				out_links.append({"a": i, "b": j, "name": str(GameData.COMBOS[k]["name"])})
	return out_links


## 右侧背包：未炼化的印 + 材料。
func _draw_bag() -> void:
	var r := bag_rect()
	draw_rect(r, Color(0.06, 0.07, 0.09, 0.92))
	draw_rect(r, Color(0.30, 0.34, 0.40, 0.75), false, 1.5)
	_text("背包", r.position + Vector2(18.0, 30.0), Color(0.86, 0.88, 0.92), 20)
	_text("未炼化的印 · 材料", r.position + Vector2(92.0, 30.0), Color(0.56, 0.60, 0.66), 13)
	var entries := bag_entries()
	if entries.is_empty():
		_text("（空的 —— 去采点东西，或者打死灵师抢一枚印）", r.position + Vector2(18.0, 74.0),
				Color(0.46, 0.50, 0.56), 13)
		return
	var y0: float = r.position.y + 54.0
	for i in range(entries.size()):
		var e: Dictionary = entries[i]
		var y: float = y0 + 34.0 * float(i)
		if y > r.position.y + r.size.y - 24.0:
			_text("…还有 %d 项" % (entries.size() - i), Vector2(r.position.x + 18.0, y),
					Color(0.50, 0.54, 0.60), 12)
			break
		if str(e["kind"]) == "seal":
			var nk := str(e["name"])
			if nk == selected_name:
				draw_rect(Rect2(Vector2(r.position.x + 8.0, y - 20.0), Vector2(r.size.x - 16.0, 30.0)),
						Color(0.92, 0.88, 0.60, 0.12))
			var d: Dictionary = GameData.SEALS[nk]
			_draw_shape(Vector2(r.position.x + 28.0, y - 6.0), 9.0, str(d.get("shape", "hex")), d["color"], 0.0)
			_text("%s   %s   炼化 %d%%   未融合（不能用）" % [nk, GameData.RANKS[int(d["rank"])],
					int(player.refine_of(nk))], Vector2(r.position.x + 48.0, y), Color(0.88, 0.82, 0.76), 14)
		else:
			var mname := str(e["name"])
			# ⭐ M30.5b：材料行画图标（没图就还是那个 ◆）
			var mtex := ActorVisual.texture_of(GameData.item_visual(mname))
			if mtex != null:
				ActorVisual.draw_icon(self, mtex, Vector2(r.position.x + 30.0, y - 6.0))
				_text("%s   ×%d" % [mname, int(player.bag.items.get(mname, 0))],
						Vector2(r.position.x + 48.0, y), Color(0.78, 0.84, 0.90), 14)
			else:
				_text("◆  %s   ×%d" % [mname, int(player.bag.items.get(mname, 0))],
						Vector2(r.position.x + 48.0, y), Color(0.78, 0.84, 0.90), 14)


## 炼化按钮：炼的是**背包里选中的**那枚未融合的印。
func _draw_refine_button() -> void:
	var rb := refine_rect()
	var nk_sel := current_seal()
	var ref_ok: bool = can_refine_now()
	draw_rect(rb, Color(0.12, 0.14, 0.16, 0.96))
	if nk_sel == "":
		_text("点背包里那枚未炼化的印，才能炼化", rb.position + Vector2(16.0, 30.0),
				Color(0.52, 0.56, 0.60), 14)
		return
	if player.is_refined(nk_sel):
		_text("%s   已融合 %d%%   完全可用" % [nk_sel, int(player.refine_of(nk_sel))],
				rb.position + Vector2(16.0, 30.0), Color(0.66, 0.82, 0.66), 15)
		return
	draw_rect(rb, Color(0.72, 0.88, 0.98, 0.85 if ref_ok else 0.22), false, 2.0)
	_text("炼化  %s   %d%%   -%d 灵力 → +%d%%" % [nk_sel, int(player.refine_of(nk_sel)),
			int(GameData.REFINE["press_cost"]), int(GameData.REFINE["press_gain"])],
			rb.position + Vector2(16.0, 30.0),
			Color(0.88, 0.95, 1.0) if ref_ok else Color(0.48, 0.52, 0.56), 15)
func _passive_text(d: Dictionary) -> String:
	var kind := str(d["passive"])
	var v := float(d.get("passive_value", 1.0))
	match kind:
		"attack_damage":
			return "普攻伤害 +%d" % int(v)
		"damage_taken":
			return "受伤 ×%.2f" % v
		"attack_cooldown":
			return "普攻冷却 ×%.2f" % v
	return kind


func _base_text(b: Dictionary) -> String:
	if b.is_empty():
		return "（无）"
	var stat := str(b["stat"])
	var v := float(b["value"])
	match stat:
		"hp_max":
			return "气血上限 +%d（永久）" % int(v)
		"essence_max":
			return "灵力上限 +%d（永久）" % int(v)
		"attack_damage":
			return "普攻伤害 +%d（永久）" % int(v)
		"attack_cooldown":
			return "普攻冷却 ×%.2f（永久）" % v
		"move_speed":
			return "移速 +%d（永久）" % int(v)
	return stat


func _text(s: String, at: Vector2, col: Color, px: int) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
