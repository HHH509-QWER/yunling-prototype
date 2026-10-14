extends Node2D
## 《蕴灵印》原型主控。
##
## M0：WASD 移动 + 鼠标朝向          —— 跑通「看得见、动得了」
## M1：鼠标左键普攻 + 会掉血的假人    —— 跑通「打得到、掉得了血」
## M2：--selftest 自测钩子           —— 改完之后，一条命令告诉你有没有弄坏东西
##
## 这个工程刻意保持小。规矩只有一条：
##   ⭐ 每一行你都得能解释。解释不了的，宁可先不写。
## 写不出来的地方，去 Desktop\gu\ 看思路，然后自己敲一遍 —— 不要复制。

var player: Player = null
var dummies: Array = []        # 场上所有假人
var hits: Array = []           # 短命伤害区，只用于判定和显示
var font: Font = null

var _pass := 0
var _fail := 0


func _ready() -> void:
	font = GameData.make_font()

	# 命令行钩子，跑法见 README「怎么跑自测」
	if OS.get_cmdline_user_args().has("--selftest"):
		_run_selftest()
		return

	_build_world()


# ==================== 搭世界 ====================

func _build_world() -> void:
	player = Player.new()
	player.game = self      # ⭐ 接线：Player 通过 game 回调主控，见 Player._attack_input()
	player.position = get_viewport_rect().size * 0.5
	add_child(player)

	for pos: Vector2 in GameData.DUMMY["spawns"]:
		_spawn_dummy(pos)


func _spawn_dummy(pos: Vector2) -> Dummy:
	var d := Dummy.new()
	d.position = pos
	d.hp_max = float(GameData.DUMMY["hp_max"])
	d.hp = d.hp_max
	d.font = font
	add_child(d)
	dummies.append(d)
	return d


# ==================== 伤害判定 ====================

## 生成一个短命伤害区，并立刻结算命中。
## 返回命中了几个目标 —— 自测就是靠这个返回值判断对错的。
func spawn_hit(center: Vector2, dir: Vector2, length: float, width: float, dmg: float) -> int:
	var n := 0
	# 用 duplicate()：下面可能删假人，不能一边遍历一边改原数组
	for d in dummies.duplicate():
		if not is_instance_valid(d):
			continue
		if _in_attack_area(d.position, center, dir, length, width):
			d.take_damage(dmg)
			n += 1
			if d.hp <= 0.0:
				_remove_dummy(d)

	hits.append({
		"center": center, "dir": dir, "length": length, "width": width,
		"t": 0.0, "life": float(GameData.ATTACK["life"]),
	})
	queue_redraw()
	return n


## 判断一个点是否落在「以 center 为中心、朝向 dir、长 length 宽 width」的矩形里。
##
## 做法：把点换算到**攻击者自己的坐标系**——沿朝向走多远 + 偏离朝向多少。
## 这样就不用真的去旋转矩形了。
## ⭐ 这套算法将来加「扇形」时，只要再比一个角度就行，不用推倒重来。
func _in_attack_area(p: Vector2, center: Vector2, dir: Vector2, length: float, width: float) -> bool:
	var rel := p - center
	var along := rel.dot(dir)                        # 正值 = 在攻击区前方
	var side := rel.dot(Vector2(-dir.y, dir.x))      # 垂直于朝向的分量
	return absf(along) <= length * 0.5 and absf(side) <= width * 0.5


func _remove_dummy(d: Dummy) -> void:
	dummies.erase(d)          # 先从名单里划掉（自测会查这个）
	d.queue_free()            # 再真正销毁节点


# ==================== 每帧 ====================

func _process(delta: float) -> void:
	# 短命伤害区：寿命到了就丢掉，不然会一直堆在内存里
	if hits.is_empty():
		return
	var keep: Array = []
	for h in hits:
		h["t"] = float(h["t"]) + delta
		if float(h["t"]) < float(h["life"]):
			keep.append(h)
	hits = keep
	queue_redraw()


func _draw() -> void:
	# 把伤害区画出来。不给玩家看见，他就不知道自己的攻击范围到底有多大。
	for h in hits:
		var c: Vector2 = h["center"]
		var d: Vector2 = h["dir"]
		var perp := Vector2(-d.y, d.x)               # 垂直于朝向的方向
		var hl := float(h["length"]) * 0.5
		var hw := float(h["width"]) * 0.5
		var k := 1.0 - clampf(float(h["t"]) / maxf(float(h["life"]), 0.001), 0.0, 1.0)

		var p0 := c + d * hl + perp * hw
		var p1 := c + d * hl - perp * hw
		var p2 := c - d * hl - perp * hw
		var p3 := c - d * hl + perp * hw

		draw_colored_polygon(PackedVector2Array([p0, p1, p2, p3]),
				Color(0.95, 0.85, 0.45, 0.28 * k))
		draw_polyline(PackedVector2Array([p0, p1, p2, p3, p0]),
				Color(1.0, 0.92, 0.55, 0.85 * k), 2.0)


# ==================== 自测（M2）====================
# 为什么值得写：编程 70% 的时间在找 bug，不是写新代码。
# 有了它，你每次改完只要跑一条命令，就知道自己有没有弄坏东西。

func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_pass += 1
		print("[PASS] ", label)
		return
	_fail += 1
	var tail := ""
	if detail != "":
		tail = "  —— " + detail
	print("[FAIL] ", label, tail)


func _run_selftest() -> void:
	print("=== 《蕴灵印》自测 ===")
	_build_world()

	# 1. 世界搭起来了吗
	_check("玩家已创建", player != null and is_instance_valid(player), "player 是 null")

	# 2. 假人按数据表生成了吗（数量来自 GameData，不是写死的数字）
	var want: int = GameData.DUMMY["spawns"].size()
	_check("假人数量是 %d" % want, dummies.size() == want, "实际 %d 个" % dummies.size())

	# 3. 打一下，目标血量应该**严格**减少约定的数值
	var d: Dummy = dummies[0]
	var before: float = d.hp
	var dmg: float = float(GameData.ATTACK["damage"])
	var n: int = spawn_hit(d.position, Vector2.DOWN,
			float(GameData.ATTACK["length"]), float(GameData.ATTACK["width"]), dmg)
	_check("伤害区命中 1 个目标", n == 1, "实际命中 %d 个" % n)
	_check("血量严格减少 %.0f" % dmg, is_equal_approx(d.hp, before - dmg),
			"从 %.1f 变成 %.1f" % [before, d.hp])

	# 4. 打死了就该从名单里划掉
	spawn_hit(d.position, Vector2.DOWN, 44.0, 36.0, 9999.0)
	_check("血量归零的假人已从名单移除", not dummies.has(d), "dummies 里还有它")

	# 5. 方向性：攻击区中心必须落在玩家朝向的正前方
	player.position = Vector2(400.0, 300.0)
	player.facing = Vector2.RIGHT
	var rc := player.attack_center()
	_check("朝右时攻击区中心在玩家右侧",
			rc.x > player.position.x and is_equal_approx(rc.y, player.position.y),
			"attack_center() = %s" % rc)

	print("通过 %d 项，失败 %d 项" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
