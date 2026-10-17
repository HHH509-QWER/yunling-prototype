extends Node2D
## 敌人（M4）：会追击、会还手；智谋型有概率改打显化中的灵印。
##
## ⚠️ 和 Seal.gd 一样不写 class_name —— 新增全局类名要先由编辑器扫描写进
##    .godot/global_script_class_cache.cfg，否则命令行自测报「Identifier not declared」。
##
## ⭐ 可测性设计：所有判断都在 step_ai(delta) 里，它是**唯一**的决策入口。
##    自测直接调它、喂一个 delta，不需要等真实帧、也不需要把游戏跑起来。

signal died(enemy)

var archetype := ""
var hp := 1.0
var hp_max := 1.0

## 挂在身上的持续伤害。每项：{dmg, tick, tick_left, left, source}
## ⭐ source 记的是「哪枚灵印点的火」—— 灵印一收回，这些火必须能一次清干净。
var dots: Array = []

var player: Node2D = null      # 主角
var game: Node = null          # 用来问「场上现在有哪些显化中的灵印」

## ⭐ 它身上带着的那枚印（灵师专属）。打死它才能强夺。
var carries := ""

## ⭐ 精英：不是新原型，是**同一个原型加档** —— 同一个 AI、同一个形状，更大更硬更疼、掉得更多。
var elite := false

var _cd := 0.0
var _flash := 0.0
var _bob := 0.0
var _warn := 0.0            # 预警剩余时间（灵师：施法；蛮兽：蓄力）
var _cast_at := Vector2.ZERO  # 落雷圈钉在哪儿
var _charge_t := 0.0        # 冲刺剩余时间（蛮兽）
var _charge_dir := Vector2.ZERO  # 冲刺方向（蓄力结束时锁定）
var _aggro := false
var _target: Node2D = null


func setup(key: String, target_player: Node2D, owner_game: Node, elite_flag := false) -> void:
	archetype = key
	elite = elite_flag
	var d: Dictionary = GameData.ENEMY[key]
	hp_max = float(d["hp_max"])
	if elite:
		hp_max *= float(GameData.ELITE["hp_mult"])
	hp = hp_max
	player = target_player
	game = owner_game
	set_meta("archetype", key)      # 开发计划 §M4：实体要有 archetype 字段
	add_to_group("enemies")


func data() -> Dictionary:
	return GameData.ENEMY[archetype]


## 实际体型（精英会放大）。
func radius_value() -> float:
	var r := float(data()["radius"])
	return r * (float(GameData.ELITE["radius_mult"]) if elite else 1.0)


## 实际伤害（精英更疼）。
func damage_value() -> float:
	var base := float(data()["attack_damage"])
	return base * (float(GameData.ELITE["damage_mult"]) if elite else 1.0)


func behavior() -> String:
	return str(data().get("behavior", "melee"))


func is_alive() -> bool:
	return hp > 0.0


## 挨打。color 决定跳字颜色；juice = false 用于持续伤害的「每跳」（只跳字，不震不卡帧）。
func take_damage(dmg: float, color := Color(0.95, 0.95, 0.92), juice := true) -> void:
	if hp <= 0.0:
		return
	hp = maxf(0.0, hp - dmg)
	_flash = 1.0
	if game != null:
		if game.has_method("add_number"):
			game.add_number(position + Vector2(0.0, -22.0), dmg, color)
		if juice:
			if game.has_method("hitstop"):
				game.hitstop(float(GameData.JUICE["hitstop_hit"]))
			if game.has_method("add_shake"):
				game.add_shake(float(GameData.JUICE["shake_hit"]))
	queue_redraw()
	if hp <= 0.0:
		died.emit(self)


func _process(delta: float) -> void:
	step_ai(delta)
	_bob += delta * 5.0
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
	queue_redraw()


## AI 的一帧。自测直接调它 —— 所以这里不许有「等真实时间」的东西。
func step_ai(delta: float) -> void:
	_tick_dots(delta)          # 灼烧和 AI 共用同一个「喂 delta」入口，自测能一起驱动
	if not is_alive() or player == null or not is_instance_valid(player):
		return

	var d := data()
	_cd = maxf(0.0, _cd - delta)

	# 1. 进仇恨的那一刻决定一次打谁，之后不再改 —— 免得目标每帧摇摆
	if not _aggro:
		if position.distance_to(player.position) > float(d["aggro_range"]):
			return
		_aggro = true
		_target = choose_target(randf())

	# 2. 目标没了（灵印被打死 / 收回 / 主角死了）就回头打主角
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		_target = player

	var dist := position.distance_to(_target.position)

	# 3. 灵师走另一条路：远程、站桩、施法前有预警
	if is_caster():
		_step_caster(delta, d, dist)
		return

	# 4. 蛮兽走第三条路：蓄力 → 锁定方向 → 高速冲撞
	if behavior() == "charger":
		_step_charger(delta, d, dist)
		return

	# 4. 近战：没进攻击距离就追，进了就按冷却打
	if dist > float(d["attack_range"]):
		position += (_target.position - position).normalized() * float(d["speed"]) * delta
		return

	if _cd <= 0.0:
		_cd = float(d["attack_cooldown"])
		_target.take_damage(damage_value())


## 正在酝酿这一发吗？（预警圈已经画出来了）—— 自测与 HUD 都读它。
func is_casting() -> bool:
	return _warn > 0.0


## 正在冲刺吗？（蛮兽）
func is_charging() -> bool:
	return _charge_t > 0.0


## 圈钉在哪儿（预警圈的中心）。
func cast_target() -> Vector2:
	return _cast_at


## 它是灵师吗？（会显化灵印、远程施法的那种）
func is_caster() -> bool:
	return str(data().get("behavior", "melee")) == "caster"


## 灵师的 AI：远程、站桩、施法前有预警。
## ⭐ 预警是给玩家的礼物 —— 没有它，一个 220 射程的远程怪只是「会掉血的背景」。
func _step_caster(delta: float, d: Dictionary, dist: float) -> void:
	# 正在酝酿：倒计时，到点就落地
	if _warn > 0.0:
		_warn = maxf(0.0, _warn - delta)
		if _warn <= 0.0:
			_cast_land(d)
		return

	var keep := float(d.get("keep_distance", 165.0))
	if dist > keep:
		position += (_target.position - position).normalized() * float(d["speed"]) * delta
		return
	if dist > float(d["attack_range"]) or _cd > 0.0:
		return

	# 开火：落点钉在**这一刻**目标的位置 —— 之后走开就躲掉了
	_cd = float(d["attack_cooldown"])
	_warn = float(d.get("cast_warn", 0.45))
	_cast_at = _target.position
	queue_redraw()


## 蛮兽的 AI：先蓄力（**方向性**预警），再朝那一刻的方向高速撞过去。
## ⭐ 它和灵师要玩家做的事正好相反 —— 灵师的圈要「走出去」，它的冲要「横着闪」。
func _step_charger(delta: float, d: Dictionary, dist: float) -> void:
	# 冲刺中：沿锁定的方向直冲，撞到就造成伤害并停下
	if _charge_t > 0.0:
		_charge_t = maxf(0.0, _charge_t - delta)
		position += _charge_dir * float(d["charge_speed"]) * delta
		if _target != null and is_instance_valid(_target):
			if position.distance_to(_target.position) <= float(d["attack_range"]):
				_target.take_damage(damage_value())
				_charge_t = 0.0
				_cd = float(d["attack_cooldown"])
		queue_redraw()
		return

	# 蓄力中：倒计时，到点**锁定方向**（之后你横着走开就躲掉了）
	if _warn > 0.0:
		_warn = maxf(0.0, _warn - delta)
		if _warn <= 0.0:
			_charge_dir = (_target.position - position).normalized()
			_charge_t = float(d["charge_time"])
		queue_redraw()
		return

	if dist > float(d["charge_range"]):
		position += (_target.position - position).normalized() * float(d["speed"]) * delta
		return
	if _cd <= 0.0:
		_warn = float(d.get("charge_warn", 0.55))     # 开始蓄力
		queue_redraw()
		return
	# 冷却还没好：贴上去，别站着发呆
	if dist > float(d["attack_range"]):
		position += (_target.position - position).normalized() * float(d["speed"]) * delta


## 雷落地：只打「那一刻还站在圈里」的人。
func _cast_land(d: Dictionary) -> void:
	var r := float(GameData.CAST_RADIUS)
	var dmg := damage_value()
	if player != null and is_instance_valid(player) and not player._dead:
		if player.position.distance_to(_cast_at) <= r:
			player.take_damage(dmg)
	if game != null and game.has_method("summoned_seals"):
		for s in game.summoned_seals():
			if is_instance_valid(s) and s.position.distance_to(_cast_at) <= r:
				s.take_damage(dmg)
	_warn = 0.0
	queue_redraw()


## 选目标。⭐ roll 是**注入进来的随机数**：生产环境传 randf()，自测传定值。
## 这样「30% 概率转向灵印」这条规则可以被确定性验收，不用靠多跑几次碰运气。
func choose_target(roll: float) -> Node2D:
	var seals: Array = []
	if game != null and game.has_method("summoned_seals"):
		seals = game.summoned_seals()
	if seals.is_empty():
		return player
	if roll >= float(data()["seal_seek_chance"]):
		return player

	var best: Node2D = null
	var best_d := INF
	for s in seals:
		var dd: float = position.distance_to(s.position)
		if dd < best_d:
			best_d = dd
			best = s
	return best if best != null else player


## 点火。同一枚印重复点 = 刷新时长，不叠新层；到上限只刷新最早那层。
func add_dot(dmg_per_tick: float, duration: float, src, tick: float, color := Color(0.95, 0.62, 0.35)) -> void:
	for dot in dots:
		if dot["source"] == src:
			dot["left"] = duration
			return
	if dots.size() >= int(GameData.EMBER_MAX_STACK):
		dots[0]["left"] = duration
		return
	dots.append({"dmg": dmg_per_tick, "tick": tick, "tick_left": tick, "left": duration, "source": src, "color": color})


## 某枚灵印留下的火，全部清掉。收回 / 灵印死亡时调 —— 这是唯一的清理出口。
func clear_dots_from(src) -> void:
	var keep: Array = []
	for dot in dots:
		if dot["source"] != src:
			keep.append(dot)
	dots = keep


func _tick_dots(delta: float) -> void:
	if dots.is_empty():
		return
	var keep: Array = []
	for dot in dots:
		dot["left"] = float(dot["left"]) - delta
		dot["tick_left"] = float(dot["tick_left"]) - delta
		if float(dot["tick_left"]) <= 0.0:
			dot["tick_left"] = float(dot["tick"])
			take_damage(float(dot["dmg"]), dot.get("color", Color(0.95, 0.62, 0.35)), false)
		if float(dot["left"]) > 0.0 and hp > 0.0:
			keep.append(dot)
	dots = keep


func _draw() -> void:
	var d := data()
	var r := radius_value()
	var col: Color = d["color"]
	if _flash > 0.0:
		col = col.lerp(Color(1.0, 1.0, 1.0), _flash * 0.8)

	var bob := sin(_bob) * 2.0

	# ⭐ 路线②（全线贴图）：有贴图就画贴图，没有就回退到形状语言 —— 见 ActorVisual.gd
	#    ⚠️ 影子只在回退分支里画：贴图自带影子，两边都画会叠成两层。
	#    ⚠️ 下面那些「环」是**功能层**（精英 / 会打灵印 / 灵师），不许因为换了贴图就删。
	var tex := ActorVisual.texture_of(d)
	if tex != null:
		ActorVisual.draw_unit(self, tex, d, _flash, bob)
	else:
		draw_circle(Vector2(2.0, 7.0), r, Color(0.0, 0.0, 0.0, 0.30))
		_draw_shape(r, col, bob)

	# 精英：双外环 —— 「这只不一样」必须一眼看得出，不然玩家会按普通怪的节奏去打它
	if elite:
		draw_arc(Vector2(0.0, bob), r + 5.0, 0.0, TAU, 28, Color(0.98, 0.86, 0.45, 0.90), 2.5)
		draw_arc(Vector2(0.0, bob), r + 9.5, 0.0, TAU, 28, Color(0.98, 0.86, 0.45, 0.30), 1.5)

	# 智谋型多一圈内环：一眼能看出「这个会绕后打我的灵印」
	if not is_caster() and behavior() != "charger" and float(d["seal_seek_chance"]) > 0.0:
		draw_arc(Vector2(0.0, bob), r * 0.55, 0.0, TAU, 18, Color(0.90, 0.88, 0.60), 2.0)

	# 灵师：身上绕着一枚转圈的印 —— 「它有印」这件事必须一眼看得见
	if is_caster():
		var ang := _bob * 1.1
		draw_arc(Vector2(0.0, bob), r + 9.0, 0.0, TAU, 24, Color(0.40, 0.72, 0.80, 0.55), 1.0)
		draw_circle(Vector2(cos(ang), sin(ang)) * (r + 9.0) + Vector2(0.0, bob), 4.5,
				Color(0.62, 0.92, 0.96))

	# ---- 两种预警：灵师是「圈」，蛮兽是「向」----
	if _warn > 0.0 and is_caster():
		var total := maxf(float(d.get("cast_warn", 0.45)), 0.001)
		var k := 1.0 - _warn / total
		var cr := float(GameData.CAST_RADIUS)
		var at := _cast_at - position
		draw_circle(at, cr, Color(0.95, 0.75, 0.30, 0.12 + 0.10 * k))
		draw_arc(at, cr, 0.0, TAU, 28, Color(0.98, 0.80, 0.35, 0.55), 2.0)
		draw_arc(at, cr * (1.0 - k), 0.0, TAU, 28, Color(0.98, 0.86, 0.45, 0.9), 2.0)

	if _warn > 0.0 and behavior() == "charger":
		var cw := maxf(float(d.get("charge_warn", 0.55)), 0.001)
		var ck := 1.0 - _warn / cw
		var reach := float(d.get("charge_range", 300.0))
		var dv := Vector2.RIGHT
		if _target != null and is_instance_valid(_target):
			dv = (_target.position - position).normalized()
		draw_line(Vector2.ZERO, dv * reach, Color(0.95, 0.65, 0.30, 0.18 + 0.22 * ck), 3.0)
		draw_line(Vector2.ZERO, dv * (reach * ck), Color(0.98, 0.76, 0.36, 0.85), 5.0)

	# 冲刺中：把锁定的方向画出来，让玩家看懂「它冲的就是这一条线」
	if _charge_t > 0.0:
		draw_line(Vector2.ZERO, _charge_dir * 46.0, Color(1.0, 0.82, 0.42, 0.95), 6.0)

	var bw := 44.0 * (1.3 if elite else 1.0)
	draw_rect(Rect2(-bw * 0.5, -r - 14.0, bw, 5.0), Color(0.0, 0.0, 0.0, 0.6))
	draw_rect(Rect2(-bw * 0.5, -r - 14.0, bw * clampf(hp / maxf(hp_max, 0.001), 0.0, 1.0), 5.0),
			Color(0.95, 0.72, 0.28) if elite else Color(0.90, 0.35, 0.30))


## 形状语言（M11）：每种原型一个固定形状。⭐ 怪物一多，「一眼分辨」就是功能需求。
##   melee 圆 / hunter 方 / caster 菱 / charger 三角
func _draw_shape(r: float, col: Color, bob: float) -> void:
	var c := Vector2(0.0, bob)
	var edge := Color(0.18, 0.15, 0.15)
	match behavior():
		"hunter":
			var rect := Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))
			draw_rect(rect, col)
			draw_rect(rect, edge, false, 2.0)
		"caster":
			var dp := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, 0.0),
					c + Vector2(0.0, r), c + Vector2(-r, 0.0)])
			draw_colored_polygon(dp, col)
			draw_polyline(PackedVector2Array([dp[0], dp[1], dp[2], dp[3], dp[0]]), edge, 2.0)
		"charger":
			var tp := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, r * 0.8),
					c + Vector2(-r, r * 0.8)])
			draw_colored_polygon(tp, col)
			draw_polyline(PackedVector2Array([tp[0], tp[1], tp[2], tp[0]]), edge, 2.0)
		_:
			draw_circle(c, r, col)
			draw_arc(c, r, 0.0, TAU, 24, edge, 2.0)