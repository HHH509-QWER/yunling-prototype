class_name GameData
extends RefCounted
## 全局数据表与工具函数。
##
## ⭐ 这个文件是整个工程最重要的设计思想：把「有什么」和「能做什么」分开。
## 想加一种敌人、想调一个数值，只动这里，逻辑代码一行都不用改。
## （这就是《学习路线》板块 2 讲的「数据驱动」——回到 gu 工程也要学它。）
##
## 注意：Godot 默认字体不含中文字形，这里用 SystemFont 直接向系统要一份，
## 见 make_font()。这个办法是从 gu 工程抄来的，已经验证过能正常显示中文。

# ---------------- 玩家 ----------------
const PLAYER := {
	"speed": 116.0,          # 移动速度（像素/秒）
	"radius": 13.0,          # 身体半径，只用于画图
	"hp_max": 120.0,
	"essence_max": 100.0,
	## ⭐ 外观（像素美术）：文件不在就自动回退成色块，见 ActorVisual.gd
	"visual": {
		## ⭐⭐ M33：主角改用**原生像素画的四方向立绘**（前 / 后 / 左 + 左镜像成右）。
		##    素材由 `art/tools/build_player_4dir.gd` 从三张单方向图生成：
		##    抠白底 → 只留最大连通块（去掉水印那种孤立像素）→ 三者用**同一个缩放系数**
		##    → 脚底压到同一行。少任何一步，走路时就会"一大一小"或"上下跳"。
		##    ⚠️ 画布仍是 192×192、scale 仍 0.25 ⇒ **世界高 48、玩法与自测都不动**；
		##       差别是人物只占 48px、被最近邻放大 4 倍塞进画布 —— 显示出来是硬边像素，
		##       而不是"1900px 压到 192"那种糊。
		"texture": "res://art/units_hd/p4_d.png",
		"scale": 0.25,
		"anims": {
			## ⚠️ M33（用户定案）：**游戏改成四方向**。
			##    八个 `walk_*` 键全部保留 —— `Player._walk_anim_name()` 仍按 8 向选名字，
			##    缺键会回退到无后缀的 `walk`；所以**斜向必须显式指向左右**，否则斜着走会
			##    退回旧 HD 图，风格瞬间跳走。这是四方向游戏的通行做法。
			"walk": {"frames": ["res://art/units_hd/p4_d.png"], "fps": 10.0, "loop": true},
			"walk_d": {"frames": [
				"res://art/units_hd/p4_d_walk_1.png",
				"res://art/units_hd/p4_d_walk_2.png",
				"res://art/units_hd/p4_d_walk_3.png",
				"res://art/units_hd/p4_d_walk_4.png",
			], "fps": 9.0, "loop": true},
			"walk_u": {"frames": ["res://art/units_hd/p4_u.png"], "fps": 10.0, "loop": true},
			"walk_l": {"frames": ["res://art/units_hd/p4_l.png"], "fps": 10.0, "loop": true},
			"walk_r": {"frames": ["res://art/units_hd/p4_r.png"], "fps": 10.0, "loop": true},
			"walk_dl": {"frames": ["res://art/units_hd/p4_l.png"], "fps": 10.0, "loop": true},
			"walk_ul": {"frames": ["res://art/units_hd/p4_l.png"], "fps": 10.0, "loop": true},
			"walk_dr": {"frames": ["res://art/units_hd/p4_r.png"], "fps": 10.0, "loop": true},
			"walk_ur": {"frames": ["res://art/units_hd/p4_r.png"], "fps": 10.0, "loop": true},
			## 施法 / 结印暂时也用正面图：旧 HD 图会瞬间跳回另一种画风，比"没动作"更刺眼。
			"cast": {"frames": ["res://art/units_hd/p4_d.png"], "fps": 10.0, "loop": false},
			"combo": {"frames": ["res://art/units_hd/p4_d.png"], "fps": 11.0, "loop": false},
			"attack": {"frames": ["res://art/units_hd/p4_d.png"], "fps": 16.0, "loop": false},
		},
		## ⭐ M30.14：192 高 × scale 0.25 = 48 世界单位（和旧像素贴图一样大）。
		## 自测会**真的去读 PNG 找脚底行**，反算脚有没有踩在碰撞圆心上 —— 换图换错它会红。
		## ⚠️ M33：四方向这张素材的脚底在**最后一行 191**（旧 HD 图有 9px 下边距、在 183），
		##    所以 offset.y = -((191+1) - 192/2) × 0.25 = **-24**（旧图是 -22）。
		"offset": Vector2(0.0, -24.0),
	},
}

# ---------------- 普攻 ----------------
# M1 的做法：每次出手，在玩家正前方生成一个「短命伤害区」。
# 它只活 life 秒，寿命到了就消失 —— 不是持续伤害。
const ATTACK := {
	## ⭐⭐ M33（用户定案）：「普攻是一道气打出去，**一条直线**」，不要那个方框。
	##    ⇒ 参数从「一小块方区」改成**长而窄的一条线**：起点在身前 20、终点在身前 196，
	##      宽 22（比一个人还窄）。窄是关键 —— 宽了就又变回"一片区域"。
	##    ⚠️ 三者是**联动**的：判定用的是「以 center 为准、沿朝向 ±length/2」的矩形，
	##      所以 `reach` 必须 = (起点 + 终点) / 2 = 108。改一个就要跟着改另外两个。
	"reach": 110.0,          # 攻击线中心离玩家多远（= (起点 20 + 终点 200) / 2）
	"length": 200.0,         # 攻击线长度（沿朝向）
	"width": 24.0,           # 攻击线宽度（垂直朝向）
	"life": 0.20,            # 气飞完全程用多久（秒）—— ⭐ 0.16 → 0.20：慢下来才看得清"一道气"
	"windup": 0.15,          # ⭐ M30.7 **前摇**（用户定案）：抬手 0.15 秒后才判定
	"knockback": 7.0,        # ⭐ 命中时把敌人推开多少像素（轻微击退）
	## 普攻的**表现**参数（纯表现，不参与任何判定）
	"qi": {
		"life": 0.15,        # 手心蓄气光点活多久（对齐 windup）
		"hand": 14.0,        # 光点离身体多远（**手心**位置，不是攻击线中心）
		"tail": 96.0,        # 气尾**最长**多少（实际随行程拉长，这里是上限；短了像飞镖，长了像浪）
		## ⭐ M33（用户定案「玉青」）：颜色只有这一处真相 —— 气浪、蓄光、命中冲击都用它。
		##    玉青 = 偏绿的青（G > B > R），和灵印的冷蓝、地面的黄绿都能分开。
		"color": Color(0.34, 0.87, 0.73),
	},
}

## ⭐ M30.7：普攻**随境界成长**（用户定案的数值：一阶 8 → 五阶 14，间隔 0.55 → 0.40 秒）。
##    为什么单独一张表、不并进 `REALMS`：普攻是「保底手段」，它的成长曲线要能
##    **单独看见、单独调**；并进境界表就会跟着别的数值一起动。
const ATTACK_REALM := {
	1: {"damage": 8.0, "cooldown": 0.55},
	2: {"damage": 9.0, "cooldown": 0.50},
	3: {"damage": 11.0, "cooldown": 0.46},
	4: {"damage": 12.0, "cooldown": 0.43},
	5: {"damage": 14.0, "cooldown": 0.40},
}


## 按境界取普攻数值。越界一律夹到表内 —— 境界只有 1..5，但读表的地方不该自己判边界。
static func attack_of(realm: int) -> Dictionary:
	var ks: Array = ATTACK_REALM.keys()
	ks.sort()
	return ATTACK_REALM[clampi(realm, int(ks[0]), int(ks[ks.size() - 1]))]

# ---------------- 假人 ----------------
const DUMMY := {
	"hp_max": 60.0,
	"radius": 16.0,
	"color": Color(0.55, 0.58, 0.62),
	"visual": {"texture": "res://art/units/dummy.png", "offset": Vector2(0.0, -14.0)},
	## 假人是 M1 的验收基线，摆在锚点旁边（走两步就能打）
	"spawns": [Vector2(1512.0, 1322.7), Vector2(2072.0, 1749.3)],
}


# ---------------- 灵印（M3）----------------
# ⭐ 「不砍玩法，砍数量」（开发计划 §六）：V0.1 只做 3 枚印、3 个命窍槽。
#    加一枚印 = 往这张表里加一条，逻辑代码一行都不用改。

## 命窍槽位数。⭐ 数字键 1 / 2 / 3 / 4 一一对应 ——
## 设计圣经 §五 的键位表写的就是 1 2 3 4，这里是把 V0.1 砍到 3 枚那一刀补回来。
const SEAL_SLOTS := 4

## 命窍**容量** = 你最多能拥有几枚灵印（活跃 4 + 备用）。
## ⭐ 活跃键永远是 1-4（键位表锁定），多带的印放**备用**，在 Tab 面板里换上场。
## ⭐ 强夺要求「容量没满」—— 所以抢来的印是有限资源，不是随便捡。
const SEAL_CAPACITY := 6

## 境界（M12）。⭐ 成长轴：灵力攒满 → 回锚点突破 → 境界 +1 → 上限与命窍容量一起涨。
## ⚠️ 境界名（炼气/筑基/金丹/元婴/化神）是本里程碑新加的 —— 设计圣经只定义了「灵印十等」，
##    没有定义灵师自己的境界名。这五个名字是通行叫法，改起来只动这张表。
## ⚠️ `seal_rank_max` = 这个境界能驾驭的印的**最高品阶**；高于它的印会被**封印**
##    （不可显化、不给被动、不给基础属性），境界够了自动解封。
##    文档 §11.1 写的是「一阶只能凡印」，但那样炼气期连二等精印（惊雷印）都用不了 ——
##    而目前游戏里最强的印才二等，等于整段炼气期只剩灰烬印能打。所以炼气给到 2。
const REALMS := {
	1: {"name": "炼气", "essence_max": 100.0, "hp_max": 120.0, "speed": 116.0, "cultivation": 100.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 2, "capacity": 6},
	2: {"name": "筑基", "essence_max": 160.0, "hp_max": 150.0, "speed": 120.0, "cultivation": 160.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 2, "capacity": 7},
	3: {"name": "金丹", "essence_max": 220.0, "hp_max": 180.0, "speed": 124.0, "cultivation": 220.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 3, "capacity": 8},
	4: {"name": "元婴", "essence_max": 300.0, "hp_max": 220.0, "speed": 129.0, "cultivation": 300.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 4, "capacity": 9},
	5: {"name": "化神", "essence_max": 400.0, "hp_max": 270.0, "speed": 135.0, "cultivation": 400.0, "sub_max": 4, "sub_gain": {"hp": 6.0, "essence": 5.0, "speed": 1.0}, "seal_rank_max": 10, "capacity": 10},
}

# ---------------- 修炼（灵力 -> 修为）----------------
## ⭐ 灵力是**燃料**：能花（显化灵印）、能买（灵石换）、能炼成修为。
##    修为是**进度**：只能涨，满了才能突破 —— 花不掉，也买不到。
##    这样「灵石买材料」和「灵石买灵力」才是真的在抢同一笔钱。
const CULTIVATE := {
	"per_press": 20.0,          # 按一次修炼花多少灵力
	"gain": 20.0,               # 换到多少修为（1:1，先简单）
	"essence_service": 25.0,    # 商人卖的「一份灵力」有多少
	"essence_price": 10,        # 一份灵力卖多少灵石
}

## ⚠️ M28（用户定案）：**回溯功能暂时移除** —— 原来这里有一张 DEPTH 表
##    （时间线帧数 / 拍帧间隔 / 收获评分权重 / 连死保底），随功能一起删掉。
##    死亡现在是最朴素的「回到上次存档」；要接回盲跳回溯时，把这张表一起恢复
##    （原值与设计记录见 设计圣经 §4.4 / 开发计划 M17）。
## ⚠️ M19：**锚点机制已移除**（用户定案）—— 这张表只剩"存档文件放哪、多久自动存一次"。
##    原来的三件事分别有了新家：复活点 = 时间线帧的位置；存档 = 定期自动；
##    回溯下限 = 没有了（可以退到本局最早，随机性彻底放开）。
const ANCHOR := {
	"save_path": "user://yunling_save.json",
	## ⭐⭐ M33（用户定案）：「**先把自动存档关了**」—— 600 秒 → **0 = 关闭**。
	##    ⚠️ `0` 是**语义值**，不是"每 0 秒存一次"：定时器见 `Game._process` 里的守卫，
	##       `<= 0` 直接跳过整段。把它改回正整数就恢复自动存档，不用动别的地方。
	##    ⚠️ 关掉的只是**定期**这一条。另外两条写盘路径**仍然存在**：
	##       ① 关窗口 / 停止运行（`Game._notification`）② 主角死亡（`_on_player_died`）。
	##       想让整局都不落盘，那两条也要一起关 —— 但那样退出即丢失全部进度。
	"autosave_sec": 0.0,
}

## ---------------- 印诀（M22 / 结印 M26）----------------
## ⭐ M26 用户拍板的触发方式（方案 A）：**按 R 起手进入结印状态 → 数字键填序列 → 凑齐结算**。
##    为什么不直接复用数字键：数字键已有职责「显化印」。复用会导致
##    「配成印诀的那两枚印再也无法单独使用」—— 那不能接受。
##    结印期间按下的印**不显化、不消耗**，只填进序列；代价只剩印诀那一笔灵力。
const COMBO_WINDOW := 1.2       # 结印窗口（秒）。每按一枚印**刷新**；超时安静收势，不扣任何东西。
## ⭐ **不用按键**：把需要的几枚印按出来（显化）的那一刻自动放。只吃灵力 +（各门自己的）冷却，
##    不消耗印的状态 —— 它是"合击"，不是"牺牲"。
## ⚠️ 键是**排过序**的两枚印名（用 combo_key() 生成）—— 别手写，写反了就对不上。
## 效果都建立在已有机制上（范围伤害 / DOT / 治疗 / 增益），不另造"持续领域"系统。
const COMBOS := {
	"云雨印|惊雷印": {
		"name": "雷雨交加", "kind": "storm",
		"essence": 30.0, "cooldown": 9.0,
		"radius": 110.0, "damage": 34.0, "dot": 6.0, "dot_time": 3.0, "heal": 40.0,
		"desc": "范围落雷 + 持续受创，自己回血",
	},
	"流风印|灰烬印": {
		"name": "燎原", "kind": "firewall",
		"essence": 28.0, "cooldown": 8.0,
		"length": 260.0, "width": 70.0, "damage": 30.0, "dot": 5.0, "dot_time": 4.0, "push": 70.0,
		"desc": "朝前一道火墙：灼烧 + 推开",
	},
	"惊雷印|灰烬印": {                 # ⚠️ 排序按**码点**：惊(60CA) < 灰(7070)，不是笔画顺序
		"name": "爆炎", "kind": "burst",
		"essence": 32.0, "cooldown": 10.0,
		"radius": 85.0, "damage": 48.0,
		"desc": "一颗爆裂火球：范围伤害",
	},
	"玄甲印|磐石印": {
		"name": "山岳", "kind": "guard",
		"essence": 25.0, "cooldown": 12.0,
		"duration": 6.0, "taken_mult": 0.5, "speed_mult": 0.6,
		"desc": "厚护盾 + 减伤 50%，移速 −40%",
	},
	"云雨印|流风印": {
		"name": "疾风", "kind": "haste",
		"essence": 22.0, "cooldown": 10.0,
		"duration": 5.0, "speed_mult": 1.6, "heal": 30.0,
		"desc": "移速 ×1.6 + 持续回血",
	},
	"惊雷印|磐石印": {
		"name": "引雷柱", "kind": "pillar",
		"essence": 30.0, "cooldown": 11.0,
		"radius": 130.0, "damage": 40.0, "dot": 7.0, "dot_time": 2.5,
		"desc": "立起石柱引雷：大范围落雷",
	},
}


## 两枚印的印诀键（**排过序**）。⚠️ 手写字符串一定会写反，一律走这里。
static func combo_key(a: String, b: String) -> String:
	var pair: Array = [a, b]
	pair.sort()
	return "%s|%s" % [pair[0], pair[1]]


## ⭐ M35：印诀的**伤害标签** = 两枚印标签的并集（弱点系统读它）。
##    为什么印诀也要吃弱点：§6 里「碧眼灵狐 · 强光破」说的是**印**克制它，
##    而印诀是两枚印合起来的那一下 —— 它当然也该算「你用了对的那个属性」。
static func combo_tags(key: String) -> Array:
	var out: Array = []
	for part in str(key).split("|"):
		if not SEALS.has(str(part)):
			continue
		for t in (SEALS[str(part)].get("tags", []) as Array):
			if not out.has(str(t)):
				out.append(str(t))
	return out


## ---------------- 闪避与冲刺（M20）----------------
## ⭐ **两者都由「已融合的灵印」给**，不是天生就会：
##    · 闪避：命窍里**有一枚养熟的印**就能用（身法来自印）
##    · 冲刺：得有一枚**标注了 move="dash" 的移速印**养熟（比如流风印）
## 灵力是共同燃料 —— 闪避与冲刺都从同一条灵力里扣。
const MOVE := {
	"dodge": {
		"essence": 8.0,        # 花多少灵力
		"cooldown": 1.0,       # 冷却（秒）
		"invuln": 0.30,        # 无敌帧（秒）—— 略长于翻滚，收尾也算安全
		"distance": 70.0,     # 位移距离（像素）
		## ⭐ 位移**时长**：翻滚是「滚过去」，不是「瞬移过去」。
		##    第一版是"一帧跳完"，用户一句话打回：「瞬移有点太快」。
		##    现在是 140px 分 0.28 秒（= 500 px/s ≈ 2.15 倍走速）。**要更慢就调大这个数**。
		"duration": 0.28,
	},
	"dash": {
		"essence": 12.0,
		"cooldown": 3.0,
		"duration": 1.2,       # 加速持续（秒）
		"speed_mult": 2.2,     # 加速期间的速度倍率
	},
}

## 身体部位：名字 -> 主角局部坐标。
## ⭐ 逻辑代码只认「名字」，不认坐标 —— 将来做真身体，把这里的值换成
##    骨骼/节点给的位置即可，其余一行都不用改。
const BODY_PARTS := {
	"右手": Vector2(12.0, -4.0),
	"左臂": Vector2(-12.0, -6.0),
	"躯干": Vector2(0.0, 3.0),
	"周身": Vector2.ZERO,
}

## 灵印表。passive 的三种取值，决定了「收回后加成立即消失」是怎么算的：
##   attack_damage   —— 加在普攻伤害上
##   damage_taken    —— 乘在「主角受到的伤害」上（越小越硬）
##   attack_cooldown —— 乘在普攻冷却上（越小越快）
##
## ⭐ 灵印有四种形态，由两条轴组合出来（不是四套特例代码）：
##   费用轴  activate 一次性 / drain 每秒
##   存续轴  instant 放完即收 / hold 到你收回或灵力扣光 / timed 到点自动收回
##     一次性攻击 = activate + instant
##     持续攻击   = 小额 activate + drain + hold
##     持续防御   = 小额 activate + drain + hold
##     一次性防御 = activate + timed
## 加第五枚印 = 往这张表里加一行。
const SEALS := {
	"灰烬印": {
		"tags": ["火"],        # 标签：印诀与（将来）推演都靠它
		"shape": "claw",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 1,                   # 十等：一等凡印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "attack_damage", "value": 4},
		"activate": 6.0,             # 按下时一次性扣的灵力
		## ⭐ M24：用户反馈「灰烬印消耗灵力太快」—— 6/秒 在炼气期只够烧 16 秒，太快。
		##    改成 2.5/秒（100 灵力 ≈ 40 秒）。玄甲(8) / 云雨(7) 还没动，觉得快就说。
		"drain": 2.5,                # 每秒扣的灵力（0 = 不持续扣）
		"life": "hold",              # 持续攻击：烧着的同时一直在扣灵力
		"seal_hp_max": 40.0,
		"passive": "attack_damage",
		"passive_value": 6.0,
		"radius": 11.0,
		"color": Color(0.86, 0.46, 0.30),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_ash.png"},
		"body_part": "右手",
		"skill": {
			"kind": "ember",
			"range": 55.0,
			"cooldown": 1.2,
			"damage": 3.0,                      # 每跳伤害
			"tick": 0.5,                        # 每跳间隔
			"duration": 3.0,                    # 灼烧持续时长
		},
	},
	"玄甲印": {
		"tags": ["岩", "守"],        # 标签：印诀与（将来）推演都靠它
		"shape": "hex",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		## ⭐ M31.4（用户拍板）：**1 → 2（一等凡印 → 二等）**。
		##    `WORLD_SITES` 里 M01 秘境给的玄甲印本来就是 `"rank": 2`，
		##    表里却是 1 —— 同一个印两个品阶，谁读表谁被坑。这里对齐到 2。
		## ⚠️⚠️ **另外两处 rank 改动本轮不做，只写目标值，别顺手改**：
		##    - **磐石印 1 → 3**：配 `REALMS[1]`（炼气）`seal_rank_max == 2` ⇒
		##      rank 3 会被 `Player.is_sealed()` 判成封印，而 harness 跑在炼气期，
		##      连带 5 条断言失败；要修就得动 `Game.gd` 的 harness（别人在改）。
		##    - **辉光印 2 → 3**：**同一条因果链**，同上。
		##    ⇒ 等 `Game.gd` 腾出手，这两处 + harness **一起改、一起验**，
		##      分开交会漏（`Game.gd:3130` 附近那条就是典型的假绿灯风险点）。
		"rank": 2,                   # 十等：二等
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "hp_max", "value": 24},
		"activate": 8.0,
		"drain": 8.0,
		"life": "hold",              # 持续防御：护着你的同时一直在扣灵力
		"seal_hp_max": 80.0,         # 最耐打的一枚
		"passive": "damage_taken",
		"passive_value": 0.70,
		"radius": 13.0,
		"color": Color(0.40, 0.62, 0.85),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_hex.png"},
		"body_part": "躯干",
		"skill": {
			"kind": "guard",                  # 常驻：替主角挨伤害
			"range": 75.0,
			"transfer": 0.5,
		},
	},
	"惊雷印": {
		"tags": ["雷"],        # 标签：印诀与（将来）推演都靠它
		"shape": "bolt",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,                   # 十等：二等精印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "attack_cooldown", "value": 0.9},
		"activate": 18.0,
		"drain": 0.0,
		"life": "instant",           # 一次性攻击：落雷落下就自动收回
		"seal_hp_max": 50.0,
		"passive": "attack_cooldown",
		"passive_value": 0.70,
		"radius": 12.0,
		"color": Color(0.72, 0.62, 0.95),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_bolt.png"},
		"body_part": "左臂",
		"skill": {
			"kind": "bolt",
			"range": 130.0,
			"cooldown": 2.0,
			"damage": 18.0,
			"warn": 0.25,                     # 落雷前的预警时间
		},
	},
	"磐石印": {
		"tags": ["岩"],        # 标签：印诀与（将来）推演都靠它
		"shape": "square",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 1,                   # 十等：一等凡印
		## 炼化满 100% 后**永久生效**的基础属性（和显化期的 passive 分开算，两者可叠）
		"base": {"stat": "essence_max", "value": 15},
		"activate": 14.0,
		"drain": 0.0,
		"life": "timed",            # 一次性防御：套一层盾，到点自动收回
		"life_time": 4.0,
		"seal_hp_max": 60.0,
		"passive": "damage_taken",
		"passive_value": 0.85,
		"radius": 12.0,
		"color": Color(0.60, 0.70, 0.55),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_rock.png"},
		"body_part": "周身",
		"skill": {
			"kind": "shield",
			"range": 0.0,
			"amount": 30.0,                   # 套一层 30 点的盾
		},
	},

	# ---- 以下三枚是灵师身上的印（M10）。开局你一枚都没有，只能靠强夺拿到 ----
	"云雨印": {
		"tags": ["水"],        # 标签：印诀与（将来）推演都靠它
		"shape": "drop",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,
		"base": {"stat": "hp_max", "value": 18},
		"activate": 10.0,
		"drain": 7.0,
		"life": "hold",              # 持续防御：一直在滋润你的气血
		"seal_hp_max": 55.0,
		"passive": "damage_taken",
		"passive_value": 0.90,
		"radius": 12.0,
		"color": Color(0.45, 0.72, 0.90),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_rain.png"},
		"body_part": "躯干",
		"skill": {
			"kind": "heal",
			"range": 0.0,
			"cooldown": 2.0,
			"heal": 4.0,                       # 每 2 秒给主角回 4 点气血
		},
	},
	"流风印": {
		"tags": ["风"],        # 标签：印诀与（将来）推演都靠它
		"shape": "leaf",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,
		## ⭐ 流风印是**移速印**：养熟它，主角才学会「冲刺」（见 MOVE 表）。
		"move": "dash",
		"base": {"stat": "move_speed", "value": 15.0},
		"activate": 12.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 45.0,
		"passive": "attack_cooldown",
		"passive_value": 0.85,
		"radius": 10.0,
		"color": Color(0.62, 0.86, 0.72),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_wind.png"},
		"body_part": "左臂",
		"skill": {
			"kind": "bolt",
			"range": 100.0,
			"cooldown": 1.4,
			"damage": 11.0,
			"warn": 0.15,                    # 又轻又快：单发弱，但几乎不给你反应时间
		},
	},
	"辉光印": {
		"tags": ["光", "爆"],        # 标签：印诀与（将来）推演都靠它
		"shape": "star",        # 形状语言：一眼认出是哪个印（先简化成几何图形）
		"rank": 2,
		"base": {"stat": "essence_max", "value": 12},
		"activate": 16.0,
		"drain": 0.0,
		"life": "timed",
		"life_time": 5.0,
		"seal_hp_max": 70.0,
		"passive": "attack_damage",
		"passive_value": 5.0,
		"radius": 14.0,
		"color": Color(0.95, 0.90, 0.60),
		# ⭐ M30.5（路线②）：贴图优先，文件不在就自动回退到形状语言
		"visual": {"texture": "res://art/seals/seal_light.png"},
		"body_part": "周身",
		"skill": {
			"kind": "shield",
			"range": 0.0,
			"amount": 45.0,                   # 比磐石印更厚的盾
		},
	},

	# ==================== 以下是《数值设计》v2 §2.1 新增的三枚基础印 ====================
	## ⭐ 碎石印：**第一枚「伤害写倍率」的印** —— `power: 2.0` = 普攻 × 2.0。
	##    为什么从这里开始改：§0 第一条锚点是「普攻是标尺，所有伤害写成普攻 × 倍率」。
	##    上面那七枚还是写死的绝对值（它们是 M3~M12 时代的产物，改动会连带一批已锁定的
	##    断言和手感），从新印开始走倍率，老的等一次专门的平衡轮再迁。
	##    ⚠️ 两种写法在 `Seal._hit_power()` 里**共存**：有 `power` 用倍率，没有就回退 `damage`。
	"碎石印": {
		"tags": ["岩", "穿"],
		"shape": "shard",
		"rank": 2,
		## 炼化被动 = 穿刺 +6%。实现成 `damage_mult`（伤害 ×1.06）——
		## ⚠️ 工程里还没有「护甲」这个量，所以「无视 6% 防御」目前只能等价成「伤害 +6%」。
		##    等敌人有护甲了，这里换成真的穿甲，字段名不用动。
		"base": {"stat": "damage_mult", "value": 1.06},
		"activate": 12.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 50.0,
		"passive": "damage_mult",
		"passive_value": 1.06,
		"radius": 12.0,
		"color": Color(0.74, 0.71, 0.62),
		"visual": {"texture": "res://art/seals/seal_shard.png"},
		"body_part": "右手",
		"skill": {
			"kind": "pierce",
			"range": 150.0,
			"cooldown": 1.6,
			"power": 2.0,
		},
	},
	## ⭐ 落叶印 / 泥巴印：§2.1 最后一行 —— **垫子印**（`skill.kind = "none"`）。
	##    它们不能打、不能防，存在的意义只有两个：当融合的副印、当破阶的祭品。
	##    为什么游戏需要这种东西：融合要「副印」，如果每一枚副印都得是能打的印，
	##    那玩家永远舍不得融 —— 有一批「本来就是喂的」印，融合才下得去手。
	##    ⚠️ `life = "instant"` + `kind = "none"` ⇒ 显化后当帧就自动收回（不烧灵力、不掉血）。
	"落叶印": {
		"tags": ["木"],
		"shape": "leaf2",
		"rank": 1,
		"base": {"stat": "attack_damage", "value": 1},
		"activate": 2.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 30.0,
		"passive": "attack_damage",
		"passive_value": 1.0,
		"radius": 9.0,
		"color": Color(0.62, 0.74, 0.38),
		"visual": {"texture": "res://art/seals/seal_fallen.png"},
		"body_part": "周身",
		"skill": {"kind": "none"},
	},
	"泥巴印": {
		"tags": ["土"],
		"shape": "mud",
		"rank": 1,
		"base": {"stat": "hp_max", "value": 6},
		"activate": 2.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 30.0,
		"passive": "damage_taken",
		"passive_value": 0.97,
		"radius": 10.0,
		"color": Color(0.55, 0.45, 0.32),
		"visual": {"texture": "res://art/seals/seal_mud.png"},
		"body_part": "周身",
		"skill": {"kind": "none"},
	},

	# ==================== 以下是《数值设计》v2 §2.2 的五枚**组合印** ====================
	## ⭐ 组合印 = 融合配方的产物：**占 1 个槽、自带一门复合技**。
	##    它们和「变异词条」是两个正交的维度（§2.2 抬头那句）：
	##    组合印可以没有变异，变异也可以挂在任何普通印上。
	## ⚠️ `fusion_only: true` = **不能在世界上捡到**：刷怪表 / 采集点 / 商人货架都不出。
	##    它只有两条来路，而且两条都是「做出来的」：
	##      ① 按 `recipe` 融出来（§2.2）
	##      ② 攒够 `SHARDS` 残片凝出来（§5）—— 通印残片 → 熔岩印
	##    ⇒ 所以这个字段更准确的读法是「**crafted**」，不是「只能融合」。
	##      残片那条路是保底：融了十几次都没出，攒 10 片通印残片也能拿到一枚。
	##    `recipe` 是融合配方（无序，用 combo_key 比较）—— 和 COMBOS 的键同一个规矩。
	## ⚠️ 这五枚的招式统一用 `kind: "aoe"`：一个圆形范围 + 一条状态。
	##    一种写法吃五种印，加第六枚组合印只加数据（§2.2 那张表本来就是这么排的）。
	"雷雨印": {
		"tags": ["水", "雷"],
		"shape": "storm",
		"rank": 2,
		"fusion_only": true,
		"recipe": ["云雨印", "惊雷印"],
		"base": {"stat": "essence_max", "value": 14},
		"activate": 24.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 60.0,
		"passive": "attack_cooldown",
		"passive_value": 0.92,
		"radius": 13.0,
		"color": Color(0.52, 0.72, 0.95),
		"visual": {"texture": "res://art/seals/seal_thunderrain.png"},
		"body_part": "左臂",
		"skill": {
			"kind": "aoe",
			"range": 130.0,
			"radius": 95.0,
			"cooldown": 3.0,
			"power": 2.5,
			## 必潮湿 + 麻痹：潮湿是雷系的引子（惊雷印打在潮湿上 ×2），麻痹是硬控。
			"status": {"name": "wet", "time": 4.0},
			"stun": 0.6,
		},
	},
	"沸血印": {
		"tags": ["火", "水"],
		"shape": "boil",
		"rank": 2,
		"fusion_only": true,
		"recipe": ["灰烬印", "云雨印"],
		"base": {"stat": "attack_damage", "value": 5},
		"activate": 22.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 55.0,
		"passive": "attack_damage",
		"passive_value": 4.0,
		"radius": 12.0,
		"color": Color(0.88, 0.52, 0.42),
		"visual": {"texture": "res://art/seals/seal_boil.png"},
		"body_part": "右手",
		"skill": {
			"kind": "aoe",
			"range": 120.0,
			"radius": 80.0,
			"cooldown": 2.6,
			"power": 2.0,
			"status": {"name": "blind", "time": 3.0},
		},
	},
	"泥沼印": {
		"tags": ["水", "土"],
		"shape": "mire",
		"rank": 2,
		"fusion_only": true,
		"recipe": ["云雨印", "碎石印"],
		"base": {"stat": "hp_max", "value": 20},
		"activate": 20.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 65.0,
		"passive": "damage_taken",
		"passive_value": 0.88,
		"radius": 12.0,
		"color": Color(0.48, 0.56, 0.42),
		"visual": {"texture": "res://art/seals/seal_mire.png"},
		"body_part": "周身",
		"skill": {
			"kind": "aoe",
			"range": 110.0,
			"radius": 100.0,
			"cooldown": 3.2,
			"power": 0.5,
			"status": {"name": "slow", "time": 4.0},
			## 「禁闪避」：泥泞里站不住 —— 敌人不能用它的位移技。
			"no_dodge": true,
		},
	},
	"熔岩印": {
		"tags": ["火", "岩"],
		"shape": "lava",
		"rank": 3,
		"fusion_only": true,
		"recipe": ["灰烬印", "碎石印"],
		"base": {"stat": "attack_damage", "value": 8},
		"activate": 34.0,
		"drain": 0.0,
		"life": "instant",
		"seal_hp_max": 75.0,
		"passive": "attack_damage",
		"passive_value": 7.0,
		"radius": 14.0,
		"color": Color(0.92, 0.44, 0.22),
		"visual": {"texture": "res://art/seals/seal_lava.png"},
		"body_part": "右手",
		"skill": {
			"kind": "aoe",
			"range": 140.0,
			"radius": 88.0,
			"cooldown": 3.6,
			"power": 4.0,
			"status": {"name": "burn", "time": 3.0},
			"knockback": 90.0,
		},
	},
	"金刚印": {
		"tags": ["岩", "守"],
		"shape": "vajra",
		"rank": 3,
		"fusion_only": true,
		"recipe": ["玄甲印", "碎石印"],
		"base": {"stat": "hp_max", "value": 32},
		"activate": 26.0,
		"drain": 0.0,
		"life": "timed",
		"life_time": 6.0,
		"seal_hp_max": 95.0,
		"passive": "damage_taken",
		"passive_value": 0.78,
		"radius": 15.0,
		"color": Color(0.78, 0.72, 0.46),
		"visual": {"texture": "res://art/seals/seal_vajra.png"},
		"body_part": "周身",
		"skill": {
			"kind": "shield",
			"range": 0.0,
			"amount": 80.0,                   # 巨额盾：磐石 30 / 辉光 45 / 金刚 80
			## 「免疫击退」：护盾期间不被推走（Game 侧在击退处读它）。
			"no_knockback": true,
		},
	},
}

# ==================== 融合 · 横向（数值设计 v2 §3.2）====================
## ⭐ 一句话：**升级是纵向变强（同一件事做得更好），融合是横向变强（多做一件别的事）**
##    —— 用户定案的原话。所以融合**不改**主印的名字 / 主动 / rank / tags，
##    它只把副印的 `base` 打折成一条「融词条」挂上去。
## ⚠️ 上限 = 主印 rank 条词条。这是「横向不能无限宽」的唯一刹车 ——
##    没有它，一枚 1 等印可以把全世界的印都融进来，等级就失去意义了。
const FUSION := {
	"success": 0.85,         # 85%。失败：副印毁、主印无损、灵力不退
	"affix_ratio": 0.5,      # 副印 base × 50%
	"cost_per_rank": 80.0,   # 灵力成本 = 主印 rank × 80
}

## 融合产出一条「融词条」长什么样。
## ⚠️ 值按 `affix_ratio` 打折，但 **`attack_cooldown` 这种乘算属性不能直接乘 0.5** ——
##    0.9 × 0.5 = 0.45 会把冷却砍一半，那比原印本身还强。乘算属性走「往 1.0 靠一半」。
static func fusion_affix(sub_name: String) -> Dictionary:
	var sub: Dictionary = SEALS.get(sub_name, {})
	var b: Dictionary = sub.get("base", {})
	if b.is_empty():
		return {}
	var stat := str(b.get("stat", ""))
	var raw := float(b.get("value", 0.0))
	var val := raw
	if stat == "attack_cooldown" or stat == "damage_mult":
		val = 1.0 + (raw - 1.0) * float(FUSION["affix_ratio"])
	else:
		val = raw * float(FUSION["affix_ratio"])
	return {"stat": stat, "value": val, "from": sub_name, "kind": "fusion"}


## 一枚印最多能有几条融词条 = 它的等级（§3.2 上限）。
static func fusion_limit(rank: int) -> int:
	return maxi(1, rank)


## 融合一次要多少灵力 = 主印 rank × 80。
static func fusion_cost(rank: int) -> float:
	return float(FUSION["cost_per_rank"]) * float(maxi(1, rank))


## 两枚印能不能融：不能同种、副印必须在表里、副印不能是组合印（组合印不能再被吃）。
static func can_fuse(main_name: String, sub_name: String) -> Dictionary:
	if not SEALS.has(main_name) or not SEALS.has(sub_name):
		return {"ok": false, "reason": "印不存在"}
	if main_name == sub_name:
		return {"ok": false, "reason": "不能拿自己当副印"}
	if bool(SEALS[sub_name].get("fusion_only", false)):
		return {"ok": false, "reason": "组合印不能再当副印被吸收"}
	if (SEALS[sub_name].get("base", {}) as Dictionary).is_empty():
		return {"ok": false, "reason": "这枚印没有可吸收的属性"}
	return {"ok": true, "reason": ""}


## 配方 → 组合印。⭐ 无序匹配（`combo_key` 同一个规矩），加配方只加数据。
static func fusion_result(a: String, b: String) -> String:
	var key := combo_key(a, b)
	for name_key in SEALS.keys():
		var s: Dictionary = SEALS[name_key]
		if not bool(s.get("fusion_only", false)):
			continue
		var rec: Array = s.get("recipe", [])
		if rec.size() != 2:
			continue
		if combo_key(str(rec[0]), str(rec[1])) == key:
			return str(name_key)
	return ""


# ==================== 升级 · 纵向（数值设计 v2 §3.4）====================
## ⭐ 升级 = **纵向变强**：「保留一个主印的特征」，只把它的数字往上抬。
##    四条门槛缺一不可：境界 ≥ 目标 rank / 炼化满 100 / 天材地宝 / 环境匹配
##    —— 门槛的判定在 Player 侧（它才知道玩家的境界与背包）。
## ⚠️ 这里只放**数值**：倍率、成功率、反噬比例。别把判定写进数据表。
const UPGRADE := {
	"active_mult": 1.4,      # 主动 ×1.4
	"passive_mult": 1.5,     # 被动 ×1.5
	"seal_hp_mult": 1.3,     # 印体 ×1.3
	"activate_mult": 0.9,    # activate −10%
	"base_chance": 0.30,     # 30% 起
	"per_fodder": 0.20,      # 每枚同名祭品 +20%
	"fodder_max": 3,         # 最多 3 枚 → 最高 90%
	"fail_hp_cap": 0.10,     # 失败：雷劫反噬气血上限 −10%
}

## 破阶成功率（含祭品加成）。`fodder` = 投入的同名祭品枚数。
static func upgrade_chance(fodder: int) -> float:
	var n := clampi(fodder, 0, int(UPGRADE["fodder_max"]))
	return clampf(float(UPGRADE["base_chance"]) + float(UPGRADE["per_fodder"]) * float(n), 0.0, 0.9)


# ==================== 变异（数值设计 v2 §3.3）====================
## ⭐ 变异 = **印上的一条词条**（不是独立印种）—— §3.3.5 定案。
##    所以它可以：「直接获得 / 当主印继续融合 / 当副印被吸收（只贡献属性）/ 升级后保留」。
## ⚠️ 每枚印最多 1 条变异词条（不能叠 2 条前缀）。
const MUTATION := {
	"max_per_seal": 1,
	"damage_mult": 1.5,       # 三大质变统一：伤害 ×1.5
	## 四条**自己触发**的途径（第 ⑤ 条是「直接获得」，不需要概率）
	"routes": {
		"fusion":        {"chance": 0.05, "label": "融合变异"},
		"fusion_attune": {"chance": 0.15, "label": "融合变异（触媒契合）"},
		"env":           {"chance": 0.20, "label": "环境变异"},
		"devour":        {"chance": 0.30, "label": "吞噬变异"},
		"life_death":    {"chance": 0.02, "label": "生死变异"},
	},
	## 吞噬变异会**降低**破阶成功率（§3.3.1 ③）
	"devour_penalty": 0.15,
	## 变异词条表。`tags` = 给这枚印额外挂上的标签（弱点判定会读它）。
	"affixes": {
		"灼烧":   {"kind": "word", "tags": ["火"], "desc": "火伤 + 禁疗", "heal_block": true},
		"霜冻":   {"kind": "word", "tags": ["冰"], "desc": "冰伤 + 冰冻", "stun": 0.8},
		"穿甲":   {"kind": "word", "tags": ["穿"], "desc": "无视 50% 物防", "damage_mult": 1.5},
		"致盲":   {"kind": "word", "tags": ["光"], "desc": "致盲范围 ×2", "blind_mult": 2.0},
		"迷幻":   {"kind": "word", "tags": ["幻"], "desc": "泥沼敌人见幻影", "illusion": true},
		"连锁雷": {"kind": "form", "tags": ["雷"], "desc": "雷电弹射 3 次、200px", "chain": 3, "chain_range": 200.0},
		"环身火": {"kind": "form", "tags": ["火"], "desc": "以自身为圆心环爆", "ring": true},
		"轻灵风": {"kind": "aura", "tags": ["风"], "desc": "闪避不耗体力", "free_dodge": true},
	},
}

## 某个变异途径的概率。`attuned` 只对 `fusion` 有意义（触媒与主副印属性契合）。
static func mutation_chance(route: String, attuned := false) -> float:
	var r: Dictionary = MUTATION["routes"]
	if route == "fusion" and attuned:
		route = "fusion_attune"
	if not r.has(route):
		return 0.0
	return float(r[route]["chance"])


## 一条变异词条的全部数据（找不到就返回 {}）。
static func mutation_affix(name_key: String) -> Dictionary:
	return (MUTATION["affixes"] as Dictionary).get(name_key, {})


## 这张表还算数吗（自测用：守的是「每条词条都有 kind / tags / desc」）。
static func mutations_well_formed() -> bool:
	for k in (MUTATION["affixes"] as Dictionary).keys():
		var a: Dictionary = MUTATION["affixes"][k]
		if not (a.has("kind") and a.has("tags") and a.has("desc")):
			return false
		if (a["tags"] as Array).is_empty():
			return false
	for k2 in (MUTATION["routes"] as Dictionary).keys():
		var p := float(MUTATION["routes"][k2]["chance"])
		if p <= 0.0 or p > 1.0:
			return false
	return true


## 开局命窍里的**两枚**印，顺序 = 数字键 1 / 2。
## ⭐ 只剩两枚是刻意的：惊雷印 / 磐石印改为**世界获得**（两只精英各掉一枚），
##    让"拿不到 → 拿到 → 还没融合不能用的"这条线在开局就成立。
const SEAL_ORDER := ["灰烬印", "玄甲印"]

## 灵印死亡的代价（待决问题 1）：反噬 = 气血上限 × 这个比例。
const SEAL_DEATH_BACKLASH := 0.15
## 灵印死亡后，该槽位受损、不可用的秒数。
const SLOT_DAMAGED_TIME := 60.0

# ---------------- 世界与分区（M7）----------------
# ⭐ 世界比屏幕大。相机跟着主角走，边界就是世界尺寸。
# ⚠️ M29 起**世界与所有距离减半**（2560×1440 → 1280×720）：相机 zoom = 2，
#    所以屏幕上看到的范围与改动前**完全一样**（683×384 世界像素 = 1366×768 屏幕像素），
#    但每个美术像素占 2×2 个屏幕像素 —— 像素颗粒粗一倍，空间关系不变。
## ⭐⭐ M34：**区域表** —— 「世界」从一组常量变成一行数据。
##
## 为什么要它：五大疆域 + 四大绝地 = 九张数据图，塞不进 WORLD_COLS/ROWS 这种常量。
##    但**数据格式一点没变**：每个区域仍是「一张 N×M 的 PNG（1px = 1 格）+ 一个 sig」，
##    由 `gen_worldmap.mjs --region=` 烘焙。所以加一个域 = 加一行，不是加一套系统。
##
## ⭐ `origin` 是它在**全局格坐标**里的左上角。存档存的是**全局坐标**（origin×32 + 局部像素），
##    这样以后把「切换」升级成「无缝」时，存档格式不用再动第二次。
##
## ⚠️ 骨架期：`east_march` 复用 cangwu 的数据图（同一张 PNG、同一个 sig）。
##    它的唯一用途是验证「多区域 + 跨区 + 存档带 region」这条链路，不是真内容。
const REGIONS := {
	"cangwu": {
		"name": "苍梧山",
		"origin": Vector2i(0, 0),
		"cols": 112,
		"rows": 96,
		"map": "res://art/world/worldmap.png",
		"sig": "res://art/world/worldmap.sig",
		"neighbors": {"east": "east_march"},
	},
	"east_march": {
		"name": "东荒边地（骨架区）",
		"origin": Vector2i(112, 0),
		"cols": 112,
		"rows": 96,
		"map": "res://art/world/worldmap.png",
		"sig": "res://art/world/worldmap.sig",
		"neighbors": {"west": "cangwu"},
	},
}
const START_REGION := "cangwu"
## 当前区域。⚠️ static var 不是 const：切区要改它。
static var current_region := START_REGION
## 世界容器。⚠️ 也变成 static var —— 它的值跟着当前区域走（原来是 const）。
static var WORLD := {
	## ⭐ M31 Step 0：**世界容器 3584×3072**（= 112×96 格 × 32px）——《40 屏世界容器架构方案》定案。
	##    ⚠️ 上一版是 5120×2880（160×90 格）：横向收窄 30%、纵向加高 6.7%，
	##    纵横比从 16:9 变成 7:6。旧存档坐标按比例缩放后 clamp（见 SaveGame.VERSION 8）。
	"size": Vector2(3584.0, 3072.0),
}

## 视口与相机缩放（M29）。⭐ 这两个数字决定「1 个美术像素 = 几个屏幕像素」：
##   相机 zoom = 2 且世界与所有距离**减半** → 可见范围 = 视口 ÷ zoom = 683×384 世界像素，
##   屏幕上仍是 1366×768，但每个美术像素占 2×2 个屏幕像素（像素颗粒粗一倍、空间关系不变）。
## ⚠️ 场景里 Camera 的 zoom 必须与 CAMERA_ZOOM 一致 —— 自测守着这一条。
const VIEWPORT := Vector2(1366.0, 768.0)
const CAMERA_ZOOM := 2.0

## 分区。⭐ 分区只是「矩形 + 名字」，但它有三个用途：
##   ① 采集产出（M8：不同区出不同材料）② 敌人配置（M10）③ 让玩家认路
## 四个区各占世界一角，锚点在正中间 —— 从中心出发，四条路各通一个区。
## ⭐ M30.13（用户定案）：「没必要做成四个区域，先做好一个修仙世界」
##    → **一张连续大地图**：地形按**离出生点的远近**分层，越远越硬、越远越好的料。
##    边界用正弦扰动做成**不规则过渡线**（不是四个直角方块）。
## ⚠️ 迁移中：`ZONES`（四分区）暂时**只用来给采集点/敌人打标签**，渲染已经不看它了。
##    下一步把采集点/敌人改成按距离分布 + 把 4 条分区断言换成地形断言，那时才删 `ZONES`。
## ⭐⭐ M30.13c：**世界数据表**（由 `art/tools/gen_worldmap.mjs` 导出，112×96 格 × 32px）
##    R = 地形 id×50 / G = 海拔 / B = 水深 —— **渲染与玩法读同一张表**。
##    ⚠️ 绝不在 GDScript 里重算噪声：那会让「画出来的山」和「判定里的山」变成两座山。
## ⚠️ 这三个也是**当前区域派生**的（原先是 const）。切区时由 `set_region()` 改。
static var WORLD_MAP_PATH := "res://art/world/worldmap.png"
static var WORLD_COLS := 112
static var WORLD_ROWS := 96
const WORLD_CELL := 32.0

## ---- 区域 API（M34）----
static func region_cfg(id: String) -> Dictionary:
	return REGIONS.get(id, {}) as Dictionary

static func region_ids() -> Array:
	return REGIONS.keys()

## 这个区域的世界尺寸（像素）。⚠️ 和 `WORLD["size"]` 的区别：后者是**当前**区域的。
static func region_size(id: String) -> Vector2:
	var cfg := region_cfg(id)
	return Vector2(float(cfg.get("cols", 0)) * WORLD_CELL, float(cfg.get("rows", 0)) * WORLD_CELL)

## 这个区域左上角的**全局像素坐标**。
static func region_origin(id: String) -> Vector2:
	var o: Vector2i = region_cfg(id).get("origin", Vector2i.ZERO) as Vector2i
	return Vector2(float(o.x) * WORLD_CELL, float(o.y) * WORLD_CELL)

static func local_to_global(id: String, local_pos: Vector2) -> Vector2:
	return region_origin(id) + local_pos

static func global_to_local(id: String, global_pos: Vector2) -> Vector2:
	return global_pos - region_origin(id)

static func neighbors_of(id: String) -> Dictionary:
	return region_cfg(id).get("neighbors", {}) as Dictionary

## 切到某个区域：把所有「当前区域派生」的量一起换掉。
## ⚠️ 返回 false = id 不存在。调用方**必须**处理，不能假设切成功。
static func set_region(id: String) -> bool:
	if not REGIONS.has(id):
		return false
	current_region = id
	var cfg := region_cfg(id)
	WORLD_COLS = int(cfg["cols"])
	WORLD_ROWS = int(cfg["rows"])
	WORLD_MAP_PATH = str(cfg["map"])
	WORLD_SIG_PATH = str(cfg["sig"])
	WORLD = {"size": region_size(id)}
	return true
## 地形 id → 名字。⚠️ 顺序必须和生成器里的 T 一致（水/草/林/山/灵田/泥沼）
const WORLD_TERRAINS := ["水泽", "草地", "竹林", "灵岩", "灵田", "泥沼"]
## 崖的判定阈值：相邻格高差超过它就算一面崖
const CLIFF_STEP := 0.06
## 海拔 1.0 抬高多少像素。
## ⭐⭐ M31.3 重烘焙：48 → **200**。改它的唯一理由是「**级差与落差的数量级**」：
##    ① **级差**：21 级量化 → 一级 = 1/20 × 200 = **10 世界单位**。
##       硬上限是 **12**（=`CLIFF_STEP` 0.06 × 200）：超过它，相邻台地就被判成崖 ——
##       而 `can_step()` 对高差是**放行**的 → 「画面看着是墙、人却能走上去」，正是用户否决过的观感。
##    ② **落差**：量化后实际跨度 0.75 → 150 世界单位 ≈ **3.1 个身高**（身高 48）。
##       48 的时候落差只有 19px —— 不到半个身高，肉眼读出来是「平铺的花色」而不是「山」。
## 只影响观感（`_draw_world_height` 的 y 偏移 + 裁剪 padding），不参与任何碰撞判定。
##
## ⚠️⚠️ **抬升会露出「暗缝」（台缘下方的底色条），这是几何必然，不要当成 padding bug 去修**：
##    每格只画**顶面**（M30.13e 按用户定案删了崖壁竖面），画在 `y - e×ELEV_LIFT`。
##    于是**只要某格的北邻比它高**，北邻就被抬得更高，两格之间露出一段底色，
##    缝高 = `Δe × ELEV_LIFT`（只在**向南下降**的相邻关系上出现；东西向只会错台，不露缝）。
##    缝的形状恒为「**一格宽 × Δe×LIFT 高**」的竖条 —— 这就是「台阶」观感的直接来源。
##
##    ⭐ M31.3 收尾的**两次更正**（此前关于「黑带」的结论全部作废，别再引用）：
##    ① 此前观察到的**大面积黑带不是几何**，是 `Game._process` 里 `queue_redraw()`
##       被 `if hits.is_empty(): return` 短路（不打架不重画，绘制命令被缓存，
##       vis_r 又按上次 _draw 时的玩家位置裁）→ 走远了屏幕上就没格子。**已修（fbe4fab）**。
##       ⇒ 「抬 LIFT 会导致黑带」这条规律**不存在**，LIFT=150 那次看到的黑带也是它。
##    ② 但**暗缝是真的存在**，不是被"低格纹理补位"掉的 —— 修复后重新抓帧实测
##       （`art/tools/preview_v2_*.png`）：drop 点未覆盖 **24.2%**、shore **10.5%**、slope **3.7%**；
##       最大一块 **244 屏幕px 高**（@zoom2 = 122 世界单位 ≈ 0.61×200，正是 cell(39,11) 那条 0.60 落差），
##       另有一批 h21×w64 的小竖条 = 「一级台阶(0.05)×一格宽(32)」的逐条暗缝。
##    → **无暗缝的条件是 `maxΔe × ELEV_LIFT < 一格高(32)`**，即 `ELEV_LIFT < 53`。
##      当前 200 远大于它 ⇒ 暗缝是**已知且被接受的代价**，解法在渲染层（见下），不是压落差。
##    → 正解是补**南向裙边**：把低格自己的顶面**向上延伸 Δe×LIFT** 画一条同色同纹理的竖条
##      （不是 M30.13e 被否决的那种灰色崖壁墙）。LIFT 越大裙边越长、立体感越强，
##      所以 **抬 LIFT 没有黑带代价，只有"没做裙边就露缝"的代价** —— 别为了躲缝把落差压回去。
##    ⚠️ 已作废判据「`ELEV_LIFT ≤ 视口半屏高`」：整片平移、上缘由下方同海拔格补位，
##      该判据与画面表现无关（当时那条"实测 0% 未覆盖"是在坏探针下测的，无效）。
##      padding 只决定画哪些格、不改变画在哪；抬升向上，需要补的只有 `pad_dn`（已补）。
## ⭐⭐ M33（用户拍板）：「**全是平坦的地面**」—— 抬升 200 → **0**。
##    ⇒ 上面那一整段关于「暗缝 / 裙边 / LIFT 上限」的分析**全部作废**：
##      缝高 = Δe × LIFT = 0，几何上不可能再露缝，也不需要裙边。
##      （那段注释保留是有意的：它记录了"为什么曾经要 200、以及怎么算的"，
##       将来若想恢复立体，从那里接着读，不要重新踩一遍。）
##    ⇒ 高度数据本身**还在**（worldmap 的 G 通道），只是不再参与绘制；
##      `_draw_world_height` 的"按海拔排序"仍然执行 —— 平地时它退化成一次无意义的排序，
##      代价可忽略，好处是不用再写一条"平地专用"的分支（两套渲染路径才是真正的风险）。
const ELEV_LIFT := 0.0

## ⭐ M34：缓存按**路径**分，不是一个字段 —— 来回切区时不用反复解码同一张图。
##    ⚠️ null 也缓存（和旧实现的 `_world_tried` 一个道理）：美术没导出时不至于每帧重试。
static var _world_imgs: Dictionary = {}

## 读一次就缓存（112×96 很小；**不要每帧读**）
static func world_image() -> Image:
	if _world_imgs.has(WORLD_MAP_PATH):
		return _world_imgs[WORLD_MAP_PATH] as Image
	var out: Image = null
	var tex: Texture2D = load(WORLD_MAP_PATH) as Texture2D
	if tex != null:
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			out = img
	_world_imgs[WORLD_MAP_PATH] = out
	return out

static func world_ready() -> bool:
	var img := world_image()
	return img != null and img.get_width() == WORLD_COLS and img.get_height() == WORLD_ROWS


## ⭐ M31.3：**世界图签名**（`world_sig`）—— 重烘焙 `worldmap.png` 的**安全网**。
##
## 为什么必须先装它：改这张图会**静默**连带改三样东西，且三者都没有任何检测机制 ——
##   ① `speed_mult_at()` 的涉水减速（M31.4 起**高地减速已删除**，只剩涉水 ×0.60；
##      阈值不再依赖海拔直方图，但深水的分布仍随重烘焙变化）
##   ② `gen_worldmap.mjs` 里写死 `e01 = 0.4` 的出生点（LEVELS 一改可能落到水里或崖上）
##   ③ 同心层 / 主城的地块排布（山长在哪儿会变）
## 签名把「意外改动」变成「必须显式确认的改动」：重烘焙后自测必红，逼人去更新基线。
##
## ⚠️ 两条设计纪律：
##   ① **不用引擎的 `hash()`** —— 它的实现不保证跨版本 / 跨机器一致；签名必须可复现。
##      这里自己写两个 32 位整数哈希（FNV-1a + SDBM），纯整数运算，到哪台机器都一样。
##   ② 输入是**解码后的 RGBA8 像素**，不是文件字节 —— 换个编码器重导出、像素没变就不该报警。
static var WORLD_SIG_PATH := "res://art/world/worldmap.sig"


static func _sig_fnv(b: PackedByteArray) -> int:
	var h := 2166136261
	for v in b:
		h = ((h ^ v) * 16777619) & 0xFFFFFFFF
	return h


static func _sig_sdbm(b: PackedByteArray) -> int:
	var h := 0
	for v in b:
		h = (v + (h << 6) + (h << 10) - h) & 0xFFFFFFFF
	return h


static func world_sig() -> String:
	var img := world_image()
	if img == null:
		return "no-image"
	var c: Image = img.duplicate()     # ⚠️ 显式标注：`duplicate()` 返回 Variant，不标会推不出类型
	c.convert(Image.FORMAT_RGBA8)      # 统一字节布局，免得编码格式影响签名
	var b: PackedByteArray = c.get_data()
	return "w1-%d-%d-%dx%d" % [_sig_fnv(b), _sig_sdbm(b), c.get_width(), c.get_height()]


## 基线（存在 `art/world/worldmap.sig`）。空串 = 还没建基线。
static func world_sig_baseline() -> String:
	if not FileAccess.file_exists(WORLD_SIG_PATH):
		return ""
	return FileAccess.get_file_as_string(WORLD_SIG_PATH).strip_edges()

static func world_cell(cx: int, cy: int) -> Color:
	var img := world_image()
	if img == null or cx < 0 or cy < 0 or cx >= WORLD_COLS or cy >= WORLD_ROWS:
		return Color(0.0, 0.0, 0.0, 0.0)
	return img.get_pixel(cx, cy)

static func cell_terrain(cx: int, cy: int) -> String:
	var idx := int(round(world_cell(cx, cy).r * 255.0 / 50.0))
	return WORLD_TERRAINS[clampi(idx, 0, WORLD_TERRAINS.size() - 1)]

static func cell_elev(cx: int, cy: int) -> float:
	return world_cell(cx, cy).g

static func cell_depth(cx: int, cy: int) -> float:
	return world_cell(cx, cy).b

static func in_map(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < WORLD_COLS and c.y < WORLD_ROWS

## ⭐ M33：**格坐标哈希** —— 地表碎屑、装饰物、瓦片变体，凡"看起来随机"的东西都由它决定。
##
## 为什么不用 `randf()`：这些东西要在 `_draw` / 构建期决定，而 `_draw` 每帧都跑 ——
##    随机数会让同一根草每帧跳位置（闪），还违反「_draw 里不许分配」的红线。
## 为什么不用引擎的 `hash()`：它不保证跨版本 / 跨机器一致（和 `world_sig` 同一条纪律）。
## ⚠️ 放在 GameData 而不是 Game：静态世界和地形是**同一套坐标**，哈希也只有一份，
##    否则「Game 里算的草」和「Props 里算的石头」会落在两套互不相干的位置上。
static func cell_hash(cx: int, cy: int) -> int:
	return absi((cx * 73856093) ^ (cy * 19349663) ^ 0x5BD1E995)


static func cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x / WORLD_CELL)), int(floor(pos.y / WORLD_CELL)))

static func elev_at_pos(pos: Vector2) -> float:
	var c := cell_of(pos)
	return cell_elev(c.x, c.y)

static func depth_at_pos(pos: Vector2) -> float:
	var c := cell_of(pos)
	return cell_depth(c.x, c.y)


## ⭐ M30.13d：**能不能从这里走到那里** —— 用户在意的「走在山上真的感觉在山上」就靠它。
##    ⚠️ 阈值和崖面渲染是**同一个** `CLIFF_STEP`。用一个、画一个，就会出现
##       「看着是崖却能走上去」或者「看着是平地却被挡住」—— 这种不一致最伤体感。
static func can_step(from_pos: Vector2, to_pos: Vector2) -> bool:
	var a := cell_of(from_pos)
	var b := cell_of(to_pos)
	if b == a:
		return true                       # 同一格内自由移动
	if not in_map(b):
		return true                       # 世界外归 _clamp_world 管，别在这儿判成崖
	if cell_depth(b.x, b.y) > 0.5:
		return false                      # 深水：挡住，得绕行
	# ⭐ M30.13e（用户定案）：「怎么墙给我挡住了，不要墙」
	#    → **高差不挡路**：多高的台地都能直接走上去。高度只保留**视觉**（台地偏移 + 遮挡），
	#      不再当墙用。深水仍然挡（那是水，不是墙）。
	return true


## 地形速度倍率：**只有涉水变慢**，平地 / 高地一律正常。
##
## ⭐⭐ M31.4（用户拍板）：**高地减速 `elev >= 0.60 → ×0.85` 已删除**。
##    它原来长这样（删掉的那两行）：
##        if elev_at_pos(pos) >= 0.60:
##            return 0.85
##    删除理由（用户原话 + 柯桥良 grep 核实后的依据）：
##      ① **地图做成平面之后，玩家踩上去会莫名变慢，而画面上没有任何提示。**
##         减速是一种惩罚，惩罚必须**看得见**——水是画得出来的（有贴图、有颜色），
##         所以涉水减速玩家能自己归因；高地在这张图上是看不见的，变慢就是"玄学掉帧"。
##      ② 它覆盖 **约 38.6% 的格子**（M31.3 重烘焙时的实测：阈值 0.60 = 12/20，
##         13/20 给 28.5%，12/20 给 38.2%）—— 超过三分之一的地图在偷偷减速，
##         玩家对"基础移动速度"的直觉会被整体拉低且无法校准。
##    ⚠️ 阈值曾经是 0.62，M31.3 重烘焙时改成 0.60 —— 因为阈值必须**正好落在
##       量化网格的某一级上**（k/20），否则减速带的边界会切在台面中间。
##       （这条纪律本身没错，只是整条规则现在被删了，留着给将来要加回来的人看。）
##
## ⚠️ 删完之后只剩一条：`depth > 0 → ×0.60`。
##    已知唯一的调用方假设：`Game.gd` 有一条断言用 `speed_mult_at(深水点) < 1.0`
##    来验「深水确实减速」—— 它读的是涉水那一条，**不受本次删除影响**。
##    另一个调用方 `Player.gd:298`（`mult *= speed_mult_at(position)`）只是相乘，
##    乘 1.0 与乘 0.85 都合法，不存在"必须 < 1"的隐含契约。
static func speed_mult_at(pos: Vector2) -> float:
	if depth_at_pos(pos) > 0.0:
		return 0.60
	return 1.0


## ⭐⭐ M31.1（P0 收尾）：**环状地形那套已经删除**。
##    曾经有三套地形名并存：`zone_at`(四象限 草原/岩区…) / `terrain_at`(环状 灵田/石山/雷泽…)
##    / `cell_terrain`(格子 世界数据 R 通道) —— 三套名字互相不认，读错就出鬼。
##    现在：**`cell_terrain()` 是唯一的地形真相**；环状那套（含 `terrain_at`/`TERRAIN_CELL`）已删。
##    `zone_at` 保留但语义降级为「玩家在哪个象限」，只用于内容标注与历史断言。

## 地形名 → **兜底颜色**。只给 `Game._draw_world_flat()` 用（世界数据缺失时的保险），
## 正常渲染走 128px 地块贴图，不看这张表。
const WORLD_TERRAIN_COLORS := {
	"水泽": Color(0.10, 0.16, 0.24),
	"草地": Color(0.11, 0.14, 0.11),
	"竹林": Color(0.08, 0.12, 0.09),
	"灵岩": Color(0.14, 0.13, 0.12),
	"灵田": Color(0.16, 0.17, 0.11),
	## 泥沼：autotile 还没画，缺图时**这就是玩家看到的东西**。
	## ⚠️ 必须和「水泽」一眼分得开 —— 水泽偏蓝（B 最高），泥沼偏黄褐（R>G>B，B 最低）。
	"泥沼": Color(0.22, 0.19, 0.09),
}


# ============ M31.4：同心层（全图界面的四色环带 + 内容点的层归属）============
## ⭐⭐ 同心层取代了原来的「四象限」：`ZONES` 只给敌人/采集点打标签，而同心层同时管
##    **全图界面的四条环带** 与 **每个内容点的层归属**。层号 1..4，**1 = 最里面（主城所在）**。
##
## ⚠️⚠️ **判据用 ρ（矩形归一化距离），不用欧氏距离** —— 这是硬要求，别改：
##    ```
##    ρ = max(|x − cx| / cx, |y − cy| / cy)          # cx,cy = 世界中心；ρ ∈ [0,1]
##    L1: ρ ≤ 0.52   L2: 0.52 < ρ ≤ 0.71   L3: 0.71 < ρ ≤ 0.86   L4: ρ > 0.86
##    ```
##    为什么：地图是 3584×3072 的**长方形**，按圆形半径硬切会让**四个角落在所有环之外**，
##    等于凭空长出「第五层」（角上永远是最外层的"更外层"）。ρ 的等值线是与地图边界
##    **相似的长方形** ⇒ 沿任何方向走到边界都意味着到了最外层，梯度在所有方向上一致。
##
## ⚠️⚠️ **层名是「地界名」，不是地形描述**（用户知情后拍板，不是遗漏）：
##    地图是噪声随机生成的，实测 `worldmap.png` 里 **L4 只有 1.5%（47/3135 格）是泥沼**，
##    **42% 是灵岩**；灵岩在四层里均匀占 32%~42%（各层都是它最多）。
##    ⇒ 层的视觉存在感来自**全图界面的四色环带**，不来自脚下地形。
##    ⇒ **别试图"修正"地形去匹配层名，也别因为"这层没有泥沼"就去改层名。**
const CONCENTRIC_THRESHOLDS := [0.52, 0.71, 0.86]
## ⭐ 下标 = 层号（0 号位留空，这样 `RING_NAMES[ring_at(pos)]` 直接能用）
const RING_NAMES := ["", "苍茫草海", "疏林", "碎石坡", "泥沼"]


## 归一化矩形距离 ρ ∈ [0,1]（0 = 世界正中，1 = 地图边界）
static func ring_rho(pos: Vector2) -> float:
	var h: Vector2 = WORLD["size"] * 0.5
	return maxf(absf(pos.x - h.x) / h.x, absf(pos.y - h.y) / h.y)


## 某个世界坐标属于哪一层（1..4）。判据见上：`CONCENTRIC_THRESHOLDS`。
static func ring_at(pos: Vector2) -> int:
	var r := ring_rho(pos)
	for i in range(CONCENTRIC_THRESHOLDS.size()):
		if r <= float(CONCENTRIC_THRESHOLDS[i]):
			return i + 1
	return CONCENTRIC_THRESHOLDS.size() + 1


static func ring_name(pos: Vector2) -> String:
	return RING_NAMES[clampi(ring_at(pos), 0, RING_NAMES.size() - 1)]


## ⭐ M31.4：**深水判定的唯一口径** —— PNG 的 **B 通道 ≥ 128**。
##    `depth > 0.5` ⟺ `b/255 > 0.5` ⟺ `b > 127.5` ⟺ **整数域 `b >= 128`**。
##    ⚠️ 写成 `> 128` 会把全图 **46 格真深水（B 恰好 = 128，depth = 0.50196）误判成可走**
##       （实测：46 = 城外 39 + 城中 7）。投点池里混进这 46 格 ⇒ 症状是「采集点刷在湖心」，
##       和早先 e08 辉光印落在深水里是**同一个故障模式**。
##    ⚠️ 全工程只允许这一处定义，别在别处重写一遍（口径散落两处 = 迟早对不上）。
static func is_deep_cell(cx: int, cy: int) -> bool:
	return int(round(cell_depth(cx, cy) * 255.0)) >= 128


static func is_deep_at(pos: Vector2) -> bool:
	var c := cell_of(pos)
	return in_map(c) and is_deep_cell(c.x, c.y)


## 主城平台（出生点所在的 32×32 格方台）。⚠️ `range(cc-16, cc+16)` 是**右开**区间，
## 所以是 32 格不是 33 格 —— 见 `_check_world_terrain()` 里的「出生点平坝」注释。
static func city_rect() -> Rect2:
	var h: Vector2 = WORLD["size"] * 0.5
	return Rect2(h.x - 16.0 * WORLD_CELL, h.y - 16.0 * WORLD_CELL,
			32.0 * WORLD_CELL, 32.0 * WORLD_CELL)


## ⭐ 四层「可站立格池」（投点的候选集）：非深水 + 主城平台之外。
##    ⚠️ 取样一律用**格心**（`c*CELL + CELL/2`）：判定层归属时取样点不统一，分层数就会漂
##       （实测：格左上角 vs 格心，L1 能差 10 格、L4 能差 168 格）。
##    ⚠️ 实测值 = **[1701, 2229, 2144, 2668]，合计 8742**（M31.4 柯桥良实测，与技架一致）。
static func ring_pool() -> Array:
	var out := [0, 0, 0, 0]
	var cr := city_rect()
	for cy in range(WORLD_ROWS):
		for cx in range(WORLD_COLS):
			if is_deep_cell(cx, cy):
				continue
			var p := Vector2(float(cx) * WORLD_CELL + WORLD_CELL * 0.5,
					float(cy) * WORLD_CELL + WORLD_CELL * 0.5)
			if cr.has_point(p):
				continue
			out[ring_at(p) - 1] += 1
	return out


## ⭐ M31 Step 0：四个区的矩形**从世界尺寸算**，不再写死。
##    ⚠️ 以前写死 2560×1440（= 旧世界 5120×2880 的一半）—— 世界一改尺寸，
##    「四个分区正好铺满世界」和「每区 2 处采集点」两条断言立刻假失败。
##    现在世界改多大，分区就跟着铺多大（**分区只是标签**：渲染与产出都不看它）。
static var ZONES: Dictionary = _build_zones()

static func _build_zones() -> Dictionary:
	var h: Vector2 = WORLD["size"] * 0.5          # 切分点 = 世界正中（四象限）
	return {
		"草原": {"rect": Rect2(0.0, 0.0, h.x, h.y), "color": Color(0.11, 0.14, 0.11),
			"visual": {"texture": "res://art/tiles/grass.png"}},
		"岩区": {"rect": Rect2(h.x, 0.0, h.x, h.y), "color": Color(0.14, 0.13, 0.12),
			"visual": {"texture": "res://art/tiles/rock.png"}},
		"雷区": {"rect": Rect2(0.0, h.y, h.x, h.y), "color": Color(0.10, 0.10, 0.16),
			"visual": {"texture": "res://art/tiles/thunder.png"}},
		"热区": {"rect": Rect2(h.x, h.y, h.x, h.y), "color": Color(0.16, 0.10, 0.09),
			"visual": {"texture": "res://art/tiles/heat.png"}},
	}

## 某个世界坐标落在哪个区。采集产出与敌人配置都靠它，避免在数据里重复写区名。
static func zone_at(pos: Vector2) -> String:
	for key in ZONES:
		if (ZONES[key]["rect"] as Rect2).has_point(pos):
			return key
	return ""


# ============ M31.4：世界内容点（单一数据源）============
## ⭐⭐ `WORLD_SITES` = **世界内容点的唯一出处**。
##    地图界面（按 M 看全图）与将来的世界实体**都从这一份数据读** ——
##    **禁止任何地方再复制一份坐标**。为什么这么硬：坐标一旦抄成两份，
##    「地图上还亮着、世界里已经打死了」这种**地图说谎**就是迟早的事，而且没人会发现。
##
## 字段：`id` / `type` / `ring` / `pos` / `label` / `payload`
##    - `ring` 是**声明值**，必须与 `ring_at(pos)` 一致（有断言守）。
##    - `payload` 按 type 不同而不同（秘境带 seal+rank、灵潮带 respawn_sec…）。
##
## ⚠️ 本轮（M31.4 Step 1）只落**数据层**：世界里的实体挂载（能走进秘境/妖巢）下一步做。
##    ⇒ 只有「印源」与「传承印出处」同时出现在 `ENEMY_SPAWNS` 里（它们是**带印敌人**）；
##      秘境 / 妖巢 / 灵潮 / 灵材 / 灵市 目前**只是地图标记，不刷实体**。
##
## ⭐⚠️ **9 枚印还缺名字**（这是本轮没闭合的一笔账，已回报 team-lead）：
##    印的总账 = 灰烬（本命，开局自带）+ 秘境 6（含玄甲）+ 传承强夺 5 + 印源 4 = **16 枚**。
##    其中 `SEALS` 里**已有** 7 枚：灰烬 / 玄甲 / 惊雷 / 磐石 / 云雨 / 流风 / 辉光。
##    ⇒ 秘境 M02~M06（5 枚）+ 印源 Y01~Y04（4 枚）共 **9 枚尚未命名/定数值** ——
##      这是**设计侧**的活（命名 + 印诀 + 数值），不是数据录入，我不擅自编 9 套数值。
##      `payload.seal` 暂留空串，断言只数**出点**（16），不要求每枚都有实体定义；
##      一旦命名落地，填进 `SEALS` 并把这里补上即可（`_check_seal_refs()` 会立刻开始守引用）。
const WORLD_SITES := [
	# ---- 秘境 6（产秘境印；M01 出玄甲印 ---- 教学印，不走梯度）----
	{"id": "M01", "type": "秘境", "ring": 1, "pos": Vector2(2640.0, 912.0), "label": "苍茫草海·秘境",
		"payload": {"seal": "玄甲印", "rank": 2, "waves": 2}},
	{"id": "M02", "type": "秘境", "ring": 2, "pos": Vector2(2960.0, 1456.0), "label": "疏林·秘境",
		"payload": {"seal": "", "rank": 3, "waves": 3}},
	{"id": "M03", "type": "秘境", "ring": 2, "pos": Vector2(1168.0, 2608.0), "label": "疏林·秘境",
		"payload": {"seal": "", "rank": 3, "waves": 3}},
	{"id": "M04", "type": "秘境", "ring": 3, "pos": Vector2(3280.0, 2448.0), "label": "碎石坡·秘境",
		"payload": {"seal": "", "rank": 4, "waves": 3}},
	{"id": "M05", "type": "秘境", "ring": 3, "pos": Vector2(1456.0, 240.0), "label": "碎石坡·秘境",
		"payload": {"seal": "", "rank": 4, "waves": 3}},
	{"id": "M06", "type": "秘境", "ring": 4, "pos": Vector2(112.0, 2864.0), "label": "泥沼·秘境",
		"payload": {"seal": "", "rank": 5, "waves": 4}},
	# ---- 妖巢 6 ----
	{"id": "N01", "type": "妖巢", "ring": 1, "pos": Vector2(912.0, 1808.0), "label": "苍茫草海·妖巢",
		"payload": {"waves": 2}},
	{"id": "N02", "type": "妖巢", "ring": 2, "pos": Vector2(1808.0, 2608.0), "label": "疏林·妖巢",
		"payload": {"waves": 2}},
	{"id": "N03", "type": "妖巢", "ring": 3, "pos": Vector2(2800.0, 2832.0), "label": "碎石坡·妖巢",
		"payload": {"waves": 3}},
	 ## ⚠️ N04 原坐标 (2192,2864)：实测 ρ=0.8646 属 **L4**（表里标 L3，对不上），
	 ##    且离 L3/L4 边界只有 **7 世界像素** —— 就算改标 L4，标记也会被地图界纹线压住。
	 ##    ⇒ 往北挪到 y=2800（ρ=0.8229，L3，离边界 57px）。
	{"id": "N04", "type": "妖巢", "ring": 3, "pos": Vector2(2192.0, 2800.0), "label": "碎石坡·妖巢",
		"payload": {"waves": 3}},
	{"id": "N05", "type": "妖巢", "ring": 4, "pos": Vector2(144.0, 848.0), "label": "泥沼·妖巢",
		"payload": {"waves": 3}},
	{"id": "N06", "type": "妖巢", "ring": 4, "pos": Vector2(3472.0, 2896.0), "label": "泥沼·妖巢",
		"payload": {"waves": 4}},
	# ---- 灵潮 4（限时刷新）----
	{"id": "T01", "type": "灵潮", "ring": 1, "pos": Vector2(2544.0, 1712.0), "label": "苍茫草海·灵潮",
		"payload": {"respawn_sec": 300.0}},
	{"id": "T02", "type": "灵潮", "ring": 2, "pos": Vector2(2928.0, 2000.0), "label": "疏林·灵潮",
		"payload": {"respawn_sec": 300.0}},
	{"id": "T03", "type": "灵潮", "ring": 3, "pos": Vector2(432.0, 1488.0), "label": "碎石坡·灵潮",
		"payload": {"respawn_sec": 300.0}},
	{"id": "T04", "type": "灵潮", "ring": 4, "pos": Vector2(1936.0, 176.0), "label": "泥沼·灵潮",
		"payload": {"respawn_sec": 300.0}},
	# ---- 灵材富集 6 ----
	{"id": "R01", "type": "灵材富集", "ring": 2, "pos": Vector2(560.0, 656.0), "label": "疏林·灵材富集",
		"payload": {"items": ["赤炎花"]}},
	{"id": "R02", "type": "灵材富集", "ring": 3, "pos": Vector2(3248.0, 592.0), "label": "碎石坡·灵材富集",
		"payload": {"items": ["雷纹石"]}},
	{"id": "R03", "type": "灵材富集", "ring": 3, "pos": Vector2(720.0, 2704.0), "label": "碎石坡·灵材富集",
		"payload": {"items": ["雷纹石"]}},
	{"id": "R04", "type": "灵材富集", "ring": 4, "pos": Vector2(3440.0, 1232.0), "label": "泥沼·灵材富集",
		"payload": {"items": ["玄霜髓"]}},
	{"id": "R05", "type": "灵材富集", "ring": 4, "pos": Vector2(144.0, 2000.0), "label": "泥沼·灵材富集",
		"payload": {"items": ["太虚核"]}},
	{"id": "R06", "type": "灵材富集", "ring": 4, "pos": Vector2(1424.0, 2960.0), "label": "泥沼·灵材富集",
		"payload": {"items": ["灵魄"]}},
	# ---- 灵市 4（商店驻点；不卖印，只清货/补给）----
	{"id": "P01", "type": "灵市", "ring": 2, "pos": Vector2(2288.0, 2384.0), "label": "疏林·灵市",
		"payload": {"services": ["essence"]}},
	{"id": "P02", "type": "灵市", "ring": 3, "pos": Vector2(2288.0, 432.0), "label": "碎石坡·灵市",
		"payload": {"services": ["essence"]}},
	{"id": "P03", "type": "灵市", "ring": 4, "pos": Vector2(3376.0, 1744.0), "label": "泥沼·灵市",
		"payload": {"services": ["essence"]}},
	{"id": "P04", "type": "灵市", "ring": 4, "pos": Vector2(816.0, 176.0), "label": "泥沼·灵市",
		"payload": {"services": ["essence"]}},
	# ---- 印源 4（带印敌人，打死可强夺）---- ⚠️ seal 待命名，见 WORLD_SITES 头注释
	{"id": "Y01", "type": "印源", "ring": 2, "pos": Vector2(560.0, 2160.0), "label": "疏林·印源",
		"payload": {"seal": "", "rank": 2}},
	{"id": "Y02", "type": "印源", "ring": 3, "pos": Vector2(2704.0, 272.0), "label": "碎石坡·印源",
		"payload": {"seal": "", "rank": 3}},
	{"id": "Y03", "type": "印源", "ring": 4, "pos": Vector2(176.0, 2448.0), "label": "泥沼·印源",
		"payload": {"seal": "", "rank": 4}},
	{"id": "Y04", "type": "印源", "ring": 4, "pos": Vector2(3472.0, 176.0), "label": "泥沼·印源",
		"payload": {"seal": "", "rank": 4}},
]

## ⭐ 印的**唯一出处总账**（16 枚）：灰烬（本命）+ 秘境 6（含玄甲）+ 传承强夺 5 + 印源 4。
##    ⚠️ 这 5 条「传承印出处」同时是 `ENEMY_SPAWNS` 里的 e07/e08/e09/e12/e13（带 `carries`）。
const SEAL_SOURCE_LEGACY := ["流风印", "辉光印", "云雨印", "惊雷印", "磐石印"]


# ---------------- 物品（M8）----------------
## 材料表。⭐ 设计圣经 §3.6：材料按**来源**分类，不按颜色分类 ——
## 每一类都对应一条灵印线，所以合炼配方是**可推理的**，玩家能自己摸索。
## `volume` = **占背包多少容积**（M30.4）：草木 1 / 兽材 2 / 矿石 3 / 触媒 3。
## 为什么按类别给而不是「越贵越大」：让「值钱但占地方」和「便宜但好带」同时存在，
## 出门带什么才是个选择（矿石/触媒沉，草木轻）。
## price 是 M14 商人用它买卖的价格（灵石）。
## ⚠️ M30.3：`refine`（药力）**现在没有任何地方在用** —— 炼化已改成只吃灵力（不再投材料）。
##    数字先留着（以后「材料影响合炼成功率」之类可以直接用），但**别以为它还有效果**。
const MATERIALS := {
	# ⭐ M30.2：`use` = **可以直接使用**的效果（背包面板里点「使用」）。没有这一项 = 只能当投料。
	"蕴灵草": {"kind": "草木", "color": Color(0.45, 0.78, 0.42), "price": 4, "volume": 1, "refine": 2,
		"use": {"essence": 25.0}},    # 和「采一口」一样回 25 灵力
	"赤炎花": {"kind": "草木", "color": Color(0.88, 0.42, 0.30), "price": 9, "volume": 1, "refine": 4},
	"玄铁矿": {"kind": "矿石", "color": Color(0.55, 0.58, 0.66), "price": 12, "volume": 3, "refine": 5},
	"雷纹石": {"kind": "矿石", "color": Color(0.62, 0.55, 0.92), "price": 16, "volume": 3, "refine": 7},
	"兽骨":   {"kind": "兽材", "color": Color(0.82, 0.78, 0.66), "price": 6, "volume": 2, "refine": 3},
	"灵魄":   {"kind": "兽材", "color": Color(0.70, 0.86, 0.92), "price": 22, "volume": 2, "refine": 9},
	"地火芯": {"kind": "触媒", "color": Color(0.95, 0.55, 0.25), "price": 40, "volume": 3, "refine": 15},
	"雷髓":   {"kind": "触媒", "color": Color(0.72, 0.68, 1.00), "price": 45, "volume": 3, "refine": 18},
	## ⭐⭐ M31.4 新增两种**顶层触媒**（用户拍板：给灵石一个"贵得有理由"的出口）。
	##    为什么需要它们：原来最贵的材料是雷髓 45 —— 商人货架最贵那件也就 60。
	##    于是"攒一大笔灵石"在中期之后**没有对应物可买**，灵石出口只剩买灵力（10/25 点）。
	##    60 / 70 这两档把**顶层合炼**变成一笔要攒一阵子的钱，出口才有纵深。
	## ⚠️ 定位：**只在外圈产出**（L4 的采集点 g23 / g24 各一处，全图仅此两份），
	##    与"越往外越值钱"的同心层梯度一致 —— 别塞进商人货架，否则梯度当场塌掉。
	##    （商人货架的意义是"救急"，不是"毕业装备商店"。）
	"玄霜髓": {"kind": "触媒", "color": Color(0.62, 0.86, 0.95), "price": 60, "volume": 3, "refine": 24},
	"太虚核": {"kind": "触媒", "color": Color(0.90, 0.80, 0.45), "price": 70, "volume": 3, "refine": 30},

	# ---- 以下按《数值设计》v2 §5 / §6 / §7 新增（苍梧山怪物带来的材料线）----
	## ⭐ 一般材料：每一样都有**写死的出处**（ENEMY[*].drops），不做随机掉率 ——
	##    和原来那条「固定数量、不做概率」的纪律同一条。
	##    ⇒ 「我缺蛇胆 → 去打竹叶青」是玩家能自己推出来的信息，而不是抽奖。
	"蛇胆":     {"kind": "兽材", "color": Color(0.42, 0.66, 0.36), "price": 8, "volume": 2, "refine": 4},
	"灵木":     {"kind": "草木", "color": Color(0.58, 0.50, 0.34), "price": 7, "volume": 1, "refine": 4},
	"幽魂精髓": {"kind": "触媒", "color": Color(0.55, 0.62, 0.72), "price": 35, "volume": 3, "refine": 12},
	## ⭐ 稀有触媒（§3.3.1 / §5）：融合变异的**唯一钥匙** —— 基础 5%，属性契合 15%。
	##    ⚠️ 它们是「门」不是「数值」：本身不提供任何战力，只把那条 5% 的缝推开。
	##    所以价格定在 130~160 这一档（比地火芯 40 / 雷髓 45 贵三倍）—— 一次变异值得攒一阵子。
	"百年蛇胆":   {"kind": "触媒", "color": Color(0.28, 0.52, 0.30), "price": 140, "volume": 3, "refine": 20},
	"天雷木":     {"kind": "触媒", "color": Color(0.66, 0.50, 0.90), "price": 150, "volume": 3, "refine": 22},
	"百年竹心草": {"kind": "触媒", "color": Color(0.38, 0.78, 0.45), "price": 130, "volume": 3, "refine": 20},
	"灵狐内丹":   {"kind": "触媒", "color": Color(0.95, 0.66, 0.30), "price": 160, "volume": 3, "refine": 24},
	## ⭐ 残片（§5 掉落阶梯）：**跨怪种收集**，所以它不属于任何一只怪 —— 谁都会掉，
	##    攒够 10 片就能凝成一枚完整的印。这是「打了很多怪但一直没掉印」的保底。
	"凡印残片": {"kind": "残片", "color": Color(0.68, 0.68, 0.70), "price": 12, "volume": 1, "refine": 1},
	"精印残片": {"kind": "残片", "color": Color(0.55, 0.66, 0.88), "price": 30, "volume": 1, "refine": 2},
	"通印残片": {"kind": "残片", "color": Color(0.75, 0.58, 0.90), "price": 70, "volume": 1, "refine": 3},
}

## ⭐ M31.4：**材料表条目齐全**（守语义，不守个数）。
##    为什么要有它：`Game.gd` 里那条 `_check("材料表有 8 种", MATERIALS.size() == 8)` 是
##    **写死旧数字** —— 加一种材料它就红，逼人回来改一个没有任何意义的常数；
##    更糟的是它会让人以为「改个数就好了」，于是漏掉真正该守的东西（字段齐全）。
##    ⇒ 改成 `MATERIALS.size() >= 8 and GameData.materials_well_formed()`：
##      「只许增不许减」+「每种都有 kind / price / volume / color」。
## ⚠️ `price` / `volume` 必须**是数字且 > 0**：price=0 会让商人白送，volume=0 会让背包无限装。
static func materials_well_formed() -> bool:
	for k in MATERIALS.keys():
		var m: Dictionary = MATERIALS[k]
		if not (m.has("kind") and m.has("price") and m.has("volume") and m.has("color")):
			return false
		if float(m["price"]) <= 0.0 or int(m["volume"]) <= 0:
			return false
		if not KIND_VOLUME.has(str(m["kind"])):
			return false
	return true

## 材料类别 → 单件容积。⚠️ 与 `volume` 字段**对不上就是 bug**（类别决定手感，字段决定算数），
## 所以 `materials_well_formed()` 顺手查这张表 —— 加新材料时如果写错类别会被抓到。
## ⭐ 类别同时决定**手感**：草木轻（1）/ 兽材中（2）/ 矿石与触媒沉（3），
##    于是「值钱但占地方」与「便宜但好带」同时存在，出门带什么才是个选择。
const KIND_VOLUME := {"草木": 1, "兽材": 2, "矿石": 3, "触媒": 3, "残片": 1}

## ⭐ 凝结表（§5）：**10 片残片 + 灵力 → 一枚完整的印**。
##    为什么要有它：残片是「打了很久但一枚印都没掉」的保底进度条 ——
##    没有它，掉落全靠运气；有了它，每一只杂怪都在往同一个目标上加一格。
## ⚠️ `shard` 是能凝出的**印名**（不是品阶）：1 等残片只能凝出凡印。
##    表里写印名而不是写 rank，是因为「哪枚印」将来可能要按流派分，而 rank 分不出来。
const SHARDS := {
	"凡印残片": {"rank": 1, "count": 10, "essence": 30.0, "shard": "落叶印"},
	"精印残片": {"rank": 2, "count": 10, "essence": 60.0, "shard": "碎石印"},
	"通印残片": {"rank": 3, "count": 10, "essence": 90.0, "shard": "熔岩印"},
}


## 残片表的体检（和 `materials_well_formed()` 同一条思路：守语义，不守个数）。
## ⚠️ 三条硬要求：① 残片本身在材料表里 ② 目标印在灵印表里且品阶对得上 ③ 数字都是正的。
static func shards_well_formed() -> bool:
	for k in SHARDS.keys():
		var s: Dictionary = SHARDS[k]
		if not MATERIALS.has(k):
			return false
		if not (s.has("rank") and s.has("count") and s.has("essence") and s.has("shard")):
			return false
		if int(s["count"]) <= 0 or float(s["essence"]) < 0.0:
			return false
		var target := str(s["shard"])
		if not SEALS.has(target):
			return false
		if int(SEALS[target]["rank"]) != int(s["rank"]):
			return false
	return true

## 商人（M14）。⭐ 待决问题 10 的落地：**一个**商人、放在世界中心锚点旁（安全区）、
## **货架一次性、不补货** —— 想买东西就得先出门把灵石赚回来。
## 买卖价差就是他的利润：买价写在货架上，卖价 = MATERIALS[*].price × sell_ratio。
const MERCHANT := {
	"pos": Vector2(1792.0, 1262.9),       # ⭐ 真坐标：出生点 (1792,1536) 正上方 273px —— 安全区内
	"radius": 19.0,
	"reach": 46.0,                      # 站多近能交易
	"color": Color(0.86, 0.78, 0.52),
	"sell_ratio": 0.5,                  # 卖给商人只能拿回半价
	"stock": [
		{"item": "蕴灵草", "count": 5, "price": 6},
		{"item": "兽骨",   "count": 5, "price": 9},
		{"item": "玄铁矿", "count": 3, "price": 17},
		{"item": "地火芯", "count": 1, "price": 55},
		{"item": "雷髓",   "count": 1, "price": 60},
	],
	## ⭐ 服务：不限量、不占货架。这是灵石**永不枯竭的出口** ——
	##    货架会卖光，服务不会。也是灵力的第二个来源（第一个是采集）。
	##    取舍就在这里：同一笔灵石，买材料（合炼）还是买灵力（修炼）？
	"services": [
		{"id": "essence", "label": "灵力", "amount": 25.0, "price": 10},
	],
}

## 货币只有一种（开发计划 §7.1）。灵石不占背包容量。
const CURRENCY := "灵石"

## 背包容量 = **容积**（M30.4 用户定案：「物品应该加一个重量或者占据的容积，放入背包里会占据不同的体积」）。
## ⚠️ 单位从「件」变成了「容积」：每件东西占多少见 `MATERIALS[*].volume`。
##    于是「带什么出门」第一次成为一个真选择：草木 1 格、矿石 3 格。
## ⭐ **灵石不占容积**（货币）；**灵印也不占容积**（见 volume_of：不在材料表里的东西一律 0）。
## ⚠️ 数值 120 的理由：改成容积后旧存档的占用会变大（原来 1 件 = 1，现在 1~3），
##    120 能让「满包的矿石」这种旧档也不至于一进来就爆仓 —— 而且爆仓不丢东西，只是捡不动。
const BAG_CAPACITY := 120

## 掉落物：走过去自动捡。⭐ 不必按 E —— E 的含义是「交互（采集）」，不许一键两义。
## ⭐ M30.1：**同类就近并成一堆**（`merge_radius`）—— 同一件东西落在这个距离内就并进已有的那一堆，
##    数量相加，**东西一件不少**。为什么需要它：背包满时掉落物不会被捡走，而死亡会复活敌人，
##    同一个刷新点被反复打 → 那一带就堆出几十个小方块（又乱，又是每帧都要重绘的活节点）。
##    ⚠️ 只合并**材料与货币**；灵印永远单独一堆（它是唯一的，地上也要一眼看得出那是一枚印）。
const PICKUP := {
	"radius": 15.0,          # 主角走到多近就自动捡起
	"size": 7.0,
	"merge_radius": 40.0,    # 同类就近并堆的距离（世界像素；屏幕上 ×2 = 80px）
}

## 掉落表：按敌人原型。⭐ 固定数量，不做随机掉率 ——
## 随机掉率会让自测变成概率游戏，等有调参台了再上权重。
##
## ⚠️⚠️ M35（数值设计 v2 §0 第二条锚点）：**普通怪不掉灵石**。
##    旧表里 猛兽 3 / 智谋 5 / 灵师 8 / 蛮兽 6 全被删掉了 —— 那让「灵石」贬值成了
##    打杂怪就能刷的日用品，而设计里它是**硬通货**，来源只有精英 5~8、首领 20~30（§7）。
##    ⇒ 现在灵石只从两处来：① `ENEMY[*].stone`（自成一档的精英）
##                          ② `ELITE.stone`（同一原型被加档的精英）
##    这条有断言盯着（见 Game.gd 的自测「普通怪不掉灵石」那一条）——
##    谁再往杂怪表里塞灵石，自测会红。
const ENEMY_DROPS := {
	"猛兽": {"兽骨": 2},
	"智谋": {"兽骨": 1, "灵魄": 1},
	"灵师": {"灵魄": 2},        # 它身上那枚印另外掉（走 carries）
	"蛮兽": {"兽骨": 2, "灵魄": 1},
	## ---- 苍梧山 ----
	"铁齿竹鼠": {"兽骨": 2},
	"鬼影竹叶青": {"蛇胆": 1},
	"青木竹妖": {"灵木": 2},
	"碧眼灵狐": {"灵魄": 2},     # + 灵石 5（在 ENEMY 表的 stone 字段里）
	"变异矿鬼": {"幽魂精髓": 1},  # + 灵石 6
	# ⭐ 精英的掉落 = 原型掉落 × drop_mult，再额外给一份 bonus_drop + 灵石（见 Game._drop_loot）
}


## 采集点（蕴灵）：走过去按 E 采一口，回灵力，然后这个点就空了。
## ⭐ 它的「空没空」是**锚点快照**的一部分 —— 死亡回锚点时一起复原（待决问题 8）。
const GATHER := {
	"radius": 13.0,           # 采集点自己的大小（绘制用）
	"reach": 29.0,            # 主角要多近才能采
	"essence": 25.0,          # 采一次回多少灵力
	"color_full": Color(0.55, 0.85, 0.95),
	"color_empty": Color(0.26, 0.30, 0.34),
	## ⭐ 两态两张图：满的是一颗灵珠，空的是它的残壳。外面那圈光晕仍由代码画（那是状态）。
	"visual": {"texture": "res://art/world/gather_full.png",
		"empty_texture": "res://art/world/gather_empty.png"},
	## ⭐ 一处采集点 = 位置 + 产出 + 数量 + 层号，写在同一个 dict 里。
	##    （不做「positions 与 yields 两个数组顺序必须对齐」那种平行表 —— 一旦错位没人发现。）
	## ⭐ M31 Step 0：`id`（g01…g24）= 稳定标识，用途同 ENEMY_SPAWNS 的 id。
	##
	## ⭐⭐ M31.4：**整表作废重建**（旧的 8 个点是「四象限每区 2 处」时代的产物）。
	##    新规则（用户拍板）：**每层 6 个，共 24 个；采集时可能被怪扑。**
	##    - 为什么按层而不是按象限：全图界面（按 M）显示的是**同心环带**，
	##      「每层有几个点」是玩家能直接读出来的信息；四象限只是历史标签。
	##    - **「可能被扑」是设计，不是缺陷**：每个点 240px 内都埋了杂怪 spawn
	##      （240 = 最大 aggro 170 + 70 位移余量）。采一口要冒被扑的风险，
	##      这是「去哪采」的第一层风险回报；旧表那 8 个点周围全是空地，采得太安稳。
	##      ⇒ 这条有断言盯着：`tests/world_data_test.gd` 第 4 段。
	##
	## 产出梯度（跟着层走，越往外越值钱）：
	##    L1 蕴灵草（草木，4/件） / L2 玄铁矿（矿石，12/件） /
	##    L3 雷纹石（矿石，16/件） / L4 触媒（地火芯 40 / 雷髓 45 / 玄霜髓 60 / 太虚核 70）
	## ⭐ 顶层触媒 玄霜髓 / 太虚核 **全图各只有一份**（g23 / g24），且都在 L4 最外圈。
	##
	## ⚠️ 每个点的 `ring` 是**实测**（用 `ring_at()` 算的），不是抄的；
	##    所有点都已核实：非深水（B < 128）、地形非「水泽」、不在主城矩形内。
	##    ⚠️ 唯一贴边的一点：g05 / m53 在 y=2064，主城矩形南边界是 2048 —— 只差 16px。
	"spots": [
		# ---- L1 苍茫草海（6）----
		{"id": "g01", "pos": Vector2(1168.0, 944.0),  "item": "蕴灵草", "amount": 2, "ring": 1},
		{"id": "g02", "pos": Vector2(1456.0, 976.0),  "item": "蕴灵草", "amount": 2, "ring": 1},
		{"id": "g03", "pos": Vector2(2352.0, 976.0),  "item": "蕴灵草", "amount": 2, "ring": 1},
		{"id": "g04", "pos": Vector2(2704.0, 1968.0), "item": "蕴灵草", "amount": 2, "ring": 1},
		{"id": "g05", "pos": Vector2(1424.0, 2064.0), "item": "蕴灵草", "amount": 2, "ring": 1},
		{"id": "g06", "pos": Vector2(2224.0, 2224.0), "item": "蕴灵草", "amount": 2, "ring": 1},
		# ---- L2 疏林（6）----
		{"id": "g07", "pos": Vector2(1232.0, 496.0),  "item": "玄铁矿", "amount": 2, "ring": 2},
		{"id": "g08", "pos": Vector2(2192.0, 592.0),  "item": "玄铁矿", "amount": 2, "ring": 2},
		{"id": "g09", "pos": Vector2(688.0, 880.0),   "item": "玄铁矿", "amount": 2, "ring": 2},
		{"id": "g10", "pos": Vector2(656.0, 1232.0),  "item": "玄铁矿", "amount": 2, "ring": 2},
		{"id": "g11", "pos": Vector2(752.0, 1776.0),  "item": "玄铁矿", "amount": 2, "ring": 2},
		{"id": "g12", "pos": Vector2(2608.0, 2608.0), "item": "玄铁矿", "amount": 2, "ring": 2},
		# ---- L3 碎石坡（6）----
		{"id": "g13", "pos": Vector2(784.0, 272.0),   "item": "雷纹石", "amount": 2, "ring": 3},
		{"id": "g14", "pos": Vector2(2832.0, 336.0),  "item": "雷纹石", "amount": 2, "ring": 3},
		{"id": "g15", "pos": Vector2(3184.0, 1232.0), "item": "雷纹石", "amount": 2, "ring": 3},
		{"id": "g16", "pos": Vector2(3216.0, 2064.0), "item": "雷纹石", "amount": 2, "ring": 3},
		{"id": "g17", "pos": Vector2(464.0, 2768.0),  "item": "雷纹石", "amount": 2, "ring": 3},
		{"id": "g18", "pos": Vector2(1360.0, 2800.0), "item": "雷纹石", "amount": 2, "ring": 3},
		# ---- L4 泥沼（6）：触媒带。⚠️ 层名是「地界名」不是地形描述，见同心层注释 ----
		{"id": "g19", "pos": Vector2(112.0, 112.0),   "item": "地火芯", "amount": 1, "ring": 4},
		{"id": "g20", "pos": Vector2(496.0, 112.0),   "item": "地火芯", "amount": 1, "ring": 4},
		{"id": "g21", "pos": Vector2(2096.0, 176.0),  "item": "雷髓",   "amount": 1, "ring": 4},
		{"id": "g22", "pos": Vector2(3408.0, 816.0),  "item": "雷髓",   "amount": 1, "ring": 4},
		{"id": "g23", "pos": Vector2(112.0, 1136.0),  "item": "玄霜髓", "amount": 1, "ring": 4},
		{"id": "g24", "pos": Vector2(3376.0, 1776.0), "item": "太虚核", "amount": 1, "ring": 4},
	],
}

# ---------------- 合炼（M13）----------------
## 炉子参数。设计圣经 §3.3：**火候指针在绿区时点击**，失误则失败。
## ⭐ 指针速度刻意做成「一轮约 1.5 秒」—— 太快变成拼手速，太慢变成走流程。
const FURNACE := {
	"pointer_speed": 1.30,      # 指针来回速度（越快越难）
	"green_zone": 0.22,        # 绿区宽度（占整条的比例）
	"essence_cost": 60.0,      # 开一次炉的灵力（设计圣经 §3.3「消耗：灵力」）
	"base_chance": 50.0,       # 成功率基数（%）
	"per_material": 5.0,       # 每多一种辅材 +5%
	"per_soul": 10.0,          # 每个灵魄 +10%
	"per_rank": 10.0,          # 目标每高一等 -10%
	"event_chance": 0.5,       # 合炼中出「填料 / 减料」事件的概率
	"event_bonus": 12.0,       # 答对 +12%
	"event_penalty": 10.0,     # 答错 -10%
}

## 升阶：每一等把**这枚印自己的底子**抬起来多少。
## ⭐ 十等只影响这三样 —— 不改被动、不改形态（形态是数据表里写死的性格，不该被等级洗掉）。
const RANK_GAIN := {
	"seal_hp": 0.25,            # 印的血量 +25% / 等
	"skill": 0.20,              # 招式伤害 +20% / 等
}

## 配方表。⭐ 一张表写全，加配方只加一行。
##   mode = "upgrade"：主材 + 辅材 → **改主材自己的等级**（§3.3 升阶）
##   mode = "craft"  ：a + b + 辅材 → **全新的一枚**（a、b 作材料被消耗，§3.3 合成）
## ⚠️「哪种搭配产出哪一枚」是**设计选择**，不是从设定推导出来的 —— 手感不对就改这张表。
## ⚠️ **本命印不能当材料**（它和魂魄相连）—— 见 Player.can_use_as_material()。
const RECIPES := [
	{"mode": "upgrade", "main": "灰烬印", "to_rank": 2, "materials": {"赤炎花": 2, "地火芯": 1}},
	{"mode": "upgrade", "main": "玄甲印", "to_rank": 2, "materials": {"玄铁矿": 3}},
	{"mode": "upgrade", "main": "惊雷印", "to_rank": 3, "materials": {"雷纹石": 3}},
	{"mode": "upgrade", "main": "磐石印", "to_rank": 2, "materials": {"兽骨": 3}},
	# 合成：守 + 雷 相激而生光
	{"mode": "craft", "a": "玄甲印", "b": "惊雷印", "result": "辉光印",
		"materials": {"雷纹石": 2, "灵魄": 1}},
	# 合成：双土相叠，否极泰来而生水
	{"mode": "craft", "a": "玄甲印", "b": "磐石印", "result": "云雨印",
		"materials": {"玄铁矿": 3}},
	# 合成：雷动石开而生风
	{"mode": "craft", "a": "惊雷印", "b": "磐石印", "result": "流风印",
		"materials": {"雷髓": 1, "兽骨": 2}},
]

# ---------------- 打击感 ----------------
## ⭐ 全部集中在这一张表：**手感不对就改这里，不碰逻辑**。
## 「命中停顿」= 打中的瞬间把时间压慢几十毫秒 —— 这是「打中了」最有效的信号，成本也最低。
const JUICE := {
	"hitstop_on": true,
	"hitstop_scale": 0.05,       # 停顿期间的时间倍率
	"hitstop_hit": 0.035,        # 打中敌人停多久（秒）
	"hitstop_hurt": 0.060,       # 自己挨打停多久 —— 更重一点
	"shake_hit": 1.1,            # 打中敌人的震屏幅度（像素）
	"shake_hurt": 2.5,           # 自己挨打
	"shake_decay": 26.0,         # 震屏衰减速度（越大越快停）
	"numbers": true,             # damage 数字
	"number_life": 0.7,          # 数字活多久
}

## 灵印十等（设计圣经 §二）。⭐ 等级就是**阶级** —— 只有这一套数字，
## 升级 = 升等，靠合炼（M13）产出，不是打怪涨经验。
const RANKS := {
	1: "凡印", 2: "精印", 3: "通印", 4: "宝印", 5: "圣印",
	6: "道印", 7: "劫印", 8: "奇印", 9: "元印", 10: "祖印",
}

## 炼化。⭐ 炼化度挂在**印**上（不是槽位上）：换槽位不该丢炼化。
## 涨法两条腿：用（显化一次涨一点）+ 喂（投材料，大头，按材料本身的「药力」）。
## 满 100% → 这枚印的 `base` 基础属性**永久生效**（不必显化）。
## ⭐ 炼化 = 印与命窍的**融合度**，是**使用前提**：未满 100% 的印完全不能用
##（不能显化、不给被动、不给基础属性）—— "武功得完全学会才能用"。
## 涨法：**点「炼化」按钮花灵力** —— 唯一一条路（M30.3 用户定案：**不再吃材料**，见 SealPanel.do_refine）。
## ⚠️ 旧版那条「显化一次涨一点」已删：新语义下"不能用还怎么用着变熟"是自相矛盾的。
const REFINE := {
	"max": 100.0,
	"press_cost": 10.0,     # 点一次「炼化」花多少灵力
	"press_gain": 8.0,      # 一次涨多少炼化度 → 0→100 约 13 次 = 130 灵力（≈1.3 管）
	"start_refined": 100.0, # 开局自带的那两枚直接给满（否则开局打不了架）
}

## ⭐ M30.4：这件东西占多少**容积**。不在材料表里的一律返回 0 ——
##    于是**灵石（货币）和灵印（收藏）天然不占地方**（用户明确要求：「灵印就不占体积没有重量」）。
static func volume_of(item: String) -> int:
	if item == CURRENCY:
		return 0
	return int((MATERIALS.get(item, {}) as Dictionary).get("volume", 0))


## ⭐ M30.5b：物品的**中文名 → 英文短名**（贴图文件名）。
##    为什么要这张表：中文名**不进文件名** —— 以后改文案 / 换语言时不该动到素材。
##    加一件材料 = 这里加一行 + 跑一次 `art/tools/gen_items.mjs`。
const ART_ID := {
	"蕴灵草": "herb",
	"赤炎花": "flower",
	"玄铁矿": "ironore",
	"雷纹石": "tstone",
	"兽骨": "bone",
	"灵魄": "wisp",
	"地火芯": "ember",
	"雷髓": "marrow",
	"玄霜髓": "frost",
	"太虚核": "voidcore",
	"灵石": "stone",
	## ---- 苍梧山材料线（M35）----
	"蛇胆": "gallsac",
	"灵木": "spiritwood",
	"幽魂精髓": "ghostess",
	"百年蛇胆": "gallold",
	"天雷木": "thunderwood",
	"百年竹心草": "bambooherb",
	"灵狐内丹": "foxcore",
	"凡印残片": "shard_common",
	"精印残片": "shard_fine",
	"通印残片": "shard_master",
}


## 面板 / 背包里的图标（32×32）。没有短名的返回 {} —— 调用方回退到形状语言。
## ⚠️ 返回的是**实体数据的形状**（`{"visual": {...}}`），不是裸的贴图字典 ——
##    因为 `ActorVisual.texture_of()/draw_unit()` 收的都是「实体数据」。
##    踩过：一开始返回 `{"texture": ...}`，结果 `texture_of()` 找不到 `visual` → 全都回退成菱形。
static func item_visual(item: String) -> Dictionary:
	var id := str(ART_ID.get(item, ""))
	if id == "":
		return {}
	return {"visual": {"texture": "res://art/items/%s.png" % id}}


## 地上的掉落物（8×8）。⭐ 灵印没有这张 —— 地上的印继续用形状语言画（见 Pickup.gd）。
static func item_drop_visual(item: String) -> Dictionary:
	var id := str(ART_ID.get(item, ""))
	if id == "":
		return {}
	return {"visual": {"texture": "res://art/items/%s_drop.png" % id}}


## 本命印：时印回溯时**永远保住**的那一枚（设计圣经 §4.2：第一世的灰烬印）。
## ⭐ 「其余灵印全部失去，只额外留一枚」是 §4.3 的锁定规则，不是保守设计。
const NATAL_SEAL := "灰烬印"

## 锚点：V0.1 只有一个固定锚点（出生点），不可覆盖（待决问题 3）。
## 死亡 → 恢复锚点快照（敌人复活 / 采集点复原）→ 主角回锚点。
## ⚠️ 多锚点与「主动设置锚点」不在 V0.1 范围。

## 灼烧最多叠几层（再多只刷新时长，不继续叠）。
const EMBER_MAX_STACK := 2
## 灵印血量低于这个比例 = 濒死（视觉忽明忽暗，纯表现，不影响数值）。
const SEAL_DYING_RATIO := 0.30


# ---------------- 敌人（M4）----------------
# ⭐ 和灵印表同一套思想：一条数据 = 一种敌人。加第三种只加一行，AI 一行都不用改。
#    seal_seek_chance 是「转向最近的显化灵印」的概率 —— 待决问题 2 的 V0.1 简化版：
#    猛兽型恒为 0（它只打主角），智谋型 30%。
## 灵师落雷的圈有多大。⭐ 预警圈画的就是它 —— 圈里才是会被打到的范围。
const CAST_RADIUS := 22.0

## 形状语言（M11）：每种原型一个**固定形状**。⭐ 怪物一多，「一眼分辨」就是功能需求，不是审美。
##   melee 圆 / hunter 方 / caster 菱 / charger 三角；精英一律再加一圈双外环 + 体型放大。
const SHAPES := {
	"melee": "circle",
	"hunter": "square",
	"caster": "diamond",
	"charger": "triangle",
	## ---- 苍梧山五种怪（数值设计 v2 §6）----
	## ⚠️ 「一眼分辨」在这里是**功能**不是审美：玩家必须能在半秒内看出
	##    「这只可以放着不管（竹鼠中立）/ 这只贴脸就死（竹叶青伏击）」。
	"burrow": "hexagon",
	"ambush": "snake",
	"disguise": "bamboo",
	"clone": "fox",
	"phase": "ghost",
}

## 精英规格。⭐ 精英不是新原型，是**同一个原型加档** ——
## 所以同一个 AI、同一个形状，只是更大更硬更疼，掉得也更多。
## ⚠️ M35：`stone` = 灵石（设计 §0 第二条锚点：**普通怪不掉灵石**，只有精英与首领掉）。
const ELITE := {
	"hp_mult": 3.0,
	"damage_mult": 1.5,
	"radius_mult": 1.35,
	"drop_mult": 3,
	"bonus_drop": "灵魄",     # 精英额外掉的高级辅材
	"stone": 6,               # 精英的灵石（设计 §5：5~8 这一档，固定 6 = 不做概率）
	"shard": "精印残片",       # 精英的残碎片种
	"shard_count": 2,
}

## 普通怪掉的残片（设计 §5：普通怪 → 凡印残片）。
## ⚠️ 设计原文写的是「60% 概率」，这里**改成必掉** —— 理由是工程既有的纪律：
##    「固定数量，不做随机掉率」（见 ENEMY_DROPS 抬头）。随机掉率会让自测变成概率游戏，
##    而残片本来就是「打了很久但一直没掉印」的保底进度条 —— 保底还要掷骰子就不叫保底了。
##    ⇒ 等有调参台了再按 §5 上权重。
const MOB_SHARD := {"shard": "凡印残片", "count": 1}

const ENEMY := {
	"猛兽": {
		"behavior": "melee",
		"hp_max": 70.0,
		"radius": 17.0,
		"color": Color(0.78, 0.35, 0.30),
		"visual": {"texture": "res://art/units/enemy_beast.png", "offset": Vector2(0.0, -14.0)},
		"speed": 46.0,             # 追击速度（像素/秒）
		"aggro_range": 130.0,      # 进这个距离才开始追
		"attack_range": 18.0,      # 进这个距离才能打
		"attack_damage": 9.0,
		"attack_cooldown": 1.10,   # 两次攻击的最小间隔（秒）
		"seal_seek_chance": 0.0,
	},
	## 灵师：会**显化灵印**的对手。远程、站桩施法、施法前有预警。
	## ⭐ 打死它 → 可以强夺它身上那枚印（代价：契合度归零 = 抢来的印没有被动）。
	"灵师": {
		"behavior": "caster",
		"hp_max": 70.0,
		"radius": 16.0,
		"color": Color(0.38, 0.80, 0.86),
		"visual": {"texture": "res://art/units/enemy_caster.png", "offset": Vector2(0.0, -14.0)},
		"speed": 48.0,
		"aggro_range": 170.0,     # 视野最远
		"attack_range": 110.0,    # 打得也最远
		"attack_damage": 11.0,
		"attack_cooldown": 2.20,
		"seal_seek_chance": 0.45, # 它懂印 —— 更爱打你显化的灵印
		"keep_distance": 82.5,   # 走到这么近就停下施法，不贴脸
		"cast_warn": 0.45,        # 施法预警：给玩家闪开的时间
	},
	## 蛮兽：冲锋型。先**蓄力预警**（方向性，不是圈），再高速撞过来。
	## ⭐ 它和灵师要玩家做的事正好相反：灵师的圈要「走出去」，它的冲要「横着闪」。
	"蛮兽": {
		"behavior": "charger",
		"hp_max": 85.0,
		"radius": 18.0,
		"color": Color(0.86, 0.56, 0.24),
		"visual": {"texture": "res://art/units/enemy_charger.png", "offset": Vector2(0.0, -14.0)},
		"speed": 40.0,
		"aggro_range": 165.0,
		"attack_range": 15.0,
		"attack_damage": 16.0,
		"attack_cooldown": 1.80,
		"seal_seek_chance": 0.15,
		"charge_range": 150.0,   # 进这个距离就开始蓄力
		"charge_warn": 0.55,     # 蓄力多久（给玩家闪开的时间）
		"charge_speed": 270.0,   # 冲刺速度
		"charge_time": 0.34,     # 冲刺持续多久
	},
	"智谋": {
		"behavior": "hunter",
		"hp_max": 55.0,
		"radius": 16.0,
		"color": Color(0.55, 0.45, 0.80),
		"visual": {"texture": "res://art/units/enemy_hunter.png", "offset": Vector2(0.0, -14.0)},
		"speed": 38.0,
		"aggro_range": 150.0,
		"attack_range": 21.0,
		"attack_damage": 7.0,
		"attack_cooldown": 1.30,
		"seal_seek_chance": 0.30,  # 30% 概率改打显化中的灵印
	},
	# ==================== 苍梧山（数值设计 v2 §6）====================
	## ⭐ 五种怪的数值**完全照抄设计表**（hp / 攻击 / 特色 / 弱点 / 掉落）。
	##    新增的三个字段是这一版的核心：
	##      · `weakness` = {标签: 倍率} —— 打标签对得上就吃倍率。**这是「弱点」第一次真的存在**。
	##        旧的四种原型没有这一项（= 什么都不弱），所以旧战斗手感一点没变。
	##      · `drops`    = 这只怪自己掉什么（覆盖 ENEMY_DROPS）。
	##      · `self_elite` = **它本来就是精英**（不是「杂怪加档」）。
	##        ⇒ `ELITE.hp_mult ×3` **不套用在它身上**：设计给的 220 就是最终血量。
	##          踩过的坑：第一版让所有 elite 都 ×3，灵狐直接变 660 血，一个新手村首领都没它硬。
	"铁齿竹鼠": {
		"behavior": "burrow",
		"hp_max": 50.0,
		"radius": 14.0,
		"color": Color(0.72, 0.58, 0.38),
		"speed": 46.0,
		"aggro_range": 120.0,
		"attack_range": 20.0,
		"attack_damage": 6.0,
		"attack_cooldown": 1.20,
		"seal_seek_chance": 0.0,
		## 中立：不进仇恨圈就当你不在。踩到它的窝（`nest_range`）才会翻脸。
		"neutral": true,
		"nest_range": 90.0,
		## 冲锋：和蛮兽同一套「蓄力 → 锁方向 → 撞」，但距离更短、更快、更弱。
		"charge_range": 130.0,
		"charge_warn": 0.40,
		"charge_speed": 300.0,
		"charge_time": 0.26,
		## 流血：撞上之后挂一条持续伤害（比灼烧慢、但更久）
		"bleed": {"damage": 2.0, "tick": 0.5, "time": 4.0},
		"weakness": {"火": 2.0},
		"drops": {"兽骨": 2},
	},
	"鬼影竹叶青": {
		"behavior": "ambush",
		"hp_max": 40.0,
		"radius": 13.0,
		"color": Color(0.34, 0.56, 0.30),
		"speed": 58.0,
		"aggro_range": 92.0,
		"attack_range": 19.0,
		"attack_damage": 12.0,
		"attack_cooldown": 1.60,
		"seal_seek_chance": 0.0,
		## 伏击：平时缩在草丛里（半透明、不追人）；进 `ambush_range` 就扑一下，
		## 那一下**打完就退回去** —— 所以它是一道「你会不会被咬到」的反应题，不是一根木桩。
		"ambush_range": 105.0,
		"ambush_mult": 1.5,
		## 剧毒：一击附加持续伤害（design §6「12（剧毒）」）
		"poison": {"damage": 3.0, "tick": 0.6, "time": 5.0},
		"weakness": {"火": 1.5},
		"drops": {"蛇胆": 1},
	},
	"青木竹妖": {
		"behavior": "disguise",
		"hp_max": 90.0,
		"radius": 18.0,
		"color": Color(0.44, 0.66, 0.34),
		"speed": 32.0,
		"aggro_range": 150.0,
		"attack_range": 26.0,
		"attack_damage": 8.0,
		"attack_cooldown": 1.80,
		"seal_seek_chance": 0.15,
		## 伪装：站着不动时就是一根枯竹（画成竹子、不 bob、不显示血条）。
		## 进 `reveal_range` 才现形 —— 玩家第一次会被它吓一跳，第二次就会拿火去烧竹子。
		"disguise_reveal": 110.0,
		## 藤蔓控制：命中后把主角钉住一会儿（`root_time` 秒内不能移动）。
		"root_time": 0.7,
		"weakness": {"火": 1.5},
		"drops": {"灵木": 2},
	},
	## ⭐ 精英 1：碧眼灵狐 —— 分身 ×3（1 真 2 假）。**强光破**（辉光印 tag 光）。
	"碧眼灵狐": {
		"behavior": "clone",
		"self_elite": true,
		"hp_max": 220.0,
		"radius": 19.0,
		"color": Color(0.42, 0.78, 0.72),
		"speed": 62.0,
		"aggro_range": 180.0,
		"attack_range": 24.0,
		"attack_damage": 10.0,
		"attack_cooldown": 1.40,
		"seal_seek_chance": 0.20,
		## 分身：本体 + 2 个幻影。幻影不痛、但会骗走你的普攻和灵印锁定。
		## ⭐ 强光破的**机制**就在这里：辉光印（tag 光）一照，幻影直接散掉。
		"clone_count": 2,
		"clone_hp_ratio": 0.01,     # 幻影一碰就碎（1% 血）
		"clone_damage_ratio": 0.0,  # 幻影打人不掉血 —— 它只是骗你，不是第二个 boss
		"weakness": {"光": 1.5, "雷": 1.2},
		"drops": {"灵魄": 2},
		"stone": 5,
	},
	## ⭐ 精英 2：变异矿鬼 —— 半透明穿墙、打你时吸灵力。**强光**。
	"变异矿鬼": {
		"behavior": "phase",
		"self_elite": true,
		"hp_max": 150.0,
		"radius": 16.0,
		"color": Color(0.46, 0.54, 0.62),
		"speed": 54.0,
		"aggro_range": 190.0,
		"attack_range": 22.0,
		"attack_damage": 10.0,
		"attack_cooldown": 1.50,
		"seal_seek_chance": 0.25,
		## 穿墙：`can_step` 对它恒为真 ⇒ 它会从石头里直接穿过来。这是它的身份，不是 bug。
		"phase": true,
		## 吸灵力：每次命中额外抽走主角 `essence_drain` 点灵力。
		"essence_drain": 6.0,
		## 灵体：一半时间半透明（`ghost_period` 秒一轮），视觉上"你打不实"。
		"ghost_period": 2.4,
		"weakness": {"光": 1.5},
		"drops": {"幽魂精髓": 1},
		"stone": 6,
	},
}

## 敌人出生点。⭐ 刻意放得离假人很远 ——
## 不然 M1 那条「伤害区命中 1 个目标」会因为顺手打到敌人而变红。
## ⭐ 出生点是世界正中 (1792, 1536)。最近的敌人是南北路口的 (1792,384) / (1792,2773.3)，
##    离出生点 1152 / 1237 px —— 都在仇恨圈（130 / 170 / 165，见 ENEMIES）**外面**，
##    所以走几步才会被发现，不会一开局就被围。假人离出生点约 352 px（M1 的验收基线）。
## ⚠️ M31 Step 0：以下坐标**就是世界像素真坐标**（单位 = 世界像素，世界 3584×3072）。
##    以前这里写的是「1280×720 设计空间」的坐标、运行时再乘 wscl —— 那套双重坐标系已删除。
##    ⚠️ 注意纵横比变了（16:9 → 7:6），所以各点之间的**距离不是等比缩放**，
##    但每个点落在世界里的**相对位置**（占世界的百分比）与改动前一致。
## ⭐⭐ M31 Step 0：`id` = **稳定标识**（e01…e13）。它是为「存档从数组下标改成稀疏 id 集合」铺路 ——
##    将来增删 / 重排刷新点，存档里已打死的敌人不会串位。**本轮只加字段，不动存档结构**。
const ENEMY_SPAWNS := [
	## ---- 杂怪 62 只（m01…m62）：**只给压力，不给印** ----
	##    - 原型只有 猛兽 / 智谋 / 蛮兽 三种；**灵师不进杂怪表**（灵师带印，见下面 5 条）。
	##    - ⚠️ 顺序有讲究：`enemies[0]` 必须是**猛兽**、`enemies[1]` 必须是**智谋**
	##      （`Game.gd` 有多处 `var foe = enemies[0]  # 猛兽` / `var brain = enemies[1]  # 智谋`）。
	##      ⇒ 别把 m01 / m02 的原型改掉，也别把带印的那 5 条挪到数组前面。
	##    - `ring` 是**实测**（`ring_at()` 算的），不是抄的。
	##    - ⚠️ m50…m62 这 13 只是**为「每个采集点 240px 内有怪」补出来的**（见 GATHER 注释）。
	##      m53 在 y=2064，主城矩形南边界 2048 —— 只差 16px，是唯一贴边的一只。
	{"id": "m01", "archetype": "猛兽", "pos": Vector2(1040.0, 1776.0), "ring": 1},
	{"id": "m02", "archetype": "智谋", "pos": Vector2(880.0, 2160.0),  "ring": 1},
	{"id": "m03", "archetype": "猛兽", "pos": Vector2(2480.0, 2256.0), "ring": 1},
	{"id": "m04", "archetype": "智谋", "pos": Vector2(2640.0, 1552.0), "ring": 1},
	{"id": "m05", "archetype": "猛兽", "pos": Vector2(1008.0, 1968.0), "ring": 1},
	{"id": "m06", "archetype": "智谋", "pos": Vector2(1488.0, 784.0),  "ring": 1},
	{"id": "m07", "archetype": "猛兽", "pos": Vector2(1968.0, 2288.0), "ring": 1},
	{"id": "m08", "archetype": "猛兽", "pos": Vector2(624.0, 2224.0),  "ring": 2},
	{"id": "m09", "archetype": "智谋", "pos": Vector2(1328.0, 2480.0), "ring": 2},
	{"id": "m10", "archetype": "蛮兽", "pos": Vector2(880.0, 2608.0),  "ring": 2},
	{"id": "m11", "archetype": "猛兽", "pos": Vector2(2352.0, 2384.0), "ring": 2},
	{"id": "m12", "archetype": "智谋", "pos": Vector2(1360.0, 624.0),  "ring": 2},
	{"id": "m13", "archetype": "蛮兽", "pos": Vector2(880.0, 2384.0),  "ring": 2},
	{"id": "m14", "archetype": "猛兽", "pos": Vector2(2704.0, 560.0),  "ring": 2},
	{"id": "m15", "archetype": "智谋", "pos": Vector2(2800.0, 2416.0), "ring": 2},
	{"id": "m16", "archetype": "蛮兽", "pos": Vector2(2528.0, 712.0),  "ring": 2},
	{"id": "m17", "archetype": "猛兽", "pos": Vector2(2992.0, 2480.0), "ring": 2},
	{"id": "m18", "archetype": "智谋", "pos": Vector2(816.0, 1136.0),  "ring": 2},
	{"id": "m19", "archetype": "蛮兽", "pos": Vector2(688.0, 2768.0),  "ring": 3},
	{"id": "m20", "archetype": "智谋", "pos": Vector2(2608.0, 400.0),  "ring": 3},
	{"id": "m21", "archetype": "猛兽", "pos": Vector2(304.0, 784.0),   "ring": 3},
	{"id": "m22", "archetype": "蛮兽", "pos": Vector2(1616.0, 368.0),  "ring": 3},
	{"id": "m23", "archetype": "智谋", "pos": Vector2(2448.0, 2832.0), "ring": 3},
	{"id": "m24", "archetype": "猛兽", "pos": Vector2(912.0, 2832.0),  "ring": 3},
	{"id": "m25", "archetype": "蛮兽", "pos": Vector2(3280.0, 368.0),  "ring": 3},
	{"id": "m26", "archetype": "智谋", "pos": Vector2(1968.0, 2800.0), "ring": 3},
	{"id": "m27", "archetype": "猛兽", "pos": Vector2(368.0, 368.0),   "ring": 3},
	{"id": "m28", "archetype": "蛮兽", "pos": Vector2(496.0, 752.0),   "ring": 3},
	{"id": "m29", "archetype": "智谋", "pos": Vector2(368.0, 1136.0),  "ring": 3},
	{"id": "m30", "archetype": "猛兽", "pos": Vector2(3152.0, 2256.0), "ring": 3},
	{"id": "m31", "archetype": "蛮兽", "pos": Vector2(1552.0, 2768.0), "ring": 3},
	{"id": "m32", "archetype": "智谋", "pos": Vector2(3120.0, 2832.0), "ring": 3},
	{"id": "m33", "archetype": "蛮兽", "pos": Vector2(112.0, 2384.0),  "ring": 4},
	{"id": "m34", "archetype": "蛮兽", "pos": Vector2(1616.0, 112.0),  "ring": 4},
	{"id": "m35", "archetype": "智谋", "pos": Vector2(1072.0, 144.0),  "ring": 4},
	{"id": "m36", "archetype": "蛮兽", "pos": Vector2(240.0, 2736.0),  "ring": 4},
	{"id": "m37", "archetype": "蛮兽", "pos": Vector2(1136.0, 2896.0), "ring": 4},
	{"id": "m38", "archetype": "智谋", "pos": Vector2(2096.0, 2960.0), "ring": 4},
	{"id": "m39", "archetype": "蛮兽", "pos": Vector2(176.0, 912.0),   "ring": 4},
	{"id": "m40", "archetype": "蛮兽", "pos": Vector2(2352.0, 144.0),  "ring": 4},
	{"id": "m41", "archetype": "智谋", "pos": Vector2(2672.0, 176.0),  "ring": 4},
	{"id": "m42", "archetype": "蛮兽", "pos": Vector2(3472.0, 2512.0), "ring": 4},
	{"id": "m43", "archetype": "蛮兽", "pos": Vector2(208.0, 1328.0),  "ring": 4},
	{"id": "m44", "archetype": "智谋", "pos": Vector2(240.0, 2256.0),  "ring": 4},
	{"id": "m45", "archetype": "蛮兽", "pos": Vector2(3376.0, 1360.0), "ring": 4},
	{"id": "m46", "archetype": "蛮兽", "pos": Vector2(3376.0, 2352.0), "ring": 4},
	{"id": "m47", "archetype": "智谋", "pos": Vector2(176.0, 1648.0),  "ring": 4},
	{"id": "m48", "archetype": "蛮兽", "pos": Vector2(2864.0, 2928.0), "ring": 4},
	{"id": "m49", "archetype": "蛮兽", "pos": Vector2(400.0, 2960.0),  "ring": 4},
	{"id": "m50", "archetype": "猛兽", "pos": Vector2(2552.0, 976.0),  "ring": 1},
	{"id": "m51", "archetype": "智谋", "pos": Vector2(2540.0, 2083.0), "ring": 1},
	{"id": "m52", "archetype": "猛兽", "pos": Vector2(980.0, 1012.0),  "ring": 1},
	{"id": "m53", "archetype": "智谋", "pos": Vector2(1624.0, 2064.0), "ring": 1},
	{"id": "m54", "archetype": "猛兽", "pos": Vector2(2392.0, 592.0),  "ring": 2},
	{"id": "m55", "archetype": "智谋", "pos": Vector2(820.0, 1964.0),  "ring": 2},
	{"id": "m56", "archetype": "蛮兽", "pos": Vector2(2808.0, 2608.0), "ring": 2},
	{"id": "m57", "archetype": "智谋", "pos": Vector2(981.0, 307.0),   "ring": 3},
	{"id": "m58", "archetype": "蛮兽", "pos": Vector2(1899.0, 211.0),  "ring": 4},
	{"id": "m59", "archetype": "蛮兽", "pos": Vector2(696.0, 112.0),   "ring": 4},
	{"id": "m60", "archetype": "智谋", "pos": Vector2(3341.0, 1579.0), "ring": 4},
	{"id": "m61", "archetype": "蛮兽", "pos": Vector2(3508.0, 989.0),  "ring": 4},
	{"id": "m62", "archetype": "蛮兽", "pos": Vector2(312.0, 112.0),   "ring": 4},

	## ---- ⭐⭐ 传承印出处 5 条（**唯一出处，不许删**）----
	##    这 5 只身上各带一枚印，打死才有强夺的机会 —— 删掉任何一条，那枚印就**永远拿不到**。
	##    ⚠️ M31.4 表重建时它们是**整体迁移**过来的（`carries` / `elite` 原样保留），
	##    另外 8 条旧记录（e01…e06 / e10 / e11）已作废删除。
	##    ⚠️ e02 原在 (2940,640) —— 实测那一格 **B=255 是深水**，Dijkstra 走不到，
	##       敌人刷在水里玩家永远打不到。它不带印，随整表作废一起删除（不单独挪）。
	# ⭐ 三名灵师各带一枚印。
	{"id": "e07", "archetype": "灵师", "pos": Vector2(868.0, 640.0),    "ring": 2, "carries": "流风印"},
	## ⚠️ 坐标更正（M31.4 架构侧复核）：(3052,896) → **(1776,688)**。
	##    原坐标落在格 (95,28)，**B=255 深水**，Dijkstra 走不到 ⇒ 而辉光印将来要升 rank 3，
	##    一枚走不到的印 + 一个高品阶 = 玩家永远拿不到。新点 L2，实测可达。
	{"id": "e08", "archetype": "灵师", "pos": Vector2(1776.0, 688.0),   "ring": 2, "carries": "辉光印"},
	{"id": "e09", "archetype": "灵师", "pos": Vector2(2772.0, 2261.3),  "ring": 2, "carries": "云雨印"},
	## ⚠️ 坐标更正（M31.4 架构侧复核）：(3184,1232) → **(3120,1072)**。
	##    ⭐⭐ 实测层归属是 **L3 不是 L4**（ρ = 1328/1792 = **0.7411**，落在 0.71~0.86 之间）。
	##    ⚠️ 我第一版把它标成 L4 是**错的**：验算脚本里那 5 条还是**旧坐标**（e12 旧 = (3388,362.7)，
	##       ρ=0.8906 才是 L4）。⇒ 新坐标按实测改标 **L3**，别照抄我上一版报告里的 L4。
	##    ⚠️ 连带后果：原来的设计意图是「精英摆在**离锚点最远的两个角落**（越远越硬）」，
	##       更正后的两只都在 L3，这条梯度**被削弱了**。要不要把它们挪回 L4 由 team-lead 定 ——
	##       我没有擅自再挪坐标（那是架构侧复核过的数）。
	##    实测：格 (97,33) R=50 G=89 **B=0**（草地，非深水、干地），可达。
	{"id": "e12", "archetype": "智谋", "pos": Vector2(3120.0, 1072.0),  "ring": 3, "carries": "惊雷印", "elite": true},
	## ⚠️ 坐标更正（M31.4 架构侧复核）：(1360,2800) → **(400,2704)**。
	##    ⭐⭐ 同样实测为 **L3**（ρ = max(1392/1792, 1168/1536) = max(0.7768, 0.7604) = **0.7768**）。
	##    实测：格 (12,84) R=150 G=166 **B=0**（灵岩，非深水、干地），可达。
	{"id": "e13", "archetype": "蛮兽", "pos": Vector2(400.0, 2704.0),   "ring": 3, "carries": "磐石印", "elite": true},

	## ---- ⭐⭐ M35：苍梧山五种怪（n01…n12，数值设计 v2 §6）----
	##    ⚠️ **必须追加在数组末尾**：`enemies[0]` / `enemies[1]` 被 `Game.gd` 多处按
	##       下标取（猛兽 / 智谋），挪位置就会串味。
	##    ⚠️ 坐标是 `tests/probe_spawns.gd` **搜出来的**，不是拍脑袋写的。那个脚本按
	##       `world_data_test.gd` 第 6/7 段的同一套条件筛：非深水 / 不在主城 / 离商人
	##       与出生点 ≥400px / 离已有怪 ≥200px / 彼此 ≥220px，再用最远点采样铺开。
	##       ⇒ 要加新怪，改那个脚本重跑，别手写坐标。
	##    `terrain` 只是**记录**（供人读），判定读的是烘出来的 worldmap。
	## ---- 铁齿竹鼠（中立 → 踩窝才翻脸 → 冲锋 + 流血）----
	{"id": "n01", "archetype": "铁齿竹鼠", "pos": Vector2(2128.0, 1008.0), "ring": 1},
	{"id": "n02", "archetype": "铁齿竹鼠", "pos": Vector2(2320.0, 1712.0), "ring": 1},
	{"id": "n03", "archetype": "铁齿竹鼠", "pos": Vector2(2832.0, 1840.0), "ring": 2},
	{"id": "n04", "archetype": "铁齿竹鼠", "pos": Vector2(432.0, 1872.0),  "ring": 3},
	## ---- 鬼影竹叶青（草丛伏击，一击带剧毒）----
	{"id": "n05", "archetype": "鬼影竹叶青", "pos": Vector2(1264.0, 1328.0), "ring": 1},
	{"id": "n06", "archetype": "鬼影竹叶青", "pos": Vector2(592.0, 1424.0),  "ring": 2},
	{"id": "n07", "archetype": "鬼影竹叶青", "pos": Vector2(2800.0, 1200.0), "ring": 2},
	## ---- 青木竹妖（伪装枯竹，现形后用藤蔓钉住你）----
	{"id": "n08", "archetype": "青木竹妖", "pos": Vector2(2064.0, 560.0),  "ring": 2},
	{"id": "n09", "archetype": "青木竹妖", "pos": Vector2(144.0, 1968.0),  "ring": 4},
	{"id": "n10", "archetype": "青木竹妖", "pos": Vector2(656.0, 432.0),   "ring": 3},
	## ---- ⭐ 两只**自成一档**的精英（`self_elite`：血量就是设计值，不再 ×3）----
	{"id": "n11", "archetype": "碧眼灵狐", "pos": Vector2(2320.0, 1328.0), "ring": 1, "elite": true},
	{"id": "n12", "archetype": "变异矿鬼", "pos": Vector2(2992.0, 1520.0), "ring": 2, "elite": true},
]


## Godot 默认字体不含中日韩字形，这里直接向系统要一份中文字体。
##
## ⚠️⚠️ 性能红线（M29.6）：`SystemFont.new()` 实测要 **5152 µs**（它得去系统里解析 / 加载字体），
##    而 `Pickup._draw()` **每帧**都会问一次字体 —— 于是地面上每一个「数量 > 1」的掉落物
##    每帧白烧约 6 毫秒；地上堆满时实测从 238 FPS 掉到 **13 FPS**。
##    → 这里缓存一份，全项目共用同一个 Font 对象。字体是只读资源，共享完全安全。
##    ⚠️ 以后任何 `_draw()` / `_process()` 里都**不许** `new()` Resource（字体 / 贴图 / 材质 / Tween），
##       必须在 `_ready()` 里取一次存起来；自测里有一条源码扫描断言专门拦这个（见 _check_draw_hot_paths）。
static var _font_cache: Font = null

static func make_font() -> Font:
	if _font_cache != null:
		return _font_cache
	var f := SystemFont.new()
	f.font_names = PackedStringArray([
		"Microsoft YaHei UI", "Microsoft YaHei", "微软雅黑", "SimHei", "黑体",
		"Noto Sans CJK SC", "Source Han Sans SC", "PingFang SC",
		"WenQuanYi Micro Hei", "sans-serif",
	])
	f.allow_system_fallback = true
	_font_cache = f
	return _font_cache
