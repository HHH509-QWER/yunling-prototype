extends RefCounted
## 交易的**规则层**（M14）。⭐ 和 Smith 一样：界面只负责画和点，
## 「买不买得起 / 卖多少钱 / 货还有没有」全在这里，喂参数就能验。
## ⚠️ 不写 class_name。


## 货架（只剩货的，数量 > 0）。
static func stock_list(game) -> Array:
	var out: Array = []
	for entry in GameData.MERCHANT["stock"]:
		var item := str(entry["item"])
		if game.merchant.available(item) > 0:
			out.append(item)
	return out


## 他卖你的这一列：**先货架（限量），再服务（不限量）**。
## ⭐ 统一成条目，面板画的和点的用同一份数据 —— 加一种服务不用碰界面。
static func buy_entries(game) -> Array:
	var out: Array = []
	for item in stock_list(game):
		out.append({"kind": "item", "id": str(item), "price": buy_price(str(item)),
				"detail": "剩 %d" % game.merchant.available(str(item))})
	for s in GameData.MERCHANT.get("services", []):
		out.append({"kind": "service", "id": str(s["id"]), "label": str(s["label"]),
				"price": int(s["price"]), "amount": float(s["amount"]), "detail": "不限量"})
	return out


## 你卖他的这一列（背包里的材料）。
static func sell_entries(game) -> Array:
	var out: Array = []
	for item in sell_list(game):
		out.append({"kind": "item", "id": str(item), "price": sell_price(str(item)),
				"detail": "×%d" % game.player.bag.count(str(item))})
	return out


static func service_of(id: String) -> Dictionary:
	for s in GameData.MERCHANT.get("services", []):
		if str(s["id"]) == id:
			return s
	return {}


## ⭐ 把半成品补成完整条目：直接传一个材料名、或者数据表里那条原始服务，都能用。
##    这样调用方不必自己凑齐 kind / price / detail —— 界面、自测、以后的新服务都好写。
static func normalize(entry: Dictionary) -> Dictionary:
	if entry.has("kind") and entry.has("price"):
		return entry
	var id := str(entry.get("id", ""))
	var s := service_of(id)
	if not s.is_empty():
		return {"kind": "service", "id": id, "label": str(s["label"]),
				"price": int(s["price"]), "amount": float(s["amount"]), "detail": "不限量"}
	return {"kind": "item", "id": id, "price": buy_price(id), "detail": ""}


## 这个条目现在买不买得起？（货架条目看库存，服务条目看有没有满）
static func can_buy_entry(game, raw_entry: Dictionary) -> bool:
	var entry := normalize(raw_entry)
	if str(entry["kind"]) == "service":
		if game.player.bag.stones < int(entry["price"]):
			return false
		if str(entry["id"]) == "essence":
			return game.player.essence < game.player.essence_max - 0.001
		return true
	return can_buy(game, str(entry["id"]))


## 买一个条目（货架或服务，自动分派）。
static func buy_entry(game, raw_entry: Dictionary) -> Dictionary:
	var entry := normalize(raw_entry)
	if str(entry["kind"]) != "service":
		return buy(game, str(entry["id"]))
	if not can_buy_entry(game, entry):
		return {"ok": false, "reason": "买不了：灵石不够，或者灵力已经满了"}
	var p = game.player
	p.bag.stones -= int(entry["price"])
	if str(entry["id"]) == "essence":
		p.essence = minf(p.essence_max, p.essence + float(entry["amount"]))
	return {"ok": true, "spent": int(entry["price"]), "item": str(entry["label"]),
			"count": 1, "service": true}


## 背包里可以卖的东西（按数量从多到少）。
static func sell_list(game) -> Array:
	return game.player.bag.top_items(8)


## 他的买价（写死在货架上）。
static func buy_price(item: String) -> int:
	for entry in GameData.MERCHANT["stock"]:
		if str(entry["item"]) == item:
			return int(entry["price"])
	return -1


## 他收东西的价：基础价值 × sell_ratio（至少 1 —— 卖东西不能白送）。
static func sell_price(item: String) -> int:
	if not GameData.MATERIALS.has(item):
		return 0
	var base := float(GameData.MATERIALS[item]["price"])
	return maxi(1, int(floorf(base * float(GameData.MERCHANT["sell_ratio"]))))


## 买得起吗？（灵石够 + 有货 + 背包还有地方）
static func can_buy(game, item: String) -> bool:
	var price := buy_price(item)
	if price < 0 or game.merchant.available(item) <= 0:
		return false
	if game.player.bag.stones < price:
		return false
	return game.player.bag.fits(item)      # ⭐ M30.4：按容积判，别只看 is_full()（剩 1 格也买不走 3 格的矿石）


## 买一个。返回这次花了多少灵石 / 拿到了什么。
static func buy(game, item: String) -> Dictionary:
	var price := buy_price(item)
	if not can_buy(game, item):
		return {"ok": false, "reason": "买不了：灵石不够 / 没货 / 背包满"}
	var p = game.player
	p.bag.stones -= price
	game.merchant.stock[item] = game.merchant.available(item) - 1
	p.bag.add(item, 1)
	return {"ok": true, "spent": price, "item": item, "count": 1}


## 卖一个。
static func sell(game, item: String) -> Dictionary:
	var p = game.player
	if p.bag.count(item) <= 0:
		return {"ok": false, "reason": "背包里没有这个"}
	var price := sell_price(item)
	p.bag.remove(item, 1)
	p.bag.stones += price
	return {"ok": true, "earned": price, "item": item, "count": 1}


## 能不能卖？（有货就行）
static func can_sell(game, item: String) -> bool:
	return game.player.bag.count(item) > 0