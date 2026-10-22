extends Control
## 屏幕层 HUD。
##
## ⭐ 为什么搬到 Control 层：气血 / 灵力 / 命窍是「玩家的状态」，不是「世界里的东西」。
##    画在世界坐标里，一改分辨率或日后加 Camera2D 就会错位；画在 Control 层则永远贴着屏幕。
##
## ⚠️ Control 的 _draw() 用的是屏幕坐标（左上角 = 0,0），别再拿世界坐标往里塞。

var game: Node = null            # 由 Game._ready() 接线
var _notice := ""                # 一句话提示（几秒后自己消失）
var _notice_left := 0.0

var _font: Font = null


func _ready() -> void:
	_font = GameData.make_font()


func _process(_delta: float) -> void:
	if _notice_left > 0.0:
		_notice_left = maxf(0.0, _notice_left - _delta)
		if _notice_left <= 0.0:
			_notice = ""
	queue_redraw()               # 数值每帧都在变，直接重画；这点开销可以忽略


## 一句话提示（锚点挪了、突破成功之类）。
func notice(text: String, secs := 3.5) -> void:
	_notice = text
	_notice_left = secs
	queue_redraw()


## 结印进度条（M26）：⭐ 窗口和"填了什么"必须看得见 —— 否则结印就是个盲操作。
func _draw_sealing(p) -> void:
	var win: float = p.combo_window()
	var left: float = clampf(p.seal_window_left / maxf(win, 0.01), 0.0, 1.0)
	var w := 240.0
	var x: float = size.x * 0.5 - w * 0.5
	var y: float = size.y - 196.0
	draw_rect(Rect2(Vector2(x, y), Vector2(w, 8.0)), Color(0.10, 0.11, 0.14, 0.92))
	draw_rect(Rect2(Vector2(x, y), Vector2(w * left, 8.0)), Color(0.98, 0.86, 0.52, 0.95))
	_text("结 印", Vector2(x - 40.0, y + 8.0), Color(0.94, 0.90, 0.70), 14)
	var at_x := x
	for nk in p.seal_input:
		var col: Color = GameData.SEALS[str(nk)]["color"]
		draw_circle(Vector2(at_x + 8.0, y + 24.0), 5.0, col)
		_text(str(nk), Vector2(at_x + 17.0, y + 29.0), Color(0.88, 0.90, 0.94), 13)
		at_x += 22.0 + float(str(nk).length()) * 13.0
	if p.seal_input.size() < 2:
		_text("数字键填入两枚印（还剩 %.1f 秒）" % p.seal_window_left,
				Vector2(x + w + 12.0, y + 29.0), Color(0.68, 0.72, 0.78), 13)


## ⚠️ M19：锚点机制移除 —— `world_to_screen()` / `_draw_anchor()` / `_clamp_label()` 全部删除。
##    它们存在的唯一目的就是"告诉玩家锚点在哪"，现在没有锚点了。


func _draw() -> void:
	if game == null or game.player == null:
		return
	var p = game.player

	_draw_notice()

	# ---- 左下：气血 + 灵力 ----
	var x := 24.0
	var y := size.y - 84.0

	# 护盾条：只在有盾时出现（磐石印那种一次性防御给的）
	if p.shield > 0.0:
		_bar(Rect2(x, y, 240.0, 12.0), p.shield / maxf(p.shield_max, 0.001), Color(0.60, 0.70, 0.55))
		_text("护盾 %d" % int(p.shield), Vector2(x + 250.0, y + 11.0))
		y += 22.0

	_bar(Rect2(x, y, 240.0, 14.0), p.hp / maxf(p.hp_max, 0.001), Color(0.85, 0.30, 0.30))
	_text("气血 %d / %d" % [int(p.hp), int(p.hp_max)], Vector2(x + 250.0, y + 12.0))
	y += 22.0
	_bar(Rect2(x, y, 240.0, 10.0), p.essence / maxf(p.essence_max, 0.001),
			Color(0.45, 0.80, 0.85))
	# ⭐ 突破是局内收获：没钉锚就明确写出来，别让玩家以为「境界凭空没了」
	var unbanked: bool = game.unbanked_realm()
	_text("灵力 %d / %d   %s · %s%s" % [int(p.essence), int(p.essence_max), p.realm_name(),
			p.sub_name(), "（未存档 · 死亡退回上次存档）" if unbanked else ""],
			Vector2(x + 250.0, y + 10.0),
			Color(0.95, 0.80, 0.45) if unbanked else Color(0.90, 0.88, 0.84))
	y += 22.0

	# 修为：⭐ 进度条，花不掉；满了就把「可突破」写在脸上
	var cmax: float = p.cultivation_max()
	var ready: bool = p.can_breakthrough()
	_bar(Rect2(x, y, 240.0, 10.0), p.cultivation / maxf(cmax, 0.001),
			Color(0.74, 0.90, 0.98) if ready else Color(0.40, 0.56, 0.76))
	_text("修为 %d / %d   %s %d/4%s" % [int(p.cultivation), int(cmax), p.sub_name(), p.sub() + 1,
			"   可突破（Tab 命窍）" if ready else ""],
			Vector2(x + 250.0, y + 10.0),
			Color(0.92, 0.96, 0.86) if ready else Color(0.70, 0.74, 0.80))

	# ---- 底部中间：三个命窍槽位 ----
	var n: int = p.slot_seal.size()
	var gap := 104.0
	var start := size.x * 0.5 - gap * float(n - 1) * 0.5
	for i in range(n):
		_draw_slot(Vector2(start + gap * float(i), size.y - 78.0), i, p)

	# ---- 灵印挨打：屏幕边缘同色裂纹（玩家不用盯血条）----
	_draw_edge_cracks(p)

	# ---- 底部中间：一句话提示 ----
	# ⚠️ M19：锚点机制移除 —— 「E 突破」那条提示没了（突破只在 Tab 命窍面板里做）
	# ⭐ 提示只在「真的能做」时出现 —— 判定和实际交互共用同一个函数
	# ⭐ 印诀（M26）：正在结印 → 画进度条；否则只报"最近那一门在冷却"。
	if p.is_sealing():
		_draw_sealing(p)
	elif str(p.last_combo_key) != "" and p.combo_cd_for(str(p.last_combo_key)) > 0.0:
		_text("印诀 · %s   冷却 %.1fs" % [str(GameData.COMBOS[p.last_combo_key]["name"]),
				p.combo_cd_for(str(p.last_combo_key))],
				Vector2(size.x * 0.5 - 96.0, size.y - 152.0), Color(0.62, 0.66, 0.72), 14)
	elif game.merchant != null and is_instance_valid(game.merchant) \
			and p.position.distance_to(game.merchant.position) <= game.merchant.reach():
		_text("E   交易", Vector2(size.x * 0.5 - 30.0, size.y - 124.0), Color(0.94, 0.84, 0.52), 16)
	elif game.has_method("nearest_gather") and game.nearest_gather(p.position) != null:
		_text("E   采集", Vector2(size.x * 0.5 - 30.0, size.y - 124.0), Color(0.55, 0.85, 0.95), 16)
	elif p.can_breakthrough():
		_text("修为已满 —— Tab 命窍 → 点「突破」", Vector2(size.x * 0.5 - 130.0, size.y - 124.0),
				Color(0.96, 0.86, 0.52), 15)
	else:
		# ⭐ 文案跟着数据走 —— 改 autosave_sec 不用再来改界面
		var auto_secs := float(GameData.ANCHOR["autosave_sec"])
		## ⚠️ M33：`0` = 自动存档**关闭**（用户定案）。这时**什么都不显示** ——
		##    写「每 0 秒自动存档」是句假话，写「已关闭」又是在屏幕上挂一条常驻说明。
		##    界面不撒谎的方式只有一种：没有这回事，就不画它。
		if auto_secs > 0.0:
			var auto_note := "每 %d 秒自动存档" % int(auto_secs)
			if auto_secs >= 60.0:
				auto_note = "每 %d 分钟自动存档" % int(round(auto_secs / 60.0))
			_text(auto_note, Vector2(size.x * 0.5 - 56.0, size.y - 124.0),
					Color(0.62, 0.66, 0.72), 14)

	# ---- 物品（M8）----
	_draw_bag(p)

	# 刚捡到东西的提示
	if str(game.pickup_toast) != "":
		_text(_pickup_toast_text(str(game.pickup_toast), p), Vector2(size.x * 0.5 - 52.0, size.y - 158.0),
				Color(0.86, 0.90, 0.70), 15)
	if bool(game.bag_full_hint):
		var why := "这一枚你已经有了" if bool(game.seize_dup_hint) else "背包已满 —— 东西留在地上"
		_text(why, Vector2(size.x * 0.5 - 90.0, size.y - 182.0), Color(0.92, 0.60, 0.45), 15)


func _draw_slot(center: Vector2, i: int, p) -> void:
	var seal_name := str(p.slot_seal[i])
	var summoned = p.slot_summoned[i]
	var damaged := float(p.slot_damaged[i]) > 0.0

	var col := Color(0.30, 0.32, 0.36)                      # 未显化 = 灰
	if summoned != null:
		col = GameData.SEALS[seal_name]["color"]              # 显化中 = 灵印自己的颜色
	elif damaged or seal_name == "":
		col = Color(0.28, 0.22, 0.22)                        # 受损 / 已永久死亡 = 暗红

	draw_circle(center, 16.0, col)
	draw_arc(center, 16.0, 0.0, TAU, 24, Color(0.10, 0.11, 0.13), 2.0)
	_text(str(i + 1), center + Vector2(-5.0, 6.0), Color(0.95, 0.95, 0.95), 16)
	if seal_name != "":
		# ⭐ 连部位一起写出来：玩家一眼知道这枚印贴在身上哪个地方
		var part := str(GameData.SEALS[seal_name]["body_part"])
		_text("%s·%s" % [seal_name, part], center + Vector2(-38.0, 34.0), Color(0.78, 0.78, 0.80), 12)
	else:
		_text("已消散", center + Vector2(-20.0, 34.0), Color(0.55, 0.40, 0.40), 12)
	if damaged:
		_text("%ds" % int(p.slot_damaged[i]), center + Vector2(-14.0, -24.0), Color(0.90, 0.45, 0.40), 12)

	# 显化中：把「它现在在干什么」写出来（状态由灵印自己回答）
	if summoned != null and is_instance_valid(summoned):
		var st: String = summoned.state_text()
		var stcol := Color(0.85, 0.90, 0.95)
		if summoned.is_dying():
			stcol = Color(0.95, 0.45, 0.40)
			st += "·濒死"
		_text(st, center + Vector2(-26.0, -28.0), stcol, 12)


## 屏幕边缘的裂纹：哪枚灵印在挨打，就用它的颜色在屏幕边上闪一圈。
## ⭐ 注意这里用的是**屏幕坐标**（Control 层），和世界坐标无关 —— 这正是把 HUD 搬上来的理由。
## 右上角：灵石 + 背包占用 + 材料清单（按数量从多到少，最多 5 种）。
## ⭐ 材料一律画成**小菱形**，和地上的掉落物同一个形状 —— 看到形就知道是什么。
func _draw_bag(p) -> void:
	var bag = p.bag
	if bag == null:
		return
	var x := size.x - 190.0
	var y := 18.0
	_text("灵石 %d" % bag.stones, Vector2(x, y), Color(0.92, 0.82, 0.45), 15)
	y += 20.0
	_text("背包容积 %d / %d" % [bag.capacity_used(), int(GameData.BAG_CAPACITY)], Vector2(x, y),
			Color(0.72, 0.76, 0.80), 13)
	y += 22.0

	for name_key in bag.top_items(5):
		var col: Color = GameData.MATERIALS[name_key]["color"]
		var c := Vector2(x + 6.0, y - 4.0)
		# ⭐ M30.5b：有 8×8 token 就画它，没图还是那个小菱形
		var dtex := ActorVisual.texture_of(GameData.item_drop_visual(name_key))
		if dtex != null:
			ActorVisual.draw_icon(self, dtex, c)
		else:
			var s := 5.0
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0.0, -s), c + Vector2(s, 0.0), c + Vector2(0.0, s), c + Vector2(-s, 0.0)]), col)
		_text("%s ×%d" % [name_key, bag.count(name_key)], Vector2(x + 18.0, y), Color(0.80, 0.82, 0.84), 13)
		y += 19.0

	_text("命窍 %d / %d    Tab 命窍 · F 开炉" % [p.aperture_count(), p.capacity()],
			Vector2(x, y + 10.0), Color(0.62, 0.66, 0.72), 12)
	if not p.reserve_seals.is_empty():
		_text("备用 ×%d" % p.reserve_seals.size(), Vector2(x, y + 26.0), Color(0.55, 0.60, 0.66), 11)
	if not p.bag_seals.is_empty():
		# ⭐ M29.5：收藏无上限 —— 命窍装不下的印都在背包里
		_text("背包里的印 ×%d" % p.bag_seals.size(), Vector2(x, y + 42.0), Color(0.72, 0.66, 0.52), 11)


func _draw_edge_cracks(p) -> void:
	for i in range(p.slot_hurt.size()):
		var t: float = float(p.slot_hurt[i])
		if t <= 0.0:
			continue
		var col: Color = GameData.SEALS[str(p.slot_seal[i])]["color"]
		var a := clampf(t / 0.4, 0.0, 1.0) * 0.75
		var line_col := Color(col.r, col.g, col.b, a)
		var inset := 6.0
		draw_rect(Rect2(Vector2(inset, inset), size - Vector2(inset * 2.0, inset * 2.0)),
				line_col, false, 4.0)
		for k in range(3):
			var f := (float(k) + 0.5) / 3.0
			var x := size.x * f
			var y := size.y * f
			draw_line(Vector2(x, inset), Vector2(x + 10.0, inset + 26.0), line_col, 2.0)
			draw_line(Vector2(x, size.y - inset), Vector2(x - 10.0, size.y - inset - 26.0), line_col, 2.0)
			draw_line(Vector2(inset, y), Vector2(inset + 26.0, y + 10.0), line_col, 2.0)
			draw_line(Vector2(size.x - inset, y), Vector2(size.x - inset - 26.0, y - 10.0), line_col, 2.0)


func _bar(r: Rect2, ratio: float, col: Color) -> void:
	draw_rect(r, Color(0.0, 0.0, 0.0, 0.65))
	draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(ratio, 0.0, 1.0), r.size.y)), col)
	draw_rect(r, Color(0.16, 0.17, 0.20), false, 1.0)


func _text(s: String, at: Vector2, col: Color = Color(0.90, 0.88, 0.84), px: int = 14) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


## ⭐ 拾取提示：**拿到一枚被封印的印，当场就说清它现在用不了**。
##    Game 只给得出「获得 玄甲印」这个骨架（那两行在 Game.gd 里，本轮不动它），
##    所以封印附注在 HUD 这一层补上 —— 文案跟着 GameData.REALMS 走，改境界表不用改界面。
## ⚠️ 认印不用正则、也不假设文案格式：印名是一张封闭表，直接看提示里有没有它。
func _pickup_toast_text(raw: String, p) -> String:
	if p == null or not p.has_method("seal_gate_of"):
		return raw
	var nk := ""
	for k in GameData.SEALS.keys():
		if str(k) != "" and raw.contains(str(k)):
			nk = str(k)
			break
	if nk == "":
		return raw
	var gate := str(p.seal_gate_of(nk))
	if gate == "":
		return raw
	# 「命窍满了先放背包」这条信息不能因为加了封印附注就丢掉
	var to_bag := raw.contains("背包")
	return "获得 %s（%s封印 · 需 %s 才能解封）" % [nk, "先放背包 · " if to_bag else "", gate]


## 提示条画在最上层（最后调）。
func _draw_notice() -> void:
	if _notice == "":
		return
	_text(_notice, Vector2(size.x * 0.5 - 180.0, size.y - 148.0), Color(0.96, 0.90, 0.56), 18)
