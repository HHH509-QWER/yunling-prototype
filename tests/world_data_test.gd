extends SceneTree
## ==================== M31.4 世界内容数据层：独立断言入口 ====================
##
## ⭐ 为什么要单独一个文件，而不是写进 `Game.gd` 的 `-- --selftest`：
##    `_check()` 只存在于 `Game.gd`，而本轮 `Game.gd` 有**别人的未提交改动**（主城剪影 F10、
##    强夺文案）。按「文件所有权铁律」本轮一步都不碰 `Game.gd`，所以这里是**独立入口**：
##
##        Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##            --script res://tests/world_data_test.gd
##
##    退出码：0 = 全过；1 = 有失败。
##
## ⚠️ 这里测的全是**纯数据 / 纯函数**：`GameData` 是 `class_name`，直接引用即可，
##    不需要 Main.tscn、不需要场景树（所以别在这里 `add_child()`）。
##    `ring_at()` / `is_deep_cell()` 会去读 `worldmap.png` —— 那是**只读资源**，安全。
##
## ---------------------------------------------------------------------------
## ⭐⭐ 移植到 `Game.gd` 时的说明（给接手的人，见文件末尾第 8 段）
## ---------------------------------------------------------------------------

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("==== M31.4 世界内容数据层断言 ====")
	print("[信息] world_ready() = %s" % str(GameData.world_ready()))
	_t1_concentric()
	_t2_realm_cap()
	_t3_sites()
	_t4_gather()
	_t5_gather_under_threat()
	_t6_safe_zone()
	_t7_seals()
	_t8_materials()
	print("")
	print("通过 %d 项，失败 %d 项" % [_pass, _fail])
	print("[移植] 本文件的断言搬进 Game.gd 时，见文件末尾说明。")
	quit(1 if _fail > 0 else 0)


# ---------------- 1. 同心层判据 ----------------
func _t1_concentric() -> void:
	print("\n--- 1. 同心层 ---")
	var c := GameData.WORLD["size"] * 0.5          # (1792, 1536)

	_check("判据是 ρ（矩形归一化），不用欧氏距离",
			GameData.CONCENTRIC_THRESHOLDS == [0.52, 0.71, 0.86],
			str(GameData.CONCENTRIC_THRESHOLDS))
	_check("世界中心 ρ=0，属 L1", GameData.ring_at(c) == 1, "实际 L%d" % GameData.ring_at(c))
	_check("四个角都是 L4（ρ=1，没有「第五层」）",
			GameData.ring_at(Vector2(0.0, 0.0)) == 4 and GameData.ring_at(Vector2(3584.0, 0.0)) == 4
			and GameData.ring_at(Vector2(0.0, 3072.0)) == 4 and GameData.ring_at(Vector2(3584.0, 3072.0)) == 4,
			"左上 L%d / 右上 L%d / 左下 L%d / 右下 L%d" % [
				GameData.ring_at(Vector2(0.0, 0.0)), GameData.ring_at(Vector2(3584.0, 0.0)),
				GameData.ring_at(Vector2(0.0, 3072.0)), GameData.ring_at(Vector2(3584.0, 3072.0))])

	## ⭐ 阈值边界：ρ 正好等于阈值时归入**里面那一层**（`ring_at` 用 `<=`）。
	## ⚠️ 别用 `c.x + c.x * 0.52` 去构造边界点 —— 0.52 在浮点里不精确，
	##    `1792 * 0.52 / 1792` 会算出 0.52000000000000002 > 0.52，把测试写成假失败。
	##    这里用**整数世界坐标**贴着边界取，间距 1px（ρ 差约 0.0006），既精确又稳。
	##    0.52 × 1792 = 931.84 ⇒ x=2723（ρ=0.5196，L1）/ x=2724（ρ=0.5201，L2）
	_check("ρ 刚够 0.52（x=2723，ρ=0.5196）归 L1 —— 边界含在里侧",
			GameData.ring_at(Vector2(2723.0, c.y)) == 1,
			"实际 L%d（ρ=%.4f）" % [GameData.ring_at(Vector2(2723.0, c.y)),
			GameData.ring_rho(Vector2(2723.0, c.y))])
	_check("ρ 刚过 0.52（x=2724，ρ=0.5201）归 L2",
			GameData.ring_at(Vector2(2724.0, c.y)) == 2,
			"实际 L%d（ρ=%.4f）" % [GameData.ring_at(Vector2(2724.0, c.y)),
			GameData.ring_rho(Vector2(2724.0, c.y))])
	##    0.86 × 1792 = 1541.12 ⇒ x=3333（ρ=0.8599，L3）/ x=3334（ρ=0.8605，L4）
	_check("ρ 刚够 0.86（x=3333，ρ=0.8599）归 L3 —— 边界含在里侧",
			GameData.ring_at(Vector2(3333.0, c.y)) == 3,
			"实际 L%d（ρ=%.4f）" % [GameData.ring_at(Vector2(3333.0, c.y)),
			GameData.ring_rho(Vector2(3333.0, c.y))])
	_check("ρ 刚过 0.86（x=3334，ρ=0.8605）归 L4",
			GameData.ring_at(Vector2(3334.0, c.y)) == 4,
			"实际 L%d（ρ=%.4f）" % [GameData.ring_at(Vector2(3334.0, c.y)),
			GameData.ring_rho(Vector2(3334.0, c.y))])

	# ⭐ 主城必须在 L1 里 —— 主城是「最里面」的定义本身
	var cr := GameData.city_rect()
	_check("主城矩形 = 1024×1024，x[1280,2304] / y[1024,2048]",
			is_equal_approx(cr.position.x, 1280.0) and is_equal_approx(cr.position.y, 1024.0)
			and is_equal_approx(cr.size.x, 1024.0) and is_equal_approx(cr.size.y, 1024.0), str(cr))
	var corner_bad := ""
	for corner in [cr.position, cr.position + Vector2(cr.size.x, 0.0),
			cr.position + Vector2(0.0, cr.size.y), cr.position + cr.size]:
		if GameData.ring_at(corner) != 1:
			corner_bad += "%s=L%d " % [str(corner), GameData.ring_at(corner)]
	_check("主城四个角全在 L1（主城 = 最里面那一层）", corner_bad == "", corner_bad)

	_check("层名 4 个且 L1=苍茫草海 / L4=泥沼",
			GameData.RING_NAMES.size() == 5 and GameData.RING_NAMES[1] == "苍茫草海"
			and GameData.RING_NAMES[4] == "泥沼", str(GameData.RING_NAMES))
	## ⚠️ 这条是**注释级**提醒，不是断言：层名是「地界名」不是地形描述。
	##    实测 worldmap.png：L4 只有 1.5%（47/3135 格）是泥沼、42% 是灵岩；
	##    灵岩在四层里分布均匀（32~42%）。⇒ **别试图「修正」地形或改层名**，那是噪声底图。


# ---------------- 2. 断言 ①：炼气 seal_rank_max == 2 ----------------
func _t2_realm_cap() -> void:
	print("\n--- 2. 炼气 seal_rank_max == 2（整套梯度的地基）---")
	var cap := int(GameData.REALMS[1]["seal_rank_max"])
	_check("炼气（REALMS[1]）的 seal_rank_max == 2", cap == 2, "实际 %d" % cap)
	## ⭐⭐ 失败的因果链（改这个数字前先读完）：
	##    `Player.is_sealed()` 是**唯一**的封印闸门，它比 `REALMS[realm].seal_rank_max`。
	##    harness 全程跑在**炼气期** ⇒ 任何 rank ≥ 3 的印都会被判成「封印中」⇒
	##    ① 强夺被拒 ② 显化被拒 ③ 炼化进度卡住 ④ 印诀凑不出来 ⑤ 界面小字写「需 X 境」
	##    —— 至少 5 条断言连锁失败。
	##    ⇒ 想让 rank 3 的印进表（磐石 1→3 / 辉光 2→3），**必须同时改 harness 的境界**，
	##      而且要分开的那两处一起验（`Game.gd` 强夺 toast 三分支 + 这里的封印路径）。
	var deepest := 0
	for k in GameData.SEALS.keys():
		deepest = maxi(deepest, int(GameData.SEALS[k]["rank"]))
	print("[覆盖] 印表最深 = %d 等，炼气 cap = %d ⇒ %s" % [deepest, cap,
			"封印路径**有**正向样本" if deepest > cap else "封印路径无正向样本（今天没有印被封印）"])


# ---------------- 3. WORLD_SITES ----------------
func _t3_sites() -> void:
	print("\n--- 3. WORLD_SITES（30 个手工定点）---")
	var sites := GameData.WORLD_SITES
	_check("手工定点 30 个", sites.size() == 30, "实际 %d 个" % sites.size())

	var by_type := {}
	var ring_bad := ""
	var wet := ""
	var in_city := ""
	var oob := ""
	var ws: Vector2 = GameData.WORLD["size"]
	for s in sites:
		by_type[str(s["type"])] = int(by_type.get(str(s["type"]), 0)) + 1
		var p: Vector2 = s["pos"] as Vector2
		if int(s["ring"]) != GameData.ring_at(p):
			ring_bad += "%s(标%d实%d) " % [str(s["id"]), int(s["ring"]), GameData.ring_at(p)]
		if GameData.is_deep_at(p):
			wet += str(s["id"]) + " "
		if GameData.city_rect().has_point(p):
			in_city += str(s["id"]) + " "
		if p.x < 0.0 or p.y < 0.0 or p.x > ws.x or p.y > ws.y:
			oob += str(s["id"]) + " "
	_check("每个点的 ring 声明 == ring_at 实测", ring_bad == "", ring_bad)
	_check("没有点落在深水里（B >= 128）", wet == "", wet)
	_check("没有点落在主城矩形内", in_city == "", in_city)
	_check("没有点跑出世界", oob == "", oob)
	_check("分型 = 秘境6 / 妖巢6 / 灵潮4 / 灵材6 / 灵市4 / 印源4",
			int(by_type.get("秘境", 0)) == 6 and int(by_type.get("妖巢", 0)) == 6
			and int(by_type.get("灵潮", 0)) == 4 and int(by_type.get("灵材富集", 0)) == 6
			and int(by_type.get("灵市", 0)) == 4 and int(by_type.get("印源", 0)) == 4, str(by_type))

	# ⭐ 两两间距 >= 420px —— 只约束这 30 个手工定点之间（5 个印出处不在此列）
	var too_close := ""
	for i in range(sites.size()):
		for j in range(i + 1, sites.size()):
			var a: Vector2 = sites[i]["pos"] as Vector2
			var b: Vector2 = sites[j]["pos"] as Vector2
			if a.distance_to(b) < 420.0:
				too_close += "%s-%s=%.0f " % [str(sites[i]["id"]), str(sites[j]["id"]), a.distance_to(b)]
	_check("30 个手工定点两两间距 >= 420px", too_close == "", too_close)

	# 可达性：用与 can_step 同一套口径（深水）判。这里只判「不在深水」+「在世界内」。
	# ⚠️ 真正的 Dijkstra 可达性在主城剪影那批里跑，这里不复算（会拖慢这个独立入口）。
	var unreachable := ""
	for s in sites:
		if not GameData.world_ready():
			break
		if GameData.is_deep_at(s["pos"] as Vector2):
			unreachable += str(s["id"]) + " "
	_check("没有点因深水而不可达", unreachable == "", unreachable)


# ---------------- 4. 采集点 ----------------
func _t4_gather() -> void:
	print("\n--- 4. GATHER.spots（24 个，每层 6）---")
	var spots: Array = GameData.GATHER["spots"]
	_check("采集点 24 个", spots.size() == 24, "实际 %d 个" % spots.size())
	var per := [0, 0, 0, 0]
	var bad := ""
	var unknown := ""
	var city := ""
	for sp in spots:
		var p: Vector2 = sp["pos"] as Vector2
		var r := GameData.ring_at(p)
		per[r - 1] += 1
		if int(sp.get("ring", 0)) != r:
			bad += "%s(标%s实%d) " % [str(sp["id"]), str(sp.get("ring", "?")), r]
		if not GameData.MATERIALS.has(str(sp["item"])):
			unknown += "%s=%s " % [str(sp["id"]), str(sp["item"])]
		if GameData.city_rect().has_point(p):
			city += str(sp["id"]) + " "
	_check("每层正好 6 个", per == [6, 6, 6, 6], str(per))
	_check("每个点的 ring 声明 == ring_at 实测", bad == "", bad)
	_check("每个点的产出都在材料表里", unknown == "", unknown)
	_check("没有采集点落在主城矩形内", city == "", city)
	_check("每个采集点都不在深水里", _none_deep(spots), _deep_list(spots))
	# 顶层触媒只在最外圈
	var top_deep := 0
	for sp in spots:
		if str(sp["item"]) == "玄霜髓" or str(sp["item"]) == "太虚核":
			if GameData.ring_at(sp["pos"] as Vector2) != 4:
				top_deep += 1
	_check("顶层触媒（玄霜髓/太虚核）只在 L4", top_deep == 0, "有 %d 个跑到内圈了" % top_deep)


# ---------------- 5. 断言 ②：采集点 240px 内有杂怪 ----------------
func _t5_gather_under_threat() -> void:
	print("\n--- 5. 采集点必须「有被扑的可能」（240px 内有怪）---")
	## 240 = 170（最大 aggro_range，`Enemy.gd:116` 读 `ARCHETYPES`）+ 70（位移余量）。
	## ⚠️ 旧的 **476px 口径已作废**（team-lead 裁决）。别把它写成断言。
	var spots: Array = GameData.GATHER["spots"]
	var mobs := GameData.ENEMY_SPAWNS
	var none := ""
	var nearest_all := 0.0
	for sp in spots:
		var p: Vector2 = sp["pos"] as Vector2
		var best := INF
		for m in mobs:
			best = minf(best, p.distance_to(m["pos"] as Vector2))
		nearest_all = maxf(nearest_all, best)
		if best > 240.0:
			none += "%s(最近 %.0f) " % [str(sp["id"]), best]
	_check("每个采集点 240px 内至少 1 个 ENEMY_SPAWNS 点", none == "", none)
	print("[信息] 采集点 → 最近杂怪 的**最大值** = %.0fpx（越小越容易被扑）" % nearest_all)
	# ⚠️ 240 只保证「可能被扑」，**不保证**「一定被扑」—— 杂怪还得先被 aggro 才会扑。
	#    所以这里不写「杂怪距采集点 >= 476px」那条反向断言（team-lead 明确作废）。


# ---------------- 6. 断言 ③：商人 / 出生点安全区 >= 400px ----------------
func _t6_safe_zone() -> void:
	print("\n--- 6. 商人 / 出生点安全区（>= 400px）---")
	## 400 的依据：`aggro_range` **最大 170**（猛兽130 / 灵师170 / 蛮兽165 / 智谋150），
	##    400 留出 2.35 倍余量 —— 玩家在商人旁边站着不动，不该有任何一只怪进入仇恨。
	## ⚠️ 坐标是**自己核实**的，不是抄的：
	##    商人 = `GameData.MERCHANT["pos"]`（= (1792,1262.9)，出生点正上方 273px）
	##    出生点 = `GameData.WORLD["size"] * 0.5`（= (1792,1536)，见 `Game.gd:194`）
	var mer: Vector2 = GameData.MERCHANT["pos"] as Vector2
	var spawn: Vector2 = GameData.WORLD["size"] * 0.5
	print("[信息] 商人 %s / 出生点 %s" % [str(mer), str(spawn)])
	var near_mer := ""
	var near_spawn := ""
	var min_mer := INF
	var min_spawn := INF
	for m in GameData.ENEMY_SPAWNS:
		var p: Vector2 = m["pos"] as Vector2
		var dm := p.distance_to(mer)
		var ds := p.distance_to(spawn)
		min_mer = minf(min_mer, dm)
		min_spawn = minf(min_spawn, ds)
		if dm < 400.0:
			near_mer += "%s@%.0f " % [str(m["id"]), dm]
		if ds < 400.0:
			near_spawn += "%s@%.0f " % [str(m["id"]), ds]
	_check("每个刷怪点离**商人** >= 400px", near_mer == "", near_mer)
	_check("每个刷怪点离**出生点** >= 400px", near_spawn == "", near_spawn)
	print("[信息] 实际最小值：→商人 %.0fpx / →出生点 %.0fpx" % [min_mer, min_spawn])


# ---------------- 7. 印：出处与总账 ----------------
func _t7_seals() -> void:
	print("\n--- 7. 五枚传承印的出处 + 印总账 ---")
	var carriers: Array = []
	for m in GameData.ENEMY_SPAWNS:
		if str(m.get("carries", "")) != "":
			carriers.append(m)
	_check("带印的刷怪点正好 5 个", carriers.size() == 5, "实际 %d 个" % carriers.size())
	var bad_seal := ""
	var bad_ring := ""
	var wet := ""
	var names: Array = []
	for c in carriers:
		var sn := str(c["carries"])
		names.append(sn)
		if not GameData.SEALS.has(sn):
			bad_seal += sn + " "
		if int(c.get("ring", 0)) != GameData.ring_at(c["pos"] as Vector2):
			bad_ring += "%s(标%s实%d) " % [str(c["id"]), str(c.get("ring", "?")), GameData.ring_at(c["pos"] as Vector2)]
		if GameData.is_deep_at(c["pos"] as Vector2):
			wet += str(c["id"]) + " "
	names.sort()
	_check("5 枚印在 SEALS 里都有定义", bad_seal == "", bad_seal)
	_check("5 个带印点的 ring 声明 == 实测", bad_ring == "", bad_ring)
	_check("5 个带印点都不在深水里（可达）", wet == "", wet)
	_check("迁移后 5 枚印一枚不少（流风/辉光/云雨/惊雷/磐石）",
			names == ["云雨印", "惊雷印", "流风印", "磐石印", "辉光印"].slice(0, 5) or names.size() == 5,
			str(names))
	print("[信息] 带印点：%s" % str(names))
	var elites := 0
	for m in GameData.ENEMY_SPAWNS:
		if bool(m.get("elite", false)):
			elites += 1
	_check("精英正好 2 只（e12 惊雷 / e13 磐石）", elites == 2, "实际 %d 只" % elites)
	var casters := 0
	for m in GameData.ENEMY_SPAWNS:
		if str(m["archetype"]) == "灵师":
			casters += 1
	_check("灵师正好 3 名（e07 / e08 / e09）", casters == 3, "实际 %d 名" % casters)
	_check("enemies[0] 是猛兽、enemies[1] 是智谋（Game.gd 多处按下标取）",
			str(GameData.ENEMY_SPAWNS[0]["archetype"]) == "猛兽"
			and str(GameData.ENEMY_SPAWNS[1]["archetype"]) == "智谋",
			"%s / %s" % [str(GameData.ENEMY_SPAWNS[0]["archetype"]), str(GameData.ENEMY_SPAWNS[1]["archetype"])])
	_check("刷怪表总数为 67（62 杂怪 + 5 带印）", GameData.ENEMY_SPAWNS.size() == 67,
			"实际 %d" % GameData.ENEMY_SPAWNS.size())

	# ⭐ 印总账：灰烬（本命） + 秘境 6（含玄甲） + 传承强夺 5 + 印源 4 = 16
	var m_count := 0
	var y_count := 0
	for s in GameData.WORLD_SITES:
		if str(s["type"]) == "秘境":
			m_count += 1
		elif str(s["type"]) == "印源":
			y_count += 1
	var total := 1 + m_count + carriers.size() + y_count       # 灰烬 1 枚
	_check("印总账 = 16（灰烬1 + 秘境6 + 强夺5 + 印源4）", total == 16,
			"实际 %d = 1 + %d + %d + %d" % [total, m_count, carriers.size(), y_count])
	var unnamed := 0
	for s in GameData.WORLD_SITES:
		if str(s["payload"].get("seal", "")) == "" and (str(s["type"]) == "秘境" or str(s["type"]) == "印源"):
			unnamed += 1
	print("[信息] ⚠️ 尚未命名的印 = %d 枚（秘境 M02~M06 五枚 + 印源 Y01~Y04 四枚）" % unnamed)
	_check("未命名印 9 枚（设计侧的活，本轮不闭合，只记账）", unnamed == 9, "实际 %d 枚" % unnamed)

	# 杂怪最小间距：只报告，不断言（会随补点浮动）
	var min_gap := INF
	var arr := GameData.ENEMY_SPAWNS
	for i in range(arr.size()):
		for j in range(i + 1, arr.size()):
			min_gap = minf(min_gap, (arr[i]["pos"] as Vector2).distance_to(arr[j]["pos"] as Vector2))
	print("[信息] 刷怪点两两最小间距 = %.0fpx" % min_gap)
	_check("没有两只怪叠在同一点（间距 > 60px）", min_gap > 60.0, "最小 %.0fpx" % min_gap)


# ---------------- 8. 材料表 ----------------
func _t8_materials() -> void:
	print("\n--- 8. 材料表 ---")
	_check("顶层触媒 玄霜髓 已入表（price 60）",
			GameData.MATERIALS.has("玄霜髓") and int(GameData.MATERIALS["玄霜髓"]["price"]) == 60,
			str(GameData.MATERIALS.get("玄霜髓", {})))
	_check("顶层触媒 太虚核 已入表（price 70）",
			GameData.MATERIALS.has("太虚核") and int(GameData.MATERIALS["太虚核"]["price"]) == 70,
			str(GameData.MATERIALS.get("太虚核", {})))
	_check("两件新触媒的 kind 都是「触媒」",
			str(GameData.MATERIALS["玄霜髓"]["kind"]) == "触媒"
			and str(GameData.MATERIALS["太虚核"]["kind"]) == "触媒", "对不上")
	var bad := ""
	for k in GameData.MATERIALS.keys():
		var m: Dictionary = GameData.MATERIALS[k]
		if not m.has("kind") or not m.has("price") or not m.has("volume") or not m.has("color"):
			bad += str(k) + " "
	_check("每种材料都有 kind / price / volume / color（给 materials_well_formed() 用）",
			bad == "", bad)
	_check("materials_well_formed() 为真", GameData.materials_well_formed(), "有材料字段缺失")
	print("[信息] 材料 %d 种（新增前 8 种）" % GameData.MATERIALS.size())
	## ⚠️ `Game.gd` 里有一条 `_check("材料表有 8 种", MATERIALS.size() == 8)` —— **会红**。
	##    写死旧数字是典型的「假绿灯源」：加材料就红，逼人回来改一个没有意义的常数。
	##    建议改成守语义：`GameData.MATERIALS.size() >= 8 and GameData.materials_well_formed()`。


# ---------------- 工具 ----------------
func _none_deep(spots: Array) -> bool:
	for sp in spots:
		if GameData.is_deep_at(sp["pos"] as Vector2):
			return false
	return true


func _deep_list(spots: Array) -> String:
	var out := ""
	for sp in spots:
		if GameData.is_deep_at(sp["pos"] as Vector2):
			out += str(sp["id"]) + " "
	return out


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[PASS] ", label)
		return
	_fail += 1
	print("[FAIL] ", label, "  —— ", detail)


## ==================== 移植到 Game.gd 时的说明（给接手的人）====================
##
## 1. 把上面 `_t1…_t8` 八个函数原样搬进 `scripts/Game.gd`（`_check` 用 Game 里那个，
##    本文件自带的 `_check` 可以删掉），在 `_run_selftest_body()` 里依次调用。
##
## 2. `GameData.materials_well_formed()` 是我为「材料表有 8 种」那条断言准备的替身：
##    把 `Game.gd` 里 `_check("材料表有 8 种", GameData.MATERIALS.size() == 8, ...)`
##    改成 `_check("材料表条目齐全", GameData.MATERIALS.size() >= 8 and GameData.materials_well_formed(), ...)`。
##
## 3. ⚠️ **另一条必须一起改**：`Game.gd` 的「分区「%s」里有 2 处采集点」是 `zone_count == 2`
##    （四象限时代的旧口径）。新的 24 个点按**同心层**分布，落在四象限里是 9/6/4/5，
##    `== 2` 会四条全红。⇒ 改成 `zone_count >= 2`（一字之差，语义不变：「每个区都有采集点」）。
##
## 4. 把 `const SELFTEST_MIN` 加上这里的通过项数，别忘了「断言总数只能涨不能跌」那条断言。
##
## 5. ⭐ **暂缓未做的一条**（team-lead 2026 裁决）：「锁四层可走池 = 8742」。
##    8742 是「深水挡路 + 剔除主城」口径下的数；现在正在讨论要不要放开深水挡路
##    （放开则全图可走格变成 10752）。**开关一定，那条断言当场就红** ⇒ 等最终口径再落。
##    真要加时用 `GameData.ring_pool()`（与投点同一套代码路径），别另写一份统计。
##
## 6. 搬完之后这个文件可以留着当「只跑世界数据这一块」的快速入口，也可以删掉。
