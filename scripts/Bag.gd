extends RefCounted
## 背包。**按容积算**（M30.4）：每种材料一个数量 + `MATERIALS[*].volume` 决定它占多少地方。
## ⭐ 灵石（货币）与灵印（收藏）**完全不占容积**（`GameData.volume_of()` 对它们返回 0）。
##
## ⚠️ 不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测直接报错）。

var items: Dictionary = {}      # 材料名 -> 数量
var stones := 0                 # 灵石（货币）。⭐ 不占容积


## 已占用的**容积**（不是件数！）
func capacity_used() -> int:
	var total := 0
	for k in items:
		total += int(items[k]) * GameData.volume_of(str(k))
	return total


## 还剩多少**容积**
func room_left() -> int:
	return maxi(0, int(GameData.BAG_CAPACITY) - capacity_used())


## 这件东西最多还能放几个进去？（按容积算，向下取整）
## ⚠️ 有它才敢判「捡不捡得动」：剩 1 格容积时「3 格的矿石」一个都放不下，
##    但那**不等于**「背包满了」（还放得下 1 格的草木）—— `is_full()` 判不出这件事。
func can_fit(item: String) -> int:
	var vol := GameData.volume_of(item)
	if vol <= 0:
		return 1 << 30            # 不占容积的东西永远放得下
	return room_left() / vol


func fits(item: String, amount := 1) -> bool:
	return can_fit(item) >= amount


func is_full() -> bool:
	return room_left() <= 0


func count(item: String) -> int:
	return int(items.get(item, 0))


## 放东西进去。返回**实际放进去了几个** —— 装不下的部分返回 0，
## 调用方（采集 / 拾取）拿这个返回值决定「要不要消耗掉它」。
func add(item: String, amount: int) -> int:
	if amount <= 0:
		return 0
	if item == GameData.CURRENCY:
		stones += amount
		return amount
	# ⭐ M30.4：按**容积**装 —— 装不下整件就一个都不装（不留半件，也不占半格）
	var take := mini(amount, can_fit(item))
	if take <= 0:
		return 0
	items[item] = count(item) + take
	return take


func remove(item: String, amount: int) -> bool:
	if count(item) < amount:
		return false
	items[item] = count(item) - amount
	if int(items[item]) <= 0:
		items.erase(item)
	return true


## 按数量从多到少排好的材料名，给 HUD 用。
func top_items(n: int) -> Array:
	var keys: Array = items.keys()
	keys.sort_custom(func(a, b): return int(items[a]) > int(items[b]))
	return keys.slice(0, mini(n, keys.size()))