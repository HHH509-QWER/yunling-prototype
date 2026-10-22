extends RefCounted
## 存档（M12）。⭐ 存成 JSON —— 人能读、能改、能 diff，原型阶段没有比这更好调试的格式。
##
## ⭐ 序列化是**纯函数**（to_dict / from_dict 不碰磁盘）：自测直接验这两个，
##    不会污染真存档；磁盘读写只是薄薄一层包装。
## ⚠️ 不写 class_name（新增全局类名要先由编辑器扫描，否则命令行自测直接报错）。

const VERSION := 9      # 2：灵印等级/商人货架；7：世界放大 4 倍（M30.25）；8：世界容器改尺寸（M31）
                        # 9（M34）：**多区域** —— 存档记 `region` + `anchor_global`（全局坐标）
## ⭐ M34：v9 起存**全局坐标**（区域原点 × 32 + 局部）。为什么不在存档里只存区域局部坐标：
##    那样一旦把「切换」升级成「无缝」，所有存档都要再迁一次。全局坐标让**区域布局**变成
##    纯数据（改 REGIONS 的 origin 即可），存档不用懂它。
const VERSION_REGION := 9
## ⭐ M31 Step 0：世界容器从 5120×2880 改成 3584×3072 —— 旧档坐标按比例缩放后 clamp，
##    否则一读档就跑到图外（纵横比也变了，必须**分轴**缩放，不能只乘一个数）。
const VERSION_WORLD_RESIZE := 8
## v7 及之前的世界尺寸。⭐ 从它到 GameData.WORLD["size"] 的比值就是迁移系数。
const WORLD_SIZE_V7 := Vector2(5120.0, 2880.0)
## ⭐ M30.25：世界从 1280×720 放大到 5120×2880（4×4 屏）—— 旧档坐标要 ×4，否则一读档就跑到左上角。
const VERSION_WORLD_QUAD := 7
                        # 3：炼化度从「养熟度」变成「融合度 = 使用前提」，旧档要补满
                        # 4：加了「学会的印诀」(learned) —— 它是知识，回溯也带不走
                        # 5：**世界与所有距离减半**（M29 像素基准：相机 zoom = 2）—— 旧档坐标要减半
                        # 6：**背包里的印**（bag_seals）—— 收藏无上限（M29.5）
const VERSION_REFINE_GATE := 3
const VERSION_WORLD_HALVED := 5


static func to_dict(game) -> Dictionary:
	var p = game.player
	## ⭐ M34：锚点存**全局坐标**（区域原点 + 局部），同时保留一个 `anchor` 局部值给旧读取器/人看。
	var reg := str(game.current_region)
	var gl: Vector2 = GameData.local_to_global(reg, game.spawn_point)
	return {
		"version": VERSION,
		"region": reg,
		"anchor_global": [gl.x, gl.y],
		"anchor": [game.spawn_point.x, game.spawn_point.y],
		"realm": int(p.realm),
		"slots": p.slot_seal.duplicate(),
		"reserve": p.reserve_seals.duplicate(),
	"bag_seals": p.bag_seals.duplicate(),
		"seized": p.seized_seals.duplicate(),
		"refine": p.seal_refine.duplicate(),
		"ranks": p.seal_rank.duplicate(),
		"cultivation": p.cultivation,
		"stock": game.merchant_stock.duplicate(),
		"bag": p.bag.items.duplicate(),
		"stones": int(p.bag.stones),
		"learned": p.learned_combos.duplicate(),
		"deaths": int(game.deaths),
	}


## 把存档写回游戏。返回是否成功。
## ⚠️ 槽位数不符的存档一律拒绝 —— 宁可读不进来，也不要读进来一个长短不一的命窍。
static func from_dict(game, data: Dictionary) -> bool:
	if not data.has("anchor") and not data.has("anchor_global"):
		return false
	var slots: Array = data.get("slots", [])
	var p = game.player
	if slots.size() != p.slot_seal.size():
		return false
	## ⭐ M34：**先定区域，再算坐标** —— 区域的 origin 参与全局↔局部换算。
	##    顺序反了的话，旧档（没有 region 字段）会按上一区的 origin 去减，直接错位。
	var want_region := str(data.get("region", GameData.START_REGION))
	if not GameData.REGIONS.has(want_region):
		want_region = GameData.START_REGION
	GameData.set_region(want_region)
	game.current_region = want_region
	if data.has("anchor_global"):
		## v9 起：全局坐标。
		var ag: Array = data["anchor_global"]
		game.spawn_point = GameData.global_to_local(want_region,
				Vector2(float(ag[0]), float(ag[1])))
	else:
		## v8 及更老：`anchor` 是**单世界**里的局部坐标 —— 就是 cangwu 的局部坐标。
		var a: Array = data["anchor"]
		game.spawn_point = Vector2(float(a[0]), float(a[1]))
		# ⭐ 迁移：v5 起世界与所有距离**减半**（M29：相机 zoom = 2，屏幕观感不变、像素粗一倍）。
		#    旧档里的坐标是旧世界的 —— 不减半会把出生点丢到世界外（旧中心 1280,720
		#    正好是新世界 1280×720 的右下角）。
		if int(data.get("version", 0)) < VERSION_WORLD_HALVED:
			game.spawn_point *= 0.5
		# ⭐ 迁移：v7 起世界**放大 4 倍**（5120×2880）。旧档坐标 ×4 才落在同一片地形上。
		if int(data.get("version", 0)) < VERSION_WORLD_QUAD:
			game.spawn_point *= 4.0
		# ⭐ 迁移：v8 起世界容器**改尺寸**（5120×2880 → 3584×3072）。
		#    旧档坐标按**分轴比例**缩放（×0.7 / ×1.0667）才落在同一片地形上。
		#    ⚠️ 不能只乘一个数：纵横比从 16:9 变成 7:6，等比缩放会把出生点挤偏。
		if int(data.get("version", 0)) < VERSION_WORLD_RESIZE:
			game.spawn_point *= GameData.region_size(GameData.START_REGION) / WORLD_SIZE_V7
	# 兜底：坐标一律夹进**当前区域**内（手改坏的存档也不至于把主角丢到图外）
	var ws: Vector2 = GameData.region_size(want_region)
	game.spawn_point = Vector2(clampf(game.spawn_point.x, 0.0, ws.x),
			clampf(game.spawn_point.y, 0.0, ws.y))
	p.realm = int(data.get("realm", 1))
	p.slot_seal = slots.duplicate()
	p.reserve_seals = (data.get("reserve", []) as Array).duplicate()
	p.seized_seals = (data.get("seized", []) as Array).duplicate()
	# ⭐ M29.5：背包里的印。旧档没有这个字段 → 默认空数组（不需要别的迁移）
	p.bag_seals = (data.get("bag_seals", []) as Array).duplicate()
	p.seal_refine = (data.get("refine", {}) as Dictionary).duplicate()
	# ⭐ 迁移：v2 及以前的「炼化度」不是使用门槛（旧版满不满都能用）。
	#    现在它是门槛 —— 若不补满，玩家的印会**全部变成废铁**。
	if int(data.get("version", 0)) < VERSION_REFINE_GATE:
		for name_key6 in p.seal_refine.keys():
			p.seal_refine[name_key6] = float(GameData.REFINE["max"])
	p.seal_rank = (data.get("ranks", {}) as Dictionary).duplicate()
	p.cultivation = float(data.get("cultivation", 0.0))
	p.learned_combos = (data.get("learned", []) as Array).duplicate()
	# ⚠️ 货架要**原地改**：Merchant 拿着这个 Dictionary 的引用（和快照那边同一个道理）
	# ⚠️ 而且**只有存档里真有这个字段才覆盖** —— 否则读一个旧存档会把货架清空
	#    （踩过：加了 stock 字段之后，旧存档一读进来，商人货架就空了）
	if data.has("stock"):
		game.merchant_stock.clear()
		for k in data["stock"]:
			game.merchant_stock[str(k)] = int(data["stock"][k])
	p.bag.items = (data.get("bag", {}) as Dictionary).duplicate()
	p.bag.stones = int(data.get("stones", 0))
	game.deaths = int(data.get("deaths", 0))
	p.refresh_limits()
	p.hp = p.hp_max
	p.essence = 0.0
	p.queue_redraw()
	return true


static func save_to(path: String, game) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(game), "  "))
	f.close()
	return true


static func load_from(path: String, game) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return false
	return from_dict(game, parsed)