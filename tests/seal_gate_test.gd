extends SceneTree
## 「封印」机制的**纯函数**断言：给定品阶，算得出正确的「所需境界」串。
##
## ⚠️⚠️ 为什么不写进 Game.gd 的 `-- --selftest`：
##    那一整套断言住在 `Game.gd` 里，而本轮 `Game.gd` / `GameData.gd` 有**别人的未提交改动**
##    （主城剪影 F10 / 世界内容数据层）。按文件所有权铁律，本轮一步都不碰这两个文件，
##    所以这里是**独立入口**，单独一条命令跑：
##
##        Godot_v4.7.2-stable_win64_console.exe --headless --path . \
##            --script res://tests/seal_gate_test.gd
##
##    ⭐ 等 Game.gd 腾出手，把 `_test_seal_gate()` 整段搬进 `_run_selftest_body()`、
##      调一次，再把 `SELFTEST_MIN` 加上这里通过的项数即可 —— 见文件末尾的移植说明。
##
## ⭐ 测的是**纯函数**：`Player.seal_gate_realm_name(rank)` 只查 `GameData.REALMS` 的
##    `seal_rank_max`，不看当前境界、不碰画面、不需要场景树 —— 所以它好测。
## ⚠️ 别在这里 `add_child()` 任何东西：本文件跑在 `--script` 模式，没有 Main.tscn。

var _pass := 0
var _fail := 0


func _initialize() -> void:
	var p := Player.new()

	# ---------------- 1. 品阶 → 所需境界（本轮的核心断言）----------------
	_check("1 等印：无封印（炼气就能驾驭）", p.seal_gate_realm_name(1) == "",
			"实际「%s」" % p.seal_gate_realm_name(1))
	_check("2 等印：无封印（炼气就能驾驭）", p.seal_gate_realm_name(2) == "",
			"实际「%s」" % p.seal_gate_realm_name(2))
	_check("3 等印：需 金丹", p.seal_gate_realm_name(3) == "金丹",
			"实际「%s」" % p.seal_gate_realm_name(3))
	_check("4 等印：需 元婴", p.seal_gate_realm_name(4) == "元婴",
			"实际「%s」" % p.seal_gate_realm_name(4))
	_check("5 等印：需 化神", p.seal_gate_realm_name(5) == "化神",
			"实际「%s」" % p.seal_gate_realm_name(5))

	# ---------------- 2. 按印名问（界面三处都问这个）----------------
	_check("玄甲印（二等）→ 无封印，界面小字为空", p.seal_gate_text("玄甲印") == "",
			"实际「%s」" % p.seal_gate_text("玄甲印"))
	_check("灰烬印（一等）→ 无封印，界面小字为空", p.seal_gate_text("灰烬印") == "",
			"实际「%s」" % p.seal_gate_text("灰烬印"))
	_check("空印名 → 无封印（界面不该画出半个「封印 · 」）", p.seal_gate_text("") == "")
	_check("表里没有的名字 → 无封印（读表不该炸）", p.seal_gate_text("不存在的印") == "")

	# ---------------- 3. 和门槛谓词自洽（5 境 × 10 阶 = 50 条）----------------
	# ⭐ 这两条规则必须永远对得上：`seal_gate_realm_name` 说「要几重」，
	#    `is_sealed_rank` 说「我现在够不够」—— 一个改了另一个没改，界面就会说谎。
	var idx: Dictionary = {}
	for k in GameData.REALMS.keys():
		idx[str(GameData.REALMS[k]["name"])] = int(k)
	for r in GameData.REALMS.keys():
		p.realm = int(r)
		for rank in range(1, 11):
			var gate: String = p.seal_gate_realm_name(rank)
			var need: int = 1 if gate == "" else int(idx[gate])
			var want_sealed: bool = need > int(r)
			_check("%s（第 %d 境）· %d 等印：%s" % [str(GameData.REALMS[r]["name"]), int(r), rank,
					"封印" if want_sealed else "可用"],
					p.is_sealed_rank(rank) == want_sealed,
					"谓词说 %s，查表说 %s" % ["是" if p.is_sealed_rank(rank) else "否",
							"是" if want_sealed else "否"])

	# ---------------- 4. 门槛**只看品阶，不看位置** ----------------
	#    「它在活跃槽 / 备用 / 背包」不该改变「能不能用」的结论（设计定案）。
	p.realm = 1
	p.seal_refine["玄甲印"] = float(GameData.REFINE["max"])
	p.reserve_seals = ["玄甲印"]
	var in_reserve: bool = bool(p.can_use("玄甲印")["ok"])
	p.reserve_seals = []
	p.bag_seals = ["玄甲印"]
	var in_bag: bool = bool(p.can_use("玄甲印")["ok"])
	_check("已炼满的二等印：在备用里能用", in_reserve)
	_check("同一枚印挪到背包里，结论不变（门槛不看位置）", in_bag == in_reserve,
			"备用 %s / 背包 %s" % [in_reserve, in_bag])
	_check("空槽位：不能用", not bool(p.can_use("")["ok"]))
	p.seal_refine.erase("玄甲印")
	_check("未融合的印：理由里写清炼化度", str(p.can_use("玄甲印")["reason"]).contains("未融合"),
			str(p.can_use("玄甲印")["reason"]))

	# ---------------- 5. 定死「为什么必须提前告知」----------------
	#    炼满一枚印 = 13 次 × 10 灵力 = 130 灵力，而炼气期满管才 100。
	#    这条断言在数值被改轻/改重时会红 —— 它是「提前告知」这条设计的存在理由。
	var times: int = int(ceilf(float(GameData.REFINE["max"]) / float(GameData.REFINE["press_gain"])))
	var total_cost: float = float(times) * float(GameData.REFINE["press_cost"])
	_check("炼满一枚印 = %d 次 × %.0f 灵力 = %.0f 灵力" % [times, float(GameData.REFINE["press_cost"]),
			total_cost], is_equal_approx(total_cost, 130.0), "实际 %.0f" % total_cost)
	_check("炼气期满管（%.0f）装不下炼满一枚印的 %.0f 灵力 —— 所以封印必须提前告知"
			% [float(GameData.REALMS[1]["essence_max"]), total_cost],
			total_cost > float(GameData.REALMS[1]["essence_max"]))

	# ---------------- 6. 突破那一帧的「解封」记账 ----------------
	#    ⚠️ 目前**表里最深也才二等**（炼气 cap = 2），所以今天没有印会被封印 ——
	#       这里只能验「不该报的时候不许乱报」。等 rank ≥ 3 的印进表，这段才有正向样本。
	p.realm = 1
	p.cultivation = p.cultivation_max()
	_check("修为攒满就能突破（夹具）", p.breakthrough(), "突破失败")
	_check("炼气 → 筑基：印品阶上限都是 2，这一帧没有任何印解封",
			p.just_unsealed.is_empty(), "报了 %s" % str(p.just_unsealed))
	_check("突破后境界真的 +1", p.realm == 2, "实际第 %d 境" % p.realm)

	# 覆盖度提示（不是断言 —— 数据变了别红，只是提醒）
	var deepest: int = 0
	for k in GameData.SEALS.keys():
		deepest = maxi(deepest, int(GameData.SEALS[k]["rank"]))
	print("[覆盖] 当前印表最深 = %d 等；炼气 cap = %d ⇒ 今天没有印会被封印（%s）" % [
			deepest, int(GameData.REALMS[1]["seal_rank_max"]),
			"封印路径无正向样本" if deepest <= int(GameData.REALMS[1]["seal_rank_max"]) else "有正向样本"])

	print("通过 %d 项，失败 %d 项" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[PASS] ", label)
		return
	_fail += 1
	print("[FAIL] ", label, "  —— ", detail)


## ==================== 移植到 Game.gd 时的说明（给接手的人）====================
##
## 1. 把上面 `_initialize()` 里第 1~6 段的内容原样搬成：
##
##        func _test_seal_gate() -> void:
##            var p := Player.new()
##            ...（同上，`_check` 直接用 Game 里那个）
##
##    放进 `scripts/Game.gd`，在 `_run_selftest_body()` 里加一行 `_test_seal_gate()`。
##
## 2. 把 `const SELFTEST_MIN` 加上这里的通过项数（本文件当前 66 项，见上面输出），
##    别忘了「断言总数只能涨不能跌」那条断言会盯着这个数。
##
## 3. 搬完之后这个文件可以留着当「只跑封印这一块」的快速入口，也可以删掉。
