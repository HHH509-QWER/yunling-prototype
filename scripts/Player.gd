class_name Player
extends Node2D
## 主角。
##
## M0：WASD 移动 + 朝向跟着鼠标
## M1：鼠标左键普攻 —— 在正前方生成一个短命伤害区
##
## ⭐ 读代码的重点：
##   _move()      —— 位置是「自己算」的
##   _face_mouse()—— 朝向由鼠标决定，不是由移动方向决定（这是《蕴灵印》的特点）
##   attack_center() —— 单独抽出来，让「真的按左键」和「自测」走同一段代码

var game: Node = null          # 由 Game 接线，见 Game._build_world()
var facing := Vector2.DOWN     # 朝向（单位向量）。Vector2.DOWN == Vector2(0, 1)
var hp := 120.0
var hp_max := 120.0
var essence_max := 100.0        # ⭐ 灵力上限会被炼化满的基础属性撑大，所以它是变量不是常量

## 修为（0..境界要求）。⭐ 和灵力是两条账：灵力能花能买，修为只能修炼涨、花不掉。
var cultivation := 0.0        # ⭐ 灵力上限会被炼化满的基础属性撑大，所以它是变量不是常量

## 境界（M12）。⭐ 它是**成长轴**：灵力攒满 → 回锚点突破 → 境界 +1。
## ⚠️ 和「灵印十等」完全是两码事：十等是印的阶级（§二），境界是**灵师本人**的修为。
var realm := 1

## ⭐ 上一次突破**当场解封**的印名（命窍面板读了就清，见 SealPanel.do_breakthrough()）。
##    为什么是字段不是返回值：`breakthrough()` 已经被十几处当 bool 用，改签名要牵一片；
##    而「哪些印解封了」是一次性的表现层事件，谁先读到谁播。
var just_unsealed: Array = []

## 炼化度：印名 -> 0..100。⭐ 炼化挂在**印**上，不挂在槽位上 —— 换槽位不该丢炼化。
## ⚠️ V0.1 限制：同一枚印只有一份炼化度（同名共用）。等合炼/强夺会产出同名印了再拆成实例。
var seal_refine: Dictionary = {}

## 备用印：拿到了但没上场的。⭐ 活跃键永远是 1-4，多出来的印在这里等。
var reserve_seals: Array = []
## ⭐ 背包里的印（M29.5）：**收藏无上限**。获得一枚印永远成功 —— 命窍还有位置就进备用，
##    满了就先放这儿。命窍容量（境界给）只限制「命窍里能放几枚」（活跃 + 备用），**不限制收藏**。
##    ⚠️ 用户定案：「灵印获得先把它放到背包里面，和物品一样，没有上限」。
var bag_seals: Array = []

## 抢来的印（强夺）。⭐ 契合度归零 = **没有被动**，只能显化放招式（设计圣经 §3.5）。
## 这条规则就是「你的印是养出来的，它的印是抢来的」在数值上的样子。
var seized_seals: Array = []

## 灵印当前的等级。⭐ 数据表里的 `rank` 是**基础值**，合炼升阶会覆写它。
## 只记「改过的」—— 没记的就是数据表里那个值。
var seal_rank: Dictionary = {}

## 主角死亡（M4）。重生放哪、要不要算代价，由 Game 接线决定 —— Player 只负责「报死」。
signal died(player)

var _dead := false

var _atk_cd := 0.0             # 攻击冷却剩余秒数
var _windup_left := 0.0        # ⭐ M30.7：前摇剩余（>0 = 正在抬手，判定还没生效）
var _bob := 0.0                # 呼吸 / 灵印濒死闪烁的计时器（和走路无关）

## 走路相位 0..1。⭐ 按**走过的距离**推进，不按时间 —— 走得快腿摆得快，站住不动腿就停。
## 128 像素一个完整循环（左右各一步）：太大像慢动作，太小像抽搐。
const WALK_CYCLE_PX := 128.0
var _walk_phase := 0.0
## 浮动幅度 0..1 的缓动（站定 → 走着）。直接归零身体会「一跳」，所以缓过去。
var _walk_blend := 0.0
## 这一帧有没有真的产生位移 —— _move() 置位，_process() 读完就清。
var _walk_moved := false
## 当前播放的**一次性动作**（"" = 底层：walk / idle）。播完自动回落。
var _anim := ""
## 这个动作已经播了多久（秒）
var _anim_t := 0.0

## ⭐ M30.18：**画哪一套画的朝向** —— 和 `facing` **分开**！
##    facing = 鼠标（判定/瞄准用，一直是它）；body_dir = **走动时取移动方向、停下时取鼠标**。
##    为什么必须分开：4 向走路动画若跟鼠标，就会出现「人朝上、脚往右挪」——走起来是错的。
var body_dir := Vector2.DOWN
## ⭐ M34：**扇区是有记忆的**。以前每次画图都拿 `body_dir` 现算
##    （`ax > ay*2` 那套阈值），鼠标压在扇区边界上抖 0.1° 就会每帧换一张图，
##    看着像抽帧。现在改成「存一个扇区，偏离**当前扇区中心**够远才换」。
##    index 跟着 DIR_SUFFIX 走：0 = 正右，顺时针一圈（和 Vector2.angle() 同向）。
const DIR_SUFFIX := ["_r", "_dr", "_d", "_dl", "_l", "_ul", "_u", "_ur"]
## 死区 = 扇区宽的 62%（约 28°）。小于它不换，大于它才换 —— 边界附近才稳。
const DIR_HYST := 0.62
var _dir_sector := 2                 # 2 = 朝下（Vector2.DOWN）
## 站定转身的**平滑速率**（每秒）。`1 - exp(-k*dt)` 与帧率无关：
## 固定步长 lerp 在高/低帧率下转得一样快，看起来就不一样快。
const TURN_RATE := 14.0
## 走路帧的**固定帧率**累加器。⚠️ 以前帧索引直接由 `_walk_phase` 取整，
## 相位推进一快就会 0→2→3 跳着走（这就是「感觉不流畅」的来源之一）。
const WALK_ANIM_FPS := 9.0
var _walk_anim_t := 0.0


# ---------------- 灵印 / 命窍（M3）----------------
# ⚠️ Seal 用 preload 而不是 class_name：新增全局类名要先由编辑器扫描写进
#    .godot/global_script_class_cache.cfg，否则命令行自测会报「Identifier "Seal" not declared」。
const SealScript := preload("res://scripts/Seal.gd")

var essence := 0.0              # 灵力。灵印是烧灵力显化的
var slot_seal: Array = []       # 槽位上的灵印名；"" = 空（灵印已永久死亡）
var slot_summoned: Array = []   # 槽位上显化中的 Seal 节点；null = 未显化
var slot_damaged: Array = []    # 槽位受损剩余秒数；> 0 期间不可用
var slot_hurt: Array = []       # 该槽位的灵印挨打后的闪红剩余秒数（HUD 用它画屏幕边缘裂纹）
var slot_life: Array = []       # timed 型灵印的剩余秒数；到 0 自动收回

## 护盾池（磐石印那种一次性防御给的）。⭐ 顺序固定：被动乘数 -> 盾 -> 玄甲印转移 -> 扣血。
var shield := 0.0
var shield_max := 0.0           # 刚套上盾时的量；HUD 用它画盾条

## 受击闪白剩余量（0..1）。⭐ 敌人挨打会闪白，主角当然也该有 —— 之前只有敌人有。
var _hurt := 0.0

## 背包（M8）。⭐ 挂在主角身上 —— 它是玩家状态，不是世界状态。
var bag = (preload("res://scripts/Bag.gd")).new()


func _ready() -> void:
	refill()
	for i in range(int(GameData.SEAL_SLOTS)):
		slot_seal.append(str(GameData.SEAL_ORDER[i]) if i < GameData.SEAL_ORDER.size() else "")
		slot_summoned.append(null)
		slot_damaged.append(0.0)
		slot_hurt.append(0.0)
		slot_life.append(0.0)
	# ⭐ 开局自带的那两枚**直接炼满**：炼化是使用前提，不给满第一场架就打不了
	#    （有存档时会被 load_game 覆盖，以存档为准）
	for i in range(GameData.SEAL_ORDER.size()):
		seal_refine[str(GameData.SEAL_ORDER[i])] = float(GameData.REFINE["start_refined"])


## 补满：先按当前境界重算上限，再把气血与灵力灌满。
## ⭐ 「开局」的**统一定义** —— 新局 / 读档 / 回溯 / 突破都走这里。
##    ⚠️ 这四处原来是散着写的，读档那处就漏了；而漏的不只是补满：
##    读档会改境界，不重算上限的话，读一个化神档灵力上限还停在炼气的 100。
func refill() -> void:
	refresh_limits()
	hp = hp_max
	essence = essence_max


func _process(delta: float) -> void:
	# M20：闪避 / 冲刺的计时
	if dodge_cd > 0.0:
		dodge_cd = maxf(0.0, dodge_cd - delta)
	if dash_cd > 0.0:
		dash_cd = maxf(0.0, dash_cd - delta)
	for k in combo_cds.keys():
		combo_cds[k] = maxf(0.0, float(combo_cds[k]) - delta)
	# M26：结印窗口 —— 超时就安静收势（不扣任何东西，只是没结成）
	if seal_window_left > 0.0:
		seal_window_left = maxf(0.0, seal_window_left - delta)
		if seal_window_left <= 0.0:
			seal_input.clear()
		queue_redraw()
	if _bulwark_left > 0.0:
		_bulwark_left = maxf(0.0, _bulwark_left - delta)
		queue_redraw()
	if _haste_left > 0.0:
		_haste_left = maxf(0.0, _haste_left - delta)
		queue_redraw()
	if _invuln > 0.0:
		_invuln = maxf(0.0, _invuln - delta)
		queue_redraw()
	if _dash_left > 0.0:
		_dash_left = maxf(0.0, _dash_left - delta)
	if _hurt > 0.0:
		_hurt = maxf(0.0, _hurt - delta * 3.5)
		queue_redraw()
	if _dead:
		return                  # 死了就不动、不出招；重生由 Game 负责
	_move(delta)
	_face_mouse()
	_attack_input(delta)
	_tick_slots(delta)
	_bob += delta * 6.0
	# ⭐ 走路的两个状态量：相位由 _move() 按位移推进；blend 缓动过去，站定时身体不再空飘。
	_walk_blend = move_toward(_walk_blend, 1.0 if _walk_moved else 0.0, delta * 10.0)
	## ⭐ M30.18：**停下时跟随鼠标**（走动的方向在 _move 里存）—— 两个需求都满足：
	##    走起来像鬼谷八荒（朝移动方向），站住会转向你鼠标（瞄准/施法直观）。
	if _walk_blend <= 0.15:
		## ⭐ M34：**缓着转**，不是直接赋值 —— 直接赋值是「翻页」，缓过去才是「转身」。
		##    用角度插值而不是 Vector2.slerp：180° 对向时 slerp 会退化，lerp_angle 不会。
		var want_a := facing.angle()
		var turned := lerp_angle(body_dir.angle(), want_a, 1.0 - exp(-TURN_RATE * delta))
		body_dir = Vector2.from_angle(turned)
	## ⭐ M34：扇区只跟 `body_dir`（真正画出来的方向）走，而且带死区 —— 见 _update_dir_sector。
	_update_dir_sector(body_dir.angle())
	## ⭐ M30.18：走路帧按**固定帧率**推进（治跳帧）；停住归零，下次起步从第一帧开始。
	if _walk_blend > 0.15:
		_walk_anim_t += delta * WALK_ANIM_FPS
	else:
		_walk_anim_t = 0.0
	_walk_moved = false
	_tick_anim(delta)
	queue_redraw()


## 走过 dist 像素 → 推进走路相位。
## ⭐ 用距离不用时间：站住推不动相位，腿就不会原地摆；冲刺时腿自然摆得更快。
func _advance_walk(dist: float) -> void:
	if dist <= 0.0:
		return
	_walk_moved = true
	_walk_phase = fmod(_walk_phase + dist / WALK_CYCLE_PX, 1.0)


## 播一个动作。⭐ 后播的打断先播的 —— 手感上「玩家刚按下的那个键」永远该赢。
## ⚠️ 数据表里没有这个动作的帧时**安静忽略**：所以触发点可以先全部接上，美术之后再补。
func play_anim(n: String) -> void:
	if ActorVisual.frame_count(GameData.PLAYER, n) <= 0:
		return
	_anim = n
	_anim_t = 0.0
	queue_redraw()


## 推进动作时间；非循环动作播完就回落到 walk / idle。
func _tick_anim(delta: float) -> void:
	if _anim == "":
		return
	_anim_t += delta
	if ActorVisual.anim_loops(GameData.PLAYER, _anim):
		return
	var n := ActorVisual.frame_count(GameData.PLAYER, _anim)
	if n > 0 and _anim_t * ActorVisual.anim_fps(GameData.PLAYER, _anim) >= float(n):
		_anim = ""
		_anim_t = 0.0


## ⭐ M34：角度 → 八方向扇区，**带死区**。
##    没有这一层：鼠标压在 45° 边界上抖 0.1°，人物就每帧换一张图（看着像抽帧）。
##    有这一层：要**偏离当前扇区中心 62% 扇区宽**（约 28°）才换，边界附近是稳的。
##    ⚠️ 越过死区时**直接取最近的扇区**，不按格步进 —— 180° 甩鼠标不该分四帧转过去。
func _update_dir_sector(a: float) -> void:
	var center := float(_dir_sector) * (TAU / 8.0)
	if absf(angle_difference(a, center)) <= (TAU / 8.0) * DIR_HYST:
		return
	_dir_sector = int(roundf(fposmod(a, TAU) / (TAU / 8.0))) % 8


## ⭐ M30.18：`body_dir` → 走路动作名后缀。八方向归成三套画：
##    朝上（背面 `_u`）/ 朝下（正面 `_d`）/ 朝侧面（`_s`，左右用镜像）。
##    ⚠️ 缺哪套回退到 `walk` —— 一套图也能跑，出齐一套生效一套。
##    ⭐ M34：扇区不再现算，改用 `_dir_sector`（带死区的状态，见 _update_dir_sector）。
func _walk_anim_name(d: Dictionary) -> String:
	var anims: Dictionary = (d["visual"] as Dictionary).get("anims", {})
	var suffix: String = DIR_SUFFIX[_dir_sector]
	## ⭐ 回退链：精确 → 主方向 → 侧面 → 无后缀（缺哪套都能跑）
	var chain: Array = ["walk" + suffix]
	if suffix == "_dl": chain.append_array(["walk_d", "walk_l"])
	elif suffix == "_dr": chain.append_array(["walk_d", "walk_r"])
	elif suffix == "_ul": chain.append_array(["walk_u", "walk_l"])
	elif suffix == "_ur": chain.append_array(["walk_u", "walk_r"])
	chain.append("walk")
	for c9 in chain:
		if anims.has(c9):
			return c9
	return "walk"


## 侧面朝左时要**镜像**（一套侧面图管左右两边）。
## ⚠️ 镜像要 ActorVisual 支持 flip —— 等侧面图到位再接线，这里先把判断留好。
func face_flip() -> bool:
	return absf(body_dir.x) > absf(body_dir.y) and body_dir.x < 0.0


## 当前该画哪一帧：一次性动作优先，其次走路，最后静止图。
func _anim_texture() -> Texture2D:
	var d: Dictionary = GameData.PLAYER
	if _anim != "":
		var n := ActorVisual.frame_count(d, _anim)
		if n > 0:
			var idx := int(_anim_t * ActorVisual.anim_fps(d, _anim))
			idx = (idx % n) if ActorVisual.anim_loops(d, _anim) else mini(idx, n - 1)
			return ActorVisual.texture_frame(d, _anim, idx)
		## ⚠️ 这里原来是「一次性动作没有帧时才播走路帧」—— 那个条件几乎永不成立，
		##    所以走路帧**从来没被播过**（像素时代也是死代码，用户看到的走路一直是静止图）。
		##    ⭐ M30.17：走路是**循环位移**，不该挂在一次性动作的分支里，直接放到底部。
	## ⭐ M30.18：按 `body_dir` 取 **4 向**动作名，缺哪套回退到无后缀那套
	##    （所以出图可以一套一套来：只出正面时，四向都用正面，不会画成空白）。
	var wname := _walk_anim_name(d)
	var wcnt := ActorVisual.frame_count(d, wname)
	if wcnt > 0:
		## ⭐ M30.19：**站定也按朝向** —— 那 8 张就是"八向站姿"；走动时按固定帧率切帧。
		##    （每向只有 1 帧时 idx 恒为 0；以后补多帧序列图自动变成走路动画）
		var i9 := 0
		if _walk_blend > 0.15:
			i9 = int(_walk_anim_t) % wcnt
		return ActorVisual.texture_frame(d, wname, i9)
	return ActorVisual.texture_of(d)


## WASD / 方向键移动。
## dir.normalized() 不能省：不归一化的话，斜着走会快 1.41 倍（勾股定理）。
func _move(delta: float) -> void:
	# ⭐ 键位现在写在 InputMap 里（project.godot 的 [input] 段），代码只认动作名。
	#    想改键 / 加手柄，去 项目设置 → 输入映射 改，这一行不用动。
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	## ⭐ M30.18：记住**移动方向** —— 走路动画画哪一套由它决定（**不是鼠标**）。
	##    所以会出现「朝上走 = 背面、朝右走 = 侧面」，而不是「人朝鼠标、脚往别处挪」。
	if dir != Vector2.ZERO:
		body_dir = dir.normalized()

	# ⭐ M20b：翻滚**有位移时长**（用户反馈：瞬移看着像闪现）。
	#    翻滚期间锁住 WASD —— 出手就得有个了结，否则它能当"无敌自由移动"用。
	if _dodge_left > 0.0:
		var roll: float = minf(delta, _dodge_left)
		_dodge_left = maxf(0.0, _dodge_left - delta)
		var roll_speed := float(GameData.MOVE["dodge"]["distance"]) / maxf(float(GameData.MOVE["dodge"]["duration"]), 0.001)
		_step_by(_dodge_dir * roll_speed * roll)     # ⭐ M30.13d：翻滚也吃地形 —— 不能滚上崖、不能滚进深水
		_clamp_world()
		return

	# ⭐ M20：冲刺期间提速（倍率在 GameData.MOVE 里）
	var mult := float(GameData.MOVE["dash"]["speed_mult"]) if _dash_left > 0.0 else 1.0
	# ⭐ M30.13d：再乘**地形倍率** —— 涉水 0.6 / 高地 0.85 / 平地 1.0
	mult *= GameData.speed_mult_at(position)
	if dir != Vector2.ZERO:
		_step_by(dir.normalized() * move_speed() * mult * delta)

	_clamp_world()


## ⭐ M30.13d：**带地形阻挡的位移**。崖与深水挡住，但允许**贴着边走**（单轴滑动）——
##    不然玩家会觉得自己被"粘"在崖上，而不是被挡住。
func _step_by(step: Vector2) -> void:
	var want := position + step
	if GameData.can_step(position, want):
		position = want
	else:
		var sx := Vector2(want.x, position.y)
		if GameData.can_step(position, sx):
			position = sx
		else:
			var sy := Vector2(position.x, want.y)
			if GameData.can_step(position, sy):
				position = sy
	_advance_walk(step.length())


## 把主角钳在世界矩形内（闪避位移也要吃这一条）。
func _clamp_world() -> void:
	var ws: Vector2 = GameData.WORLD["size"]
	position = Vector2(clampf(position.x, 0.0, ws.x), clampf(position.y, 0.0, ws.y))


## 朝向 = 从自己指向鼠标。
## get_global_mouse_position() 给的是「鼠标在世界里的位置」，
## 减去自己的位置，就得到一个「从我指向鼠标」的向量。
func _face_mouse() -> void:
	var to_mouse: Vector2 = get_global_mouse_position() - position
	## ⚠️ 死区要按**屏幕像素**想：相机 zoom = 2，1 世界像素 = 2 屏幕像素。
	##    旧值 1.0 只有 2 屏幕像素 —— 鼠标贴着人时朝向会乱跳。6.0 ≈ 12 屏幕像素。
	if to_mouse.length() > 6.0:
		facing = to_mouse.normalized()


## 攻击区中心：在玩家朝向前方 reach 像素处。
func attack_center() -> Vector2:
	return position + facing * float(GameData.ATTACK["reach"])


## 按住左键就连续出招，靠 _atk_cd 控制频率。
## 按住左键就连续出招，靠 _atk_cd 控制频率。
## ⭐ M30.7（用户定案）：**真前摇** —— 抬手 0.15 秒之后判定才生效。
##    · 抬手那一瞬间就出**掌风弧光**：玩家先看见「我要打了」，再看见伤害
##    · 前摇期间不接新指令（不会连点就叠招）
##    · 死了就丢掉没打完的那一掌（见 take_damage 的死亡分支）—— 别让尸体打人
func _attack_input(delta: float) -> void:
	_atk_cd = maxf(0.0, _atk_cd - delta)
	if _windup_left > 0.0:
		_windup_left = maxf(0.0, _windup_left - delta)
		if _windup_left <= 0.0:
			_strike()
		return
	if _atk_cd > 0.0:
		return
	if not Input.is_action_pressed("attack"):
		return

	_atk_cd = float(GameData.attack_of(realm)["cooldown"]) * attack_cooldown_mult()
	_windup_left = float(GameData.ATTACK["windup"])
	play_anim("attack")               # 出手动作（帧还没画，会安静忽略）
	if game == null:
		return
	## ⭐ M33：前摇的提示从「掌风弧光」换成**手心聚气** —— 和「一道气走直线」同一套语言。
	##    位置是**手心**（身前 14px），不是攻击线中心（身前 108px）——
	##    拿 `attack_center()` 会画成"气在两百米外凭空聚起来"。
	game.spawn_swing(position + facing * float(GameData.ATTACK["qi"]["hand"]), facing)
	queue_redraw()


## 前摇到点：**判定真正生效的那一刻**（伤害按境界表算，再加炼化给的基础加成）。
func _strike() -> void:
	if game == null or _dead:
		return
	var a: Dictionary = GameData.ATTACK
	game.spawn_hit(attack_center(), facing,
			float(a["length"]), float(a["width"]),
			float(GameData.attack_of(realm)["damage"]) + attack_damage_bonus())


## ⭐ M34：**朝向锚点** —— 身体只有 4 张图，「现在在瞄哪边」靠这个自由角度的小东西说。
##    它不采样贴图（纯 draw_circle / draw_arc），所以转多少度都不会糊；
##    这是撤掉那条 16px 朝向线（M33b）之后，视觉上唯一还在做「指向鼠标」的东西。
##    位置 = `facing * 17`（绕身一圈）+ 固定的胸口抬高 —— 所以它永远落在鼠标那一侧。
func _draw_aim_anchor(bob: float) -> void:
	var hand := facing * 17.0 + Vector2(0.0, bob - 8.0)
	var a := facing.angle()
	## 抬手 / 出掌时点亮；平时只是低调的余光，不抢立绘
	var hot := _windup_left > 0.0 or _anim == "attack"
	var col := Color(0.72, 0.95, 1.0, 0.90 if hot else 0.55)
	draw_circle(hand, 4.0 if hot else 3.0, col)
	draw_arc(hand, 7.5 if hot else 6.0, a - 0.55, a + 0.55, 12,
			Color(col.r, col.g, col.b, col.a * 0.55), 1.5)


func _draw() -> void:
	var r := float(GameData.PLAYER["radius"])
	# ⭐ 走路的上下起伏跟**步频**走（一个循环两次）；站定时 _walk_blend 缓到 0，身体不再空飘。
	var bob := sin(_walk_phase * TAU * 2.0) * 2.2 * _walk_blend
	# ⭐ M30.15：**呼吸** —— 站着不动时上下浮动 1.2 像素。
	#    HD 立绘是**静态一张图**，不加这个就像纸片插在地上；加了立刻"活着"。
	#    ⚠️ 乘 (1 - _walk_blend)：走路时自动让位给走路的弹跳，两个浮动不会打架。
	#    频率用 _bob（每秒 6 的计时器）× 2.0 ≈ 1.9Hz —— 比人心跳快、比呼吸略快，看着才不呆。
	bob += sin(_bob * 2.0) * 1.2 * (1.0 - _walk_blend)

	# ⭐ M33b：**朝向线已删除**（用户要求）。
	#    以前这里 draw_line 画一条 16px 的黄色短线指向鼠标，作用是"分不清朝向"时的原型提示。
	#    现在四向走路图自己就能读出朝向，那条线反而挂角色旁边碍眼 —— 撤掉。
	#    ⚠️ `facing` 本身**保留**：出手方向、气劲判定仍然靠它，只是不再画出来。

	# ⭐ 有贴图就画贴图（影子/身体/描边/眼睛都在图里），没有就走色块 —— 见 ActorVisual.gd
	var tex := _anim_texture()
	## ⭐ M30.21：**落地影** —— HD 立绘里**没有**投影（出图时我要求去掉的，因为 AI 画的影子方向/长短不可控），
	##    所以影子必须在游戏里画：压扁的椭圆叠两层（外柔内实），只有"人在光下"这一条信息。
	##    ⚠️ 用 draw_set_transform 压扁成椭圆（y 轴 0.42），画完**必须复位**，否则后面的绘制全被压扁。
	if tex != null:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, 13.0, Color(0.0, 0.0, 0.0, 0.16))
		draw_circle(Vector2.ZERO, 9.0, Color(0.0, 0.0, 0.0, 0.14))
		draw_circle(Vector2.ZERO, 5.5, Color(0.0, 0.0, 0.0, 0.12))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if tex != null:
		ActorVisual.draw_unit(self, tex, GameData.PLAYER, 0.0, bob)
	else:
		# 影子 + 身体 + 描边
		draw_circle(Vector2(2.0, 8.0), r, Color(0.0, 0.0, 0.0, 0.30))
		# ⭐ 受击闪白：挨打那一下整个人亮一下（和敌人的 _flash 一个道理）
		var body := Color(0.86, 0.87, 0.90)
		if _hurt > 0.0:
			body = body.lerp(Color(1.0, 0.70, 0.66), _hurt * 0.85)
		draw_circle(Vector2(0.0, bob), r, body)

		# ⭐ M20：闪避的无敌帧 / 冲刺的加速 —— 玩家必须看得见自己现在处于什么状态
		if _invuln > 0.0:
			draw_arc(Vector2(0.0, bob), r + 6.0, 0.0, TAU, 24, Color(0.55, 0.90, 1.0, 0.85), 2.5)
		if _dash_left > 0.0:
			var back := -facing.normalized()
			for k in range(3):
				var off := back * (16.0 + 11.0 * float(k))
				draw_line(Vector2(0.0, bob) + off, Vector2(0.0, bob) + off * 1.7,
						Color(0.70, 0.92, 1.0, 0.32), 2.0)
		draw_arc(Vector2(0.0, bob), r, 0.0, TAU, 28, Color(0.20, 0.22, 0.28), 2.0)

		# 面朝方向的小暗点，像一只眼睛，让朝向更明显
		draw_circle(Vector2(0.0, bob) + facing * (r * 0.5), 3.0, Color(0.18, 0.20, 0.26))

	# ⭐ M34：朝向锚点 —— 贴图 / 色块两条分支**都要**。
	#    色块那边虽然已经有「眼睛」，但那只在身体圈内、贴图分支完全没有；统一画一个绕身的，
	#    换美术前后朝向的可读性才一致。
	if not _dead:
		_draw_aim_anchor(bob)

	# ---- 灵印贴附在身上的部位表现（显化中才有）----
	# ⭐ 挨打的那一枚会闪红：玩家不用盯血条，看身体哪个部位在闪就知道谁在挨打
	for i in range(slot_summoned.size()):
		var seal = slot_summoned[i]
		if seal == null or not is_instance_valid(seal):
			continue
		var sd: Dictionary = GameData.SEALS[str(slot_seal[i])]
		var scol: Color = sd["color"]
		var mount: Vector2 = GameData.BODY_PARTS[str(sd["body_part"])]
		var a := 0.55
		if seal.is_dying():
			a = 0.15 + 0.6 * (0.5 + 0.5 * sin(_bob * 2.6))      # 濒死：忽明忽暗
		if float(slot_hurt[i]) > 0.0:
			scol = Color(1.0, 0.35, 0.35)                      # 挨打：闪红
			a = 1.0
		draw_circle(mount, 9.0, Color(scol.r, scol.g, scol.b, 0.30 * a))
		draw_arc(mount, 11.0, 0.0, TAU, 18, Color(scol.r, scol.g, scol.b, a), 2.0)

	# 气血 / 灵力条已搬到 HUD（Control 层）—— 那是玩家状态，不是世界里的东西


# ==================== 灵印 / 命窍（M3）====================

## 数字键 1 / 2 / 3 的唯一含义：把第 i 个槽位「翻面」——
## 没显化就显化，显化了就收回。返回值是给自测看的，不是给 UI 用的。
func toggle_slot(i: int) -> Dictionary:
	if i < 0 or i >= slot_seal.size():
		return {"ok": false, "reason": "bad_slot"}
	if float(slot_damaged[i]) > 0.0:
		return {"ok": false, "reason": "damaged"}
	if str(slot_seal[i]) == "":
		return {"ok": false, "reason": "empty"}
	# ⭐ 唯一的门槛：未融合 / 封印的印**不能用**（显化、被动、基础属性全都不给）
	var usable: Dictionary = can_use(str(slot_seal[i]))
	if not bool(usable["ok"]):
		if slot_summoned[i] != null:
			recall_slot(i)          # 已经显化的（比如刚被封印）也要收回去
		return {"ok": false, "reason": "unusable", "detail": str(usable["reason"])}

	if slot_summoned[i] != null:
		recall_slot(i)
		return {"ok": true, "action": "recall"}

	var d: Dictionary = GameData.SEALS[str(slot_seal[i])]
	var cost := float(d["activate"])
	if essence < cost:
		return {"ok": false, "reason": "no_essence"}
	essence -= cost
	summon_slot(i, d)
	return {"ok": true, "action": "summon", "cost": cost}


func summon_slot(i: int, d: Dictionary) -> void:
	var seal = SealScript.new()
	seal.name = "Seal_%s" % slot_seal[i]
	# ⭐ 部位只认名字：将来换真身体，改 GameData.BODY_PARTS 一张表就行
	var mount: Vector2 = GameData.BODY_PARTS[str(d["body_part"])]
	# ⭐ 升阶过的印，血量和招式都按它**当前**的等级算
	seal.rank_scale = skill_scale_of(str(slot_seal[i]))
	seal.setup(str(slot_seal[i]),
			float(d["seal_hp_max"]) * seal_hp_scale_of(str(slot_seal[i])), self, mount, game)
	seal.died.connect(_on_seal_died)
	seal.hurt.connect(_on_seal_hurt)
	if game != null:
		game.add_child(seal)
	else:
		add_child(seal)
	slot_summoned[i] = seal
	play_anim("cast")                    # ⭐ 显化 = 抬手聚光推出：按下的每一枚印都有身体反应
	# ⚠️ 旧版这里「显化一次涨 1.5% 炼化度」已删 —— 炼化现在是**使用前提**，不能用就没法靠用变熟。
	slot_life[i] = float(d.get("life_time", 0.0))
	if seal.kind() == "shield":
		shield += float(d["skill"]["amount"])     # 一次性防御：套一层盾
		shield_max = shield
	# ⭐ 「按一下就是使用」：显化的同一瞬间就出招，不等第一帧
	seal.step_skill(0.0)
	queue_redraw()


func recall_slot(i: int) -> void:
	var seal = slot_summoned[i]
	slot_summoned[i] = null
	slot_hurt[i] = 0.0
	slot_life[i] = 0.0
	if seal != null and is_instance_valid(seal):
		if seal.kind() == "shield":
			shield = 0.0                                       # 盾是它的，它走了盾就没了
			shield_max = 0.0
		seal.break_skill()                                    # 还没落下来的雷 / 还没结束的火
		if game != null and game.has_method("clear_dots_from"):
			game.clear_dots_from(seal)                        # 火要一次清干净
		seal.queue_free()
	queue_redraw()


## 回溯时能保住的那枚「额外灵印」的候选：除本命印外，命窍里还有名字的印。
## ⭐ 死了的印不在里面（它已经永久死亡）—— 只有本命印能从死亡里回来。
func rewind_candidates() -> Array:
	var out: Array = []
	for i in range(slot_seal.size()):
		var n := str(slot_seal[i])
		if n != "" and n != GameData.NATAL_SEAL:
			out.append(n)
	return out


## 时印回溯：命窍重建成「本命印 + 你选的那一枚」，其余灵印全部失去。
## ⚠️ 这是 §4.3 的锁定规则。本命印无论死没死都回到槽 0。
func apply_rewind(kept: String) -> void:
	for i in range(slot_summoned.size()):
		if slot_summoned[i] != null:
			recall_slot(i)

	var keep_names: Array = [GameData.NATAL_SEAL]
	if kept != "" and kept != GameData.NATAL_SEAL:
		keep_names.append(kept)

	for i in range(slot_seal.size()):
		slot_seal[i] = str(keep_names[i]) if i < keep_names.size() else ""
		slot_damaged[i] = 0.0                  # 时间倒流：槽位受损也一起抹掉
		slot_hurt[i] = 0.0
		slot_life[i] = 0.0

	# ⭐ 回溯失去灵印：备用、抢来的、以及**挂在那些印上的炼化度**一起失去（§4.3 / §3.7）
	reserve_seals.clear()
	seized_seals.clear()
	for name_key in seal_refine.keys():
		if not has_seal(str(name_key)):
			seal_refine.erase(name_key)
	refresh_limits()
	hp = hp_max
	shield = 0.0
	shield_max = 0.0
	_dead = false
	queue_redraw()


## 主角死亡 → 显化中的灵印全部自动收回。
## ⭐ 不反噬、不永久死亡 —— 否则每死一次就赔一枚印，玩家会永远不敢显化。
func recall_all_seals() -> void:
	for i in range(slot_summoned.size()):
		if slot_summoned[i] != null:
			recall_slot(i)


## 显化中的灵印死了 → 按待决问题 1 结算代价。
## ⭐ 代价只有这一处代码，所以「灵印死了会怎样」永远只有一个答案。
func _on_seal_died(seal) -> void:
	var i: int = slot_summoned.find(seal)
	if i < 0:
		return
	slot_summoned[i] = null
	slot_seal[i] = ""                       # 永久死亡，从命窍移除
	slot_damaged[i] = float(GameData.SLOT_DAMAGED_TIME)
	slot_hurt[i] = 0.0
	slot_life[i] = 0.0
	if seal.kind() == "shield":
		shield = 0.0
		shield_max = 0.0
	hp = maxf(0.0, hp - hp_max * float(GameData.SEAL_DEATH_BACKLASH))
	if game != null and game.has_method("clear_dots_from"):
		game.clear_dots_from(seal)                            # 它留下的火随它一起灭
	if is_instance_valid(seal):
		seal.queue_free()
	queue_redraw()


## 显化中的灵印列表（已失效的自动排除）。
## 某枚显化灵印挨打了 → 点亮它所在部位（HUD 会读 slot_hurt 画屏幕边缘裂纹）。
func _on_seal_hurt(seal) -> void:
	var i: int = slot_summoned.find(seal)
	if i >= 0:
		slot_hurt[i] = 0.4


## 玄甲印的常驻护主：主角受伤时，射程内显化中的玄甲印替他扛一部分。
func _guard_seal():
	for i in range(slot_summoned.size()):
		var s = slot_summoned[i]
		if s == null or not is_instance_valid(s) or not s.is_alive():
			continue
		if s.kind() != "guard":
			continue
		if position.distance_to(s.position) <= float(GameData.SEALS[s.seal_name]["skill"]["range"]):
			return s
	return null


func summoned_seals() -> Array:
	var out: Array = []
	for s in slot_summoned:
		if s != null and is_instance_valid(s):
			out.append(s)
	return out


func summoned_count() -> int:
	return summoned_seals().size()


## ⭐ 被动加成全部是「现算」的：不维护任何「已生效加成」的缓存列表，
##    所以收回之后，下一帧的答案里自然就没有它了 —— 不需要额外的同步代码。
func attack_damage_bonus() -> float:
	return _passive_sum("attack_damage") + base_bonus_add("attack_damage")


func damage_taken_mult() -> float:
	var m := _passive_product("damage_taken")
	if _bulwark_left > 0.0:
		m *= _bulwark_taken          # 山岳：减伤 50%
	return m


func attack_cooldown_mult() -> float:
	return _passive_product("attack_cooldown") * base_bonus_mult("attack_cooldown")


# ---------------- 炼化（M9）----------------

## 按「表里的基础值 + 炼化满的永久加成」重算上限。
## ⭐ 上限是**算出来的**不是常量 —— 不然炼化一满就得重启游戏才生效。
func refresh_limits() -> void:
	var r := realm_data()
	hp_max = float(r["hp_max"]) + sub_bonus("hp") + base_bonus_add("hp_max")
	essence_max = float(r["essence_max"]) + sub_bonus("essence") + base_bonus_add("essence_max")


## 当前境界的数据。
func realm_data() -> Dictionary:
	return GameData.REALMS[clampi(realm, 1, GameData.REALMS.size())]


## 境界名（炼气 / 筑基 / …）。
func realm_name() -> String:
	return str(realm_data()["name"])


func max_realm() -> int:
	return GameData.REALMS.size()


## 命窍容量（由境界决定）= **命窍里能放几枚**（活跃 + 备用）。
## ⚠️ 它**不是**收藏上限 —— 背包里的印想放多少放多少（M29.5）。
func capacity() -> int:
	return int(realm_data()["capacity"])


## 移动速度也由境界决定。
func move_speed() -> float:
	return (float(realm_data()["speed"]) + sub_bonus("speed") + base_bonus_add("move_speed")) \
			* combo_speed_mult()


## 小境界（0 .. sub_max-1）：初 / 中 / 高 / 巅峰。
## ⭐ 它是**修为的刻度**，不是独立进度：sub = floor(修为 / (上限/sub_max))，
##    所以回溯退修为时它自动跟着退 —— 不需要存档字段，也不会和修为对不上。
func sub() -> int:
	var maxx: float = maxf(cultivation_max(), 0.001)
	var n: int = int(realm_data().get("sub_max", 1))
	return clampi(int(floor(cultivation / (maxx / float(n)))), 0, n - 1)


func sub_name() -> String:
	var names: Array = ["初", "中", "高", "巅峰"]
	return str(names[clampi(sub(), 0, names.size() - 1)])


## 小境界带来的少量加成，叠加在大境界基础值上。
func sub_bonus(stat: String) -> float:
	var g: Dictionary = realm_data().get("sub_gain", {})
	return float(g.get(stat, 0.0)) * float(sub())


## 修为上限（这一级要攒多少才能突破）。
func cultivation_max() -> float:
	return float(realm_data()["cultivation"])


## 能突破吗？⭐ 两个条件：**修为**攒满 + 没到顶。
##    ⚠️ 条件是「修为」不是「灵力」—— 灵力是燃料，花掉不心疼；修为是进度，花不掉。
##    （「必须回锚点」那一条由 Game.try_breakthrough() 把守 —— 它知道锚点在哪。）
func can_breakthrough() -> bool:
	return realm < max_realm() and cultivation >= cultivation_max() - 0.001


## 修炼：把灵力炼成修为。返回**实际换到了多少修为**（灵力不够 / 修为已满就少换或不换）。
## ⭐ 这是灵力唯一的「变强」出口 —— 打架花掉的灵力，和修炼花掉的灵力，是同一笔。
func cultivate() -> float:
	var per := float(GameData.CULTIVATE["per_press"])
	var ratio := float(GameData.CULTIVATE["gain"]) / maxf(per, 0.001)
	if per <= 0.0 or essence < 1.0:
		return 0.0
	var room := cultivation_max() - cultivation
	if room <= 0.0:
		return 0.0
	var spend := minf(essence, per)
	var gain := minf(spend * ratio, room)
	essence -= gain / ratio                 # 只按真正换到的部分扣灵力，不吃亏
	cultivation += gain
	queue_redraw()
	return gain


## 突破：修为灌进去，境界 +1，气血 / 灵力上限 / 移速 / 命窍容量一起涨。
## ⭐ 顺手记下「这一帧有哪些印解封了」—— 提前养的那枚印在这一刻兑现，
##    这是整条长线投资的兑现点，界面必须报一声（见 `just_unsealed`）。
func breakthrough() -> bool:
	if not can_breakthrough():
		return false
	var sealed_before: Array = sealed_owned()
	realm += 1
	cultivation = 0.0
	refill()                               # 突破后气血与灵力回满（新境界的上限）
	hp = hp_max
	just_unsealed = []
	for nk in sealed_before:
		if not is_sealed(str(nk)):
			just_unsealed.append(str(nk))
	queue_redraw()
	return true


## 这枚印的炼化度（0..100）。没炼过就是 0。
func refine_of(name_key: String) -> float:
	return float(seal_refine.get(name_key, 0.0))


## 炼化满了吗？满 100% 之后这枚印的 base 基础属性**永久生效**。
## 这枚印是不是被**封印**了（品阶高于当前境界能驾驭的）。
## ⭐ 封印 ≠ 未融合：前者是「你境界不够」，后者是「还没和它融合」 —— 界面必须给两种不同的理由。
func seal_rank_cap() -> int:
	return int(realm_data().get("seal_rank_max", 10))


## ⭐ 纯谓词：这个**品阶**在当前的境界下会不会被封印。
##    抽出来是为了能直接断言（GameData 是 const，测试里没法临时改一枚印的 rank）。
func is_sealed_rank(rank: int) -> bool:
	return rank > seal_rank_cap()


func is_sealed(name_key: String) -> bool:
	if name_key == "" or not GameData.SEALS.has(name_key):
		return false
	return is_sealed_rank(int(GameData.SEALS[name_key]["rank"]))


## ⭐ 纯查表：这个**品阶**要哪个境界才解得开封印（返回境界名；"" = 无封印）。
##    · rank 1 / 2 → ""（炼气就能驾驭）
##    · rank 3 → 金丹　rank 4 → 元婴　rank 5 → 化神
## ⚠️ 只查 GameData.REALMS 的 `seal_rank_max`，**不看当前境界** ⇒ 它是纯函数，能直接断言
##    （tests/seal_gate_test.gd）。这也是它和 `is_sealed()` 的分工：一个说「要几重」，
##    一个说「我现在够不够」。
func seal_gate_realm_name(rank: int) -> String:
	var keys: Array = GameData.REALMS.keys()
	keys.sort()
	for i in range(keys.size()):
		var k: int = int(keys[i])
		if rank <= int(GameData.REALMS[k].get("seal_rank_max", 10)):
			return "" if i == 0 else str(GameData.REALMS[k]["name"])
	return ""


## 这枚印的**封印门槛**："" = 没封印；否则 "金丹" / "元婴" / "化神"。
## ⭐ 它也**不看当前境界** —— 「这枚印要几重」是印自己的属性，和玩家现在几重无关。
func seal_gate_of(name_key: String) -> String:
	if name_key == "" or not GameData.SEALS.has(name_key):
		return ""
	return seal_gate_realm_name(int(GameData.SEALS[name_key]["rank"]))


## 界面上那一小段小字："" 或 "封印 · 金丹"。
## ⭐ 三处界面（拾取提示 / 背包条目 / 炼化按钮）全问这一个函数 —— 文案不会各写一套。
func seal_gate_text(name_key: String) -> String:
	var g := seal_gate_of(name_key)
	return "" if g == "" else "封印 · %s" % g


## 我手上**正被封印**的印（活跃 + 备用 + 背包，去重）。
func sealed_owned() -> Array:
	var out: Array = []
	for nk in owned_seal_names():
		if is_sealed(str(nk)) and not out.has(str(nk)):
			out.append(str(nk))
	return out


## 我手上的印名（活跃 + 备用 + 背包，去重，按这个顺序）。
func owned_seal_names() -> Array:
	var out: Array = []
	for i in range(slot_seal.size()):
		var nk := str(slot_seal[i])
		if nk != "" and not out.has(nk):
			out.append(nk)
	for n in reserve_seals:
		if not out.has(str(n)):
			out.append(str(n))
	for n in bag_seals:
		if not out.has(str(n)):
			out.append(str(n))
	return out


## ⭐ **唯一的门槛入口**：能不能用这枚印（显化 / 被动 / 基础属性都问它）。
func can_use(name_key: String) -> Dictionary:
	if name_key == "":
		return {"ok": false, "reason": "空槽位"}
	if not is_refined(name_key):
		return {"ok": false, "reason": "未融合（炼化 %.0f%%）" % refine_of(name_key)}
	# ⚠️ 门槛本身只看 `is_sealed()`（**当前境界**够不够）；`seal_gate_of()` 只负责把
	#    「要几重」写进理由 —— 「需更高境界」是一句正确的废话，玩家算不出还差多远。
	if is_sealed(name_key):
		return {"ok": false, "reason": "封印 · 需 %s 才能解封" % seal_gate_of(name_key)}
	return {"ok": true, "reason": ""}


## 花灵力炼化一次。⭐ 炼化是**使用前提** —— 它是"拿到手"变成"能用"的唯一途径。
func refine_press(name_key: String) -> Dictionary:
	if name_key == "":
		return {"ok": false, "reason": "空槽位", "gained": 0.0}
	if is_refined(name_key):
		return {"ok": false, "reason": "已经炼满了", "gained": 0.0}
	var cost := float(GameData.REFINE["press_cost"])
	if essence < cost:
		return {"ok": false, "reason": "灵力不够（要 %d）" % int(cost), "gained": 0.0}
	essence -= cost
	var got := add_refine(name_key, float(GameData.REFINE["press_gain"]))
	queue_redraw()
	return {"ok": true, "reason": "", "gained": got, "spent": cost}


func is_refined(name_key: String) -> bool:
	return name_key != "" and refine_of(name_key) >= float(GameData.REFINE["max"])


## 你已经拥有几枚印（活跃里非空的 + 备用的）。
## 命窍里有多少枚（活跃 + 备用）。⭐ 这才是**容量的口径**。
func aperture_count() -> int:
	var n := reserve_seals.size()
	for i in range(slot_seal.size()):
		if str(slot_seal[i]) != "":
			n += 1
	return n


## 我一共有多少枚印（命窍 + 背包）。⭐ 收藏无上限，所以它可以超过 capacity()。
func owned_count() -> int:
	return aperture_count() + bag_seals.size()


func has_seal(name_key: String) -> bool:
	if name_key == "":
		return false
	for i in range(slot_seal.size()):
		if str(slot_seal[i]) == name_key:
			return true
	return reserve_seals.has(name_key) or bag_seals.has(name_key)


## 命窍里还装得下吗？（M29.5 起**只管装得下几枚**，不再挡「能不能拿」）
func can_seize() -> bool:
	return aperture_count() < capacity()       # ⭐ 容量由境界决定（M12）


## 回血（云雨印那种）。⭐ 不超过上限 —— 溢出的部分直接丢掉，不攒着。返回实际回了多少。
func heal(amount: float) -> float:
	if _dead or amount <= 0.0:
		return 0.0
	var before := hp
	hp = minf(hp_max, hp + amount)
	return hp - before


## 这枚印当前的等级（数据表基础值 + 升阶覆写）。
func rank_of(name_key: String) -> int:
	if seal_rank.has(name_key):
		return int(seal_rank[name_key])
	if not GameData.SEALS.has(name_key):
		return 1
	return int(GameData.SEALS[name_key]["rank"])


## 比基础等级高了几等。
func rank_over(name_key: String) -> int:
	if not GameData.SEALS.has(name_key):
		return 0
	return maxi(0, rank_of(name_key) - int(GameData.SEALS[name_key]["rank"]))


## 升阶：等级 +1（合炼的产出之一）。返回新等级。
func rank_up(name_key: String) -> int:
	var r := rank_of(name_key) + 1
	seal_rank[name_key] = r
	queue_redraw()
	return r


## 升阶给**印的血量**的加成系数。
func seal_hp_scale_of(name_key: String) -> float:
	return 1.0 + float(GameData.RANK_GAIN["seal_hp"]) * float(rank_over(name_key))


## 升阶给**招式**的加成系数。
func skill_scale_of(name_key: String) -> float:
	return 1.0 + float(GameData.RANK_GAIN["skill"]) * float(rank_over(name_key))


## 能不能拿它当合炼材料？⭐ **本命印不行** —— 它和魂魄相连（§4.2），废了就没有「你」了。
func can_use_as_material(name_key: String) -> bool:
	return name_key != "" and name_key != GameData.NATAL_SEAL


## 得到一枚印。⭐ M29.5 起**永远成功**（收藏无上限）：
##    命窍还有位置 → 进**备用**（和以前一样）；命窍满了 → 进**背包**（不再出现「拿不下、印留在地上」）。
##    is_seized = true 表示是抢来的（炼化度归零，要重新养）。
func gain_seal(name_key: String, is_seized := false) -> bool:
	if name_key == "" or not GameData.SEALS.has(name_key):
		return false
	if has_seal(name_key):
		return false                       # 同一枚印只有一份（同时唯一性 §2.1）
	if can_seize():
		reserve_seals.append(name_key)
	else:
		bag_seals.append(name_key)         # ⭐ 命窍满了就进背包

	if is_seized and not seized_seals.has(name_key):
		seized_seals.append(name_key)
	queue_redraw()
	return true


## 消耗一枚印（合炼用）。活跃 / 备用都找，找到就抹掉。
func consume_seal(name_key: String) -> bool:
	var removed := false
	# ⚠️ 同一枚印只该有一份（同时唯一性 §2.1）。但**万一**出现重复（夹具真造出来过），
	#    这里一次全清 —— 否则「合成后材料印还留着」这种假失败会跑到别处去。
	for i in range(slot_seal.size()):
		if str(slot_seal[i]) == name_key:
			if slot_summoned[i] != null:
				recall_slot(i)
			slot_seal[i] = ""
			removed = true
	while reserve_seals.has(name_key):
		reserve_seals.erase(name_key)
		removed = true
	while bag_seals.has(name_key):
		bag_seals.erase(name_key)
		removed = true
	if removed and seized_seals.has(name_key):
		seized_seals.erase(name_key)
	if removed:
		queue_redraw()
	return removed


## ⭐ M30.3：把这枚印**丢掉**（永久失去）。返回是否真的丢掉了。
## ⚠️ **本命印不许丢** —— 和 `can_use_as_material()` 同一条理由：它和魂魄相连（§4.2）。
## ⚠️ 它在**活跃槽**里也不行：先收回再丢，否则会留下一个指向「已经不存在的印」的槽。
## 为什么复用 `consume_seal()`：它会把「备用 / 背包 / 抢来的标记」一次清干净；
## 炼化度要另外清 —— 留着的话，以后再把同一枚印弄回来，它会**带着旧的炼化度**回来。
func discard_seal(name_key: String) -> bool:
	if name_key == "" or name_key == str(GameData.NATAL_SEAL):
		return false
	if not has_seal(name_key):
		return false
	if slot_seal.has(name_key):
		return false
	if not consume_seal(name_key):
		return false
	seal_refine.erase(name_key)
	return not has_seal(name_key)


## 强夺：收进**备用**（命窍满了就进**背包** —— 收藏无上限，见 gain_seal），并打上「抢来的」标记。
func seize(name_key: String) -> bool:
	return gain_seal(name_key, true)


# ---------------- 闪避与冲刺（M20）----------------
## ⭐ 两个能力都**由已融合的灵印给**，不是天生就会：
##    · 闪避：命窍里**有一枚养熟的印**就能用（身法来自印）
##    · 冲刺：得有一枚**标注了 move="dash" 的移速印**养熟（比如流风印）
var dodge_cd := 0.0              # 闪避冷却剩余
var dash_cd := 0.0               # 冲刺冷却剩余
# ---------------- 印诀 / 结印（M22→M26，代码里仍叫 combo）----------------
## ⭐ 触发方式（M26 用户拍板的方案 A）：**按 R 起手进入结印 → 数字键填序列 → 凑齐结算**。
##    结印期间按下的印**不显化、不消耗**，只填进序列；代价只剩印诀那一笔灵力。
var combo_cds: Dictionary = {}   # 每门印诀**各自**的冷却剩余 {key: 秒}
# 结印状态（M26）
var seal_input: Array = []          # 本次结印已填入的印名（两枚制）
var seal_window_left := 0.0         # 窗口剩余（秒）；> 0 = 正在结印
var last_combo_msg := ""            # 最近一次结印的结果（测试与界面共用）
var last_combo_key := ""            # 最近放成的印诀（HUD 显示冷却用）
## ⭐ 「学会」是一份**知识**：放过一次就记住了，**回溯也带不走**（它是记忆，不是状态）。
var learned_combos: Array = []
var _bulwark_left := 0.0         # 山岳：减伤剩余
var _bulwark_taken := 1.0        # 山岳：受伤乘数
var _bulwark_speed := 1.0        # 山岳：移速乘数（会变慢）
var _haste_left := 0.0           # 疾风：加速剩余
var _haste_speed := 1.0          # 疾风：移速乘数
var _invuln := 0.0               # 无敌帧剩余（闪避给的那 0.26 秒）
var _dash_left := 0.0            # 加速剩余
var _dodge_left := 0.0           # 翻滚剩余时间（位移是"滚"出来的，不是瞬移）
var _dodge_dir := Vector2.ZERO   # 翻滚方向（按下那一刻定死，滚到一半不能拐弯）


func can_dodge() -> bool:
	return refined_seals().size() > 0


func can_dash() -> bool:
	for name_key in refined_seals():
		if is_sealed(name_key):
			continue
		if str(GameData.SEALS[name_key].get("move", "")) == "dash":
			return true
	return false


## 往哪滚：有移动输入就用输入方向，没有就朝正面。
func _move_dir() -> Vector2:
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	return dir.normalized() if dir != Vector2.ZERO else facing.normalized()


## 闪避：短暂无敌 + 滚一段。返回 {"ok", "reason"}。
func try_dodge() -> Dictionary:
	if dodge_cd > 0.0:
		return {"ok": false, "reason": "闪避冷却中" }
	if not can_dodge():
		return {"ok": false, "reason": "还没有养熟的灵印 —— 闪避是灵印给的身法"}
	var cost := float(GameData.MOVE["dodge"]["essence"])
	if essence < cost:
		return {"ok": false, "reason": "灵力不够（闪避要 %d）" % int(cost)}
	essence -= cost
	dodge_cd = float(GameData.MOVE["dodge"]["cooldown"])
	_invuln = float(GameData.MOVE["dodge"]["invuln"])
	# ⭐ 不在这里直接改 position —— 那只会在**一帧内**跳完（= 瞬移）。
	#    改成起一段翻滚，位移由 _move(delta) 逐帧推进。
	_dodge_left = float(GameData.MOVE["dodge"]["duration"])
	_dodge_dir = _move_dir()
	play_anim("dodge")
	queue_redraw()
	return {"ok": true, "reason": ""}


## 冲刺：持续加速。返回 {"ok", "reason"}。
func try_dash() -> Dictionary:
	if dash_cd > 0.0:
		return {"ok": false, "reason": "冲刺冷却中" }
	if not can_dash():
		return {"ok": false, "reason": "需要一枚养熟的移速印（比如流风印）"}
	var cost := float(GameData.MOVE["dash"]["essence"])
	if essence < cost:
		return {"ok": false, "reason": "灵力不够（冲刺要 %d）" % int(cost)}
	essence -= cost
	dash_cd = float(GameData.MOVE["dash"]["cooldown"])
	_dash_left = float(GameData.MOVE["dash"]["duration"])
	queue_redraw()
	return {"ok": true, "reason": ""}


## 按键入口：失败时把「为什么不能」说出来 —— 静默失败玩家只会以为键坏了。
## 冷却中不提示（那是玩家自己按快了，不用每次都念）。
## 场上**已显化**的印名（印诀只认显化中的两枚）。
func summoned_names() -> Array:
	var out_list: Array = []
	for i in range(slot_summoned.size()):
		if slot_summoned[i] != null:
			out_list.append(str(slot_seal[i]))
	return out_list


func combo_cd_for(key: String) -> float:
	return float(combo_cds.get(key, 0.0))


func is_combo_learned(key: String) -> bool:
	return learned_combos.has(key)


func combo_window() -> float:
	return float(GameData.COMBO_WINDOW)


func is_sealing() -> bool:
	return seal_window_left > 0.0


## 这枚印我有没有（活跃槽或备用都算）。
## ⭐ 结印用的是"你会不会这一门"，与它此刻在不在场上无关。
func owns_seal(name_key: String) -> bool:
	return slot_seal.has(name_key) or reserve_seals.has(name_key)


## `R` 的入口：起手结印；已经在结印中就是收势。返回 {ok, cancelled, reason}。
func toggle_sealing() -> Dictionary:
	if is_sealing():
		cancel_sealing()
		return {"ok": true, "cancelled": true, "reason": ""}
	# 连两枚养熟的印都没有，就别让玩家对着进度条发呆 —— 直接说清
	var usable: int = 0
	for nk in GameData.SEALS.keys():
		if owns_seal(str(nk)) and is_refined(str(nk)):
			usable += 1
	if usable < 2:
		return {"ok": false, "cancelled": false, "reason": "至少要养熟两枚印，才谈得上结印"}
	seal_input.clear()
	seal_window_left = combo_window()
	play_anim("combo")                   # ⭐ 结印 = 一连串动作，起手就进
	queue_redraw()
	return {"ok": true, "cancelled": false, "reason": ""}


func cancel_sealing() -> void:
	seal_input.clear()
	seal_window_left = 0.0
	queue_redraw()


## 结印状态下数字键的入口：把一枚印填进序列。返回 {ok, reason, fired}。
## ⭐ **不显化、不扣灵力** —— 结印不是出印，是"起势"。
func input_seal(i: int) -> Dictionary:
	if i < 0 or i >= slot_seal.size():
		return {"ok": false, "reason": "没有这一格", "fired": ""}
	var nk := str(slot_seal[i])
	if nk == "":
		return {"ok": false, "reason": "第 %d 格是空的" % (i + 1), "fired": ""}
	if not is_refined(nk):
		return {"ok": false, "reason": "「%s」还没融合，结不出印诀" % nk, "fired": ""}
	if seal_input.has(nk):
		seal_window_left = combo_window()          # 重复按同一枚：只刷新窗口，不算一步
		queue_redraw()
		return {"ok": true, "reason": "", "fired": ""}
	seal_input.append(nk)
	seal_window_left = combo_window()              # ⭐ 每按一枚都刷新窗口（这就是"加成"）
	if seal_input.size() < 2:
		queue_redraw()
		return {"ok": true, "reason": "", "fired": ""}
	var fired := _resolve_seal_input()             # 凑齐两枚 → 结算
	queue_redraw()
	return {"ok": true, "reason": "", "fired": fired}


## 两枚凑齐：成诀就放；不成诀就**如实说**。
## ⭐ 未学会的也能试 —— 这是发现感，也是将来「推演」的地基。
func _resolve_seal_input() -> String:
	if seal_input.size() < 2:
		return ""
	var key: String = GameData.combo_key(str(seal_input[0]), str(seal_input[1]))
	if not GameData.COMBOS.has(key):
		last_combo_msg = "这两枚配不出印诀（%s + %s）" % [str(seal_input[0]), str(seal_input[1])]
		cancel_sealing()
		return ""
	var r: Dictionary = try_combo_key(key)
	if not bool(r["ok"]):
		last_combo_msg = str(r["reason"])
		cancel_sealing()
		return ""
	var nm := str(GameData.COMBOS[key]["name"])
	var fresh: bool = not learned_combos.has(key)
	if fresh:
		learned_combos.append(key)                 # ⭐ 放成一次 = 学会了（知识，回溯也带不走）
	last_combo_key = key
	last_combo_msg = "印诀 · %s%s" % [nm, "（新学会）" if fresh else ""]
	cancel_sealing()
	return nm


## 按**指定的**那一门放印诀（结印走这里）。
## ⭐ 不再依赖"哪几枚印在场" —— 那是旧触发方式的遗留。
func try_combo_key(key: String) -> Dictionary:
	if not GameData.COMBOS.has(key):
		return {"ok": false, "reason": "这两枚配不出印诀", "key": key, "name": ""}
	var d: Dictionary = GameData.COMBOS[key]
	var nm := str(d["name"])
	var left := combo_cd_for(key)
	if left > 0.0:
		return {"ok": false, "reason": "%s 冷却中（%.1f 秒）" % [nm, left], "key": key, "name": nm}
	if essence < float(d["essence"]):
		return {"ok": false, "reason": "灵力不够（%s 要 %d）" % [nm, int(d["essence"])], "key": key, "name": nm}
	essence -= float(d["essence"])
	combo_cds[key] = float(d["cooldown"])
	match str(d["kind"]):
		"guard":
			_bulwark_left = float(d["duration"])
			_bulwark_taken = float(d["taken_mult"])
			_bulwark_speed = float(d["speed_mult"])
		"haste":
			_haste_left = float(d["duration"])
			_haste_speed = float(d["speed_mult"])
			heal(float(d.get("heal", 0.0)))
	if game != null and game.has_method("execute_combo"):
		game.execute_combo(key)
	queue_redraw()
	return {"ok": true, "reason": "", "key": key, "name": nm}


## 印诀带来的移速倍率（山岳变慢 / 疾风变快）。
func combo_speed_mult() -> float:
	var m := 1.0
	if _bulwark_left > 0.0:
		m *= _bulwark_speed
	if _haste_left > 0.0:
		m *= _haste_speed
	return m


## ⚠️ M26：旧的「显化即触发 + 放完收回」已经删掉 —— 换成结印状态机（见上）。


## 数字键：结印中 → 填序列；否则 → 显化/收回。
func _seal_key(i: int) -> void:
	if is_sealing():
		var r: Dictionary = input_seal(i)
		if not bool(r["ok"]) and game != null and game.hud != null:
			game.hud.notice(str(r["reason"]))
		return
	toggle_slot(i)


func _dodge_input() -> void:
	var r: Dictionary = try_dodge()
	if not bool(r["ok"]) and str(r["reason"]) != "闪避冷却中" and game != null and game.hud != null:
		game.hud.notice(str(r["reason"]))


func _dash_input() -> void:
	var r: Dictionary = try_dash()
	if not bool(r["ok"]) and str(r["reason"]) != "冲刺冷却中" and game != null and game.hud != null:
		game.hud.notice(str(r["reason"]))


## 这枚印的被动还算数吗？
## ⭐ M20（用户定案）：**所有灵印只要炼化满就享受被动** —— 不再区分"抢来的"。
##    （原来"强夺来的印没有被动"是为了平衡强夺，现在取消 —— 抢到了养熟就一样能用。）
func passive_works(_name_key: String) -> bool:
	return true


## 换印：把备用第 j 枚换上活跃第 i 格，原来那枚退回备用。
func swap_seal(i: int, j: int) -> bool:
	if i < 0 or i >= slot_seal.size() or j < 0 or j >= reserve_seals.size():
		return false
	if slot_summoned[i] != null:
		recall_slot(i)
	var incoming := str(reserve_seals[j])
	var outgoing := str(slot_seal[i])
	reserve_seals[j] = outgoing
	if outgoing == "":
		reserve_seals.remove_at(j)
	slot_seal[i] = incoming
	if is_refined(incoming):
		refresh_limits()
	queue_redraw()
	return true


## 把**背包里**的印换上活跃第 i 格（M29.5）。
## ⭐ 换下来的那枚回**背包**（不是备用）—— 这样命窍里的枚数不变，不需要额外判容量。
##    只有「第 i 格本来是空的」才算真的装进命窍，那时才看容量。
func swap_in_bag_seal(i: int, name_key: String) -> bool:
	if i < 0 or i >= slot_seal.size():
		return false
	var j: int = bag_seals.find(name_key)
	if j < 0:
		return false
	var outgoing := str(slot_seal[i])
	if outgoing == "" and not can_seize():
		return false
	if slot_summoned[i] != null:
		recall_slot(i)
	bag_seals.remove_at(j)
	slot_seal[i] = name_key
	if outgoing != "":
		bag_seals.append(outgoing)
	if is_refined(name_key):
		refresh_limits()
	queue_redraw()
	return true


## 涨炼化度。返回**实际涨了多少**（满了就不再涨，不会溢出）。
func add_refine(name_key: String, amount: float) -> float:
	if name_key == "" or amount <= 0.0:
		return 0.0
	var before := refine_of(name_key)
	var after := minf(float(GameData.REFINE["max"]), before + amount)
	seal_refine[name_key] = after
	# 刚好炼满 → 永久加成当场生效（不必重启，也不必重进场景）
	if is_refined(name_key):
		refresh_limits()
	return after - before


## 已经炼化满的印。⭐ 不看它在不在命窍里 —— 炼化是印的属性，不是槽位的。
func refined_seals() -> Array:
	var done: Array = []
	for name_key in seal_refine:
		if is_refined(str(name_key)):
			done.append(str(name_key))
	return done


## 炼化满带来的**永久加算**加成（气血上限 / 灵力上限 / 普攻伤害）。
func base_bonus_add(stat: String) -> float:
	var total := 0.0
	for name_key in refined_seals():
		if is_sealed(name_key):
			continue                    # 封印的印不给基础属性（境界退了就该失去）
		var b: Dictionary = GameData.SEALS[name_key].get("base", {})
		if str(b.get("stat", "")) == stat:
			total += float(b.get("value", 0.0))
	return total


## 炼化满带来的**永久乘算**加成（普攻冷却）。多个就相乘。
func base_bonus_mult(stat: String) -> float:
	var m := 1.0
	for name_key in refined_seals():
		if is_sealed(name_key):
			continue
		var b: Dictionary = GameData.SEALS[name_key].get("base", {})
		if str(b.get("stat", "")) == stat:
			m *= float(b.get("value", 0.0))
	return m


func _passive_sum(kind: String) -> float:
	# ⭐ 抢来的印没有被动（契合度归零）
	var total := 0.0
	for seal in summoned_seals():
		if not passive_works(str(seal.seal_name)):
			continue                       # ⭐ 抢来的印没有被动（契合度归零）
		var d: Dictionary = GameData.SEALS[seal.seal_name]
		if str(d["passive"]) == kind:
			total += float(d["passive_value"])
	return total


func _passive_product(kind: String) -> float:
	var mult := 1.0
	for seal in summoned_seals():
		if not passive_works(str(seal.seal_name)):
			continue                       # ⭐ 抢来的印没有被动（契合度归零）
		var d: Dictionary = GameData.SEALS[seal.seal_name]
		if str(d["passive"]) == kind:
			mult *= float(d["passive_value"])
	return mult


## 槽位受损倒计时。到 0 就自动恢复可用 —— 不需要任何「恢复」按钮。
func _tick_slots(delta: float) -> void:
	for i in range(slot_damaged.size()):
		if float(slot_damaged[i]) > 0.0:
			slot_damaged[i] = maxf(0.0, float(slot_damaged[i]) - delta)
		if float(slot_hurt[i]) > 0.0:
			slot_hurt[i] = maxf(0.0, float(slot_hurt[i]) - delta)

		# ---- 三种存续形态 ----
		var s = slot_summoned[i]
		if s == null or not is_instance_valid(s):
			continue
		var d: Dictionary = GameData.SEALS[str(slot_seal[i])]

		# 持续型：每秒烧灵力。⭐ 烧光就一起收 —— 这是持续型的硬上限
		var drain := float(d.get("drain", 0.0))
		if drain > 0.0:
			if essence < drain * delta:
				essence = 0.0
				recall_slot(i)
				continue
			essence -= drain * delta

		# timed 型：到点自动收回
		var life := str(d.get("life", "hold"))
		if life == "timed":
			slot_life[i] = maxf(0.0, float(slot_life[i]) - delta)
			if float(slot_life[i]) <= 0.0:
				recall_slot(i)
				continue

		# instant 型：招式一结算完就自动收回
		# ⭐ 不能提前收 —— 否则 break_skill() 会把还没落下的那一发取消掉
		if life == "instant" and s.is_skill_settled():
			recall_slot(i)


## 键盘入口。只在「按下的那一帧」翻面 —— 长按不会连续翻。
func _input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	# ⭐ is_action_pressed 的 echo 默认为 false —— 长按不会连续翻面，正好是我们要的。
	# ⭐ M26：数字键的**唯一分派点** —— 结印中填序列，否则照旧显化/收回。
	#    这样"一个键一个含义"仍然成立：含义由状态决定，而不是键本身。
	if event.is_action_pressed("seal_1"):
		_seal_key(0)
	elif event.is_action_pressed("seal_2"):
		_seal_key(1)
	elif event.is_action_pressed("seal_3"):
		_seal_key(2)
	elif event.is_action_pressed("seal_4"):
		_seal_key(3)
	elif event.is_action_pressed("combo"):
		var sr: Dictionary = toggle_sealing()
		if not bool(sr["ok"]) and game != null and game.hud != null:
			game.hud.notice(str(sr["reason"]))
	elif event.is_action_pressed("dodge"):
		_dodge_input()
	elif event.is_action_pressed("dash"):
		_dash_input()
	elif event.is_action_pressed("interact"):
		# ⭐ E 的含义只有一个（交互），**具体做什么由站的地方决定** ——
		#    锚点旁 + 灵力满 = 突破；商人旁 = 交易；采集点旁 = 采集。
		#    这三个判定全在 Game.try_interact() 里，Player 只负责「按键转发」。
		# ⚠️ 以前这里直接调 try_gather() —— 于是「E 交易」「E 突破」的提示全是空话。
		if game != null and game.has_method("try_interact"):
			game.try_interact()


# ==================== 受伤 / 死亡（M4）====================

## 主角唯一的受伤入口。敌人打的是这里，不是直接改 hp。
## ⭐ 玄甲印的减伤就在这里生效 —— 它是「受伤倍率」，不是「加血」。
func take_damage(dmg: float) -> void:
	if _dead:
		return
	if _invuln > 0.0:
		return                      # ⭐ 闪避的无敌帧：这 0.25 秒内不吃任何伤害
	play_anim("hurt")
	# ⭐ 受伤顺序固定为：被动乘数 -> 护盾 -> 玄甲印护主 -> 扣血。不要调换。
	var scaled := dmg * damage_taken_mult()

	if shield > 0.0:
		var absorbed := minf(shield, scaled)
		shield -= absorbed
		scaled -= absorbed

	# 护主走和敌人攻击完全相同的 take_damage，不新开分支 —— 灵印被打死会自然走死亡流程
	var guard = _guard_seal()
	if guard != null:
		var transfer: float = scaled * float(GameData.SEALS[guard.seal_name]["skill"]["transfer"])
		guard.take_damage(transfer)
		scaled -= transfer
	hp = maxf(0.0, hp - scaled)
	_hurt = 1.0                                  # 受击闪白（绘制时用）
	# ⭐ 自己挨打要有反应：红色跳字 + 更大的震屏 + 更长的停顿
	if game != null:
		if game.has_method("add_number"):
			game.add_number(position + Vector2(0.0, -28.0), scaled, Color(0.97, 0.46, 0.40))
		if game.has_method("add_shake"):
			game.add_shake(float(GameData.JUICE["shake_hurt"]))
		if game.has_method("hitstop"):
			game.hitstop(float(GameData.JUICE["hitstop_hurt"]))
	queue_redraw()
	if hp <= 0.0:
		_dead = true
		_windup_left = 0.0          # ⭐ M30.7：死了就丢掉没打完的那一掌
		recall_all_seals()          # 死了就别护主了
		died.emit(self)


func is_alive() -> bool:
	return not _dead


## 复活。M4 先做「原地回满血」；M5 会换成「回到锚点 + 区域快照回滚」。
func respawn(at: Vector2) -> void:
	position = at
	hp = hp_max
	shield = 0.0
	shield_max = 0.0
	_dead = false
	queue_redraw()
