extends SceneTree
## 一次性探测器：给「苍梧山五种新怪」找合法刷怪点。
##
## 判定条件与 `tests/world_data_test.gd` 第 6/7 段**完全一致**（那边是断言，这边是搜索）：
##   ① 不在深水（`GameData.is_deep_at` 为假）
##   ② 不在主城矩形里
##   ③ 离商人 / 出生点 >= 400px
##   ④ 离已有刷怪点 >= 200px（别叠在旧怪身上）
##   ⑤ 新点彼此之间 >= 220px（别挤成一坨）
##
## 跑法：godot --headless --path . --script res://tests/probe_spawns.gd

const CELL := 32.0

## 每种怪想要的「生地」—— 地形决定它长什么样、玩家去哪找它。
const WANT := [
	{"archetype": "铁齿竹鼠", "terrain": ["竹林", "灵田"], "count": 4},
	{"archetype": "鬼影竹叶青", "terrain": ["竹林", "泥沼"], "count": 3},
	{"archetype": "青木竹妖", "terrain": ["竹林"], "count": 3},
	{"archetype": "碧眼灵狐", "terrain": ["灵田", "草地", "竹林"], "count": 1},
	{"archetype": "变异矿鬼", "terrain": ["灵岩"], "count": 1},
]


func _initialize() -> void:
	var mer: Vector2 = GameData.MERCHANT["pos"] as Vector2
	var spawn: Vector2 = GameData.WORLD["size"] * 0.5
	var taken: Array = []
	for m in GameData.ENEMY_SPAWNS:
		taken.append(m["pos"] as Vector2)

	var out: Array = []
	var cursor := 0
	for w in WANT:
		var want_n := int(w["count"])
		var terrains: Array = w["terrain"]
		# 候选池：符合地形的格子（按地形优先级分层，再按格哈希打散，避免排成行列）
		var pool: Array = []
		for cy in range(GameData.WORLD_ROWS):
			for cx in range(GameData.WORLD_COLS):
				if cx < 4 or cy < 4 or cx >= GameData.WORLD_COLS - 4 or cy >= GameData.WORLD_ROWS - 4:
					continue              # 留 4 格边距：贴着世界边界的点走位会很别扭
				var tn := GameData.cell_terrain(cx, cy)
				if not terrains.has(tn):
					continue
				var p := Vector2((float(cx) + 0.5) * CELL, (float(cy) + 0.5) * CELL)
				if GameData.is_deep_at(p):
					continue
				if GameData.city_rect().has_point(p):
					continue
				if p.distance_to(mer) < 400.0 or p.distance_to(spawn) < 400.0:
					continue
				var bad := false
				for t in taken:
					if p.distance_to(t) < 200.0:
						bad = true
						break
				if bad:
					continue
				pool.append({"p": p, "h": GameData.cell_hash(cx, cy)})
		pool.sort_custom(func(a, b): return int(a["h"]) < int(b["h"]))
		var picked := 0
		while picked < want_n and not pool.is_empty():
			# 最远点采样：每次挑「离所有已选点最远」的那个 —— 让同种怪均匀铺开，
			# 而不是全挤在候选池排序靠前的那一角落里。
			var best_i := 0
			var best_d := -1.0
			for idx in range(pool.size()):
				var p: Vector2 = pool[idx]["p"]
				var nearest := INF
				for t in taken:
					nearest = minf(nearest, p.distance_to(t))
				if nearest > best_d:
					best_d = nearest
					best_i = idx
			if best_d < 220.0:
				break
			var bp: Vector2 = pool[best_i]["p"]
			pool.remove_at(best_i)
			taken.append(bp)
			cursor += 1
			out.append({"id": "n%02d" % cursor, "archetype": str(w["archetype"]),
					"pos": bp, "ring": GameData.ring_at(bp), "terrain": GameData.cell_terrain(
							GameData.cell_of(bp).x, GameData.cell_of(bp).y)})
			picked += 1
		print("[%s] 需要 %d 个，候选池 %d，选中 %d" % [str(w["archetype"]), want_n, pool.size() + picked, picked])

	print("\n---- 选中点 ----")
	for o in out:
		print('\t{"id": "%s", "archetype": "%s", "pos": Vector2(%.1f, %.1f), "ring": %d},   # %s' % [
			str(o["id"]), str(o["archetype"]), (o["pos"] as Vector2).x, (o["pos"] as Vector2).y,
			int(o["ring"]), str(o["terrain"])])
	print("\n---- 最小间距自检 ----")
	var mingap := INF
	for i in range(out.size()):
		for j in range(i + 1, out.size()):
			mingap = minf(mingap, (out[i]["pos"] as Vector2).distance_to(out[j]["pos"] as Vector2))
	print("新点两两最小间距 = %.1fpx" % mingap)
	quit()
