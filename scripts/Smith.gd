extends RefCounted
## 合炼的**规则层**（M13）。
##
## ⭐ 为什么单独一个文件：界面只负责「画什么、点什么」，
##    「能不能炼 / 成功率多少 / 失败了会失去什么」全在这里 —— 喂参数就能穷举验。
## ⚠️ 不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测直接报错）。


## 现在**能做的**配方。mode 传空就是全部。
static func available(game, mode := "") -> Array:
	var out: Array = []
	for r in GameData.RECIPES:
		if mode != "" and str(r["mode"]) != mode:
			continue
		if can_afford(game, r):
			out.append(r)
	return out


static func can_afford(game, recipe: Dictionary) -> bool:
	return missing(game, recipe).is_empty()


## 还缺什么？返回一串**人能读的话** —— HUD 与面板直接拿去显示。
static func missing(game, recipe: Dictionary) -> Array:
	var p = game.player
	var out: Array = []
	if str(recipe["mode"]) == "upgrade":
		var main := str(recipe["main"])
		if not p.has_seal(main):
			out.append("没有「%s」" % main)
	else:
		for key in [str(recipe["a"]), str(recipe["b"])]:
			if not p.has_seal(key):
				out.append("没有「%s」" % key)
			elif not p.can_use_as_material(key):
				out.append("「%s」是本命印，不能当材料" % key)
	for item in recipe.get("materials", {}):
		var need := int(recipe["materials"][item])
		var have: int = p.bag.count(str(item))
		if have < need:
			out.append("%s 还差 %d" % [item, need - have])
	if p.essence < float(GameData.FURNACE["essence_cost"]):
		out.append("灵力不足（要 %d）" % int(GameData.FURNACE["essence_cost"]))
	return out


## 目标等级（成功率要用它）。
static func target_rank(recipe: Dictionary) -> int:
	if str(recipe["mode"]) == "upgrade":
		return int(recipe["to_rank"])
	return int(GameData.SEALS[str(recipe["result"])]["rank"])


## 成功率（%）。⭐ 全部来自 GameData.FURNACE —— 想调难度只改那张表。
static func chance(game, recipe: Dictionary) -> float:
	var f: Dictionary = GameData.FURNACE
	var p = game.player
	var mats: Dictionary = recipe.get("materials", {})
	var souls := int(mats.get("灵魄", 0))
	var c := float(f["base_chance"])
	c += float(f["per_material"]) * float(mats.size())
	c += float(f["per_soul"]) * float(souls)
	c -= float(f["per_rank"]) * float(maxi(0, target_rank(recipe) - 1))
	return clampf(c, 5.0, 95.0)


## 火候指针点在绿区里吗？⭐ 绿区居中，宽度来自数据表。
static func in_green(pointer: float) -> bool:
	var half := float(GameData.FURNACE["green_zone"]) * 0.5
	return absf(pointer - 0.5) <= half


## 算一次合炼的结果 —— **不改任何状态**（纯函数，所以自测能穷举）。
##   pointer_hit:  火候有没有点在绿区（设计圣经 §3.3：失误则失败）
##   event_choice: 0 = 不管，1 = 加料，2 = 减料
##   roll:         注入的随机数（0..1），自测传定值
static func plan(game, recipe: Dictionary, pointer_hit: bool, event_choice: int, roll: float) -> Dictionary:
	var f: Dictionary = GameData.FURNACE
	var delta := 0.0
	if event_choice == 1:
		delta = float(f["event_bonus"])
	elif event_choice == 2:
		delta = -float(f["event_penalty"])
	var c := clampf(chance(game, recipe) + delta, 5.0, 95.0)
	if not pointer_hit:
		return {"success": false, "reason": "pointer_miss", "chance": c, "event_delta": delta}
	return {"success": roll * 100.0 < c, "reason": "chance", "chance": c, "event_delta": delta}


## 把结果落到游戏上。返回「这次失去了什么、得到了什么」—— HUD 与自测都读它。
## ⭐ 失败规则（§3.3）：**辅材全部浪费**；合成失败时两枚印也一起没；升阶失败时印还在。
static func apply(game, recipe: Dictionary, success: bool) -> Dictionary:
	var p = game.player
	var lost_mats: Array = []
	for item in recipe.get("materials", {}):
		var need := int(recipe["materials"][item])
		p.bag.remove(str(item), need)
		lost_mats.append("%s×%d" % [item, need])
	p.essence = maxf(0.0, p.essence - float(GameData.FURNACE["essence_cost"]))
	var report := {"success": success, "result": "", "rank": 0,
			"lost_materials": lost_mats, "lost_seals": []}

	if str(recipe["mode"]) == "upgrade":
		var main := str(recipe["main"])
		if success:
			report["result"] = main
			report["rank"] = p.rank_up(main)
	else:
		var a := str(recipe["a"])
		var b := str(recipe["b"])
		p.consume_seal(a)
		p.consume_seal(b)
		report["lost_seals"] = [a, b]
		if success:
			p.gain_seal(str(recipe["result"]))
			report["result"] = str(recipe["result"])
			report["rank"] = p.rank_of(str(recipe["result"]))
	return report