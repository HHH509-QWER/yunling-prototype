extends Node2D
## 敌人：会追击、会还手；智谋型有概率改打显化中的灵印。
##
## ⚠️ 和 Seal.gd 一样不写 class_name —— 新增全局类名要先由编辑器扫描写进
##    .godot/global_script_class_cache.cfg，否则命令行自测报「Identifier not declared」。
##
## ⭐ 可测性设计：所有判断都在 step_ai(delta) 里，它是**唯一**的决策入口。
##    自测直接调它、喂一个 delta，不需要等真实帧、也不需要把游戏跑起来。
##
## ⭐⭐ M35：从「四种原型」扩到「四种杂怪 + 苍梧山五怪」。扩的方式**不是**加 if，
##    而是把「它怎么动」收进 `behavior`，把「它怕什么」收进 `weakness`：
##      · 新的行为 = 加一个 `_step_xxx()` + 形状表里的一行
##      · 新的弱点 = 在怪物的数据里写 `"weakness": {"火": 2.0}`
##    所以「加第六种怪」仍然只动数据表。

signal died(enemy)

var archetype := ""
var hp := 1.0
var hp_max := 1.0

## 挂在身上的持续伤害。每项：{dmg, tick, tick_left, left, source}
## ⭐ source 记的是「哪枚灵印点的火」—— 灵印一收回，这些火必须能一次清干净。
var dots: Array = []

var player: Node2D = null      # 主角
var game: Node = null          # 用来问「场上现在有哪些显化灵印」

## ⭐ 它身上带着的那枚印（灵师专属）。打死它才能强夺。
var carries := ""

## ⭐ 精英：不是新原型，是**同一个原型加档** —— 同一个 AI、同一个形状，更大更硬更疼、掉得更多。
var elite := false

## ⭐⭐ M35：**自成一档的精英**（碧眼灵狐 / 变异矿鬼）。
##    `true` ⇒ 不再套 `ELITE.hp_mult ×3`（设计给的 220 就是最终血量）。
var self_elite := false

## ⭐ 幻影（碧眼灵狐的分身）。幻影不计入「精英掉落」，也不掉东西。
var is_phantom := false
var phantom_of = null          # 幻影跟着哪个本体（本体一死，幻影一起散）

var _cd := 0.0
var _flash := 0.0
var _bob := 0.0
var _warn := 0.0            # 预警剩余时间（灵师：施法；蛮兽/竹鼠：蓄力）
var _cast_at := Vector2.ZERO  # 落雷圈钉在哪儿
var _charge_t := 0.0        # 冲刺剩余时间（蛮兽 / 竹鼠）
var _charge_dir := Vector2.ZERO  # 冲刺方向（蓄力结束时锁定）
var _aggro := false
var _target: Node2D = null

## ---- M35 新增的状态 ----
var _provoked := false          # 被打了（中立怪翻脸的原因之一）
var _revealed := false          # 伪装/伏击：现形了吗
var _reveal_t := 0.0            # 现形剩余时间（伏击扑完会再藏回去）
var _bleed: Array = []          # 我挂给主角的持续伤害（流血 / 剧毒）
var _clones_done := false
var _ghost_phase := 0.0         # 矿鬼的半透明相位

## ---- M35 状态系统（组合印带来的控制效果）----
## ⭐ `_status` 只存「还剩几秒」，名字就是语义：wet / blind / burn / slow。
##    为什么不做成资源/节点：「状态」目前只影响速度与弱点，一张字典足够，
##    多一层抽象只是给将来加 bug 的地方。
var _stun := 0.0
var _status: Dictionary = {}
var _no_dodge := 0.0            # 泥沼印：这段时间不能放「位移技」（冲锋）


func setup(key: String, target_player: Node2D, owner_game: Node, elite_flag := false) -> void:
	archetype = key
	elite = elite_flag
	var d: Dictionary = GameData.ENEMY[key]
	self_elite = bool(d.get("self_elite", false))
	hp_max = float(d["hp_max"])
	## ⚠️ 只有「杂怪被加档」才乘 3。自成一档的精英（灵狐 / 矿鬼）血量已经是设计值。
	if elite and not self_elite:
		hp_max *= float(GameData.ELITE["hp_mult"])
	hp = hp_max
	player = target_player
	game = owner_game
	set_meta("archetype", key)      # 开发计划 §M4：实体要有 archetype 字段
	add_to_group("enemies")
	_ghost_phase = float(position.x) * 0.01


func data() -> Dictionary:
	return GameData.ENEMY[archetype]


## 实际体型（被加档的精英会放大）。
func radius_value() -> float:
	var r := float(data()["radius"])
	if elite and not self_elite:
		return r * float(GameData.ELITE["radius_mult"])
	return r


## 实际伤害（被加档的精英更疼；幻影按 `clone_damage_ratio` 打折）。
func damage_value() -> float:
	if is_phantom:
		return float(data()["attack_damage"]) * float(data().get("clone_damage_ratio", 0.0))
	var base := float(data()["attack_damage"])
	if elite and not self_elite:
		return base * float(GameData.ELITE["damage_mult"])
	return base


func behavior() -> String:
	return str(data().get("behavior", "melee"))


func is_alive() -> bool:
	return hp > 0.0


## ⭐⭐ 弱点：按**伤害标签**算倍率（§6 里那一列「弱点」终于真的存在了）。
##    tags 是打过来的这一下带的标签（灵印的 `tags`、印诀的标签、变异词条的标签）。
##    多个标签命中就相乘 —— 但现在的怪每种只有 1~2 个弱点，相乘只是留个口子。
## ⚠️ 普攻没有标签 ⇒ 普攻永远吃不到弱点。这是有意的：
##    「弱点」应该奖励**选对了印**，而不是奖励「一直左键」。
func weakness_mult(tags: Array) -> float:
	var w: Dictionary = data().get("weakness", {})
	if w.is_empty() or tags.is_empty():
		return 1.0
	var m := 1.0
	for t in tags:
		if w.has(str(t)):
			m *= float(w[str(t)])
	## ⭐「潮湿 ×2」：设计 §2.1 惊雷印那一行「潮湿×2」。
	##    它不是某一枚印的特例 —— 而是一条**跨印的规则**：水打湿 → 雷更疼。
	##    所以它写在敌人身上（谁湿了谁吃），而不是写在惊雷印里。
	if has_status("wet"):
		for t2 in tags:
			if str(t2) == "雷":
				m *= 2.0
				break
	return m


## ---- 状态 ----（组合印的麻痹 / 致盲 / 减速 / 潮湿）
func stun_for(t: float) -> void:
	_stun = maxf(_stun, t)


func apply_status(name_key: String, t: float) -> void:
	_status[name_key] = maxf(float(_status.get(name_key, 0.0)), t)


func has_status(name_key: String) -> bool:
	return float(_status.get(name_key, 0.0)) > 0.0


func set_no_dodge(t: float) -> void:
	_no_dodge = maxf(_no_dodge, t)


func is_stunned() -> bool:
	return _stun > 0.0


## 当前移速倍率（泥沼的减速）。⭐ 只有一个出口 —— 别在五处各乘一次。
func speed_mult() -> float:
	return 0.55 if has_status("slow") else 1.0


func _spd(d: Dictionary) -> float:
	return float(d["speed"]) * speed_mult()


## 这只怕什么（给玩家看的文案，HUD / 掉落提示用）。
func weakness_text() -> String:
	var w: Dictionary = data().get("weakness", {})
	if w.is_empty():
		return ""
	var parts: Array = []
	for k in w.keys():
		parts.append("%s×%.1f" % [str(k), float(w[k])])
	return "弱 " + "、".join(parts)


## 挨打。color 决定跳字颜色；juice = false 用于持续伤害的「每跳」（只跳字，不震不卡帧）。
## ⭐⭐ M35：多了第四个参数 `tags` —— 弱点按它结算。
##    ⚠️ 不传 = 无标签 = 不吃弱点。所以老调用点（普攻、印诀）行为完全不变。
func take_damage(dmg: float, color := Color(0.95, 0.95, 0.92), juice := true, tags: Array = []) -> void:
	if hp <= 0.0:
		return
	_provoked = true             # 挨打 = 翻脸（中立怪也一样）
	var mult := weakness_mult(tags)
	var real := dmg * mult
	hp = maxf(0.0, hp - real)
	_flash = 1.0
	if game != null:
		if game.has_method("add_number"):
			## 弱点命中的跳字用**弱点色**（金）——
			## 「这一下为什么疼」必须当场看得见，否则玩家永远发现不了弱点系统。
			if mult > 1.0:
				game.add_number(position + Vector2(0.0, -26.0), real, Color(1.0, 0.86, 0.35))
			else:
				game.add_number(position + Vector2(0.0, -22.0), real, color)
		if juice:
			if game.has_method("hitstop"):
				game.hitstop(float(GameData.JUICE["hitstop_hit"]))
			if game.has_method("add_shake"):
				game.add_shake(float(GameData.JUICE["shake_hit"]))
	queue_redraw()
	if hp <= 0.0:
		_die()
		return
	## ⭐「强光破」（设计 §6）：辉光印的「光」标签专门克幻影 ——
	##    打在幻影身上直接散；打在本体身上，它放出来的幻影也一起散。
	##    这就是那张设计表里「弱点：强光破」真正落地的地方：
	##    不是「光伤害高一点」，而是**光让骗术失效**。
	if tags.has("光"):
		if is_phantom:
			hp = 0.0
			_die()
			return
		if game != null and is_instance_valid(game):
			for e2 in game.enemies.duplicate():
				if is_instance_valid(e2) and e2.is_phantom and e2.phantom_of == self:
					e2.phantom_of = null
					e2.take_damage(1e9, Color(0.85, 0.92, 1.0), false)


## 真正死掉：本体死时带上自己所有幻影。只 emit 一次。
func _die() -> void:
	if not is_phantom and game != null and is_instance_valid(game):
		# 本体死了，分身一起散（不然场上留一堆打不死的幻影）
		for e in game.enemies.duplicate():
			if is_instance_valid(e) and e.is_phantom and e.phantom_of == self:
				e.phantom_of = null
				e.take_damage(1e9, Color(0.8, 0.9, 1.0), false)
	died.emit(self)


func _process(delta: float) -> void:
	step_ai(delta)
	_bob += delta * 5.0
	_ghost_phase += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
	queue_redraw()


## AI 的一帧。自测直接调它 —— 所以这里不许有「等真实时间」的东西。
func step_ai(delta: float) -> void:
	_tick_dots(delta)          # 灼烧和 AI 共用同一个「喂 delta」入口，自测能一起驱动
	_tick_bleed(delta)
	if not is_alive() or player == null or not is_instance_valid(player):
		return

	var d := data()
	_cd = maxf(0.0, _cd - delta)
	if _reveal_t > 0.0:
		_reveal_t = maxf(0.0, _reveal_t - delta)
		if _reveal_t <= 0.0:
			_revealed = false

	# 0. 状态推进（麻痹 / 减速 / 潮湿 / 禁位移）。⭐ 麻痹优先于一切：
	#    被麻痹 = 这一帧什么都不做（这是「硬控」的定义）。
	_tick_status(delta)
	if _stun > 0.0:
		return

	# 1. 进仇恨的那一刻决定一次打谁，之后不再改 —— 免得目标每帧摇摆
	if not _aggro:
		if not _should_aggro(d):
			return
		_aggro = true
		_target = choose_target(randf())
		_on_aggro()

	# 2. 目标没了（灵印被打死 / 收回 / 主角死了）就回头打主角
	if _target == null or not is_instance_valid(_target) or not _target.is_alive():
		_target = player

	var dist := position.distance_to(_target.position)

	# 3. 每种行为走自己那条路。⚠️ 这里是一张**分派表**，不是一串特判。
	match behavior():
		"caster":
			_step_caster(delta, d, dist)
		"charger":
			_step_charger(delta, d, dist)
		"burrow":
			_step_burrow(delta, d, dist)
		"ambush":
			_step_ambush(delta, d, dist)
		"disguise":
			_step_disguise(delta, d, dist)
		"clone":
			_step_clone_ai(delta, d, dist)
		"phase":
			_step_phase(delta, d, dist)
		_:
			_step_melee(delta, d, dist)


## 补上状态倒计时。⭐ 每帧只在这里扣一次 —— 别在各行为里各扣一次。
func _tick_status(delta: float) -> void:
	if _stun > 0.0:
		_stun = maxf(0.0, _stun - delta)
	if _no_dodge > 0.0:
		_no_dodge = maxf(0.0, _no_dodge - delta)
	if _status.is_empty():
		return
	var dead_keys: Array = []
	for k in _status.keys():
		_status[k] = maxf(0.0, float(_status[k]) - delta)
		if float(_status[k]) <= 0.0:
			dead_keys.append(k)
	for k2 in dead_keys:
		_status.erase(k2)


## 该不该进仇恨？五条判据，按「行为」分流。
##   · 中立（竹鼠）：只在**窝边**翻脸（或者你先动手 —— 那是 take_damage 里的事）
##   · 伏击（竹叶青）：只在扑击距离内翻脸
##   · 伪装（竹妖）：现形距离内翻脸
##   · 其余：原来的 aggro_range
func _should_aggro(d: Dictionary) -> bool:
	if _provoked:
		return true
	var dist := position.distance_to(player.position)
	if bool(d.get("neutral", false)):
		return dist <= float(d.get("nest_range", 90.0))
	if behavior() == "ambush":
		return dist <= float(d.get("ambush_range", 105.0))
	if behavior() == "disguise":
		return dist <= float(d.get("disguise_reveal", 110.0))
	return dist <= float(d["aggro_range"])


## 刚翻脸时的一次性动作（目前只有灵狐：放分身）。
func _on_aggro() -> void:
	if behavior() == "clone" and not is_phantom and not _clones_done:
		_clones_done = true
		_spawn_clones()
	if behavior() == "disguise":
		_revealed = true


## 普通近战：没进攻击距离就追，进了就按冷却打。
func _step_melee(delta: float, d: Dictionary, dist: float) -> void:
	if dist > float(d["attack_range"]):
		position += (_target.position - position).normalized() * _spd(d) * delta
		return
	if _cd <= 0.0:
		_cd = float(d["attack_cooldown"])
		_hit(_target, damage_value())


## 主角挨了一下之后要结算的「附赠效果」：流血 / 剧毒 / 吸灵力 / 藤蔓。
## ⭐ 只有这一个入口 —— 否则「谁挂的持续伤害」会散落在五处。
func _hit(tgt: Node2D, dmg: float, mult := 1.0) -> void:
	if tgt == null or not is_instance_valid(tgt):
		return
	var d := data()
	if tgt.has_method("take_damage"):
		tgt.take_damage(dmg * mult)
	# 流血 / 剧毒：挂在自己身上结算（谁咬的就谁记着），到点自己掉
	var st: Dictionary = d.get("bleed", d.get("poison", {}))
	if not st.is_empty():
		_bleed.append({"dmg": float(st["damage"]), "tick": float(st["tick"]),
				"tick_left": float(st["tick"]), "left": float(st["time"]), "target": tgt})
	# 吸灵力（变异矿鬼）
	var drain := float(d.get("essence_drain", 0.0))
	if drain > 0.0 and tgt.has_method("drain_essence"):
		tgt.drain_essence(drain)
	# 藤蔓控制（青木竹妖）
	var root := float(d.get("root_time", 0.0))
	if root > 0.0 and tgt.has_method("root_for"):
		tgt.root_for(root)


## 流血 / 剧毒每帧推进。⭐ 目标没了就把这条丢掉。
func _tick_bleed(delta: float) -> void:
	if _bleed.is_empty():
		return
	var keep: Array = []
	for b in _bleed:
		var tg = b["target"]
		if tg == null or not is_instance_valid(tg):
			continue
		b["left"] = float(b["left"]) - delta
		b["tick_left"] = float(b["tick_left"]) - delta
		if float(b["tick_left"]) <= 0.0:
			b["tick_left"] = float(b["tick"])
			if tg.has_method("take_damage"):
				tg.take_damage(float(b["dmg"]))
		if float(b["left"]) > 0.0:
			keep.append(b)
	_bleed = keep


## 正在酝酿这一发吗？（预警圈已经画出来了）—— 自测与 HUD 都读它。
func is_casting() -> bool:
	return _warn > 0.0


## 正在冲刺吗？（蛮兽 / 竹鼠）
func is_charging() -> bool:
	return _charge_t > 0.0


## 圈钉在哪儿（预警圈的中心）。
func cast_target() -> Vector2:
	return _cast_at


## 它是灵师吗？（会显化灵印、远程施法的那种）
func is_caster() -> bool:
	return behavior() == "caster"


## 现在是不是藏着的（伏击 / 伪装）—— 绘制与自测都读它。
func is_hidden() -> bool:
	if behavior() == "ambush":
		return not _revealed and _reveal_t <= 0.0
	if behavior() == "disguise":
		return not _revealed
	return false


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
		position += (_target.position - position).normalized() * _spd(d) * delta
		return
	if dist > float(d["attack_range"]) or _cd > 0.0:
		return

	# 开火：落点钉在**这一刻**目标的位置 —— 之后走开就躲掉了
	_cd = float(d["attack_cooldown"])
	_warn = float(d.get("cast_warn", 0.45))
	_cast_at = _target.position
	queue_redraw()


## 「蓄力 → 锁定方向 → 高速撞过去」这一套，蛮兽和竹鼠**共用**。
## ⭐ 它和灵师要玩家做的事正好相反 —— 灵师的圈要「走出去」，它的冲要「横着闪」。
func _step_charger(delta: float, d: Dictionary, dist: float) -> void:
	# 冲刺中：沿锁定的方向直冲，撞到就造成伤害并停下
	if _charge_t > 0.0:
		_charge_t = maxf(0.0, _charge_t - delta)
		position += _charge_dir * float(d["charge_speed"]) * delta
		if _target != null and is_instance_valid(_target):
			if position.distance_to(_target.position) <= float(d["attack_range"]):
				_hit(_target, damage_value())
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
		position += (_target.position - position).normalized() * _spd(d) * delta
		return
	if _cd <= 0.0:
		## 泥沼印（§2.2「禁闪避」）：**禁用位移技**。
		## ⚠️ 敌人没有「闪避」这个动作，最接近的位移技就是冲锋 ——
		##    所以「禁闪避」在这里落成「禁冲锋」。这是把设计意图翻译成本工程已有的机制，
		##    不是偷懒：多造一个没人用的 dodge 系统才是真的偷懒。
		if _no_dodge > 0.0:
			if dist > float(d["attack_range"]):
				position += (_target.position - position).normalized() * _spd(d) * delta
			return
		_warn = float(d.get("charge_warn", 0.55))     # 开始蓄力
		queue_redraw()
		return
	# 冷却还没好：贴上去，别站着发呆
	if dist > float(d["attack_range"]):
		position += (_target.position - position).normalized() * _spd(d) * delta


## 铁齿竹鼠：**中立**。你不进它的窝，它连头都不抬；进了窝，它冲锋 + 流血。
## ⭐ 为什么需要「中立怪」：新手村如果每一只都主动扑上来，玩家就没有一处能停下来看地图。
##    中立 = 玩家学会「什么时候不该打」的最便宜教具。
func _step_burrow(delta: float, d: Dictionary, dist: float) -> void:
	_step_charger(delta, d, dist)


## 鬼影竹叶青：**伏击**。藏在草里（半透明、不动），你走进 `ambush_range` 就扑出来咬一口
## （伤害 × ambush_mult + 剧毒），然后退回草里等冷却。
## ⭐ 它是「反应题」不是「木桩」：咬完就藏，所以它每秒的威胁其实很低 ——
##    疼的是**第一口**。玩家的解法是「先看见它」。
func _step_ambush(delta: float, d: Dictionary, dist: float) -> void:
	var reach := float(d.get("ambush_range", 105.0))
	if not _revealed:
		# 藏着：不动。进范围了才扑。
		if dist <= reach and _cd <= 0.0:
			_revealed = true
			_reveal_t = 0.9
			_cd = float(d["attack_cooldown"])
			if dist <= float(d["attack_range"]) + 26.0:
				_hit(_target, damage_value(), float(d.get("ambush_mult", 1.5)))
			else:
				# 还差一步：这次先蹿过去，不造成伤害（给玩家一次「它动了」的提醒）
				position += (_target.position - position).normalized() * 40.0
			queue_redraw()
		return
	# 现形中：追一小会儿
	if dist > float(d["attack_range"]):
		position += (_target.position - position).normalized() * _spd(d) * delta
		return
	if _cd <= 0.0:
		_cd = float(d["attack_cooldown"])
		_hit(_target, damage_value())


## 青木竹妖：**伪装**。站着不动时就是一根枯竹（不 bob、不显示血条、像背景）；
## 玩家进 `disguise_reveal` 就现形，然后走上来用藤蔓把主角钉住。
func _step_disguise(delta: float, d: Dictionary, dist: float) -> void:
	if not _revealed:
		_revealed = true          # 进仇恨即现形（_should_aggro 已经判过距离了）
		queue_redraw()
	if dist > float(d["attack_range"]):
		position += (_target.position - position).normalized() * _spd(d) * delta
		return
	if _cd <= 0.0:
		_cd = float(d["attack_cooldown"])
		_hit(_target, damage_value())


## 碧眼灵狐：**分身**。本体第一次翻脸时放出 `clone_count` 个幻影（1% 血、0 伤害）。
## ⭐ 幻影的作用不是「多打你几下」，而是**骗走你的锁定与普攻** ——
##    所以它必须长得和本体一模一样（同一张画、同一个形状），只能靠「打上去没掉血」来识破。
##    ⭐ 而辉光印（tag 光）是**官方答案**：强光一照，幻影直接散。
func _step_clone_ai(delta: float, d: Dictionary, dist: float) -> void:
	# 幻影只会绕着你晃，不打人（clone_damage_ratio = 0）
	if is_phantom:
		var ang := _bob * 0.7 + float(get_instance_id() % 7)
		var want := player.position + Vector2(cos(ang), sin(ang)) * 70.0
		position = position.lerp(want, clampf(delta * 1.4, 0.0, 1.0))
		return
	_step_melee(delta, d, dist)


## 变异矿鬼：**穿墙 + 吸灵力 + 半透明**。
## 穿墙在这套工程里是「本来就没有墙」—— 敌人的移动不走 `can_step`，所以它天然能穿。
## 所以这条行为的「实现」其实只有两件事：命中吸灵力（`_hit` 里）与半透明（_draw 里）。
func _step_phase(delta: float, d: Dictionary, dist: float) -> void:
	_step_melee(delta, d, dist)


## 放分身。⚠️ 幻影**不复制**本体当前的 `_aggro` —— 它出生就跟着本体一起翻脸。
func _spawn_clones() -> void:
	var n := int(data().get("clone_count", 0))
	if n <= 0 or game == null or not is_instance_valid(game):
		return
	for i in range(n):
		var c = get_script().new()
		c.setup(archetype, player, game, elite)
		c.is_phantom = true
		c.phantom_of = self
		c.hp_max = maxf(1.0, hp_max * float(data().get("clone_hp_ratio", 0.01)))
		c.hp = c.hp_max
		c.carries = ""
		c.name = "%s_phantom%d" % [name, i + 1]
		c.position = player.position + Vector2(0.0, 1.0).rotated(TAU * float(i) / float(n)) * 64.0
		c.died.connect(game._on_enemy_died)
		game.add_child(c)
		game.enemies.append(c)


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


## 弱点标记的**元素色**：印色是「这枚印长什么样」，元素色是「这个属性是什么」，
## 两者不该混用 —— 否则雷印和火印的弱点标记会撞色。
const ELEM_COLORS := {
	"火": Color(1.00, 0.42, 0.20),
	"雷": Color(0.72, 0.58, 1.00),
	"光": Color(1.00, 0.92, 0.55),
	"水": Color(0.40, 0.72, 0.95),
	"冰": Color(0.62, 0.90, 1.00),
	"土": Color(0.72, 0.58, 0.36),
	"岩": Color(0.70, 0.70, 0.62),
	"风": Color(0.62, 0.90, 0.72),
	"穿": Color(0.85, 0.85, 0.88),
	"木": Color(0.45, 0.78, 0.38),
	"幻": Color(0.85, 0.62, 0.95),
}


func _draw() -> void:
	var d := data()
	var r := radius_value()
	var col: Color = d["color"]

	# ⭐ 伪装中：画成一根枯竹，**不 bob、不画血条** —— 让它真的像背景。
	#    这不是作弊，是它唯一的身份：玩家该被骗一次，不该被骗十次
	#    （现形条件是「进 110px」，也就是你已经在它脸上了）。
	if is_hidden():
		_draw_disguise(r, col)
		return

	if _flash > 0.0:
		col = col.lerp(Color(1.0, 1.0, 1.0), _flash * 0.8)

	# 矿鬼：半透明呼吸（灵体感）。⭐ 它和「伪装」不同 —— 你一直看得见它，只是看不清。
	if behavior() == "phase":
		col.a = 0.55 + 0.35 * (0.5 + 0.5 * sin(_ghost_phase * 2.6))
	# 幻影：比本体淡，但**不是**淡到看不出来（那样就不叫骗了）
	if is_phantom:
		col.a = 0.55

	var bob := sin(_bob) * 2.0

	# ⭐ 路线②（全线贴图）：有贴图就画贴图，没有就回退到形状语言 —— 见 ActorVisual.gd
	#    ⚠️ 影子只在回退分支里画：贴图自带影子，两边都画会叠成两层。
	#    ⚠️ 下面那些「环」是**功能层**（精英 / 会打灵印 / 灵师），不许因为换了贴图就删。
	var tex := ActorVisual.texture_of(d)
	if tex != null:
		ActorVisual.draw_unit(self, tex, d, _flash, bob, col.a)
	else:
		draw_circle(Vector2(2.0, 7.0), r, Color(0.0, 0.0, 0.0, 0.30 * col.a))
		_draw_shape(r, col, bob)

	# 精英：双外环 —— 「这只不一样」必须一眼看得出，不然玩家会按普通怪的节奏去打它
	if elite and not is_phantom:
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

	# ⭐ 弱点标记：怕火就画一颗火色小灯 —— 弱点必须**在血条旁边**就看得见，
	#    否则「换印克制」这条设计会永远埋在文档里。
	_draw_weakness_marks(r, bob)

	# 麻痹：头顶三颗转圈的星
	if _stun > 0.0:
		for k in range(3):
			var a2 := _bob * 3.0 + TAU * float(k) / 3.0
			draw_circle(Vector2(cos(a2), sin(a2) * 0.35) * 9.0 + Vector2(0.0, -r - 8.0 + bob), 2.2,
					Color(0.95, 0.92, 0.55))

	# ---- 两种预警：灵师是「圈」，冲锋型是「向」----
	if _warn > 0.0 and is_caster():
		var total := maxf(float(d.get("cast_warn", 0.45)), 0.001)
		var k := 1.0 - _warn / total
		var cr := float(GameData.CAST_RADIUS)
		var at := _cast_at - position
		draw_circle(at, cr, Color(0.95, 0.75, 0.30, 0.12 + 0.10 * k))
		draw_arc(at, cr, 0.0, TAU, 28, Color(0.98, 0.80, 0.35, 0.55), 2.0)
		draw_arc(at, cr * (1.0 - k), 0.0, TAU, 28, Color(0.98, 0.86, 0.45, 0.9), 2.0)

	if _warn > 0.0 and (behavior() == "charger" or behavior() == "burrow"):
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


func _draw_weakness_marks(r: float, bob: float) -> void:
	var w: Dictionary = data().get("weakness", {})
	if w.is_empty():
		return
	var i := 0
	for tag in w.keys():
		var c: Color = ELEM_COLORS.get(str(tag), Color(0.85, 0.85, 0.85))
		var at := Vector2(-r - 8.0 - float(i) * 9.0, -r - 11.5 + bob)
		draw_circle(at, 3.2, Color(c.r, c.g, c.b, 0.95))
		draw_arc(at, 3.2, 0.0, TAU, 10, Color(0.10, 0.10, 0.12, 0.9), 1.0)
		i += 1


## 伪装形态：一根枯竹 + 两片枯叶。⭐ 它必须看起来「和地图上的竹子装饰是同一类东西」，
## 否则伪装没有意义。所以这里画的就是 `Props` 里 bamboo 那套配色。
func _draw_disguise(_r: float, _col: Color) -> void:
	var stalk := Color(0.52, 0.48, 0.30)
	var dark := Color(0.30, 0.28, 0.18)
	draw_circle(Vector2(2.0, 6.0), 7.0, Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(Rect2(-3.0, -26.0, 6.0, 34.0), stalk)
	for k in range(3):
		draw_rect(Rect2(-3.0, -22.0 + float(k) * 11.0, 6.0, 2.0), dark)
	draw_colored_polygon(PackedVector2Array([Vector2(3.0, -20.0), Vector2(15.0, -24.0),
			Vector2(13.0, -16.0)]), dark)
	draw_colored_polygon(PackedVector2Array([Vector2(-3.0, -12.0), Vector2(-14.0, -16.0),
			Vector2(-12.0, -8.0)]), dark)
	# 藏着的竹叶青：一丛草里两粒竖瞳（只在极近距离才看得见 —— 这是「看见它」的奖励）
	if behavior() == "ambush":
		draw_colored_polygon(PackedVector2Array([Vector2(-12.0, -4.0), Vector2(12.0, -4.0),
				Vector2(9.0, 4.0), Vector2(-9.0, 4.0)]), Color(0.28, 0.44, 0.26))
		draw_circle(Vector2(-3.5, -1.0), 1.6, Color(0.95, 0.85, 0.35, 0.85))
		draw_circle(Vector2(3.5, -1.0), 1.6, Color(0.95, 0.85, 0.35, 0.85))


## 形状语言：每种原型一个固定形状。⭐ 怪物一多，「一眼分辨」就是功能需求。
##   melee 圆 / hunter 方 / caster 菱 / charger 三角
##   burrow 六边 / ambush 蛇形 / disguise 竹 / clone 狐 / phase 鬼
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
		"burrow":
			# 六边形：啮齿类的圆钝轮廓，和 melee 的圆区分开
			var hp := PackedVector2Array()
			for k in range(6):
				var a: float = TAU * float(k) / 6.0 + PI / 6.0
				hp.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(hp, col)
			draw_polyline(PackedVector2Array([hp[0], hp[1], hp[2], hp[3], hp[4], hp[5], hp[0]]), edge, 2.0)
			# 两颗门牙：竹鼠的招牌
			draw_rect(Rect2(c + Vector2(-4.0, r * 0.25), Vector2(3.0, 6.0)), Color(0.98, 0.96, 0.86))
			draw_rect(Rect2(c + Vector2(1.0, r * 0.25), Vector2(3.0, 6.0)), Color(0.98, 0.96, 0.86))
		"ambush":
			# 蛇形：一条细长的 S
			var sp := PackedVector2Array()
			for k in range(9):
				var t := float(k) / 8.0
				sp.append(c + Vector2(lerpf(-r * 1.4, r * 1.4, t), sin(t * TAU) * r * 0.55))
			draw_polyline(sp, col, maxf(4.0, r * 0.45))
			draw_polyline(sp, edge, 1.5)
			draw_circle(sp[sp.size() - 1], r * 0.32, col)
		"disguise":
			var br := Rect2(c + Vector2(-r * 0.30, -r * 1.5), Vector2(r * 0.60, r * 2.0))
			draw_rect(br, col)
			draw_rect(br, edge, false, 2.0)
			for k in range(4):
				draw_rect(Rect2(c + Vector2(-r * 0.30, -r * 1.2 + float(k) * r * 0.5),
						Vector2(r * 0.60, 2.0)), edge)
		"clone":
			# 狐：尖三角 + 两只耳朵
			var fp := PackedVector2Array([c + Vector2(0.0, -r), c + Vector2(r, r * 0.75),
					c + Vector2(0.0, r * 0.35), c + Vector2(-r, r * 0.75)])
			draw_colored_polygon(fp, col)
			draw_polyline(PackedVector2Array([fp[0], fp[1], fp[2], fp[3], fp[0]]), edge, 2.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.75, -r * 0.15),
					c + Vector2(-r * 0.95, -r * 0.95), c + Vector2(-r * 0.30, -r * 0.45)]), col)
			draw_colored_polygon(PackedVector2Array([c + Vector2(r * 0.75, -r * 0.15),
					c + Vector2(r * 0.95, -r * 0.95), c + Vector2(r * 0.30, -r * 0.45)]), col)
		"phase":
			# 鬼：上圆下摆，底下是波浪边
			draw_circle(c + Vector2(0.0, -r * 0.25), r * 0.85, col)
			var gp := PackedVector2Array()
			gp.append(c + Vector2(-r * 0.85, -r * 0.25))
			for k in range(5):
				var t2 := float(k) / 4.0
				gp.append(c + Vector2(lerpf(-r * 0.85, r * 0.85, t2), r * 0.9 + sin(t2 * TAU) * r * 0.18))
			gp.append(c + Vector2(r * 0.85, -r * 0.25))
			draw_colored_polygon(gp, col)
			draw_circle(c + Vector2(-r * 0.30, -r * 0.40), r * 0.16, Color(0.10, 0.12, 0.16))
			draw_circle(c + Vector2(r * 0.30, -r * 0.40), r * 0.16, Color(0.10, 0.12, 0.16))
		_:
			draw_circle(c, r, col)
			draw_arc(c, r, 0.0, TAU, 24, edge, 2.0)
