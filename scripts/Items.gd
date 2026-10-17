extends RefCounted
## 物品的「使用」与「丢弃」规则（M30.2）。**纯函数层** —— 界面只负责画和点。
##
## ⭐ 为什么单独一层：合炼有 Smith.gd、交易有 Trade.gd，都是「规则是纯函数、界面是哑的」，
##    自测因此可以直接验规则，不用去点界面。
##
## ⭐ 「使用」的第一版只有一种效果（用户定案）：**蕴灵草 → 回灵力**（25 点，和采集一口一样）。
##    其余材料明说「不能直接使用」，并写清它是什么（**合炼**用的材料 —— M30.3 起炼化不再吃材料）。
##
## ⚠️ 不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测直接报错）。


## 这个物品有没有直接的「使用」效果？返回 {} = 没有。
static func use_effect(item: String) -> Dictionary:
	var d: Dictionary = GameData.MATERIALS.get(item, {})
	var u: Variant = d.get("use", null)
	return u if u is Dictionary else {}


## 不能使用时给一句人话（界面直接显示，理由要说清 —— 和「炼化失败要说明原因」同一条规矩）。
static func use_reason(item: String, p) -> String:
	if not GameData.MATERIALS.has(item):
		return "这个东西不能直接使用"
	if use_effect(item).is_empty():
		return "%s 是合炼用的材料，不能直接使用" % item
	if float(use_effect(item).get("essence", 0.0)) <= 0.0:
		return "这个东西不能直接使用"
	if p != null and p.essence >= p.essence_max - 0.001:
		return "灵力已经满了（用了会浪费）"
	return ""


## 能用几个：⭐ **只要灵力没满就能用**（用户定案：「未满时应该还能使用，直到灵力满了再显示灵力已满」）。
## ⚠️ 踩过：这里原来按「够不够回满」取整（floor(余量 ÷ 25)），于是灵力 90/100 时**一个都用不了** ——
##    明明没满却不能用，就是这个取整写出来的。现在只拦「已经满了」这一种情况；
##    超出上限的部分算浪费（use_apply 会把它作为 wasted 报出来，界面写清）。
static func usable_amount(p, item: String, want: int) -> int:
	if p == null or want <= 0:
		return 0
	if float(use_effect(item).get("essence", 0.0)) <= 0.0:
		return 0
	if float(p.essence) >= float(p.essence_max) - 0.001:
		return 0                       # 满了：一个都不用（理由由 use_reason 说清）
	return maxi(0, mini(want, int(p.bag.count(item))))


## 真的用掉 want 个。返回 {used, gained, wasted}。
static func use_apply(p, item: String, want: int) -> Dictionary:
	var used := usable_amount(p, item, want)
	if used <= 0:
		return {"used": 0, "gained": 0.0, "wasted": 0.0}
	if not p.bag.remove(item, used):
		return {"used": 0, "gained": 0.0, "wasted": 0.0}
	var gain := float(use_effect(item).get("essence", 0.0)) * float(used)
	var before := float(p.essence)
	p.essence = minf(float(p.essence_max), before + gain)     # 上限夹住，绝不溢出
	return {"used": used, "gained": p.essence - before, "wasted": before + gain - p.essence}


## 能不能丢弃？⭐ M30.3（用户定案）：**普通灵印也能丢** —— 只有**本命印不能丢**。
static func can_discard(item: String) -> bool:
	if GameData.MATERIALS.has(item):
		return true
	return GameData.SEALS.has(item) and item != str(GameData.NATAL_SEAL)


static func discard_reason(item: String) -> String:
	if GameData.MATERIALS.has(item):
		return ""
	if item == str(GameData.NATAL_SEAL):
		return "本命印不能丢弃（它和魂魄相连，§4.2）"
	if GameData.SEALS.has(item):
		return ""
	return "这个东西不能丢弃"


## 真丢掉 n 个，返回实际丢掉的数量（材料按数量丢；灵印只有一枚，一次丢一个）。
static func discard_apply(p, item: String, n: int) -> int:
	if not can_discard(item) or n <= 0:
		return 0
	if GameData.SEALS.has(item):
		return 1 if p.discard_seal(item) else 0
	var take := mini(n, int(p.bag.count(item)))
	if take <= 0:
		return 0
	p.bag.remove(item, take)
	return take
