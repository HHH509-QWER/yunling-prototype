extends Node2D
## 显化中的灵印：一个有自己的血条、会被单独打的活体单位（设计圣经 §6.4）。
##
## ⭐ 为什么单独一个文件：灵印有独立生命值，所以它是一条独立的命，
##    而不是主角身上的一个数字。
##
## ⭐ 「按一下就是使用」：Player 显化它的一瞬间调一次 step_skill()，
##    之后它按冷却自己续招 —— 玩家不用一直按着，也不用管它怎么打。
##
## ⚠️ 这里刻意**不写 `class_name`**：新增全局类名要先由编辑器扫描写进
##    `.godot/global_script_class_cache.cfg`，否则命令行自测会报
##    「Identifier "Seal" not declared」。改用 preload 引用（见 Player.gd）。

## 死亡时通知命窍。代价（反噬 / 槽位受损）由 Player 结算，Seal 只负责「报死」。
## 只 emit 一次 —— 死了以后再怎么打都不再结算。
signal died(seal)

## 被打中时喊一声。Player 用它点亮「哪个部位在挨打」，HUD 用它画屏幕边缘裂纹。
signal hurt(seal)

var seal_name := ""
var hp := 1.0
var hp_max := 1.0

## 升阶带来的招式加成（由 Player 显化时写进来）。
## ⭐ 十等只影响「印血量 + 招式伤害」—— 不改形态、不改被动（那是这枚印的性格）。
var rank_scale := 1.0

var follow_target: Node2D = null      # 跟着主角走
var follow_offset := Vector2.ZERO     # = 数据表里的 mount（贴附部位）
var game: Node = null                 # 用来问「场上有哪些敌人」

var _flash := 0.0
var _bob := 0.0
var _dead := false

var _cd := 0.0                        # 招式冷却
var _last_target: Node2D = null       # 上一发打的是谁（只用于画反馈线）
var _pending_bolt: Node2D = null      # 惊雷印的预警：还没落下来的那一道
var _bolt_t := 0.0


func setup(name_key: String, hp_value: float, target: Node2D, offset: Vector2, owner_game: Node) -> void:
	seal_name = name_key
	hp_max = hp_value
	hp = hp_value
	follow_target = target
	follow_offset = offset
	game = owner_game
	add_to_group("seals")
	# ⭐ 出生就贴到身上：不然第一帧它会画在 (0,0)，自测也拿不到正确距离
	if follow_target != null and is_instance_valid(follow_target):
		position = follow_target.position + follow_offset


func data() -> Dictionary:
	return GameData.SEALS[seal_name]


func skill() -> Dictionary:
	return GameData.SEALS[seal_name]["skill"]


func kind() -> String:
	return str(skill()["kind"])


## 还活着吗。⭐ Enemy 选目标、Player 找护主都要问它 —— 和 Enemy.take_damage 一族保持同名，
## 这样「谁是活的目标」在全工程只有一个问法。
func is_alive() -> bool:
	return hp > 0.0 and not _dead


func is_dying() -> bool:
	return is_alive() and hp / maxf(hp_max, 0.001) < float(GameData.SEAL_DYING_RATIO)


func take_damage(dmg: float) -> void:
	if _dead:
		return
	hp = maxf(0.0, hp - dmg)
	_flash = 1.0
	hurt.emit(self)
	queue_redraw()
	if hp <= 0.0:
		_dead = true
		break_skill()
		died.emit(self)


## 收回 / 死亡时把「还没落地的东西」全部取消。
## ⭐ 只有这一个出口 —— 否则收回之后敌人身上还会留着灼烧。
func break_skill() -> void:
	_pending_bolt = null
	_bolt_t = 0.0
	_last_target = null


## 招式的一帧。**自测直接调它**（喂 delta），不依赖真实帧 —— 和 Enemy.step_ai 同一套成例。
func step_skill(delta: float) -> void:
	if _dead:
		return

	# 先结算「上一发惊雷」的预警：到点了才真的劈下来
	if _pending_bolt != null:
		_bolt_t -= delta
		if _bolt_t <= 0.0:
			if is_instance_valid(_pending_bolt) and _pending_bolt.has_method("take_damage"):
				# 落雷：紫色跳字（重击，带停顿与震屏）
				_pending_bolt.take_damage(_power(float(skill()["damage"])), Color(0.74, 0.64, 0.98))
			_pending_bolt = null
			queue_redraw()

	_cd = maxf(0.0, _cd - delta)
	if _cd > 0.0:
		return

	match kind():
		"guard":
			return                                  # 常驻：由 Player.take_damage() 主动来问它
		"shield":
			return                                  # 一次性防御：盾挂在主角身上，它自己不行动
		"ember":
			var t := pick_target(float(skill()["range"]))
			if t != null:
				t.add_dot(_power(float(skill()["damage"])), float(skill()["duration"]), self, float(skill()["tick"]),
						Color(0.98, 0.66, 0.34))          # 灼烧：橙色跳字
				_last_target = t
				_cd = float(skill()["cooldown"])
				queue_redraw()
		"bolt":
			var t2 := pick_target(float(skill()["range"]))
			if t2 != null:
				_pending_bolt = t2                      # 先挂预警，到点才落雷
				_bolt_t = float(skill()["warn"])
				_last_target = t2
				_cd = float(skill()["cooldown"])
				queue_redraw()
		"heal":
			# ⭐ 云雨印：不打架，只滋润主人。回血由 Player.heal() 结算（不超上限）。
			#    ⚠️ 这一支是 M12 之后补的 —— 之前 kind="heal" 一直在空转，招式什么也不做。
			if is_instance_valid(follow_target) and follow_target.has_method("heal"):
				follow_target.heal(_power(float(skill()["heal"])))
				_cd = float(skill()["cooldown"])
				queue_redraw()


## 升阶放大招式数值。⭐ 只有这一处缩放 —— 想改「十等收益」只改 GameData.RANK_GAIN。
func _power(base: float) -> float:
	return base * rank_scale


## 这一发招式结算完了吗？instant 型（惊雷印）靠它决定「可以自动收回了」。
## ⭐ 预警还没落地时绝不能收回 —— 否则 break_skill() 会把那一发雷取消掉。
func is_skill_settled() -> bool:
	if kind() == "bolt":
		return _pending_bolt == null
	return true


## 有没有「已经挂上、还没落地」的一击（惊雷印的预警）。
func has_pending_strike() -> bool:
	return _pending_bolt != null


## 给 HUD 用的一句状态。⭐ HUD 不该去猜灵印的内部字段，问它就对了。
func state_text() -> String:
	match kind():
		"ember":
			return "灼烧中"
		"bolt":
			return "落雷·蓄力" if _pending_bolt != null else "落雷·待发"
		"guard":
			return "护主中"
		"shield":
			return "护盾中"
	return "显化中"


## 射程内最近的敌人。确定性选择，不需要注入随机数。
func pick_target(range_px: float) -> Node2D:
	if game == null or not game.has_method("nearest_enemy_to"):
		return null
	return game.nearest_enemy_to(position, range_px)


func _process(delta: float) -> void:
	if follow_target != null and is_instance_valid(follow_target):
		position = follow_target.position + follow_offset
	_bob += delta * 5.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
	step_skill(delta)
	queue_redraw()


func _draw() -> void:
	var d := data()
	var r := float(d["radius"])
	var col: Color = d["color"]
	if _flash > 0.0:
		col = col.lerp(Color(1.0, 1.0, 1.0), _flash * 0.8)

	# 濒死：忽明忽暗（纯表现，不改数值）—— 玩家不用盯血条就知道它快碎了
	var alpha := 1.0
	if is_dying():
		alpha = 0.35 + 0.65 * (0.5 + 0.5 * sin(_bob * 2.6))
	col.a = alpha

	draw_circle(Vector2(2.0, 6.0), r, Color(0.0, 0.0, 0.0, 0.28 * alpha))   # 影子：两种路径都要
	# ⭐ M30.5 路线②：**有贴图就画贴图**（形状 / 描边 / 高光都在图里，见 art/seals/），
	#    没有就回退到形状语言 —— 和其它单位完全同一套规矩（ActorVisual）。
	#    ⚠️ 贴图是 32×32 居中画，形状只占中间约 22px —— 和原来那个 r≈11 的圆大小一致。
	var tex := ActorVisual.texture_of(d)
	if tex != null:
		ActorVisual.draw_unit(self, tex, d, _flash, _bob_offset(), alpha)
	else:
		draw_circle(Vector2(0.0, _bob_offset()), r, col)
		draw_arc(Vector2(0.0, _bob_offset()), r, 0.0, TAU, 22, Color(0.16, 0.17, 0.20, alpha), 1.5)

	# 招式反馈：让「它在干什么」一眼可见
	if _pending_bolt != null and is_instance_valid(_pending_bolt):
		draw_line(Vector2.ZERO, to_local(_pending_bolt.position), Color(0.85, 0.85, 1.0, 0.55), 2.0)
	elif kind() == "guard" and follow_target != null:
		draw_line(Vector2.ZERO, to_local(follow_target.position), Color(0.55, 0.80, 0.95, 0.35), 2.0)

	# 灵印血条：比主角的小一号，用青色和「敌人 / 主角」区分开
	draw_rect(Rect2(-18.0, -r - 12.0, 36.0, 4.0), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(-18.0, -r - 12.0, 36.0 * clampf(hp / maxf(hp_max, 0.001), 0.0, 1.0), 4.0),
			Color(0.45, 0.80, 0.85))


func _bob_offset() -> float:
	return sin(_bob) * 2.0