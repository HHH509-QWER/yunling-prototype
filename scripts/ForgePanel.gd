extends Control
## 合炼面板。⭐ M35 起从「一个火候小游戏」变成**四个页面**：
##   合炼（M13 的火候指针，原样保留） / 融合（§3.2） / 破阶（§3.4） / 凝结（§5）
##
## ⭐ 为什么放在同一个面板里：这四件事在玩家的脑子里是**同一件事** ——「我要把这枚印变强」。
##    拆成四个入口只会让人不知道去哪。所以用页签，共用一套「选中 → 看代价 → 执行」的操作。
##
## ⭐ 操作约定（和 BagPanel 一致）：
##    鼠标点行选**当前页**要操作的东西；E = 执行；←/→ = 换页；Esc = 返回 / 关闭。
##    ⚠️ 合炼页保持原来的「数字键选配方 + E 开炉」，一个字都没改 ——
##       它是 M13 的验收基线，动它会连带一批断言。
##
## ⚠️ 打开时游戏暂停，所以必须 PROCESS_MODE_WHEN_PAUSED。

signal closed

const SmithScript := preload("res://scripts/Smith.gd")

## 四个页面。顺序 = 页签顺序 = ←/→ 的顺序。
const PAGE_NAMES := ["合炼", "融合", "破阶", "凝结"]
const PAGE_FORGE := 0
const PAGE_FUSE := 1
const PAGE_UPGRADE := 2
const PAGE_CONDENSE := 3

var game = null
var page := 0

## ---- 合炼页（M13，原样）----
var step := 0              # 0 选配方 / 1 事件 / 2 火候 / 3 结果
var recipe_index := 0
var pointer := 0.0         # 火候指针在 0..1 之间来回
var running := false

## ---- 融合页 ----
var fuse_main := 0         # 主印在 owned_names() 里的下标
var fuse_sub := 0          # 副印在 fusible_subs() 里的下标
var fuse_cat := -1         # 触媒下标；-1 = 不投

## ---- 破阶页 ----
var up_seal := 0           # 目标印下标
var up_cat := 0            # 触媒下标（破阶必须投，所以没有 -1）
var up_fodder := 0         # 投入的祭品枚数（0..3）

## ---- 凝结页 ----
var shard_idx := 0

var _t := 0.0
var _has_event := false
var _event_choice := 0     # 0 不管 / 1 加料 / 2 减料
var _msg := ""
## 最近一次执行的结果（三个新页共用；`_report` 是合炼页专用的老结构，别混）
var _last: Dictionary = {}
## ⭐ 打开面板的**那一帧**不接受操作。
##    实测：按 E 开交易面板，会顺手把第一件商品买下来 ——
##    因为「开面板」和「面板处理按键」看到的是**同一个事件**。
var _opened_frame := -1
var _report: Dictionary = {}
var _font: Font = null

## 版式常量（1366×768 画布，和 HUD 同一套硬坐标）
const TAB_Y := 100.0
const TAB_W := 122.0
const TAB_H := 30.0
const TAB_X0 := 140.0
## ⚠️ 行高 38 而不是 34：每行要放**两行字**（名字 + 副标题）。
##    34 的时候副标题会掉到下一行的框里 —— 截图一眼就看出来了。
const ROW_H := 38.0
const COL_L := 140.0
const COL_LW := 430.0
const COL_R := 600.0
const COL_RW := 330.0
const LIST_Y := 176.0
const LIST_MAX := 8            # 每列最多画几行（再多就得滚动，先不做到 9 行）


func _ready() -> void:
	_font = GameData.make_font()
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	visible = false


func open(g) -> void:
	game = g
	page = PAGE_FORGE
	step = 0
	recipe_index = 0
	running = false
	_msg = ""
	_report = {}
	_last = {}
	fuse_main = 0
	fuse_sub = 0
	fuse_cat = -1
	up_seal = 0
	up_cat = 0
	up_fodder = 0
	shard_idx = 0
	visible = true
	_opened_frame = Engine.get_process_frames()
	queue_redraw()


func close() -> void:
	visible = false
	running = false
	closed.emit()


## 换页。⚠️ 换页时把「上次结果」清掉 —— 上一页的结果挂在这一页会很怪。
func set_page(p: int) -> void:
	page = clampi(p, 0, PAGE_NAMES.size() - 1)
	step = 0
	running = false
	_last = {}
	_msg = ""
	queue_redraw()


func next_page(d: int) -> void:
	set_page((page + d + PAGE_NAMES.size()) % PAGE_NAMES.size())


# ==================== 合炼（M13，一个字没改）====================

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


# ==================== 融合（§3.2）====================

## 玩家手上所有印名（活跃 + 备用 + 背包），**去掉重复**。
## ⚠️ 顺序要稳定：`slot_seal` → 备用 → 背包。列表每帧重排的话鼠标就点不准了。
func owned_names() -> Array:
	var out: Array = []
	if game == null or game.player == null:
		return out
	var p = game.player
	for i in range(p.slot_seal.size()):
		var n := str(p.slot_seal[i])
		if n != "" and not out.has(n):
			out.append(n)
	for n2 in p.reserve_seals:
		if not out.has(str(n2)):
			out.append(str(n2))
	for n3 in p.bag_seals:
		if not out.has(str(n3)):
			out.append(str(n3))
	return out


func fuse_main_name() -> String:
	var arr := owned_names()
	if arr.is_empty():
		return ""
	return str(arr[clampi(fuse_main, 0, arr.size() - 1)])


## 能当副印的：不是主印、且 `GameData.can_fuse` 认可（组合印不能当副印）。
func fusible_subs() -> Array:
	var main_name := fuse_main_name()
	var out: Array = []
	if main_name == "":
		return out
	for n in owned_names():
		if str(n) == main_name:
			continue
		if bool(GameData.can_fuse(main_name, str(n))["ok"]):
			out.append(str(n))
	return out


func fuse_sub_name() -> String:
	var arr := fusible_subs()
	if arr.is_empty():
		return ""
	return str(arr[clampi(fuse_sub, 0, arr.size() - 1)])


## 手上的稀有触媒（`CATALYST_TAGS` 那张表就是「哪些算稀有触媒」的唯一真相）。
func catalysts() -> Array:
	var out: Array = []
	if game == null or game.player == null:
		return out
	for k in game.player.CATALYST_TAGS.keys():
		if game.player.bag.count(str(k)) > 0:
			out.append(str(k))
	out.sort()
	return out


func fuse_cat_name() -> String:
	var arr := catalysts()
	if fuse_cat < 0 or fuse_cat >= arr.size():
		return ""
	return str(arr[fuse_cat])


## 融合预览（面板画字用）。返回 {} = 当前选不出可融合的组合。
func fuse_preview() -> Dictionary:
	var main_name := fuse_main_name()
	var sub_name := fuse_sub_name()
	if main_name == "" or sub_name == "":
		return {}
	var can: Dictionary = game.player.can_fuse_seals(main_name, sub_name)
	var combo := GameData.fusion_result(main_name, sub_name)
	var cat := fuse_cat_name()
	var attuned: bool = cat != "" and bool(game.player._catalyst_attuned(cat, main_name, sub_name))
	var mut_p := 0.0
	if cat != "":
		mut_p = GameData.mutation_chance("fusion", attuned)
	return {
		"ok": bool(can["ok"]), "reason": str(can["reason"]),
		"main": main_name, "sub": sub_name,
		"cost": GameData.fusion_cost(game.player.rank_of(main_name)),
		"affix": GameData.fusion_affix(sub_name),
		"combo": combo, "catalyst": cat, "attuned": attuned, "mut": mut_p,
		"limit": GameData.fusion_limit(game.player.rank_of(main_name)),
		"used": game.player.affixes_of(main_name).size(),
	}


## 执行融合。`roll` / `mut_roll` 可以注入（自测用），-1 = 真随机。
func do_fuse(roll := -1.0, mut_roll := -1.0) -> Dictionary:
	if page != PAGE_FUSE or game == null:
		return {}
	var main_name := fuse_main_name()
	var sub_name := fuse_sub_name()
	if main_name == "" or sub_name == "":
		_msg = "先选一枚主印和一枚副印"
		queue_redraw()
		return {}
	var r: Dictionary = game.player.fuse_seals(main_name, sub_name, fuse_cat_name(), roll, mut_roll)
	_last = r
	if not bool(r.get("ok", false)):
		_msg = str(r.get("reason", "融合失败"))
	else:
		_msg = ""
		## ⭐ 成功之后下标可能越界（副印被吃掉了）—— 夹回合法范围，别让下一帧崩。
		fuse_sub = 0
		fuse_main = clampi(fuse_main, 0, maxi(0, owned_names().size() - 1))
	queue_redraw()
	return r


# ==================== 破阶（§3.4）====================

func up_seal_name() -> String:
	var arr := owned_names()
	if arr.is_empty():
		return ""
	return str(arr[clampi(up_seal, 0, arr.size() - 1)])


## 破阶要用的触媒：**所有**手上的触媒（不限于稀有 —— 门槛只要求「天材地宝」）。
func upgrade_catalysts() -> Array:
	var out: Array = []
	if game == null or game.player == null:
		return out
	for k in GameData.MATERIALS.keys():
		if str(GameData.MATERIALS[k]["kind"]) != "触媒":
			continue
		if game.player.bag.count(str(k)) > 0:
			out.append(str(k))
	out.sort()
	return out


func up_cat_name() -> String:
	var arr := upgrade_catalysts()
	if arr.is_empty():
		return ""
	return str(arr[clampi(up_cat, 0, arr.size() - 1)])


## 这一枚印**能投入的祭品**（同阶、非主印、非本命）。
func up_fodder_pool() -> Array:
	var n := up_seal_name()
	if n == "":
		return []
	return game.player.upgrade_fodder_for(n)


## 破阶预览。
func upgrade_preview() -> Dictionary:
	var n := up_seal_name()
	if n == "":
		return {}
	var can: Dictionary = game.player.can_upgrade_seal(n, up_cat_name())
	var pool := up_fodder_pool()
	var take := mini(up_fodder, mini(pool.size(), int(GameData.UPGRADE["fodder_max"])))
	return {
		"ok": bool(can["ok"]), "reason": str(can["reason"]), "seal": n,
		"target": int(can.get("target", game.player.rank_of(n) + 1)),
		"catalyst": up_cat_name(), "fodder": take, "pool": pool,
		"chance": GameData.upgrade_chance(take),
		"affixes": game.player.affixes_of(n).size(),
		"mutation": game.player.mutation_of(n),
	}


## 执行破阶。`roll` 可注入（自测用）。
func do_upgrade(roll := -1.0) -> Dictionary:
	if page != PAGE_UPGRADE or game == null:
		return {}
	var n := up_seal_name()
	if n == "":
		_msg = "先选一枚印"
		queue_redraw()
		return {}
	var pool := up_fodder_pool()
	var take := mini(up_fodder, mini(pool.size(), int(GameData.UPGRADE["fodder_max"])))
	var fodder: Array = pool.slice(0, take)
	var r: Dictionary = game.player.upgrade_seal(n, fodder, up_cat_name(), true, roll)
	_last = r
	if not bool(r.get("ok", false)):
		_msg = str(r.get("reason", "破阶失败"))
	else:
		_msg = ""
		up_fodder = 0
		up_seal = clampi(up_seal, 0, maxi(0, owned_names().size() - 1))
	queue_redraw()
	return r


# ==================== 凝结（§5）====================

func shard_names() -> Array:
	var out: Array = []
	for k in GameData.SHARDS.keys():
		out.append(str(k))
	out.sort()
	return out


func shard_name() -> String:
	var arr := shard_names()
	if arr.is_empty():
		return ""
	return str(arr[clampi(shard_idx, 0, arr.size() - 1)])


## 执行凝结。
func do_condense() -> Dictionary:
	if page != PAGE_CONDENSE or game == null:
		return {}
	var n := shard_name()
	if n == "":
		_msg = "没有可凝结的残片"
		queue_redraw()
		return {}
	var r: Dictionary = game.player.condense_shard(n)
	_last = r
	_msg = "" if bool(r.get("ok", false)) else str(r.get("reason", "凝结失败"))
	queue_redraw()
	return r


# ==================== 每帧 / 输入 ====================

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
		if page != PAGE_FORGE:
			set_page(PAGE_FORGE)
		elif step == 0:
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
	## ←/→ 换页。⚠️ 只在这四个页签之间转，不碰任何别的键。
	if is_key and (event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT):
		get_viewport().set_input_as_handled()
		next_page(-1 if event.keycode == KEY_LEFT else 1)
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		get_viewport().set_input_as_handled()
		match page:
			PAGE_FORGE:
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
			PAGE_FUSE:
				do_fuse()
			PAGE_UPGRADE:
				do_upgrade()
			PAGE_CONDENSE:
				do_condense()
		return
	if is_key:
		get_viewport().set_input_as_handled()
		if page == PAGE_FORGE:
			if event.keycode == KEY_Q and step == 1:
				choose_event(false)
				return
			var idx := int(event.keycode) - int(KEY_1)
			if idx >= 0 and idx < recipes().size() and step == 0:
				recipe_index = idx
				_msg = ""
				queue_redraw()
		elif page == PAGE_UPGRADE:
			## T = 祭品枚数 0→1→2→3→0（**不自动替你吃印** —— 那是不可撤销的操作）
			if event.keycode == KEY_T:
				up_fodder = (up_fodder + 1) % (int(GameData.UPGRADE["fodder_max"]) + 1)
				queue_redraw()


# ==================== 绘制 ====================

func _draw() -> void:
	if not visible or game == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.02, 0.02, 0.91))
	_text("炉 火", Vector2(140.0, 72.0), Color(0.96, 0.78, 0.50), 26)
	_text(_hint(), Vector2(142.0, TAB_Y - 6.0), Color(0.74, 0.76, 0.80), 13)
	_text("再按 F 关闭  ·  ←/→ 换页", Vector2(1150.0, 72.0), Color(0.52, 0.55, 0.58), 12)
	_draw_tabs()

	match page:
		PAGE_FORGE:
			_draw_forge_page()
		PAGE_FUSE:
			_draw_fuse_page()
		PAGE_UPGRADE:
			_draw_upgrade_page()
		PAGE_CONDENSE:
			_draw_condense_page()

	if _msg != "":
		_text(_msg, Vector2(142.0, 736.0), Color(0.95, 0.62, 0.46), 15)
	if not _last.is_empty():
		_draw_last_result()


func _hint() -> String:
	match page:
		PAGE_FUSE:
			return "点主印 / 点副印 / 点触媒（可空）  ·  E 融合  ·  成功率 %d%%" % int(float(GameData.FUSION["success"]) * 100.0)
		PAGE_UPGRADE:
			return "点目标印 / 点触媒  ·  T 调整祭品  ·  E 破阶"
		PAGE_CONDENSE:
			return "点一档残片  ·  E 凝结成印"
	match step:
		0:
			return "选一条配方（数字键）  ·  E 开炉"
		1:
			return "炉火突变 —— E 加一份灵魄（+%d%%）  ·  Q 不管" % int(GameData.FURNACE["event_bonus"])
		2:
			return "指针进绿区时按 E —— 失误必失败"
	return "E 再来一次  ·  Esc 返回"


func _draw_tabs() -> void:
	for i in range(PAGE_NAMES.size()):
		var box := tab_rect(i)
		var on: bool = i == page
		draw_rect(box, Color(0.13, 0.11, 0.09) if on else Color(0.08, 0.07, 0.06))
		draw_rect(box, Color(0.95, 0.72, 0.35, 0.90 if on else 0.22), false, 2.0 if on else 1.0)
		_text(str(PAGE_NAMES[i]), box.position + Vector2(38.0, 21.0),
				Color(0.98, 0.90, 0.74) if on else Color(0.58, 0.56, 0.52), 16)


func tab_rect(i: int) -> Rect2:
	return Rect2(Vector2(TAB_X0 + float(i) * (TAB_W + 8.0), TAB_Y), Vector2(TAB_W, TAB_H))


## 一行可点的条目。返回它占的矩形（绘制与命中判定共用同一个函数 —— 不许各算一套）。
func row_rect(col_x: float, w: float, i: int, y0 := LIST_Y) -> Rect2:
	return Rect2(Vector2(col_x, y0 + ROW_H * float(i)), Vector2(w, ROW_H - 6.0))


## 触媒行的矩形。⚠️ 位置是**跟着主印列表长度走的**（不写死 CAT_Y）：
##    开局只有 2 枚印、写了固定 Y 的话中间会空出一大片，看着像面板坏了。
##    绘制与点击共用这一个函数 —— 两边各算一套迟早会错位。
func cat_y() -> float:
	var rows := clampi(owned_names().size(), 3, LIST_MAX)
	return LIST_Y + ROW_H * float(rows) + 26.0


func cat_rect(i: int, col_x := COL_L, w := COL_LW) -> Rect2:
	return row_rect(col_x, w, i, cat_y())


## 数值带符号的写法。⚠️ GDScript 的 `%` **不支持 `%+g` / `%+.1f` 这种 flag**——
##    写了会原样打印出 "%+g"（踩过：融合页上真的显示了 "+ %s %+g"）。
func _fmt_signed(v: float) -> String:
	var s := "%.2f" % v
	if s.contains("."):
		s = s.rstrip("0").rstrip(".")
	return ("+" if v >= 0.0 else "") + s


func _draw_row(box: Rect2, label: String, sub: String, picked: bool, ok: bool, right := "") -> void:
	draw_rect(box, Color(0.10, 0.09, 0.08, 0.95))
	draw_rect(box, Color(0.95, 0.72, 0.35, 0.85 if picked else 0.18), false, 2.5 if picked else 1.0)
	_text(label, box.position + Vector2(12.0, 17.0),
			Color(0.94, 0.90, 0.84) if ok else Color(0.52, 0.50, 0.48), 15)
	if sub != "":
		_text(sub, box.position + Vector2(12.0, 31.0), Color(0.62, 0.66, 0.70), 11)
	if right != "":
		_text(right, box.position + Vector2(box.size.x - 92.0, 20.0),
				Color(0.62, 0.82, 0.66) if ok else Color(0.62, 0.44, 0.40), 13)


# ---- 合炼页（原样）----

func _draw_forge_page() -> void:
	for i in range(recipes().size()):
		_draw_recipe_row(i)
	if step >= 1:
		_draw_furnace()


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


# ---- 融合页 ----

func _draw_fuse_page() -> void:
	var p = game.player
	var names := owned_names()

	_text("主印（身份 / 主动 / 等级全都保留）", Vector2(COL_L, 158.0), Color(0.86, 0.80, 0.66), 13)
	if names.is_empty():
		_text("一枚印都没有", Vector2(COL_L, LIST_Y + 20.0), Color(0.60, 0.58, 0.56), 14)
	for i in range(mini(names.size(), LIST_MAX)):
		var n := str(names[i])
		var box := row_rect(COL_L, COL_LW, i)
		var rk: int = p.rank_of(n)
		_draw_row(box, n, "rank %d  ·  融词条 %d/%d  ·  %s" % [
				rk, p.affixes_of(n).size(), GameData.fusion_limit(rk),
				p.mutation_of(n) if p.mutation_of(n) != "" else "无变异"],
				i == fuse_main, true)

	_text("副印（会被吸收掉）", Vector2(COL_R, 158.0), Color(0.86, 0.80, 0.66), 13)
	var subs := fusible_subs()
	if subs.is_empty():
		_text("没有可融的副印", Vector2(COL_R, LIST_Y + 20.0), Color(0.60, 0.58, 0.56), 12)
		_text("（组合印不能再当副印）", Vector2(COL_R, LIST_Y + 36.0), Color(0.52, 0.52, 0.50), 11)
	for i in range(mini(subs.size(), 6)):
		var s := str(subs[i])
		var box2 := row_rect(COL_R, COL_RW, i)
		var aff := GameData.fusion_affix(s)
		_draw_row(box2, s, "贡献 %s %s" % [str(aff.get("stat", "?")), _fmt_signed(float(aff.get("value", 0.0)))],
				i == fuse_sub, true)

	## 触媒：第一行是「不投」
	_text("稀有触媒（投了就开变异那扇门）", Vector2(COL_L, cat_y() - 12.0), Color(0.86, 0.80, 0.66), 13)
	_draw_row(cat_rect(0), "不投触媒", "融合 85% 照旧，只是没有变异机会",
			fuse_cat < 0, true)
	var cats := catalysts()
	for i in range(mini(cats.size(), 4)):
		var c := str(cats[i])
		_draw_row(cat_rect(i + 1), c,
				"手上 %d 份" % p.bag.count(c), fuse_cat == i, true)

	## 预览
	var pv := fuse_preview()
	var x := 980.0
	if pv.is_empty():
		_text("选好主副印后这里显示结果", Vector2(x, LIST_Y + 20.0), Color(0.56, 0.56, 0.54), 13)
		return
	var main_name := str(pv["main"])
	var combo := str(pv["combo"])
	_text("结果", Vector2(x, LIST_Y + 4.0), Color(0.86, 0.80, 0.66), 13)
	_text(combo if combo != "" else main_name, Vector2(x, LIST_Y + 30.0),
			Color(0.98, 0.86, 0.55), 20)
	if combo != "":
		_text("（配方命中 → 变成组合印）", Vector2(x, LIST_Y + 50.0), Color(0.72, 0.86, 0.72), 11)
	var aff: Dictionary = pv["affix"]
	_text("+ %s %s" % [str(aff.get("stat", "?")), _fmt_signed(float(aff.get("value", 0.0)))],
			Vector2(x, LIST_Y + 76.0), Color(0.80, 0.84, 0.74), 13)
	_text("灵力 %.0f  ·  成功率 %.0f%%" % [float(pv["cost"]), float(GameData.FUSION["success"]) * 100.0],
			Vector2(x, LIST_Y + 98.0), Color(0.70, 0.74, 0.78), 12)
	_text("融词条 %d/%d" % [int(pv["used"]) + 1, int(pv["limit"])], Vector2(x, LIST_Y + 118.0),
			Color(0.70, 0.74, 0.78), 12)
	if str(pv["catalyst"]) != "":
		_text("变异几率 %.0f%%%s" % [float(pv["mut"]) * 100.0,
				"（属性契合）" if bool(pv["attuned"]) else ""],
				Vector2(x, LIST_Y + 140.0), Color(0.90, 0.72, 0.96), 12)
	if not bool(pv["ok"]):
		_text(str(pv["reason"]), Vector2(x, LIST_Y + 164.0), Color(0.92, 0.52, 0.44), 12)


# ---- 破阶页 ----

func _draw_upgrade_page() -> void:
	var p = game.player
	var names := owned_names()
	_text("目标印（等级 +1，身份与变异词条都保留）", Vector2(COL_L, 158.0), Color(0.86, 0.80, 0.66), 13)
	for i in range(mini(names.size(), 9)):
		var n := str(names[i])
		var mut: String = p.mutation_of(n)
		_draw_row(row_rect(COL_L, COL_LW, i), n,
				"rank %d  ·  炼化 %.0f  ·  %s" % [p.rank_of(n), p.refine_of(n),
						("变异·" + mut) if mut != "" else "无变异"],
				i == up_seal, true)

	var cats := upgrade_catalysts()
	_text("天材地宝（破阶必投）", Vector2(COL_R, 158.0), Color(0.86, 0.80, 0.66), 13)
	if cats.is_empty():
		_text("包里没有触媒", Vector2(COL_R, LIST_Y + 20.0), Color(0.62, 0.48, 0.44), 12)
	for i in range(mini(cats.size(), 5)):
		var c := str(cats[i])
		_draw_row(row_rect(COL_R, COL_RW, i), c, "手上 %d 份" % p.bag.count(c), i == up_cat, true)

	var pv := upgrade_preview()
	if pv.is_empty():
		return
	var pool: Array = pv["pool"]
	var take := int(pv["fodder"])
	_text("祭品：同阶印 %d 枚（最多 3）  ·  T 调整" % take,
			Vector2(COL_R, LIST_Y + 6.0 * ROW_H), Color(0.86, 0.80, 0.66), 13)
	var fodder_line := "不投" if take == 0 else "、".join(pool.slice(0, take))
	_text("将消耗：" + fodder_line, Vector2(COL_R, LIST_Y + 6.0 * ROW_H + 20.0),
			Color(0.88, 0.66, 0.50), 12)

	var x := 980.0
	_text("结果", Vector2(x, LIST_Y + 4.0), Color(0.86, 0.80, 0.66), 13)
	_text("%s → rank %d" % [str(pv["seal"]), int(pv["target"])], Vector2(x, LIST_Y + 30.0),
			Color(0.98, 0.86, 0.55), 20)
	_text("成功率 %.0f%%" % (float(pv["chance"]) * 100.0), Vector2(x, LIST_Y + 56.0),
			Color(0.66, 0.88, 0.70), 15)
	_text("失败：炼化清零 + 气血上限 −%.0f%%" % (float(GameData.UPGRADE["fail_hp_cap"]) * 100.0),
			Vector2(x, LIST_Y + 78.0), Color(0.92, 0.56, 0.46), 12)
	_text("失败会毁掉触媒与祭品（这是豪赌）", Vector2(x, LIST_Y + 98.0),
			Color(0.88, 0.62, 0.50), 12)
	if not bool(pv["ok"]):
		_text(str(pv["reason"]), Vector2(x, LIST_Y + 122.0), Color(0.92, 0.52, 0.44), 12)


# ---- 凝结页 ----

func _draw_condense_page() -> void:
	var p = game.player
	_text("残片 → 完整的印（10 片 + 灵力）", Vector2(COL_L, 158.0), Color(0.86, 0.80, 0.66), 13)
	var arr := shard_names()
	for i in range(arr.size()):
		var sn := str(arr[i])
		var cfg: Dictionary = GameData.SHARDS[sn]
		var have: int = p.bag.count(sn)
		var need := int(cfg["count"])
		var chk: Dictionary = p.can_condense(sn)
		_draw_row(row_rect(COL_L, COL_LW + 120.0, i), sn,
				"%d/%d 片  ·  灵力 %.0f  ·  → %s" % [have, need, float(cfg["essence"]), str(cfg["shard"])],
				i == shard_idx, bool(chk["ok"]))
	var cur := shard_name()
	if cur != "":
		var chk2: Dictionary = p.can_condense(cur)
		_text("E 凝结" if bool(chk2["ok"]) else str(chk2["reason"]),
				Vector2(COL_L, LIST_Y + ROW_H * float(arr.size()) + 16.0),
				Color(0.66, 0.88, 0.70) if bool(chk2["ok"]) else Color(0.92, 0.56, 0.46), 14)


## 上一次执行的结果（融合 / 破阶 / 凝结共用）。
## ⚠️ 合炼页有自己的 `_report` 画法，这里只画三个新页的。
func _draw_last_result() -> void:
	if page == PAGE_FORGE:
		return
	var x := 980.0
	var y := 470.0
	if not bool(_last.get("ok", false)):
		return
	if page == PAGE_FUSE:
		if not bool(_last.get("success", false)):
			_text("融合失败 —— 副印已毁，主印无损", Vector2(x, y), Color(0.92, 0.52, 0.44), 14)
			return
		_text("融合成功", Vector2(x, y), Color(0.66, 0.90, 0.66), 16)
		var combo := str(_last.get("combo", ""))
		if combo != "":
			_text("→ %s" % combo, Vector2(x, y + 22.0), Color(0.98, 0.86, 0.55), 14)
		var aff: Dictionary = _last.get("affix", {})
		if not aff.is_empty():
			_text("+ %s %s" % [str(aff.get("stat", "?")), _fmt_signed(float(aff.get("value", 0.0)))],
					Vector2(x, y + 42.0), Color(0.80, 0.84, 0.74), 13)
		if str(_last.get("mutation", "")) != "":
			_text("★ 变异：%s" % str(_last["mutation"]), Vector2(x, y + 62.0),
					Color(0.92, 0.74, 0.98), 15)
	elif page == PAGE_UPGRADE:
		if bool(_last.get("success", false)):
			_text("破阶成功 —— rank %d" % int(_last.get("rank", 0)), Vector2(x, y),
					Color(0.66, 0.90, 0.66), 16)
		else:
			_text("破阶失败 —— 祭品尽毁", Vector2(x, y), Color(0.92, 0.52, 0.44), 16)
			_text("炼化清零，气血上限 −10%", Vector2(x, y + 22.0), Color(0.88, 0.62, 0.50), 13)
	elif page == PAGE_CONDENSE:
		_text("凝结成功 —— %s" % str(_last.get("seal", "")), Vector2(x, y), Color(0.66, 0.90, 0.66), 16)


# ==================== 鼠标 ====================

func _gui_input(event: InputEvent) -> void:
	if not visible or game == null:
		return
	if Engine.get_process_frames() == _opened_frame:
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var pos := mb.position
	for i in range(PAGE_NAMES.size()):
		if tab_rect(i).has_point(pos):
			set_page(i)
			return
	match page:
		PAGE_FUSE:
			_fuse_click(pos)
		PAGE_UPGRADE:
			_upgrade_click(pos)
		PAGE_CONDENSE:
			for i in range(shard_names().size()):
				if row_rect(COL_L, COL_LW + 120.0, i).has_point(pos):
					shard_idx = i
					_last = {}
					queue_redraw()
					return
		PAGE_FORGE:
			for i in range(recipes().size()):
				if Rect2(Vector2(140.0, 168.0 + 58.0 * float(i)), Vector2(640.0, 50.0)).has_point(pos):
					recipe_index = i
					_msg = ""
					queue_redraw()
					return


func _fuse_click(pos: Vector2) -> void:
	for i in range(mini(owned_names().size(), LIST_MAX)):
		if row_rect(COL_L, COL_LW, i).has_point(pos):
			fuse_main = i
			fuse_sub = 0
			_last = {}
			queue_redraw()
			return
	for i in range(mini(fusible_subs().size(), 6)):
		if row_rect(COL_R, COL_RW, i).has_point(pos):
			fuse_sub = i
			_last = {}
			queue_redraw()
			return
	if cat_rect(0).has_point(pos):
		fuse_cat = -1
		_last = {}
		queue_redraw()
		return
	for i in range(mini(catalysts().size(), 4)):
		if cat_rect(i + 1).has_point(pos):
			fuse_cat = i
			_last = {}
			queue_redraw()
			return


func _upgrade_click(pos: Vector2) -> void:
	for i in range(mini(owned_names().size(), LIST_MAX)):
		if row_rect(COL_L, COL_LW, i).has_point(pos):
			up_seal = i
			up_fodder = 0
			_last = {}
			queue_redraw()
			return
	for i in range(mini(upgrade_catalysts().size(), 5)):
		if row_rect(COL_R, COL_RW, i).has_point(pos):
			up_cat = i
			_last = {}
			queue_redraw()
			return


func _text(s: String, at: Vector2, col: Color, px: int) -> void:
	if _font != null:
		draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
